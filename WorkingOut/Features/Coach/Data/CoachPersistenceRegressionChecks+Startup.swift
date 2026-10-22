#if DEBUG
import Foundation
import SwiftData

extension CoachPersistenceRegressionChecks {
    /// Executes the real startup/migration implementation using only disposable
    /// legacy fixtures. Never resolves an application or CloudKit store URL.
    @MainActor static func runStartupCases(root: URL) async throws -> Int {
        var checks = 0
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
        return checks
    }
}
#endif
