#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CloudHistoryReplayDuplicateRegressionChecks {
    /// App UUIDs are not unique in existing installations. Exercise both replay
    /// policies with distinct physical rows and the real inverse relationships.
    static func run() throws -> Int {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudReplayDuplicateChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func require(_ condition: Bool, _ message: String) throws {
            count += 1
            guard condition else { throw CoachRepositoryError.invalidValue("Duplicate history replay: " + message) }
        }
        func copy(_ source: URL, to destination: URL) throws {
            try CoachLocalOwnership.copyStore(from: source, to: destination)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: destination)
        }
        let legacySchema = Schema(PersistenceController.legacyModelTypes)
        for allowDeletions in [true, false] {
            let directory = root.appendingPathComponent(allowDeletions ? "delete" : "retain", isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(directory)
            let originalURL = directory.appendingPathComponent("original.store")
            let baselineURL = directory.appendingPathComponent("baseline.store")
            let localURL = directory.appendingPathComponent("local.store")
            let destinationURL = directory.appendingPathComponent("destination.store")
            let definitionID = UUID()
            let logID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            let spacerID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
            let leftSessionID = UUID(), rightSessionID = UUID(), absentSessionID = UUID()
            let absentLogID = UUID(), movedLogID = UUID()
            try autoreleasepool {
                let container = try ModelContainer(for: legacySchema, configurations: [
                    ModelConfiguration(schema: legacySchema, url: originalURL, cloudKitDatabase: .none)
                ])
                let context = container.mainContext
                let left = ExerciseDefinition(id: definitionID, name: "Replay left definition", muscleGroup: "Chest", isUserDefined: true)
                let right = ExerciseDefinition(id: definitionID, name: "Replay right definition", muscleGroup: "Back", isUserDefined: true)
                let leftSession = WorkoutSession(id: leftSessionID, title: "Replay left workout")
                let rightSession = WorkoutSession(id: rightSessionID, title: "Replay right workout")
                let absentSession = WorkoutSession(id: absentSessionID, title: "Replay retained workout")
                context.insert(left); context.insert(right)
                context.insert(leftSession); context.insert(rightSession); context.insert(absentSession)
                let first = ExerciseLog(id: logID, reps: 5, weight: 41, notes: "first duplicate")
                first.exerciseDefinition = left; first.workoutSession = leftSession
                let second = ExerciseLog(id: logID, reps: 6, weight: 42, notes: "second duplicate")
                second.exerciseDefinition = right; second.workoutSession = rightSession
                let absent = ExerciseLog(id: absentLogID, reps: 7, weight: 43, notes: "retained inverse")
                absent.exerciseDefinition = left; absent.workoutSession = leftSession
                let moved = ExerciseLog(id: movedLogID, reps: 8, weight: 44, notes: "moved inverse")
                moved.exerciseDefinition = right; moved.workoutSession = absentSession
                for log in [first, second, absent, moved] { context.insert(log) }
                try context.save()
            }
            let originalCheckpoint = try CoachLocalOwnership.rawCheckpoint(originalURL).identity
            try copy(originalURL, to: baselineURL)
            try copy(originalURL, to: localURL)
            try copy(originalURL, to: destinationURL)
            try autoreleasepool {
                let full = PersistenceController.coachSchema
                let container = try ModelContainer(for: full, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: full, url: localURL, cloudKitDatabase: .none)
                ])
                let context = container.mainContext
                let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
                let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
                let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
                guard let left = definitions.first(where: { $0.name == "Replay left definition" }),
                      let rightSession = sessions.first(where: { $0.id == rightSessionID }),
                      let absentSession = sessions.first(where: { $0.id == absentSessionID }),
                      let second = logs.first(where: { $0.notes == "second duplicate" }),
                      let absent = logs.first(where: { $0.id == absentLogID }),
                      let moved = logs.first(where: { $0.id == movedLogID }) else {
                    throw CoachRepositoryError.invalidValue("Duplicate replay fixture could not be reopened")
                }
                left.name = "Replay left definition edited"
                second.reps = 11; second.weight = 55
                moved.workoutSession = rightSession
                context.delete(absent)
                context.delete(absentSession)
                // Separate saves force source row allocation in the opposite
                // order to replay's UUID ordering, exercising insertion aliases.
                let spacer = ExerciseLog(id: spacerID, reps: 9, weight: 45, notes: "insertion spacer")
                spacer.exerciseDefinition = left; spacer.workoutSession = rightSession
                context.insert(spacer)
                try context.save()
                let third = ExerciseLog(id: logID, reps: 10, weight: 46, notes: "third duplicate")
                third.exerciseDefinition = left; third.workoutSession = rightSession
                context.insert(third)
                try context.save()
            }
            let localCheckpoint = try CoachLocalOwnership.rawCheckpoint(localURL).identity
            try CloudHistoryReplay.replay(baselineURL: baselineURL, localSnapshotURL: localURL,
                                          destinationURL: destinationURL, allowDeletions: allowDeletions)
            try require(try CoachLocalOwnership.rawCheckpoint(originalURL).identity == originalCheckpoint,
                        "the original store remains unchanged")
            try require(try CoachLocalOwnership.rawCheckpoint(localURL).identity == localCheckpoint,
                        "the selected local source remains unchanged")
            try autoreleasepool {
                let container = try ModelContainer(for: legacySchema, configurations: [
                    ModelConfiguration(schema: legacySchema, url: destinationURL, cloudKitDatabase: .none)
                ])
                let context = container.mainContext
                let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
                let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
                let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
                try require(definitions.count == 2 && definitions.allSatisfy { $0.id == definitionID },
                            "duplicate definition UUIDs retain both physical rows")
                try require(logs.filter { $0.id == logID }.count == 3,
                            "both duplicate logs and the same-UUID insertion survive")
                try require(logs.count == (allowDeletions ? 5 : 6), "no log is silently deduplicated")
                try require(sessions.count == (allowDeletions ? 2 : 3), "the chosen deletion policy preserves the expected sessions")
                guard let first = logs.first(where: { $0.notes == "first duplicate" }),
                      let second = logs.first(where: { $0.notes == "second duplicate" }),
                      let third = logs.first(where: { $0.notes == "third duplicate" }),
                      let moved = logs.first(where: { $0.id == movedLogID }),
                      let spacer = logs.first(where: { $0.id == spacerID }) else {
                    throw CoachRepositoryError.invalidValue("Replayed duplicate fixture is missing a record")
                }
                try require(first.weight == 41 && first.reps == 5, "an edit does not overwrite another row with the same UUID")
                try require(second.weight == 55 && second.reps == 11, "the intended duplicate log receives its edit")
                try require(first.exerciseDefinition?.name == "Replay left definition edited", "first duplicate keeps the left definition")
                try require(second.exerciseDefinition?.name == "Replay right definition", "second duplicate keeps the distinct right definition")
                try require(first.workoutSession?.id == leftSessionID && second.workoutSession?.id == rightSessionID,
                            "same-UUID logs keep different workout parents")
                try require(third.weight == 46 && third.workoutSession?.id == rightSessionID
                            && third.exerciseDefinition?.name == "Replay left definition edited",
                            "a newly inserted duplicate resolves through its destination alias")
                try require(spacer.weight == 45 && spacer.workoutSession?.id == rightSessionID,
                            "source and destination insertion ordering does not exchange rows")
                try require(moved.workoutSession?.id == rightSessionID, "a moved log keeps its new parent")
                let absent = logs.first { $0.id == absentLogID }
                try require((absent == nil) == allowDeletions, "only verified deletion removes the absent log")
                if !allowDeletions {
                    try require(absent?.workoutSession?.id == leftSessionID
                                && absent?.exerciseDefinition?.name == "Replay left definition edited",
                                "retained rows preserve links to locally edited parents")
                    let left = sessions.first { $0.id == leftSessionID }
                    try require(left?.exerciseLogs?.contains { $0.id == absentLogID } == true,
                                "retained rows remain in parent inverse collections")
                    let oldParent = sessions.first { $0.id == absentSessionID }
                    try require(oldParent != nil && (oldParent?.exerciseLogs?.isEmpty ?? true),
                                "a retained old parent releases a child moved locally")
                }
            }
        }
        return count
    }
}
#endif
