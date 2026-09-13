#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachScheduleRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachScheduleChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: directory.appendingPathComponent("schedule.store"), cloudKitDatabase: .none)])
        let context = container.mainContext
        let repository = CoachRepository(context: context)
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw CoachExecutionCoordinator.ExecutionError.invalid("Schedule regression: " + message) }
        }
        var verificationContexts: [ModelContext] = []
        func freshContext() -> ModelContext {
            let fresh = ModelContext(container)
            verificationContexts.append(fresh)
            return fresh
        }
        func savedPlan(_ id: UUID) throws -> TrainingPlan {
            guard let row = try freshContext().fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == id }) else { throw CoachRepositoryError.missingRecord }; return row
        }
        func savedRows(_ id: UUID) throws -> [PlannedSession] { try CoachRepository(context: freshContext()).occurrences(planID: id) }
        func rejects(_ label: String, _ operation: () throws -> Void) throws {
            do { try operation() }
            catch { checks += 1; return }
            throw CoachExecutionCoordinator.ExecutionError.invalid("Schedule regression accepted: " + label)
        }
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let anchor = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: Date()))!
        let exercise = CoachStrengthExercise(id: "press", exercise: .init(key: "synthetic_press", name: "Synthetic Regression Press", equipment: ["dumbbells"]),
            prescriptionBasis: .perSide, loadBasis: .perImplement,
            sets: [.init(id: "working", role: .working, target: .reps(min: 6, max: 10))])
        var document = CoachPlanDocument(programId: "schedule_regression", title: "Synthetic 26-week program", goal: "General fitness",
            phases: [.init(id: "phase_one", title: "First phase", advanceMode: .reviewRequired), .init(id: "phase_two", title: "Second phase", advanceMode: .reviewRequired)],
            sessionTemplates: [.strength(.init(id: "lift", title: "Lift", exercises: [exercise])), .rest(.init(id: "rest", title: "Rest"))],
            weekPatterns: [.init(id: "pattern", title: "Weekly pattern", slots: [
                .init(id: "morning", dayOffset: 0, sessionTemplateId: "lift"),
                .init(id: "evening", dayOffset: 0, sessionTemplateId: "lift", optional: true),
                .init(id: "rest_day", dayOffset: 1, sessionTemplateId: "rest")])],
            weeks: (0..<26).map { .init(id: "week_\($0)", phaseId: $0 < 13 ? "phase_one" : "phase_two", weekPatternId: "pattern") })
        let validated = try CoachPlanValidator().validate(document)
        let expanded = try CoachSchedule.expand(validated, startDate: anchor, timeZone: zone)
        try require(expanded.count == 78 && Set(expanded.map(\.sourceKey)).count == 78, "26-week expansion has stable distinct occurrence identities")
        try require(expanded.filter { $0.weekIndex == 0 && $0.dayOffset == 0 }.map(\.intraDayOrder) == [0, 1], "two sessions on one day retain authored order")
        let cancellation = Task { @MainActor [document] in try await repository.importPlan(document: document, startDate: anchor, activate: false, allowCreatingExercises: true) }
        cancellation.cancel()
        do { _ = try await cancellation.value; throw CoachExecutionCoordinator.ExecutionError.invalid("Schedule regression accepted canceled import") }
        catch is CancellationError { checks += 1 }
        try require(try freshContext().fetchCount(FetchDescriptor<TrainingPlan>()) == 0, "canceled import commits no plan")
        do { _ = try await repository.importPlan(document: document, startDate: anchor, activate: false) }
        catch { checks += 1 }
        try require(try freshContext().fetchCount(FetchDescriptor<ExerciseDefinition>()) == 0, "unreviewed unknown exercise creates no library record")

        let planID = try await repository.importPlan(document: document, startDate: anchor, activate: false, allowCreatingExercises: true)
        let exactID = try await repository.importPlan(document: document, startDate: anchor, activate: false)
        let importedPlanCount = try freshContext().fetchCount(FetchDescriptor<TrainingPlan>())
        try require(planID == exactID && importedPlanCount == 1, "exact normalized reimport opens the same plan")
        var rows = try savedRows(planID)
        let firstID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.sourceSlotID == "morning" })!.id
        let secondID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.sourceSlotID == "evening" })!.id
        let restID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.activityType == "rest" })!.id
        try rejects("start draft") { _ = try repository.beginExecution(occurrenceID: firstID) }
        let staleRevision = UUID()
        document.revision = 2; document.title = "Reviewed synthetic revision"
        do {
            _ = try await repository.importPlan(document: document, startDate: anchor, activate: false, allowCreatingExercises: true,
                replacingDraftID: planID, expectedRevisionID: staleRevision)
            throw CoachExecutionCoordinator.ExecutionError.invalid("Schedule regression accepted stale draft revision")
        } catch CoachRepositoryError.revisionConflict { checks += 1 }
        let draftRevision = try savedPlan(planID).currentRevisionID
        _ = try await repository.importPlan(document: document, startDate: anchor, activate: false, allowCreatingExercises: true,
            replacingDraftID: planID, expectedRevisionID: draftRevision)
        rows = try savedRows(planID)
        let morningID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.sourceSlotID == "morning" })!.id
        let eveningID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.sourceSlotID == "evening" })!.id
        let newRestID = rows.first(where: { $0.sourceWeekID == "week_0" && $0.activityType == "rest" })!.id
        try require(try savedPlan(planID).sourceRevision == 2, "reviewed draft replacement saves its revision")
        try repository.activate(planID: planID)
        try rejects("unreviewed first phase") { _ = try repository.beginExecution(occurrenceID: morningID) }
        try repository.reviewPhase(planID: planID, phaseID: "phase_one", ready: true)
        let firstExecution = try repository.beginExecution(occurrenceID: morningID)
        let resumed = try repository.beginExecution(occurrenceID: morningID)
        try require(firstExecution.id == resumed.id, "repeat Start resumes exact occurrence")
        try repository.setPlanStatus(planID: planID, status: .paused)
        try require(try repository.beginExecution(occurrenceID: morningID).id == firstExecution.id, "pausing a plan preserves an active execution")
        try rejects("new Start from paused plan") { _ = try repository.beginExecution(occurrenceID: eveningID) }
        try repository.activate(planID: planID)
        try repository.finishExecution(executionID: firstExecution.id, status: .partial, notes: "Known partial activity", provenance: "recorded")
        let originalPrescription = try savedRows(planID).first(where: { $0.id == morningID })!.prescriptionData
        let phaseTwoID = rows.first(where: { $0.sourceWeekID == "week_13" && $0.sourceSlotID == "morning" })!.id
        try rejects("later phase awaiting review") { _ = try repository.beginExecution(occurrenceID: phaseTwoID) }
        try repository.transaction { isolated in
            for gate in try isolated.fetch(FetchDescriptor<CoachPhaseReview>()) where gate.planID == planID && gate.phaseID == "phase_two" { isolated.delete(gate) }
        }
        try rejects("missing phase gate") { _ = try repository.beginExecution(occurrenceID: phaseTwoID) }

        let beforeMove = try savedRows(planID).first(where: { $0.id == eveningID })!
        let originalCivil = beforeMove.originalCivilDate
        let preview = try repository.schedulePreview(planID: planID, selected: [eveningID], dayOffset: 2)
        let previewVersion = try savedPlan(planID).updatedAt
        try repository.applySchedule(preview, planID: planID, expectedUpdatedAt: previewVersion)
        let moved = try savedRows(planID).first(where: { $0.id == eveningID })!
        try require(moved.id == eveningID && moved.originalCivilDate == originalCivil && moved.currentCivilDate == preview.first?.to && moved.executionID == nil, "move preserves identity and original civil date")
        try require(moved.localScheduleOverride, "manual schedule move records a local override")
        try rejects("stale schedule preview") { try repository.applySchedule(preview, planID: planID, expectedUpdatedAt: previewVersion) }
        let restPreview = try repository.schedulePreview(planID: planID, selected: [newRestID], dayOffset: -1)
        try rejects("rest conflicts with training") { try repository.applySchedule(restPreview, planID: planID, expectedUpdatedAt: savedPlan(planID).updatedAt) }
        try rejects("moving started or terminal occurrence") { _ = try repository.schedulePreview(planID: planID, selected: [morningID], dayOffset: 1) }
        let beforeRepeatIDs = Set(try savedRows(planID).map(\.id))
        try repository.repeatWeek(planID: planID, sourceWeekID: "week_1", startDate: calendar.date(byAdding: .day, value: 200, to: anchor)!, expectedUpdatedAt: savedPlan(planID).updatedAt)
        let afterRepeat = try savedRows(planID)
        try require(afterRepeat.count == beforeRepeatIDs.count + 3 && beforeRepeatIDs.isSubset(of: Set(afterRepeat.map(\.id))), "repeat week adds new identities while retaining every prior occurrence")

        var changed = document
        changed.revision = 3
        if case var .strength(strength) = changed.sessionTemplates[0] {
            strength.exercises[0].sets[0].target = .reps(min: 7, max: 11)
            changed.sessionTemplates[0] = .strength(strength)
        }
        changed.weekPatterns[0].slots.removeAll { $0.id == "evening" }
        changed.weekPatterns[0].slots[0].dayOffset = 2
        changed.weekPatterns[0].slots.append(.init(id: "additional", dayOffset: 3, sessionTemplateId: "lift"))
        changed.weeks.swapAt(1, 2)
        let incoming = try CoachPlanValidator().validate(changed)
        let selectedFuture = afterRepeat.first { $0.sourceWeekID == "week_1" && $0.sourceSlotID == "morning" }!
        let removedFuture = afterRepeat.first { $0.sourceWeekID == "week_1" && $0.sourceSlotID == "evening" }!
        let untouched = afterRepeat.first { $0.sourceWeekID == "week_2" && $0.sourceSlotID == "morning" }!
        let untouchedData = untouched.prescriptionData
        let selectedFutureData = selectedFuture.prescriptionData
        let current = try savedPlan(planID)
        try await repository.applyRevision(incoming, planID: planID, selected: [selectedFuture.id, removedFuture.id],
            addSourceKeys: [CoachSchedule.sourceKey(programId: document.programId, weekId: "week_1", slotId: "additional")],
            expectedRevisionID: current.currentRevisionID, expectedUpdatedAt: current.updatedAt)
        let revisedRows = try savedRows(planID)
        try require(revisedRows.first(where: { $0.id == morningID })?.prescriptionData == originalPrescription && revisedRows.first(where: { $0.id == morningID })?.status == "partial", "revision preserves finished prescription and outcome")
        try require(revisedRows.first(where: { $0.id == untouched.id })?.prescriptionData == untouchedData, "revision leaves unselected future prescriptions unchanged")
        try require(revisedRows.first(where: { $0.id == removedFuture.id })?.status == "skipped" && revisedRows.contains(where: { $0.sourceWeekID == "week_1" && $0.sourceSlotID == "additional" }), "reviewed removal and addition apply only selected source identities")
        try require(revisedRows.first(where: { $0.id == selectedFuture.id })?.prescriptionData != selectedFutureData, "selected future prescription changes")
        let revisedFuture = revisedRows.first { $0.id == selectedFuture.id }!
        try require(revisedFuture.weekIndex == 2 && revisedFuture.dayIndex == 3 && revisedFuture.scheduleRevision > 0 && !revisedFuture.localScheduleOverride,
            "reviewed date change updates authored week/day indices without becoming a local override")
        try rejects("new prescription revision without readiness review") { _ = try repository.beginExecution(occurrenceID: selectedFuture.id) }
        let summary = try CoachRepository(context: freshContext()).progress(planID: planID)
        try require(summary.partial == 1 && summary.completed == 0 && summary.required < revisedRows.count, "rest and optional occurrences do not inflate required completion")
        // Retained objects and a fresh context must agree on the durable outcome.
        let visible = try repository.occurrences(planID: planID).first { $0.id == morningID }
        let persisted = revisedRows.first { $0.id == morningID }
        try require(visible?.status == persisted?.status && visible?.completedAt == persisted?.completedAt, "view context reads the same status as fresh on-disk capture")
        var nextDocument = changed
        nextDocument.revision = 4
        if case var .strength(strength) = nextDocument.sessionTemplates[0] {
            strength.exercises[0].sets[0].target = .reps(min: 8, max: 12)
            nextDocument.sessionTemplates[0] = .strength(strength)
        }
        let nextRevision = try CoachPlanValidator().validate(nextDocument)
        let precedingFutureRevisionID = revisedFuture.revisionID
        let precedingFutureCivilDate = revisedFuture.currentCivilDate
        let nextExpectedRevisionID = try savedPlan(planID).currentRevisionID
        let nextExpectedUpdatedAt = try savedPlan(planID).updatedAt
        do {
            try await repository.applyRevision(nextRevision, planID: planID, selected: [eveningID], addSourceKeys: [],
                expectedRevisionID: nextExpectedRevisionID, expectedUpdatedAt: nextExpectedUpdatedAt)
            throw CoachExecutionCoordinator.ExecutionError.invalid("Schedule regression accepted revision over a local schedule override")
        } catch CoachRepositoryError.futureOnly { checks += 1 }
        try await repository.applyRevision(nextRevision, planID: planID, selected: [selectedFuture.id], addSourceKeys: [],
            expectedRevisionID: nextExpectedRevisionID, expectedUpdatedAt: nextExpectedUpdatedAt)
        let revisedAgain = try savedRows(planID).first { $0.id == selectedFuture.id }!
        try require(revisedAgain.revisionID != precedingFutureRevisionID && revisedAgain.currentCivilDate == precedingFutureCivilDate && !revisedAgain.localScheduleOverride,
            "a date changed by an earlier program revision remains eligible for later reviewed prescriptions")
        let beforeReviewedRepeat = Set(try savedRows(planID).map(\.id))
        let repeatAnchor = calendar.date(byAdding: .day, value: 220, to: anchor)!
        try repository.repeatWeek(planID: planID, sourceWeekID: "week_1", startDate: repeatAnchor, expectedUpdatedAt: savedPlan(planID).updatedAt)
        let repeatedRevisedRows = try savedRows(planID).filter { !beforeReviewedRepeat.contains($0.id) }
        try require(repeatedRevisedRows.count == 3 && !repeatedRevisedRows.contains(where: { $0.sourceSlotID == "evening" }),
            "repeating a reviewed week excludes removed audit rows")
        let expectedRepeatedMorning = CoachSchedule.civilDate(calendar.date(byAdding: .day, value: 2, to: repeatAnchor)!, timeZone: zone)
        try require(repeatedRevisedRows.first(where: { $0.sourceSlotID == "morning" })?.currentCivilDate == expectedRepeatedMorning,
            "repeating a revised week uses its revised authored day index")
        _ = [firstID, secondID, restID] // Original draft IDs were intentionally replaced before any execution existed.
        return checks
    }
}
#endif
