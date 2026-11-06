#if DEBUG
import Foundation
import SwiftData

/// The same disposable-data checks run on the host and in isolated device QA.
enum WorkoutStatisticsRegressionChecks {
    enum Failure: Error { case failed(String) }

    @MainActor static func run() throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WorkoutStatistics-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([ExerciseDefinition.self, WorkoutSession.self, ExerciseLog.self,
            RunningSession.self, RunningPlan.self, RunningPlanSession.self, TrainingPlan.self,
            PlannedSession.self, WeightEntry.self, AIConversation.self, WorkoutTemplate.self,
            TemplateExercise.self, HealthWorkoutInboxItem.self, CardioWorkoutInboxItem.self] + CoachPersistence.modelTypes)
        let configuration = ModelConfiguration("StatisticsFixture", schema: schema,
            url: directory.appendingPathComponent("fixture.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var count = 0
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure.failed(message) }
            count += 1
        }
        func session(_ title: String, status: CoachExecutionStatus = .inProgress) -> WorkoutSession {
            let value = WorkoutSession(date: Date(timeIntervalSince1970: 1_800_000_000), notes: "Retain", title: title,
                                       executionStatus: status)
            context.insert(value)
            return value
        }
        func log(_ session: WorkoutSession, reps: Int = 8, weight: Double = 25,
                 completed: Bool = false, type: String = "strength", duration: Int? = nil) -> ExerciseLog {
            let value = ExerciseLog(reps: reps, weight: weight, weightUnit: "kg", setNumber: 1,
                                    exerciseName: "Fixture", exerciseType: type, durationSeconds: duration,
                                    isCompleted: completed)
            value.workoutSession = session
            context.insert(value)
            return value
        }
        let manual = session("Yesterday's manually entered workout")
        let first = log(manual), second = log(manual, reps: 5, weight: 10)
        try context.save()
        let originalID = manual.id, originalDate = manual.date, originalStatus = manual.executionStatusRaw
        let originalNotes = manual.notes, originalProvenance = manual.completionProvenance
        try check(!WorkoutStatistics.isPlanned(manual), "unmarked manual history remains manual")
        try check(WorkoutStatistics.hasActivity(manual), "unchecked manually entered values are activity")
        try check(WorkoutStatistics.confirmedLogs(in: manual).count == 2,
                  "manual values do not require set circles or receipt backfill")
        try check(WorkoutStatistics.volume(for: manual, unit: "kg") == 250,
                  "manual volume includes every valid entered set")
        try check(!first.isCompleted && !second.isCompleted && first.actualReps == nil && first.actualWeight == nil,
                  "reading statistics does not backfill completion flags or actuals")
        try check(manual.id == originalID && manual.date == originalDate && manual.notes == originalNotes
                    && manual.executionStatusRaw == originalStatus && manual.completionProvenance == originalProvenance
                    && manual.endedAt == nil, "statistics preserve all workout state")
        first.actualReps = 1; first.actualWeight = 1
        try check(WorkoutStatistics.volume(for: manual, unit: "kg") == 250,
                  "stale optional actual fields do not hide newer manual editor values")
        first.reps = 10; first.weight = 30
        try check(WorkoutStatistics.volume(for: manual, unit: "kg") == 350,
                  "manual edits immediately update volume without a completion toggle")
        try context.save()
        let reopenedContainer = try ModelContainer(for: schema, configurations: [configuration])
        let reopened = ModelContext(reopenedContainer)
        let storedFirst = try reopened.fetch(FetchDescriptor<ExerciseLog>()).first { $0.id == first.id }!
        let storedSession = try reopened.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == manual.id }!
        try check(WorkoutStatistics.volume(for: storedSession, unit: "kg") == 350 && !storedFirst.isCompleted,
                  "persisted unchecked manual history is included after reopening")
        try check(storedFirst.actualReps == 1 && storedFirst.actualWeight == 1
                    && storedSession.executionStatusRaw == originalStatus,
                  "projections leave optional actual fields and status untouched")
        let inverseMissing = WorkoutSession(title: "Legacy parent membership")
        let parentOwnedLog = ExerciseLog(reps: 8, weight: 25, weightUnit: "kg")
        inverseMissing.exerciseLogs = [parentOwnedLog]
        try check(WorkoutStatistics.acceptsParentMembership(ownerID: nil, sessionID: inverseMissing.id),
                  "missing inverse accepts explicit parent membership")
        try check(WorkoutStatistics.acceptsParentMembership(ownerID: inverseMissing.id, sessionID: inverseMissing.id),
                  "matching inverse accepts parent membership")
        try check(!WorkoutStatistics.acceptsParentMembership(ownerID: UUID(), sessionID: inverseMissing.id),
                  "conflicting explicit inverse rejects parent membership")
        try check(WorkoutStatistics.volume(for: inverseMissing, unit: "kg") == 200
                    && WorkoutStatistics.confirmedLogs(in: inverseMissing).map(\.id) == [parentOwnedLog.id],
                  "real parent membership preserves valid set volume")
        try check(parentOwnedLog.workoutSession?.id == inverseMissing.id,
                  "projection preserves the SwiftData reconstructed inverse")

        let empty = session("Empty")
        _ = log(empty, reps: 0, weight: 100)
        try check(!WorkoutStatistics.hasActivity(empty) && WorkoutStatistics.confirmedLogs(in: empty).isEmpty,
                  "zero default reps and suggested weight do not invent activity")
        let legacy = session("Historical", status: .legacyRecorded)
        _ = log(legacy)
        try check(WorkoutStatistics.hasActivity(legacy) && WorkoutStatistics.volume(for: legacy, unit: "kg") == 200,
                  "legacy manual history keeps its numeric meaning")
        let emptyLegacy = session("Legacy empty", status: .legacyRecorded)
        try check(WorkoutStatistics.hasActivity(emptyLegacy), "legacy manual activity status remains compatible")

        let planned = session("Explicit plan")
        planned.completionProvenance = "planned_workout"
        let target = log(planned, reps: 100, weight: 100)
        let performed = log(planned, completed: true)
        try check(WorkoutStatistics.isPlanned(planned), "explicit plan marker enables checked-set semantics")
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 200,
                  "only checked planned sets contribute volume")
        try check(WorkoutStatistics.confirmedLogs(in: planned).map(\.id) == [performed.id],
                  "unchecked planned targets are excluded independently")
        performed.isCompleted = false
        try check(!WorkoutStatistics.hasActivity(planned), "a wholly unchecked plan is not performed activity")
        target.actualReps = 100; target.actualWeight = 100
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 0,
                  "unchecked copied actual fields cannot promote a planned target")
        performed.isCompleted = true; performed.actualReps = 6; performed.actualWeight = 20
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 120,
                  "checked planned logs prefer their recorded actual values")
        performed.actualReps = 0; performed.actualWeight = 0
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 0 && !WorkoutStatistics.hasActivity(planned),
                  "explicit zero actuals never fall back to nonzero planned targets")
        performed.actualReps = 6; performed.actualWeight = .infinity
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 0 && !WorkoutStatistics.hasActivity(planned),
                  "invalid actuals never become prescribed planned values")
        performed.actualWeight = nil
        try check(WorkoutStatistics.volume(for: planned, unit: "kg") == 0 && !WorkoutStatistics.hasActivity(planned),
                  "incomplete actuals never invent a performed load")
        let repeated = session("Repeat workout targets")
        repeated.completionProvenance = "planned_workout"
        _ = log(repeated, reps: first.reps, weight: first.weight)
        try check(!WorkoutStatistics.hasActivity(repeated), "repeated targets marked as planned wait for checked sets")
        for keyPath in [\WorkoutSession.sourceTemplateID, \WorkoutSession.coachExecutionID, \WorkoutSession.plannedSessionID] {
            let scheduled = session("Existing planned source")
            scheduled[keyPath: keyPath] = UUID()
            let scheduledLog = log(scheduled)
            try check(WorkoutStatistics.isPlanned(scheduled) && !WorkoutStatistics.hasActivity(scheduled),
                      "existing template, Coach and scheduled IDs all enforce planned semantics")
            scheduledLog.isCompleted = true
            try check(WorkoutStatistics.hasActivity(scheduled) && WorkoutStatistics.volume(for: scheduled, unit: "kg") == 200,
                      "checked existing planned sources retain activity")
        }
        let plannedLegacy = session("Legacy template", status: .legacyRecorded)
        plannedLegacy.sourceTemplateID = UUID(); _ = log(plannedLegacy)
        try check(!WorkoutStatistics.hasActivity(plannedLegacy), "an unchecked legacy plan does not bypass planned semantics")

        let bodyweight = session("Bodyweight")
        _ = log(bodyweight, reps: 12, weight: 0)
        try check(WorkoutStatistics.hasActivity(bodyweight) && WorkoutStatistics.volume(for: bodyweight, unit: "kg") == 0,
                  "positive bodyweight reps count as activity with honest zero external volume")
        let cardio = session("Manual cardio")
        _ = log(cardio, reps: 1, weight: 0, type: "cardio", duration: 600)
        try check(WorkoutStatistics.hasActivity(cardio) && WorkoutStatistics.volume(for: cardio, unit: "kg") == 0,
                  "positive manual cardio duration adds activity but no lifting volume")
        let emptyCardio = session("Untouched cardio")
        _ = log(emptyCardio, type: "cardio", duration: 0)
        try check(!WorkoutStatistics.hasActivity(emptyCardio), "cardio defaults do not count strength placeholder fields")
        let timed = session("Timed strength")
        _ = log(timed, reps: 0, weight: 0, duration: 60)
        try check(WorkoutStatistics.hasActivity(timed) && WorkoutStatistics.volume(for: timed, unit: "kg") == 0,
                  "timed strength remains activity without invented reps")
        for badWeight in [-1.0, Double.nan, Double.infinity] {
            let invalid = session("Invalid weight")
            _ = log(invalid, weight: badWeight)
            try check(!WorkoutStatistics.hasActivity(invalid) && WorkoutStatistics.volume(for: invalid, unit: "kg") == 0,
                      "invalid weight never creates activity or nonfinite volume")
        }
        let negative = session("Negative reps")
        _ = log(negative, reps: -2)
        try check(!WorkoutStatistics.hasActivity(negative), "negative reps are not activity")
        let invalidUnit = session("Unknown unit")
        let invalidUnitLog = log(invalidUnit); invalidUnitLog.weightUnit = "unknown"
        try check(!WorkoutStatistics.hasActivity(invalidUnit), "unknown weight units are not silently relabeled")
        let huge = session("Bounded arithmetic")
        let hugeLog = log(huge, reps: Int.max, weight: 1); hugeLog.isIsolated = true
        try check(WorkoutStatistics.volume(for: huge, unit: "kg").isFinite,
                  "unilateral Int.max reps cannot overflow integer arithmetic")
        hugeLog.weight = Double.greatestFiniteMagnitude
        try check(WorkoutStatistics.volume(for: huge, unit: "kg") == 0
                    && WorkoutStatistics.volume(for: huge, unit: "lbs") == 0,
                  "overflowing multiplication or conversion never produces infinite volume")
        let accumulation = session("Overflowing total")
        _ = log(accumulation, reps: 1, weight: Double.greatestFiniteMagnitude)
        _ = log(accumulation, reps: 1, weight: Double.greatestFiniteMagnitude)
        try check(WorkoutStatistics.volume(for: accumulation, unit: "kg").isFinite,
                  "multiple finite contributions cannot overflow the session total")
        try check(WorkoutStatistics.sumFiniteVolumes([Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude]).isFinite,
                  "day aggregation cannot overflow from individually finite session volumes")
        try check(WorkoutStatistics.sumFiniteVolumes([10, -1, .nan, .infinity, -.infinity, 20]) == 30,
                  "day aggregation rejects negative and nonfinite inputs without losing valid volumes")
        try check(WorkoutStatistics.sumFiniteVolumes([]) == 0,
                  "empty day aggregation produces zero")
        try check(WorkoutStatistics.volume(for: manual, unit: "unknown") == 0,
                  "unknown target units do not mislabel volume")
        let category = ExerciseDefinition(name: "Fixture", muscleGroup: "Chest")
        context.insert(category); first.exerciseDefinition = category
        try check(WorkoutStatistics.volume(for: manual, unit: "kg", category: "Chest") == 300
                    && WorkoutStatistics.volume(for: manual, unit: "kg", category: "Back") == 0,
                  "category filtering respects eligible set values")
        try check(WorkoutStatistics.volume(for: manual, unit: "kg", logIDs: [first.id]) == 300
                    && WorkoutStatistics.volume(for: manual, unit: "kg", logIDs: [second.id]) == 50,
                  "per-exercise subsets use the same validated set measurements")
        try check(WorkoutStatistics.volume(for: manual, unit: "kg", logIDs: []) == 0
                    && WorkoutStatistics.volume(for: manual, unit: "kg", logIDs: [UUID()]) == 0,
                  "empty or unknown subsets never fall back to total volume")
        try check(WorkoutStatistics.volume(for: planned, unit: "kg", logIDs: [target.id]) == 0,
                  "subset volume cannot bypass unchecked planned-set exclusion")
        try check(abs(WorkoutStatistics.volume(for: manual, unit: "lbs") - UnitConverter.weight(350, from: "kg", to: "lbs")) < 0.0001,
                  "volume conversion uses the production converter")
        let canceled = session("Canceled", status: .canceled)
        _ = log(canceled, completed: true); canceled.healthDuration = 600
        try check(!WorkoutStatistics.hasActivity(canceled) && WorkoutStatistics.volume(for: canceled, unit: "kg") == 0,
                  "canceled workouts cannot regain activity from checked or Health fields")
        let health = session("Health duration", status: .completed)
        health.healthDuration = 600
        try check(WorkoutStatistics.hasActivity(health), "finite positive Health duration remains activity evidence")
        health.healthDuration = .infinity
        try check(!WorkoutStatistics.hasActivity(health), "nonfinite Health duration is excluded")
        health.executionStatusRaw = "unknown"; health.healthDuration = 600
        try check(!WorkoutStatistics.hasActivity(health), "unknown status is not silently promoted")
        return count
    }
}
#endif
