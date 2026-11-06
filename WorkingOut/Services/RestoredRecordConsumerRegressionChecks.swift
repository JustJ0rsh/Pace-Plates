#if DEBUG
import Foundation
import SwiftData

@MainActor
enum RestoredRecordConsumerRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RestoredRecordConsumers-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let configuration = ModelConfiguration(CoachPersistence.configurationName, schema: schema,
            url: directory.appendingPathComponent("consumers.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        context.autosaveEnabled = false
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw CoachRepositoryError.invalidValue("restored-record regression: " + message) }
        }
        func rejectsAmbiguity(_ operation: () throws -> Void) throws {
            do { try operation() }
            catch CoachRepositoryError.ambiguousRecord { checks += 1; return }
            throw CoachRepositoryError.invalidValue("duplicate identifier rejection")
        }
        let plan = TrainingPlan(title: "Synthetic preserved rows", goal: "Review", source: "manual", startDate: Date())
        context.insert(plan)
        let duplicatedOccurrenceID = UUID()
        let duplicateOccurrences = ["First preserved occurrence", "Second preserved occurrence"].map { title in
            let row = PlannedSession(id: duplicatedOccurrenceID, plan: plan, title: title, activityType: "run", scheduledDate: Date(), weekIndex: 0, dayIndex: 1)
            context.insert(row); return row
        }
        let ambiguousRunTarget = PlannedSession(plan: plan, title: "Ambiguous actual", activityType: "run", scheduledDate: Date(), weekIndex: 0, dayIndex: 2)
        let exactTarget = PlannedSession(plan: plan, title: "Unique actual", activityType: "run", scheduledDate: Date(), weekIndex: 0, dayIndex: 3)
        context.insert(ambiguousRunTarget); context.insert(exactTarget)
        let runForDuplicate = RunningSession(distance: 1, duration: 600, plannedSessionID: duplicatedOccurrenceID)
        let exactRun = RunningSession(distance: 2, duration: 900, plannedSessionID: exactTarget.id)
        context.insert(runForDuplicate); context.insert(exactRun)
        let duplicatedRunID = UUID()
        let duplicateRuns = (0..<2).map { index in
            let row = RunningSession(id: duplicatedRunID, date: Date().addingTimeInterval(Double(index) * -86_400), distance: Double(index + 3), duration: 1000,
                notes: "Preserved run \(index)", plannedSessionID: ambiguousRunTarget.id)
            context.insert(row); return row
        }
        let duplicatedSourceID = UUID()
        for title in ["Source A", "Source B"] {
            let source = RunningPlan(name: title, source: "manual", style: "hybrid", targetDistanceMeters: 1000, primaryGoal: "fitness", durationWeeks: 1, daysPerWeek: 1, startDate: Date())
            source.id = duplicatedSourceID; context.insert(source)
        }
        try context.save()
        let initialOccurrenceCount = try context.fetchCount(FetchDescriptor<PlannedSession>())
        let initialRunCount = try context.fetchCount(FetchDescriptor<RunningSession>())
        TrainingPlanService.shared.syncRunningPlans(context: context)
        let verification = ModelContext(container)
        let savedOccurrences = try verification.fetch(FetchDescriptor<PlannedSession>())
        try require(savedOccurrences.count == initialOccurrenceCount && savedOccurrences.filter { $0.id == duplicatedOccurrenceID }.count == 2,
            "normal launch preserves both duplicate occurrence records")
        try require(savedOccurrences.filter { $0.id == duplicatedOccurrenceID }.allSatisfy { $0.status == "pending" && $0.completedRunningSessionID == nil },
            "an ambiguous occurrence link never chooses a completion winner")
        try require(savedOccurrences.first { $0.id == ambiguousRunTarget.id }?.status == "pending", "duplicate actual UUIDs never invent a completion link")
        try require(savedOccurrences.first { $0.id == exactTarget.id }?.completedRunningSessionID == exactRun.id, "unique legacy completion still reconciles")
        try require(try verification.fetch(FetchDescriptor<TrainingPlan>()).filter { $0.sourceRunningPlanID == duplicatedSourceID }.isEmpty,
            "ambiguous source plans never create or relink derived plans")
        TrainingPlanService.shared.syncRunningPlans(context: context)
        try require(try context.fetchCount(FetchDescriptor<RunningSession>()) == initialRunCount
            && context.fetchCount(FetchDescriptor<PlannedSession>()) == initialOccurrenceCount, "repeated launch does not duplicate or remove preserved history")

        let page = try RunHistoryStore.fetch(context: context, search: "Preserved run", range: .all, activity: nil, limit: 20)
        try require(page.sessions.count == 2 && Set(page.sessions.map(\.persistentModelID)).count == 2, "both same-UUID runs remain separate history rows")
        for run in duplicateRuns {
            let selected = try RunHistoryStore.session(recordID: run.persistentModelID, context: context)
            try require(selected?.persistentModelID == run.persistentModelID && selected?.notes == run.notes, "history navigation resolves the exact selected physical row")
        }
        let firstRun = duplicateRuns[0], secondRun = duplicateRuns[1]
        let firstDistance = firstRun.distance
        try RunImportStore.apply([.update(recordID: secondRun.persistentModelID, healthWorkoutUUID: "synthetic-new-health", activityType: "walking",
            date: nil, distance: 7, distanceUnit: "km", duration: nil, calories: 50, locations: nil)], context: context)
        try require(firstRun.distance == firstDistance && firstRun.healthWorkoutUUID == nil && secondRun.distance == 7
            && secondRun.healthWorkoutUUID == "synthetic-new-health", "Health import updates only its exact persistent target despite duplicate UUIDs")
        let competingUpdates: [RunImportAction] = [
            .update(recordID: secondRun.persistentModelID, healthWorkoutUUID: "synthetic-competing-a", activityType: "running",
                date: nil, distance: 11, distanceUnit: "km", duration: 2000, calories: 100, locations: nil),
            .update(recordID: secondRun.persistentModelID, healthWorkoutUUID: "synthetic-competing-b", activityType: "running",
                date: nil, distance: 22, distanceUnit: "km", duration: 3000, calories: 200, locations: nil)
        ]
        let unrelatedUpdate = RunImportAction.update(recordID: exactRun.persistentModelID, healthWorkoutUUID: "synthetic-unrelated-health",
            activityType: "running", date: nil, distance: 8, distanceUnit: "km", duration: nil, calories: nil, locations: nil)
        for batch in [competingUpdates, Array(competingUpdates.reversed())] {
            let result = try RunImportStore.apply(batch + [unrelatedUpdate], context: context)
            try require(result.needsReview && result.conflictingRecordCount == 1,
                "conflicting targets report unfinished review instead of silently consuming the Health page")
            try require(secondRun.healthWorkoutUUID == "synthetic-new-health" && secondRun.distance == 7
                && secondRun.duration == 1000 && secondRun.calories == 50,
                "competing Health updates retain the original link and measurements regardless of order")
            try require(exactRun.healthWorkoutUUID == "synthetic-unrelated-health" && exactRun.distance == 8,
                "an unrelated valid update still commits when another target is ambiguous")
        }
        let retried = try RunImportStore.apply([unrelatedUpdate, unrelatedUpdate], context: context)
        try require(!retried.needsReview && exactRun.healthWorkoutUUID == "synthetic-unrelated-health" && exactRun.distance == 8
            && context.fetchCount(FetchDescriptor<RunningSession>()) == initialRunCount,
            "identical update retries are idempotent without creating or redirecting history")
        try RunImportStore.apply([.update(recordID: firstRun.persistentModelID, healthWorkoutUUID: "synthetic-new-health", activityType: "running",
            date: nil, distance: 99, distanceUnit: nil, duration: nil, calories: nil, locations: nil)], context: context)
        try require(firstRun.healthWorkoutUUID == nil && firstRun.distance == firstDistance, "a Health link already owned by another row is not reassigned")
        firstRun.healthWorkoutUUID = "synthetic-ambiguous-health"; secondRun.healthWorkoutUUID = "synthetic-ambiguous-health"; try context.save()
        try require(try RunHistoryStore.session(healthUUID: "synthetic-ambiguous-health", context: context) == nil, "enrichment never picks one of multiple rows sharing a Health UUID")
        try RunImportStore.apply([.unlink(healthWorkoutUUID: "synthetic-ambiguous-health")], context: context)
        try require(firstRun.healthWorkoutUUID == nil && secondRun.healthWorkoutUUID == nil
            && firstRun.notes == "Preserved run 0" && secondRun.notes == "Preserved run 1", "a Health deletion unlinks copies while retaining both app histories")
        let payload = NewRunPayload(date: Date(), distance: 4, distanceUnit: "km", duration: 1200, calories: nil, locations: nil,
            healthWorkoutUUID: "synthetic-insert-health", activityType: "running", avgHeartRate: nil, maxHeartRate: nil,
            minHeartRate: nil, avgCadence: nil, maxCadence: nil, totalAscent: nil, totalDescent: nil, minElevation: nil,
            maxElevation: nil, avgPower: nil, maxPower: nil)
        try RunImportStore.apply([.insert(payload), .insert(payload)], context: context)
        try require(try context.fetchCount(FetchDescriptor<RunningSession>()) == initialRunCount + 1, "repeated import inserts one external workout without altering duplicate records")

        let repository = CoachRepository(context: context)
        try rejectsAmbiguity { _ = try repository.beginExecution(occurrenceID: duplicatedOccurrenceID) }
        try rejectsAmbiguity { try repository.markSession(id: duplicatedOccurrenceID, status: .skipped) }
        try rejectsAmbiguity { try repository.moveSession(id: duplicatedOccurrenceID, to: Date()) }
        try rejectsAmbiguity { _ = try repository.schedulePreview(planID: plan.id, selected: [duplicatedOccurrenceID], dayOffset: 1) }
        try require(try context.fetchCount(FetchDescriptor<CoachSessionExecution>()) == 0, "rejected duplicate-session actions create no execution")

        var document = CoachPlanDocument(programId: "duplicate-revision-check", title: "Reviewed duplicate", goal: "Review",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [.recovery(.init(id: "recovery", title: "Mobility", instructions: "Gentle mobility"))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 1, sessionTemplateId: "recovery")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let future = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let reviewedPlanID = try await repository.importPlan(document: document, startDate: future, activate: false)
        let fresh = ModelContext(container)
        let reviewed = try CoachRepository(context: fresh).plans().first { $0.id == reviewedPlanID }!
        let original = try CoachRepository(context: fresh).occurrences(planID: reviewedPlanID)[0]
        let copy = PlannedSession(id: original.id, plan: reviewed, title: "Second retained copy", activityType: original.activityType,
            scheduledDate: original.scheduledDate, weekIndex: original.weekIndex, dayIndex: original.dayIndex)
        copy.sourceWeekID = original.sourceWeekID; copy.sourceSlotID = original.sourceSlotID
        copy.revisionID = original.revisionID; copy.prescriptionData = original.prescriptionData
        copy.currentCivilDate = original.currentCivilDate
        fresh.insert(copy); try fresh.save()
        document.revision += 1
        let validated = try CoachPlanValidator().validate(document)
        let revisionCount = try fresh.fetchCount(FetchDescriptor<CoachPlanRevision>())
        for restore in [false, true] {
            do {
                try await CoachRepository(context: fresh).applyRevision(validated, planID: reviewedPlanID,
                    selected: restore ? [] : [original.id], addSourceKeys: [], expectedRevisionID: reviewed.currentRevisionID,
                    expectedUpdatedAt: reviewed.updatedAt, restoreRemovedIDs: restore ? [original.id] : [])
                throw CoachRepositoryError.invalidValue("ambiguous reviewed revision should fail")
            } catch CoachRepositoryError.ambiguousRecord { checks += 1 }
        }
        try require(try fresh.fetchCount(FetchDescriptor<CoachPlanRevision>()) == revisionCount
            && CoachRepository(context: fresh).occurrences(planID: reviewedPlanID).count == 2, "rejected revision and restore retain both records and create no revision")

        let workout = WorkoutSession(title: "Synthetic Coach measurements", executionStatus: .completed)
        let execution = CoachSessionExecution(); workout.coachExecutionID = execution.id; execution.workoutSessionID = workout.id
        var snapshot = CoachExecutionSnapshot()
        snapshot.setResults = [.init(id: "press/set", exerciseID: "press", setID: "set", performedExerciseID: "press",
            performedExerciseName: "Press", reps: 10, load: 30, loadUnit: "kg", state: .completed)]
        execution.snapshotData = try JSONEncoder().encode(snapshot)
        let originalSnapshot = execution.snapshotData
        let measured = ExerciseLog(reps: 10, weight: 30, weightUnit: "kg", isCompleted: true)
        measured.actualReps = 10; measured.actualWeight = 30; measured.workoutSession = workout
        let unknown = ExerciseLog(reps: 10, weight: 0, weightUnit: "kg", isCompleted: true)
        unknown.actualReps = 10; unknown.workoutSession = workout
        let zero = ExerciseLog(reps: 10, weight: 0, weightUnit: "kg", isCompleted: true)
        zero.actualReps = 10; zero.actualWeight = 0; zero.workoutSession = workout
        context.insert(workout); context.insert(execution)
        for log in [measured, unknown, zero] { context.insert(log) }
        try context.save()
        for unit in ["lbs", "kg", "lbs", "kg"] {
            for log in [measured, unknown, zero] { WorkoutWeightUnitConversion.convert(log, to: unit) }
            try context.save()
            try require(abs(WorkoutStatistics.volume(for: workout, unit: "kg") - 300) < 0.000001,
                "measurement preference changes preserve physical actual volume")
            try require(measured.weightUnit == unit && abs(UnitConverter.weight(measured.actualWeight!, from: unit, to: "kg") - 30) < 0.000001,
                "raw and actual loads share their converted unit")
            try require(unknown.actualWeight == nil && zero.actualWeight == 0, "unknown and explicit zero loads survive conversion distinctly")
            try require(execution.snapshotData == originalSnapshot, "unit changes preserve the immutable entered Coach snapshot")
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let reopenedContext = ModelContext(reopened)
        let reopenedRuns = try reopenedContext.fetch(FetchDescriptor<RunningSession>()).filter { $0.id == duplicatedRunID }
        try require(reopenedRuns.count == 2 && Set(reopenedRuns.compactMap(\.notes)) == ["Preserved run 0", "Preserved run 1"],
            "reopening preserves both duplicate rows and their distinct contents")
        for run in reopenedRuns {
            let row = try RunHistoryStore.session(recordID: run.persistentModelID, context: reopenedContext)
            try require(row?.notes == run.notes, "each same-UUID run remains independently reviewable after reopening")
        }
        let savedWorkout = try reopenedContext.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == workout.id }!
        try require(abs(WorkoutStatistics.volume(for: savedWorkout, unit: "kg") - 300) < 0.000001, "converted actual statistics remain correct after reopening")
        _ = duplicateOccurrences // Retain both model identities throughout the check.
        return checks
    }
}
#endif
