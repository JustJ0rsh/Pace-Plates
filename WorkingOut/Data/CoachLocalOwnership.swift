import Foundation
import SwiftData
import SQLite3

/// The old store remains recoverable. Only a verified copy is selected, and only
/// after the user chooses local ownership in Coach.
enum CoachLocalOwnership {
    struct Selection: Codable {
        let version: Int
        let directory: String
        let selectedAt: Date
        let legacyStorePath: String
        var migrationID: UUID? = nil
        var checkpoint: String? = nil
    }

    enum OwnershipError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self { case .unavailable(let message): return message }
        }
    }

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CoachLocalOwnership", isDirectory: true)
    }

    static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }

    static func selectedStoreURL(root: URL = CoachLocalOwnership.root) throws -> URL? {
        let marker = root.appendingPathComponent("selection.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: marker))
        guard [1, 2].contains(selection.version), UUID(uuidString: selection.directory) != nil else {
            throw OwnershipError.unavailable("The local storage selection could not be read. Your original records have been retained.")
        }
        if selection.version == 2 {
            guard let journal = try readJournal(root: root), journal.id == selection.migrationID,
                  journal.directory == selection.directory, journal.source == selection.legacyStorePath,
                  journal.checkpoint == selection.checkpoint, selection.checkpoint != nil,
                  ["verified", "active"].contains(journal.phase) else {
                throw migrationError("The selected history does not match its verified migration journal.")
            }
        }
        let directory = root.appendingPathComponent(selection.directory, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path),
           try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw migrationError("The selected storage directory is an unsupported link.")
        }
        let store = directory.appendingPathComponent("default.store")
        if FileManager.default.fileExists(atPath: store.path),
           try store.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw migrationError("The selected storage file is an unsupported link.")
        }
        return store
    }

    static func newStagingStore(root: URL = CoachLocalOwnership.root) throws -> URL {
        try prepareDirectory(root)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try prepareDirectory(directory)
        return directory.appendingPathComponent("default.store")
    }

    static func select(_ destination: URL, legacy: URL, root: URL = CoachLocalOwnership.root, journal: MigrationJournal? = nil) throws {
        let selection = Selection(version: journal == nil ? 1 : 2, directory: destination.deletingLastPathComponent().lastPathComponent,
                                  selectedAt: Date(), legacyStorePath: legacy.standardizedFileURL.path, migrationID: journal?.id, checkpoint: journal?.checkpoint)
        let data = try JSONEncoder().encode(selection)
        try data.write(to: root.appendingPathComponent("selection.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("selection.json")); defer { try? handle.close() }
        try handle.synchronize()
    }

    /// SQLite's backup API reads a consistent snapshot including live WAL
    /// content. Cold WAL-format files use a verified disposable source clone.
    static func copyStore(from source: URL, to destination: URL) throws {
        let sourceURL = canonicalSQLiteURL(source)
        let destinationURL = canonicalSQLiteURL(destination)
        guard sourceURL != destinationURL,
              ![destinationURL.path, destinationURL.path + "-wal", destinationURL.path + "-shm"].contains(where: FileManager.default.fileExists(atPath:)) else {
            throw OwnershipError.unavailable("The copy destination is not a new, unselected store. The original history is unchanged.")
        }
        try withReadableSource(sourceURL) { sourceDB in
            try copyStore(from: sourceDB, to: destinationURL)
        }
    }

    /// Shared by raw verification and backup so both use the same guarded
    /// cold-source path and never normalize the retained original.
    static func withReadableSource<T>(_ source: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        do { return try CoachSQLiteReadSnapshot.withReadOnlySource(source, body) }
        catch let error as CoachSQLiteReadSnapshot.SnapshotError {
            throw migrationError(error.localizedDescription)
        }
    }

    private static func copyStore(from sourceDB: OpaquePointer, to destination: URL) throws {
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            if let destinationDB { sqlite3_close(destinationDB) }
            throw OwnershipError.unavailable("There is not enough writable storage to prepare the local copy.")
        }
        defer { sqlite3_close(destinationDB) }
        sqlite3_busy_timeout(sourceDB, 5_000)
        sqlite3_busy_timeout(destinationDB, 5_000)
        guard let backup = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw OwnershipError.unavailable("The local copy could not be started. The original store is unchanged.")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else {
            throw OwnershipError.unavailable("The store was busy or the copy was interrupted. Retry after other activity has finished.")
        }
        // Backup preserves the source WAL header even though this new snapshot
        // has no shared-memory/WAL sidecars. Normalize only the unselected copy
        // while its sole writable connection is open. A subsequent read-only
        // verifier can then open it without creating sidecars. The source
        // remains read-only and its journaling mode is never changed.
        var modeStatement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(destinationDB, "PRAGMA journal_mode=DELETE", -1, &modeStatement, nil)
        guard prepared == SQLITE_OK, let modeStatement else {
            if let modeStatement { sqlite3_finalize(modeStatement) }
            throw OwnershipError.unavailable("The new snapshot could not be made independently readable. The original history is unchanged.")
        }
        defer { sqlite3_finalize(modeStatement) }
        guard sqlite3_step(modeStatement) == SQLITE_ROW,
              let mode = sqlite3_column_text(modeStatement, 0),
              String(cString: mode).lowercased() == "delete",
              sqlite3_step(modeStatement) == SQLITE_DONE else {
            throw OwnershipError.unavailable("The new snapshot retained an unsupported journaling mode. The original history is unchanged.")
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: destination.path)
    }

    /// Resolve the existing parent without asking Foundation to resolve a
    /// not-yet-created database tail. All connections use the same WAL name.
    static func canonicalSQLiteURL(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent).standardizedFileURL
    }

    @MainActor
    static func identityInventory(_ context: ModelContext) throws -> [String: [UUID]] {
        var inventory: [String: [UUID]] = [:]
        inventory["exercises"] = try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.id)
        inventory["workouts"] = try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id)
        inventory["sets"] = try context.fetch(FetchDescriptor<ExerciseLog>()).map(\.id)
        inventory["runs"] = try context.fetch(FetchDescriptor<RunningSession>()).map(\.id)
        inventory["runningPlans"] = try context.fetch(FetchDescriptor<RunningPlan>()).map(\.id)
        inventory["runningPlanSessions"] = try context.fetch(FetchDescriptor<RunningPlanSession>()).map(\.id)
        inventory["plans"] = try context.fetch(FetchDescriptor<TrainingPlan>()).map(\.id)
        inventory["plannedSessions"] = try context.fetch(FetchDescriptor<PlannedSession>()).map(\.id)
        inventory["weights"] = try context.fetch(FetchDescriptor<WeightEntry>()).map(\.id)
        inventory["conversations"] = try context.fetch(FetchDescriptor<AIConversation>()).map(\.id)
        inventory["templates"] = try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id)
        inventory["templateExercises"] = try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id)
        inventory["healthInbox"] = try context.fetch(FetchDescriptor<HealthWorkoutInboxItem>()).map(\.id)
        inventory["cardioInbox"] = try context.fetch(FetchDescriptor<CardioWorkoutInboxItem>()).map(\.id)
        return inventory.mapValues { $0.sorted { $0.uuidString < $1.uuidString } }
    }

}
