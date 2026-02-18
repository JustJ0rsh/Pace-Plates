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
    enum AskGenerationProfile { case conversational, strictStructuredOutput }

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
    // Reused session to prewarm once and reduce latency
    private var basicSession: LanguageModelSession? = nil
    #endif
    
    // Static variable to track last context summary for conversation continuity
    static var lastConversationSummary: String? = nil

    // Last structured plan JSON emitted during generation (if any). Used for persistence/preview.
    static var lastStructuredPlanJSON: String? = nil

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func generationOptionsForAsk(profile: AskGenerationProfile) -> GenerationOptions {
        switch profile {
        case .conversational:
            return GenerationOptions(
                sampling: .random(probabilityThreshold: 0.96),
                temperature: 0.9
            )
        case .strictStructuredOutput:
            return GenerationOptions(
                sampling: .random(probabilityThreshold: 0.72),
                temperature: 0.35
            )
        }
    }

    @available(iOS 26, *)
    private static func generationOptionsForPlan() -> GenerationOptions {
        GenerationOptions(
            sampling: .random(probabilityThreshold: 0.9),
            temperature: 0.55
        )
    }

    private static func normalizeCoachAnswer(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Keep numbered and bulleted content readable when the model compresses lines.
        text = text.replacingOccurrences(
            of: #"(?<=\S)\s+(\d+\.)\s+"#,
            with: "\n\n$1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?<=\S)\s+([•\-])\s+"#,
            with: "\n$1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return text
    }
    #endif

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

    // Tool-enabled session and prewarming removed (web search disabled)
    
    /// Reset/offload the model sessions to clear context and free memory
    @MainActor
    func resetModelContext() {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            print("🔄 Resetting model context...")
            basicSession = nil
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
        if request.mode == .ask {
            return generateAskStream(request: request, history: [])
        }
        Self.lastStructuredPlanJSON = nil

        let availability = availability()
        switch availability {
        case .available:
            return generatePlanStreamOnDevice(request: request)
        case .unavailable, .unknown:
            return generatePlanStreamFromTemplate(request: request)
        }
    }

    // Streaming for Ask mode with concise conversation context (no repetition)
    func generateAskStream(request: WorkoutPlanRequest,
                           history: [(String, String)],
                           profile: AskGenerationProfile = .conversational) -> AsyncThrowingStream<String, Error> {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            // Do not include previous conversation context in Ask to minimize tokens
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let generationOptions = Self.generationOptionsForAsk(profile: profile)
                        // Use a fresh, ephemeral session to avoid context accumulation
                        let session: LanguageModelSession = await MainActor.run {
                            let s = LanguageModelSession(
                                instructions: "You are a concise fitness/nutrition coach. Keep answers short, safe, and practical."
                            )
                            return s
                        }

                        let userStats: UserStats = await Self.collectRecentStats(context: request.modelContext, 
                                                                                  weightUnit: request.weightUnit, 
                                                                                  distanceUnit: request.distanceUnit)

                        // Build concise prompt using centralized builder
                        // Include equipment from Settings if available
                        let equipment = UserDefaults.standard.string(forKey: "userEquipment")
                        var prompt = AIPromptBuilder.buildConversationPrompt(
                            goal: request.goal,
                            question: request.extraContext,
                            weightUnit: request.weightUnit,
                            distanceUnit: request.distanceUnit,
                            userStats: userStats,
                            equipment: equipment
                        )
                        // Extra-safe cap for Ask prompts
                        if prompt.count > 900 { prompt = String(prompt.prefix(900)) }

                        // Clamp prompt size defensively to avoid context window overflow
                        let safePrompt = Self.clampPrompt(prompt)

                        // Web search/tool calls disabled
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                print("🎯 Conversation: Streaming Foundation Models response for prompt: \(safePrompt.prefix(100))...")
                                var previousSnapshotText = ""
                                var streamedAnyText = false

                                for try await snapshot in session.streamResponse(
                                    to: safePrompt,
                                    options: generationOptions
                                ) {
                                    if Task.isCancelled { break }
                                    let currentText = snapshot.content
                                        .replacingOccurrences(of: "\r\n", with: "\n")
                                        .replacingOccurrences(of: "\r", with: "\n")

                                    let delta = AIStreamSmoothing.appendableDelta(
                                        previous: previousSnapshotText,
                                        current: currentText
                                    )
                                    previousSnapshotText = currentText

                                    guard !delta.isEmpty else { continue }
                                    streamedAnyText = true
                                    for piece in AIStreamSmoothing.wordChunked(delta, maxChunkChars: 34) {
                                        continuation.yield(piece)
                                    }
                                }

                                if !streamedAnyText && !previousSnapshotText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    continuation.yield(previousSnapshotText)
                                }
                                continuation.finish()
                                return
                            } catch {
                                print("❌ Conversation streaming failed: \(error.localizedDescription)")
                                continuation.finish(throwing: error)
                                return
                            }
                        }
                        #else
                        // Fallback for older versions or when Foundation Models unavailable
                        continuation.yield("AI unavailable on this device or OS version.")
                        continuation.finish()
                        return
                        #endif
                    }
                }
            }
            #else
            return generatePlanStreamFromTemplate(request: request)
            #endif
        }
        #endif
        return generatePlanStreamFromTemplate(request: request)
    }

    // Web search disabled - always false

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
            // Guided generation via FoundationModels; use a fresh session per request to avoid context carry-over
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        #if canImport(FoundationModels)
                        let session: LanguageModelSession = await MainActor.run {
                            let s = LanguageModelSession(
                                instructions: "You are a friendly, creative fitness/nutrition coach. Keep answers short, varied, and actionable."
                            )
                            return s
                        }

                        // Compute stats for prompt context
                        let userStats: UserStats = await Self.collectRecentStats(context: request.modelContext, 
                                                                                  weightUnit: request.weightUnit, 
                                                                                  distanceUnit: request.distanceUnit)

                        // Use proper Foundation Models API with guided generation
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                if request.mode == .plan {
                                    if await Self.streamStructuredPlanMarkdown(
                                        session: session,
                                        request: request,
                                        userStats: userStats,
                                        continuation: continuation
                                    ) {
                                        continuation.finish()
                                        return
                                    }

                                    continuation.yield("⚠️ **Generation Failed**\n\nUnable to generate a structured plan right now. Please try again.")
                                    continuation.finish()
                                    return
                                }

                                let askStream = self.generateAskStream(request: request, history: [])
                                for try await chunk in askStream {
                                    if Task.isCancelled { break }
                                    continuation.yield(chunk)
                                }
                                continuation.finish()
                                return
                            } catch {
                                print("❌ Foundation Models streaming failed: \(error.localizedDescription)")
                                print("📋 Error details: \(error)")

                                // Show user-friendly error message
                                let errorMessage = error.localizedDescription
                                continuation.yield("⚠️ **Generation Failed**\n\nUnable to complete AI generation: \(errorMessage)\n\nPlease try again or reset the model context.")
                                continuation.finish()
                                return
                            }
                        }
                        #endif

                        // Fallback for older versions or when tools aren't available
                        continuation.yield("AI unavailable on this device or OS version.")
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
        // Typical distance and suggested long run
        let typicalRunDistance: Double?
        let suggestedLongRunDistance: Double?
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
                let logVolume = Double(log.effectiveReps) * w
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
        var lastDistances: [Double] = []
        
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
            if converted > 0 { lastDistances.append(converted) }

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
        
        // Compute typical distance (median of last up to 6 runs)
        var typicalRunDistance: Double? = nil
        var suggestedLongRun: Double? = nil
        if !lastDistances.isEmpty {
            let sorted = lastDistances.suffix(6).sorted()
            if !sorted.isEmpty {
                let mid = sorted.count / 2
                let median = sorted.count % 2 == 0 ? (sorted[mid-1] + sorted[mid]) / 2.0 : sorted[mid]
                typicalRunDistance = roundRunDistance(median, unit: distanceUnit)
                if let base = typicalRunDistance {
                    // Increase long run by ~15% with a minimum floor of +0.5 (mi) or +1.0 (km)
                    let minStep = distanceUnit.lowercased().contains("km") ? 1.0 : 0.5
                    let inc = max(base * 0.15, minStep)
                    suggestedLongRun = roundRunDistance(base + inc, unit: distanceUnit)
                }
            }
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
            typicalRunDistance: typicalRunDistance,
            suggestedLongRunDistance: suggestedLongRun,
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

    private static func roundRunDistance(_ value: Double, unit: String) -> Double {
        // Round to realistic increments: 0.5 for miles, 1.0 for km
        if unit.lowercased().contains("km") {
            return (value / 1.0).rounded() * 1.0
        } else {
            return (value / 0.5).rounded() * 0.5
        }
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
    private static func streamStructuredPlanMarkdown(
        session: LanguageModelSession,
        request: WorkoutPlanRequest,
        userStats: UserStats,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async -> Bool {
        let instructions = AIPromptBuilder.buildPlanPrompt(
            goal: request.goal,
            context: request.extraContext,
            weightUnit: request.weightUnit,
            distanceUnit: request.distanceUnit,
            userStats: userStats
        )
        let prompt = Self.clampPrompt(instructions)

        do {
            var previousPreviewText = ""
            var emittedText = ""
            var finalRawContent: GeneratedContent? = nil

            let stream = session.streamResponse(
                to: prompt,
                generating: WorkoutPlan.self,
                options: Self.generationOptionsForPlan()
            )

            for try await snapshot in stream {
                if Task.isCancelled { return false }

                finalRawContent = snapshot.rawContent
                let preview = partialMarkdownPreview(
                    from: snapshot.rawContent,
                    fallback: previousPreviewText,
                    distanceUnit: request.distanceUnit
                )
                let delta = AIStreamSmoothing.appendableDelta(previous: previousPreviewText, current: preview)
                previousPreviewText = preview

                guard !delta.isEmpty else { continue }
                for piece in AIStreamSmoothing.wordChunked(delta, maxChunkChars: 52) {
                    emittedText += piece
                    continuation.yield(piece)
                }
            }

            guard let finalRawContent else { return false }
            let finalPlan = try WorkoutPlan(finalRawContent)
            let normalizedPlan = normalizePlan(finalPlan)
            Self.lastStructuredPlanJSON = normalizedPlan.generatedContent.jsonString

            let finalMarkdown = formatMarkdown(
                from: normalizedPlan,
                weightUnit: request.weightUnit,
                distanceUnit: request.distanceUnit
            )
            let finalDelta = AIStreamSmoothing.appendableDelta(previous: emittedText, current: finalMarkdown)
            if !finalDelta.isEmpty {
                for piece in AIStreamSmoothing.wordChunked(finalDelta, maxChunkChars: 52) {
                    continuation.yield(piece)
                }
            } else if emittedText.isEmpty && !finalMarkdown.isEmpty {
                continuation.yield(finalMarkdown)
            }
            return true
        } catch {
            print("⚠️ Guided generation fallback to text stream: \(error.localizedDescription)")
            return false
        }
    }

    static func markdownFromStructuredPlanJSON(_ json: String, weightUnit: String, distanceUnit: String) -> String? {
        if #available(iOS 26, *) {
            guard let content = try? GeneratedContent(json: json),
                  let plan = try? WorkoutPlan(content) else {
                return nil
            }
            return formatMarkdown(
                from: normalizePlan(plan),
                weightUnit: weightUnit,
                distanceUnit: distanceUnit
            )
        }
        return nil
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

    private static func partialMarkdownPreview(from rawContent: GeneratedContent,
                                               fallback: String,
                                               distanceUnit: String) -> String {
        guard let data = rawContent.jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }

        var out: [String] = ["## This Week's Training Plan", ""]

        let overview = stringValue(root["overview"])
        if !overview.isEmpty {
            out.append(overview)
            out.append("")
        }

        if let weeks = arrayValue(root["weeks"]),
           let firstWeek = weeks.first.flatMap(dictionaryValue),
           let days = arrayValue(firstWeek["days"]) {
            for dayValue in days {
                guard let day = dictionaryValue(dayValue) else { continue }
                let dayTitle = stringValue(day["title"])
                guard !dayTitle.isEmpty else { continue }

                out.append("### \(dayTitle)")

                var emittedItems = false
                if let items = arrayValue(day["items"]) {
                    for itemValue in items {
                        guard let item = dictionaryValue(itemValue),
                              let line = previewLine(from: item, distanceUnit: distanceUnit) else { continue }
                        out.append(line)
                        emittedItems = true
                    }
                }

                if !emittedItems {
                    let dayType = stringValue(day["type"]).lowercased()
                    if dayType == DayType.activeRecovery.rawValue.lowercased() {
                        out.append("- Active Recovery")
                    } else if dayType == DayType.rest.rawValue.lowercased() {
                        out.append("- Rest Day")
                    }
                }

                out.append("")
            }
        }

        let guidance = stringValue(root["guidance"])
        if !guidance.isEmpty {
            out.append("---")
            out.append(guidance)
        }

        let rendered = out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? fallback : rendered
    }

    private static func previewLine(from item: [String: Any], distanceUnit: String) -> String? {
        let name = stringValue(item["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let sets = intValue(item["sets"]), let reps = intValue(item["reps"]) {
            let suggestedWeight = stringValue(item["suggestedWeight"])
            if !suggestedWeight.isEmpty {
                return "- **\(name)** — \(sets)x\(reps) @ \(suggestedWeight)"
            }
            return "- **\(name)** — \(sets)x\(reps)"
        }

        if let distance = doubleValue(item["distance"]) {
            let unit = {
                let found = stringValue(item["distanceUnit"])
                return found.isEmpty ? distanceUnit : found
            }()
            var line = "- \(name): \(String(format: "%.1f", distance)) \(unit)"
            let pace = stringValue(item["pace"])
            if !pace.isEmpty { line += " @ \(pace)" }
            if let minutes = intValue(item["durationMinutes"]) { line += " (\(minutes) min)" }
            let effort = stringValue(item["effort"])
            if !effort.isEmpty { line += " — \(effort)" }
            return line
        }

        let notes = stringValue(item["notes"])
        if !notes.isEmpty {
            return "- \(name): \(notes)"
        }
        return "- \(name)"
    }

    private static func normalizePlan(_ plan: WorkoutPlan, calendar: Calendar = .current) -> WorkoutPlan {
        let normalizedWeek = normalizeWeek(plan.weeks.first, calendar: calendar)
        return WorkoutPlan(
            title: plan.title,
            overview: plan.overview,
            unit: plan.unit,
            weeks: [normalizedWeek],
            guidance: plan.guidance
        )
    }

    private static func normalizeWeek(_ week: Week?, calendar: Calendar) -> Week {
        let orderedWeekdays = localeWeekdayOrder(calendar: calendar)
        let sourceDays = week?.days ?? []
        var buckets: [Int: Day] = [:]

        for (offset, day) in sourceDays.enumerated() {
            let weekday = weekdayIndex(from: day.title, calendar: calendar)
                ?? orderedWeekdays[offset % orderedWeekdays.count]
            let normalized = Day(
                title: weekdayLabel(for: weekday, calendar: calendar),
                type: day.type,
                items: deduplicatedItems(day.items)
            )

            if let existing = buckets[weekday] {
                buckets[weekday] = mergeDays(existing, normalized, weekday: weekday, calendar: calendar)
            } else {
                buckets[weekday] = normalized
            }
        }

        let normalizedDays: [Day] = orderedWeekdays.map { weekday in
            if let existing = buckets[weekday] {
                return Day(
                    title: weekdayLabel(for: weekday, calendar: calendar),
                    type: existing.type,
                    items: deduplicatedItems(existing.items)
                )
            }
            return Day(
                title: weekdayLabel(for: weekday, calendar: calendar),
                type: .rest,
                items: []
            )
        }

        let title = week?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Week(
            title: title?.isEmpty == false ? title! : "Week 1",
            days: normalizedDays
        )
    }

    private static func mergeDays(_ primary: Day,
                                  _ secondary: Day,
                                  weekday: Int,
                                  calendar: Calendar) -> Day {
        let mergedItems = deduplicatedItems(primary.items + secondary.items)
        var mergedType = preferredDayType(primary: primary.type, secondary: secondary.type)
        if !mergedItems.isEmpty && (mergedType == .rest || mergedType == .activeRecovery) {
            mergedType = firstTrainingType(from: [primary.type, secondary.type]) ?? .fullBodyStrength
        }
        return Day(
            title: weekdayLabel(for: weekday, calendar: calendar),
            type: mergedType,
            items: mergedItems
        )
    }

    private static func preferredDayType(primary: DayType, secondary: DayType) -> DayType {
        if primary == .rest || primary == .activeRecovery {
            if secondary != .rest && secondary != .activeRecovery {
                return secondary
            }
        }
        if secondary == .rest || secondary == .activeRecovery {
            return primary
        }
        return primary
    }

    private static func firstTrainingType(from values: [DayType]) -> DayType? {
        values.first(where: { $0 != .rest && $0 != .activeRecovery })
    }

    private static func deduplicatedItems(_ items: [Item]) -> [Item] {
        var seen: Set<String> = []
        var result: [Item] = []
        for item in items {
            let key = itemDedupKey(item)
            if seen.insert(key).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func itemDedupKey(_ item: Item) -> String {
        let name = normalizedToken(item.name)
        let sets = item.sets.map(String.init) ?? ""
        let reps = item.reps.map(String.init) ?? ""
        let weight = normalizedToken(item.suggestedWeight ?? "")
        let distance = item.distance.map { String(format: "%.2f", $0) } ?? ""
        let unit = normalizedToken(item.distanceUnit ?? "")
        let pace = normalizedToken(item.pace ?? "")
        let duration = item.durationMinutes.map(String.init) ?? ""
        let effort = normalizedToken(item.effort ?? "")
        return "\(name)|\(sets)|\(reps)|\(weight)|\(distance)|\(unit)|\(pace)|\(duration)|\(effort)"
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func localeWeekdayOrder(calendar: Calendar) -> [Int] {
        let firstWeekday = calendar.firstWeekday
        return (0..<7).map { ((firstWeekday - 1 + $0) % 7) + 1 }
    }

    private static func weekdayLabel(for weekday: Int, calendar: Calendar) -> String {
        let symbols = calendar.shortWeekdaySymbols
        let index = max(0, min(6, weekday - 1))
        return symbols.indices.contains(index) ? symbols[index] : "Day \(weekday)"
    }

    private static func weekdayIndex(from title: String, calendar: Calendar) -> Int? {
        let lowered = title.lowercased()
        let normalized = lowered.replacingOccurrences(of: "[^a-z]", with: " ", options: .regularExpression)
        let compact = lowered.replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
        let tokens = Set(normalized.split(separator: " ").map(String.init))

        for idx in 0..<7 {
            let full = normalizedDayToken(calendar.weekdaySymbols[idx])
            let short = normalizedDayToken(calendar.shortWeekdaySymbols[idx])
            if tokens.contains(full) || tokens.contains(short) || compact.contains(full) || compact.contains(short) {
                return idx + 1
            }
        }

        let fallback: [(String, Int)] = [
            ("sun", 1), ("sunday", 1),
            ("mon", 2), ("monday", 2),
            ("tue", 3), ("tues", 3), ("tuesday", 3),
            ("wed", 4), ("wednesday", 4),
            ("thu", 5), ("thur", 5), ("thurs", 5), ("thursday", 5),
            ("fri", 6), ("friday", 6),
            ("sat", 7), ("saturday", 7)
        ]
        for (token, weekday) in fallback where tokens.contains(token) || compact.contains(token) {
            return weekday
        }
        return nil
    }

    private static func normalizedDayToken(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z]", with: "", options: .regularExpression)
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private static func stringValue(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let double = Double(string) { return double }
        return nil
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

    // Tool calling removed
}
