import Foundation
import CryptoKit

/// A deliberately simple, uncompressed stream: magic, manifest byte count,
/// manifest, bounded record JSON, then declared image bytes in manifest order.
/// There are no directory, link, or executable entries in this format.
enum CoachHistoryArchive {
    static let magic = Data("PACECOACH5\n".utf8)
    static let maxRecords = 64 * 1_024 * 1_024
    static let maxAsset = 25 * 1_024 * 1_024
    static let maxEntries = 10_000
    static let maxTotal: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maxManifest = 4 * 1_024 * 1_024
    static var restoreDirectory: URL { CoachPersistence.directory.appendingPathComponent("RestoreStaging", isDirectory: true) }

    struct Entry: Codable, Sendable {
        let path: String
        let bytes: Int
        let digest: String
    }
    struct Manifest: Codable, Sendable {
        let format: String
        let version: Int
        let photosIncluded: Bool
        let records: Entry
        let assets: [Entry]
    }
    struct Journal: Codable, Sendable {
        let id: UUID
        let manifest: Manifest
        var state: String
    }
    enum ArchiveError: LocalizedError {
        case invalid(String), exceedsLimit(String), missingAsset(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let reason): return "The backup is invalid: \(reason). No records were restored."
            case .exceedsLimit(let reason): return "This backup exceeds the \(reason) limit. Choose export without photos if needed."
            case .missingAsset(let key): return "The backup photo \(key) is missing or damaged. A full restore requires every referenced photo."
            }
        }
    }

    static func export(_ file: BackupFile, includePhotos: Bool) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let records = try encoder.encode(file)
        guard records.count <= maxRecords else { throw ArchiveError.exceedsLimit("64 MiB record JSON") }
        let photos = file.coach?.photos ?? []
        guard photos.count + 1 <= maxEntries else { throw ArchiveError.exceedsLimit("10,000 entries") }
        var entries: [Entry] = []
        var total = Int64(records.count)
        for photo in photos {
            let url = try CoachPhotoStore.assetURL(for: photo.assetKey)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let count = values.fileSize,
                  count == photo.byteCount, count <= maxAsset else { throw ArchiveError.missingAsset(photo.assetKey) }
            let digest = try digestFile(url, expectedBytes: count)
            guard digest == photo.digest else { throw ArchiveError.missingAsset(photo.assetKey) }
            entries.append(Entry(path: "photos/\(photo.assetKey)", bytes: count, digest: digest))
            total += Int64(count)
            guard total <= maxTotal else { throw ArchiveError.exceedsLimit("2 GiB archive") }
        }
        let manifest = Manifest(format: "pace-and-plates.history", version: 5, photosIncluded: includePhotos,
                                records: Entry(path: "records.json", bytes: records.count, digest: CoachPhotoStore.digest(records)), assets: entries)
        let manifestData = try encoder.encode(manifest)
        guard manifestData.count <= maxManifest else { throw ArchiveError.exceedsLimit("manifest size") }
        guard total + Int64(manifestData.count + magic.count + 8) <= maxTotal else { throw ArchiveError.exceedsLimit("2 GiB complete archive") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pace&Plates-Backup-\(UUID().uuidString).pacebackup")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url)
        do {
            try output.write(contentsOf: magic)
            var length = UInt64(manifestData.count).bigEndian
            try withUnsafeBytes(of: &length) { try output.write(contentsOf: Data($0)) }
            try output.write(contentsOf: manifestData); try output.write(contentsOf: records)
            for entry in entries {
                let key = String(entry.path.dropFirst("photos/".count))
                try stream(from: CoachPhotoStore.assetURL(for: key), to: output, expectedBytes: entry.bytes, expectedDigest: entry.digest)
            }
            try output.synchronize(); try output.close(); try CoachPersistence.protect(url)
            return url
        } catch { try? output.close(); try? FileManager.default.removeItem(at: url); throw error }
    }

    static func prepareImport(from url: URL) throws -> CoachPreparedRestore {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ArchiveError.invalid("Expected a regular backup file") }
        if let count = values.fileSize, Int64(count) > maxTotal { throw ArchiveError.exceedsLimit("2 GiB input") }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        let prefix = try input.read(upToCount: magic.count) ?? Data()
        if prefix != magic {
            try input.seek(toOffset: 0)
            let records = try readBounded(input, limit: maxRecords)
            let file = try JSONDecoder().decode(BackupFile.self, from: records)
            guard file.coach?.photos.isEmpty != false else { throw ArchiveError.invalid("Photo records require an archive with image assets") }
            return CoachPreparedRestore(file: file, directory: nil, manifest: nil)
        }
        let lengthData = try readExactly(input, count: 8)
        let length = lengthData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length > 0 && length <= UInt64(maxManifest) else { throw ArchiveError.exceedsLimit("manifest size") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: readExactly(input, count: Int(length)))
        try validate(manifest)
        let id = UUID(); let stage = restoreDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try CoachPersistence.protect(stage, isDirectory: true)
        do {
            let records = try readExactly(input, count: manifest.records.bytes)
            guard CoachPhotoStore.digest(records) == manifest.records.digest else { throw ArchiveError.invalid("Record digest does not match") }
            let file = try JSONDecoder().decode(BackupFile.self, from: records)
            try file.coach?.validate()
            let photos = file.coach?.photos ?? []
            guard Set(photos.map { "photos/\($0.assetKey)" }) == Set(manifest.assets.map(\.path)), manifest.photosIncluded || photos.isEmpty else { throw ArchiveError.invalid("Photo manifest does not match records") }
            for photo in photos {
                guard let entry = manifest.assets.first(where: { $0.path == "photos/\(photo.assetKey)" }), entry.bytes == photo.byteCount, entry.digest == photo.digest else { throw ArchiveError.missingAsset(photo.assetKey) }
            }
            try records.write(to: stage.appendingPathComponent("records.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            var total = Int64(records.count) + Int64(length) + Int64(magic.count + 8)
            for entry in manifest.assets {
                let key = String(entry.path.dropFirst("photos/".count)); let destination = stage.appendingPathComponent(key)
                try copyExactly(input: input, to: destination, entry: entry)
                try CoachPhotoStore.verifyRetainedFile(destination)
                total += Int64(entry.bytes); guard total <= maxTotal else { throw ArchiveError.exceedsLimit("2 GiB expanded bytes") }
            }
            guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw ArchiveError.invalid("Unexpected trailing archive entries") }
            // Until the database commit is durable, a relaunch rolls back
            // copied assets that have no committed metadata. If the save already
            // succeeded, the reference check retains those assets instead.
            let journal = Journal(id: id, manifest: manifest, state: "rollback")
            try JSONEncoder().encode(journal).write(to: stage.appendingPathComponent("journal.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
            return CoachPreparedRestore(file: file, directory: stage, manifest: manifest)
        } catch { try? FileManager.default.removeItem(at: stage); throw error }
    }

    static func pendingRestores() throws -> [CoachPreparedRestore] {
        guard FileManager.default.fileExists(atPath: restoreDirectory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: restoreDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var result: [CoachPreparedRestore] = []
        for folder in folders {
            guard UUID(uuidString: folder.lastPathComponent) != nil else { continue }
            let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw ArchiveError.invalid("Unexpected restore staging item") }
            let journalURL = folder.appendingPathComponent("journal.json")
            // An interrupted extraction has not installed files or touched the database.
            guard FileManager.default.fileExists(atPath: journalURL.path) else { try FileManager.default.removeItem(at: folder); continue }
            let journal = try JSONDecoder().decode(Journal.self, from: boundedFile(journalURL, limit: maxManifest))
            try validate(journal.manifest)
            let records = try boundedFile(folder.appendingPathComponent("records.json"), limit: maxRecords)
            guard CoachPhotoStore.digest(records) == journal.manifest.records.digest else { throw ArchiveError.invalid("Pending restore records are damaged") }
            let file = try JSONDecoder().decode(BackupFile.self, from: records)
            try file.coach?.validate()
            for entry in journal.manifest.assets {
                let key = String(entry.path.dropFirst("photos/".count))
                guard try digestFile(folder.appendingPathComponent(key), expectedBytes: entry.bytes) == entry.digest else { throw ArchiveError.missingAsset(key) }
            }
            guard ["validated", "rollback"].contains(journal.state) else { throw ArchiveError.invalid("Unknown restore journal state") }
            result.append(CoachPreparedRestore(file: file, directory: folder, manifest: journal.manifest, rollbackOnly: journal.state == "rollback"))
        }
        return result
    }

    private static func validate(_ manifest: Manifest) throws {
        guard manifest.format == "pace-and-plates.history", manifest.version == 5,
              manifest.records.path == "records.json", manifest.records.bytes > 0,
              manifest.records.bytes <= maxRecords, manifest.assets.count + 1 <= maxEntries,
              Set(manifest.assets.map(\.path)).count == manifest.assets.count else { throw ArchiveError.invalid("Unsupported or duplicate manifest entries") }
        var total = Int64(manifest.records.bytes)
        for entry in manifest.assets {
            guard entry.path.hasPrefix("photos/"), CoachPhotoStore.isSafeAssetKey(String(entry.path.dropFirst(7))),
                  entry.bytes > 0, entry.bytes <= maxAsset, entry.digest.count == 64,
                  entry.digest.allSatisfy({ $0.isHexDigit }) else { throw ArchiveError.invalid("Unsafe asset path, size, or digest") }
            total += Int64(entry.bytes)
            guard total <= maxTotal else { throw ArchiveError.exceedsLimit("2 GiB expanded bytes") }
        }
    }

    private static func readExactly(_ file: FileHandle, count: Int) throws -> Data {
        var data = Data(); data.reserveCapacity(count)
        while data.count < count {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(1_048_576, count - data.count)) ?? Data()
            guard !chunk.isEmpty else { throw ArchiveError.invalid("Truncated data") }; data.append(chunk)
        }
        return data
    }
    private static func readBounded(_ file: FileHandle, limit: Int) throws -> Data {
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount: min(1_048_576, limit - data.count + 1)) ?? Data()
            if chunk.isEmpty { return data }
            guard data.count + chunk.count <= limit else { throw ArchiveError.exceedsLimit("64 MiB record JSON") }; data.append(chunk)
        }
    }
    private static func boundedFile(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ArchiveError.invalid("Unsafe staging file") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        return try readBounded(handle, limit: limit)
    }
    static func digestFile(_ url: URL, expectedBytes: Int) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == expectedBytes else { throw ArchiveError.missingAsset(url.lastPathComponent) }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hash = SHA256(); var read = 0
        while read < expectedBytes {
            let chunk = try readExactly(input, count: min(1_048_576, expectedBytes - read)); hash.update(data: chunk); read += chunk.count
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw ArchiveError.invalid("Asset grew while reading") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func stream(from url: URL, to output: FileHandle, expectedBytes: Int, expectedDigest: String) throws {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hash = SHA256(); var read = 0
        while read < expectedBytes {
            let chunk = try readExactly(input, count: min(1_048_576, expectedBytes - read)); hash.update(data: chunk); try output.write(contentsOf: chunk); read += chunk.count
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expectedDigest, (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw ArchiveError.missingAsset(url.lastPathComponent) }
    }
    private static func copyExactly(input: FileHandle, to url: URL, entry: Entry) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        var hash = SHA256(); var read = 0
        while read < entry.bytes {
            let chunk = try readExactly(input, count: min(1_048_576, entry.bytes - read)); hash.update(data: chunk); try output.write(contentsOf: chunk); read += chunk.count
        }
        try output.synchronize()
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == entry.digest else { throw ArchiveError.missingAsset(entry.path) }
        try CoachPersistence.protect(url)
    }
}

struct CoachPreparedRestore: Sendable {
    let file: BackupFile
    let directory: URL?
    let manifest: CoachHistoryArchive.Manifest?
    var rollbackOnly: Bool = false

    func markForRollback() throws {
        guard let directory, let manifest, let id = UUID(uuidString: directory.lastPathComponent),
              FileManager.default.fileExists(atPath: directory.path) else { return }
        let journal = CoachHistoryArchive.Journal(id: id, manifest: manifest, state: "rollback")
        try JSONEncoder().encode(journal).write(to: directory.appendingPathComponent("journal.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    /// Keep files referenced by already-committed records, including a prior
    /// completed restore. A failed import owns only unreferenced copied assets.
    func rollbackAssets(keeping referencedKeys: Set<String>) throws {
        guard let manifest else { return }
        for entry in manifest.assets {
            let key = String(entry.path.dropFirst("photos/".count))
            if let temporary = installationURL(for: key), FileManager.default.fileExists(atPath: temporary.path) {
                try FileManager.default.removeItem(at: temporary)
            }
            guard !referencedKeys.contains(key) else { continue }
            let destination = try CoachPhotoStore.assetURL(for: key)
            if FileManager.default.fileExists(atPath: destination.path) {
                // Never remove an unrelated pre-existing collision with other content.
                if (try? CoachHistoryArchive.digestFile(destination, expectedBytes: entry.bytes)) == entry.digest {
                    try FileManager.default.removeItem(at: destination)
                }
            }
        }
    }

    func installAssets() throws {
        guard let directory, let manifest else { return }
        try CoachPersistence.protect(CoachPhotoStore.directory, isDirectory: true)
        for entry in manifest.assets {
            let key = String(entry.path.dropFirst("photos/".count)); let destination = try CoachPhotoStore.assetURL(for: key)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try CoachHistoryArchive.digestFile(destination, expectedBytes: entry.bytes) == entry.digest else { throw CoachHistoryArchive.ArchiveError.invalid("An existing photo has different content") }
            } else {
                let staged = directory.appendingPathComponent(key)
                guard try CoachHistoryArchive.digestFile(staged, expectedBytes: entry.bytes) == entry.digest else { throw CoachHistoryArchive.ArchiveError.missingAsset(key) }
                guard let temporary = installationURL(for: key) else { throw CoachHistoryArchive.ArchiveError.invalid("Missing restore identity") }
                do {
                    if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: staged, to: temporary)
                    try CoachPersistence.protect(temporary)
                    guard try CoachHistoryArchive.digestFile(temporary, expectedBytes: entry.bytes) == entry.digest else { throw CoachHistoryArchive.ArchiveError.missingAsset(key) }
                    // Rename a verified complete file on the same volume. Failed
                    // copies cannot leave a truncated final asset blocking retries.
                    try FileManager.default.moveItem(at: temporary, to: destination)
                } catch { try? FileManager.default.removeItem(at: temporary); throw error }
            }
        }
    }

    func installationURL(for key: String) -> URL? {
        guard let directory, let id = UUID(uuidString: directory.lastPathComponent), CoachPhotoStore.isSafeAssetKey(key) else { return nil }
        return CoachPhotoStore.directory.appendingPathComponent(".restore-\(id.uuidString)-\(key).partial")
    }

    /// After an atomic database save, replaying a retained journal is harmless:
    /// all records and assets have stable IDs and are restored idempotently.
    func discard() { if let directory { try? FileManager.default.removeItem(at: directory) } }
}
