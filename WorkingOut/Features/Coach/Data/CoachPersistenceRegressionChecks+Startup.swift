#if DEBUG
import Foundation
import SwiftData
import SQLite3

@MainActor
private enum StartupStorageEvidence {
    static var coldSourceMigrationStatus = "not reached"
}

extension CoachPersistenceRegressionChecks {
    static var coldSourceMigrationStatus: String { StartupStorageEvidence.coldSourceMigrationStatus }

    /// Executes the real startup/migration implementation using only disposable
    /// legacy fixtures. Never resolves an application or CloudKit store URL.
    @MainActor static func runStartupCases(root: URL) async throws -> Int {
        var checks = 0
        StartupStorageEvidence.coldSourceMigrationStatus = "not reached"
        func require(_ value: Bool, _ reason: String) throws {
            checks += 1
            guard value else { throw CoachRepositoryError.invalidValue("startup regression: " + reason) }
        }
        func paths(_ name: String) throws -> (URL, URL) {
            let folder = root.appendingPathComponent("startup-" + name, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(folder)
            return (folder.appendingPathComponent("ownership", isDirectory: true), folder.appendingPathComponent("default.store"))
        }
        let temporary = FileManager.default.temporaryDirectory
        let trailingSlash = URL(fileURLWithPath: temporary.path + "/", isDirectory: true)
        try require(PersistenceController.isSyntheticDescendant(root, of: trailingSlash),
                    "temporary-directory trailing slash does not reject a contained fixture")
        try require(!PersistenceController.isSyntheticDescendant(temporary, of: temporary),
                    "temporary root itself is not an owned fixture")
        try require(!PersistenceController.isSyntheticDescendant(URL(fileURLWithPath: temporary.path + "-outside/example"), of: temporary),
                    "prefix sibling is not a contained fixture")
        try require(PersistenceController.isSyntheticDescendant(root.appendingPathComponent("not-created/ownership", isDirectory: true), of: temporary),
                    "nonexistent fixture tail resolves through its existing temporary ancestor")
        let outsideLink = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: outsideLink, withDestinationURL: root.deletingLastPathComponent())
        try require(!PersistenceController.isSyntheticDescendant(outsideLink.appendingPathComponent("outside-child"), of: root),
                    "symbolic link outside the owned fixture is rejected")
        let ordinaryFile = root.appendingPathComponent("ordinary-file")
        try Data().write(to: ordinaryFile)
        try require(!PersistenceController.isSyntheticDescendant(ordinaryFile.appendingPathComponent("child"), of: root),
                    "a file cannot be the parent of a new fixture directory")
        let (freshRoot, freshLegacy) = try paths("fresh")
        let fresh = PersistenceController(storageRootForRegression: freshRoot, legacyStoreForRegression: freshLegacy)
        try require(fresh.isCoachLocal && !fresh.isCloudBacked && fresh.storageError == nil, "fresh startup selects explicit local storage")
        let freshWeight = WeightEntry(date: Date(timeIntervalSince1970: 10), weight: 82, weightUnit: "kg")
        fresh.container.mainContext.insert(freshWeight); try fresh.container.mainContext.save()
        let reopenedFresh = PersistenceController(storageRootForRegression: freshRoot, legacyStoreForRegression: freshLegacy)
        try require(try reopenedFresh.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == freshWeight.id,
                    "fresh local selection reopens the same records")

        let schema = Schema(PersistenceController.legacyModelTypes)
        for interruption in ["allocated", "copied", "verified", "selected"] {
            let (ownership, legacyURL) = try paths(interruption)
            let legacy = try ModelContainer(for: schema, configurations: [ModelConfiguration("LegacyFixture", schema: schema, url: legacyURL, cloudKitDatabase: .none)])
            let workout = WorkoutSession(date: Date(timeIntervalSince1970: 1_750_000_000), notes: "Synthetic only", title: "Legacy " + interruption, executionStatus: .inProgress)
            let definition = ExerciseDefinition(name: "Synthetic press", muscleGroup: "Chest", isUserDefined: true)
            let log = ExerciseLog(reps: 3, weight: 20, weightUnit: "kg", setNumber: 1, exerciseName: definition.name, isCompleted: false)
            log.workoutSession = workout; log.exerciseDefinition = definition
            let route = Data((0..<256_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
            let run = RunningSession(date: workout.date, distance: 1, distanceUnit: "km", duration: 600, locations: route)
            legacy.mainContext.insert(workout); legacy.mainContext.insert(definition); legacy.mainContext.insert(log); legacy.mainContext.insert(run)
            try legacy.mainContext.save()
            let before = try CoachLocalOwnership.rawCheckpoint(legacyURL)
            let pending = PersistenceController(storageRootForRegression: ownership, legacyStoreForRegression: legacyURL)
            try require(pending.needsLegacyMigration && !pending.isCoachLocal && !pending.isCloudBacked && pending.storageError != nil,
                        "legacy startup gates app access without opening cloud storage")
            var stopped = false
            do {
                try await pending.migrateForStorageRegression(interruptAfter: interruption)
            } catch { stopped = true }
            try require(stopped, "injected interruption stops before completion")
            try require(try CoachLocalOwnership.rawCheckpoint(legacyURL).identity == before.identity,
                        "interruption leaves original SQLite and assets unchanged")
            let resumed = PersistenceController(storageRootForRegression: ownership, legacyStoreForRegression: legacyURL)
            if !resumed.isCoachLocal { try await resumed.migrateForStorageRegression(interruptAfter: nil) }
            try require(resumed.isCoachLocal && resumed.storageError == nil && !resumed.needsLegacyMigration,
                        "interrupted migration resumes to one local selection")
            let rows = try resumed.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
            let logs = try resumed.container.mainContext.fetch(FetchDescriptor<ExerciseLog>())
            let runs = try resumed.container.mainContext.fetch(FetchDescriptor<RunningSession>())
            try require(rows.count == 1 && rows.first?.id == workout.id && logs.first?.id == log.id && logs.first?.isCompleted == false && logs.first?.reps == 3,
                        "identity, relationships, actuals and incomplete flags survive actual migration")
            try require(runs.first?.locations == route, "external route bytes survive actual migration")
            let newWeight = WeightEntry(date: workout.date, weight: 72, weightUnit: "kg")
            resumed.container.mainContext.insert(newWeight); try resumed.container.mainContext.save()
            let nextLaunch = PersistenceController(storageRootForRegression: ownership, legacyStoreForRegression: legacyURL)
            try require(try nextLaunch.container.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()) == 1 && nextLaunch.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).contains { $0.id == newWeight.id },
                        "restart does not recopy or discard new local writes")
            try require(try CoachLocalOwnership.rawCheckpoint(legacyURL).identity == before.identity, "source remains unchanged after successful selection")
            if interruption == "selected" {
                let journalURL = CoachLocalOwnership.journalURL(root: ownership)
                let journalBytes = try Data(contentsOf: journalURL)
                try FileManager.default.removeItem(at: journalURL)
                let missingJournal = PersistenceController(storageRootForRegression: ownership, legacyStoreForRegression: legacyURL)
                try require(!missingJournal.isCoachLocal && missingJournal.storageError != nil, "missing migration journal fails closed")
                try Data("{}".utf8).write(to: journalURL)
                let corruptJournal = PersistenceController(storageRootForRegression: ownership, legacyStoreForRegression: legacyURL)
                try require(!corruptJournal.isCoachLocal && corruptJournal.storageError != nil, "corrupt migration journal fails closed")
                try journalBytes.write(to: journalURL)
                let chosen = try CoachLocalOwnership.selectedStoreURL(root: ownership)!
                try FileManager.default.removeItem(at: chosen)
                var rejectedMissing = false
                do { try await pending.migrateForStorageRegression(interruptAfter: nil) }
                catch { rejectedMissing = true }
                try require(rejectedMissing && !pending.isCoachLocal && !FileManager.default.fileExists(atPath: chosen.path),
                            "retry of committed missing selection cannot create an empty store")
            }
        }

        let (changedRoot, changedURL) = try paths("changed-source")
        let changing = try ModelContainer(for: schema, configurations: [ModelConfiguration("LegacyFixture", schema: schema, url: changedURL, cloudKitDatabase: .none)])
        let changingWorkout = WorkoutSession(date: Date(timeIntervalSince1970: 12), notes: "Before", title: "Changing source")
        changing.mainContext.insert(changingWorkout); try changing.mainContext.save()
        let changingController = PersistenceController(storageRootForRegression: changedRoot, legacyStoreForRegression: changedURL)
        do { try await changingController.migrateForStorageRegression(interruptAfter: "copied") } catch { }
        let oldJournal = try CoachLocalOwnership.readJournal(root: changedRoot)!
        changingWorkout.notes = "Updated retained source"; try changing.mainContext.save()
        try await changingController.migrateForStorageRegression(interruptAfter: nil)
        let newJournal = try CoachLocalOwnership.readJournal(root: changedRoot)!
        try require(oldJournal.id != newJournal.id && FileManager.default.fileExists(atPath: CoachLocalOwnership.destination(for: oldJournal, root: changedRoot).path),
                    "explicit retry after source change retains old stage and makes a fresh copy")
        try require(try changingController.container.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.notes == "Updated retained source",
                    "fresh retry contains the latest source values")

        let lockRoot = root.appendingPathComponent("startup-lock", isDirectory: true)
        let held = try CoachLocalOwnership.MigrationLock(root: lockRoot)
        var lockRejected = false
        do { _ = try CoachLocalOwnership.MigrationLock(root: lockRoot) } catch { lockRejected = true }
        try require(lockRejected, "a concurrent migration lock is refused")
        withExtendedLifetime(held) { }

        let (orphanRoot, orphanLegacy) = try paths("orphan")
        try Data("synthetic orphan".utf8).write(to: URL(fileURLWithPath: orphanLegacy.path + "-wal"))
        let orphan = PersistenceController(storageRootForRegression: orphanRoot, legacyStoreForRegression: orphanLegacy)
        try require(!orphan.isCoachLocal && !orphan.needsLegacyMigration && orphan.storageError != nil,
                    "orphan sidecar does not create an empty replacement history")
        let selected = try CoachLocalOwnership.selectedStoreURL(root: freshRoot)!
        try FileManager.default.removeItem(at: selected)
        let missing = PersistenceController(storageRootForRegression: freshRoot, legacyStoreForRegression: freshLegacy)
        try require(!missing.isCoachLocal && missing.storageError != nil, "missing selected store does not fall back")
        try FileManager.default.removeItem(at: freshRoot.appendingPathComponent("selection.json"))
        let lostMarker = PersistenceController(storageRootForRegression: freshRoot, legacyStoreForRegression: freshLegacy)
        try require(!lostMarker.isCoachLocal && lostMarker.storageError != nil, "unselected local directories prevent empty replacement after marker loss")
        checks += try runSemanticMigrationCases(root: root)
        // Run the independent active-source suite before probing the platform
        // cold-WAL limitation so a fixture problem cannot hide its evidence.
        let (coldRoot, coldURL) = try paths("closed-legacy")
        let seedURL = coldURL.deletingLastPathComponent().appendingPathComponent("seed.store")
        StartupStorageEvidence.coldSourceMigrationStatus = "preparing deterministic cold fixture"
        let coldValues: (workout: UUID, run: UUID, route: Data) = try autoreleasepool {
            let seed = try ModelContainer(for: schema, configurations: [ModelConfiguration("LegacyFixture", schema: schema, url: seedURL, cloudKitDatabase: .none)])
            let workout = WorkoutSession(date: Date(timeIntervalSince1970: 25), notes: "Closed synthetic source", title: "Cold history")
            let bytes = Data((0..<128_000).map { UInt8(truncatingIfNeeded: $0 &* 17) })
            let run = RunningSession(date: workout.date, distance: 2, distanceUnit: "km", duration: 900, locations: bytes)
            seed.mainContext.insert(workout); seed.mainContext.insert(run)
            try seed.mainContext.save()
            // Use the actual consistent backup API while the full-model seed
            // may be live. Never copy an active SQLite main file by itself.
            try CoachLocalOwnership.copyStore(from: seedURL, to: coldURL)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: seedURL, to: coldURL)
            try require(try CoachLocalOwnership.rawCheckpoint(seedURL).identity == CoachLocalOwnership.rawCheckpoint(coldURL).identity,
                        "deterministic cold fixture starts as an exact full-model backup")
            return (workout.id, run.id, bytes)
        }
        // This new test-owned snapshot has never been opened by SwiftData.
        // Its only SQLite writer sets WAL mode, then closes naturally. No
        // WAL/SHM files are removed to manufacture a successful cold test.
        try prepareSyntheticColdWAL(coldURL)
        let headerHandle = try FileHandle(forReadingFrom: coldURL)
        let coldHeader = try headerHandle.read(upToCount: 20) ?? Data()
        try headerHandle.close()
        try require(coldHeader.count == 20 && coldHeader[18] == 2 && coldHeader[19] == 2,
                    "cold fixture retains its WAL-format header")
        try require(!FileManager.default.fileExists(atPath: coldURL.path + "-wal")
                    && !FileManager.default.fileExists(atPath: coldURL.path + "-shm"),
                    "the sole cold fixture writer naturally closes without sidecars")
        let coldBytesBefore = try syntheticStoreBytes(coldURL)
        let coldController = PersistenceController(storageRootForRegression: coldRoot, legacyStoreForRegression: coldURL)
        var coldReadable = false
        var coldIdentity: String?
        do {
            coldIdentity = try CoachLocalOwnership.rawCheckpoint(coldURL, phase: "Closed synthetic legacy source").identity
            coldReadable = true
        } catch {
            guard case CoachLocalOwnership.OwnershipError.unavailable(let message) = error,
                  message.contains("(SQLite 14, OS ") else { throw error }
        }
        if coldReadable {
            try await coldController.migrateForStorageRegression(interruptAfter: nil)
            let coldWorkouts = try coldController.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
            let coldRuns = try coldController.container.mainContext.fetch(FetchDescriptor<RunningSession>())
            try require(coldController.isCoachLocal && coldWorkouts.count == 1 && coldWorkouts[0].id == coldValues.workout
                        && coldRuns.count == 1 && coldRuns[0].id == coldValues.run && coldRuns[0].locations == coldValues.route,
                        "supported cold legacy migration preserves records and external asset identities")
            try require(try CoachLocalOwnership.rawCheckpoint(coldURL, phase: "Closed retained source after migration").identity == coldIdentity,
                        "supported cold migration leaves source records and assets unchanged")
            try require(try syntheticStoreBytes(coldURL) == coldBytesBefore,
                        "supported cold migration preserves original file and asset bytes")
            StartupStorageEvidence.coldSourceMigrationStatus = "supported: deterministic cold WAL fixture migrated with records and assets preserved"
        } else {
            // This is an explicit unsupported capability, not a successful
            // migration. Prove the production boundary refuses it safely;
            // successful live-WAL migrations below still run independently.
            var refused = false
            do { try await coldController.migrateForStorageRegression(interruptAfter: nil) }
            catch {
                guard case CoachLocalOwnership.OwnershipError.unavailable(let message) = error,
                      message.contains("(SQLite 14, OS ") else { throw error }
                refused = true
            }
            try require(refused && !coldController.isCoachLocal && coldController.needsLegacyMigration && coldController.storageError != nil,
                        "unsupported cold WAL remains in recovery rather than reporting migration success")
            try require(try CoachLocalOwnership.selectedStoreURL(root: coldRoot) == nil,
                        "unsupported cold WAL never selects a destination")
            try require(try syntheticStoreBytes(coldURL) == coldBytesBefore,
                        "unsupported cold WAL leaves original main file and all assets byte-identical")
            try require(!FileManager.default.fileExists(atPath: coldURL.path + "-wal")
                        && !FileManager.default.fileExists(atPath: coldURL.path + "-shm"),
                        "unsupported cold WAL does not create or remove source sidecars")
            StartupStorageEvidence.coldSourceMigrationStatus = "unsupported: read-only cold WAL returned SQLITE_CANTOPEN(14); recovery and source preservation verified, migration not completed"
        }

        return checks
    }

    private static func prepareSyntheticColdWAL(_ url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(CoachLocalOwnership.canonicalSQLiteURL(url).path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db = database else {
            if let database { sqlite3_close(database) }
            throw CoachRepositoryError.invalidValue("cold fixture could not open its new snapshot")
        }
        defer { if database != nil { sqlite3_close(database) } }
        var query: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL", -1, &query, nil)
        guard prepared == SQLITE_OK, let query else {
            if let query { sqlite3_finalize(query) }
            throw CoachRepositoryError.invalidValue("cold fixture could not set WAL mode")
        }
        guard sqlite3_step(query) == SQLITE_ROW, let mode = sqlite3_column_text(query, 0),
              String(cString: mode).lowercased() == "wal", sqlite3_step(query) == SQLITE_DONE else {
            sqlite3_finalize(query)
            throw CoachRepositoryError.invalidValue("cold fixture WAL mode was not confirmed")
        }
        sqlite3_finalize(query)
        guard sqlite3_close(db) == SQLITE_OK else {
            throw CoachRepositoryError.invalidValue("cold fixture's sole SQLite connection did not close")
        }
        database = nil
    }

    private static func syntheticStoreBytes(_ store: URL) throws -> [String: Data] {
        var result = ["main": try Data(contentsOf: store)]
        let support = store.deletingLastPathComponent().appendingPathComponent(".\(store.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        if FileManager.default.fileExists(atPath: support.path) {
            var enumerationError: Error?
            guard let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey],
                errorHandler: { _, error in enumerationError = error; return false }) else {
                throw CoachRepositoryError.invalidValue("cold fixture assets could not be enumerated")
            }
            for case let file as URL in enumerator {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    result[String(file.path.dropFirst(support.path.count))] = try Data(contentsOf: file)
                }
            }
            if let enumerationError { throw enumerationError }
        }
        return result
    }

}
#endif
