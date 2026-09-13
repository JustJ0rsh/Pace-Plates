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

    static func selectedStoreURL() throws -> URL? {
        let marker = root.appendingPathComponent("selection.json")
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: marker))
        guard selection.version == 1, UUID(uuidString: selection.directory) != nil else {
            throw OwnershipError.unavailable("The local storage selection could not be read. Your original records have been retained.")
        }
        return root.appendingPathComponent(selection.directory, isDirectory: true).appendingPathComponent("default.store")
    }

    static func newStagingStore() throws -> URL {
        try prepareDirectory(root)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try prepareDirectory(directory)
        return directory.appendingPathComponent("default.store")
    }

    static func select(_ destination: URL, legacy: URL) throws {
        let selection = Selection(version: 1, directory: destination.deletingLastPathComponent().lastPathComponent,
                                  selectedAt: Date(), legacyStorePath: legacy.path)
        let data = try JSONEncoder().encode(selection)
        try data.write(to: root.appendingPathComponent("selection.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// SQLite's backup API reads a consistent snapshot including WAL content;
    /// copying the main SQLite file alone can lose recently saved records.
    static func copyStore(from source: URL, to destination: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?
        guard sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let sourceDB { sqlite3_close(sourceDB) }
            throw OwnershipError.unavailable("The original store could not be opened for a read-only copy.")
        }
        defer { sqlite3_close(sourceDB) }
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
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                             ofItemAtPath: destination.path)
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
