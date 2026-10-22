import Foundation
import SwiftData
import CryptoKit
import SQLite3
import Darwin

extension CoachLocalOwnership {
    /// A journal contains identities and digests, never record contents. The
    /// original store and every selected destination are retained on failure.
    struct MigrationJournal: Codable {
        var version = 1
        let id: UUID
        let source: String
        let directory: String
        var phase: String
        var checkpoint: String? = nil
    }

    struct RawCheckpoint {
        let digest: String
        let assetDigest: String
        let columns: [String: [String]]
        let recordDigest: String
        var identity: String { digest + ":" + assetDigest }
    }

    final class MigrationLock {
        private let descriptor: Int32
        init(root: URL) throws {
            try prepareDirectory(root)
            descriptor = Darwin.open(root.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { throw migrationError("The storage lock could not be opened.") }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(descriptor)
                throw migrationError("Another storage operation is already in progress.")
            }
        }
        deinit { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
    }

    static func migrationError(_ message: String) -> OwnershipError {
        .unavailable(message + " Your original history has been retained.")
    }

    static func journalURL(root: URL) -> URL { root.appendingPathComponent("migration.json") }

    static func readJournal(root: URL) throws -> MigrationJournal? {
        let url = journalURL(root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let journal = try JSONDecoder().decode(MigrationJournal.self, from: Data(contentsOf: url))
        guard journal.version == 1, UUID(uuidString: journal.directory) != nil,
              ["allocated", "copied", "verified", "active"].contains(journal.phase),
              journal.phase == "allocated" || journal.checkpoint != nil else {
            throw migrationError("The migration journal needs recovery.")
        }
        return journal
    }

    static func writeJournal(_ journal: MigrationJournal, root: URL) throws {
        try prepareDirectory(root)
        let data = try JSONEncoder().encode(journal)
        try data.write(to: journalURL(root: root), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let handle = try FileHandle(forWritingTo: journalURL(root: root)); defer { try? handle.close() }
        try handle.synchronize()
    }

    static func beginMigration(source: URL, root: URL) throws -> MigrationJournal {
        if let current = try readJournal(root: root) {
            guard current.source == source.standardizedFileURL.path else {
                throw migrationError("The retained source no longer matches the migration journal.")
            }
            guard current.phase != "active" else {
                throw migrationError("An active destination is missing its selection. Recovery is required before another copy.")
            }
            return current
        }
        let journal = MigrationJournal(id: UUID(), source: source.standardizedFileURL.path,
                                       directory: UUID().uuidString, phase: "allocated")
        try writeJournal(journal, root: root)
        return journal
    }

    static func restartUnselectedMigration(_ previous: MigrationJournal, source: URL, root: URL) throws -> MigrationJournal {
        guard try selectedStoreURL(root: root) == nil, previous.phase != "active",
              try readJournal(root: root)?.id == previous.id else {
            throw migrationError("The migration changed while a fresh copy was being prepared.")
        }
        let retained = root.appendingPathComponent("retained-migration-\(previous.id.uuidString).json")
        if !FileManager.default.fileExists(atPath: retained.path) {
            try JSONEncoder().encode(previous).write(to: retained, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let fresh = MigrationJournal(id: UUID(), source: source.standardizedFileURL.path,
                                     directory: UUID().uuidString, phase: "allocated")
        try writeJournal(fresh, root: root)
        return fresh
    }

    static func destination(for journal: MigrationJournal, root: URL) -> URL {
        root.appendingPathComponent(journal.directory, isDirectory: true).appendingPathComponent("default.store")
    }

    /// Inspects only SQLite through a read-only connection. Comparing every
    /// original column avoids treating the portable backup DTO as a complete
    /// inventory of persisted fields. Core Data bookkeeping is checked in the
    /// raw-copy digest, but may legitimately change when a copy is opened.
    static func rawCheckpoint(_ url: URL) throws -> RawCheckpoint {
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw migrationError("The retained storage file is an unsupported link or file type.")
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = database else {
            if let database { sqlite3_close(database) }
            throw migrationError("The retained SQLite history could not be read.")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw migrationError("A consistent history snapshot was unavailable.") }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", -1, &statement, nil) == SQLITE_OK,
              let tablesStatement = statement else { throw migrationError("The source schema could not be inspected.") }
        defer { sqlite3_finalize(tablesStatement) }
        var all = "", records = "", columns: [String: [String]] = [:]
        while true {
            let step = sqlite3_step(tablesStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let nameBytes = sqlite3_column_text(tablesStatement, 0) else { throw migrationError("The source schema could not be read completely.") }
            let name = String(cString: nameBytes)
            let schema = sqlite3_column_text(tablesStatement, 1).map { String(cString: $0) } ?? ""
            let row = try tableDigest(db, table: name, columns: nil)
            all += "\(name.utf8.count):\(name)\(schema.utf8.count):\(schema)\(row.digest)"
            // These are Core Data metadata, not app-owned model columns.
            if !["Z_METADATA", "Z_PRIMARYKEY", "Z_MODELCACHE"].contains(name) && !name.hasPrefix("ANSCK") {
                columns[name] = row.columns
                records += "\(name.utf8.count):\(name)\(row.digest)"
            }
        }
        guard !columns.isEmpty else { throw migrationError("The source contains no recognized persisted tables.") }
        return RawCheckpoint(digest: hash(Data(all.utf8)), assetDigest: try assetDigest(url), columns: columns,
                             recordDigest: hash(Data(records.utf8)))
    }

    static func verifyRetainedColumns(_ checkpoint: RawCheckpoint, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = database else {
            if let database { sqlite3_close(database) }
            throw migrationError("The local copy could not be verified.")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw migrationError("The local copy snapshot could not be opened.") }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        var records = ""
        for table in checkpoint.columns.keys.sorted() {
            let row = try tableDigest(db, table: table, columns: checkpoint.columns[table])
            records += "\(table.utf8.count):\(table)\(row.digest)"
        }
        guard hash(Data(records.utf8)) == checkpoint.recordDigest, try assetDigest(url) == checkpoint.assetDigest else {
            throw migrationError("Opening the local schema changed an original record or asset. The copy was not selected.")
        }
    }

    private static func quote(_ identifier: String) -> String { "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private static func tableDigest(_ db: OpaquePointer, table: String, columns: [String]?) throws -> (columns: [String], digest: String) {
        let fields = columns.map { $0.map(quote).joined(separator: ",") } ?? "*"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT \(fields) FROM \(quote(table))", -1, &statement, nil) == SQLITE_OK,
              let query = statement else { throw migrationError("A persisted table or field could not be verified.") }
        defer { sqlite3_finalize(query) }
        let names = (0..<sqlite3_column_count(query)).map { String(cString: sqlite3_column_name(query, $0)) }
        var rows: [String] = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw migrationError("A persisted row could not be verified.") }
            var bytes = Data()
            for index in 0..<sqlite3_column_count(query) {
                let type = sqlite3_column_type(query, index)
                bytes.append(Data("\(type):".utf8))
                let value: Data
                switch type {
                case SQLITE_NULL: value = Data()
                case SQLITE_INTEGER: value = Data(String(sqlite3_column_int64(query, index)).utf8)
                case SQLITE_FLOAT: value = Data(String(sqlite3_column_double(query, index).bitPattern).utf8)
                default:
                    let count = Int(sqlite3_column_bytes(query, index))
                    if count > 0, let pointer = sqlite3_column_blob(query, index) { value = Data(bytes: pointer, count: count) }
                    else { value = Data() }
                }
                bytes.append(Data("\(value.count):".utf8)); bytes.append(value)
            }
            rows.append(hash(bytes))
        }
        return (names, hash(Data((names.joined(separator: "|") + ":" + rows.sorted().joined()).utf8)))
    }

    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func assetDigest(_ store: URL) throws -> String {
        let manager = FileManager.default
        let support = store.deletingLastPathComponent().appendingPathComponent(".\(store.deletingPathExtension().lastPathComponent)_SUPPORT", isDirectory: true)
        guard manager.fileExists(atPath: support.path) else { return hash(Data()) }
        let info = try support.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var enumerationError: Error?
        guard info.isDirectory == true, info.isSymbolicLink != true,
              let enumerator = manager.enumerator(at: support, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                  errorHandler: { _, error in enumerationError = error; return false }) else {
            throw migrationError("The original data assets could not be inspected safely.")
        }
        var rows: [String] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw migrationError("A linked data asset needs manual recovery.") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw migrationError("An unsupported data asset needs manual recovery.") }
            let relative = String(file.path.dropFirst(support.path.count))
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            var digest = SHA256()
            while true {
                try Task.checkCancellation()
                let part = try handle.read(upToCount: 1_048_576) ?? Data()
                if part.isEmpty { break }; digest.update(data: part)
            }
            rows.append(relative + ":" + digest.finalize().map { String(format: "%02x", $0) }.joined())
        }
        if let enumerationError { throw enumerationError }
        return hash(Data(rows.sorted().joined(separator: "\n").utf8))
    }
}
