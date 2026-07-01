import Foundation

struct OpenRouterChatMessage {
    let role: String
    let content: String
}

struct OpenRouterCompletionResult {
    let text: String
    let modelID: String
}

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case noFreeModel
    case invalidResponse
    case invalidStructuredOutput
    case unauthorized(String)
    case paymentRequired(String)
    case rateLimited(String)
    case serviceUnavailable(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No OpenRouter API key is configured."
        case .noFreeModel:
            return "OpenRouter could not find a compatible free-tier model."
        case .invalidResponse:
            return "OpenRouter returned an unexpected response."
        case .invalidStructuredOutput:
            return "OpenRouter did not return valid structured JSON."
        case let .unauthorized(message):
            return message
        case let .paymentRequired(message):
            return message
        case let .rateLimited(message):
            return message
        case let .serviceUnavailable(message):
            return message
        case let .requestFailed(message):
            return message
        }
    }
}

final class OpenRouterAIService {
    static let shared = OpenRouterAIService()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    private let preferredFreeModels = [
        "google/gemma-4-26b-a4b-it:free",
        "google/gemma-4-31b-it:free",
        "nvidia/nemotron-nano-9b-v2:free"
    ]

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func streamChat(
        systemPrompt: String,
        messages: [OpenRouterChatMessage],
        apiKey: String,
        temperature: Double = 0.75,
        maxTokens: Int = AIUsageBudgetManager.openRouterChatOutputTokenLimit
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let candidateModels = Array(
                        try await resolveFreeModelCandidates(requireJSONMode: false)
                            .prefix(AIUsageBudgetManager.maxModelAttemptsPerRequest)
                    )
                    var lastTransientError: Error?
                    var sawProviderThrottle = false

                    modelLoop: for candidate in candidateModels {
                        try AIUsageBudgetManager.consumeOpenRouterAttempt()

                        var request = try makeRequest(
                            path: "chat/completions",
                            apiKey: apiKey,
                            body: OpenRouterChatRequest(
                                model: candidate.id,
                                messages: makeMessages(systemPrompt: systemPrompt, messages: messages),
                                stream: true,
                                temperature: temperature,
                                max_tokens: maxTokens,
                                response_format: nil
                            )
                        )
                        request.timeoutInterval = 120

                        let (bytes, response) = try await session.bytes(for: request)
                        try validate(response: response)

                        var streamedAnyText = false

                        do {
                            for try await line in bytes.lines {
                                if Task.isCancelled { throw CancellationError() }
                                if line.hasPrefix(":") { continue }

                                if line.hasPrefix("data: ") {
                                    let payload = String(line.dropFirst(6))
                                    if payload == "[DONE]" { break }
                                    guard let data = payload.data(using: .utf8) else { continue }

                                    let chunk = try decoder.decode(OpenRouterChatChunk.self, from: data)
                                    if let streamError = chunk.error?.message, !streamError.isEmpty {
                                        let mapped = self.mapBodyError(
                                            OpenRouterErrorResponse(
                                                error: .init(message: streamError, code: nil, metadata: nil)
                                            )
                                        )
                                        if !streamedAnyText, self.isRetriableModelError(mapped) {
                                            lastTransientError = mapped
                                            sawProviderThrottle = sawProviderThrottle || self.isProviderThrottleError(mapped)
                                            AIProviderManager.setCurrentOpenRouterModelID(nil)
                                            continue modelLoop
                                        }
                                        throw mapped
                                    }

                                    if let text = chunk.choices.first?.delta.text, !text.isEmpty {
                                        if !streamedAnyText {
                                            streamedAnyText = true
                                            AIProviderManager.setCurrentOpenRouterModelID(candidate.id)
                                        }
                                        continuation.yield(text)
                                    }
                                    continue
                                }

                                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard trimmed.first == "{",
                                      let data = trimmed.data(using: .utf8),
                                      let errorResponse = try? decoder.decode(OpenRouterErrorResponse.self, from: data) else {
                                    continue
                                }

                                let mapped = mapBodyError(errorResponse)
                                if !streamedAnyText, isRetriableModelError(mapped) {
                                    lastTransientError = mapped
                                    sawProviderThrottle = sawProviderThrottle || isProviderThrottleError(mapped)
                                    AIProviderManager.setCurrentOpenRouterModelID(nil)
                                    continue modelLoop
                                }
                                throw mapped
                            }

                            AIProviderManager.setCurrentOpenRouterModelID(candidate.id)
                            continuation.finish()
                            return
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if !streamedAnyText, isRetriableModelError(error) {
                                lastTransientError = error
                                sawProviderThrottle = sawProviderThrottle || isProviderThrottleError(error)
                                AIProviderManager.setCurrentOpenRouterModelID(nil)
                                continue
                            }
                            throw error
                        }
                    }

                    if let lastTransientError {
                        if sawProviderThrottle {
                            AIUsageBudgetManager.registerOpenRouterThrottle()
                        }
                        throw lastTransientError
                    }
                    continuation.finish(throwing: OpenRouterError.noFreeModel)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func completeStructuredJSON(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String,
        temperature: Double = 0.35,
        maxTokens: Int = 2600
    ) async throws -> OpenRouterCompletionResult {
        let candidateModels = Array(
            try await resolveFreeModelCandidates(requireJSONMode: true)
                .prefix(AIUsageBudgetManager.maxModelAttemptsPerRequest)
        )
        var lastTransientError: Error?
        var sawProviderThrottle = false

        for candidate in candidateModels {
            try AIUsageBudgetManager.consumeOpenRouterAttempt()

            let request = try makeRequest(
                path: "chat/completions",
                apiKey: apiKey,
                body: OpenRouterChatRequest(
                    model: candidate.id,
                    messages: makeMessages(
                        systemPrompt: systemPrompt,
                        messages: [OpenRouterChatMessage(role: "user", content: userPrompt)]
                    ),
                    stream: false,
                    temperature: temperature,
                    max_tokens: maxTokens,
                    response_format: candidate.supportsResponseFormat ? OpenRouterResponseFormat() : nil
                )
            )

            do {
                let (data, response) = try await session.data(for: request)
                try validate(response: response, data: data)
                try validateBody(data)

                let completion = try decoder.decode(OpenRouterChatResponse.self, from: data)
                guard let message = completion.choices.first?.message.text, !message.isEmpty else {
                    throw OpenRouterError.invalidResponse
                }

                guard let jsonObject = extractJSONObject(from: message) else {
                    throw OpenRouterError.invalidStructuredOutput
                }

                AIProviderManager.setCurrentOpenRouterModelID(candidate.id)
                return OpenRouterCompletionResult(text: jsonObject, modelID: candidate.id)
            } catch {
                if isRetriableStructuredModelError(error) {
                    lastTransientError = error
                    sawProviderThrottle = sawProviderThrottle || isProviderThrottleError(error)
                    AIProviderManager.setCurrentOpenRouterModelID(nil)
                    continue
                }
                throw error
            }
        }

        if let lastTransientError {
            if sawProviderThrottle {
                AIUsageBudgetManager.registerOpenRouterThrottle()
            }
            throw lastTransientError
        }
        throw OpenRouterError.noFreeModel
    }

    func resolveFreeModelID() async throws -> String {
        guard let first = try await resolveFreeModelCandidates(requireJSONMode: false).first else {
            throw OpenRouterError.noFreeModel
        }
        return first.id
    }

    private func resolveFreeModelCandidates(requireJSONMode: Bool) async throws -> [OpenRouterModelCandidate] {
        let cachedModelID = AIProviderManager.currentOpenRouterModelID()

        if let candidates = try? await fetchFreeModelCandidates(), !candidates.isEmpty {
            let ordered = orderedCandidates(
                from: candidates,
                cachedModelID: cachedModelID,
                requireJSONMode: requireJSONMode
            )

            if !ordered.isEmpty {
                return ordered
            }
        }

        var fallback = [OpenRouterModelCandidate]()
        if let cachedModelID, !cachedModelID.isEmpty {
            fallback.append(
                OpenRouterModelCandidate(
                    id: cachedModelID,
                    supportsResponseFormat: false
                )
            )
        }
        fallback.append(
            contentsOf: preferredFreeModels
                .filter { candidateID in
                    !fallback.contains(where: { $0.id == candidateID })
                }
                .map { OpenRouterModelCandidate(id: $0, supportsResponseFormat: false) }
        )
        if !fallback.isEmpty {
            return fallback
        }

        throw OpenRouterError.noFreeModel
    }

    private func fetchFreeModelCandidates() async throws -> [OpenRouterModelCandidate] {
        let request = URLRequest(url: baseURL.appendingPathComponent("models"))
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, allowErrorDecoding: false)

        let decoded = try decoder.decode(OpenRouterModelListResponse.self, from: data)
        let candidates = decoded.data.filter { model in
            guard model.id.hasSuffix(":free") else { return false }
            let supportsText = model.architecture?.output_modalities.contains("text") ?? true
            return supportsText
        }

        return candidates.map { model in
            OpenRouterModelCandidate(
                id: model.id,
                supportsResponseFormat: model.supported_parameters?.contains("response_format") ?? false
            )
        }
    }

    private func orderedCandidates(
        from candidates: [OpenRouterModelCandidate],
        cachedModelID: String?,
        requireJSONMode: Bool
    ) -> [OpenRouterModelCandidate] {
        let primary = requireJSONMode ? candidates.filter(\.supportsResponseFormat) : candidates
        let secondary = requireJSONMode ? candidates.filter { !$0.supportsResponseFormat } : []
        var ordered = prioritizedCandidates(from: primary, cachedModelID: cachedModelID)

        if requireJSONMode {
            let orderedIDs = Set(ordered.map(\.id))
            ordered.append(
                contentsOf: prioritizedCandidates(from: secondary, cachedModelID: cachedModelID)
                    .filter { !orderedIDs.contains($0.id) }
            )
        }

        return ordered
    }

    private func prioritizedCandidates(
        from candidates: [OpenRouterModelCandidate],
        cachedModelID: String?
    ) -> [OpenRouterModelCandidate] {
        var ordered: [OpenRouterModelCandidate] = []

        if let cachedModelID,
           let cached = candidates.first(where: { $0.id == cachedModelID }) {
            ordered.append(cached)
        }

        for modelID in preferredFreeModels {
            guard let candidate = candidates.first(where: { $0.id == modelID }),
                  !ordered.contains(where: { $0.id == candidate.id }) else {
                continue
            }
            ordered.append(candidate)
        }

        for candidate in candidates where !ordered.contains(where: { $0.id == candidate.id }) {
            ordered.append(candidate)
        }

        return ordered
    }

    private func makeRequest(path: String, apiKey: String, body: some Encodable) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.missingAPIKey
        }

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Pace & Plates", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/JustJ0rsh/Pace-Plates", forHTTPHeaderField: "HTTP-Referer")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func makeMessages(systemPrompt: String, messages: [OpenRouterChatMessage]) -> [OpenRouterRequestMessage] {
        var result = [OpenRouterRequestMessage(role: "system", content: systemPrompt)]
        result.append(contentsOf: messages.map { OpenRouterRequestMessage(role: $0.role, content: $0.content) })
        return result
    }

    private func validate(
        response: URLResponse,
        data: Data? = nil,
        allowErrorDecoding: Bool = true
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let decodedError: OpenRouterErrorResponse? = {
                guard allowErrorDecoding, let data else { return nil }
                return try? decoder.decode(OpenRouterErrorResponse.self, from: data)
            }()

            let message = decodedError?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)

            switch http.statusCode {
            case 401:
                throw OpenRouterError.unauthorized("OpenRouter rejected the API key: \(message)")
            case 402:
                throw OpenRouterError.paymentRequired("OpenRouter free models can fail when the account is rate-limited or has insufficient balance: \(message)")
            case 429:
                throw OpenRouterError.rateLimited("OpenRouter rate limit reached: \(message)")
            case 503:
                throw OpenRouterError.serviceUnavailable("OpenRouter has no available provider for the selected free model right now: \(message)")
            default:
                throw OpenRouterError.requestFailed("OpenRouter request failed (\(http.statusCode)): \(message)")
            }
        }
    }

    private func validateBody(_ data: Data) throws {
        if let errorResponse = try? decoder.decode(OpenRouterErrorResponse.self, from: data) {
            throw mapBodyError(errorResponse)
        }
    }

    private func mapBodyError(_ errorResponse: OpenRouterErrorResponse) -> OpenRouterError {
        let message = errorResponse.error.metadata?.raw ?? errorResponse.error.message

        switch errorResponse.error.code {
        case 401:
            return .unauthorized("OpenRouter rejected the API key: \(message)")
        case 402:
            return .paymentRequired("OpenRouter free models can fail when the account is rate-limited or has insufficient balance: \(message)")
        case 429:
            return .rateLimited("OpenRouter rate limit reached: \(message)")
        case 503:
            return .serviceUnavailable("OpenRouter has no available provider for the selected free model right now: \(message)")
        default:
            return .requestFailed("OpenRouter request failed: \(message)")
        }
    }

    private func isRetriableModelError(_ error: Error) -> Bool {
        switch error {
        case OpenRouterError.rateLimited, OpenRouterError.serviceUnavailable:
            return true
        case let OpenRouterError.requestFailed(message):
            let lower = message.lowercased()
            return lower.contains("json mode is not enabled")
                || lower.contains("response_format")
                || lower.contains("unsupported")
        default:
            return false
        }
    }

    private func isProviderThrottleError(_ error: Error) -> Bool {
        switch error {
        case OpenRouterError.rateLimited, OpenRouterError.serviceUnavailable:
            return true
        default:
            return false
        }
    }

    private func isRetriableStructuredModelError(_ error: Error) -> Bool {
        if isRetriableModelError(error) {
            return true
        }

        switch error {
        case OpenRouterError.invalidResponse, OpenRouterError.invalidStructuredOutput:
            return true
        default:
            return false
        }
    }

    private func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        if let fencedRange = trimmed.range(of: "```json") ?? trimmed.range(of: "```"),
           let closingRange = trimmed.range(of: "```", range: fencedRange.upperBound..<trimmed.endIndex) {
            let fencedContent = trimmed[fencedRange.upperBound..<closingRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fencedContent.first == "{", fencedContent.last == "}" {
                return String(fencedContent)
            }
        }

        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[start...end])
    }
}

private struct OpenRouterModelCandidate {
    let id: String
    let supportsResponseFormat: Bool
}

private struct OpenRouterChatRequest: Encodable {
    let model: String
    let messages: [OpenRouterRequestMessage]
    let stream: Bool
    let temperature: Double
    let max_tokens: Int
    let response_format: OpenRouterResponseFormat?
}

private struct OpenRouterRequestMessage: Encodable {
    let role: String
    let content: String
}

private struct OpenRouterResponseFormat: Encodable {
    let type: String = "json_object"
}

private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        let message: OpenRouterMessage
    }

    let choices: [Choice]
}

private struct OpenRouterChatChunk: Decodable {
    struct Choice: Decodable {
        let delta: OpenRouterMessageDelta
    }

    struct StreamError: Decodable {
        let message: String
    }

    let choices: [Choice]
    let error: StreamError?
}

private struct OpenRouterMessage: Decodable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let string = try? container.decode(String.self, forKey: .content) {
            text = string
            return
        }

        if let parts = try? container.decode([OpenRouterContentPart].self, forKey: .content) {
            let joined = parts.compactMap(\.text).joined()
            text = joined.isEmpty ? nil : joined
            return
        }

        text = nil
    }
}

private struct OpenRouterMessageDelta: Decodable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let string = try? container.decode(String.self, forKey: .content) {
            text = string
            return
        }

        if let parts = try? container.decode([OpenRouterContentPart].self, forKey: .content) {
            let joined = parts.compactMap(\.text).joined()
            text = joined.isEmpty ? nil : joined
            return
        }

        text = nil
    }
}

private struct OpenRouterContentPart: Decodable {
    let text: String?
}

private struct OpenRouterErrorResponse: Decodable {
    struct OpenRouterAPIError: Decodable {
        let message: String
        let code: Int?
        let metadata: Metadata?
    }

    struct Metadata: Decodable {
        let raw: String?
    }

    let error: OpenRouterAPIError
}

private struct OpenRouterModelListResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable {
    struct Architecture: Decodable {
        let output_modalities: [String]
    }

    let id: String
    let supported_parameters: [String]?
    let architecture: Architecture?
}
