import Foundation
import SwiftData
import Synchronization

/// An explicit way to keep logging when older storage cannot open. The selected
/// store persists across launches; recovery never silently switches it back.
@MainActor
enum LocalHistoryContinuation {
    private struct Selection: Codable {
        let version: Int
        let directory: UUID
        let storeIdentifier: String
    }

    private nonisolated static let activePaths = Mutex<(directory: URL?, recovery: RunRecoveryStore?)>((nil, nil))
    nonisolated static var activeDirectory: URL? { activePaths.withLock { $0.directory } }
    nonisolated static var runRecoveryStore: RunRecoveryStore? { activePaths.withLock { $0.recovery } }
    static let notice = "Some older history is unavailable. New entries are saved on this device in separate local history. Your original files are kept. Export a backup before recovering or combining older history."

    private static func folder(_ root: URL) -> URL {
        root.appendingPathComponent("ContinuedHistory", isDirectory: true)
    }

    private static func requireRegular(_ url: URL, directory: Bool = false) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true,
              (directory ? values.isDirectory == true : values.isRegularFile == true) else {
            throw CoachLocalOwnership.migrationError("The continued local history could not be opened safely. Its files were kept.")
        }
    }

    static func selectedStoreURL(root: URL) throws -> URL? {
        let manager = FileManager.default
        let directory = folder(root)
        guard manager.fileExists(atPath: directory.path) else { return nil }
        try requireRegular(root, directory: true)
        try requireRegular(directory, directory: true)
        let marker = directory.appendingPathComponent("selection.json")
        guard manager.fileExists(atPath: marker.path) else { return nil }
        try requireRegular(marker)
        let selection = try JSONDecoder().decode(Selection.self, from: Data(contentsOf: marker))
        guard selection.version == 1 else {
            throw CoachLocalOwnership.migrationError("The continued local history selection could not be read. Its files were kept.")
        }
        let selected = directory.appendingPathComponent(selection.directory.uuidString, isDirectory: true)
        try requireRegular(selected, directory: true)
        let store = selected.appendingPathComponent("default.store")
        try requireRegular(store)
        guard try CoachLocalOwnership.persistentStoreID(at: store) == selection.storeIdentifier else {
            throw CoachLocalOwnership.migrationError("The continued local history has a different storage identity. Its files were kept.")
        }
        return store
    }

    static func create(root: URL, opening: (URL) throws -> ModelContainer) throws -> (ModelContainer, URL) {
        if let selected = try selectedStoreURL(root: root) { return (try opening(selected), selected) }
        let directory = folder(root)
        try CoachLocalOwnership.prepareDirectory(root)
        try requireRegular(root, directory: true)
        try CoachLocalOwnership.prepareDirectory(directory)
        try requireRegular(directory, directory: true)
        let id = UUID()
        let selected = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(selected)
        let url = selected.appendingPathComponent("default.store")
        let container = try opening(url)
        try container.mainContext.save()
        let marker = directory.appendingPathComponent("selection.json")
        let selection = Selection(version: 1, directory: id,
                                  storeIdentifier: try CoachLocalOwnership.persistentStoreID(at: url))
        // No normal app views are released until this durable selection succeeds.
        try JSONEncoder().encode(selection).write(to: marker, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return (container, url)
    }

    static func activate(storeURL: URL?) {
        let directory = storeURL?.deletingLastPathComponent()
        let recovery = directory.map { RunRecoveryStore(url: $0.appendingPathComponent("ActiveRun/recovery.json")) }
        activePaths.withLock { $0 = (directory, recovery) }
    }
}
