import Foundation
#if canImport(os)
import os
#endif

/// Minimal atomic JSON-file persistence for small Codable state blobs, such as
/// the active-run draft and the cached weather summary.
///
/// Values are written atomically so a crash mid-write can never leave a
/// half-written file, and unreadable payloads are discarded on load so one bad
/// write cannot wedge every future launch.
///
/// This type deliberately depends only on Foundation so the stores built on it
/// can be exercised with the open-source Swift toolchain (see the standalone
/// tests under `scripts/`). It is not thread-safe; callers use it from the
/// main thread.
final class CodableFileStore<Value: Codable> {
    let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// Store named `<name>.json` inside the default app-state directory.
    convenience init(name: String, fileManager: FileManager = .default) {
        let directory = Self.defaultDirectory(fileManager: fileManager)
        self.init(
            fileURL: directory.appendingPathComponent("\(name).json"),
            fileManager: fileManager
        )
    }

    /// `Application Support/AppState/`, created on demand by `save`.
    static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("AppState", isDirectory: true)
    }

    func save(_ value: Value) {
        do {
            let data = try encoder.encode(value)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            log("Failed to save \(fileURL.lastPathComponent): \(error)")
        }
    }

    func load() -> Value? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(Value.self, from: data)
        } catch {
            log("Discarding unreadable \(fileURL.lastPathComponent): \(error)")
            clear()
            return nil
        }
    }

    func clear() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            log("Failed to clear \(fileURL.lastPathComponent): \(error)")
        }
    }

    private func log(_ message: String) {
        #if canImport(os)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.paceandplates", category: "fileStore")
            .error("\(message, privacy: .public)")
        #else
        FileHandle.standardError.write(Data("[CodableFileStore] \(message)\n".utf8))
        #endif
    }
}
