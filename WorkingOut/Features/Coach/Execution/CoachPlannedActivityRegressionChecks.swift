#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachPlannedActivityRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachPlannedActivityChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: directory.appendingPathComponent("history.store"), cloudKitDatabase: .none)])
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachExecutionCoordinator.ExecutionError.invalid("Planned activity regression: " + message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { count += 1; return }
            throw CoachExecutionCoordinator.ExecutionError.invalid("Planned activity regression accepted: " + message)
        }
        func freshContext() -> ModelContext {
            let context = ModelContext(container); context.autosaveEnabled = false; return context
        }
        let exercise = CoachStrengthExercise(id: "press", exercise: .init(key: "press", name: "Synthetic Planned Press", equipment: ["barbell"]),
            prescriptionBasis: .total, loadBasis: .totalExternal,
            sets: [.init(id: "working", role: .working, target: .reps(min: 8, max: 10))])
        let document = CoachPlanDocument(programId: "activity_tabs", title: "Synthetic Mixed Program", goal: "General fitness",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [
                .strength(.init(id: "lift", title: "Planned Lift", exercises: [exercise])),
                .running(.init(kind: "running", id: "run", title: "Planned Run", main: [.segment(.init(id: "easy", activity: .run, target: .duration(seconds: 60)))])),
                .cardio(.init(kind: "cardio", id: "cycle", title: "Planned Cycle", main: [.segment(.init(id: "ride", activity: .cycle, target: .duration(seconds: 60)))])),
                .recovery(.init(id: "recover", title: "Recovery", instructions: "Gentle mobility")),
                .rest(.init(id: "rest", title: "Rest"))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [
                .init(id: "lift1", dayOffset: 0, sessionTemplateId: "lift"),
                .init(id: "run1", dayOffset: 1, sessionTemplateId: "run"),
                .init(id: "lift2", dayOffset: 2, sessionTemplateId: "lift"),
                .init(id: "cycle1", dayOffset: 3, sessionTemplateId: "cycle"),
                .init(id: "recover1", dayOffset: 4, sessionTemplateId: "recover"),
                .init(id: "rest1", dayOffset: 5, sessionTemplateId: "rest")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let planID = try await CoachRepository(context: container.mainContext).importPlan(document: document,
            startDate: Date(), activate: false, allowCreatingExercises: true)
        var context = freshContext()
        let draftRows = try context.fetch(FetchDescriptor<PlannedSession>())
        let draftWorkouts = CoachPlannedActivities(draftRows, kind: .workouts)
        let draftRuns = CoachPlannedActivities(draftRows, kind: .runs)
        try require(draftWorkouts.sessions.count == 2 && draftRuns.sessions.count == 2,
            "mixed JSON appears in both activity tabs while recovery and rest stay in Coach")
        try require(draftWorkouts.sessions.allSatisfy(CoachPlannedActivities.needsPlanReview)
            && draftRuns.sessions.allSatisfy(CoachPlannedActivities.needsPlanReview), "draft rows lead to program review before execution")
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0
            && context.fetchCount(FetchDescriptor<RunningSession>()) == 0, "import and planned projections create no actual activity history")
        let firstID = draftWorkouts.sessions.first!.id
        let runID = draftRuns.sessions.first { $0.sourceSlotID == "run1" }!.id
        try CoachRepository(context: context).activate(planID: planID)
        context = freshContext()
        var rows = try context.fetch(FetchDescriptor<PlannedSession>())
        var workouts = CoachPlannedActivities(rows, kind: .workouts)
        try require(workouts.sessions.first?.id == firstID && !CoachPlannedActivities.needsPlanReview(workouts.sessions[0]),
            "activation preserves the imported occurrence identity and enables its canonical session route")
        let execution = try CoachExecutionCoordinator.startStrength(workouts.sessions[0], context: context)
        let resumed = try CoachExecutionCoordinator.startStrength(workouts.sessions[0], context: context)
        try require(execution.id == resumed.id && execution.workoutSessionID == resumed.workoutSessionID,
            "Coach and activity-tab Start resume the same execution and workout")
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1
            && context.fetchCount(FetchDescriptor<ExerciseLog>()) == 0, "starting a planned workout creates one identity and no invented actual sets")
        let progressContext = freshContext()
        workouts = CoachPlannedActivities(try progressContext.fetch(FetchDescriptor<PlannedSession>()), kind: .workouts)
        try require(workouts.preview.first?.id == firstID && workouts.preview.first?.status == "in_progress", "the in-progress occurrence is first in the activity preview")
        try CoachRepository(context: context).setPlanStatus(planID: planID, status: .paused)
        let pausedContext = freshContext()
        let pausedWorkouts = CoachPlannedActivities(try pausedContext.fetch(FetchDescriptor<PlannedSession>()), kind: .workouts)
        let pausedSession = pausedWorkouts.sessions.first { $0.id == firstID }!
        try require(pausedWorkouts.preview.first?.id == firstID && !CoachPlannedActivities.needsPlanReview(pausedSession),
            "an existing execution remains first and resumable after its plan is paused")
        let pausedResume = try CoachExecutionCoordinator.startStrength(pausedSession, context: pausedContext)
        try require(pausedResume.id == execution.id && pausedResume.workoutSessionID == execution.workoutSessionID,
            "resuming from a paused plan retains the original execution and workout")
        try CoachRepository(context: context).activate(planID: planID)
        var snapshot = CoachExecutionSnapshot()
        snapshot.setResults = [.init(id: "press/working", exerciseID: "press", setID: "working", performedExerciseID: "press",
            performedExerciseName: "Synthetic Planned Press", equipment: "barbell", reps: 8,
            loadBasis: "totalExternal", repCounting: "total", state: .completed)]
        try CoachExecutionCoordinator.finish(execution, snapshot: snapshot, status: .completed, explanation: nil, context: context)
        context = freshContext()
        rows = try context.fetch(FetchDescriptor<PlannedSession>())
        workouts = CoachPlannedActivities(rows, kind: .workouts)
        let completed = workouts.sessions.first { $0.id == firstID }
        try require(workouts.sessions.count == 2 && completed?.status == "completed" && completed?.completedWorkoutSessionID == execution.workoutSessionID,
            "finishing updates the same planned row while retaining its completed review and history link")
        try require(workouts.preview.first?.sourceSlotID == "lift2" && workouts.outstanding.count == 1,
            "the next scheduled workout moves ahead of the completed occurrence")

        let run = CoachPlannedActivities(rows, kind: .runs).sessions.first { $0.id == runID }!
        let runExecution = try CoachRepository(context: context).beginExecution(occurrenceID: run.id)
        let target = try CoachExecutionCoordinator.runTarget(run, execution: runExecution)
        try require(target.canonicalOccurrenceID == runID && target.executionID == runExecution.id && target.legacySessionID == nil,
            "planned run uses canonical identity rather than a cloned legacy running-plan session")
        var intervals = CoachRunIntervalState(steps: target.structuredSteps!, prescriptionRevisionID: runExecution.prescriptionRevisionID)
        intervals.observe(duration: 60, meters: nil)
        let actualRun = RunningSession(distance: 0, duration: 60)
        actualRun.hasMeasuredDistance = false; context.insert(actualRun)
        try CoachExecutionCoordinator.saveRun(actualRun, target: target, intervalState: intervals, context: context)
        context = freshContext()
        rows = try context.fetch(FetchDescriptor<PlannedSession>())
        let finishedRun = CoachPlannedActivities(rows, kind: .runs).sessions.first { $0.id == runID }
        try require(finishedRun?.status == "completed" && finishedRun?.completedRunningSessionID == actualRun.id,
            "saving a planned run checks off the exact displayed occurrence")
        try require(try context.fetchCount(FetchDescriptor<RunningSession>()) == 1,
            "planned run projection and completion create one actual history record")

        try CoachRepository(context: context).setPlanStatus(planID: planID, status: .paused)
        context = freshContext()
        rows = try context.fetch(FetchDescriptor<PlannedSession>())
        workouts = CoachPlannedActivities(rows, kind: .workouts)
        try require(workouts.outstanding.allSatisfy(CoachPlannedActivities.needsPlanReview)
            && !CoachPlannedActivities.needsPlanReview(workouts.sessions.first { $0.id == firstID }!),
            "paused upcoming sessions lead to program review while completed actuals remain reviewable")
        let authored = rows.first!.plan!
        let auditRow = PlannedSession(plan: authored, title: "Removed audit", activityType: "strength", scheduledDate: Date(), weekIndex: 0, dayIndex: 0, status: "skipped")
        auditRow.prescriptionData = draftWorkouts.sessions[0].prescriptionData; auditRow.revisionID = authored.currentRevisionID
        auditRow.completionProvenance = "removed_by_reviewed_revision"; context.insert(auditRow)
        let legacy = TrainingPlan(title: "Legacy", goal: "Fitness", source: "coach_ai", startDate: Date()); context.insert(legacy)
        let legacyRow = PlannedSession(plan: legacy, title: "Legacy lift", activityType: "strength", scheduledDate: Date(), weekIndex: 0, dayIndex: 0)
        context.insert(legacyRow); try context.save()
        rows = try context.fetch(FetchDescriptor<PlannedSession>())
        try require(CoachPlannedActivities(rows, kind: .workouts).sessions.count == 2,
            "legacy rows without prescriptions and removed revision audit rows never enter canonical execution")
        try rejects("Undo Skip for a removed occurrence") {
            try CoachRepository(context: context).markSession(id: auditRow.id, status: .pending)
        }
        let retainedAudit = try freshContext().fetch(FetchDescriptor<PlannedSession>()).first { $0.id == auditRow.id }!
        try require(retainedAudit.status == "skipped" && retainedAudit.completionProvenance == "removed_by_reviewed_revision",
            "a stale Undo Skip action cannot overwrite reviewed-removal provenance")
        // Even a restored inconsistent pending status must not bypass the removal marker.
        auditRow.status = "pending"; try context.save()
        try CoachRepository(context: context).activate(planID: planID)
        try rejects("Start for a removed occurrence whose pending status was restored") {
            _ = try CoachRepository(context: context).beginExecution(occurrenceID: auditRow.id)
        }
        let checkedContext = freshContext()
        let checkedAudit = try checkedContext.fetch(FetchDescriptor<PlannedSession>()).first { $0.id == auditRow.id }!
        try require(checkedAudit.executionID == nil && checkedAudit.completionProvenance == "removed_by_reviewed_revision"
            && (try checkedContext.fetch(FetchDescriptor<CoachSessionExecution>())).allSatisfy { $0.plannedSessionID != auditRow.id },
            "a stale Start action cannot create an execution for a removed occurrence")
        try CoachRepository(context: context).setPlanStatus(planID: planID, status: .archived)
        context = freshContext()
        rows = try context.fetch(FetchDescriptor<PlannedSession>())
        try require(CoachPlannedActivities(rows, kind: .workouts).sessions.isEmpty && CoachPlannedActivities(rows, kind: .runs).sessions.isEmpty,
            "archived plans leave the activity tabs without deleting their actual history")
        try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1 && context.fetchCount(FetchDescriptor<RunningSession>()) == 1,
            "changing plan visibility never duplicates or removes actual workout and run history")
        return count + (try await CoachImportActivationRegressionChecks.run())
    }
}
#endif
