#if DEBUG
import Foundation
import SwiftData
import CoreLocation

@MainActor
enum CoachExecutionRegressionChecks {
    /// Disposable on-disk history exercises real relationships and backup IDs;
    /// it never opens the user's store, Health data, or cloud configuration.
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachExecutionChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func container(_ name: String) throws -> ModelContainer {
            let schema = PersistenceController.coachSchema
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: directory.appendingPathComponent(name), cloudKitDatabase: .none)])
        }
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachExecutionCoordinator.ExecutionError.invalid("Execution regression: " + message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { count += 1; return }
            throw CoachExecutionCoordinator.ExecutionError.invalid("Execution regression accepted: " + message)
        }
        let source = try container("source.store")
        let context = source.mainContext
        let plan = TrainingPlan(title: "Synthetic program", goal: "General fitness", source: "coach_import", startDate: Date())
        plan.currentRevisionID = UUID()
        let exercise = CoachStrengthExercise(id: "exercise", exercise: .init(key: "press", name: "Synthetic Press", equipment: ["dumbbell"]),
            prescriptionBasis: .perSide, loadBasis: .perImplement,
            sets: [.init(id: "set1", role: .working, target: .reps(min: 6, max: 10)), .init(id: "set2", role: .working, target: .reps(min: 6, max: 10))])
        let template = CoachSessionTemplate.strength(.init(id: "lift", title: "Lift", exercises: [exercise]))
        context.insert(plan)
        let first = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: Date(), weekIndex: 0, dayIndex: 0)
        let second = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: Date().addingTimeInterval(7 * 86_400), weekIndex: 1, dayIndex: 7)
        for occurrence in [first, second] {
            occurrence.prescriptionData = try JSONEncoder().encode(template)
            occurrence.revisionID = plan.currentRevisionID
            occurrence.sourceTemplateID = "lift"
            context.insert(occurrence)
        }
        try context.save()
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0, "scheduling creates no actual workout")
        let execution = try CoachExecutionCoordinator.startStrength(first, context: context)
        let resumed = try CoachExecutionCoordinator.startStrength(first, context: context)
        try require(resumed.id == execution.id && resumed.workoutSessionID == execution.workoutSessionID, "repeated Start resumes the exact execution and workout")
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1, "repeated Start creates one historical identity")
        let workout = try context.fetch(FetchDescriptor<WorkoutSession>()).first!
        try require(!workout.countsAsPerformedActivity && (workout.exerciseLogs ?? []).isEmpty, "unperformed prescriptions do not count as exercise")
        var snapshot = CoachExecutionSnapshot()
        snapshot.setResults = [.init(id: "exercise/set1", exerciseID: "exercise", setID: "set1", performedExerciseID: "press", performedExerciseName: "Synthetic Press",
            equipment: "dumbbell", reps: 8, loadBasis: "perImplement", repCounting: "perSide", effortScale: "rir", effort: 3, state: .completed)]
        snapshot.restTimer = CoachRestTimerState(setResultID: "exercise/set1", seconds: 60)
        var invalid = snapshot
        invalid.setResults[0].durationSeconds = 1e100
        try rejects("duration outside historical integer storage") { try CoachExecutionCoordinator.save(invalid, execution: execution, context: context) }
        invalid = snapshot; invalid.setResults.append(invalid.setResults[0])
        try rejects("duplicate actual set") { try CoachExecutionCoordinator.save(invalid, execution: execution, context: context) }
        invalid = snapshot; invalid.setResults[0].setID = "not_prescribed"
        try rejects("actual set from another prescription") { try CoachExecutionCoordinator.save(invalid, execution: execution, context: context) }
        try require(execution.snapshotData == nil && (workout.exerciseLogs ?? []).isEmpty, "rejected actuals leave snapshot and historical logs unchanged")
        try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context)
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
        try require(logs.count == 1 && logs[0].actualWeight == nil && logs[0].actualReps == 8 && logs[0].isIsolated, "optional actual load and per-side counting survive history projection")
        try CoachExecutionCoordinator.finish(execution, snapshot: snapshot, status: .partial, explanation: nil, context: context)
        try require(workout.executionStatusRaw == "partial" && workout.countsAsPerformedActivity, "finished partial work counts only with performed results")
        let occurrences = try context.fetch(FetchDescriptor<PlannedSession>())
        try require(occurrences.first(where: { $0.id == first.id })?.completedWorkoutSessionID == workout.id && occurrences.first(where: { $0.id == second.id })?.status == "pending", "only the exact repeated occurrence completes")
        snapshot.setResults[0].state = .unlogged
        try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context)
        try require(try context.fetchCount(FetchDescriptor<ExerciseLog>()) == 0 && !workout.countsAsPerformedActivity, "correcting a set removes its derived actual and streak contribution")
        snapshot.setResults[0].state = .completed
        try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context)

        let legacy = WorkoutSession(title: "Legacy history", executionStatus: .legacyRecorded)
        context.insert(legacy)
        let oldLog = ExerciseLog(reps: 5, weight: 20, isCompleted: false)
        oldLog.workoutSession = legacy; context.insert(oldLog)
        try context.save()
        try require(legacy.countsAsPerformedActivity && legacy.executionStatusRaw == "legacy_recorded", "legacy unchecked sets retain historical semantics")

        let export = try await DataBackupService.exportAll(context: context)
        defer { try? FileManager.default.removeItem(at: export) }
        let target = try container("restored.store")
        try await DataBackupService.import(from: export, context: target.mainContext)
        try await DataBackupService.import(from: export, context: target.mainContext)
        let restored = try target.mainContext.fetch(FetchDescriptor<CoachSessionExecution>())
        try require(restored.count == 1 && restored[0].id == execution.id && restored[0].plannedSessionID == first.id, "backup restores execution and occurrence IDs idempotently")
        let restoredSnapshot = try CoachExecutionCoordinator.snapshot(restored[0])
        try require(restoredSnapshot.setResults == snapshot.setResults && restoredSnapshot.restTimer == snapshot.restTimer, "actuals and rest state round trip")
        let restoredLogs = try target.mainContext.fetch(FetchDescriptor<ExerciseLog>()).filter { $0.coachSetResultID != nil }
        try require(restoredLogs.count == 1 && restoredLogs[0].actualWeight == nil && restoredLogs[0].prescriptionBasis == "perSide", "history actual optionals survive backup")
        let reopened = try container("restored.store")
        let reopenedExecutions = try reopened.mainContext.fetch(FetchDescriptor<CoachSessionExecution>())
        try require(reopenedExecutions.first?.id == execution.id, "on-disk store can reopen with preserved execution")
        try CoachDeletionService.detachActual(workoutID: workout.id, context: context)
        context.delete(workout); try context.save()
        let terminal = try CoachExecutionCoordinator.startStrength(first, context: context)
        try require(terminal.id == execution.id && terminal.workoutSessionID == nil && terminal.statusRaw == "partial",
            "reopening terminal history never recreates a deliberately deleted actual workout")
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1, "only retained legacy workout remains after deletion and terminal reopen")

        let runStore = try container("run.store")
        let runContext = runStore.mainContext
        let runPlan = TrainingPlan(title: "Synthetic intervals", goal: "General fitness", source: "coach_import", startDate: Date())
        runPlan.currentRevisionID = UUID(); runContext.insert(runPlan)
        let runPrescription = CoachSessionTemplate.running(.init(kind: "running", id: "run", title: "Intervals", main: [
            .segment(.init(id: "time", activity: .run, target: .duration(seconds: 60))),
            .segment(.init(id: "distance", activity: .walk, target: .distance(.init(value: 100, unit: .m))))]))
        let runOccurrence = PlannedSession(plan: runPlan, title: "Intervals", activityType: "run", scheduledDate: Date(), weekIndex: 0, dayIndex: 1)
        runOccurrence.prescriptionData = try JSONEncoder().encode(runPrescription); runOccurrence.revisionID = runPlan.currentRevisionID
        runContext.insert(runOccurrence); try runContext.save()
        let runExecution = try CoachRepository(context: runContext).beginExecution(occurrenceID: runOccurrence.id)
        let runTarget = try CoachExecutionCoordinator.runTarget(runOccurrence, execution: runExecution)
        let tracker = RunTracker()
        tracker.plannedTarget = runTarget
        tracker.distanceUnit = "km"
        tracker.duration = 70
        tracker.distance = 125
        tracker.authorizationStatus = .authorizedWhenInUse
        try require(tracker.measuredDistance == nil, "permission alone cannot turn an unmeasured distance into an actual")
        tracker.route = [CLLocation(latitude: 52, longitude: 13), CLLocation(latitude: 52.001, longitude: 13)]
        tracker.authorizationStatus = .denied
        try require(tracker.measuredDistance == 125, "recorded route distance survives permission revocation")
        tracker.isRunning = true
        tracker.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 52.002, longitude: 13)])
        try require(tracker.route.count == 2 && tracker.distance == 125, "a queued denied-location callback cannot add new route samples")
        tracker.isRunning = false
        let recordedRun = tracker.stopRun()
        try require(recordedRun?.hasMeasuredDistance == true && recordedRun?.distance == 0.125,
            "saving after permission revocation retains measured-distance provenance and actual distance")
        var intervals = CoachRunIntervalState(steps: runTarget.structuredSteps!, prescriptionRevisionID: runExecution.prescriptionRevisionID)
        intervals.observe(duration: 60, meters: nil)
        let runID = UUID(), runStart = Date().addingTimeInterval(-70)
        let checkpoint = RunRecoverySnapshot(sessionID: runID, startDate: runStart, duration: 70, distanceMeters: 0,
            distanceUnit: "km", activityType: "running", plannedTarget: runTarget, points: [], intervalState: intervals,
            recordedAt: runStart.addingTimeInterval(70), completedPauses: [])
        try require(checkpoint.isValid, "time-based run checkpoint is valid without GPS")
        try CoachExecutionCoordinator.mirrorRunCheckpoint(checkpoint, context: runContext)
        let checkpointCopy = try CoachExecutionCoordinator.backedUpRunCheckpoint(context: runContext)
        try require(checkpointCopy?.sessionID == runID && checkpointCopy?.intervalState == intervals, "active backup checkpoint retains exact run identity and current interval")
        let activeExport = try await DataBackupService.exportAll(context: runContext)
        defer { try? FileManager.default.removeItem(at: activeExport) }
        let restoredRunStore = try container("restored-run.store")
        try await DataBackupService.import(from: activeExport, context: restoredRunStore.mainContext)
        let recovered = try CoachExecutionCoordinator.backedUpRunCheckpoint(context: restoredRunStore.mainContext)
        try require(recovered?.sessionID == runID && recovered?.intervalState?.results.first?.distanceMeters == nil,
            "deliberate active-run backup restores partial interval progress and unknown distance")
        let actualRun = RunningSession(id: runID, distance: 0, duration: 70)
        actualRun.hasMeasuredDistance = false; runContext.insert(actualRun)
        var wrongRevision = intervals; wrongRevision.prescriptionRevisionID = UUID()
        try rejects("run intervals from another revision") { try CoachExecutionCoordinator.saveRun(actualRun, target: runTarget, intervalState: wrongRevision, context: runContext) }
        try require(runExecution.runSessionID == nil && runExecution.statusRaw == "in_progress", "mismatched run revision does not finish or link the occurrence")
        intervals.restorePaused(at: 70)
        intervals.finishEarly(duration: 70, meters: nil)
        try CoachExecutionCoordinator.saveRun(actualRun, target: runTarget, intervalState: intervals, context: runContext)
        try require(runExecution.statusRaw == "partial" && runOccurrence.completedRunningSessionID == runID && !actualRun.hasMeasuredDistance,
            "early finish links the exact run as partial without manufacturing distance")
        try require(try CoachExecutionCoordinator.backedUpRunCheckpoint(context: runContext) == nil, "finished run cannot be offered as an active backup recovery")
        try CoachExecutionCoordinator.mirrorRunCheckpoint(checkpoint, context: runContext)
        try require(try CoachExecutionCoordinator.snapshot(runExecution).runRecoveryData == nil, "late active checkpoint cannot overwrite a terminal run")
        count += try await progressionChecks(container("progression.store"))
        return count
    }

    private static func progressionChecks(_ container: ModelContainer) async throws -> Int {
        let context = container.mainContext
        let repository = CoachRepository(context: context)
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachExecutionCoordinator.ExecutionError.invalid("Progression regression: " + message) }
        }
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.date(byAdding: .day, value: -4, to: Date())!
        let exercise = CoachStrengthExercise(id: "press", exercise: .init(key: "press", name: "Synthetic Progression Press", equipment: ["barbell"]),
            prescriptionBasis: .total, loadBasis: .totalExternal,
            sets: [.init(id: "working", role: .working, target: .reps(min: 8, max: 12), effort: .init(scale: .rir, min: 2, max: 4))])
        let rule = CoachDoubleProgressionRule(id: "rule", title: "Reviewed increase", sessionTemplateId: "lift", exerciseId: "press",
            requiredSuccessfulOccurrences: 2, minimumRIR: 2, increment: .init(value: 2.5, unit: .kg))
        let document = CoachPlanDocument(programId: "progression_regression", title: "Synthetic progression", goal: "General fitness",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [.strength(.init(id: "lift", title: "Lift", exercises: [exercise]))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [
                .init(id: "first", dayOffset: 0, sessionTemplateId: "lift"),
                .init(id: "second", dayOffset: 2, sessionTemplateId: "lift"),
                .init(id: "third", dayOffset: 6, sessionTemplateId: "lift")])],
            weeks: [.init(id: "one", phaseId: "phase", weekPatternId: "pattern"), .init(id: "two", phaseId: "phase", weekPatternId: "pattern")],
            progressionRules: [.doubleProgression(rule)])
        let id = try await repository.importPlan(document: document, startDate: start, activate: true, allowCreatingExercises: true)
        let plan = try repository.plans().first { $0.id == id }!
        let rows = try repository.occurrences(planID: id)
        let performed = rows.filter { $0.sourceWeekID == "one" && $0.sourceSlotID != "third" }
        let actual = CoachSetResult(id: "press/working", exerciseID: "press", setID: "working", performedExerciseID: "press", performedExerciseName: "Synthetic Progression Press",
            equipment: "barbell", reps: 12, load: 30, loadUnit: "kg", loadBasis: "totalExternal", repCounting: "total", effortScale: "rir", effort: 2, state: .completed)
        for row in performed {
            let execution = try CoachExecutionCoordinator.startStrength(row, context: context)
            var snapshot = CoachExecutionSnapshot(); snapshot.setResults = [actual]
            try CoachExecutionCoordinator.finish(execution, snapshot: snapshot, status: .completed, explanation: nil, context: context)
            execution.startedAt = row.scheduledDate.addingTimeInterval(-60); execution.endedAt = row.scheduledDate
            row.completedAt = row.scheduledDate
            let check = CoachRecoveryCheckIn(); check.civilDate = CoachSchedule.civilDate(row.scheduledDate, timeZone: zone)
            check.timeZoneIdentifier = zone.identifier; check.painScore = 0; context.insert(check)
        }
        try context.save()
        let oldFeedback = CoachRecoveryCheckIn()
        oldFeedback.civilDate = CoachSchedule.civilDate(calendar.date(byAdding: .day, value: -60, to: Date())!, timeZone: zone)
        oldFeedback.timeZoneIdentifier = zone.identifier; oldFeedback.painScore = 4; oldFeedback.updatedAt = Date()
        context.insert(oldFeedback)
        let futureFeedback = CoachRecoveryCheckIn()
        futureFeedback.civilDate = CoachSchedule.civilDate(calendar.date(byAdding: .day, value: 10, to: Date())!, timeZone: zone)
        futureFeedback.timeZoneIdentifier = zone.identifier; futureFeedback.soreness = 8; context.insert(futureFeedback)
        try context.save()
        let generated = try CoachProgressionEvaluator.generate(plan: plan, context: context)
        let suggestion = generated.suggestions.first { $0.statusRaw == "pending" }
        try require(suggestion != nil, "two completed comparable actual sessions with recorded feedback create a reviewable suggestion")
        try require(suggestion != nil && generated.holds.isEmpty, "recent edits to historical feedback and future-dated feedback do not create a current recovery hold")
        guard let suggestion else { return count }
        let skipped = rows.first { $0.sourceWeekID == "one" && $0.sourceSlotID == "third" }!
        skipped.scheduledDate = Date(); skipped.currentCivilDate = CoachSchedule.civilDate(Date(), timeZone: zone)
        try context.save()
        try repository.markSession(id: skipped.id, status: .skipped)
        let future = rows.first { $0.sourceWeekID == "two" && $0.sourceSlotID == "first" }!
        let originalFuturePrescription = future.prescriptionData
        do {
            try CoachProgressionEvaluator.accept(suggestionID: suggestion.id, selectedIDs: [future.id], increment: 2.5, confirmedPerImplement: false, context: context)
            throw CoachExecutionCoordinator.ExecutionError.invalid("Progression regression accepted evidence interrupted by an unstarted skip")
        } catch let error as CoachExecutionCoordinator.ExecutionError {
            if error.localizedDescription.contains("regression accepted") { throw error }; count += 1
        }
        let afterSkip = try CoachProgressionEvaluator.generate(plan: plan, context: context)
        try require(afterSkip.suggestions.allSatisfy { $0.statusRaw != "pending" }, "a newly skipped occurrence makes an older pending proposal stale")
        try require(future.prescriptionData == originalFuturePrescription, "rejected progression leaves future targets unchanged")
        try repository.markSession(id: skipped.id, status: .pending)
        let nextExecution = try CoachExecutionCoordinator.startStrength(skipped, context: context)
        var nextSnapshot = CoachExecutionSnapshot(); nextSnapshot.setResults = [actual]
        let todayCheck = CoachRecoveryCheckIn(); todayCheck.civilDate = CoachSchedule.civilDate(Date(), timeZone: zone)
        todayCheck.timeZoneIdentifier = zone.identifier; todayCheck.painScore = 0; context.insert(todayCheck); try context.save()
        try CoachExecutionCoordinator.finish(nextExecution, snapshot: nextSnapshot, status: .completed, explanation: nil, context: context)
        let refreshed = try CoachProgressionEvaluator.generate(plan: plan, context: context)
        let refreshedSuggestion = refreshed.suggestions.first { $0.statusRaw == "pending" }
        try require(refreshedSuggestion != nil && refreshedSuggestion?.id != suggestion.id, "new completed evidence supports a new reviewed suggestion")
        guard let refreshedSuggestion else { return count }
        let futureID = future.id
        try CoachProgressionEvaluator.accept(suggestionID: refreshedSuggestion.id, selectedIDs: [futureID], increment: 1.25, confirmedPerImplement: false, context: context)
        let verification = ModelContext(container)
        let changed = try verification.fetch(FetchDescriptor<PlannedSession>()).first { $0.id == futureID }!
        let changedPrescription = try JSONDecoder().decode(CoachSessionTemplate.self, from: changed.prescriptionData!)
        if case let .strength(value) = changedPrescription {
            try require(value.exercises[0].sets[0].load?.value == 31.25, "accepted equipment increment changes only the selected future load")
        }
        let storedSuggestion = try verification.fetch(FetchDescriptor<CoachProgressionSuggestion>()).first { $0.id == refreshedSuggestion.id }!
        try require(storedSuggestion.statusRaw == "edited" && changed.revisionID != performed.first?.revisionID, "edited acceptance persists its decision and a new prescription revision")
        let oldPrescription = performed.first?.prescriptionData
        try require(try verification.fetch(FetchDescriptor<PlannedSession>()).first { $0.id == performed.first?.id }?.prescriptionData == oldPrescription,
            "progression preserves completed historical prescriptions")
        return count
    }
}
#endif
