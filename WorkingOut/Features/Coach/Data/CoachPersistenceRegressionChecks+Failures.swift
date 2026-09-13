#if DEBUG
import Foundation
import SwiftData

extension CoachPersistenceRegressionChecks {
    @MainActor static func runFailureCases(root: URL) async throws -> Int {
        let schema = PersistenceController.coachSchema
        let url = root.appendingPathComponent("failure-cases.store")
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: url, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let repository = CoachRepository(context: context)
        var checks = 0
        func require(_ condition: Bool, _ reason: String) throws {
            checks += 1
            guard condition else { throw CoachRepositoryError.invalidValue("persistence failure regression: " + reason) }
        }
        func reject(_ reason: String, _ operation: () throws -> Void) throws {
            do { try operation() }
            catch { checks += 1; return }
            throw CoachRepositoryError.invalidValue("failure regression accepted " + reason)
        }
        func fresh() -> ModelContext { let value = ModelContext(container); value.autosaveEnabled = false; return value }
        let day = Calendar.current.startOfDay(for: Date())
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let thirdDay = Calendar.current.date(byAdding: .day, value: 2, to: day)!
        let sourceID = try repository.saveNutrition(date: day, calories: 100, protein: 25, carbs: nil, fat: nil)
        let destinationID = try repository.saveNutrition(date: nextDay, calories: 200, protein: nil, carbs: 50, fat: nil)
        let preview = try repository.nutritionMovePreview(id: sourceID, to: nextDay)
        let reviewedSourceDate = preview.source.updatedAt, reviewedDestinationDate = preview.destination!.updatedAt
        try repository.transaction { isolated in
            let target = try isolated.fetch(FetchDescriptor<CoachNutritionLog>()).first { $0.id == destinationID }!
            target.calories = 250; target.updatedAt = reviewedDestinationDate.addingTimeInterval(1)
        }
        try reject("stale destination merge") {
            _ = try repository.moveNutrition(id: sourceID, to: nextDay, mergedCalories: 300, mergedProtein: 25, mergedCarbs: 50, mergedFat: nil, mergedNotes: nil, isFinal: true,
                expectedDestinationID: destinationID, expectedSourceUpdatedAt: reviewedSourceDate, expectedDestinationUpdatedAt: reviewedDestinationDate)
        }
        let preserved = try fresh().fetch(FetchDescriptor<CoachNutritionLog>())
        try require(preserved.count == 2 && preserved.first { $0.id == sourceID }?.calories == 100 && preserved.first { $0.id == destinationID }?.calories == 250,
            "stale merge preserves both saved records")
        try repository.deleteNutrition(id: sourceID)
        try reject("stale nutrition identity") { _ = try repository.saveNutrition(date: day, calories: 150, protein: nil, carbs: nil, fat: nil, id: sourceID) }
        try reject("stale weight identity") { _ = try repository.saveWeight(date: day, value: 80, unit: "kg", id: UUID()) }
        try reject("stale waist identity") { _ = try repository.saveWaist(date: day, value: 90, unit: "cm", id: UUID()) }
        try require(try fresh().fetchCount(FetchDescriptor<WeightEntry>()) == 0 && fresh().fetchCount(FetchDescriptor<CoachWaistMeasurement>()) == 0,
            "stale observation editors do not recreate deleted records")

        let coverage = Data("synthetic source-day sample IDs".utf8)
        let recoveryID = try repository.saveRecovery(date: day, manualSleepHours: 6, soreness: 2, energy: 3, painScore: 0, notes: "Move these manual fields")
        try repository.saveHealthSleep(date: day, hours: 7, source: "Source day", endDate: day, coverageData: coverage)
        let movedID = try repository.moveRecovery(id: recoveryID, to: nextDay, manualSleepHours: 6, soreness: 2, energy: 3, painScore: 0, painLocation: nil, notes: "Reviewed move")
        var recoveryRows = try fresh().fetch(FetchDescriptor<CoachRecoveryCheckIn>())
        let sourceSleep = recoveryRows.first { $0.id == recoveryID }
        let movedCheckIn = recoveryRows.first { $0.id == movedID }
        try require(movedID != recoveryID && sourceSleep?.civilDate == CoachRepository.civilDate(day) && sourceSleep?.healthSleepHours == 7 && sourceSleep?.healthSampleCoverageData == coverage && sourceSleep?.manualSleepHours == nil && sourceSleep?.notes == nil,
            "date correction retains original Health sleep on its measured day")
        try require(movedCheckIn?.civilDate == CoachRepository.civilDate(nextDay) && movedCheckIn?.manualSleepHours == 6 && movedCheckIn?.healthSleepHours == nil && movedCheckIn?.sleepSourceRaw == "manual",
            "date correction does not relabel original Health coverage as destination sleep")
        try repository.saveHealthSleep(date: nextDay, hours: 8, source: "Destination day", endDate: nextDay, coverageData: Data("destination samples".utf8))
        let collisionID = try repository.saveRecovery(date: thirdDay, manualSleepHours: 5, soreness: nil, energy: nil, painScore: nil)
        let collisionPreview = try repository.recoveryMovePreview(id: collisionID, to: nextDay)
        let mergedID = try repository.moveRecovery(id: collisionID, to: nextDay, manualSleepHours: nil, soreness: 1, energy: 4, painScore: nil, painLocation: nil, notes: "Reviewed collision",
            expectedDestinationID: movedID, expectedSourceUpdatedAt: collisionPreview.source.updatedAt, expectedDestinationUpdatedAt: collisionPreview.destination?.updatedAt)
        recoveryRows = try fresh().fetch(FetchDescriptor<CoachRecoveryCheckIn>())
        try require(mergedID == movedID && !recoveryRows.contains { $0.id == collisionID } && recoveryRows.first { $0.id == movedID }?.healthSleepHours == 8 && recoveryRows.first { $0.id == movedID }?.sleepSourceRaw == "health",
            "reviewed collision preserves destination-day Health sleep")

        let baseline = try DataBackupService.capture(context: fresh())
        let baselineDigest = try CoachLocalOwnership.snapshotDigest(fresh())
        func rejectRestore(_ archive: BackupFile, reason: String) throws {
            let isolated = fresh()
            try reject(reason) { try DataBackupService.restore(archive, context: isolated) }
            try require(!isolated.hasChanges && (try CoachLocalOwnership.snapshotDigest(fresh())) == baselineDigest,
                reason + " leaves stored history and restore context unchanged")
        }
        var collision = baseline
        collision.coach?.nutrition[0].id = UUID()
        try rejectRestore(collision, reason: "backup nutrition-day collision")
        collision = baseline; collision.coach?.recovery[0].id = UUID()
        try rejectRestore(collision, reason: "backup recovery-day collision")
        var duplicateDay = baseline
        var duplicate = duplicateDay.coach!.nutrition[0]; duplicate.id = UUID()
        duplicateDay.coach?.nutrition.append(duplicate)
        try rejectRestore(duplicateDay, reason: "duplicate daily rows inside backup")
        let invalidTarget = CoachNutritionTargetPeriod(); invalidTarget.startCivilDate = CoachRepository.civilDate(day); invalidTarget.calories = 1e300
        var invalid = baseline; invalid.coach?.targets = [.init(invalidTarget)]
        try rejectRestore(invalid, reason: "overflow-sized restored target")
        invalid.coach?.targets[0].calories = 2000.5
        try rejectRestore(invalid, reason: "fractional restored target calories")
        let invalidPhoto = CoachProgressPhoto(); invalidPhoto.assetKey = "\(UUID().uuidString).jpg"
        invalidPhoto.pixelWidth = 1; invalidPhoto.pixelHeight = 1; invalidPhoto.byteCount = 1; invalidPhoto.digest = String(repeating: "a", count: 64)
        invalid = baseline; invalid.coach?.photos = [.init(invalidPhoto)]
        try rejectRestore(invalid, reason: "photo metadata with mismatched asset identity")
        try DataBackupService.restore(baseline, context: fresh())
        try require(try CoachLocalOwnership.snapshotDigest(fresh()) == baselineDigest, "valid repeated restore remains idempotent after preflight guards")

        let firstWorkout = WorkoutSession(date: day, title: "Same-day source", executionStatus: .legacyRecorded)
        let secondWorkout = WorkoutSession(date: day, title: "Same-day source", executionStatus: .legacyRecorded)
        let plan = TrainingPlan(title: "Deletion fixture", goal: "General fitness", source: "manual", startDate: day)
        let firstRow = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: day, weekIndex: 0, dayIndex: 1, status: "completed", completedWorkoutSessionID: firstWorkout.id)
        let secondRow = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: day, weekIndex: 0, dayIndex: 1, status: "completed", completedWorkoutSessionID: secondWorkout.id)
        let execution = CoachSessionExecution(); execution.plannedSessionID = firstRow.id; execution.workoutSessionID = firstWorkout.id; execution.statusRaw = "completed"
        execution.snapshotData = try JSONEncoder().encode(CoachExecutionSnapshot()); firstRow.executionID = execution.id
        let suggestion = CoachProgressionSuggestion(); suggestion.evidenceIDsData = try JSONEncoder().encode([execution.id])
        for value in [firstWorkout, secondWorkout] { context.insert(value) }
        context.insert(plan); context.insert(firstRow); context.insert(secondRow); context.insert(execution); context.insert(suggestion); try context.save()
        try repository.transaction { isolated in
            try CoachDeletionService.detachActual(workoutID: firstWorkout.id, context: isolated)
            if let actual = try isolated.fetch(FetchDescriptor<WorkoutSession>()).first(where: { $0.id == firstWorkout.id }) { isolated.delete(actual) }
        }
        let deletedRows = try fresh().fetch(FetchDescriptor<PlannedSession>())
        let deletedExecution = try fresh().fetch(FetchDescriptor<CoachSessionExecution>()).first { $0.id == execution.id }
        try require(deletedRows.first { $0.id == firstRow.id }?.completedWorkoutSessionID == nil && deletedRows.first { $0.id == secondRow.id }?.completedWorkoutSessionID == secondWorkout.id,
            "individual deletion updates the exact occurrence without rematching a same-day workout")
        try require(deletedExecution?.snapshotData == nil && deletedExecution?.provenance == "activity_deleted" && (try fresh().fetch(FetchDescriptor<CoachProgressionSuggestion>())).first { $0.id == suggestion.id }?.statusRaw == "stale",
            "deleted evidence clears its actual snapshot and invalidates pending progression")
        let activeBaseline = try CoachLocalOwnership.snapshotDigest(fresh())
        var conflictingActive = try DataBackupService.capture(context: fresh())
        let incomingActive = TrainingPlan(title: "Other active program", goal: "General fitness", source: "manual", startDate: day)
        conflictingActive.coach?.trainingPlans.append(.init(incomingActive))
        let activeRestore = fresh()
        try reject("second active plan restore") { try DataBackupService.restore(conflictingActive, context: activeRestore) }
        try require(!activeRestore.hasChanges && (try CoachLocalOwnership.snapshotDigest(fresh())) == activeBaseline,
            "restoring another active program requires explicit lifecycle review without changing Today")
        return checks
    }
}
#endif
