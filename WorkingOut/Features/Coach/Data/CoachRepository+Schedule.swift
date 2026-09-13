import Foundation
import SwiftData
import UserNotifications

struct CoachScheduleChange: Identifiable {
    var id: UUID
    var title: String
    var from: String
    var to: String
    var order: Int
}

extension CoachRepository {
    func schedulePreview(planID: UUID, selected: Set<UUID>, dayOffset: Int) throws -> [CoachScheduleChange] {
        guard let plan = try plans().first(where: { $0.id == planID }) else { throw CoachRepositoryError.missingRecord }
        let zone = Self.timeZone(plan)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return try occurrences(planID: planID).filter { selected.contains($0.id) }.map { row in
            guard row.status == "pending", row.executionID == nil,
                  let date = calendar.date(byAdding: .day, value: dayOffset, to: row.scheduledDate) else { throw CoachRepositoryError.futureOnly }
            return .init(id: row.id, title: row.title, from: row.currentCivilDate ?? Self.civilDate(row.scheduledDate, timeZone: zone),
                         to: Self.civilDate(date, timeZone: zone), order: row.intraDayOrder)
        }
    }

    func applySchedule(_ changes: [CoachScheduleChange], planID: UUID, expectedUpdatedAt: Date) throws {
        try transaction { isolated in
            guard let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == planID }),
                  plan.updatedAt == expectedUpdatedAt else { throw CoachRepositoryError.revisionConflict }
            let zone = Self.timeZone(plan)
            let rows = try isolated.fetch(FetchDescriptor<PlannedSession>()).filter { $0.plan?.id == planID }
            let mappings = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>())
            for change in changes {
                guard let row = rows.first(where: { $0.id == change.id }), row.status == "pending", row.executionID == nil,
                      (row.currentCivilDate ?? Self.civilDate(row.scheduledDate, timeZone: zone)) == change.from else { throw CoachRepositoryError.futureOnly }
                row.scheduledDate = try Self.date(change.to, timeZone: zone); row.currentCivilDate = change.to
                row.intraDayOrder = change.order; row.scheduleRevision += 1; row.localScheduleOverride = true
                for mapping in mappings where mapping.plannedSessionID == row.id { mapping.pendingProjection = true }
            }
            try Self.validateScheduleDays(rows)
            plan.updatedAt = Date()
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: changes.map { "coach.session.\($0.id.uuidString)" })
    }

    func repeatWeek(planID: UUID, sourceWeekID: String, startDate: Date, expectedUpdatedAt: Date) throws {
        try transaction { isolated in
            guard let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == planID }),
                  plan.updatedAt == expectedUpdatedAt else { throw CoachRepositoryError.revisionConflict }
            let original = (plan.sessions ?? []).filter { $0.sourceWeekID == sourceWeekID && $0.completionProvenance != "removed_by_reviewed_revision" }.sorted { ($0.dayIndex, $0.intraDayOrder) < ($1.dayIndex, $1.intraDayOrder) }
            guard !original.isEmpty else { throw CoachRepositoryError.missingRecord }
            let zone = Self.timeZone(plan); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let weekID = UUID().uuidString
            let index = (plan.sessions ?? []).map(\.weekIndex).max().map { $0 + 1 } ?? 0
            guard index < 104, (plan.sessions ?? []).count + original.count <= 5_824 else { throw CoachRepositoryError.invalidValue("program within 104 weeks and 5,824 sessions") }
            var created: [PlannedSession] = []
            for source in original {
                let date = calendar.date(byAdding: .day, value: source.dayIndex - 1, to: startDate)!
                let row = PlannedSession(plan: plan, title: source.title, activityType: source.activityType,
                                         scheduledDate: date, weekIndex: index, dayIndex: source.dayIndex, notes: source.notes)
                row.sourceWeekID = weekID; row.sourceSlotID = source.sourceSlotID; row.sourceTemplateID = source.sourceTemplateID
                row.phaseID = source.phaseID; row.prescriptionData = source.prescriptionData; row.revisionID = source.revisionID
                row.originalCivilDate = Self.civilDate(date, timeZone: zone); row.currentCivilDate = row.originalCivilDate
                row.intraDayOrder = source.intraDayOrder; row.isOptional = source.isOptional
                isolated.insert(row)
                created.append(row)
            }
            try Self.validateScheduleDays((plan.sessions ?? []) + created.filter { candidate in !(plan.sessions ?? []).contains { $0.id == candidate.id } })
            plan.durationWeeks = max(plan.durationWeeks, index + 1); plan.updatedAt = Date()
        }
    }

    static func validateScheduleDays(_ rows: [PlannedSession]) throws {
        let days = Dictionary(grouping: rows.filter { $0.status != "skipped" }, by: { $0.currentCivilDate ?? "" })
        for day in days.values {
            guard day.count <= 8 else { throw CoachRepositoryError.invalidValue("at most eight sessions on a day") }
            guard !day.contains(where: { $0.activityType == "rest" }) || day.count == 1 else {
                throw CoachRepositoryError.invalidValue("schedule without rest and training on the same day")
            }
            let ordered = day.sorted { ($0.intraDayOrder, $0.id.uuidString) < ($1.intraDayOrder, $1.id.uuidString) }
            for (order, row) in ordered.enumerated() where row.status == "pending" && row.executionID == nil { row.intraDayOrder = order }
        }
    }

    /// Reviewed active revisions preserve all historical and locally moved rows.
    /// Selection is by occurrence UUID; matching source IDs never authorize edits.
    func applyRevision(_ incoming: CoachValidatedProgram, planID: UUID, selected: Set<UUID>,
                       addSourceKeys: Set<String>, expectedRevisionID: UUID?, expectedUpdatedAt: Date,
                       exerciseSelections: [String: UUID] = [:], allowCustomExercises: Bool = false,
                       applyNutritionTargetsFrom: Date? = nil) async throws {
        try requireLocal()
        guard let current = try plans().first(where: { $0.id == planID }) else { throw CoachRepositoryError.missingRecord }
        let start = current.startDate, zone = Self.timeZone(current)
        let exerciseMappings = try self.exerciseMappings(for: incoming.document)
        for mapping in exerciseMappings {
            if mapping.requiresSelection && exerciseSelections[mapping.id] == nil { throw CoachRepositoryError.ambiguousExercise(mapping.choice.name) }
            if mapping.candidates.isEmpty && exerciseSelections[mapping.id] == nil && !allowCustomExercises { throw CoachRepositoryError.ambiguousExercise(mapping.choice.name) }
        }
        let expanded = try await Task.detached { try CoachSchedule.expand(incoming, startDate: start, timeZone: zone) }.value
        try Task.checkCancellation()
        try transaction { isolated in
            guard let plan = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == planID }),
                  plan.currentRevisionID == expectedRevisionID, plan.updatedAt == expectedUpdatedAt,
                  plan.sourceProgramID == incoming.document.programId, incoming.document.revision > plan.sourceRevision else { throw CoachRepositoryError.revisionConflict }
            let today = Self.civilDate(Date(), timeZone: zone)
            let rows = (plan.sessions ?? [])
            guard selected.isSubset(of: Set(rows.map(\.id))), addSourceKeys.isSubset(of: Set(expanded.map(\.sourceKey))),
                  rows.count + addSourceKeys.count <= 5_824 else { throw CoachRepositoryError.invalidValue("existing selected sessions and a program within 5,824 occurrences") }
            let calendarMappings = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>())
            var additions: [PlannedSession] = []
            let newRevision = CoachPlanRevision()
            newRevision.planID = plan.id; newRevision.documentData = incoming.canonicalData
            newRevision.sourceProgramID = incoming.document.programId; newRevision.sourceRevision = incoming.document.revision
            newRevision.fingerprint = incoming.fingerprint; newRevision.provenance = "reviewed_revision"
            if let previous = try isolated.fetch(FetchDescriptor<CoachPlanRevision>()).first(where: { $0.id == expectedRevisionID }) {
                newRevision.exerciseMappingsData = previous.exerciseMappingsData
            }
            var resolvedMappings = exerciseSelections
            let definitions = try isolated.fetch(FetchDescriptor<ExerciseDefinition>())
            for mapping in exerciseMappings {
                if let selectedID = resolvedMappings[mapping.id] {
                    guard definitions.contains(where: { $0.id == selectedID }) else { throw CoachRepositoryError.ambiguousExercise(mapping.choice.name) }
                } else if let candidate = mapping.candidates.first { resolvedMappings[mapping.id] = candidate.id }
                else {
                    let definition = ExerciseDefinition(name: mapping.choice.name, muscleGroup: "Other", isUserDefined: true)
                    isolated.insert(definition); resolvedMappings[mapping.id] = definition.id
                }
            }
            newRevision.exerciseMappingsData = try JSONEncoder().encode(resolvedMappings)
            isolated.insert(newRevision)
            for row in rows where selected.contains(row.id) {
                for mapping in calendarMappings where mapping.plannedSessionID == row.id { mapping.pendingProjection = true }
                guard row.status == "pending", row.executionID == nil, !row.localScheduleOverride,
                      (row.currentCivilDate ?? "") >= today else { throw CoachRepositoryError.futureOnly }
                guard let source = expanded.first(where: { $0.weekId == row.sourceWeekID && $0.slotId == row.sourceSlotID }) else {
                    // Removed future prescription remains a visible skipped row,
                    // retaining its source identity for backup and audit.
                    row.status = "skipped"; row.completionProvenance = "removed_by_reviewed_revision"; continue
                }
                row.title = source.label ?? source.template.title;
                row.notes = [source.notes, source.template.notes].compactMap { $0 }.joined(separator: "\n"); row.prescriptionData = try JSONEncoder().encode(source.template)
                row.activityType = source.template.kind == "running" ? "run" : source.template.kind
                row.sourceTemplateID = source.templateId; row.revisionID = newRevision.id; row.phaseID = source.phaseId
                row.isOptional = source.isOptional
                row.weekIndex = source.weekIndex; row.dayIndex = source.dayOffset + 1
                if row.currentCivilDate != source.civilDate {
                    row.currentCivilDate = source.civilDate; row.scheduledDate = try Self.date(source.civilDate, timeZone: zone)
                    row.scheduleRevision += 1
                }
                row.intraDayOrder = source.intraDayOrder
            }
            for source in expanded where addSourceKeys.contains(source.sourceKey) {
                guard source.civilDate >= today, !rows.contains(where: { $0.sourceWeekID == source.weekId && $0.sourceSlotID == source.slotId }) else { throw CoachRepositoryError.futureOnly }
                let row = PlannedSession(plan: plan, title: source.label ?? source.template.title, activityType: source.template.kind == "running" ? "run" : source.template.kind,
                    scheduledDate: try Self.date(source.civilDate, timeZone: zone), weekIndex: source.weekIndex, dayIndex: source.dayOffset + 1,
                    notes: [source.notes, source.template.notes].compactMap { $0 }.joined(separator: "\n"))
                row.sourceWeekID = source.weekId; row.sourceSlotID = source.slotId; row.sourceTemplateID = source.templateId
                row.phaseID = source.phaseId; row.prescriptionData = try JSONEncoder().encode(source.template); row.revisionID = newRevision.id
                row.originalCivilDate = source.civilDate; row.currentCivilDate = source.civilDate; row.intraDayOrder = source.intraDayOrder; row.isOptional = source.isOptional
                isolated.insert(row); additions.append(row)
            }
            try Self.validateScheduleDays(rows + additions)
            for phase in incoming.document.phases where phase.advanceMode == .reviewRequired {
                let gate = CoachPhaseReview(); gate.planID = plan.id; gate.phaseID = phase.id; gate.revisionID = newRevision.id
                isolated.insert(gate)
            }
            plan.title = incoming.document.title; plan.goal = incoming.document.goal
            plan.overview = incoming.document.overview; plan.guidance = incoming.document.guidance
            plan.durationWeeks = max(plan.durationWeeks, incoming.document.weeks.count)
            plan.currentRevisionID = newRevision.id; plan.sourceRevision = incoming.document.revision
            plan.fingerprint = incoming.fingerprint; plan.updatedAt = Date()
            if let applyNutritionTargetsFrom {
                try Self.createTargetPeriods(document: incoming.document, plan: plan, context: isolated, effectiveFrom: applyNutritionTargetsFrom)
            }
            for suggestion in try isolated.fetch(FetchDescriptor<CoachProgressionSuggestion>()) where suggestion.planID == planID && suggestion.statusRaw == "pending" { suggestion.statusRaw = "stale" }
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: selected.map { "coach.session.\($0.uuidString)" })
    }
}
