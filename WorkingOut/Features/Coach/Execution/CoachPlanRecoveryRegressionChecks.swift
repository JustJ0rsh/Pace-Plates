#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachPlanRecoveryRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachPlanRecoveryChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: directory.appendingPathComponent("recovery.store"), cloudKitDatabase: .none)])
        var contexts: [ModelContext] = []
        var checks = 0
        func repository() -> CoachRepository {
            let context = ModelContext(container); context.autosaveEnabled = false; contexts.append(context)
            return CoachRepository(context: context)
        }
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw CoachRepositoryError.invalidValue("plan recovery regression: " + message) }
        }
        func plan(_ id: UUID) throws -> TrainingPlan { try repository().plans().first { $0.id == id }! }
        func rows(_ id: UUID) throws -> [PlannedSession] { try repository().occurrences(planID: id) }
        func document(_ id: String, calories: Int? = nil) -> CoachPlanDocument {
            CoachPlanDocument(programId: id, title: id, goal: "Synthetic recovery checks",
                nutritionTargets: calories.map { .init(caloriesKcal: $0) },
                phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
                sessionTemplates: [.recovery(.init(id: "mobility", title: "Mobility", instructions: "Gentle mobility")), .rest(.init(id: "rest", title: "Rest"))],
                weekPatterns: [.init(id: "pattern", title: "Week", slots: [
                    .init(id: "a", dayOffset: 1, sessionTemplateId: "mobility"),
                    .init(id: "b", dayOffset: 2, sessionTemplateId: "mobility")])],
                weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() }
            catch { checks += 1; return }
            throw CoachRepositoryError.invalidValue("plan recovery regression accepted " + message)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        let now = Date(), future = calendar.date(byAdding: .day, value: 2, to: now)!

        let a = try await repository().importPlan(document: document("targets_a", calories: 2000), startDate: now, activate: true)
        let logID = try repository().saveNutrition(date: now, calories: 1900, protein: nil, carbs: nil, fat: nil)
        let snapshot = try repository().nutritionLogs().first { $0.id == logID }!.targetSnapshotData
        let b = try await repository().importPlan(document: document("targets_b", calories: 2500), startDate: now, activate: true)
        try require(try repository().nutritionTarget(on: now)?.calories == 2500, "switching to B applies B's targets")
        try repository().activate(planID: a)
        let resumedTarget = try repository().nutritionTarget(on: now)
        try require(resumedTarget?.planID == a && resumedTarget?.calories == 2000, "resuming A replaces B's future targets")
        try require(try repository().nutritionLogs().first { $0.id == logID }?.targetSnapshotData == snapshot, "switching plans preserves saved daily target snapshots")
        try repository().setPlanStatus(planID: a, status: .paused)
        let manualID = try repository().saveNutritionTarget(date: now, calories: 2100, protein: nil, carbs: nil, fat: nil)
        try repository().activate(planID: a)
        try require(try repository().nutritionTarget(on: now)?.id == manualID, "same-plan pause/resume preserves manual target edits")
        try repository().activate(planID: b)
        _ = try repository().saveNutritionTarget(date: calendar.date(byAdding: .day, value: 1, to: now)!, calories: 2200, protein: nil, carbs: nil, fat: nil)
        try repository().setPlanStatus(planID: b, status: .paused)
        try repository().activate(planID: a)
        try require(try repository().nutritionTarget(on: now)?.planID == a, "future manual guidance cannot hide the displaced plan's current targets when resuming")
        try repository().activate(planID: b)
        let targetFree = try await repository().importPlan(document: document("target_free"), startDate: now, activate: true)
        try require(try plan(targetFree).status == "active" && repository().nutritionTarget(on: now) == nil, "a target-free plan activates without inheriting displaced plan targets")
        try repository().activate(planID: b)
        let past = calendar.date(byAdding: .day, value: -30, to: now)!
        let expired = try await repository().importPlan(document: document("expired", calories: 1800), startDate: past, activate: false)
        try repository().activate(planID: expired)
        try require(try plan(expired).status == "active" && repository().nutritionTarget(on: now) == nil, "expired targets do not block activity-plan activation or inherit other guidance")

        var restPlan = document("undo_skip_rest")
        restPlan.weekPatterns[0].slots = [.init(id: "rest", dayOffset: 0, sessionTemplateId: "rest"), .init(id: "work", dayOffset: 1, sessionTemplateId: "mobility")]
        let restPlanID = try await repository().importPlan(document: restPlan, startDate: future, activate: true)
        let restID = try rows(restPlanID).first { $0.sourceSlotID == "rest" }!.id
        let workID = try rows(restPlanID).first { $0.sourceSlotID == "work" }!.id
        try repository().markSession(id: restID, status: .skipped)
        try repository().moveSession(id: workID, to: future)
        let beforeRejectedUndo = try plan(restPlanID).updatedAt
        try rejects("Undo Skip creating a rest/training conflict") { try repository().markSession(id: restID, status: .pending) }
        try require(try rows(restPlanID).first { $0.id == restID }?.status == "skipped" && plan(restPlanID).updatedAt == beforeRejectedUndo,
                    "failed Undo Skip rolls back the occurrence and plan version")
        try repository().moveSession(id: workID, to: calendar.date(byAdding: .day, value: 2, to: future)!)
        let beforeValidUndo = try plan(restPlanID).updatedAt
        try repository().markSession(id: restID, status: .pending)
        try require(try rows(restPlanID).first { $0.id == restID }?.status == "pending" && plan(restPlanID).updatedAt != beforeValidUndo,
                    "valid Undo Skip persists and invalidates stale schedule reviews")

        var fullDay = document("undo_skip_limit")
        fullDay.weekPatterns[0].slots = (0..<8).map { .init(id: "slot_\($0)", dayOffset: 0, sessionTemplateId: "mobility") }
            + [.init(id: "extra", dayOffset: 1, sessionTemplateId: "mobility")]
        let fullDayID = try await repository().importPlan(document: fullDay, startDate: future, activate: true)
        let skippedID = try rows(fullDayID).first { $0.sourceSlotID == "slot_0" }!.id
        let extraID = try rows(fullDayID).first { $0.sourceSlotID == "extra" }!.id
        try repository().markSession(id: skippedID, status: .skipped)
        try repository().moveSession(id: extraID, to: future)
        try rejects("Undo Skip creating a ninth session") { try repository().markSession(id: skippedID, status: .pending) }
        try require(try rows(fullDayID).filter { $0.status != "skipped" }.count == 8, "session limit rejection preserves the valid eight-session day")

        var restoredDocument = document("restore_slot")
        let restoredPlanID = try await repository().importPlan(document: restoredDocument, startDate: future, activate: true)
        let originalRows = try rows(restoredPlanID)
        let restoredID = originalRows.first { $0.sourceSlotID == "a" }!.id
        restoredDocument.revision = 2; restoredDocument.weekPatterns[0].slots.removeFirst()
        var version = try plan(restoredPlanID)
        try await repository().applyRevision(CoachPlanValidator().validate(restoredDocument), planID: restoredPlanID, selected: [restoredID], addSourceKeys: [], expectedRevisionID: version.currentRevisionID, expectedUpdatedAt: version.updatedAt)
        restoredDocument = document("restore_slot"); restoredDocument.revision = 3
        version = try plan(restoredPlanID)
        try await repository().applyRevision(CoachPlanValidator().validate(restoredDocument), planID: restoredPlanID, selected: [], addSourceKeys: [], expectedRevisionID: version.currentRevisionID, expectedUpdatedAt: version.updatedAt)
        try require(try rows(restoredPlanID).first { $0.id == restoredID }?.completionProvenance == "removed_by_reviewed_revision", "reintroducing an authored slot does not silently restore it")
        restoredDocument.revision = 4
        restoredDocument.sessionTemplates[0] = .recovery(.init(id: "mobility", title: "Reviewed mobility", instructions: "Updated guidance"))
        version = try plan(restoredPlanID)
        try await repository().applyRevision(CoachPlanValidator().validate(restoredDocument), planID: restoredPlanID, selected: [], addSourceKeys: [], expectedRevisionID: version.currentRevisionID, expectedUpdatedAt: version.updatedAt, restoreRemovedIDs: [restoredID])
        let restoredRows = try rows(restoredPlanID)
        let restored = restoredRows.first { $0.id == restoredID }!
        try require(restoredRows.count == originalRows.count && restored.status == "pending" && restored.completionProvenance == nil,
                    "explicit restoration reuses the occurrence identity without duplicates")
        try require(try restored.revisionID == plan(restoredPlanID).currentRevisionID && restored.title == "Reviewed mobility", "restoration applies the reviewed prescription and revision")
        restoredDocument.revision = 5
        let next = try CoachPlanValidator().validate(restoredDocument)
        let yesterday = CoachRepository.civilDate(calendar.date(byAdding: .day, value: -1, to: now)!)
        for invalidState in ["started", "history", "local", "past", "manual_skip"] {
            try repository().transaction { context in
                let row = try context.fetch(FetchDescriptor<PlannedSession>()).first { $0.id == restoredID }!
                row.status = "skipped"; row.completionProvenance = "removed_by_reviewed_revision"
                row.executionID = invalidState == "started" ? UUID() : nil
                row.completedAt = invalidState == "history" ? now : nil
                row.localScheduleOverride = invalidState == "local"
                row.currentCivilDate = invalidState == "past" ? yesterday : CoachRepository.civilDate(calendar.date(byAdding: .day, value: 1, to: future)!)
                if invalidState == "manual_skip" { row.completionProvenance = "manual_attestation" }
            }
            version = try plan(restoredPlanID)
            do {
                try await repository().applyRevision(next, planID: restoredPlanID, selected: [], addSourceKeys: [], expectedRevisionID: version.currentRevisionID, expectedUpdatedAt: version.updatedAt, restoreRemovedIDs: [restoredID])
                throw CoachRepositoryError.invalidValue("plan recovery regression accepted restoration over " + invalidState)
            } catch CoachRepositoryError.futureOnly { checks += 1 }
            try require(try plan(restoredPlanID).currentRevisionID == version.currentRevisionID, "rejected restoration over \(invalidState) commits no revision")
        }
        return checks
    }
}
#endif
