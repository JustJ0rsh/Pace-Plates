#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachLegacyDuplicateBackupRegressionChecks {
    static func run() async throws -> Int {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("CoachLegacyDuplicateChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? files.removeItem(at: root) }
        func store(_ name: String) throws -> ModelContainer {
            let schema = PersistenceController.coachSchema
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: root.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)])
        }
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachRepositoryError.invalidValue("legacy duplicate backup regression: " + message) }
        }
        let source = try store("source"), context = source.mainContext, date = Date()
        let runID = UUID(), definitionID = UUID(), weightID = UUID()
        context.insert(RunningSession(id: runID, date: date, distance: 3.25, duration: 900, notes: "Unlinked legacy left run"))
        context.insert(RunningSession(id: runID, date: date, distance: 8.75, duration: 2400, notes: "Unlinked legacy right run"))
        context.insert(ExerciseDefinition(id: definitionID, name: "Unreferenced legacy left definition", muscleGroup: "Chest"))
        context.insert(ExerciseDefinition(id: definitionID, name: "Unreferenced legacy right definition", muscleGroup: "Back"))
        // Identical twins remain two physical rows, including after repeat import.
        context.insert(WeightEntry(id: weightID, date: date, weight: 80, weightUnit: "kg"))
        context.insert(WeightEntry(id: weightID, date: date, weight: 80, weightUnit: "kg"))
        let definition = ExerciseDefinition(name: "Uniquely referenced legacy definition", muscleGroup: "Chest")
        let workout = WorkoutSession(date: date, notes: "Legacy parent", title: "Unique legacy workout", executionStatus: .legacyRecorded)
        let log = ExerciseLog(reps: 7, weight: 40, weightUnit: "kg", exerciseName: definition.name, notes: "Unique legacy set")
        log.exerciseDefinition = definition; log.workoutSession = workout
        let template = WorkoutTemplate(title: "Unique legacy template"); template.sourceSession = workout
        let templateExercise = TemplateExercise(name: "Unique template exercise", order: 0, sets: 3, reps: 8); templateExercise.template = template
        let plan = RunningPlan(name: "Unique legacy run plan", style: "hybrid", targetDistanceMeters: 5000,
            primaryGoal: "hybrid", durationWeeks: 1, daysPerWeek: 1, startDate: date)
        let linkedRun = RunningSession(date: date, distance: 5, duration: 1800, notes: "Uniquely linked legacy run")
        let slot = RunningPlanSession(plan: plan, completedRun: linkedRun, weekIndex: 0, dayIndex: 0, sessionType: "easy",
            intensityLevel: "easy", status: "completed", completedRunSessionID: linkedRun.id)
        plan.sessions = [slot]; linkedRun.plannedSession = slot; linkedRun.plannedSessionID = slot.id
        context.insert(definition); context.insert(workout); context.insert(log); context.insert(template); context.insert(templateExercise)
        context.insert(plan); context.insert(slot); context.insert(linkedRun); try context.save()
        let original = try DataBackupService.capture(context: context)
        var legacy = original; legacy.formatVersion = 5; legacy.physicalRecords = nil
        func write(_ file: BackupFile, _ name: String, version: Int?, streamed: Bool = false) throws -> URL {
            var value = file; value.formatVersion = version
            var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
            if version == nil { object.removeValue(forKey: "formatVersion") }
            let historicalVersion = version ?? 1
            let laterKeys = ["executionStatusRaw", "canonicalPlannedSessionID", "coachExecutionID", "completionProvenance", "endedAt", "hasMeasuredDistance", "intervalResultsData", "sourceHealthSampleID", "sourceName", "provenance", "coachSetResultID", "actualReps", "actualWeight", "actualDurationSeconds", "actualEffortScale", "actualEffort", "performedExerciseKey", "prescriptionBasis", "loadBasis"]
            let version3Keys = ["title", "shouldSaveAsTemplate", "sourceTemplateID", "generatedTemplateID", "isSampleData", "healthWorkoutUUID", "healthDuration", "healthCalories", "healthAvgHeartRate", "healthSourceName", "healthActivityType", "exerciseOrder", "exerciseType", "durationSeconds", "distance", "distanceUnit", "caloriesBurned", "avgHeartRate", "notes", "isCompleted", "isIsolated"]
            for collection in ["workoutSessions", "exerciseLogs", "runningSessions", "weightEntries"] {
                if var entries = object[collection] as? [[String: Any]] {
                    for index in entries.indices {
                        if historicalVersion < 5 { for key in laterKeys { entries[index].removeValue(forKey: key) } }
                        if historicalVersion < 3 && ["workoutSessions", "exerciseLogs"].contains(collection) {
                            for key in version3Keys { entries[index].removeValue(forKey: key) }
                        }
                        if historicalVersion < 3 { entries[index].removeValue(forKey: "isSampleData") }
                        if historicalVersion < 4 && collection == "runningSessions" {
                            entries[index].removeValue(forKey: "linkedHealthWorkoutUUIDsRaw")
                        }
                    }
                    object[collection] = entries
                }
            }
            let records = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let url = root.appendingPathComponent(name + (streamed ? ".pacebackup" : ".json"))
            if streamed {
                let manifest = CoachHistoryArchive.Manifest(format: "pace-and-plates.history", version: 5, photosIncluded: false,
                    records: .init(path: "records.json", bytes: records.count, digest: CoachPhotoStore.digest(records)), assets: [])
                let encoded = try JSONEncoder().encode(manifest); var length = UInt64(encoded.count).bigEndian
                var bytes = CoachHistoryArchive.magic; withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
                bytes.append(encoded); bytes.append(records); try bytes.write(to: url)
            } else { try records.write(to: url) }
            return url
        }
        func roundTrip(_ file: BackupFile, _ name: String, version: Int?, streamed: Bool = false) async throws {
            let url = try write(file, name, version: version, streamed: streamed), bytes = try Data(contentsOf: url)
            let prepared = try CoachHistoryArchive.prepareImport(from: url)
            let expected = prepared.file
            try require(expected.formatVersion == 6 && expected.physicalRecords != nil
                        && (!streamed || prepared.manifest?.version == 5), "legacy IDs normalize in memory without retagging the original manifest")
            prepared.discard()
            let restored = try store(name)
            try await DataBackupService.import(from: url, context: restored.mainContext)
            func matches(_ container: ModelContainer) throws -> Bool {
                let actual = try DataBackupService.capture(context: ModelContext(container))
                return try expected.physicalRecords!.hasSameContent(as: actual.physicalRecords!, file: expected, otherFile: actual)
            }
            try require(try matches(restored), "legacy restore preserves all distinct rows, original UUIDs and uniquely saved relationships")
            let reopened = try store(name)
            try require(try matches(reopened), "legacy physical graph survives disk reopen")
            try await DataBackupService.import(from: url, context: reopened.mainContext)
            try require(try matches(reopened), "legacy exact-repeat import preserves identical-twin multiplicity")
            try require(try Data(contentsOf: url) == bytes, "legacy source file bytes are never rewritten")
        }
        try await roundTrip(legacy, "absent-version", version: nil)
        for version in 1...5 { try await roundTrip(legacy, "version-\(version)", version: version) }
        try await roundTrip(legacy, "stream-version-5", version: 5, streamed: true)
        var onlyRuns = try BackupPhysicalGraph.collections(in: legacy)
        for key in onlyRuns.keys where key != "runningSessions" { onlyRuns[key] = [] }
        onlyRuns["runningSessions"] = onlyRuns["runningSessions"]!.filter { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) == runID }
        let unlinked = try BackupPhysicalGraph.replacingCollections(in: legacy, with: onlyRuns)
        try await roundTrip(unlinked, "standalone-unlinked-runs", version: 5, streamed: true)
        func rejects(_ file: BackupFile, _ name: String, streamed: Bool = false) async throws {
            let url = try write(file, name, version: 5, streamed: streamed)
            let target = try store(name), retained = WeightEntry(weight: 69, weightUnit: "kg")
            target.mainContext.insert(retained); try target.mainContext.save()
            let before = try CoachLocalOwnership.rawCheckpoint(root.appendingPathComponent(name + ".store")).identity
            var message: String?
            do { try await DataBackupService.import(from: url, context: target.mainContext) }
            catch let error as CoachHistoryArchive.ArchiveError { message = error.localizedDescription }
            try require(message?.contains("Export a new backup") == true && message?.contains("No records were restored") == true,
                        "missing or ambiguous parent information has an actionable error")
            try require(try target.mainContext.fetchCount(FetchDescriptor<RunningSession>()) == 0
                        && target.mainContext.fetchCount(FetchDescriptor<WeightEntry>()) == 1, "legacy ambiguity rejects before unrelated inserts")
            try require(try CoachLocalOwnership.rawCheckpoint(root.appendingPathComponent(name + ".store")).identity == before,
                        "legacy ambiguity leaves retained destination bytes unchanged")
        }
        var ambiguous = try BackupPhysicalGraph.collections(in: legacy)
        ambiguous["exerciseLogs"]![0]["exerciseDefinitionId"] = definitionID.uuidString
        let ambiguousFile = try BackupPhysicalGraph.replacingCollections(in: legacy, with: ambiguous)
        try await rejects(ambiguousFile, "ambiguous-parent-json")
        try await rejects(ambiguousFile, "ambiguous-parent-stream", streamed: true)
        var missing = try BackupPhysicalGraph.collections(in: legacy)
        missing["exerciseLogs"]![0]["workoutSessionId"] = UUID().uuidString
        try await rejects(BackupPhysicalGraph.replacingCollections(in: legacy, with: missing), "missing-parent")
        var conflict = try BackupPhysicalGraph.collections(in: legacy)
        var secondWorkout = conflict["workoutSessions"]![0]
        let secondWorkoutID = UUID(); secondWorkout["id"] = secondWorkoutID.uuidString
        secondWorkout.removeValue(forKey: "generatedTemplateID")
        conflict["workoutSessions"]!.append(secondWorkout)
        conflict["workoutTemplates"]![0]["sourceSessionId"] = secondWorkoutID.uuidString
        try await rejects(BackupPhysicalGraph.replacingCollections(in: legacy, with: conflict), "conflicting-inverse")
        return count
    }
}
#endif
