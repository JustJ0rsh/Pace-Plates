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
    // Reused session to prewarm once and reduce latency
    private var basicSession: LanguageModelSession? = nil
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
            // Do not include previous conversation context in Ask to minimize tokens
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        // Use a fresh, ephemeral session to avoid context accumulation
                        let session: LanguageModelSession = await MainActor.run {
                            let s = LanguageModelSession(
                                instructions: "You are a concise fitness/nutrition coach. Keep answers short, safe, and practical."
                            )
                            s.prewarm()
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
                        // Use proper Foundation Models API for conversation mode
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                print("🎯 Conversation: Using Foundation Models streamResponse() API for prompt: \(safePrompt.prefix(100))...")

                                let stream = session.streamResponse(
                                    to: safePrompt,
                                    options: GenerationOptions(sampling: .greedy)
                                )

                                var lastSnapshot = ""
                                var hasStreamedContent = false
                                for try await partial in stream {
                                    if Task.isCancelled { break }
                                    let snapshot = partial.content
                                    guard !snapshot.isEmpty else { continue }
                                    let delta: String
                                    if snapshot.hasPrefix(lastSnapshot) {
                                        delta = String(snapshot.dropFirst(lastSnapshot.count))
                                    } else {
                                        delta = snapshot
                                    }
                                    guard !delta.isEmpty else { continue }
                                    hasStreamedContent = true
                                    continuation.yield(delta)
                                    lastSnapshot = snapshot
                                }

                                if !hasStreamedContent {
                                    // Fallback if no partial snapshots arrived.
                                    let response = try await session.respond(
                                        to: safePrompt,
                                        options: GenerationOptions(sampling: .greedy)
                                    )
                                    let fallbackText = response.content
                                    if !fallbackText.isEmpty {
                                        continuation.yield(fallbackText)
                                    }
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
            return generatePlanStream(request: request)
            #endif
        }
        #endif
        return generatePlanStream(request: request)
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
                            s.prewarm()
                            return s
                        }

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
                                    userStats: userStats
                                )

                            // Web search/tool calls removed
                            case .ask:
                                let equipment = UserDefaults.standard.string(forKey: "userEquipment")
                                prompt = AIPromptBuilder.buildConversationPrompt(
                                    goal: request.goal,
                                    question: request.extraContext,
                                    weightUnit: request.weightUnit,
                                    distanceUnit: request.distanceUnit,
                                    userStats: userStats,
                                    equipment: equipment
                                )

                            // Web search/tool calls removed
                        }

                        // Use proper Foundation Models API with guided generation
                        #if canImport(FoundationModels)
                        if #available(iOS 26, *) {
                            do {
                                let safePrompt = Self.clampPrompt(prompt)
                                print("🎯 Using Foundation Models streamResponse() API for prompt: \(safePrompt.prefix(100))...")

                                let stream = session.streamResponse(
                                    to: safePrompt,
                                    options: GenerationOptions(sampling: .greedy)
                                )

                                var lastSnapshot = ""
                                var hasStreamedContent = false
                                for try await partial in stream {
                                    if Task.isCancelled { break }
                                    let snapshot = partial.content
                                    guard !snapshot.isEmpty else { continue }
                                    let delta: String
                                    if snapshot.hasPrefix(lastSnapshot) {
                                        delta = String(snapshot.dropFirst(lastSnapshot.count))
                                    } else {
                                        delta = snapshot
                                    }
                                    guard !delta.isEmpty else { continue }
                                    hasStreamedContent = true
                                    continuation.yield(delta)
                                    lastSnapshot = snapshot
                                }

                                if !hasStreamedContent {
                                    let response = try await session.respond(
                                        to: safePrompt,
                                        options: GenerationOptions(sampling: .greedy)
                                    )
                                    let fallbackText = response.content
                                    if fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        throw NSError(
                                            domain: "WorkoutPlanGenerator",
                                            code: -2,
                                            userInfo: [NSLocalizedDescriptionKey: "AI generated empty response"]
                                        )
                                    }
                                    continuation.yield(fallbackText)
                                }

                                continuation.finish()
                                return
                            } catch {
                                print("❌ Foundation Models streaming failed: \(error.localizedDescription)")
                                print("📋 Error details: \(error)")

                                // Show user-friendly error message
                                let errorMessage = error.localizedDescription
                                if errorMessage.contains("empty response") {
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

                                continuation.yield("⚠️ **Generation Failed**\n\n")
                                continuation.yield("Unable to complete AI generation: \(errorMessage)\n\n")
                                continuation.yield("Please try again or reset the model context.")
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
            userStats: userStats
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

    // Tool calling removed
}
