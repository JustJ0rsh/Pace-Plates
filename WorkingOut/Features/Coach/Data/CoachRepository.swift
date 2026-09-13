import Foundation
import SwiftData
import CryptoKit
import UserNotifications

struct CoachTodayProjection {
    var plan: TrainingPlan?
    var today: [PlannedSession]
    var overdue: [PlannedSession]
    var next: [PlannedSession]
}

struct CoachProgressSummary {
    var required: Int = 0
    var completed: Int = 0
    var partial: Int = 0
    var skipped: Int = 0
    var pending: Int = 0
    var inProgress: Int = 0
    var optionalCompleted: Int = 0
    var completionFraction: Double? { required == 0 ? nil : Double(completed) / Double(required) }
}

struct CoachExerciseMapping: Identifiable {
    var id: String { choice.key }
    let choice: CoachExerciseChoice
    let candidates: [ExerciseDefinition]
    var requiresSelection: Bool { candidates.count > 1 }
}

enum CoachRepositoryError: LocalizedError {
    case localOwnershipRequired, missingRecord, invalidValue(String), ambiguousExercise(String), futureOnly, revisionConflict, dateCollision
    var errorDescription: String? {
        switch self {
        case .localOwnershipRequired: return "Review and enable local storage before saving Coach records."
        case .missingRecord: return "This record is no longer available."
        case .invalidValue(let field): return "Enter a valid \(field). Blank fields can stay blank."
        case .ambiguousExercise(let name): return "Select the matching exercise for \(name) before importing."
        case .futureOnly: return "Only selected, unstarted future sessions can be changed."
        case .revisionConflict: return "Review the changed revision, then choose a draft replacement, selected future sessions, or a new plan."
        case .dateCollision: return "More than one entry exists on this date. Select the entry to edit before merging these records."
        }
    }
}

@MainActor
final class CoachRepository {
    let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func requireLocal() throws {
        guard CoachPersistence.isLocal(context) else { throw CoachRepositoryError.localOwnershipRequired }
    }

    /// Every unit of work uses a separate context. A failed import must never
    /// roll back an unrelated edit held by the view's context.
    func transaction<T>(_ operation: (ModelContext) throws -> T) throws -> T {
        try requireLocal()
        let isolated = ModelContext(context.container)
        isolated.autosaveEnabled = false
        do {
            let result = try operation(isolated)
            try isolated.save()
            return result
        } catch {
            isolated.rollback()
            throw error
        }
    }

    func plans() throws -> [TrainingPlan] {
        try context.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func occurrences(planID: UUID) throws -> [PlannedSession] {
        try context.fetch(FetchDescriptor<PlannedSession>()).filter { $0.plan?.id == planID }
            .sorted { ($0.scheduledDate, $0.intraDayOrder, $0.id.uuidString) < ($1.scheduledDate, $1.intraDayOrder, $1.id.uuidString) }
    }

    func today(on date: Date = Date()) throws -> CoachTodayProjection {
        let plan = try plans().first { $0.status == CoachPlanStatus.active.rawValue }
        guard let plan else { return .init(plan: nil, today: [], overdue: [], next: []) }
        let key = Self.civilDate(date, timeZone: Self.timeZone(plan))
        let sessions = try occurrences(planID: plan.id).filter { $0.completionProvenance != "removed_by_reviewed_revision" }
        let unresolved = sessions.filter { ["pending", "in_progress"].contains($0.status) && $0.activityType != "rest" }
        return .init(plan: plan,
                     today: sessions.filter { Self.day($0, plan: plan) == key },
                     overdue: unresolved.filter { Self.day($0, plan: plan) < key },
                     next: Array(unresolved.filter { Self.day($0, plan: plan) > key }.prefix(8)))
    }

    func progress(planID: UUID, from start: Date? = nil, through end: Date? = nil) throws -> CoachProgressSummary {
        var result = CoachProgressSummary()
        let occurrences = try occurrences(planID: planID)
        let zone = occurrences.first.flatMap { $0.plan }.map { Self.timeZone($0) } ?? .current
        let startKey = start.map { Self.civilDate($0, timeZone: zone) }
        let endKey = end.map { Self.civilDate($0, timeZone: zone) }
        let rows = occurrences.filter {
            let day = $0.currentCivilDate ?? Self.civilDate($0.scheduledDate, timeZone: zone)
            return $0.activityType != "rest" && $0.completionProvenance != "removed_by_reviewed_revision" && (startKey == nil || day >= startKey!) && (endKey == nil || day <= endKey!)
        }
        for row in rows {
            if row.isOptional { if row.status == "completed" { result.optionalCompleted += 1 }; continue }
            result.required += 1
            switch row.status {
            case "completed": result.completed += 1
            case "partial": result.partial += 1
            case "skipped": result.skipped += 1
            case "in_progress": result.inProgress += 1
            default: result.pending += 1
            }
        }
        return result
    }

    func document(for plan: TrainingPlan) throws -> CoachPlanDocument? {
        guard let revisionID = plan.currentRevisionID,
              let revision = try context.fetch(FetchDescriptor<CoachPlanRevision>()).first(where: { $0.id == revisionID }) else { return nil }
        return try JSONDecoder().decode(CoachPlanDocument.self, from: revision.documentData)
    }

    func exerciseMappings(for document: CoachPlanDocument) throws -> [CoachExerciseMapping] {
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        var seen = Set<String>()
        return document.sessionTemplates.flatMap { template -> [CoachExerciseChoice] in
            guard case .strength(let strength) = template else { return [] }
            return strength.exercises.flatMap { [$0.exercise] + ($0.substitutions ?? []) }
        }.filter { seen.insert($0.key).inserted }.map { choice in
            let idMatch = choice.catalogExerciseId.flatMap(UUID.init(uuidString:)).flatMap { id in definitions.first { $0.id == id } }
            let candidates = idMatch.map { [$0] } ?? definitions.filter { Self.normalized($0.name) == Self.normalized(choice.name) }
            return CoachExerciseMapping(choice: choice, candidates: candidates)
        }
    }

    @discardableResult
    func importPlan(document: CoachPlanDocument, startDate: Date, activate: Bool,
                    exerciseMappings: [String: UUID] = [:], allowCreatingExercises: Bool = false,
                    replacingDraftID: UUID? = nil, expectedRevisionID: UUID? = nil, saveAsNewPlan: Bool = false, firstPhaseReady: Bool = false,
                    timeZone: TimeZone = .current) async throws -> UUID {
        try requireLocal()
        let generation = WearableWorkoutInboxService.localDataPurgeGeneration
        let zone = timeZone
        let prepared = try await Task.detached(priority: .userInitiated) {
            let validated = try CoachPlanValidator().validate(JSONEncoder().encode(document))
            let rows = try CoachSchedule.expand(validated, startDate: startDate, timeZone: zone)
            return (validated, rows)
        }.value
        try Task.checkCancellation()
        guard WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation) else { throw CancellationError() }
        let savedPlans = try plans()
        if !saveAsNewPlan, let existing = savedPlans.first(where: { $0.sourceProgramID == document.programId && $0.fingerprint == prepared.0.fingerprint }) { return existing.id }
        if !saveAsNewPlan && replacingDraftID == nil && savedPlans.contains(where: { $0.sourceProgramID == document.programId }) { throw CoachRepositoryError.revisionConflict }
        let firstPhaseID = document.weeks.first?.phaseId
        if activate && document.phases.contains(where: { $0.id == firstPhaseID && $0.advanceMode == .reviewRequired }) && !firstPhaseReady {
            throw CoachRepositoryError.invalidValue("readiness acknowledgement for the first phase")
        }
        let mappings = try self.exerciseMappings(for: document)
        for mapping in mappings {
            if let selected = exerciseMappings[mapping.id] {
                guard try context.fetch(FetchDescriptor<ExerciseDefinition>()).contains(where: { $0.id == selected }) else { throw CoachRepositoryError.ambiguousExercise(mapping.choice.name) }
            } else if mapping.requiresSelection || (mapping.candidates.isEmpty && !allowCreatingExercises) {
                throw CoachRepositoryError.ambiguousExercise(mapping.choice.name)
            }
        }
        return try transaction { isolated in
            let existingPlans = try isolated.fetch(FetchDescriptor<TrainingPlan>())
            let plan: TrainingPlan
            if let replacement = replacingDraftID {
                guard let draft = existingPlans.first(where: { $0.id == replacement }), draft.status == "draft" else { throw CoachRepositoryError.revisionConflict }
                guard expectedRevisionID == draft.currentRevisionID, document.revision > draft.sourceRevision else { throw CoachRepositoryError.revisionConflict }
                guard (draft.sessions ?? []).allSatisfy({ $0.executionID == nil && $0.status == "pending" }) else { throw CoachRepositoryError.futureOnly }
                for row in draft.sessions ?? [] { isolated.delete(row) }
                plan = draft
            } else {
                plan = TrainingPlan(title: document.title, goal: document.goal, source: "coach_import", status: "draft", startDate: startDate)
                isolated.insert(plan)
            }
            let revision = CoachPlanRevision()
            revision.planID = plan.id; revision.documentData = prepared.0.canonicalData
            revision.fingerprint = prepared.0.fingerprint; revision.sourceProgramID = document.programId
            revision.sourceRevision = document.revision; revision.schemaVersion = document.schemaVersion
            var resolvedMappings = exerciseMappings
            for mapping in mappings where resolvedMappings[mapping.id] == nil {
                if let candidate = mapping.candidates.first { resolvedMappings[mapping.id] = candidate.id }
                else {
                    let definition = ExerciseDefinition(name: mapping.choice.name, muscleGroup: "Other", isUserDefined: true)
                    // Equipment stays in the typed prescription; the library has no equipment column.
                    isolated.insert(definition); resolvedMappings[mapping.id] = definition.id
                }
            }
            revision.exerciseMappingsData = try JSONEncoder().encode(resolvedMappings)
            isolated.insert(revision)
            plan.title = document.title; plan.goal = document.goal; plan.overview = document.overview; plan.guidance = document.guidance
            plan.sourceProgramID = document.programId; plan.sourceRevision = document.revision
            plan.fingerprint = prepared.0.fingerprint; plan.currentRevisionID = revision.id
            plan.startDate = startDate; plan.startCivilDate = Self.civilDate(startDate, timeZone: zone)
            plan.timeZoneIdentifier = zone.identifier; plan.durationWeeks = document.weeks.count; plan.updatedAt = Date()
            var sessions: [PlannedSession] = []
            for row in prepared.1 {
                let session = PlannedSession(plan: plan, title: row.label ?? row.template.title, activityType: Self.activityType(row.template),
                                             scheduledDate: try Self.date(row.civilDate, timeZone: zone), weekIndex: row.weekIndex,
                                             dayIndex: row.dayOffset + 1, notes: [row.notes, row.template.notes].compactMap { $0 }.joined(separator: "\n\n"))
                session.sourceWeekID = row.weekId; session.sourceSlotID = row.slotId; session.phaseID = row.phaseId
                session.sourceTemplateID = row.templateId; session.prescriptionData = try JSONEncoder().encode(row.template)
                session.revisionID = revision.id; session.originalCivilDate = row.civilDate; session.currentCivilDate = row.civilDate
                session.intraDayOrder = row.intraDayOrder; session.isOptional = row.isOptional
                isolated.insert(session); sessions.append(session)
            }
            plan.sessions = sessions
            for phase in document.phases where phase.advanceMode == .reviewRequired {
                let gate = CoachPhaseReview(); gate.planID = plan.id; gate.phaseID = phase.id; gate.revisionID = revision.id
                if activate && firstPhaseReady && phase.id == firstPhaseID { gate.statusRaw = "ready"; gate.reviewedAt = Date() }
                isolated.insert(gate)
            }
            if activate {
                for current in existingPlans where current.id != plan.id && current.status == "active" { current.status = "paused"; current.pausedAt = Date(); current.updatedAt = Date() }
                plan.status = "active"; plan.activatedAt = Date()
                try Self.createTargetPeriods(document: document, plan: plan, context: isolated)
            }
            return plan.id
        }
    }

    func activate(planID: UUID, startDate: Date? = nil) throws {
        try transaction { isolated in
            let plans = try isolated.fetch(FetchDescriptor<TrainingPlan>())
            guard let plan = plans.first(where: { $0.id == planID }) else { throw CoachRepositoryError.missingRecord }
            for current in plans where current.id != planID && current.status == "active" { current.status = "paused"; current.pausedAt = Date(); current.updatedAt = Date() }
            let isFirstActivation = plan.activatedAt == nil
            if let startDate { try Self.shiftUnstarted(plan: plan, to: startDate) }
            plan.status = "active"; plan.activatedAt = plan.activatedAt ?? Date(); plan.pausedAt = nil; plan.updatedAt = Date()
            if isFirstActivation, let revisionID = plan.currentRevisionID,
               let revision = try isolated.fetch(FetchDescriptor<CoachPlanRevision>()).first(where: { $0.id == revisionID }) {
                let document = try JSONDecoder().decode(CoachPlanDocument.self, from: revision.documentData)
                try Self.createTargetPeriods(document: document, plan: plan, context: isolated)
            }
        }
    }

    func setPlanStatus(planID: UUID, status: CoachPlanStatus) throws {
        if status == .active { try activate(planID: planID); return }
        try transaction { isolated in
            guard let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == planID }) else { throw CoachRepositoryError.missingRecord }
            plan.status = status.rawValue; plan.updatedAt = Date(); plan.pausedAt = status == .paused ? Date() : nil
        }
    }

    func moveSession(id: UUID, to date: Date, intraDayOrder: Int? = nil) throws {
        try transaction { isolated in
            guard let session = try isolated.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == id }), let plan = session.plan else { throw CoachRepositoryError.missingRecord }
            guard session.executionID == nil && session.status == "pending" else { throw CoachRepositoryError.futureOnly }
            session.currentCivilDate = Self.civilDate(date, timeZone: Self.timeZone(plan)); session.scheduledDate = try Self.date(session.currentCivilDate!, timeZone: Self.timeZone(plan))
            if let intraDayOrder { session.intraDayOrder = intraDayOrder }; session.scheduleRevision += 1; plan.updatedAt = Date()
            session.localScheduleOverride = true
            try Self.validateScheduleDays(try isolated.fetch(FetchDescriptor<PlannedSession>()).filter { $0.plan?.id == plan.id })
            for mapping in try isolated.fetch(FetchDescriptor<CoachCalendarMapping>()) where mapping.plannedSessionID == id { mapping.pendingProjection = true }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["coach.session.\(id.uuidString)"])
    }

    func markSession(id: UUID, status: CoachOccurrenceStatus, notes: String? = nil) throws {
        guard [.completed, .partial, .skipped, .pending].contains(status) else { throw CoachRepositoryError.invalidValue("status") }
        if [.completed, .partial].contains(status), notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw CoachRepositoryError.invalidValue("explanation for a manually recorded outcome")
        }
        try transaction { isolated in
            guard let row = try isolated.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }
            guard row.executionID == nil else { throw CoachRepositoryError.invalidValue("session outcome in the workout logger") }
            if status == .pending && row.status != "skipped" { throw CoachRepositoryError.invalidValue("skipped session to return to pending") }
            if status != .pending && row.status != "pending" { throw CoachRepositoryError.invalidValue("unstarted session outcome") }
            row.status = status.rawValue; row.completionProvenance = "manual_attestation"
            row.completedAt = [.completed, .partial].contains(status) ? Date() : nil
            if let notes { row.notes = notes }
            for mapping in try isolated.fetch(FetchDescriptor<CoachCalendarMapping>()) where mapping.plannedSessionID == id { mapping.pendingProjection = true }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["coach.session.\(id.uuidString)"])
    }

    func deletePlan(id: UUID, keepingCalendarEvents: Bool = false) throws {
        let deletedIDs: [UUID] = try transaction { isolated in
            guard let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == id }) else { return [] }
            // Executions and revision snapshots are kept as provenance of actual activity.
            let ids = Set((plan.sessions ?? []).map(\.id))
            let executions = try isolated.fetch(FetchDescriptor<CoachSessionExecution>()).filter { $0.plannedSessionID.map(ids.contains) == true }
            guard !executions.contains(where: { $0.statusRaw == "in_progress" }), !(plan.sessions ?? []).contains(where: { $0.status == "in_progress" }) else {
                throw CoachRepositoryError.invalidValue("saved or canceled active session before deleting the plan")
            }
            let mappings = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>()).filter { ids.contains($0.plannedSessionID) }
            guard mappings.isEmpty || keepingCalendarEvents else {
                throw CoachRepositoryError.invalidValue("calendar decision: remove mapped events first, or explicitly keep exported events")
            }
            for execution in executions { execution.plannedSessionID = nil }
            for workout in try isolated.fetch(FetchDescriptor<WorkoutSession>()) where workout.plannedSessionID.map(ids.contains) == true { workout.plannedSessionID = nil }
            for run in try isolated.fetch(FetchDescriptor<RunningSession>()) where run.canonicalPlannedSessionID.map(ids.contains) == true { run.canonicalPlannedSessionID = nil }
            for mapping in mappings { isolated.delete(mapping) }
            for phase in try isolated.fetch(FetchDescriptor<CoachPhaseReview>()) where phase.planID == id { isolated.delete(phase) }
            let today = Self.civilDate(Date(), timeZone: Self.timeZone(plan))
            let periods = try isolated.fetch(FetchDescriptor<CoachNutritionTargetPeriod>()).filter { $0.planID == id }
            let retainedTargetRevisions = periods.filter { $0.startCivilDate < today }.compactMap(\.revisionID)
            for period in periods {
                if period.startCivilDate >= today { isolated.delete(period) }
                else if period.endCivilDate == nil || period.endCivilDate! > today { period.endCivilDate = today }
            }
            for suggestion in try isolated.fetch(FetchDescriptor<CoachProgressionSuggestion>()) where suggestion.planID == id && suggestion.statusRaw == "pending" { suggestion.statusRaw = "stale" }
            // A discarded draft has no historical prescription to retain.
            // Execution and earlier target-period provenance keep only revisions they use.
            var retainedRevisions = Set(executions.compactMap(\.prescriptionRevisionID))
            retainedRevisions.formUnion(retainedTargetRevisions)
            for revision in try isolated.fetch(FetchDescriptor<CoachPlanRevision>()) where revision.planID == id && !retainedRevisions.contains(revision.id) { isolated.delete(revision) }
            isolated.delete(plan)
            return Array(ids)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: deletedIDs.map { "coach.session.\($0.uuidString)" })
    }

    func beginExecution(occurrenceID: UUID) throws -> CoachSessionExecution {
        let executionID: UUID = try transaction { isolated in
            guard let row = try isolated.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == occurrenceID }), row.activityType != "rest" else { throw CoachRepositoryError.missingRecord }
            if let id = row.executionID, let current = try isolated.fetch(FetchDescriptor<CoachSessionExecution>()).first(where: { $0.id == id }) { return current.id }
            guard row.status == "pending" else { throw CoachRepositoryError.invalidValue("unstarted session") }
            guard row.plan?.status == CoachPlanStatus.active.rawValue else { throw CoachRepositoryError.invalidValue("active program before starting a new session") }
            if let planID = row.plan?.id, let phaseID = row.phaseID {
                let revisions = try isolated.fetch(FetchDescriptor<CoachPlanRevision>())
                guard let revision = revisions.first(where: { $0.id == row.revisionID }) else { throw CoachRepositoryError.missingRecord }
                let document = try JSONDecoder().decode(CoachPlanDocument.self, from: revision.documentData)
                guard let phase = document.phases.first(where: { $0.id == phaseID }) else { throw CoachRepositoryError.missingRecord }
                if phase.advanceMode == .reviewRequired {
                    let gates = try isolated.fetch(FetchDescriptor<CoachPhaseReview>())
                    guard gates.contains(where: { $0.planID == planID && $0.phaseID == phaseID && $0.statusRaw == "ready" && $0.revisionID == row.revisionID }) else {
                        throw CoachRepositoryError.invalidValue("readiness review for this phase and prescription revision")
                    }
                }
            }
            let execution = CoachSessionExecution(); execution.plannedSessionID = row.id
            execution.prescriptionRevisionID = row.revisionID; execution.prescriptionData = row.prescriptionData
            isolated.insert(execution); row.executionID = execution.id; row.status = "in_progress"
            return execution.id
        }
        guard let result = try context.fetch(FetchDescriptor<CoachSessionExecution>()).first(where: { $0.id == executionID }) else { throw CoachRepositoryError.missingRecord }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["coach.session.\(occurrenceID.uuidString)"])
        return result
    }

    func saveExecution(_ execution: CoachSessionExecution) throws {
        try requireLocal(); execution.updatedAt = Date(); try context.save()
    }

    func finishExecution(executionID: UUID, status: CoachExecutionStatus, notes: String? = nil, provenance: String = "recorded") throws {
        guard status != .inProgress else { throw CoachRepositoryError.invalidValue("finished outcome") }
        try requireLocal()
        guard let execution = try context.fetch(FetchDescriptor<CoachSessionExecution>()).first(where: { $0.id == executionID }) else { throw CoachRepositoryError.missingRecord }
        execution.statusRaw = status.rawValue; execution.endedAt = Date(); execution.notes = notes; execution.provenance = provenance; execution.updatedAt = Date()
        if let id = execution.plannedSessionID, let row = try context.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == id }) {
            row.status = status == .canceled ? "skipped" : status.rawValue
            row.completedAt = status == .canceled ? nil : execution.endedAt
            row.completedWorkoutSessionID = execution.workoutSessionID; row.completedRunningSessionID = execution.runSessionID
            row.completionProvenance = provenance
        }
        try context.save()
    }

    func reviewPhase(planID: UUID, phaseID: String, ready: Bool, notes: String? = nil, revisionID: UUID? = nil) throws {
        try transaction { isolated in
            let currentRevision = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == planID })?.currentRevisionID
            let selectedRevision = revisionID ?? currentRevision
            guard let review = try isolated.fetch(FetchDescriptor<CoachPhaseReview>()).first(where: { $0.planID == planID && $0.phaseID == phaseID && $0.revisionID == selectedRevision }) else { throw CoachRepositoryError.missingRecord }
            review.statusRaw = ready ? "ready" : "awaiting_review"; review.notes = notes; review.reviewedAt = Date()
        }
    }

    static func civilDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(_ civilDate: String, timeZone: TimeZone = .current) throws -> Date {
        let parts = civilDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { throw CoachRepositoryError.invalidValue("date") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), Self.civilDate(date, timeZone: timeZone) == civilDate else { throw CoachRepositoryError.invalidValue("date") }
        return date
    }

    static func timeZone(_ plan: TrainingPlan) -> TimeZone { TimeZone(identifier: plan.timeZoneIdentifier) ?? .current }
    private static func day(_ row: PlannedSession, plan: TrainingPlan) -> String { row.currentCivilDate ?? civilDate(row.scheduledDate, timeZone: timeZone(plan)) }
    private static func normalized(_ name: String) -> String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    private static func activityType(_ template: CoachSessionTemplate) -> String { template.kind == "running" ? "run" : template.kind }

    private static func shiftUnstarted(plan: TrainingPlan, to startDate: Date) throws {
        let zone = timeZone(plan); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let oldStart = calendar.startOfDay(for: plan.startDate), newStart = calendar.startOfDay(for: startDate)
        let days = calendar.dateComponents([.day], from: oldStart, to: newStart).day ?? 0
        for row in plan.sessions ?? [] where row.status == "pending" && row.executionID == nil {
            guard let date = calendar.date(byAdding: .day, value: days, to: row.scheduledDate) else { continue }
            row.scheduledDate = date; row.currentCivilDate = civilDate(date, timeZone: zone); row.scheduleRevision += 1
        }
        plan.startDate = startDate; plan.startCivilDate = civilDate(startDate, timeZone: zone)
    }

    static func createTargetPeriods(document: CoachPlanDocument, plan: TrainingPlan, context: ModelContext, effectiveFrom: Date? = nil) throws {
        guard document.nutritionTargets != nil || document.phases.contains(where: { $0.nutritionTargets != nil }) else { return }
        let zone = timeZone(plan); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let today = civilDate(Date(), timeZone: zone)
        let effective = effectiveFrom.map { civilDate($0, timeZone: zone) } ?? today
        guard effective >= today else { throw CoachRepositoryError.invalidValue("target effective date today or later") }
        let start = max(plan.startCivilDate ?? civilDate(plan.startDate, timeZone: zone), effective)
        guard let programEnd = calendar.date(byAdding: .day, value: document.weeks.count * 7, to: plan.startDate), civilDate(programEnd, timeZone: zone) > start else {
            throw CoachRepositoryError.invalidValue("target effective date within the program schedule")
        }
        for period in try context.fetch(FetchDescriptor<CoachNutritionTargetPeriod>()) where period.endCivilDate == nil || period.endCivilDate! > start {
            if period.startCivilDate < start { period.endCivilDate = start }
            else { context.delete(period) }
        }
        for (index, week) in document.weeks.enumerated() {
            let targets = document.phases.first { $0.id == week.phaseId }?.nutritionTargets ?? document.nutritionTargets
            guard let targets, let weekStart = calendar.date(byAdding: .day, value: index * 7, to: plan.startDate), let weekEnd = calendar.date(byAdding: .day, value: (index + 1) * 7, to: plan.startDate) else { continue }
            let end = civilDate(weekEnd, timeZone: zone); guard end > start else { continue }
            let period = CoachNutritionTargetPeriod(); period.planID = plan.id; period.phaseID = week.phaseId
            period.startCivilDate = max(civilDate(weekStart, timeZone: zone), start); period.endCivilDate = end
            period.timeZoneIdentifier = zone.identifier; period.calories = targets.caloriesKcal.map(Double.init)
            period.protein = targets.proteinGrams; period.carbs = targets.carbohydrateGrams; period.fat = targets.fatGrams
            period.notes = targets.notes; period.revisionID = plan.currentRevisionID; context.insert(period)
        }
    }
}
