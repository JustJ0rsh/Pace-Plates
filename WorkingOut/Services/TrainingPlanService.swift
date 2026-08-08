import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class TrainingPlanService {
    static let shared = TrainingPlanService()

    private let calendar = Calendar.current

    private init() {}

    @discardableResult
    func createOrUpdateAIPlan(
        conversation: AIConversation,
        templates: [WorkoutTemplate],
        context: ModelContext,
        activate: Bool = true
    ) -> TrainingPlan? {
        let allPlans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let existing = allPlans.first { $0.sourceAIConversationID == conversation.id }
        let startDate = calendar.startOfDay(for: Date())

        #if canImport(FoundationModels)
        if let json = conversation.structuredPlanJSON,
           let data = json.data(using: .utf8),
           let structured = try? JSONDecoder().decode(WorkoutPlan.self, from: data) {
            let plan = existing ?? TrainingPlan(
                title: structured.title,
                goal: conversation.goal,
                overview: structured.overview,
                guidance: structured.guidance,
                source: "coach_ai",
                status: activate ? "active" : "draft",
                startDate: startDate,
                sourceAIConversationID: conversation.id
            )
            if existing == nil { context.insert(plan) }

            plan.title = structured.title
            plan.goal = conversation.goal
            plan.overview = structured.overview
            plan.guidance = structured.guidance
            plan.updatedAt = Date()
            plan.sourceAIConversationID = conversation.id

            let templateByDay = Dictionary(
                uniqueKeysWithValues: templates.compactMap { template in
                    template.aiDayIndex.map { ($0, template) }
                }
            )
            let existingByDay = Dictionary(
                uniqueKeysWithValues: (plan.sessions ?? []).map { ($0.dayIndex, $0) }
            )
            var retained = Set<UUID>()
            var globalDayIndex = 0

            for (weekIndex, week) in structured.weeks.enumerated() {
                for day in week.days {
                    let item = primaryTarget(in: day)
                    let session = existingByDay[globalDayIndex] ?? PlannedSession(
                        plan: plan,
                        title: day.title,
                        activityType: activityType(for: day.type),
                        scheduledDate: calendar.date(byAdding: .day, value: globalDayIndex, to: startDate) ?? startDate,
                        weekIndex: weekIndex,
                        dayIndex: globalDayIndex
                    )
                    if session.plan == nil { session.plan = plan }
                    if existingByDay[globalDayIndex] == nil { context.insert(session) }

                    session.title = day.title
                    session.activityType = activityType(for: day.type)
                    session.scheduledDate = calendar.date(byAdding: .day, value: globalDayIndex, to: startDate) ?? startDate
                    session.weekIndex = weekIndex
                    session.dayIndex = globalDayIndex
                    session.notes = day.items.compactMap(\.notes).first
                    session.targetDistanceMeters = item.flatMap(distanceMeters)
                    session.targetDurationSeconds = item?.durationMinutes.map { Double($0) * 60 }
                    session.targetPaceMinPerMile = item?.pace.flatMap(paceMinutesPerMile)
                    session.intensityLevel = item?.effort
                    session.workoutTemplateID = templateByDay[globalDayIndex]?.id
                    retained.insert(session.id)
                    globalDayIndex += 1
                }
            }

            for stale in (plan.sessions ?? []) where !retained.contains(stale.id) {
                context.delete(stale)
            }

            if activate { activatePlan(plan, among: allPlans, context: context) }
            _ = PersistenceSave.commit(context, action: "save Coach plan")
            return plan
        }
        #endif

        guard !templates.isEmpty else { return nil }
        let ordered = templates.sorted { ($0.aiDayIndex ?? 0) < ($1.aiDayIndex ?? 0) }
        let plan = existing ?? TrainingPlan(
            title: ordered.first?.aiPlanTitle ?? "Coach Training Plan",
            goal: conversation.goal,
            overview: "A training plan created by Coach.",
            source: "coach_ai",
            status: activate ? "active" : "draft",
            startDate: startDate,
            sourceAIConversationID: conversation.id
        )
        if existing == nil { context.insert(plan) }

        plan.title = ordered.first?.aiPlanTitle ?? plan.title
        plan.goal = conversation.goal
        plan.updatedAt = Date()
        let existingByTemplate = Dictionary(
            uniqueKeysWithValues: (plan.sessions ?? []).compactMap { session in
                session.workoutTemplateID.map { ($0, session) }
            }
        )
        var retained = Set<UUID>()

        for (index, template) in ordered.enumerated() {
            let session = existingByTemplate[template.id] ?? PlannedSession(
                plan: plan,
                title: template.aiDayTitle ?? template.title,
                activityType: activityType(forRawDayType: template.aiDayType),
                scheduledDate: calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate,
                weekIndex: index / 7,
                dayIndex: index,
                workoutTemplateID: template.id
            )
            if session.plan == nil { session.plan = plan }
            if existingByTemplate[template.id] == nil { context.insert(session) }
            session.title = template.aiDayTitle ?? template.title
            session.activityType = activityType(forRawDayType: template.aiDayType)
            session.scheduledDate = calendar.date(byAdding: .day, value: index, to: startDate) ?? startDate
            session.weekIndex = index / 7
            session.dayIndex = index
            session.notes = template.notes
            session.workoutTemplateID = template.id
            retained.insert(session.id)
        }

        for stale in (plan.sessions ?? []) where !retained.contains(stale.id) {
            context.delete(stale)
        }
        if activate { activatePlan(plan, among: allPlans, context: context) }
        _ = PersistenceSave.commit(context, action: "save Coach plan")
        return plan
    }

    @discardableResult
    func syncRunningPlan(_ runningPlan: RunningPlan, context: ModelContext) -> TrainingPlan {
        let allPlans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        let existing = allPlans.first { $0.sourceRunningPlanID == runningPlan.id }
        let plan = existing ?? TrainingPlan(
            title: runningPlan.name,
            goal: runningPlan.primaryGoal,
            overview: "A \(runningPlan.durationWeeks)-week running plan.",
            source: "running_assistant",
            status: runningPlan.isArchived ? "archived" : (runningPlan.isActive ? "active" : "draft"),
            startDate: runningPlan.startDate,
            sourceRunningPlanID: runningPlan.id
        )
        if existing == nil { context.insert(plan) }

        plan.title = runningPlan.name
        plan.goal = runningPlan.primaryGoal
        plan.overview = "A \(runningPlan.durationWeeks)-week \(runningPlan.style.replacingOccurrences(of: "_", with: " ")) running plan."
        plan.status = runningPlan.isArchived ? "archived" : (runningPlan.isActive ? "active" : "draft")
        plan.startDate = runningPlan.startDate
        plan.updatedAt = runningPlan.updatedAt
        plan.sourceRunningPlanID = runningPlan.id

        let existingBySource = Dictionary(
            uniqueKeysWithValues: (plan.sessions ?? []).compactMap { session in
                session.runningPlanSessionID.map { ($0, session) }
            }
        )
        var retained = Set<UUID>()

        for source in runningPlan.sessions ?? [] {
            let scheduled = source.scheduledDate ?? runningPlan.startDate
            let session = existingBySource[source.id] ?? PlannedSession(
                plan: plan,
                title: runningTitle(for: source.sessionType),
                activityType: source.sessionType == "rest" ? "rest" : "run",
                scheduledDate: scheduled,
                weekIndex: source.weekIndex,
                dayIndex: source.dayIndex,
                runningPlanSessionID: source.id
            )
            if session.plan == nil { session.plan = plan }
            if existingBySource[source.id] == nil { context.insert(session) }
            session.title = runningTitle(for: source.sessionType)
            session.activityType = source.sessionType == "rest" ? "rest" : "run"
            session.scheduledDate = scheduled
            session.weekIndex = source.weekIndex
            session.dayIndex = source.dayIndex
            session.status = source.status
            session.notes = source.notes
            session.targetDistanceMeters = source.targetDistanceMeters
            session.targetDurationSeconds = source.targetDurationSeconds
            session.targetPaceMinPerMile = source.targetPaceMinPerMile
            session.intensityLevel = source.intensityLevel
            session.runningPlanSessionID = source.id
            session.completedRunningSessionID = source.completedRunSessionID
            session.completedAt = source.completedAt
            retained.insert(session.id)
        }

        for stale in (plan.sessions ?? []) where !retained.contains(stale.id) {
            context.delete(stale)
        }
        if runningPlan.isActive && !runningPlan.isArchived {
            activatePlan(plan, among: allPlans, context: context)
        }
        _ = PersistenceSave.commit(context, action: "sync Coach running plan")
        return plan
    }

    func syncRunningPlans(context: ModelContext) {
        let runningPlans = (try? context.fetch(FetchDescriptor<RunningPlan>())) ?? []
        for plan in runningPlans {
            _ = syncRunningPlan(plan, context: context)
        }
        rebuildMissingAIPlans(context: context)
        reconcileTrackedRuns(context: context)
    }

    /// Generalized Coach plans are a lifecycle layer over durable source data.
    /// Rebuilding missing rows keeps older installs and restored backups useful
    /// without duplicating AI or running source records.
    private func rebuildMissingAIPlans(context: ModelContext) {
        let plans = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        var knownConversationIDs = Set(plans.compactMap(\.sourceAIConversationID))
        let conversations = ((try? context.fetch(
            FetchDescriptor<AIConversation>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )) ?? []).filter { $0.mode == "plan" }
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []

        var rebuilt: [TrainingPlan] = []
        for conversation in conversations where !knownConversationIDs.contains(conversation.id) {
            let matching = templates.filter { $0.sourceAIConversationId == conversation.id }
            guard !matching.isEmpty,
                  let plan = createOrUpdateAIPlan(
                    conversation: conversation,
                    templates: matching,
                    context: context,
                    activate: false
                  ) else { continue }
            rebuilt.append(plan)
            knownConversationIDs.insert(conversation.id)
        }

        let refreshed = (try? context.fetch(FetchDescriptor<TrainingPlan>())) ?? []
        if !refreshed.contains(where: { $0.status == "active" }),
           let newest = rebuilt.first ?? refreshed
            .filter({ $0.status != "archived" })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first {
            newest.status = "active"
            newest.updatedAt = Date()
            _ = PersistenceSave.commit(context, action: "restore active Coach plan")
        }
    }

    func reconcileTrackedRuns(context: ModelContext) {
        let planned = (try? context.fetch(FetchDescriptor<PlannedSession>())) ?? []
        let byID = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })
        let runs = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        var changed = false

        for run in runs {
            guard let plannedID = run.plannedSessionID,
                  let session = byID[plannedID],
                  session.activityType == "run" else { continue }
            if session.status != "completed" || session.completedRunningSessionID != run.id {
                session.status = "completed"
                session.completedAt = run.date
                session.completedRunningSessionID = run.id
                session.plan?.updatedAt = Date()
                changed = true
            }
        }

        if changed {
            _ = PersistenceSave.commit(context, action: "reconcile Coach runs")
        }
    }

    func move(_ session: PlannedSession, to date: Date, context: ModelContext) {
        session.scheduledDate = calendar.startOfDay(for: date)
        session.plan?.updatedAt = Date()
        if let runningID = session.runningPlanSessionID,
           let source = fetchRunningSession(id: runningID, context: context) {
            source.scheduledDate = session.scheduledDate
            source.plan?.updatedAt = Date()
        }
        _ = PersistenceSave.commit(context, action: "move planned session")
    }

    func mark(
        _ session: PlannedSession,
        status: String,
        completedWorkoutSessionID: UUID? = nil,
        completedRunningSessionID: UUID? = nil,
        context: ModelContext
    ) {
        session.status = status
        session.completedAt = status == "completed" ? Date() : nil
        session.completedWorkoutSessionID = completedWorkoutSessionID
        session.completedRunningSessionID = completedRunningSessionID
        session.plan?.updatedAt = Date()

        if let runningID = session.runningPlanSessionID,
           let source = fetchRunningSession(id: runningID, context: context) {
            RunAssistantService.shared.markSession(
                source.id,
                status: status,
                completionSource: status == "completed" ? "manual" : nil,
                completedRunSessionID: completedRunningSessionID,
                context: context
            )
        }
        _ = PersistenceSave.commit(context, action: "update planned session")
    }

    func archive(_ plan: TrainingPlan, context: ModelContext) {
        plan.status = "archived"
        plan.updatedAt = Date()
        if let runningID = plan.sourceRunningPlanID {
            RunAssistantService.shared.archivePlan(runningID, context: context)
        }
        _ = PersistenceSave.commit(context, action: "archive Coach plan")
    }

    private func activatePlan(_ plan: TrainingPlan, among plans: [TrainingPlan], context: ModelContext) {
        for other in plans where other.id != plan.id && other.status == "active" {
            other.status = "draft"
            other.updatedAt = Date()
        }
        plan.status = "active"
        plan.updatedAt = Date()
    }

    private func fetchRunningSession(id: UUID, context: ModelContext) -> RunningPlanSession? {
        let sessions = (try? context.fetch(FetchDescriptor<RunningPlanSession>())) ?? []
        return sessions.first { $0.id == id }
    }

    private func runningTitle(for type: String) -> String {
        switch type {
        case "easy": return "Easy Run"
        case "interval": return "Intervals"
        case "tempo": return "Tempo Run"
        case "long": return "Long Run"
        case "recovery": return "Recovery Run"
        case "rest": return "Rest Day"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func activityType(forRawDayType raw: String?) -> String {
        guard let raw else { return "workout" }
        if raw == "rest" { return "rest" }
        if raw == "activeRecovery" { return "recovery" }
        if raw.lowercased().contains("run") { return "run" }
        if raw.lowercased().contains("strength") { return "strength" }
        return "cardio"
    }

    #if canImport(FoundationModels)
    private func activityType(for type: DayType) -> String {
        activityType(forRawDayType: type.rawValue)
    }

    private func primaryTarget(in day: Day) -> Item? {
        day.items.first { $0.distance != nil || $0.durationMinutes != nil || $0.pace != nil }
    }

    private func distanceMeters(_ item: Item) -> Double? {
        guard let value = item.distance else { return nil }
        switch item.distanceUnit?.lowercased() {
        case "mi", "mile", "miles": return value * 1_609.344
        case "m": return value
        default: return value * 1_000
        }
    }
    #endif

    private func paceMinutesPerMile(_ value: String) -> Double? {
        let normalized = value.lowercased()
        let components = normalized.split(whereSeparator: { !$0.isNumber && $0 != ":" })
        guard let token = components.first else { return nil }
        let time = token.split(separator: ":")
        guard let minutes = Double(time[0]) else { return nil }
        let seconds = time.count > 1 ? (Double(time[1]) ?? 0) : 0
        let pace = minutes + seconds / 60
        return normalized.contains("km") ? pace * 1.609344 : pace
    }
}
