import Foundation
import SwiftData
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class RunAssistantAIService {
    static let shared = RunAssistantAIService()

    struct PlanDraft {
        var name: String
        var style: String
        var targetDistanceMeters: Double
        var primaryGoal: String
        var durationWeeks: Int
        var daysPerWeek: Int
        var prompt: String
        var sessions: [RunPlanSessionBlueprint]
    }

    enum AIError: Error, LocalizedError {
        case unavailable(String)
        case invalidResponse
        case invalidSchema(String)
        case saveFailed
        case activationFailed

        var errorDescription: String? {
            switch self {
            case let .unavailable(message):
                return message
            case .invalidResponse:
                return "The generated response could not be parsed as plan JSON."
            case let .invalidSchema(message):
                return message
            case .saveFailed:
                return "The running plan couldn’t be saved. Please try again."
            case .activationFailed:
                return "The running plan was saved, but it couldn’t be activated. Please try starting it again."
            }
        }
    }

    private init() {}

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private var hasPrewarmedSession = false

    @available(iOS 26, *)
    private static func generationOptions(
        sampling: GenerationOptions.SamplingMode,
        temperature: Double
    ) -> GenerationOptions {
        #if compiler(>=6.4)
        return GenerationOptions(
            samplingMode: sampling,
            temperature: temperature
        )
        #else
        return GenerationOptions(
            sampling: sampling,
            temperature: temperature
        )
        #endif
    }
    #endif

    func canGenerate() -> Bool {
        AIProviderManager.currentStatus().canGenerateNow
    }

    func prewarmIfPossible() {
        guard AIProviderManager.currentStatus().canGenerateNow else {
            return
        }

        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            guard !hasPrewarmedSession else { return }
            let session = LanguageModelSession(
                instructions: """
                You are a running coach that creates safe, progressive training plans.
                Follow the provided schema exactly.
                Keep notes concise, practical, and non-medical.
                """
            )
            session.prewarm()
            hasPrewarmedSession = true
            #endif
        }
        #endif
    }

    func generateDraft(
        style: String,
        profile: RunAssistantProfile,
        context: ModelContext,
        onStreamChunk: (@MainActor (String) -> Void)? = nil
    ) async throws -> PlanDraft {
        let status = AIProviderManager.currentStatus()
        guard status.canGenerateNow else {
            throw AIError.unavailable(status.unavailableDescription)
        }

        let detailedPrompt = await buildPrompt(style: style, profile: profile, context: context, compact: false)
        var promptUsed = detailedPrompt

        prewarmIfPossible()

        let decoded: AIRunPlanPayload
        do {
            decoded = try await generatePayload(
                prompt: detailedPrompt,
                providerStatus: status,
                onStreamChunk: onStreamChunk
            )
        } catch {
            if isModelContextOverflow(error) {
                let compactPrompt = await buildPrompt(style: style, profile: profile, context: context, compact: true)
                promptUsed = compactPrompt
                do {
                    decoded = try await generatePayload(
                        prompt: compactPrompt,
                        providerStatus: status,
                        onStreamChunk: onStreamChunk
                    )
                } catch {
                    if isModelContextOverflow(error) {
                        let fallback = fallbackDraft(style: style, profile: profile, prompt: compactPrompt, context: context)
                        return applyPaceGoalProgression(fallback, profile: profile, context: context)
                    }
                    throw error
                }
            } else {
                throw error
            }
        }

        let normalized = normalizePayload(decoded, profile: profile)
        try validate(payload: normalized)
        let baseDraft = draftFromPayload(normalized, prompt: promptUsed)
        return applyPaceGoalProgression(baseDraft, profile: profile, context: context)
    }

    @discardableResult
    func saveDraft(
        _ draft: PlanDraft,
        profile: RunAssistantProfile,
        context: ModelContext,
        activate: Bool
    ) throws -> RunningPlan {
        let startDate = Calendar.current.startOfDay(for: Date())
        let plan = RunningPlan(
            name: draft.name,
            source: "ai",
            style: draft.style,
            targetDistanceMeters: draft.targetDistanceMeters,
            primaryGoal: draft.primaryGoal,
            durationWeeks: draft.durationWeeks,
            daysPerWeek: draft.daysPerWeek,
            startDate: startDate,
            isActive: false,
            isArchived: false,
            createdAt: Date(),
            updatedAt: Date(),
            profileSnapshotJSON: profile.asJSONString(),
            aiPrompt: draft.prompt
        )
        context.insert(plan)

        for item in draft.sessions.sorted(by: { lhs, rhs in
            if lhs.weekIndex == rhs.weekIndex {
                if lhs.scheduledWeekday == rhs.scheduledWeekday {
                    return lhs.dayIndex < rhs.dayIndex
                }
                return lhs.scheduledWeekday < rhs.scheduledWeekday
            }
            return lhs.weekIndex < rhs.weekIndex
        }) {
            let session = RunningPlanSession(
                plan: plan,
                weekIndex: item.weekIndex,
                dayIndex: item.dayIndex,
                scheduledDate: scheduledDate(startDate: plan.startDate, weekOffset: item.weekIndex, weekday: item.scheduledWeekday),
                sessionType: item.sessionType,
                targetDistanceMeters: item.targetDistanceMeters,
                targetDurationSeconds: item.targetDurationSeconds,
                targetPaceMinPerMile: item.targetPaceMinPerMile,
                intensityLevel: item.intensityLevel,
                notes: item.notes,
                status: "pending"
            )
            context.insert(session)
        }

        guard PersistenceSave.commit(context, action: "save running plan") else {
            context.rollback()
            throw AIError.saveFailed
        }

        if activate {
            guard RunAssistantService.shared.setActivePlan(plan.id, context: context) else {
                throw AIError.activationFailed
            }
        }

        return plan
    }

    // MARK: - Prompting

    private func buildPrompt(style: String, profile: RunAssistantProfile, context: ModelContext, compact: Bool) async -> String {
        let runs = ((try? context.fetch(FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\RunningSession.date, order: .reverse)]))) ?? [])
        let recentRuns = Array(runs.prefix(24)).filter { $0.duration > 0 && $0.distance > 0 }
        let calendar = Calendar.current

        let weights = ((try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\WeightEntry.date, order: .reverse)]))) ?? [])
        let latestWeight = weights.first

        let recentCount = recentRuns.count
        let totalDistanceMiles = recentRuns.reduce(0.0) { $0 + miles(for: $1) }
        let totalDurationMinutes = recentRuns.reduce(0.0) { $0 + ($1.duration / 60.0) }
        let longestRunMiles = recentRuns.map { miles(for: $0) }.max()
        let paceValues = recentRuns.compactMap { paceMinPerMile(for: $0) }
        let medianPace = median(paceValues)
        let fastestPace = paceValues.min()
        let avgHeartRate = average(recentRuns.compactMap(\.avgHeartRate))
        let avgCadence = average(recentRuns.compactMap(\.avgCadence))
        let avgAscent = average(recentRuns.compactMap(\.totalAscent))
        let localActivityMix = activityMixSummary(from: recentRuns)

        let start4Weeks = calendar.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let runs4Weeks = runs.filter { $0.date >= start4Weeks && $0.duration > 0 && $0.distance > 0 }
        let miles4Weeks = runs4Weeks.reduce(0.0) { $0 + miles(for: $1) }
        let avgWeeklyMiles = miles4Weeks / 4.0
        let activeDays4Weeks = Set(runs4Weeks.map { calendar.startOfDay(for: $0.date) }).count

        let daysPerWeek = max(1, min(profile.daysPerWeek, 7))
        let longRunWeekday = max(1, min(profile.longRunWeekday, 7))
        let target = Int(profile.targetDistanceMiles.rounded())

        let profileDeltaPace: String = {
            let delta = profile.paceGoalMinPerMile - profile.currentAveragePaceMinPerMile
            if !delta.isFinite { return "n/a" }
            let sign = delta <= 0 ? "faster" : "slower"
            return "\(String(format: "%.2f", abs(delta))) min/mi \(sign)"
        }()

        var hkSummary = "HealthKit unavailable"
        if HKHealthStore.isHealthDataAvailable() {
            async let hkRunsTask = (try? await HealthKitManager.shared.fetchRecentRuns(limit: 24)) ?? []
            async let hkWeightTask = try? await HealthKitManager.shared.getBodyWeight()
            let hkRuns = await hkRunsTask
            let hkWeight = await hkWeightTask

            let hkDurationMinutes = hkRuns.reduce(0.0) { $0 + ($1.duration / 60.0) }
            #if canImport(HealthKit)
            let hkDistanceMiles = hkRuns.reduce(0.0) { $0 + hkMiles(for: $1) }
            let hkMix = hkActivityMixSummary(from: hkRuns)
            #else
            let hkDistanceMiles = 0.0
            let hkMix = "n/a"
            #endif

            hkSummary = """
            HealthKit cardio workouts: \(hkRuns.count), total distance: \(String(format: "%.1f", hkDistanceMiles)) mi, total duration: \(Int(hkDurationMinutes.rounded())) min, activity mix: [\(hkMix)], body weight (lb): \(hkWeight.map { String(format: "%.1f", $0) } ?? "n/a")
            """
        }

        if compact {
            return """
Create a progressive running plan.
Follow the app schema exactly.

STYLE: \(style)
TARGET: \(target) mile(s)
ABILITY: \(profile.abilityLevel)
DAYS_PER_WEEK: \(daysPerWeek)
LONG_RUN_WEEKDAY: \(longRunWeekday)
PRIMARY_GOAL: \(profile.goalFocus)
CURRENT_AVERAGE_PACE_MIN_PER_MILE: \(String(format: "%.2f", profile.currentAveragePaceMinPerMile))
PACE_GOAL_MIN_PER_MILE: \(String(format: "%.2f", profile.paceGoalMinPerMile))
LOCAL_LAST_4_WEEKS_MILES: \(String(format: "%.1f", miles4Weeks))
LOCAL_AVG_WEEKLY_MILES: \(String(format: "%.1f", avgWeeklyMiles))
LOCAL_MEDIAN_PACE: \(formatPace(medianPace))
LOCAL_ACTIVITY_MIX: \(localActivityMix)
HK: \(hkSummary)

Rules:
- durationWeeks should be between 6 and 12.
- Use weeks 0...(durationWeeks-1).
- Include exactly 7 sessions per week (weekday 1...7 exactly once).
- Include exactly DAYS_PER_WEEK non-rest sessions per week.
- Keep one long run on LONG_RUN_WEEKDAY when possible.
- Use concise notes (max 1 short sentence).
"""
        }

        return """
Create a progressive running plan for a couch-to-distance assistant.
Use the response schema provided by the app.

STYLE: \(style)
TARGET: \(target) mile(s)
ABILITY: \(profile.abilityLevel)
DAYS_PER_WEEK: \(daysPerWeek)
LONG_RUN_WEEKDAY: \(longRunWeekday)
PRIMARY_GOAL: \(profile.goalFocus)
CURRENT_AVERAGE_PACE_MIN_PER_MILE: \(String(format: "%.2f", profile.currentAveragePaceMinPerMile))
PACE_GOAL_MIN_PER_MILE: \(String(format: "%.2f", profile.paceGoalMinPerMile))

RUNNING_PROFILE_CONTEXT:
- Goal focus: \(profile.goalFocus)
- Ability level: \(profile.abilityLevel)
- Days per week preference: \(daysPerWeek)
- Long run day preference: \(weekdayAbbreviation(longRunWeekday))
- Current profile pace: \(String(format: "%.2f", profile.currentAveragePaceMinPerMile)) min/mi
- Target profile pace: \(String(format: "%.2f", profile.paceGoalMinPerMile)) min/mi
- Pace delta to goal: \(profileDeltaPace)

LOCAL_CARDIO_CONTEXT:
- Local cardio sessions analyzed: \(recentCount)
- Local total distance: \(String(format: "%.1f", totalDistanceMiles)) mi
- Local total duration: \(Int(totalDurationMinutes.rounded())) min
- Local longest session: \(longestRunMiles.map { String(format: "%.2f mi", $0) } ?? "n/a")
- Local median pace: \(formatPace(medianPace))
- Local fastest pace: \(formatPace(fastestPace))
- Local avg heart rate: \(avgHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "n/a")
- Local avg cadence: \(avgCadence.map { "\(Int($0.rounded())) spm" } ?? "n/a")
- Local avg ascent: \(avgAscent.map { "\(Int($0.rounded())) m" } ?? "n/a")
- Local activity mix: \(localActivityMix)
- Last 4 weeks total distance: \(String(format: "%.1f", miles4Weeks)) mi
- Last 4 weeks average weekly distance: \(String(format: "%.1f", avgWeeklyMiles)) mi
- Last 4 weeks active run days: \(activeDays4Weeks)

BODY_CONTEXT:
- Latest local weight: \(latestWeight.map { String(format: "%.1f \($0.weightUnit)", $0.weight) } ?? "n/a")
- \(hkSummary)

Rules:
- Use weeks 0...(durationWeeks-1)
- Keep durationWeeks between 6 and 12 unless user profile clearly requires otherwise.
- Include only weekday values 1..7
- Include exactly DAYS_PER_WEEK non-rest sessions per week.
- Fill all non-training weekdays with rest sessions so each week has all 7 days.
- Spread non-rest sessions across the week and avoid clustering all training at the start of the week.
- Keep one long run on LONG_RUN_WEEKDAY whenever possible.
- Include progression with occasional deload and final taper/test week
- Use realistic distances/paces for ability level
- Start week 1 paces near CURRENT_AVERAGE_PACE_MIN_PER_MILE before progressing.
- Week over week, push pace slightly faster (harder sessions first) toward the pace goal.
- Keep easy/recovery slower than tempo/interval while still trending faster over the plan.
"""
    }

    private func isModelContextOverflow(_ error: Error) -> Bool {
        let details = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        let markers = [
            "context size",
            "context window",
            "maximum context",
            "model context",
            "prompt is too long",
            "input is too long",
            "exceeds context"
        ]
        return markers.contains(where: { details.contains($0) })
    }

    private func miles(for run: RunningSession) -> Double {
        run.distanceUnit == "mi" ? run.distance : run.distance / 1.60934
    }

    private func paceMinPerMile(for run: RunningSession) -> Double? {
        let milesValue = miles(for: run)
        guard milesValue > 0, run.duration > 0 else { return nil }
        return (run.duration / 60.0) / milesValue
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0.0, +)
        return sum / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            return (sorted[upper - 1] + sorted[upper]) / 2.0
        }
        return sorted[sorted.count / 2]
    }

    private func activityMixSummary(from runs: [RunningSession]) -> String {
        guard !runs.isEmpty else { return "n/a" }
        let grouped = Dictionary(grouping: runs) { run in
            let cleaned = run.activityType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return cleaned.isEmpty ? "running" : cleaned
        }
        let ordered = grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.count ?? 0
            let right = grouped[rhs]?.count ?? 0
            if left == right { return lhs < rhs }
            return left > right
        }
        return ordered.prefix(4).map { key in
            "\(key): \(grouped[key]?.count ?? 0)"
        }.joined(separator: ", ")
    }

    #if canImport(HealthKit)
    private func hkMiles(for workout: HKWorkout) -> Double {
        HealthKitManager.recordedDistanceMeters(for: workout) / 1609.34
    }

    private func hkActivityLabel(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairs"
        default: return "other"
        }
    }

    private func hkActivityMixSummary(from workouts: [HKWorkout]) -> String {
        guard !workouts.isEmpty else { return "n/a" }
        let grouped = Dictionary(grouping: workouts) { hkActivityLabel($0.workoutActivityType) }
        let ordered = grouped.keys.sorted { lhs, rhs in
            let left = grouped[lhs]?.count ?? 0
            let right = grouped[rhs]?.count ?? 0
            if left == right { return lhs < rhs }
            return left > right
        }
        return ordered.prefix(4).map { key in
            "\(key): \(grouped[key]?.count ?? 0)"
        }.joined(separator: ", ")
    }
    #endif

    private func goalForStyle(_ style: String) -> String {
        if style.contains("speed") { return "speed" }
        if style.contains("endurance") { return "endurance" }
        return "hybrid"
    }

    private func defaultDistanceMiles(
        sessionType: String,
        weekIndex: Int,
        durationWeeks: Int,
        profile: RunAssistantProfile
    ) -> Double {
        let base = max(0.8, profile.targetDistanceMiles / Double(max(profile.daysPerWeek, 1)))
        let progress = durationWeeks <= 1 ? 0.0 : Double(weekIndex) / Double(durationWeeks - 1)
        let scale: Double
        switch sessionType {
        case "interval": scale = 0.9
        case "tempo": scale = 1.0
        case "long": scale = 1.5
        case "recovery": scale = 0.75
        default: scale = 1.0
        }
        return max(0.4, (base * scale) * (0.9 + (0.25 * progress)))
    }

    private func defaultSessionNote(for sessionType: String, index: Int) -> String {
        switch sessionType {
        case "interval":
            return index.isMultiple(of: 2) ? "Keep recoveries controlled between reps." : "Focus on even splits and strong form."
        case "tempo":
            return index.isMultiple(of: 2) ? "Run comfortably hard, avoid sprinting early." : "Stay steady and finish with good posture."
        case "long":
            return "Keep effort easy and conversational."
        case "recovery":
            return "Very easy effort to absorb training load."
        case "easy":
            return index.isMultiple(of: 2) ? "Relaxed pace, light stride." : "Smooth aerobic effort with controlled breathing."
        default:
            return "Complete this session at the planned effort."
        }
    }

    private func generatePayload(
        prompt: String,
        providerStatus: AIProviderStatus,
        onStreamChunk: (@MainActor (String) -> Void)?
    ) async throws -> AIRunPlanPayload {
        try await generateGuidedPayload(prompt: prompt, onStreamChunk: onStreamChunk)
    }

    private func generateGuidedPayload(
        prompt: String,
        onStreamChunk: (@MainActor (String) -> Void)?
    ) async throws -> AIRunPlanPayload {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let session = LanguageModelSession(
                instructions: """
                You are a running coach that creates safe, progressive training plans.
                Follow the provided schema exactly.
                Keep notes concise, practical, and non-medical.
                """
            )
            var previousPreview = ""
            var emittedPreview = ""
            var streamedAny = false
            var lastRawContent: GeneratedContent? = nil

            let stream = session.streamResponse(
                to: prompt,
                generating: AIRunPlanGeneratedPayload.self,
                options: Self.generationOptions(
                    sampling: .random(probabilityThreshold: 0.70),
                    temperature: 0.30
                )
            )

            for try await snapshot in stream {
                if Task.isCancelled { throw CancellationError() }
                lastRawContent = snapshot.rawContent

                guard let onStreamChunk else { continue }
                let preview = runPlanStreamPreview(from: snapshot.rawContent, fallback: previousPreview)
                let delta = AIStreamSmoothing.appendableDelta(previous: emittedPreview, current: preview)
                previousPreview = preview
                guard !delta.isEmpty else { continue }

                streamedAny = true
                emittedPreview += delta
                for piece in AIStreamSmoothing.wordChunked(delta, maxChunkChars: 50) {
                    onStreamChunk(piece)
                }
            }

            guard let lastRawContent else { throw AIError.invalidResponse }
            if let onStreamChunk, !streamedAny, !previousPreview.isEmpty {
                onStreamChunk(previousPreview)
            }

            let generated = try AIRunPlanGeneratedPayload(lastRawContent)
            return payloadFromGenerated(generated)
            #else
            throw AIError.unavailable("Apple Intelligence is not available in this build.")
            #endif
        }
        #endif
        throw AIError.unavailable("Apple Intelligence is not available on this device.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func runPlanStreamPreview(from rawContent: GeneratedContent, fallback: String) -> String {
        guard let data = rawContent.jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fallback
        }

        let durationWeeks = max(1, min(intValue(root["durationWeeks"]) ?? 1, 24))
        var lines: [String] = []
        let planName = stringValue(root["planName"])
        if !planName.isEmpty {
            lines.append(planName)
        } else {
            lines.append("Generating running plan...")
        }

        var summaryParts: [String] = []
        summaryParts.append("\(durationWeeks) weeks")
        let style = stringValue(root["style"])
        if !style.isEmpty {
            summaryParts.append(style.replacingOccurrences(of: "_", with: " ").capitalized)
        }
        if let daysPerWeek = intValue(root["daysPerWeek"]) {
            summaryParts.append("\(daysPerWeek) days/week")
        }
        if !summaryParts.isEmpty {
            lines.append(summaryParts.joined(separator: " • "))
            lines.append("")
        }

        if let sessionsValue = arrayValue(root["sessions"]) {
            var bucketed: [Int: [Int: [StreamPreviewSession]]] = [:]
            var renderedAnySession = false

            for value in sessionsValue {
                guard let parsed = parsePreviewSession(value) else { continue }
                let session = normalizedPreviewSession(parsed, durationWeeks: durationWeeks)
                bucketed[session.weekIndex, default: [:]][session.weekday, default: []].append(session)
            }

            let orderedWeeks = bucketed.keys.sorted()
            for week in orderedWeeks {
                if renderedAnySession {
                    lines.append("")
                }
                lines.append("Week \(week + 1)")

                let dayBuckets = bucketed[week] ?? [:]
                let orderedDays = dayBuckets.keys.sorted()
                for weekday in orderedDays {
                    guard let candidates = dayBuckets[weekday],
                          let selected = preferredPreviewSession(from: candidates) else { continue }

                    lines.append(previewLine(for: selected))
                    renderedAnySession = true

                    if let note = selected.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        lines.append("  \(note)")
                    }
                }
            }

            if !renderedAnySession {
                lines.append("Building week-by-week sessions...")
            }
        }

        let rendered = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? fallback : rendered
    }
    #endif

    private func runPlanPreview(from payload: AIRunPlanPayload) -> String {
        var lines: [String] = []
        lines.append(payload.planName)
        lines.append("\(payload.durationWeeks) weeks • \(payload.primaryGoal.capitalized) • \(payload.daysPerWeek) days/week")
        lines.append("")

        let sortedSessions = payload.sessions.sorted {
            if $0.weekIndex == $1.weekIndex {
                return $0.weekday < $1.weekday
            }
            return $0.weekIndex < $1.weekIndex
        }

        for session in sortedSessions.prefix(14) {
            let week = session.weekIndex + 1
            let weekday = weekdayAbbreviation(session.weekday)
            var line = "Week \(week) • \(weekday) • \(session.sessionType.capitalized)"
            if let miles = session.targetDistanceMiles, miles > 0 {
                line += " • \(String(format: "%.1f", miles)) mi"
            }
            if let minutes = session.targetDurationMinutes, minutes > 0 {
                line += " • \(Int(minutes.rounded())) min"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }

    private func normalizePayload(_ payload: AIRunPlanPayload, profile: RunAssistantProfile) -> AIRunPlanPayload {
        var normalized = payload
        normalized.durationWeeks = max(1, min(payload.durationWeeks, 24))
        normalized.daysPerWeek = max(1, min(profile.daysPerWeek, 7))
        normalized.targetDistanceMiles = max(payload.targetDistanceMiles, max(1.0, profile.targetDistanceMiles))

        let validTypes = Set(["easy", "interval", "tempo", "long", "recovery", "rest"])
        let validIntensity = Set(["easy", "moderate", "hard"])
        let baselinePace = (profile.currentAveragePaceMinPerMile.isFinite && profile.currentAveragePaceMinPerMile > 0)
            ? profile.currentAveragePaceMinPerMile
            : 12.0

        let cleanedSessions = payload.sessions.enumerated().map { index, item in
            var session = item
            session.weekIndex = max(0, min(item.weekIndex, normalized.durationWeeks - 1))
            session.weekday = max(1, min(item.weekday, 7))

            if !validTypes.contains(session.sessionType) {
                session.sessionType = "easy"
            }
            if !validIntensity.contains(session.intensityLevel) {
                session.intensityLevel = session.sessionType == "interval" || session.sessionType == "tempo" ? "hard" : "easy"
            }

            if session.sessionType == "rest" {
                session.targetDistanceMiles = nil
                session.targetDurationMinutes = nil
                session.targetPaceMinPerMile = nil
                session.intensityLevel = "easy"
                session.notes = "Rest day"
                return session
            }

            let distanceMiles = (session.targetDistanceMiles ?? 0) > 0
                ? (session.targetDistanceMiles ?? 0)
                : defaultDistanceMiles(
                    sessionType: session.sessionType,
                    weekIndex: session.weekIndex,
                    durationWeeks: normalized.durationWeeks,
                    profile: profile
                )
            session.targetDistanceMiles = max(0.4, distanceMiles)

            if let pace = session.targetPaceMinPerMile {
                session.targetPaceMinPerMile = pace.isFinite && pace > 0 ? min(max(pace, 5.0), 20.0) : nil
            }

            let paceForDuration = session.targetPaceMinPerMile ?? baselinePace
            if (session.targetDurationMinutes ?? 0) <= 0 {
                session.targetDurationMinutes = max(12, (session.targetDistanceMiles ?? 1.0) * paceForDuration)
            }

            let cleanedNote = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedNote?.isEmpty ?? true {
                session.notes = defaultSessionNote(for: session.sessionType, index: index)
            } else {
                session.notes = cleanedNote
            }
            return session
        }

        var seenSessionKeys: Set<String> = []
        let deduplicated = cleanedSessions
            .sorted(by: { lhs, rhs in
                if lhs.weekIndex == rhs.weekIndex {
                    if lhs.weekday == rhs.weekday {
                        if lhs.sessionType == rhs.sessionType {
                            return (lhs.targetDistanceMiles ?? 0) > (rhs.targetDistanceMiles ?? 0)
                        }
                        return sessionTypeRank(lhs.sessionType) < sessionTypeRank(rhs.sessionType)
                    }
                    return lhs.weekday < rhs.weekday
                }
                return lhs.weekIndex < rhs.weekIndex
            })
            .filter { session in
                let key = sessionDedupKey(session)
                return seenSessionKeys.insert(key).inserted
            }

        let coveredSessions = ensureWeekdayCoverage(
            sessions: deduplicated,
            durationWeeks: normalized.durationWeeks
        )
        normalized.sessions = alignSessionsToProfileWeekdays(
            sessions: coveredSessions,
            durationWeeks: normalized.durationWeeks,
            profile: profile
        )
        return normalized
    }

    private func sessionDedupKey(_ session: AIRunPlanPayload.Session) -> String {
        let distance = session.targetDistanceMiles.map { String(format: "%.2f", $0) } ?? "nil"
        let duration = session.targetDurationMinutes.map { String(format: "%.2f", $0) } ?? "nil"
        let pace = session.targetPaceMinPerMile.map { String(format: "%.2f", $0) } ?? "nil"
        return "\(session.weekIndex)|\(session.weekday)|\(session.sessionType)|\(distance)|\(duration)|\(pace)"
    }

    private func ensureWeekdayCoverage(
        sessions: [AIRunPlanPayload.Session],
        durationWeeks: Int
    ) -> [AIRunPlanPayload.Session] {
        var bucketed: [Int: [Int: [AIRunPlanPayload.Session]]] = [:]
        for session in sessions {
            bucketed[session.weekIndex, default: [:]][session.weekday, default: []].append(session)
        }

        var result: [AIRunPlanPayload.Session] = []
        for week in 0..<durationWeeks {
            for weekday in 1...7 {
                let candidates = bucketed[week]?[weekday] ?? []
                if candidates.isEmpty {
                    result.append(restPlaceholder(weekIndex: week, weekday: weekday))
                } else {
                    result.append(preferredSession(from: candidates))
                }
            }
        }

        return result.sorted(by: { lhs, rhs in
            if lhs.weekIndex == rhs.weekIndex {
                if lhs.weekday == rhs.weekday {
                    return sessionTypeRank(lhs.sessionType) < sessionTypeRank(rhs.sessionType)
                }
                return lhs.weekday < rhs.weekday
            }
            return lhs.weekIndex < rhs.weekIndex
        })
    }

    private func alignSessionsToProfileWeekdays(
        sessions: [AIRunPlanPayload.Session],
        durationWeeks: Int,
        profile: RunAssistantProfile
    ) -> [AIRunPlanPayload.Session] {
        let targetDays = preferredTrainingWeekdays(
            daysPerWeek: profile.daysPerWeek,
            longRunWeekday: profile.longRunWeekday
        )
        guard !targetDays.isEmpty else { return sessions }

        let baselinePace = (profile.currentAveragePaceMinPerMile.isFinite && profile.currentAveragePaceMinPerMile > 0)
            ? profile.currentAveragePaceMinPerMile
            : 12.0

        var bucketed: [Int: [Int: [AIRunPlanPayload.Session]]] = [:]
        for session in sessions {
            bucketed[session.weekIndex, default: [:]][session.weekday, default: []].append(session)
        }

        var output: [AIRunPlanPayload.Session] = []
        let trainingCount = min(max(1, profile.daysPerWeek), 7)
        let longRunDay = min(max(profile.longRunWeekday, 1), 7)

        for week in 0..<durationWeeks {
            var trainingSessions = (bucketed[week] ?? [:])
                .values
                .compactMap { preferredSession(from: $0) }
                .filter { $0.sessionType != "rest" }

            trainingSessions.sort(by: { lhs, rhs in
                let leftRank = sessionTypeRank(lhs.sessionType)
                let rightRank = sessionTypeRank(rhs.sessionType)
                if leftRank != rightRank { return leftRank < rightRank }

                let leftDistance = lhs.targetDistanceMiles ?? 0
                let rightDistance = rhs.targetDistanceMiles ?? 0
                if leftDistance != rightDistance { return leftDistance > rightDistance }

                return (lhs.targetDurationMinutes ?? 0) > (rhs.targetDurationMinutes ?? 0)
            })

            if trainingSessions.isEmpty {
                trainingSessions.append(
                    fallbackTrainingSession(
                        weekIndex: week,
                        weekday: longRunDay,
                        sessionType: "easy",
                        durationWeeks: durationWeeks,
                        baselinePace: baselinePace,
                        profile: profile,
                        index: 0
                    )
                )
            }

            var selectedTraining = Array(trainingSessions.prefix(trainingCount))
            while selectedTraining.count < trainingCount {
                let nextDay = targetDays[min(selectedTraining.count, targetDays.count - 1)]
                let nextType = nextDay == longRunDay ? "long" : "easy"
                selectedTraining.append(
                    fallbackTrainingSession(
                        weekIndex: week,
                        weekday: nextDay,
                        sessionType: nextType,
                        durationWeeks: durationWeeks,
                        baselinePace: baselinePace,
                        profile: profile,
                        index: selectedTraining.count
                    )
                )
            }

            var assignedByDay: [Int: AIRunPlanPayload.Session] = [:]

            if let longIndex = selectedTraining.firstIndex(where: { $0.sessionType == "long" }),
               targetDays.contains(longRunDay) {
                var longSession = selectedTraining.remove(at: longIndex)
                longSession.weekIndex = week
                longSession.weekday = longRunDay
                assignedByDay[longRunDay] = longSession
            }

            let remainingDays = targetDays.filter { assignedByDay[$0] == nil }
            for (index, day) in remainingDays.enumerated() {
                guard index < selectedTraining.count else { break }
                var session = selectedTraining[index]
                session.weekIndex = week
                session.weekday = day
                assignedByDay[day] = session
            }

            for day in 1...7 {
                if var session = assignedByDay[day] {
                    session.targetDistanceMiles = max(0.4, session.targetDistanceMiles ?? defaultDistanceMiles(
                        sessionType: session.sessionType,
                        weekIndex: week,
                        durationWeeks: durationWeeks,
                        profile: profile
                    ))
                    if (session.targetDurationMinutes ?? 0) <= 0 {
                        let pace = session.targetPaceMinPerMile ?? baselinePace
                        session.targetDurationMinutes = max(12, (session.targetDistanceMiles ?? 1.0) * pace)
                    }
                    let note = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if note?.isEmpty ?? true {
                        session.notes = defaultSessionNote(for: session.sessionType, index: day)
                    }
                    output.append(session)
                } else {
                    output.append(restPlaceholder(weekIndex: week, weekday: day))
                }
            }
        }

        return output.sorted(by: { lhs, rhs in
            if lhs.weekIndex == rhs.weekIndex {
                return lhs.weekday < rhs.weekday
            }
            return lhs.weekIndex < rhs.weekIndex
        })
    }

    private func preferredTrainingWeekdays(daysPerWeek: Int, longRunWeekday: Int) -> [Int] {
        let validDays = min(max(daysPerWeek, 1), 7)
        let clampedLong = min(max(longRunWeekday, 1), 7)

        var selected: [Int] = [clampedLong]
        let spreadOrder = [2, 4, 6, 3, 5, 7, 1]
        for day in spreadOrder where day != clampedLong {
            if selected.count >= validDays { break }
            selected.append(day)
        }

        while selected.count < validDays {
            let fallback = ((selected.last ?? 1) % 7) + 1
            if !selected.contains(fallback) {
                selected.append(fallback)
            } else {
                break
            }
        }

        return selected.sorted()
    }

    private func fallbackTrainingSession(
        weekIndex: Int,
        weekday: Int,
        sessionType: String,
        durationWeeks: Int,
        baselinePace: Double,
        profile: RunAssistantProfile,
        index: Int
    ) -> AIRunPlanPayload.Session {
        let type = sessionType == "rest" ? "easy" : sessionType
        let distance = defaultDistanceMiles(
            sessionType: type,
            weekIndex: weekIndex,
            durationWeeks: durationWeeks,
            profile: profile
        )

        let paceOffset: Double
        switch type {
        case "interval": paceOffset = -0.40
        case "tempo": paceOffset = -0.20
        case "easy": paceOffset = 0.60
        case "recovery": paceOffset = 1.00
        case "long": paceOffset = 0.35
        default: paceOffset = 0.60
        }

        let pace = min(max(baselinePace + paceOffset, 5.0), 20.0)
        let duration = max(12, distance * pace)
        let intensity: String = {
            switch type {
            case "interval", "tempo": return "hard"
            case "long": return "moderate"
            default: return "easy"
            }
        }()

        return AIRunPlanPayload.Session(
            weekIndex: weekIndex,
            weekday: weekday,
            sessionType: type,
            targetDistanceMiles: distance,
            targetDurationMinutes: duration,
            targetPaceMinPerMile: pace,
            intensityLevel: intensity,
            notes: defaultSessionNote(for: type, index: index)
        )
    }

    private func preferredSession(from candidates: [AIRunPlanPayload.Session]) -> AIRunPlanPayload.Session {
        candidates.sorted(by: { lhs, rhs in
            let leftRank = sessionTypeRank(lhs.sessionType)
            let rightRank = sessionTypeRank(rhs.sessionType)
            if leftRank != rightRank { return leftRank < rightRank }

            let leftDistance = lhs.targetDistanceMiles ?? 0
            let rightDistance = rhs.targetDistanceMiles ?? 0
            if leftDistance != rightDistance { return leftDistance > rightDistance }

            let leftDuration = lhs.targetDurationMinutes ?? 0
            let rightDuration = rhs.targetDurationMinutes ?? 0
            if leftDuration != rightDuration { return leftDuration > rightDuration }

            return (lhs.notes ?? "") < (rhs.notes ?? "")
        }).first ?? restPlaceholder(weekIndex: 0, weekday: 1)
    }

    private func restPlaceholder(weekIndex: Int, weekday: Int) -> AIRunPlanPayload.Session {
        AIRunPlanPayload.Session(
            weekIndex: weekIndex,
            weekday: weekday,
            sessionType: "rest",
            targetDistanceMiles: nil,
            targetDurationMinutes: nil,
            targetPaceMinPerMile: nil,
            intensityLevel: "easy",
            notes: "Rest day"
        )
    }

    private func sessionTypeRank(_ type: String) -> Int {
        switch type {
        case "long": return 0
        case "interval": return 1
        case "tempo": return 2
        case "easy": return 3
        case "recovery": return 4
        case "rest": return 5
        default: return 6
        }
    }

    private func weekdayAbbreviation(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let index = max(0, min(symbols.count - 1, weekday - 1))
        return symbols.indices.contains(index) ? symbols[index] : "Day \(weekday)"
    }

    private func formatPace(_ minPerMile: Double?) -> String {
        guard let minPerMile else { return "n/a" }
        return formatPace(minPerMile)
    }

    private func formatPace(_ minPerMile: Double) -> String {
        guard minPerMile.isFinite, minPerMile > 0 else { return "--:--/mi" }
        let totalSeconds = Int((minPerMile * 60.0).rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d/mi", mins, secs)
    }

    private struct StreamPreviewSession {
        var weekIndex: Int
        var weekday: Int
        var sessionType: String
        var targetDistanceMiles: Double?
        var targetDurationMinutes: Double?
        var targetPaceMinPerMile: Double?
        var notes: String?
    }

    private func parsePreviewSession(_ value: Any) -> StreamPreviewSession? {
        guard let dictionary = dictionaryValue(value) else { return nil }
        return StreamPreviewSession(
            weekIndex: intValue(dictionary["weekIndex"]) ?? 0,
            weekday: intValue(dictionary["weekday"]) ?? 1,
            sessionType: stringValue(dictionary["sessionType"]).isEmpty ? "easy" : stringValue(dictionary["sessionType"]),
            targetDistanceMiles: doubleValue(dictionary["targetDistanceMiles"]),
            targetDurationMinutes: doubleValue(dictionary["targetDurationMinutes"]),
            targetPaceMinPerMile: doubleValue(dictionary["targetPaceMinPerMile"]),
            notes: stringValue(dictionary["notes"]).isEmpty ? nil : stringValue(dictionary["notes"])
        )
    }

    private func normalizedPreviewSession(_ session: StreamPreviewSession, durationWeeks: Int) -> StreamPreviewSession {
        var normalized = session
        normalized.weekIndex = max(0, min(session.weekIndex, durationWeeks - 1))
        normalized.weekday = max(1, min(session.weekday, 7))

        let validTypes = Set(["easy", "interval", "tempo", "long", "recovery", "rest"])
        if !validTypes.contains(normalized.sessionType) {
            normalized.sessionType = "easy"
        }
        return normalized
    }

    private func preferredPreviewSession(from candidates: [StreamPreviewSession]) -> StreamPreviewSession? {
        candidates.sorted(by: { lhs, rhs in
            let leftRank = sessionTypeRank(lhs.sessionType)
            let rightRank = sessionTypeRank(rhs.sessionType)
            if leftRank != rightRank { return leftRank < rightRank }

            let leftDistance = lhs.targetDistanceMiles ?? 0
            let rightDistance = rhs.targetDistanceMiles ?? 0
            if leftDistance != rightDistance { return leftDistance > rightDistance }

            let leftDuration = lhs.targetDurationMinutes ?? 0
            let rightDuration = rhs.targetDurationMinutes ?? 0
            if leftDuration != rightDuration { return leftDuration > rightDuration }

            return (lhs.notes ?? "") < (rhs.notes ?? "")
        }).first
    }

    private func previewLine(for session: StreamPreviewSession) -> String {
        var line = "\(weekdayAbbreviation(session.weekday)) • \(session.sessionType.capitalized)"
        if let distance = session.targetDistanceMiles {
            line += " • \(String(format: "%.2f", distance)) mi"
        }
        if let duration = session.targetDurationMinutes {
            line += " • \(Int(duration.rounded())) min"
        }
        if let pace = session.targetPaceMinPerMile {
            line += " @ \(formatPace(pace))"
        }
        return line
    }

    private func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func arrayValue(_ value: Any?) -> [Any]? {
        value as? [Any]
    }

    private func stringValue(_ value: Any?) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let int = Int(string) { return int }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String, let double = Double(string) { return double }
        return nil
    }

    private func validate(payload: AIRunPlanPayload) throws {
        if payload.planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIError.invalidSchema("AI plan name is missing.")
        }

        if payload.durationWeeks <= 0 {
            throw AIError.invalidSchema("AI plan must include at least one week.")
        }

        if payload.daysPerWeek < 1 || payload.daysPerWeek > 7 {
            throw AIError.invalidSchema("AI plan daysPerWeek must be between 1 and 7.")
        }

        if payload.sessions.isEmpty {
            throw AIError.invalidSchema("AI plan did not include any sessions.")
        }

        let validTypes = Set(["easy", "interval", "tempo", "long", "recovery", "rest"])
        let validIntensity = Set(["easy", "moderate", "hard"])

        for session in payload.sessions {
            if session.weekIndex < 0 || session.weekIndex >= payload.durationWeeks {
                throw AIError.invalidSchema("AI session weekIndex is out of bounds.")
            }
            if !(1...7).contains(session.weekday) {
                throw AIError.invalidSchema("AI session weekday must be between 1 and 7.")
            }
            if !validTypes.contains(session.sessionType) {
                throw AIError.invalidSchema("AI session type '\(session.sessionType)' is invalid.")
            }
            if !validIntensity.contains(session.intensityLevel) {
                throw AIError.invalidSchema("AI session intensity '\(session.intensityLevel)' is invalid.")
            }
            if session.sessionType != "rest" {
                let hasDistance = (session.targetDistanceMiles ?? 0) > 0
                let hasDuration = (session.targetDurationMinutes ?? 0) > 0
                if !hasDistance || !hasDuration {
                    throw AIError.invalidSchema("AI session targets were incomplete.")
                }
            }
        }
    }

    private func draftFromPayload(_ payload: AIRunPlanPayload, prompt: String) -> PlanDraft {
        let sessions: [RunPlanSessionBlueprint] = payload.sessions.map { item in
            RunPlanSessionBlueprint(
                weekIndex: item.weekIndex,
                dayIndex: item.weekday,
                scheduledWeekday: item.weekday,
                sessionType: item.sessionType,
                targetDistanceMeters: item.targetDistanceMiles.map { $0 * 1609.34 },
                targetDurationSeconds: item.targetDurationMinutes.map { $0 * 60 },
                targetPaceMinPerMile: item.targetPaceMinPerMile,
                intensityLevel: item.intensityLevel,
                notes: item.notes
            )
        }

        return PlanDraft(
            name: payload.planName,
            style: payload.style,
            targetDistanceMeters: payload.targetDistanceMiles * 1609.34,
            primaryGoal: payload.primaryGoal,
            durationWeeks: payload.durationWeeks,
            daysPerWeek: payload.daysPerWeek,
            prompt: prompt,
            sessions: sessions
        )
    }

    private func fallbackDraft(
        style: String,
        profile: RunAssistantProfile,
        prompt: String,
        context: ModelContext
    ) -> PlanDraft {
        let recommendations = RunAssistantService.shared.recommendedTemplates(for: profile)
        let targetGoal = goalForStyle(style)
        let template = recommendations.first(where: { $0.primaryGoal == targetGoal })
            ?? recommendations.first
            ?? RunPlanCatalog.allTemplates.first!

        let sessions = RunAssistantService.shared.blueprintsForTemplate(
            template,
            profile: profile,
            startDate: Date(),
            context: context
        )

        return PlanDraft(
            name: "AI Personalized \(template.name)",
            style: template.style,
            targetDistanceMeters: template.targetDistanceMeters,
            primaryGoal: template.primaryGoal,
            durationWeeks: template.durationWeeks,
            daysPerWeek: profile.daysPerWeek,
            prompt: prompt,
            sessions: sessions
        )
    }

    private func applyPaceGoalProgression(
        _ draft: PlanDraft,
        profile: RunAssistantProfile,
        context: ModelContext
    ) -> PlanDraft {
        var updated = draft
        let baseline = baselinePaceMinPerMile(
            context: context,
            abilityLevel: profile.abilityLevel,
            profileCurrentAveragePace: profile.currentAveragePaceMinPerMile
        )
        let goal = profile.paceGoalMinPerMile
        let totalWeeks = max(1, draft.durationWeeks)

        updated.sessions = draft.sessions.map { session in
            guard session.sessionType != "rest" else { return session }

            let progress = totalWeeks <= 1 ? 1.0 : Double(session.weekIndex) / Double(totalWeeks - 1)
            // Move toward goal over time; clamp to avoid extreme jumps.
            let projected = baseline + ((goal - baseline) * progress)

            let offset: Double
            switch session.sessionType {
            case "interval": offset = -0.40
            case "tempo": offset = -0.20
            case "easy": offset = 0.60
            case "recovery": offset = 1.00
            case "long": offset = 0.35
            default: offset = 0.0
            }

            var pace = projected + offset
            pace = min(max(pace, 5.0), 20.0)

            var updatedSession = session
            updatedSession.targetPaceMinPerMile = pace

            let volumeFactor = weeklyVolumeFactor(
                weekIndex: session.weekIndex,
                totalWeeks: totalWeeks,
                abilityLevel: profile.abilityLevel
            )
            let fraction = sessionDistanceFraction(
                sessionType: session.sessionType,
                progress: progress
            )
            let bounds = distanceBounds(
                sessionType: session.sessionType,
                targetMiles: profile.targetDistanceMiles
            )
            var targetMiles = profile.targetDistanceMiles
                * fraction
                * abilityDistanceScale(for: profile.abilityLevel)
                * volumeFactor

            if let meters = session.targetDistanceMeters, meters > 0 {
                let existingMiles = meters / 1609.34
                // Blend existing output with deterministic progression to keep some personalization.
                targetMiles = (targetMiles * 0.70) + (existingMiles * 0.30)
            }

            targetMiles = quantizedMiles(targetMiles)
            targetMiles = min(max(targetMiles, bounds.min), bounds.max)

            updatedSession.targetDistanceMeters = targetMiles * 1609.34
            updatedSession.targetDurationSeconds = targetMiles * pace * 60.0
            return updatedSession
        }
        return updated
    }

    private struct SessionDistanceBounds {
        var min: Double
        var max: Double
    }

    private func weeklyVolumeFactor(weekIndex: Int, totalWeeks: Int, abilityLevel: String) -> Double {
        let growth: Double
        let cap: Double
        switch abilityLevel {
        case "brand_new":
            growth = 1.03
            cap = 1.30
        case "continuous":
            growth = 1.07
            cap = 1.70
        default:
            growth = 1.05
            cap = 1.50
        }

        var factor = pow(growth, Double(max(0, weekIndex)))

        let weekNumber = weekIndex + 1
        if weekNumber % 4 == 0 {
            factor *= 0.88 // Deload every fourth week.
        }
        if weekIndex == totalWeeks - 1 {
            factor *= 0.92 // Taper/test week.
        } else if weekIndex == totalWeeks - 2 {
            factor *= 0.96
        }

        return min(max(0.85, factor), cap)
    }

    private func abilityDistanceScale(for abilityLevel: String) -> Double {
        switch abilityLevel {
        case "brand_new": return 0.90
        case "continuous": return 1.10
        default: return 1.00
        }
    }

    private func sessionDistanceFraction(sessionType: String, progress: Double) -> Double {
        let clamped = min(max(progress, 0.0), 1.0)
        let (start, end): (Double, Double)
        switch sessionType {
        case "long":
            (start, end) = (0.62, 1.08)
        case "tempo":
            (start, end) = (0.42, 0.78)
        case "interval":
            (start, end) = (0.36, 0.64)
        case "recovery":
            (start, end) = (0.32, 0.58)
        default: // easy
            (start, end) = (0.40, 0.72)
        }
        return start + ((end - start) * clamped)
    }

    private func distanceBounds(sessionType: String, targetMiles: Double) -> SessionDistanceBounds {
        switch sessionType {
        case "long":
            return SessionDistanceBounds(
                min: max(0.9, targetMiles * 0.45),
                max: max(1.2, targetMiles * 1.20)
            )
        case "tempo":
            return SessionDistanceBounds(
                min: max(0.7, targetMiles * 0.35),
                max: max(1.0, targetMiles * 0.90)
            )
        case "interval":
            return SessionDistanceBounds(
                min: max(0.6, targetMiles * 0.30),
                max: max(0.9, targetMiles * 0.75)
            )
        case "recovery":
            return SessionDistanceBounds(
                min: max(0.5, targetMiles * 0.25),
                max: max(0.9, targetMiles * 0.70)
            )
        default: // easy
            return SessionDistanceBounds(
                min: max(0.7, targetMiles * 0.35),
                max: max(1.0, targetMiles * 0.85)
            )
        }
    }

    private func quantizedMiles(_ miles: Double) -> Double {
        let clamped = max(0.4, miles)
        return (clamped * 4.0).rounded() / 4.0
    }

    private func baselinePaceMinPerMile(
        context: ModelContext,
        abilityLevel: String,
        profileCurrentAveragePace: Double?
    ) -> Double {
        if let profileCurrentAveragePace, profileCurrentAveragePace.isFinite, (5.0...20.0).contains(profileCurrentAveragePace) {
            return profileCurrentAveragePace
        }

        let runs = ((try? context.fetch(FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\RunningSession.date, order: .reverse)]))) ?? [])
            .filter { $0.duration > 0 && $0.distance > 0 }
            .prefix(20)

        var paces: [Double] = []
        for run in runs {
            let miles = run.distanceUnit == "mi" ? run.distance : run.distance / 1.60934
            guard miles > 0 else { continue }
            paces.append((run.duration / 60.0) / miles)
        }

        if !paces.isEmpty {
            let sorted = paces.sorted()
            return sorted[sorted.count / 2]
        }

        switch abilityLevel {
        case "brand_new": return 13.5
        case "continuous": return 10.5
        default: return 12.0
        }
    }

    private func scheduledDate(startDate: Date, weekOffset: Int, weekday: Int) -> Date {
        RunAssistantWeekday.scheduledDate(startDate: startDate, weekOffset: weekOffset, weekday: weekday)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private func payloadFromGenerated(_ generated: AIRunPlanGeneratedPayload) -> AIRunPlanPayload {
        AIRunPlanPayload(
            planName: generated.planName,
            style: generated.style.rawValue,
            targetDistanceMiles: generated.targetDistanceMiles,
            primaryGoal: generated.primaryGoal.rawValue,
            durationWeeks: generated.durationWeeks,
            daysPerWeek: generated.daysPerWeek,
            sessions: generated.sessions.map { item in
                AIRunPlanPayload.Session(
                    weekIndex: item.weekIndex,
                    weekday: item.weekday,
                    sessionType: item.sessionType.rawValue,
                    targetDistanceMiles: item.targetDistanceMiles,
                    targetDurationMinutes: item.targetDurationMinutes,
                    targetPaceMinPerMile: item.targetPaceMinPerMile,
                    intensityLevel: item.intensityLevel.rawValue,
                    notes: item.notes
                )
            }
        )
    }
    #endif
}

private struct AIRunPlanPayload: Codable {
    struct Session: Codable {
        var weekIndex: Int
        var weekday: Int
        var sessionType: String
        var targetDistanceMiles: Double?
        var targetDurationMinutes: Double?
        var targetPaceMinPerMile: Double?
        var intensityLevel: String
        var notes: String?
    }

    var planName: String
    var style: String
    var targetDistanceMiles: Double
    var primaryGoal: String
    var durationWeeks: Int
    var daysPerWeek: Int
    var sessions: [Session]
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
private enum AIRunPlanStyle: String, Codable, Equatable {
    case speed
    case endurance
    case hybrid
    case endurance_beginner
    case endurance_intermediate
    case speed_beginner
    case speed_intermediate
}

@available(iOS 26, *)
@Generable
private enum AIRunPrimaryGoal: String, Codable, Equatable {
    case speed
    case endurance
    case hybrid
}

@available(iOS 26, *)
@Generable
private enum AIRunSessionType: String, Codable, Equatable {
    case easy
    case interval
    case tempo
    case long
    case recovery
    case rest
}

@available(iOS 26, *)
@Generable
private enum AIRunIntensityLevel: String, Codable, Equatable {
    case easy
    case moderate
    case hard
}

@available(iOS 26, *)
@Generable
private struct AIRunPlanGeneratedSession: Codable, Equatable {
    @Guide(description: "Week index from 0 to durationWeeks-1")
    var weekIndex: Int

    @Guide(description: "Weekday value from 1 to 7")
    var weekday: Int

    @Guide(description: "Session type")
    var sessionType: AIRunSessionType

    @Guide(description: "Target distance in miles. Required for easy/interval/tempo/long/recovery. Omit only for rest.")
    var targetDistanceMiles: Double?

    @Guide(description: "Target duration in minutes. Required for non-rest sessions.")
    var targetDurationMinutes: Double?

    @Guide(description: "Target pace in min/mile for non-rest sessions when possible.")
    var targetPaceMinPerMile: Double?

    @Guide(description: "Session intensity")
    var intensityLevel: AIRunIntensityLevel

    @Guide(description: "Short coaching note")
    var notes: String?
}

@available(iOS 26, *)
@Generable
private struct AIRunPlanGeneratedPayload: Codable, Equatable {
    @Guide(description: "Plan title")
    var planName: String

    @Guide(description: "Plan style")
    var style: AIRunPlanStyle

    @Guide(description: "Target distance in miles")
    var targetDistanceMiles: Double

    @Guide(description: "Primary goal")
    var primaryGoal: AIRunPrimaryGoal

    @Guide(description: "Plan duration in weeks")
    var durationWeeks: Int

    @Guide(description: "Training days per week from 1 to 7")
    var daysPerWeek: Int

    @Guide(description: "Sessions for all weeks in the plan. Every non-rest session must include distance and duration.")
    var sessions: [AIRunPlanGeneratedSession]
}
#endif
