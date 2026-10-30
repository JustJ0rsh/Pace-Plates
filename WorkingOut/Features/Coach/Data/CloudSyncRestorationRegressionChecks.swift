#if DEBUG
import Foundation
import SwiftData
import CoreData
import CryptoKit

@MainActor
enum CloudSyncRestorationRegressionChecks {
    /// Exercises the production split and restart paths with disposable stores.
    /// CloudKit is explicitly disabled in every container opened by this suite.
    static func run() throws -> Int {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncRestorationChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            guard value else { throw CoachRepositoryError.invalidValue("iCloud restoration regression: " + message) }
        }
        func paths(_ name: String) throws -> (URL, URL) {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(directory)
            return (directory.appendingPathComponent("default.store"),
                    directory.appendingPathComponent("ownership", isDirectory: true))
        }
        func selectVerified(_ selected: URL, legacy: URL, ownership: URL, checkpoint: String) throws {
            let journal = CoachLocalOwnership.MigrationJournal(
                id: UUID(), source: legacy.standardizedFileURL.path,
                directory: selected.deletingLastPathComponent().lastPathComponent,
                phase: "verified", checkpoint: checkpoint)
            try CoachLocalOwnership.writeJournal(journal, root: ownership)
            try CoachLocalOwnership.select(selected, legacy: legacy, root: ownership, journal: journal)
        }
        func legacyAliasedCheckpoint(_ url: URL) throws -> String {
            let current = try CoachLocalOwnership.rawCheckpoint(url)
            let support = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            var rows: [String] = []
            if let files = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let file as URL in files {
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    let relative = "/" + file.resolvingSymlinksInPath().pathComponents
                        .dropFirst(support.pathComponents.count).joined(separator: "/")
                    let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
                    rows.append("_SUPPORT" + relative + ":" + digest)
                }
            }
            let assetDigest = SHA256.hash(data: Data(rows.sorted().joined(separator: "\n").utf8))
                .map { String(format: "%02x", $0) }.joined()
            return current.digest + ":" + assetDigest
        }
        func checkConfigurations(_ container: ModelContainer, legacy: URL, coach: URL) throws {
            try require(container.configurations.count == 2, "legacy and Coach have distinct configurations")
            let legacyConfiguration = container.configurations.first { $0.url == legacy }
            let coachConfiguration = container.configurations.first { $0.url == coach }
            let legacyNames = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
            let coachNames = Set(CoachPersistence.modelTypes.map { String(describing: $0) })
            try require(Set(legacyConfiguration?.schema?.entities.map(\.name) ?? []) == legacyNames,
                        "the original store contains precisely the legacy model types")
            try require(Set(coachConfiguration?.schema?.entities.map(\.name) ?? []) == coachNames,
                        "the separate Coach store contains precisely the Coach model types")
            try require(CoachPersistence.isLocal(container.mainContext),
                        "Coach operations accept a context with a separate local Coach configuration")
        }

        let (freshLegacy, freshOwnership) = try paths("fresh")
        let freshCoach = try CloudSyncRestoration.prepare(legacyURL: freshLegacy, ownershipRoot: freshOwnership)
        try require(!FileManager.default.fileExists(atPath: freshLegacy.path),
                    "preparing a fresh install does not create or move the original store")
        let freshID = UUID()
        try autoreleasepool {
            let container = try CloudSyncRestoration.makeContainer(legacyURL: freshLegacy, coachURL: freshCoach, cloudKitMode: .none)
            try checkConfigurations(container, legacy: freshLegacy, coach: freshCoach)
            container.mainContext.insert(WeightEntry(id: freshID, weight: 70, weightUnit: "kg"))
            let nutrition = CoachNutritionLog(); nutrition.protein = 125
            container.mainContext.insert(nutrition)
            try container.mainContext.save()
        }
        try autoreleasepool {
            let coachURL = try CloudSyncRestoration.prepare(legacyURL: freshLegacy, ownershipRoot: freshOwnership)
            let container = try CloudSyncRestoration.makeContainer(legacyURL: freshLegacy, coachURL: coachURL, cloudKitMode: .none)
            try require(try container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == freshID,
                        "fresh legacy entries persist across reopening")
            try require(try container.mainContext.fetch(FetchDescriptor<CoachNutritionLog>()).first?.protein == 125,
                        "fresh local Coach entries persist across reopening")
        }

        let (legacyOnly, legacyOwnership) = try paths("legacy-without-selection")
        let retainedID = UUID()
        try autoreleasepool {
            let schema = Schema(PersistenceController.legacyModelTypes)
            let container = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, url: legacyOnly, cloudKitDatabase: .none)
            ])
            container.mainContext.insert(WeightEntry(id: retainedID, weight: 74, weightUnit: "kg"))
            try container.mainContext.save()
        }
        let legacyBefore = try CoachLocalOwnership.rawCheckpoint(legacyOnly).identity
        let legacyCoach = try CloudSyncRestoration.prepare(legacyURL: legacyOnly, ownershipRoot: legacyOwnership)
        try require(try CoachLocalOwnership.rawCheckpoint(legacyOnly).identity == legacyBefore,
                    "unmigrated legacy history is unchanged by preparation")
        try autoreleasepool {
            let container = try CloudSyncRestoration.makeContainer(legacyURL: legacyOnly, coachURL: legacyCoach, cloudKitMode: .none)
            try require(try container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == retainedID,
                        "unmigrated users reopen the original history without a local-copy gate")
        }

        for interruption in [nil, "prepared", "backedUp", "installed"] as [String?] {
            let (legacy, ownership) = try paths("selected-" + (interruption ?? "uninterrupted"))
            let workoutID = UUID(), logID = UUID(), weightID = UUID(), deletedWeightID = UUID(), newWeightID = UUID()
            let nutritionID = UUID()
            let route = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 5) })
            let healthDistanceAttempt = Date(timeIntervalSince1970: 1_792_987_200)
            try autoreleasepool {
                let schema = Schema(PersistenceController.legacyModelTypes)
                let original = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, url: legacy, cloudKitDatabase: .none)
                ])
                let workout = WorkoutSession(id: workoutID, notes: "Before local switch", title: "Original title")
                let definition = ExerciseDefinition(name: "Synthetic restoration press", muscleGroup: "Chest", isUserDefined: true)
                let log = ExerciseLog(id: logID, reps: 6, weight: 40, weightUnit: "kg", setNumber: 1, exerciseName: definition.name)
                log.workoutSession = workout; log.exerciseDefinition = definition
                original.mainContext.insert(workout); original.mainContext.insert(definition); original.mainContext.insert(log)
                original.mainContext.insert(WeightEntry(id: weightID, weight: 73, weightUnit: "kg"))
                original.mainContext.insert(WeightEntry(id: deletedWeightID, weight: 72, weightUnit: "kg"))
                original.mainContext.insert(RunningSession(distance: 5, distanceUnit: "km", duration: 1_600, locations: route))
                try original.mainContext.save()
            }
            let originalCheckpoint = try CoachLocalOwnership.rawCheckpoint(legacy).identity
            let selected = try CoachLocalOwnership.newStagingStore(root: ownership)
            try CoachLocalOwnership.copyStore(from: legacy, to: selected)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: legacy, to: selected)
            let expectedDigest: String = try autoreleasepool {
                let schema = PersistenceController.coachSchema
                let local = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: selected, cloudKitDatabase: .none)
                ])
                let context = local.mainContext
                let workout = try context.fetch(FetchDescriptor<WorkoutSession>()).first!
                workout.title = "Edited during 2.5"; workout.notes = "Keep the later local edit"
                let log = try context.fetch(FetchDescriptor<ExerciseLog>()).first!
                log.reps = 9; log.weight = 47.5
                let selectedRun = try context.fetch(FetchDescriptor<RunningSession>()).first
                selectedRun?.healthDistanceLastAttemptAt = healthDistanceAttempt
                for weight in try context.fetch(FetchDescriptor<WeightEntry>()) {
                    if weight.id == weightID { weight.weight = 76 }
                    if weight.id == deletedWeightID { context.delete(weight) }
                }
                context.insert(WeightEntry(id: newWeightID, weight: 77, weightUnit: "kg"))
                let nutrition = CoachNutritionLog(id: nutritionID)
                nutrition.civilDate = "2026-10-30"; nutrition.timeZoneIdentifier = "UTC"
                nutrition.protein = 130; nutrition.calories = 2_200; nutrition.notes = "Keep local Coach data"
                context.insert(nutrition)
                try context.save()
                return try CoachLocalOwnership.snapshotDigest(context)
            }
            try selectVerified(selected, legacy: legacy, ownership: ownership, checkpoint: originalCheckpoint)
            let selectedCheckpoint = try CoachLocalOwnership.rawCheckpoint(selected).identity
            if interruption == nil {
                let alias = root.appendingPathComponent("selected-parent-alias", isDirectory: true)
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: selected.deletingLastPathComponent())
                let aliased = alias.appendingPathComponent(selected.lastPathComponent)
                let support = selected.deletingLastPathComponent().appendingPathComponent(".default_SUPPORT", isDirectory: true)
                try require(FileManager.default.fileExists(atPath: support.path), "alias fixture contains external route assets")
                try require(try CoachLocalOwnership.rawCheckpoint(aliased).identity == selectedCheckpoint,
                            "parent aliases preserve the same database and asset checkpoint")
            }
            if let interruption {
                var interrupted = false
                do {
                    _ = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership, interruptAfter: interruption)
                } catch { interrupted = error.localizedDescription.contains("Synthetic interruption") }
                try require(interrupted, "the \(interruption) restart fixture reaches its injected interruption")
                if interruption == "installed" {
                    let journalURL = ownership.appendingPathComponent("iCloudRestoration/restoration.json")
                    guard var journal = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any],
                          let directory = journal["directory"] as? String else {
                        throw CoachRepositoryError.invalidValue("installed legacy journal fixture unavailable")
                    }
                    let coach = ownership.appendingPathComponent("iCloudRestoration/\(directory)/coach/coach.store")
                    journal["sourceCheckpoint"] = try legacyAliasedCheckpoint(selected)
                    journal["coachCheckpoint"] = try legacyAliasedCheckpoint(coach)
                    let legacyHistoryCheckpoint = try legacyAliasedCheckpoint(legacy)
                    journal["historyCheckpoint"] = legacyHistoryCheckpoint
                    try JSONSerialization.data(withJSONObject: journal).write(to: journalURL, options: .atomic)
                    try require(try CoachLocalOwnership.matchesCheckpoint(legacyHistoryCheckpoint, at: legacy),
                                "the exact legacy alias artifact matches unchanged installed assets")
                    let forgedDatabase = String(repeating: "0", count: 64) + ":"
                        + String(legacyHistoryCheckpoint.split(separator: ":", maxSplits: 1)[1])
                    let forgedMatches = try CoachLocalOwnership.matchesCheckpoint(forgedDatabase, at: legacy)
                    try require(!forgedMatches,
                                "legacy asset compatibility never accepts a changed database digest")
                    let support = legacy.deletingLastPathComponent().appendingPathComponent(".default_SUPPORT", isDirectory: true)
                    var firstAsset: URL?
                    if let files = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey]) {
                        for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                            firstAsset = file; break
                        }
                    }
                    guard let firstAsset else { throw CoachRepositoryError.invalidValue("legacy alias asset fixture unavailable") }
                    let originalBytes = try Data(contentsOf: firstAsset)
                    var changedBytes = originalBytes; changedBytes.append(0xff)
                    let changedMatches: Bool
                    do {
                        try changedBytes.write(to: firstAsset, options: .atomic)
                        changedMatches = try CoachLocalOwnership.matchesCheckpoint(legacyHistoryCheckpoint, at: legacy)
                        try originalBytes.write(to: firstAsset, options: .atomic)
                    } catch {
                        try? originalBytes.write(to: firstAsset, options: .atomic)
                        throw error
                    }
                    try require(!changedMatches, "legacy asset compatibility rejects changed asset bytes")
                }
            }
            let coach = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership)
            let historyMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: legacy)
            let coachMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: coach)
            let historyStoreID = historyMetadata[NSStoreUUIDKey] as? String
            let coachStoreID = coachMetadata[NSStoreUUIDKey] as? String
            try require(historyStoreID != nil && coachStoreID != nil && historyStoreID != coachStoreID,
                        "split stores have distinct Core Data identities for correct object fault resolution")
            try require(try CoachLocalOwnership.rawCheckpoint(selected).identity == selectedCheckpoint,
                        "the selected full history and external assets remain unchanged after \(interruption ?? "normal") restoration")
            try autoreleasepool {
                let split = try CloudSyncRestoration.makeContainer(legacyURL: legacy, coachURL: coach, cloudKitMode: .none)
                try checkConfigurations(split, legacy: legacy, coach: coach)
                try require(try CoachLocalOwnership.snapshotDigest(split.mainContext) == expectedDigest,
                            "all selected scalar values, UUIDs, relationships, and Coach data survive the split")
                let workouts = try split.mainContext.fetch(FetchDescriptor<WorkoutSession>())
                let logs = try split.mainContext.fetch(FetchDescriptor<ExerciseLog>())
                let weights = try split.mainContext.fetch(FetchDescriptor<WeightEntry>())
                try require(workouts.first?.id == workoutID && workouts.first?.title == "Edited during 2.5",
                            "same-ID local workout edits win over retained stale content")
                try require(logs.first?.id == logID && logs.first?.workoutSession?.id == workoutID && logs.first?.weight == 47.5,
                            "exercise values and parent links survive restoration")
                try require(Set(weights.map(\.id)) == Set([weightID, newWeightID]),
                            "local additions remain and locally deleted rows are not resurrected")
                let restoredRun = try split.mainContext.fetch(FetchDescriptor<RunningSession>()).first
                try require(restoredRun?.locations == route,
                            "external route bytes survive restoration")
                try require(restoredRun?.healthDistanceLastAttemptAt == healthDistanceAttempt,
                            "persisted fields omitted from portable backups survive the raw store split")
                let nutrition = try split.mainContext.fetch(FetchDescriptor<CoachNutritionLog>()).first!
                try require(nutrition.id == nutritionID && nutrition.protein == 130,
                            "Coach data remains in the local store with its original identity")
                workouts[0].title = "Edited after iCloud restoration"
                nutrition.protein = 140
                try split.mainContext.save()
            }
            let repeatedCoach = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership)
            try autoreleasepool {
                let split = try CloudSyncRestoration.makeContainer(legacyURL: legacy, coachURL: repeatedCoach, cloudKitMode: .none)
                try require(try split.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.title == "Edited after iCloud restoration",
                            "a later startup does not recopy stale pre-restoration history")
                try require(try split.mainContext.fetch(FetchDescriptor<CoachNutritionLog>()).first?.protein == 140,
                            "a later startup preserves subsequent local Coach edits")
            }
            let enumerator = FileManager.default.enumerator(at: ownership, includingPropertiesForKeys: [.isRegularFileKey])
            var foundOriginalBackup = false
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "store", url != selected, url != coach,
                   let checkpoint = try? CoachLocalOwnership.rawCheckpoint(url), checkpoint.identity == originalCheckpoint {
                    foundOriginalBackup = true
                }
            }
            try require(foundOriginalBackup, "the original pre-local legacy store and its external assets remain recoverable")
        }

        // A prepared snapshot must never replace the old store if either the
        // selected source or the staged copy changed before a restart.
        for changedFile in ["source", "stage"] {
            let (legacy, ownership) = try paths("prepared-change-" + changedFile)
            try autoreleasepool {
                let schema = Schema(PersistenceController.legacyModelTypes)
                let original = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, url: legacy, cloudKitDatabase: .none)
                ])
                original.mainContext.insert(WeightEntry(weight: 80, weightUnit: "kg"))
                try original.mainContext.save()
            }
            let originalCheckpoint = try CoachLocalOwnership.rawCheckpoint(legacy).identity
            let selected = try CoachLocalOwnership.newStagingStore(root: ownership)
            try CoachLocalOwnership.copyStore(from: legacy, to: selected)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: legacy, to: selected)
            try autoreleasepool {
                let schema = PersistenceController.coachSchema
                let local = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: selected, cloudKitDatabase: .none)
                ])
                let localWeight = try local.mainContext.fetch(FetchDescriptor<WeightEntry>()).first
                localWeight?.weight = 81
                try local.mainContext.save()
            }
            try selectVerified(selected, legacy: legacy, ownership: ownership, checkpoint: originalCheckpoint)
            var interrupted = false
            do {
                _ = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership, interruptAfter: "prepared")
            } catch { interrupted = error.localizedDescription.contains("Synthetic interruption") }
            try require(interrupted, "changed-\(changedFile) fixture reaches a completed prepared snapshot")

            let changedURL: URL
            let changedSchema: Schema
            if changedFile == "source" {
                changedURL = selected
                changedSchema = PersistenceController.coachSchema
            } else {
                let stagedFiles = FileManager.default.enumerator(at: ownership, includingPropertiesForKeys: nil)
                var stage: URL?
                while let url = stagedFiles?.nextObject() as? URL {
                    if url.path.hasSuffix("/history/default.store") { stage = url; break }
                }
                guard let stage else { throw CoachRepositoryError.invalidValue("prepared history fixture was not found") }
                changedURL = stage
                changedSchema = Schema(PersistenceController.legacyModelTypes)
            }
            try autoreleasepool {
                let changed = try ModelContainer(for: changedSchema, configurations: [
                    ModelConfiguration(schema: changedSchema, url: changedURL, cloudKitDatabase: .none)
                ])
                let changedWeight = try changed.mainContext.fetch(FetchDescriptor<WeightEntry>()).first
                changedWeight?.weight = 99
                try changed.mainContext.save()
            }
            var rejectedChange = false
            do {
                _ = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership)
            } catch {
                rejectedChange = error.localizedDescription.contains(changedFile == "source"
                    ? "History changed during iCloud recovery" : "staged history changed during iCloud recovery")
            }
            try require(rejectedChange, "resuming rejects changed \(changedFile) content before replacing history")
            try require(try CoachLocalOwnership.rawCheckpoint(legacy).identity == originalCheckpoint,
                        "changed \(changedFile) rejection leaves the original legacy store untouched")
            try require(FileManager.default.fileExists(atPath: selected.path),
                        "changed \(changedFile) rejection retains the selected source")
        }

        // The app sandbox path can change after an update while its selected
        // UUID directory remains the same. A different selection is not a retry.
        for replaceSelection in [false, true] {
            let (legacy, ownership) = try paths("relocated-ownership-" + String(replaceSelection))
            let weightID = UUID()
            let legacySchema = Schema(PersistenceController.legacyModelTypes)
            try autoreleasepool {
                let original = try ModelContainer(for: legacySchema, configurations: [
                    ModelConfiguration(schema: legacySchema, url: legacy, cloudKitDatabase: .none)
                ])
                original.mainContext.insert(WeightEntry(id: weightID, weight: 80, weightUnit: "kg"))
                try original.mainContext.save()
            }
            let originalCheckpoint = try CoachLocalOwnership.rawCheckpoint(legacy).identity
            let selected = try CoachLocalOwnership.newStagingStore(root: ownership)
            try CoachLocalOwnership.copyStore(from: legacy, to: selected)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: legacy, to: selected)
            try autoreleasepool {
                let schema = PersistenceController.coachSchema
                let local = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: selected, cloudKitDatabase: .none)
                ])
                let weight = try local.mainContext.fetch(FetchDescriptor<WeightEntry>()).first
                weight?.weight = 82
                try local.mainContext.save()
            }
            try selectVerified(selected, legacy: legacy, ownership: ownership, checkpoint: originalCheckpoint)
            let selectedCheckpoint = try CoachLocalOwnership.rawCheckpoint(selected).identity
            var interrupted = false
            do {
                _ = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: ownership, interruptAfter: "prepared")
            } catch { interrupted = error.localizedDescription.contains("Synthetic interruption") }
            try require(interrupted, "relocation fixture reaches a verified prepared journal")
            let relocated = ownership.deletingLastPathComponent().appendingPathComponent("updated-sandbox/ownership", isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(relocated.deletingLastPathComponent())
            // Model a replacement app container without moving fixture files
            // that a framework may still retain in this test process.
            try FileManager.default.copyItem(at: ownership, to: relocated)
            let retainedSelection = relocated.appendingPathComponent(selected.deletingLastPathComponent().lastPathComponent)
                .appendingPathComponent("default.store")
            if replaceSelection {
                let replacement = try CoachLocalOwnership.newStagingStore(root: relocated)
                try CoachLocalOwnership.copyStore(from: retainedSelection, to: replacement)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: retainedSelection, to: replacement)
                try selectVerified(replacement, legacy: legacy, ownership: relocated, checkpoint: originalCheckpoint)
                var rejected = false
                do { _ = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: relocated) }
                catch { rejected = error.localizedDescription.contains("History changed during iCloud recovery") }
                try require(rejected, "a different selected UUID is rejected even when its copied content matches")
                try require(try CoachLocalOwnership.rawCheckpoint(legacy).identity == originalCheckpoint,
                            "rejecting a changed selection leaves the original iCloud store untouched")
            } else {
                let coach = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: relocated)
                try require(try CoachLocalOwnership.rawCheckpoint(retainedSelection).identity == selectedCheckpoint,
                            "resuming under a new sandbox path retains the selected source unchanged")
                try autoreleasepool {
                    let restored = try CloudSyncRestoration.makeContainer(legacyURL: legacy, coachURL: coach, cloudKitMode: .none)
                    let weight = try restored.mainContext.fetch(FetchDescriptor<WeightEntry>()).first
                    try require(weight?.id == weightID && weight?.weight == 82,
                                "the same selected UUID resumes after an app-data container relocation")
                }
            }
        }

        // Replay must create exportable persistent history, while keeping the
        // original cloud store identity. A changed baseline disables deletions.
        let (replayBaseline, _) = try paths("direct-replay-baseline")
        let (replayLocal, _) = try paths("direct-replay-local")
        let originalID = UUID(), removedID = UUID(), addedID = UUID(), remoteOnlyID = UUID()
        let legacySchema = Schema(PersistenceController.legacyModelTypes)
        try autoreleasepool {
            let baseline = try ModelContainer(for: legacySchema, configurations: [
                ModelConfiguration(schema: legacySchema, url: replayBaseline, cloudKitDatabase: .none)
            ])
            baseline.mainContext.insert(ExerciseDefinition(id: originalID, name: "Replay original", muscleGroup: "Synthetic", isUserDefined: true))
            baseline.mainContext.insert(ExerciseDefinition(id: removedID, name: "Replay removed locally", muscleGroup: "Synthetic", isUserDefined: true))
            try baseline.mainContext.save()
        }
        try CoachLocalOwnership.copyStore(from: replayBaseline, to: replayLocal)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: replayBaseline, to: replayLocal)
        try autoreleasepool {
            let local = try ModelContainer(for: PersistenceController.coachSchema, configurations: [
                ModelConfiguration(CoachPersistence.configurationName, schema: PersistenceController.coachSchema,
                                   url: replayLocal, cloudKitDatabase: .none)
            ])
            for row in try local.mainContext.fetch(FetchDescriptor<ExerciseDefinition>()) {
                if row.id == originalID { row.name = "Replay local update" }
                if row.id == removedID { local.mainContext.delete(row) }
            }
            local.mainContext.insert(ExerciseDefinition(id: addedID, name: "Replay local insertion", muscleGroup: "Synthetic", isUserDefined: true))
            try local.mainContext.save()
        }
        try autoreleasepool {
            let baseline = try ModelContainer(for: legacySchema, configurations: [
                ModelConfiguration(schema: legacySchema, url: replayBaseline, cloudKitDatabase: .none)
            ])
            baseline.mainContext.insert(ExerciseDefinition(id: remoteOnlyID, name: "Replay newer remote row", muscleGroup: "Synthetic", isUserDefined: true))
            try baseline.mainContext.save()
        }
        for allowDeletions in [true, false] {
            let (destination, _) = try paths("direct-replay-" + String(allowDeletions))
            try CoachLocalOwnership.copyStore(from: replayBaseline, to: destination)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: replayBaseline, to: destination)
            let beforeID = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: destination)[NSStoreUUIDKey] as? String
            try CloudHistoryReplay.replay(baselineURL: replayBaseline, localSnapshotURL: replayLocal,
                                          destinationURL: destination, allowDeletions: allowDeletions)
            let afterID = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: destination)[NSStoreUUIDKey] as? String
            try require(beforeID != nil && beforeID == afterID, "replay preserves the original cloud store UUID")
            try autoreleasepool {
                let replayed = try ModelContainer(for: legacySchema, configurations: [
                    ModelConfiguration(schema: legacySchema, url: destination, cloudKitDatabase: .none)
                ])
                let rows = try replayed.mainContext.fetch(FetchDescriptor<ExerciseDefinition>())
                try require(rows.first(where: { $0.id == originalID })?.name == "Replay local update"
                            && rows.contains(where: { $0.id == addedID }),
                            "replay applies same-ID updates and new local records")
                let expectedIDs = allowDeletions ? Set([originalID, addedID])
                    : Set([originalID, removedID, addedID, remoteOnlyID])
                try require(Set(rows.map(\.id)) == expectedIDs,
                            allowDeletions ? "verified-baseline replay applies local deletions"
                                : "replay without deletion permission preserves rows absent from the local snapshot")
            }
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: legacySchema) else {
                throw CoachRepositoryError.invalidValue("replay history model unavailable")
            }
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: destination,
                options: [NSPersistentHistoryTrackingKey: true, NSReadOnlyPersistentStoreOption: true])
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let types: Set<NSPersistentHistoryChangeType> = try context.performAndWait {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
                request.resultType = .transactionsAndChanges
                guard let result = try context.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    throw CoachRepositoryError.invalidValue("replay persistent history unavailable")
                }
                return Set(transactions.filter { $0.author == "icloud-restoration-v1" }
                    .flatMap { $0.changes ?? [] }.map(\.changeType))
            }
            context.performAndWait { context.reset() }
            try coordinator.remove(store)
            try require(types.contains(.insert) && types.contains(.update)
                        && (!allowDeletions || types.contains(.delete)),
                        "replay records insert/update/deletion transactions for CloudKit export")
        }
        count += try CloudHistoryReplayDuplicateRegressionChecks.run()
        return count
    }
}
#endif
