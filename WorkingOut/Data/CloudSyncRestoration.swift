import Foundation
import SwiftData
import CoreData

/// Restores the original iCloud store without discarding history written by 2.5.
/// Only verified disposable copies are split. Both original stores are retained.
@MainActor
enum CloudSyncRestoration {
    private struct Journal: Codable {
        let version: Int
        let directory: String
        let legacyPath: String
        let sourcePath: String
        let sourceCheckpoint: String
        let legacyCheckpoint: String?
        let historyCheckpoint: String
        let coachCheckpoint: String
        var phase: String
    }

    static func makeContainer(legacyURL: URL, coachURL: URL,
                              cloudKitMode: PersistenceController.CloudKitMode) throws -> ModelContainer {
        let legacySchema = Schema(PersistenceController.legacyModelTypes)
        let coachSchema = Schema(CoachPersistence.modelTypes)
        let history = ModelConfiguration(schema: legacySchema, url: legacyURL,
                                         cloudKitDatabase: cloudKitMode == .automatic ? .automatic : .none)
        let coach = ModelConfiguration(CoachPersistence.configurationName, schema: coachSchema,
                                       url: coachURL, cloudKitDatabase: .none)
        return try ModelContainer(for: PersistenceController.coachSchema, configurations: [history, coach])
    }

    static func prepare(legacyURL: URL, ownershipRoot: URL,
                        interruptAfter: String? = nil) throws -> URL {
        let manager = FileManager.default
        let root = ownershipRoot.appendingPathComponent("iCloudRestoration", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        let journalURL = root.appendingPathComponent("restoration.json")
        let lock = try CoachLocalOwnership.MigrationLock(root: ownershipRoot)
        defer { withExtendedLifetime(lock) {} }

        var journal: Journal
        if manager.fileExists(atPath: journalURL.path) {
            journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            guard journal.version == 2, UUID(uuidString: journal.directory) != nil,
                  journal.legacyPath == legacyURL.standardizedFileURL.path,
                  ["prepared", "backingUp", "installing", "complete"].contains(journal.phase) else {
                throw failure("The iCloud recovery journal could not be verified.")
            }
        } else {
            guard let selected = try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot) else {
                // A failed/unstarted 2.5 migration must not block the old iCloud store.
                return root.appendingPathComponent("coach.store")
            }
            guard manager.fileExists(atPath: selected.path) else {
                throw failure("The history selected by version 2.5 is missing.")
            }
            let directory = UUID().uuidString
            let stage = root.appendingPathComponent(directory, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(stage)
            let fullURL = stage.appendingPathComponent("full/default.store")
            let baselineURL = stage.appendingPathComponent("baseline/default.store")
            let historyURL = stage.appendingPathComponent("history/default.store")
            let coachURL = stage.appendingPathComponent("coach/coach.store")
            let sourceCheckpoint = try CoachLocalOwnership.rawCheckpoint(selected)
            for url in [fullURL, coachURL] {
                try CoachLocalOwnership.prepareDirectory(url.deletingLastPathComponent())
                try CoachLocalOwnership.copyStore(from: selected, to: url)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: selected, to: url)
            }
            try CoachLocalOwnership.prepareDirectory(baselineURL.deletingLastPathComponent())
            try CoachLocalOwnership.prepareDirectory(historyURL.deletingLastPathComponent())
            let legacyCheckpoint = manager.fileExists(atPath: legacyURL.path)
                ? try CoachLocalOwnership.rawCheckpoint(legacyURL).identity : nil
            if legacyCheckpoint != nil {
                try CoachLocalOwnership.copyStore(from: legacyURL, to: baselineURL)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: legacyURL, to: baselineURL)
            } else {
                try autoreleasepool {
                    let schema = Schema(PersistenceController.legacyModelTypes)
                    let empty = try ModelContainer(for: schema, configurations: [
                        ModelConfiguration(schema: schema, url: baselineURL, cloudKitDatabase: .none)
                    ])
                    try empty.mainContext.save()
                }
            }
            try CoachLocalOwnership.copyStore(from: baselineURL, to: historyURL)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: baselineURL, to: historyURL)
            // A recorded baseline is required to interpret absence as a deletion.
            // Older selections retain ambiguous cloud-only rows instead of deleting them.
            let selection = try JSONDecoder().decode(CoachLocalOwnership.Selection.self,
                from: Data(contentsOf: ownershipRoot.appendingPathComponent("selection.json")))
            let allowDeletions = selection.version == 2 && selection.checkpoint == legacyCheckpoint
            try CloudHistoryReplay.replay(baselineURL: baselineURL, localSnapshotURL: fullURL,
                                          destinationURL: historyURL, allowDeletions: allowDeletions)
            try autoreleasepool {
                let schema = Schema(CoachPersistence.modelTypes)
                let coach = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(CoachPersistence.configurationName, schema: schema,
                                       url: coachURL, cloudKitDatabase: .none)
                ])
                try coach.mainContext.save()
            }
            // The two snapshots initially share a Core Data store UUID. Give the
            // Coach copy its own identity so faults resolve to the correct store.
            var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: coachURL)
            metadata[NSStoreUUIDKey] = UUID().uuidString
            try NSPersistentStoreCoordinator.setMetadata(metadata, forPersistentStoreOfType: NSSQLiteStoreType, at: coachURL)
            try CloudHistoryReplay.verifyCoachCopy(sourceURL: fullURL, destinationURL: coachURL)
            try autoreleasepool {
                let combined = try makeContainer(legacyURL: historyURL, coachURL: coachURL, cloudKitMode: .none)
                _ = try CoachLocalOwnership.snapshotDigest(combined.mainContext)
            }
            guard try CoachLocalOwnership.rawCheckpoint(selected).identity == sourceCheckpoint.identity else {
                throw failure("The history changed while iCloud recovery was being prepared.")
            }
            journal = Journal(version: 2, directory: directory,
                              legacyPath: legacyURL.standardizedFileURL.path,
                              sourcePath: selected.standardizedFileURL.path,
                              sourceCheckpoint: sourceCheckpoint.identity,
                              legacyCheckpoint: legacyCheckpoint,
                              historyCheckpoint: try CoachLocalOwnership.rawCheckpoint(historyURL).identity,
                              coachCheckpoint: try CoachLocalOwnership.rawCheckpoint(coachURL).identity,
                              phase: "prepared")
            try write(journal, to: journalURL)
        }

        let stage = root.appendingPathComponent(journal.directory, isDirectory: true)
        let historyURL = stage.appendingPathComponent("history/default.store")
        let coachURL = stage.appendingPathComponent("coach/coach.store")
        if journal.phase == "complete" {
            guard manager.fileExists(atPath: legacyURL.path), manager.fileExists(atPath: coachURL.path) else {
                throw failure("A restored history file is missing.")
            }
            return coachURL
        }
        guard let selected = try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot),
              selected.standardizedFileURL.path == journal.sourcePath,
              try CoachLocalOwnership.rawCheckpoint(selected).identity == journal.sourceCheckpoint,
              try CoachLocalOwnership.rawCheckpoint(coachURL).identity == journal.coachCheckpoint else {
            throw failure("History changed during iCloud recovery. The retained copies need review before continuing.")
        }
        if journal.phase != "installing" {
            guard try CoachLocalOwnership.rawCheckpoint(historyURL).identity == journal.historyCheckpoint else {
                throw failure("The staged history changed during iCloud recovery.")
            }
        }
        if interruptAfter == "prepared", journal.phase == "prepared" { throw failure("Synthetic interruption after preparation.") }

        if journal.phase == "prepared" {
            let currentLegacy = manager.fileExists(atPath: legacyURL.path)
                ? try CoachLocalOwnership.rawCheckpoint(legacyURL).identity : nil
            guard currentLegacy == journal.legacyCheckpoint else {
                throw failure("The original iCloud history changed while recovery was being prepared.")
            }
            journal.phase = "backingUp"
            try write(journal, to: journalURL)
        }
        if journal.phase == "backingUp" {
            let retainedURL = stage.appendingPathComponent("retained-icloud/default.store")
            try CoachLocalOwnership.prepareDirectory(retainedURL.deletingLastPathComponent())
            try moveBundle(from: legacyURL, to: retainedURL, allowExistingDestination: false)
            journal.phase = "installing"
            try write(journal, to: journalURL)
        }
        if interruptAfter == "backedUp", journal.phase == "installing" { throw failure("Synthetic interruption after retaining iCloud history.") }

        if journal.phase == "installing" {
            try manager.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try moveBundle(from: historyURL, to: legacyURL, allowExistingDestination: true)
            guard manager.fileExists(atPath: legacyURL.path), manager.fileExists(atPath: coachURL.path) else {
                throw failure("The restored history files could not be installed.")
            }
            guard try CoachLocalOwnership.rawCheckpoint(legacyURL).identity == journal.historyCheckpoint else {
                throw failure("The installed history did not match the verified copy.")
            }
            if interruptAfter == "installed" { throw failure("Synthetic interruption after installation.") }
            journal.phase = "complete"
            try write(journal, to: journalURL)
        }
        return coachURL
    }

    private static func bundleFiles(_ url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm"),
         url.deletingLastPathComponent().appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)_SUPPORT")]
    }

    private static func moveBundle(from source: URL, to destination: URL,
                                   allowExistingDestination: Bool) throws {
        let manager = FileManager.default
        for (from, to) in zip(bundleFiles(source), bundleFiles(destination)) {
            guard manager.fileExists(atPath: from.path) else { continue }
            guard !manager.fileExists(atPath: to.path) else {
                throw failure(allowExistingDestination
                              ? "The restored store destination is unexpectedly occupied."
                              : "Both a retained store file and its original are present.")
            }
            let attributes = try from.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard attributes.isSymbolicLink != true else { throw failure("A history file is an unsupported link.") }
            try manager.moveItem(at: from, to: to)
        }
    }

    private static func write(_ journal: Journal, to url: URL) throws {
        try JSONEncoder().encode(journal).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }

    private static func failure(_ message: String) -> CoachLocalOwnership.OwnershipError {
        .unavailable(message + " Your original files are retained. Close and reopen the app to retry.")
    }
}
