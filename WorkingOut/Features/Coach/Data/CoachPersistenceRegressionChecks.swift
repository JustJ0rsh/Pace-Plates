#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachPersistenceRegressionChecks {
    /// Disposable file stores only. This fixture never reads the selected store,
    /// CloudKit, HealthKit, Photos, or the user's ownership marker.
    static func run() async throws -> Int {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoachPersistenceChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachRepositoryError.invalidValue("persistence regression: " + message) }
        }
        func store(_ folder: String, local: Bool) throws -> (URL, ModelContainer) {
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(directory)
            let url = directory.appendingPathComponent("default.store")
            let schema = local ? PersistenceController.coachSchema : Schema(PersistenceController.legacyModelTypes)
            return (url, try ModelContainer(for: schema, configurations: [ModelConfiguration(local ? CoachPersistence.configurationName : "LegacyFixture", schema: schema, url: url, cloudKitDatabase: .none)]))
        }
        let (sourceURL, source) = try store("legacy", local: false)
        let context = source.mainContext
        let definition = ExerciseDefinition(name: "Synthetic press", muscleGroup: "Chest", isUserDefined: true)
        let workout = WorkoutSession(date: Date(timeIntervalSince1970: 1_750_000_000), notes: "Historical notes", title: "Legacy workout", executionStatus: .legacyRecorded)
        let log = ExerciseLog(reps: 7, weight: 22.5, weightUnit: "kg", setNumber: 2, exerciseName: definition.name, notes: "Kept", isCompleted: false)
        log.exerciseDefinition = definition; log.workoutSession = workout
        let route = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 41 &+ 123) })
        let run = RunningSession(date: Date(timeIntervalSince1970: 1_750_000_123), distance: 3.25, distanceUnit: "mi", duration: 1815, notes: "Route preservation", locations: route)
        let weight = WeightEntry(date: Date(timeIntervalSince1970: 1_750_000_456), weight: 77.25, weightUnit: "kg")
        let plan = TrainingPlan(title: "Historical plan", goal: "Preserve", source: "manual", startDate: Date(timeIntervalSince1970: 1_750_000_000))
        let occurrence = PlannedSession(plan: plan, title: "Historical lift", activityType: "strength", scheduledDate: workout.date, weekIndex: 2, dayIndex: 4, status: "completed", completedWorkoutSessionID: workout.id, completedAt: workout.date)
        context.insert(definition); context.insert(workout); context.insert(log); context.insert(run); context.insert(weight); context.insert(plan); context.insert(occurrence)
        try context.save()
        let before = try CoachLocalOwnership.identityInventory(context)
        let beforeValues = try CoachLocalOwnership.snapshotDigest(context)
        let destinationDirectory = root.appendingPathComponent("local", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(destinationDirectory)
        let destination = destinationDirectory.appendingPathComponent("default.store")
        try require(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"), "source fixture includes WAL state")
        try CoachLocalOwnership.copyStore(from: sourceURL, to: destination)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: sourceURL, to: destination)
        let schema = PersistenceController.coachSchema
        let migrated = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: destination, cloudKitDatabase: .none)])
        try require(try CoachLocalOwnership.identityInventory(migrated.mainContext) == before, "migration preserves every existing model ID")
        try require(try CoachLocalOwnership.snapshotDigest(migrated.mainContext) == beforeValues, "migration preserves scalar fields, units, relationships and dates")
        try require(try migrated.mainContext.fetch(FetchDescriptor<RunningSession>()).first?.locations == route, "external route bytes preserved")
        try require(try migrated.mainContext.fetch(FetchDescriptor<ExerciseLog>()).first?.isCompleted == false, "legacy false set flags remain false")
        try require(try migrated.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.sourceHealthSampleID == nil, "legacy weight provenance stays unknown")
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: destination, cloudKitDatabase: .none)])
        try require(try reopened.mainContext.fetch(FetchDescriptor<RunningSession>()).first?.locations == route, "external route survives reopening")
        try require(try CoachLocalOwnership.snapshotDigest(context) == beforeValues, "read-only migration leaves original history unchanged")
        // A copied database remains unselected and can be retried after interruption.
        let interruptedDirectory = root.appendingPathComponent("interrupted", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(interruptedDirectory)
        try CoachLocalOwnership.copyStore(from: sourceURL, to: interruptedDirectory.appendingPathComponent("default.store"))
        try require(try CoachLocalOwnership.identityInventory(context) == before, "unselected partial copy does not affect original")

        let repository = CoachRepository(context: migrated.mainContext)
        let day = Date()
        _ = try repository.saveNutrition(date: day, calories: 0, protein: nil, carbs: 45, fat: nil)
        _ = try repository.saveNutrition(date: day, calories: nil, protein: 60, carbs: nil, fat: nil, isFinal: true)
        let nutrition = try repository.nutritionLogs()
        try require(nutrition.count == 1 && nutrition[0].calories == nil && nutrition[0].protein == 60 && nutrition[0].statusRaw == "final", "daily totals replace, never add, preserving optional fields")
        _ = try repository.saveRecovery(date: day, manualSleepHours: 6.5, soreness: 0, energy: nil, painScore: nil)
        try repository.saveHealthSleep(date: day, hours: 7, source: "Synthetic Health source", endDate: day, coverageData: nil)
        let recovery = try repository.recoveryLogs()[0]
        try require(recovery.displayedSleepHours == 6.5 && recovery.healthSleepHours == 7 && recovery.soreness == 0 && recovery.energy == nil, "manual sleep overrides and zero stays distinct from missing")
        _ = try repository.saveWeight(date: day, value: 80, unit: "kg")
        try require(try migrated.mainContext.fetchCount(FetchDescriptor<WeightEntry>()) == 2, "Coach writes the shared WeightEntry model")
        _ = try repository.saveWaist(date: day, value: 90, unit: "cm")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let sourceNutritionID = nutrition[0].id
        let destinationNutritionID = try repository.saveNutrition(date: tomorrow, calories: 900, protein: nil, carbs: 100, fat: nil)
        do {
            _ = try repository.moveNutrition(id: sourceNutritionID, to: tomorrow, mergedCalories: 0, mergedProtein: 60, mergedCarbs: nil, mergedFat: nil, mergedNotes: nil, isFinal: true)
            throw CoachRepositoryError.invalidValue("unreviewed collision should have failed")
        } catch CoachRepositoryError.dateCollision { count += 1 }
        let move = try repository.nutritionMovePreview(id: sourceNutritionID, to: tomorrow)
        _ = try repository.moveNutrition(id: sourceNutritionID, to: tomorrow, mergedCalories: 0, mergedProtein: 60, mergedCarbs: nil, mergedFat: nil, mergedNotes: "Reviewed fields", isFinal: true,
            expectedDestinationID: destinationNutritionID, expectedSourceUpdatedAt: move.source.updatedAt, expectedDestinationUpdatedAt: move.destination?.updatedAt)
        let moved = try repository.nutritionLogs()
        try require(moved.count == 1 && moved[0].id == destinationNutritionID && moved[0].calories == 0 && moved[0].protein == 60 && moved[0].carbs == nil, "reviewed merge retains destination ID and explicit fields without addition")
        let pendingWeight = WeightEntry(weight: 79, weightUnit: "kg")
        migrated.mainContext.insert(pendingWeight)
        let waistCount = try repository.waistMeasurements().count
        do {
            let _: UUID = try repository.transaction { isolated in
                let temporary = CoachWaistMeasurement(); temporary.value = 99; isolated.insert(temporary)
                throw CoachRepositoryError.invalidValue("synthetic transaction failure")
            }
        } catch CoachRepositoryError.invalidValue { count += 1 }
        try require(try repository.waistMeasurements().count == waistCount && migrated.mainContext.hasChanges && pendingWeight.modelContext != nil, "failed isolated write rolls back only its own rows")
        migrated.mainContext.delete(pendingWeight); try migrated.mainContext.save()
        let graph = try DataBackupService.capture(context: migrated.mainContext)
        let (_, restored) = try store("backup", local: true)
        try DataBackupService.restore(graph, context: restored.mainContext)
        try DataBackupService.restore(graph, context: restored.mainContext)
        try require(try restored.mainContext.fetchCount(FetchDescriptor<CoachNutritionLog>()) == 1 && restored.mainContext.fetchCount(FetchDescriptor<CoachRecoveryCheckIn>()) == 1 && restored.mainContext.fetchCount(FetchDescriptor<CoachWaistMeasurement>()) == 1, "all daily records restore idempotently")
        try require(try CoachLocalOwnership.snapshotDigest(restored.mainContext) == CoachLocalOwnership.snapshotDigest(migrated.mainContext), "complete backup graph round trip")
        for version in 1...4 {
            var legacy = graph; legacy.formatVersion = version; legacy.coach = nil
            let encoder = JSONEncoder()
            var object = try JSONSerialization.jsonObject(with: encoder.encode(legacy)) as! [String: Any]
            let laterKeys = ["executionStatusRaw", "plannedSessionID", "canonicalPlannedSessionID", "coachExecutionID", "completionProvenance", "endedAt", "hasMeasuredDistance", "intervalResultsData", "sourceHealthSampleID", "sourceName", "provenance", "coachSetResultID", "actualReps", "actualWeight", "actualDurationSeconds", "actualEffortScale", "actualEffort", "performedExerciseKey", "prescriptionBasis", "loadBasis"]
            let v3Keys = ["title", "shouldSaveAsTemplate", "sourceTemplateID", "generatedTemplateID", "isSampleData", "healthWorkoutUUID", "healthDuration", "healthCalories", "healthAvgHeartRate", "healthSourceName", "healthActivityType", "exerciseOrder", "exerciseType", "durationSeconds", "distance", "distanceUnit", "caloriesBurned", "avgHeartRate", "notes", "isCompleted", "isIsolated"]
            for collection in ["workoutSessions", "exerciseLogs", "runningSessions", "weightEntries"] {
                if var rows = object[collection] as? [[String: Any]] {
                    for index in rows.indices {
                        for key in laterKeys { rows[index].removeValue(forKey: key) }
                        if version < 3 && ["workoutSessions", "exerciseLogs"].contains(collection) {
                            for key in v3Keys { rows[index].removeValue(forKey: key) }
                        }
                    }
                    object[collection] = rows
                }
            }
            let decoded = try JSONDecoder().decode(BackupFile.self, from: JSONSerialization.data(withJSONObject: object))
            let (_, target) = try store("v\(version)", local: true)
            try DataBackupService.restore(decoded, context: target.mainContext)
            try require(try target.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()) == 1, "legacy backup v\(version) decodes and restores")
        }
        var movedLegacyArchive = graph
        movedLegacyArchive.coach?.plannedSessions[0].scheduleRevision = 3
        movedLegacyArchive.coach?.plannedSessions[0].localScheduleOverride = nil
        let oldScheduleData = try JSONEncoder().encode(movedLegacyArchive)
        let decodedOldSchedule = try JSONDecoder().decode(BackupFile.self, from: oldScheduleData)
        let (_, oldScheduleTarget) = try store("legacy-schedule-override", local: true)
        try DataBackupService.restore(decodedOldSchedule, context: oldScheduleTarget.mainContext)
        try require(try oldScheduleTarget.mainContext.fetch(FetchDescriptor<PlannedSession>()).first?.localScheduleOverride == true, "missing legacy override flag conservatively preserves moved rows")
        movedLegacyArchive.coach?.plannedSessions[0].localScheduleOverride = false
        let (_, modernScheduleTarget) = try store("modern-schedule-revision", local: true)
        try DataBackupService.restore(movedLegacyArchive, context: modernScheduleTarget.mainContext)
        try require(try modernScheduleTarget.mainContext.fetch(FetchDescriptor<PlannedSession>()).first?.localScheduleOverride == false, "reviewed revision changes do not become user schedule overrides")
        var malformed = graph
        malformed.weightEntries.append(graph.weightEntries[0])
        let (_, failedRestore) = try store("invalid-backup", local: true)
        do {
            try DataBackupService.restore(malformed, context: failedRestore.mainContext)
            throw CoachRepositoryError.invalidValue("duplicate backup should fail")
        } catch CoachHistoryArchive.ArchiveError.invalid { count += 1 }
        try require(try failedRestore.mainContext.fetchCount(FetchDescriptor<WeightEntry>()) == 0 && failedRestore.mainContext.hasChanges == false, "invalid backup fails before any model writes")
        let (zoneStoreURL, zoneStore) = try store("selected-time-zone", local: true)
        let selectedZone = TimeZone(identifier: "Pacific/Kiritimati")!
        let selectedStart = ISO8601DateFormatter().date(from: "2026-09-13T18:00:00Z")!
        let zoneDocument = CoachPlanDocument(programId: "selected_zone_regression", title: "Selected zone", goal: "General fitness",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .reviewRequired)],
            sessionTemplates: [.rest(.init(id: "rest", title: "Rest"))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "rest")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let zonePlanID = try await CoachRepository(context: zoneStore.mainContext).importPlan(document: zoneDocument, startDate: selectedStart, activate: false, timeZone: selectedZone)
        let reopenedZoneStore = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: zoneStoreURL, cloudKitDatabase: .none)])
        let savedZonePlan = try reopenedZoneStore.mainContext.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == zonePlanID }
        let savedZoneOccurrence = try reopenedZoneStore.mainContext.fetch(FetchDescriptor<PlannedSession>()).first
        try require(savedZonePlan?.timeZoneIdentifier == selectedZone.identifier && savedZonePlan?.startCivilDate == "2026-09-14" && savedZonePlan?.startDate == selectedStart,
            "import preserves the selected time zone and civil start date across disk reopening")
        try require(savedZoneOccurrence?.originalCivilDate == "2026-09-14" && savedZoneOccurrence?.currentCivilDate == "2026-09-14" && savedZoneOccurrence.map { CoachRepository.civilDate($0.scheduledDate, timeZone: selectedZone) } == "2026-09-14",
            "imported occurrence dates use the persisted selected time zone")
        count += try await runFailureCases(root: root)
        return count
    }
}
#endif
