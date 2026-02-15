import Foundation
import SwiftData

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
        case unavailable
        case invalidResponse
        case invalidSchema(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Apple Intelligence is not available on this device."
            case .invalidResponse:
                return "The generated response could not be parsed as plan JSON."
            case let .invalidSchema(message):
                return message
            }
        }
    }

    private init() {}

    func canGenerate() -> Bool {
        WorkoutPlanGenerator.shared.availability() == .available
    }

    func generateDraft(
        style: String,
        profile: RunAssistantProfile,
        context: ModelContext,
        onStreamChunk: (@MainActor (String) -> Void)? = nil
    ) async throws -> PlanDraft {
        guard canGenerate() else {
            throw AIError.unavailable
        }

        let distanceUnit = UserDefaults.standard.string(forKey: "distanceUnit") ?? "mi"
        let weightUnit = UserDefaults.standard.string(forKey: "weightUnit") ?? "lbs"

        let prompt = await buildPrompt(style: style, profile: profile, context: context)
        let request = WorkoutPlanRequest(
            goal: goalForStyle(style),
            extraContext: prompt,
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            modelContext: context,
            mode: .ask
        )

        do {
            if let onStreamChunk {
                onStreamChunk("Preparing Apple Intelligence model...\n")
            }
            var response = ""
            let stream = WorkoutPlanGenerator.shared.generateAskStream(request: request, history: [])
            var iterator = stream.makeAsyncIterator()
            while let chunk = try await iterator.next() {
                response += chunk
                if let onStreamChunk {
                    onStreamChunk(chunk)
                }
            }

            guard let json = extractJSON(response) else {
                throw AIError.invalidResponse
            }
            guard let data = json.data(using: .utf8) else {
                throw AIError.invalidResponse
            }

            let decoded = try JSONDecoder().decode(AIRunPlanPayload.self, from: data)
            try validate(payload: decoded)
            let baseDraft = draftFromPayload(decoded, prompt: prompt)
            return applyPaceGoalProgression(baseDraft, profile: profile, context: context)
        } catch {
            // Graceful fallback: still provide a reviewable personalized draft.
            if let onStreamChunk {
                onStreamChunk("\n\nFalling back to a local personalized draft...\n")
            }
            let baseDraft = fallbackDraft(style: style, profile: profile, prompt: prompt, context: context)
            return applyPaceGoalProgression(baseDraft, profile: profile, context: context)
        }
    }

    @discardableResult
    func saveDraft(
        _ draft: PlanDraft,
        profile: RunAssistantProfile,
        context: ModelContext,
        activate: Bool
    ) -> RunningPlan {
        let plan = RunningPlan(
            name: draft.name,
            source: "ai",
            style: draft.style,
            targetDistanceMeters: draft.targetDistanceMeters,
            primaryGoal: draft.primaryGoal,
            durationWeeks: draft.durationWeeks,
            daysPerWeek: draft.daysPerWeek,
            startDate: Date(),
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

        _ = PersistenceSave.commit(context, action: "save changes")

        if activate {
            RunAssistantService.shared.setActivePlan(plan.id, context: context)
        }

        return plan
    }

    // MARK: - Prompting

    private func buildPrompt(style: String, profile: RunAssistantProfile, context: ModelContext) async -> String {
        let runs = ((try? context.fetch(FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\RunningSession.date, order: .reverse)]))) ?? [])
        let recentRuns = Array(runs.prefix(20))

        let weights = ((try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\WeightEntry.date, order: .reverse)]))) ?? [])
        let latestWeight = weights.first

        let totalDistanceMiles: Double = recentRuns.reduce(0) { partial, run in
            let miles = run.distanceUnit == "mi" ? run.distance : run.distance / 1.60934
            return partial + miles
        }

        let recentCount = recentRuns.count
        let avgPace: String = {
            let durations = recentRuns.reduce(0.0) { $0 + $1.duration }
            let miles = recentRuns.reduce(0.0) { partial, run in
                partial + (run.distanceUnit == "mi" ? run.distance : run.distance / 1.60934)
            }
            guard miles > 0 else { return "unknown" }
            let minPerMile = (durations / 60.0) / miles
            let mins = Int(minPerMile)
            let secs = Int((minPerMile - Double(mins)) * 60)
            return String(format: "%d:%02d per mile", mins, secs)
        }()

        var hkSummary = "HealthKit unavailable"
        if HealthKitManager.shared.isAuthorized {
            let hkRuns = (try? await HealthKitManager.shared.fetchRecentRuns(limit: 20)) ?? []
            let hkWeight = try? await HealthKitManager.shared.getBodyWeight()
            hkSummary = "HealthKit runs: \(hkRuns.count), HealthKit body weight (lb): \(hkWeight.map { String(format: "%.1f", $0) } ?? "n/a")"
        }

        let target = Int(profile.targetDistanceMiles)

        return """
Create a strict JSON running plan for a couch-to-distance assistant.

STYLE: \(style)
TARGET: \(target) mile(s)
ABILITY: \(profile.abilityLevel)
DAYS_PER_WEEK: \(profile.daysPerWeek)
LONG_RUN_WEEKDAY: \(profile.longRunWeekday)
PRIMARY_GOAL: \(profile.goalFocus)
CURRENT_AVERAGE_PACE_MIN_PER_MILE: \(String(format: "%.2f", profile.currentAveragePaceMinPerMile))
PACE_GOAL_MIN_PER_MILE: \(String(format: "%.2f", profile.paceGoalMinPerMile))

DATA_CONTEXT:
- Local run count: \(recentCount)
- Local total distance (mi): \(String(format: "%.2f", totalDistanceMiles))
- Local average pace: \(avgPace)
- Latest local weight: \(latestWeight.map { String(format: "%.1f \($0.weightUnit)", $0.weight) } ?? "n/a")
- \(hkSummary)

Output VALID JSON only. Do not wrap in markdown.
Schema:
{
  "planName": "string",
  "style": "speed|endurance|hybrid|endurance_beginner|endurance_intermediate|speed_beginner|speed_intermediate",
  "targetDistanceMiles": number,
  "primaryGoal": "speed|endurance|hybrid",
  "durationWeeks": number,
  "daysPerWeek": number,
  "sessions": [
    {
      "weekIndex": number,
      "weekday": number,
      "sessionType": "easy|interval|tempo|long|recovery|rest",
      "targetDistanceMiles": number|null,
      "targetDurationMinutes": number|null,
      "targetPaceMinPerMile": number|null,
      "intensityLevel": "easy|moderate|hard",
      "notes": "string"
    }
  ]
}

Rules:
- Use weeks 0...(durationWeeks-1)
- Include only weekday values 1..7
- Respect daysPerWeek plus rest days
- Include progression with occasional deload and final taper/test week
- Use realistic distances/paces for ability level
- Start week 1 paces near CURRENT_AVERAGE_PACE_MIN_PER_MILE before progressing.
- Week over week, push pace slightly faster (harder sessions first) toward the pace goal.
- Keep easy/recovery slower than tempo/interval while still trending faster over the plan.
"""
    }

    private func goalForStyle(_ style: String) -> String {
        if style.contains("speed") { return "speed" }
        if style.contains("endurance") { return "endurance" }
        return "hybrid"
    }

    private func extractJSON(_ response: String) -> String? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }

        if let fenceStart = trimmed.range(of: "```json"),
           let fenceEnd = trimmed.range(of: "```", range: fenceStart.upperBound..<trimmed.endIndex) {
            return String(trimmed[fenceStart.upperBound..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}") else {
            return nil
        }
        return String(trimmed[first...last])
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
            if let meters = session.targetDistanceMeters, meters > 0 {
                let miles = meters / 1609.34
                updatedSession.targetDurationSeconds = miles * pace * 60.0
            }
            return updatedSession
        }
        return updated
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
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)) ?? startDate
        let offsetWeekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) ?? weekStart
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: offsetWeekStart)
        comps.weekday = weekday
        return calendar.date(from: comps) ?? offsetWeekStart
    }
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
