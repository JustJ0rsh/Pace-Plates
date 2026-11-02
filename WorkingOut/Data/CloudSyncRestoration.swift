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
        var ownershipPath: String? = nil
        var historyStoreID: String? = nil
        var coachStoreID: String? = nil
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

    /// A finished install can open immediately. Anything else still has file
    /// work to do and should keep the startup gate up.
    static func isReady(legacyURL: URL, ownershipRoot: URL) -> Bool {
        let root = ownershipRoot.appendingPathComponent("iCloudRestoration", isDirectory: true)
        let journalURL = root.appendingPathComponent("restoration.json")
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(Journal.self, from: data),
              journal.version == 2, journal.phase == "complete",
              UUID(uuidString: journal.directory) != nil else { return false }
        let stage = root.appendingPathComponent(journal.directory, isDirectory: true)
        let coachURL = stage.appendingPathComponent("coach/coach.store")
        guard FileManager.default.fileExists(atPath: legacyURL.path),
              FileManager.default.fileExists(atPath: coachURL.path) else { return false }
        guard let expectedHistoryID = try? journal.historyStoreID
                ?? CoachLocalOwnership.persistentStoreID(at: stage.appendingPathComponent("baseline/default.store")),
              (try? CoachLocalOwnership.persistentStoreID(at: legacyURL)) == expectedHistoryID else { return false }
        if let expectedCoachID = journal.coachStoreID {
            guard (try? CoachLocalOwnership.persistentStoreID(at: coachURL)) == expectedCoachID else { return false }
        }
        return true
    }

    static let unverifiedJournalNotice = "iCloud recovery records could not be verified. Your history on this phone is open, and the original files were kept."

    /// The journal cannot be read or fails its format check, and the history file
    /// already on this phone is a regular store. A relaunch cannot repair that
    /// journal. In-progress installs, location mismatches, and identity mismatches
    /// stay on the strict path.
    static func opensDespiteUnverifiedJournal(legacyURL: URL, ownershipRoot: URL) -> Bool {
        let journalURL = ownershipRoot
            .appendingPathComponent("iCloudRestoration", isDirectory: true)
            .appendingPathComponent("restoration.json")
        guard case .untrusted = classifyJournal(at: journalURL) else { return false }
        return readableStore(legacyURL)
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
        switch classifyJournal(at: journalURL) {
        case .untrusted(let decoded):
            // Reopening retries this same check, so it cannot clear the screen.
            // Open the history file already on this phone and leave the journal as it is.
            guard readableStore(legacyURL) else {
                throw failure("The iCloud recovery journal could not be verified.")
            }
            return try coachStoreForUnverifiedJournal(decoded, root: root)
        case .trusted(let existing):
            journal = existing
            if journal.legacyPath != legacyURL.standardizedFileURL.path {
                guard let recordedRoot = recordedOwnershipRoot(journal),
                      CoachLocalOwnership.sameRelocatedLegacyStore(legacyURL, root: ownershipRoot,
                          recordedPath: journal.legacyPath, recordedRoot: recordedRoot) else {
                    throw failure("The iCloud recovery journal does not identify this history location.")
                }
            }
        case .absent:
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
                try prepareClosedLocalStore(at: baselineURL, modelTypes: PersistenceController.legacyModelTypes)
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
            try prepareClosedLocalStore(at: coachURL, modelTypes: CoachPersistence.modelTypes)
            // The two snapshots initially share a Core Data store UUID. Give the
            // Coach copy its own identity so faults resolve to the correct store.
            var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: coachURL)
            metadata[NSStoreUUIDKey] = UUID().uuidString
            try NSPersistentStoreCoordinator.setMetadata(metadata, forPersistentStoreOfType: NSSQLiteStoreType, at: coachURL)
            try CloudHistoryReplay.verifyCoachCopy(sourceURL: fullURL, destinationURL: coachURL)
            // Replay validates every legacy value, relationship and export
            // transaction; verifyCoachCopy validates the separate Coach graph.
            // The groups have no cross-store relationships. A SwiftData probe
            // here can retain open SQLite handles past an autoreleasepool, so
            // the combined container is opened only after installation.
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
                              phase: "prepared", ownershipPath: ownershipRoot.standardizedFileURL.path,
                              historyStoreID: try CoachLocalOwnership.persistentStoreID(at: historyURL),
                              coachStoreID: try CoachLocalOwnership.persistentStoreID(at: coachURL))
            try write(journal, to: journalURL)
        }

        let stage = root.appendingPathComponent(journal.directory, isDirectory: true)
        let historyURL = stage.appendingPathComponent("history/default.store")
        let coachURL = stage.appendingPathComponent("coach/coach.store")
        if journal.phase == "complete" {
            guard manager.fileExists(atPath: legacyURL.path), manager.fileExists(atPath: coachURL.path) else {
                throw failure("A restored history file is missing.")
            }
            // Records may have changed after completion, so bind later launches
            // to stable store identities rather than a stale content checkpoint.
            // Older journals retain the baseline from which history was copied.
            let expectedHistoryID = try journal.historyStoreID
                ?? CoachLocalOwnership.persistentStoreID(at: stage.appendingPathComponent("baseline/default.store"))
            guard try CoachLocalOwnership.persistentStoreID(at: legacyURL) == expectedHistoryID else {
                throw failure("The restored history has a different storage identity.")
            }
            if let expectedCoachID = journal.coachStoreID {
                guard try CoachLocalOwnership.persistentStoreID(at: coachURL) == expectedCoachID else {
                    throw failure("The restored Coach history has a different storage identity.")
                }
            }
            if journal.historyStoreID == nil || journal.coachStoreID == nil {
                journal.historyStoreID = expectedHistoryID
                journal.coachStoreID = try CoachLocalOwnership.persistentStoreID(at: coachURL)
                try write(journal, to: journalURL)
            }
            return coachURL
        }
        guard let selected = try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot),
              sameSelectedStore(selected, recordedPath: journal.sourcePath),
              try CoachLocalOwnership.matchesCheckpoint(journal.sourceCheckpoint, at: selected),
              try CoachLocalOwnership.matchesCheckpoint(journal.coachCheckpoint, at: coachURL) else {
            throw failure("History changed during iCloud recovery. The retained copies need review before continuing.")
        }
        if journal.phase != "installing" {
            guard try CoachLocalOwnership.matchesCheckpoint(journal.historyCheckpoint, at: historyURL) else {
                throw failure("The staged history changed during iCloud recovery.")
            }
        }
        if interruptAfter == "prepared", journal.phase == "prepared" { throw failure("Synthetic interruption after preparation.") }

        if journal.phase == "prepared" {
            let legacyExists = manager.fileExists(atPath: legacyURL.path)
            let legacyMatches: Bool
            if let checkpoint = journal.legacyCheckpoint {
                if legacyExists {
                    legacyMatches = try CoachLocalOwnership.matchesCheckpoint(checkpoint, at: legacyURL)
                } else {
                    legacyMatches = false
                }
            } else {
                legacyMatches = !legacyExists
            }
            guard legacyMatches else {
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
            guard try CoachLocalOwnership.matchesCheckpoint(journal.historyCheckpoint, at: legacyURL) else {
                throw failure("The installed history did not match the verified copy.")
            }
            if interruptAfter == "installed" { throw failure("Synthetic interruption after installation.") }
            journal.phase = "complete"
            try write(journal, to: journalURL)
        }
        return coachURL
    }

    private enum JournalClassification {
        case absent
        case trusted(Journal)
        case untrusted(Journal?)
    }

    private static func classifyJournal(at journalURL: URL) -> JournalClassification {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return .absent }
        guard let data = try? Data(contentsOf: journalURL),
              let journal = try? JSONDecoder().decode(Journal.self, from: data) else { return .untrusted(nil) }
        guard journal.version == 2, UUID(uuidString: journal.directory) != nil,
              ["prepared", "backingUp", "installing", "complete"].contains(journal.phase) else {
            return .untrusted(journal)
        }
        return .trusted(journal)
    }

    /// Metadata only. A link, a missing file, or an unreadable store stays closed.
    private static func readableStore(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return (try? CoachLocalOwnership.persistentStoreID(at: url)) != nil
    }

    /// Prefer the staged Coach file when its directory is a real UUID and that file
    /// opens. Otherwise create the local Coach file beside the journal. Never move
    /// or replace the history file, and never rewrite the journal.
    private static func coachStoreForUnverifiedJournal(_ journal: Journal?, root: URL) throws -> URL {
        if let directory = journal?.directory, UUID(uuidString: directory) != nil,
           !directory.contains("/"), directory != ".", directory != ".." {
            let staged = root.appendingPathComponent(directory, isDirectory: true)
                .appendingPathComponent("coach", isDirectory: true)
                .appendingPathComponent("coach.store")
            if readableStore(staged) { return staged }
        }
        let coachURL = root.appendingPathComponent("coach.store")
        if readableStore(coachURL) { return coachURL }
        if FileManager.default.fileExists(atPath: coachURL.path) {
            let values = try coachURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw failure("A history file is an unsupported link.") }
            throw failure("The iCloud recovery journal could not be verified.")
        }
        try prepareClosedLocalStore(at: coachURL, modelTypes: CoachPersistence.modelTypes)
        guard readableStore(coachURL) else {
            throw failure("The iCloud recovery journal could not be verified.")
        }
        return coachURL
    }

    private static func recordedOwnershipRoot(_ journal: Journal) -> String? {
        guard journal.sourcePath.hasPrefix("/") else { return nil }
        let selected = URL(fileURLWithPath: journal.sourcePath).standardizedFileURL
        guard selected.lastPathComponent == "default.store",
              UUID(uuidString: selected.deletingLastPathComponent().lastPathComponent) != nil else { return nil }
        let inferred = selected.deletingLastPathComponent().deletingLastPathComponent().path
        guard journal.ownershipPath == nil || journal.ownershipPath == inferred else { return nil }
        return inferred
    }

    /// iOS can replace the app-data container directory during an update. The
    /// app-owned selection UUID and file name persist; checkpoints below still
    /// verify the complete database and assets before resuming installation.
    private static func sameSelectedStore(_ selected: URL, recordedPath: String) -> Bool {
        guard recordedPath.hasPrefix("/") else { return false }
        let recorded = URL(fileURLWithPath: recordedPath).standardizedFileURL
        guard selected.lastPathComponent == "default.store", recorded.lastPathComponent == "default.store",
              let selectedID = UUID(uuidString: selected.deletingLastPathComponent().lastPathComponent),
              let recordedID = UUID(uuidString: recorded.deletingLastPathComponent().lastPathComponent) else {
            return false
        }
        return selectedID == recordedID
    }

    /// Schema creation/reduction must finish with an explicitly detached store
    /// before its metadata is changed or its files are moved into place.
    private static func prepareClosedLocalStore(at url: URL, modelTypes: [any PersistentModel.Type]) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
            throw failure("The local recovery model could not be prepared.")
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSPersistentHistoryTrackingKey: true,
                      NSMigratePersistentStoresAutomaticallyOption: true,
                      NSInferMappingModelAutomaticallyOption: true])
        try coordinator.remove(store)
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
