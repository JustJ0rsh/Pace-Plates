import Foundation
import SwiftData
#if canImport(AppleIntelligence)
import AppleIntelligence
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Request Model
struct WorkoutPlanRequest {
    let goal: String                // "lose" | "maintain" | "gain"
    let extraContext: String        // free-form user input
    let weightUnit: String          // "lbs" | "kg"
    let distanceUnit: String        // "mi" | "km"
    let modelContext: ModelContext  // to pull recent user data
    var mode: WorkoutPlanGenerator.Mode = .plan          // .plan => generate plan; .ask => answer Q&A
}

// NOTE: To enable on‑device Apple Intelligence / Foundation Models path, define the build setting
// `AI_FOUNDATION_AVAILABLE` for your target (Other Swift Flags -> -DAI_FOUNDATION_AVAILABLE)
// and link the appropriate SDKs when available. The code compiles safely without them.

final class WorkoutPlanGenerator {
    enum Mode { case plan, ask }
    enum Availability { case available, unavailable, unknown }

    static let shared = WorkoutPlanGenerator()
    private init() {}

    // Defensive limit to avoid exceeding model context window.
    // Keep prompts comfortably below typical on‑device limits.
    private static let maxPromptChars: Int = 3500

    private static func clampPrompt(_ text: String, max: Int = maxPromptChars) -> String {
        if text.count <= max { return text }
        return String(text.prefix(max))
    }

    #if canImport(FoundationModels)
    // Reused sessions to prewarm once and reduce latency
    private var basicSession: LanguageModelSession? = nil
    private var toolEnabledSession: LanguageModelSession? = nil
    #endif
    
    // Static variable to track last context summary for conversation continuity
    static var lastConversationSummary: String? = nil

    // Last structured plan JSON emitted during generation (if any). Used for persistence/preview.
    static var lastStructuredPlanJSON: String? = nil

    // Availability check: iOS 26+ devices with Apple Intelligence can run on‑device.
    // We conservatively return .unavailable unless the build defines AI_FOUNDATION_AVAILABLE.
    func availability() -> Availability {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            // Use the real Apple Intelligence API to check availability
            let model = SystemLanguageModel.default
            
            switch model.availability {
            case .available:
                // Apple Intelligence is available and enabled
                return .available
            case .unavailable(.deviceNotEligible):
                // Device doesn't support Apple Intelligence
                return .unavailable
            case .unavailable(.appleIntelligenceNotEnabled):
                // Apple Intelligence is supported but not enabled in Settings
                return .unavailable
            case .unavailable(.modelNotReady):
                // Model is downloading or not ready yet
                return .unavailable
            case .unavailable:
                // Any other unavailable reason
                return .unavailable
            @unknown default:
                return .unavailable
            }
            #else
            // Build flag is set but FoundationModels couldn't be imported
            return .unavailable
            #endif
        } else {
            // iOS version too old (< iOS 26)
            return .unavailable
        }
        #else
        // Build flag not set - device doesn't support it or build config excludes it
        return .unavailable
        #endif
    }

    // Prewarm on AI tab open to reduce first-token latency
    @MainActor
    func prewarmIfPossible() async {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            if basicSession == nil {
                basicSession = LanguageModelSession(
                    instructions: "You are a friendly, creative fitness and nutrition coach. Provide practical guidance with a bit of variety and fresh ideas."
                )
                basicSession?.prewarm()
            }
            #endif
        }
        #endif
    }

    // Prewarm tool-enabled session when web search is enabled
    func prewarmToolSessionIfNeeded() async {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            await MainActor.run {
                if toolEnabledSession == nil {
                    let tools: [any Tool] = [WebSearchTool()]
                    toolEnabledSession = LanguageModelSession(
                        tools: tools,
                        instructions: "You are a friendly, creative fitness and nutrition coach. Use webSearch when a claim needs verification or current facts, and cite sources concisely. Keep responses helpful and varied."
                    )
                    toolEnabledSession?.prewarm()
                }
            }
            #endif
        }
        #endif
    }
    
    /// Reset/offload the model sessions to clear context and free memory
    @MainActor
    func resetModelContext() {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            print("🔄 Resetting model context...")
            basicSession = nil
            toolEnabledSession = nil
            Self.lastConversationSummary = nil
            print("✅ Model context reset complete")
            #endif
        }
        #endif
    }
    
    /// Summarize a conversation for continuity when context resets
    static func summarizeConversation(_ messages: [(String, String)]) async -> String? {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            // Take last 6-8 messages for summary
            let recentMessages = messages.suffix(8)
            guard !recentMessages.isEmpty else { return nil }
            
            // Build a concise summary prompt
            var summaryText = "Previous conversation summary:\n"
            for (role, text) in recentMessages {
                let preview = String(text.prefix(150))
                summaryText += "\(role): \(preview)...\n"
            }
            
            return summaryText
            #endif
        }
        #endif
        return nil
    }

    // Streams the generated plan. Uses on‑device model when available, else template fallback.
    func generatePlanStream(request: WorkoutPlanRequest) -> AsyncThrowingStream<String, Error> {
        let availability = availability()
        switch availability {
        case .available:
            return generatePlanStreamOnDevice(request: request)
        case .unavailable, .unknown:
            return generatePlanStreamFromTemplate(request: request)
        }
    }

    // Streaming for Ask mode with concise conversation context (no repetition)
    func generateAskStream(request: WorkoutPlanRequest, history: [(String, String)]) -> AsyncThrowingStream<String, Error> {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            // Build a small, non-repeating context from recent assistant messages
            // Keep this short to avoid exceeding model context window
            let contextLines: [String] = Self.compactAssistantContext(history: history, maxChars: 400)
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        // Choose session type based on whether web search is enabled and relevant
                        let useToolSession = shouldUseWebSearch(for: request.extraContext)

                        // Prefer prewarmed, reusable sessions to avoid asset reload overhead
                        let session: LanguageModelSession = await MainActor.run {
                            if useToolSession {
                                if self.toolEnabledSession == nil { Task { await self.prewarmToolSessionIfNeeded() } }
                                return self.toolEnabledSession ?? self.basicSession ?? LanguageModelSession(
                                    instructions: "You are a concise fitness/nutrition coach. Keep answers short, safe, and practical."
                                )
                            } else {
                                if self.basicSession == nil { Task { await self.prewarmIfPossible() } }
                                return self.basicSession ?? LanguageModelSession(
                                    instructions: "You are a concise fitness/nutrition coach. Keep answers short, safe, and practical."
                                )
                            }
                        }

                        let userStats: UserStats = await Self.collectRecentStats(context: request.modelContext, 
                                                                                  weightUnit: request.weightUnit, 
                                                                                  distanceUnit: request.distanceUnit)

                        // Build concise prompt using centralized builder
                        let prompt = AIPromptBuilder.buildConversationPrompt(
                            goal: request.goal,
                            question: request.extraContext,
                            weightUnit: request.weightUnit,
                            distanceUnit: request.distanceUnit,
                            userStats: userStats,
                            recentContext: contextLines,
                            includeWebSearchGuidance: useToolSession
                        )

                        // Clamp prompt size defensively to avoid context window overflow
                        let safePrompt = Self.clampPrompt(prompt)

                        // Pre-process query: Force tool usage for certain patterns BEFORE sending to model (CONVERSATION MODE)
                        if shouldUseWebSearch(for: request.extraContext) && useToolSession {
                            print("🎯 CONVERSATION PRE-PROCESSING: Force-enabling web search for factual query: \(request.extraContext)")

                            // For certain high-confidence factual queries, call web search directly
                            let lowerQuery = request.extraContext.lowercased()
                            let directCallKeywords = ["what is", "define", "benefits", "research", "study", "evidence", "side effects", " RDA "]

                            if directCallKeywords.contains(where: { lowerQuery.contains($0) }) {
                                print("🚨 CONVERSATION DIRECT TOOL CALL: High-confidence factual query detected, calling web search immediately...")
                                do {
                                    let webResults = try await WebSearchService.shared.search(query: request.extraContext, maxResults: 4)
                                    let context = WebSearchService.formattedContext(for: webResults, includeCitations: true)

                                    // Stream the verified information
                                    continuation.yield("\n\n=== VERIFIED INFORMATION ===\n\(context)\n=== END VERIFIED INFORMATION ===\n\n")
                                    continuation.yield("Based on the above research, here's my analysis:")

                                    // Then let the model continue with the verified context
                                    let enhancedPrompt = "\(safePrompt)\n\nVERIFIED CONTEXT FROM WEB SEARCH:\n\(context)\n\nNow provide your analysis based on this verified information:"
                                    let response = try await session.respond(to: Self.clampPrompt(enhancedPrompt))
                                    print("✅ Conversation enhanced response generated with verified context")

                                    // Extract text from Foundation Models response
                                    let responseText: String
                                    let mirror = Mirror(reflecting: response)

                                    // Try to find text content in the response
                                    if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
                                        responseText = textValue
                                    } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
                                        responseText = contentValue
                                    } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
                                        responseText = valueValue
                                    } else {
                                        responseText = String(describing: response)
                                    }

                                    // Stream the enhanced response (larger chunks, smaller delay)
                                    var currentIndex = responseText.startIndex
                                    while currentIndex < responseText.endIndex {
                                        let chunkSize = min(120, responseText.distance(from: currentIndex, to: responseText.endIndex))
                                        let endIndex = responseText.index(currentIndex, offsetBy: chunkSize)
                                        let chunk = String(responseText[currentIndex..<endIndex])
                                        continuation.yield(chunk)
                                        currentIndex = endIndex
                                        try? await Task.sleep(nanoseconds: 2_000_000)
                                    }

                        continuation.finish()
                                    return
                    } catch {
                                    print("❌ Direct tool call failed: \(error.localizedDescription)")
                                    continuation.yield("[Direct web search failed. Continuing with standard response.]")
                                }
                            }
                        }
                        // Use proper Foundation Models API for conversation mode
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                print("🎯 Conversation: Attempting Foundation Models respond() API for prompt: \(prompt.prefix(100))...")

                                // Use respond() instead of streamResponse() - this handles tool calling automatically
                                let response = try await session.respond(to: safePrompt)
                                print("✅ Conversation Foundation Models respond() completed")

                                // Convert response to string for processing
                                let responseText: String
                                let mirror = Mirror(reflecting: response)

                                // Try to find text content in the response
                                if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
                                    responseText = textValue
                                } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
                                    responseText = contentValue
                                } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
                                    responseText = valueValue
                                } else {
                                    responseText = String(describing: response)
                                }

                                // Check if response contains tool call indicators
                                if responseText.contains("webSearch") || responseText.contains("tool") {
                                    print("🔍 Conversation tool usage detected in response!")
                                }

                                // Stream the response as chunks for UI compatibility
                                var currentIndex = responseText.startIndex
                                while currentIndex < responseText.endIndex {
                                    let chunkSize = min(160, responseText.distance(from: currentIndex, to: responseText.endIndex))
                                    let endIndex = responseText.index(currentIndex, offsetBy: chunkSize)
                                    let chunk = String(responseText[currentIndex..<endIndex])
                                    continuation.yield(chunk)
                                    currentIndex = endIndex
                                    try? await Task.sleep(nanoseconds: 2_000_000)
                                }

                                continuation.finish()
                                return
                            } catch {
                                print("❌ Conversation Foundation Models respond() failed: \(error.localizedDescription)")

                                // Fallback: Force web search for critical queries
                                if shouldUseWebSearch(for: request.extraContext) {
                                    print("🚨 Forcing fallback web search for conversation due to API failure...")
                                    do {
                                        let webResults = try await WebSearchService.shared.search(query: request.extraContext, maxResults: 3)
                                        let context = WebSearchService.formattedContext(for: webResults, includeCitations: true)
                                        continuation.yield("\n\n=== VERIFIED INFORMATION (Fallback) ===\n\(context)\n=== END VERIFIED INFORMATION ===\n\n")
                                        continuation.yield("Note: Using fallback web search due to technical issues. Always verify information from reliable sources.")
                                    } catch {
                                        print("❌ Fallback conversation web search also failed: \(error.localizedDescription)")
                                        continuation.yield("[Web search verification failed. Please check latest research for accuracy.]")
                                    }
                                } else {
                                    continuation.yield("[Unable to verify information with web search. Please check latest research for accuracy.]")
                                }
                                continuation.finish()
                                return
                            }
                        }
                        #else
                        // Ultimate fallback for older versions or when Foundation Models unavailable
                        continuation.yield("Web search verification unavailable. Please verify information from reliable sources.")
                        continuation.finish()
                        return
                        #endif
                    }
                }
            }
            #else
            return generatePlanStream(request: request)
            #endif
        }
        #endif
        return generatePlanStream(request: request)
    }

    private func shouldUseWebSearch(for query: String) -> Bool {
        // Use web search if enabled and query appears to need factual verification or current information
        let allowWebSearch = UserDefaults.standard.bool(forKey: "allowAIWebSearch")
        guard allowWebSearch else { return false }

        let lower = query.lowercased()

        // First, exclude personalized/subjective queries that shouldn't use web search
        let personalizedPatterns = [
            "for me", "my workout", "should i", "can i", "what should i do",
            "recommend", "suggest", "advice", "help me", "good workout for me",
            "today", "this week", "my plan", "my training", "my schedule",
            "when my", "when i", "if my", "if i", "my thighs", "my legs",
            "my arms", "my back", "i'm sore", "i am sore", "what to do when",
            "what is good to do", "what should i eat", "how do i"
        ]
        
        if personalizedPatterns.contains(where: { lower.contains($0) }) {
            // This is a personalized query - don't use web search
            return false
        }

        // Always factual keywords (high confidence) - specific, verifiable information
        let alwaysFactualKeywords = ["what is", "who is", "define", "definition", "research shows", "study found", "evidence",
                                   "clinical", "medical", "science", "scientific", "benefits of", "side effects",
                                   "contraindications", "drug", "medication", "supplement facts", "vitamin",
                                   "micronutrient", "macronutrient", " RDA ", "recommended daily",
                                   "current guidelines", "latest research", "recent study", "2024", "2025"]

        // Check for always factual keywords first (force tool usage)
        if alwaysFactualKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        // Force tool usage for critical health/nutrition topics
        let criticalHealthKeywords = ["side effects", "contraindications", "allergy", "pregnancy",
                                    "medication", "drug interaction", " RDA ", "daily requirement",
                                    "toxicity", "deficiency", "chronic", "acute", "symptoms"]
        if criticalHealthKeywords.contains(where: { lower.contains($0) }) {
            return true
        }

        // Check for specific factual phrases (not personalized)
        let factualPhrases = ["tell me about", "explain how", "describe the", "what are the effects",
                            "what causes", "what happens when", "is it safe to", "is it healthy to",
                            "how effective is", "does it work", "what's the evidence for"]

        if factualPhrases.contains(where: { lower.contains($0) }) {
            return true
        }

        // Default: don't use web search for general queries
        return false
    }

    private static func compactAssistantContext(history: [(String, String)], maxChars: Int) -> [String] {
        // Take last few assistant messages only, avoid repeating user's text
        let assistants = history.reversed().filter { $0.0.lowercased().contains("assistant") }.prefix(3).map { $0.1 }
        var bullets: [String] = []
        for text in assistants {
            // Extract first few lines; strip markdown list markers to keep short
            let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").prefix(6)
            for l in lines {
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                let clean = trimmed.replacingOccurrences(of: "^- ", with: "", options: .regularExpression)
                bullets.append(clean)
            }
        }
        var out: [String] = []
        var total = 0
        for b in bullets {
            let add = b
            if total + add.count > maxChars { break }
            out.append(add)
            total += add.count
        }
        return out
    }

    // MARK: On‑device (Apple Intelligence)
    private func generatePlanStreamOnDevice(request: WorkoutPlanRequest) -> AsyncThrowingStream<String, Error> {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            // Guided generation via FoundationModels; reuse prewarmed session when possible
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        #if canImport(FoundationModels)
                        // Choose session based on whether web search is relevant for this request
                        let useToolSession = shouldUseWebSearch(for: request.extraContext)
                        let selectedSession: LanguageModelSession

                        if useToolSession {
                            if toolEnabledSession == nil {
                                await self.prewarmToolSessionIfNeeded()
                            }
                            if let s = toolEnabledSession ?? basicSession {
                                selectedSession = s
                            } else {
                                let fallback: LanguageModelSession = await MainActor.run {
                                    LanguageModelSession(
                                        instructions: "You are a friendly, creative fitness/nutrition coach. Offer a few varied options and keep guidance practical."
                                    )
                                }
                                selectedSession = fallback
                            }
                        } else {
                            if basicSession == nil {
                                await self.prewarmIfPossible()
                            }
                            if let s = basicSession {
                                selectedSession = s
                            } else {
                                let fallback: LanguageModelSession = await MainActor.run {
                                    LanguageModelSession(
                                        instructions: "You are a friendly, creative fitness/nutrition coach. Keep answers short, varied, and actionable."
                                    )
                                }
                                selectedSession = fallback
                            }
                        }

                        if selectedSession !== basicSession && selectedSession !== toolEnabledSession {
                            selectedSession.prewarm()
                        }

                        let session = selectedSession

                        // Compute stats for prompt context
                        let userStats: UserStats = await Self.collectRecentStats(context: request.modelContext, 
                                                                                  weightUnit: request.weightUnit, 
                                                                                  distanceUnit: request.distanceUnit)

                        // Build prompt(s)
                        let prompt: String
                            switch request.mode {
                            case .plan:
                                // TESTING: Enable @Generable structured generation
                                // Previously disabled because nested schema was causing issues
                                // Now testing with simplified prompt
                                
                                prompt = AIPromptBuilder.buildPlanPrompt(
                                    goal: request.goal,
                                    context: request.extraContext,
                                    weightUnit: request.weightUnit,
                                    distanceUnit: request.distanceUnit,
                                    userStats: userStats,
                                    includeWebSearchGuidance: useToolSession
                                )

                            // Pre-process query: Force tool usage for certain patterns BEFORE sending to model (PLAN MODE)
                            if shouldUseWebSearch(for: request.extraContext) && useToolSession {
                                print("🎯 PLAN PRE-PROCESSING: Force-enabling web search for factual query: \(request.extraContext)")

                                // For certain high-confidence factual queries, call web search directly
                                let lowerQuery = request.extraContext.lowercased()
                                let directCallKeywords = ["what is", "define", "benefits", "research", "study", "evidence", "side effects", " RDA "]

                                if directCallKeywords.contains(where: { lowerQuery.contains($0) }) {
                                    print("🚨 PLAN DIRECT TOOL CALL: High-confidence factual query detected, calling web search immediately...")
                                    do {
                                        let webResults = try await WebSearchService.shared.search(query: request.extraContext, maxResults: 4)
                                        let context = WebSearchService.formattedContext(for: webResults, includeCitations: true)

                                        // Stream the verified information
                                        continuation.yield("\n\n=== VERIFIED INFORMATION ===\n\(context)\n=== END VERIFIED INFORMATION ===\n\n")
                                        continuation.yield("Based on the above research, here's my analysis:")

                                        // Then let the model continue with the verified context
                                    let enhancedPrompt = "\(Self.clampPrompt(prompt))\n\nVERIFIED CONTEXT FROM WEB SEARCH:\n\(context)\n\nNow provide your analysis based on this verified information:"
                                        let response = try await session.respond(to: Self.clampPrompt(enhancedPrompt))
                                        print("✅ Plan enhanced response generated with verified context")

                                        // Extract text from Foundation Models response
                                        let responseText: String
                                        let mirror = Mirror(reflecting: response)

                                        // Try to find text content in the response
                                        if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
                                            responseText = textValue
                                        } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
                                            responseText = contentValue
                                        } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
                                            responseText = valueValue
                                        } else {
                                            responseText = String(describing: response)
                                        }

                                        // Stream the enhanced response
                                        var currentIndex = responseText.startIndex
                                        while currentIndex < responseText.endIndex {
                                            let chunkSize = min(40, responseText.distance(from: currentIndex, to: responseText.endIndex))
                                            let endIndex = responseText.index(currentIndex, offsetBy: chunkSize)
                                            let chunk = String(responseText[currentIndex..<endIndex])
                                            continuation.yield(chunk)
                                            currentIndex = endIndex
                                            try? await Task.sleep(nanoseconds: 12_000_000) // 12ms
                                        }

                                        continuation.finish()
                                        return
                                    } catch {
                                        print("❌ Plan direct tool call failed: \(error.localizedDescription)")
                                        continuation.yield("[Direct web search failed. Continuing with standard response.]")
                                    }
                                }
                            }
                            case .ask:
                                prompt = AIPromptBuilder.buildConversationPrompt(
                                    goal: request.goal,
                                    question: request.extraContext,
                                    weightUnit: request.weightUnit,
                                    distanceUnit: request.distanceUnit,
                                    userStats: userStats,
                                    includeWebSearchGuidance: useToolSession
                                )

                            // Pre-process query: Force tool usage for certain patterns BEFORE sending to model (ASK MODE)
                            if shouldUseWebSearch(for: request.extraContext) && useToolSession {
                                print("🎯 ASK PRE-PROCESSING: Force-enabling web search for factual query: \(request.extraContext)")

                                // For certain high-confidence factual queries, call web search directly
                                let lowerQuery = request.extraContext.lowercased()
                                let directCallKeywords = ["what is", "define", "benefits", "research", "study", "evidence", "side effects", " RDA "]

                                if directCallKeywords.contains(where: { lowerQuery.contains($0) }) {
                                    print("🚨 ASK DIRECT TOOL CALL: High-confidence factual query detected, calling web search immediately...")
                                    do {
                                        let webResults = try await WebSearchService.shared.search(query: request.extraContext, maxResults: 4)
                                        let context = WebSearchService.formattedContext(for: webResults, includeCitations: true)

                                        // Stream the verified information
                                        continuation.yield("\n\n=== VERIFIED INFORMATION ===\n\(context)\n=== END VERIFIED INFORMATION ===\n\n")
                                        continuation.yield("Based on the above research, here's my analysis:")

                                        // Then let the model continue with the verified context
                                        let enhancedPrompt = "\(Self.clampPrompt(prompt))\n\nVERIFIED CONTEXT FROM WEB SEARCH:\n\(context)\n\nNow provide your analysis based on this verified information:"
                                        let response = try await session.respond(to: Self.clampPrompt(enhancedPrompt))
                                        print("✅ Ask enhanced response generated with verified context")

                                        // Extract text from Foundation Models response
                                        let responseText: String
                                        let mirror = Mirror(reflecting: response)

                                        // Try to find text content in the response
                                        if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
                                            responseText = textValue
                                        } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
                                            responseText = contentValue
                                        } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
                                            responseText = valueValue
                                        } else {
                                            responseText = String(describing: response)
                                        }

                                        // Stream the enhanced response
                                        var currentIndex = responseText.startIndex
                                        while currentIndex < responseText.endIndex {
                                            let chunkSize = min(40, responseText.distance(from: currentIndex, to: responseText.endIndex))
                                            let endIndex = responseText.index(currentIndex, offsetBy: chunkSize)
                                            let chunk = String(responseText[currentIndex..<endIndex])
                                            continuation.yield(chunk)
                                            currentIndex = endIndex
                                            try? await Task.sleep(nanoseconds: 12_000_000) // 12ms
                                        }

                                        continuation.finish()
                                        return
                                    } catch {
                                        print("❌ Ask direct tool call failed: \(error.localizedDescription)")
                                        continuation.yield("[Direct web search failed. Continuing with standard response.]")
                                    }
                                }
                            }
                        }

                        // Use proper Foundation Models API with guided generation
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                print("🎯 Using Foundation Models respond() API for prompt: \(prompt.prefix(100))...")

                                // Use respond() instead of generate() - the generate() API is not available
                                let response = try await session.respond(to: Self.clampPrompt(prompt))
                                print("✅ Foundation Models respond() completed")
                                print("📊 Response type: \(type(of: response))")

                                // Extract text from Foundation Models response
                                let responseText: String
                                let mirror = Mirror(reflecting: response)
                                
                                // Log all available properties for debugging
                                print("🔍 Response properties: \(mirror.children.map { "\($0.label ?? "unknown"): \(type(of: $0.value))" }.joined(separator: ", "))")

                                // Try to find text content in the response
                                if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
                                    responseText = textValue
                                    print("✅ Extracted text from 'text' property: \(responseText.prefix(100))...")
                                } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
                                    responseText = contentValue
                                    print("✅ Extracted text from 'content' property: \(responseText.prefix(100))...")
                                } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
                                    responseText = valueValue
                                    print("✅ Extracted text from 'value' property: \(responseText.prefix(100))...")
                                } else {
                                    // Fallback: use string description
                                    let description = String(describing: response)
                                    print("⚠️ Could not extract text property, using description: \(description.prefix(100))...")
                                    
                                    // Check if description is just the type name (indicates extraction failure)
                                    if description.hasPrefix("LanguageModelResponse") || description.count < 50 {
                                        print("❌ Extraction failed - description too short or just type name")
                                        throw NSError(domain: "WorkoutPlanGenerator", code: -1, 
                                                    userInfo: [NSLocalizedDescriptionKey: "Failed to extract text from AI response"])
                                    }
                                    responseText = description
                                }
                                
                                // Validate we have actual content
                                let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmedResponse.isEmpty {
                                    print("❌ Response text is empty after extraction")
                                    throw NSError(domain: "WorkoutPlanGenerator", code: -2,
                                                userInfo: [NSLocalizedDescriptionKey: "AI generated empty response"])
                                }
                                
                                print("✅ Streaming \(responseText.count) characters to UI...")

                                // Stream the response as chunks for UI compatibility
                                var currentIndex = responseText.startIndex
                                while currentIndex < responseText.endIndex {
                                    let chunkSize = min(160, responseText.distance(from: currentIndex, to: responseText.endIndex))
                                    let endIndex = responseText.index(currentIndex, offsetBy: chunkSize)
                                    let chunk = String(responseText[currentIndex..<endIndex])
                                    continuation.yield(chunk)
                                    currentIndex = endIndex

                                    // Smaller delay for better perceived latency
                                    try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
                                }

                                print("✅ Streaming complete, finishing continuation")
                                continuation.finish()
                                return
                            } catch {
                                print("❌ Foundation Models respond() failed: \(error.localizedDescription)")
                                print("📋 Error details: \(error)")

                                // Show user-friendly error message
                                let errorMessage = error.localizedDescription
                                if errorMessage.contains("Failed to extract text") {
                                    continuation.yield("⚠️ **AI Response Processing Error**\n\n")
                                    continuation.yield("The AI model completed generation, but the response couldn't be properly extracted. ")
                                    continuation.yield("This might be due to an API format change.\n\n")
                                    continuation.yield("**What you can do:**\n")
                                    continuation.yield("1. Try regenerating the plan\n")
                                    continuation.yield("2. Use the 'Reset Model Context' button and try again\n")
                                    continuation.yield("3. Check the console logs for more details\n\n")
                                    continuation.yield("**Technical details:** \(errorMessage)")
                                    continuation.finish()
                                    return
                                } else if errorMessage.contains("empty response") {
                                    continuation.yield("⚠️ **No Content Generated**\n\n")
                                    continuation.yield("The AI model completed but didn't generate any content. ")
                                    continuation.yield("This can happen if the request was unclear or too complex.\n\n")
                                    continuation.yield("**Try:**\n")
                                    continuation.yield("1. Simplify your request\n")
                                    continuation.yield("2. Be more specific about what you need\n")
                                    continuation.yield("3. Use the 'Reset Model Context' button to clear the session")
                                    continuation.finish()
                                    return
                                }

                                // Fallback: Force web search for critical queries
                                if shouldUseWebSearch(for: request.extraContext) {
                                    print("🚨 Forcing fallback web search due to API failure...")
                                    do {
                                        let webResults = try await WebSearchService.shared.search(query: request.extraContext, maxResults: 4)
                                        let context = WebSearchService.formattedContext(for: webResults, includeCitations: true)
                                        continuation.yield("\n\n=== VERIFIED INFORMATION (Fallback) ===\n\(context)\n=== END VERIFIED INFORMATION ===\n\n")
                                        continuation.yield("Note: Using fallback web search due to technical issues. Always verify information from reliable sources.")
                                    } catch {
                                        print("❌ Fallback web search also failed: \(error.localizedDescription)")
                                        continuation.yield("[Web search verification failed. Please check latest research for accuracy.]")
                                    }
                                } else {
                                    continuation.yield("⚠️ **Generation Failed**\n\n")
                                    continuation.yield("Unable to complete AI generation: \(errorMessage)\n\n")
                                    continuation.yield("Please try again or reset the model context.")
                                }
                                continuation.finish()
                                return
                            }
                        }
                        #endif

                        // Fallback for older versions or when tools aren't available
                        continuation.yield("Web search verification unavailable. Please verify information from reliable sources.")
                        continuation.finish()
                        return
                        #else
                        let fallback = self.generatePlanStreamFromTemplate(request: request)
                        for try await chunk in fallback { continuation.yield(chunk) }
                        continuation.finish()
                        #endif
                    } catch {
                        let message = error.localizedDescription
                        let lower = message.lowercased()
                        if lower.contains("system state") || lower.contains("game mode") || lower.contains("sensitivecontentanalysisml") || lower.contains("modelmanager") {
                            continuation.yield("[AI unavailable now: \(message).]")
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
        }
        #endif
        return generatePlanStreamFromTemplate(request: request)
    }

    // MARK: Fallback Template (Non‑AI devices)
    private func generatePlanStreamFromTemplate(request: WorkoutPlanRequest) -> AsyncThrowingStream<String, Error> {
        // No manual templates: return a minimal message only.
        let message = "AI is currently unavailable. Please try again later."
        return AsyncThrowingStream { continuation in
            continuation.yield(message)
            continuation.finish()
        }
    }

    // MARK: - Stats Aggregation
    struct UserStats {
        // Strength
        let workoutSessions: Int
        let totalLifted: Double
        // Running (last 14d)
        let runSessions: Int
        let totalDistance: Double
        // Running (this week)
        let weeklyRunSessions: Int
        let weeklyDistance: Double
        // Weight + units
        let latestWeight: Double?
        let weightUnit: String
        let distanceUnit: String
        // Library and baselines
        let exerciseBaselines: [ExerciseBaseline]
        let exerciseLibrary: [String]
        // HealthKit data
        let todaySteps: Int?
        let recentHealthKitRuns: Int
        let avgRecentPace: String?
        // Detailed data for specific queries
        let detailedRuns: [DetailedRun]
        let detailedWorkouts: [DetailedWorkout]
        // User profile
        let experienceLevel: String  // "beginner" or "experienced"
    }
    
    struct DetailedRun {
        let date: Date
        let distance: Double
        let duration: TimeInterval
        let distanceUnit: String
    }
    
    struct DetailedWorkout {
        let date: Date
        let exercises: [String]
        let totalVolume: Double
    }

    @MainActor
    private static func collectRecentStats(context: ModelContext, weightUnit: String, distanceUnit: String) async -> UserStats {
        // Last 14 days
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        // This week (locale-aware)
        let startOfWeek: Date = {
            let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
            return calendar.date(from: comps) ?? calendar.startOfDay(for: Date())
        }()

        // Fetch objects directly via SwiftData queries
        let workouts: [WorkoutSession] = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let exerciseDefs: [ExerciseDefinition] = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let weights: [WeightEntry] = (try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []

        // Filter last 14 days
        let recentWorkouts = workouts.filter { $0.date >= start }
        let recentRuns = runs.filter { $0.date >= start }
        let weeklyRuns = runs.filter { $0.date >= startOfWeek }

        // Volume = sum(reps * weight) across logs
        var totalLifted: Double = 0
        var detailedWorkouts: [DetailedWorkout] = []
        
        for session in recentWorkouts {
            let logs = session.exerciseLogs ?? []
            var sessionVolume: Double = 0
            var exerciseNames: [String] = []
            
            for log in logs {
                let w = convertWeight(log.weight, from: log.weightUnit, to: weightUnit)
                let logVolume = Double(log.reps) * w
                sessionVolume += logVolume
                totalLifted += logVolume
                
                if let name = log.exerciseName, !exerciseNames.contains(name) {
                    exerciseNames.append(name)
                }
            }
            
            detailedWorkouts.append(DetailedWorkout(
                date: session.date,
                exercises: exerciseNames,
                totalVolume: sessionVolume
            ))
        }

        // Distance in desired unit
        var totalDistance: Double = 0
        var weeklyDistance: Double = 0
        var detailedRuns: [DetailedRun] = []
        // For distance-weighted average pace
        var aggDurationSec14d: TimeInterval = 0
        var aggDistanceUnits14d: Double = 0
        
        for run in recentRuns {
            let baseMi = run.distanceUnit.lowercased().contains("mi")
            let value = run.distance
            let inKm = baseMi ? value * 1.60934 : value
            let targetKm = distanceUnit.lowercased().contains("km")
            let converted = targetKm ? inKm : inKm / 1.60934
            totalDistance += converted

            // Pace aggregation (distance-weighted): sum times, sum distances
            let distInUnit = targetKm ? inKm : inKm / 1.60934
            if distInUnit > 0, run.duration > 0 {
                aggDurationSec14d += run.duration
                aggDistanceUnits14d += distInUnit
            }

            detailedRuns.append(DetailedRun(
                date: run.date,
                distance: run.distance,
                duration: run.duration,
                distanceUnit: run.distanceUnit
            ))
        }

        // Weekly distance from local runs
        for run in weeklyRuns {
            let baseMi = run.distanceUnit.lowercased().contains("mi")
            let value = run.distance
            let inKm = baseMi ? value * 1.60934 : value
            let targetKm = distanceUnit.lowercased().contains("km")
            let converted = targetKm ? inKm : inKm / 1.60934
            weeklyDistance += converted
        }

        let latestWeight = weights.first?.weightUnit == weightUnit ? weights.first?.weight : (weights.first.map { convertWeight($0.weight, from: $0.weightUnit, to: weightUnit) })

        let baselines = ExerciseRecommendationService.baselines(context: context, preferredUnit: weightUnit)
        
        // Fetch HealthKit data asynchronously
        var todaySteps: Int? = nil
        var recentHealthKitRuns = 0
        var avgRecentPace: String? = nil
        
        let hkManager = HealthKitManager.shared
        if hkManager.isAuthorized {
            todaySteps = try? await hkManager.todayStepCount()
            if let hkWorkouts = try? await hkManager.fetchRecentRuns(limit: 10) {
                let recent = hkWorkouts.filter { $0.endDate >= start }
                recentHealthKitRuns = recent.count

                // If we don't have any local runs in the last 14d, fall back to HK for avg pace
                if aggDistanceUnits14d <= 0 {
                    var hkTotalDuration: TimeInterval = 0
                    var hkTotalDistanceUnits: Double = 0
                    for workout in recent {
                        guard let distanceM = workout.totalDistance?.doubleValue(for: .meter()), distanceM > 0 else { continue }
                        let duration = workout.duration
                        let distanceInUnit = distanceUnit.lowercased().contains("km") ? distanceM / 1000.0 : distanceM / 1609.34
                        hkTotalDuration += duration
                        hkTotalDistanceUnits += distanceInUnit
                    }
                    if hkTotalDistanceUnits > 0 {
                        let paceMinPerUnit = (hkTotalDuration / 60.0) / hkTotalDistanceUnits
                        let mins = Int(paceMinPerUnit)
                        let secs = Int((paceMinPerUnit - Double(mins)) * 60)
                        avgRecentPace = String(
                            format: "%d:%02d per %@",
                            mins, secs,
                            distanceUnit.lowercased().contains("km") ? "km" : "mi"
                        )
                    }
                }
            }
        }

        // If we have local data, compute distance-weighted average pace from it
        if aggDistanceUnits14d > 0 {
            let paceMinPerUnit = (aggDurationSec14d / 60.0) / aggDistanceUnits14d
            let mins = Int(paceMinPerUnit)
            let secs = Int((paceMinPerUnit - Double(mins)) * 60)
            avgRecentPace = String(
                format: "%d:%02d per %@",
                mins, secs,
                distanceUnit.lowercased().contains("km") ? "km" : "mi"
            )
        }
        
        // Get experience level from UserDefaults
        let experienceLevel = UserDefaults.standard.string(forKey: "experienceLevel") ?? "beginner"
        
        return UserStats(
            workoutSessions: recentWorkouts.count,
            totalLifted: totalLifted,
            runSessions: recentRuns.count,
            totalDistance: totalDistance,
            weeklyRunSessions: weeklyRuns.count,
            weeklyDistance: weeklyDistance,
            latestWeight: latestWeight,
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            exerciseBaselines: baselines,
            exerciseLibrary: exerciseDefs.map { $0.name }.sorted(),
            todaySteps: todaySteps,
            recentHealthKitRuns: recentHealthKitRuns,
            avgRecentPace: avgRecentPace,
            detailedRuns: detailedRuns,
            detailedWorkouts: detailedWorkouts,
            experienceLevel: experienceLevel
        )
    }

    private static func convertWeight(_ value: Double, from: String, to: String) -> Double {
        if from == to { return value }
        if from == "kg" && to == "lbs" { return value * 2.20462 }
        if from == "lbs" && to == "kg" { return value / 2.20462 }
        return value
    }
    
    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }

    // MARK: - Structured plan generation helpers
    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func tryGenerateStructuredPlanMarkdown(session: LanguageModelSession,
                                                         request: WorkoutPlanRequest,
                                                         userStats: UserStats) async throws -> String? {
        // TEMPORARILY COMMENTED OUT: Testing @Generable guided generation instead of JSON prompt
        /*
        // Build a JSON-only prompt to generate a structured plan
        let instructions = AIPromptBuilder.buildPlanPrompt(
            goal: request.goal,
            context: request.extraContext,
            weightUnit: request.weightUnit,
            distanceUnit: request.distanceUnit,
            userStats: userStats,
            includeWebSearchGuidance: false
        )

        let schemaHint = """
Return ONLY valid JSON with this shape (no backticks, no prose):
{
  "title": String,
  "overview": String,
  "unit": String,
  "weeks": [
    { "title": String, "days": [
      { "title": String, "type": String,
        "items": [
          { "name": String,
            "sets": Number?,
            "reps": Number?,
            "suggestedWeight": String?,
            "notes": String?,
            "distance": Number?,
            "distanceUnit": String?,
            "pace": String?,
            "durationMinutes": Number?,
            "effort": String?
          }
        ]
      }
    ]}
  ],
  "guidance": String
}
Type values for "type" must be one of: "strengthUpper","strengthLower","fullBodyStrength","runEasy","runTempo","runIntervals","longRun","cyclingEndurance","rowing","swimming","activeRecovery","rest".
Ensure strength days have 4–6 items; running items include distance and pace; non-running cardio uses duration/effort.
"""

        let jsonPrompt = Self.clampPrompt(instructions + "\n\n" + schemaHint)

        // Ask the model
        let response = try await session.respond(to: jsonPrompt)
        let responseText: String
        let mirror = Mirror(reflecting: response)
        if let textValue = mirror.children.first(where: { $0.label?.contains("text") == true })?.value as? String {
            responseText = textValue
        } else if let contentValue = mirror.children.first(where: { $0.label?.contains("content") == true })?.value as? String {
            responseText = contentValue
        } else if let valueValue = mirror.children.first(where: { $0.label?.contains("value") == true })?.value as? String {
            responseText = valueValue
        } else {
            responseText = String(describing: response)
        }

        guard let jsonString = extractJSONString(from: responseText) else { return nil }
        guard let data = jsonString.data(using: .utf8) else { return nil }

        // Decode into guided schema
        do {
            let decoder = JSONDecoder()
            let plan = try decoder.decode(WorkoutPlan.self, from: data)
            Self.lastStructuredPlanJSON = jsonString
            return formatMarkdown(from: plan, weightUnit: request.weightUnit, distanceUnit: request.distanceUnit)
        } catch {
            print("❌ Structured decode failed: \(error)")
            return nil
        }
        */
        return nil
    }

    private static func extractJSONString(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return nil }
        let s = String(text[first...last])
        // Trim code fences if present
        return s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatMarkdown(from plan: WorkoutPlan, weightUnit: String, distanceUnit: String) -> String {
        var out: [String] = []
        out.append("## This Week's Training Plan")
        out.append("")
        if !plan.overview.isEmpty { out.append(plan.overview); out.append("") }

        // Use only first week for weekly view
        if let week = plan.weeks.first {
            for day in week.days {
                out.append("### \(day.title)")
                if day.items.isEmpty {
                    // Rest or recovery indicator
                    switch day.type {
                    case .activeRecovery: out.append("- Active Recovery")
                    case .rest: out.append("- Rest Day")
                    default: break
                    }
                } else {
                    for item in day.items {
                        if let sets = item.sets, let reps = item.reps {
                            // Strength item; include suggested weight if present
                            if let w = item.suggestedWeight, !w.isEmpty {
                                out.append("- **\(item.name)** — \(sets)x\(reps) @ \(w)")
                            } else {
                                out.append("- **\(item.name)** — \(sets)x\(reps)")
                            }
                        } else if let dist = item.distance, let unit = item.distanceUnit {
                            var line = "- \(item.name): \(String(format: "%.1f", dist)) \(unit)"
                            if let pace = item.pace { line += " @ \(pace)" }
                            if let mins = item.durationMinutes { line += " (\(mins) min)" }
                            if let eff = item.effort, !eff.isEmpty { line += " — \(eff)" }
                            out.append(line)
                        } else {
                            // Generic item with optional notes
                            var line = "- \(item.name)"
                            if let n = item.notes, !n.isEmpty { line += ": \(n)" }
                            out.append(line)
                        }
                    }
                }
                out.append("")
            }
        }

        if !plan.guidance.isEmpty {
            out.append("---")
            out.append(plan.guidance)
        }
        return out.joined(separator: "\n")
    }
    #endif
    
    private static func calculatePace(distance: Double, duration: TimeInterval, unit: String) -> String {
        guard distance > 0 else { return "N/A" }
        // duration is in seconds, so convert to minutes per unit
        let paceMinutesPerUnit = (duration / 60.0) / distance
        let mins = Int(paceMinutesPerUnit)
        let secs = Int((paceMinutesPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d per %@", mins, secs, unit)
    }

    // MARK: - Tool Calling Flow
    private func handleToolCallIfPresent(_ snapshot: Any) async -> ToolCall? {
        // Enhanced tool call detection for Foundation Models
        let mirror = Mirror(reflecting: snapshot)

        // First check if it's a direct ToolCall object
        for child in mirror.children {
            if let toolCall = child.value as? ToolCall {
                return toolCall
            }
        }

        // Check for tool call in string representation with enhanced patterns
        let description = String(describing: snapshot)
        if description.contains("webSearch(") || description.contains("webSearch") {
            return parseToolCallFromString(description)
        }

        // Also check the snapshot's description directly
        if let desc = snapshot as? CustomStringConvertible {
            let text = desc.description
            if text.contains("webSearch(") || text.contains("webSearch") {
                return parseToolCallFromString(text)
            }
        }

        return nil
    }

    private func parseToolCallFromString(_ text: String) -> ToolCall? {
        // Parse tool calls in multiple formats and variations:
        // webSearch('query', 3)
        // webSearch('query')
        // webSearch("query", 3)
        // webSearch("query")
        // webSearch(query, 3)
        // webSearch(query)

        // Clean the text first
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try single quotes with maxResults
        let pattern1 = "webSearch\\('([^']+)',\\s*(\\d+)\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern1) {
            return toolCall
        }

        // Try single quotes without maxResults (default to 3)
        let pattern2 = "webSearch\\('([^']+)'\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern2, defaultMaxResults: 3) {
            return toolCall
        }

        // Try double quotes with maxResults
        let pattern3 = "webSearch\\(\"([^\"]+)\",\\s*(\\d+)\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern3) {
            return toolCall
        }

        // Try double quotes without maxResults
        let pattern4 = "webSearch\\(\"([^\"]+)\"\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern4, defaultMaxResults: 3) {
            return toolCall
        }

        // Try no quotes with maxResults
        let pattern5 = "webSearch\\(([^,]+),\\s*(\\d+)\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern5) {
            return toolCall
        }

        // Try no quotes without maxResults
        let pattern6 = "webSearch\\(([^)]+)\\)"
        if let toolCall = parseWithPattern(cleanText, pattern: pattern6, defaultMaxResults: 3) {
            return toolCall
        }

        return nil
    }

    private func parseWithPattern(_ text: String, pattern: String, defaultMaxResults: Int? = nil) -> ToolCall? {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(text.startIndex..., in: text)

        guard let match = regex?.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let queryRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let query = String(text[queryRange])
        let maxResults = defaultMaxResults ?? (match.numberOfRanges >= 3 ? (Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 3) : 3)

        return ToolCall(toolName: "webSearch", arguments: ["query": query, "maxResults": maxResults])
    }

    private func executeTool(_ toolCall: ToolCall) async throws -> String {
        // Add timeout for tool execution to prevent hanging
        return try await withTimeout(seconds: 30) {
            switch toolCall.toolName {
            case "webSearch":
                guard let query = toolCall.arguments["query"] as? String,
                      let maxResults = toolCall.arguments["maxResults"] as? Int else {
                    throw NSError(domain: "ToolCall", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid webSearch arguments"])
                }

                // Validate maxResults range
                let clampedMaxResults = max(1, min(maxResults, 5))
                let results = try await WebSearchService.shared.search(query: query, maxResults: clampedMaxResults)
                return WebSearchService.formattedContext(for: results)

            default:
                throw NSError(domain: "ToolCall", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown tool: \(toolCall.toolName)"])
            }
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "ToolCall", code: -2, userInfo: [NSLocalizedDescriptionKey: "Tool execution timed out"])
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func buildToolResultPrompt(_ toolCall: ToolCall, result: String) async -> String {
        var lines: [String] = []
        lines.append("Tool call completed: \(toolCall.toolName)")
        lines.append("Arguments: \(toolCall.arguments)")
        lines.append("Result:")
        lines.append(result)
        lines.append("")
        lines.append("Continue with the user's original request, incorporating the tool result above.")
        return lines.joined(separator: "\n")
    }

    private func generateWithToolResult(_ session: LanguageModelSession, _ toolPrompt: String, originalPrompt: String) async -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var previous = ""
                    for try await snapshot in session.streamResponse(to: toolPrompt) {
                        let full: String = {
                            if let s = snapshot as? CustomStringConvertible { return s.description }
                            let mirror = Mirror(reflecting: snapshot)
                            if let child = mirror.children.first(where: { $0.value is String }) {
                                return child.value as? String ?? ""
                            }
                            return String(describing: snapshot)
                        }()
                        let piece = full.hasPrefix(previous) ? String(full.dropFirst(previous.count)) : full
                        previous = full
                        if !piece.isEmpty { continuation.yield(piece) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: Supporting Types
    private struct ToolCall {
        let toolName: String
        let arguments: [String: Any]
    }
}
