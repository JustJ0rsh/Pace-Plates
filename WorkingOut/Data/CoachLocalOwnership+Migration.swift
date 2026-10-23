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
        let schemaTables: Set<String>
        let recordDigest: String
        #if DEBUG
        let source: URL
        let tableDigests: [String: String]
        #endif
        var identity: String { digest + ":" + assetDigest }
    }

    final class MigrationLock {
        private var descriptor: Int32 = -1
        init(root: URL) throws {
            try prepareDirectory(root)
            descriptor = Darwin.open(root.appendingPathComponent("migration.lock").path, O_CREAT | O_RDWR, 0o600)
            guard descriptor >= 0 else { throw migrationError("The storage lock could not be opened.") }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                Darwin.close(descriptor)
                descriptor = -1
                throw migrationError("Another storage operation is already in progress.")
            }
        }
        deinit {
            if descriptor >= 0 { _ = flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        }
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
    static func rawCheckpoint(_ url: URL, phase: String = "History") throws -> RawCheckpoint {
        try withReadableSource(url) { db in
            try rawCheckpoint(url, database: db, phase: phase)
        }
    }

    private static func rawCheckpoint(_ url: URL, database db: OpaquePointer, phase: String) throws -> RawCheckpoint {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT name, sql FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", -1, &statement, nil)
        guard prepared == SQLITE_OK, let tablesStatement = statement else {
            let failure = sqliteFailure("\(phase) schema could not be inspected", database: db)
            if let statement { sqlite3_finalize(statement) }
            throw failure
        }
        defer { sqlite3_finalize(tablesStatement) }
        let entityNames = try entityNameMap(db)
        var all = "", records = "", columns: [String: [String]] = [:]
        var schemaTables: Set<String> = []
        #if DEBUG
        var tableDigests: [String: String] = [:]
        #endif
        while true {
            let step = sqlite3_step(tablesStatement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let nameBytes = sqlite3_column_text(tablesStatement, 0) else { throw sqliteFailure("The source schema could not be read completely", database: db) }
            let name = String(cString: nameBytes)
            schemaTables.insert(name)
            let schema = sqlite3_column_text(tablesStatement, 1).map { String(cString: $0) } ?? ""
            let row = try tableDigest(db, table: name, columns: nil)
            all += "\(name.utf8.count):\(name)\(schema.utf8.count):\(schema)\(row.digest)"
            // These are Core Data metadata, not app-owned model columns.
            if !knownBookkeepingTables.contains(name) && !name.hasPrefix("ANSCK") {
                let semantic = try tableDigest(db, table: name, columns: nil, entityNames: entityNames)
                columns[name] = row.columns
                records += "\(name.utf8.count):\(name)\(semantic.digest)"
                #if DEBUG
                tableDigests[name] = semantic.digest
                #endif
            }
        }
        guard !columns.isEmpty else { throw migrationError("The source contains no recognized persisted tables.") }
        #if DEBUG
        return RawCheckpoint(digest: hash(Data(all.utf8)), assetDigest: try assetDigest(url), columns: columns, schemaTables: schemaTables,
                             recordDigest: hash(Data(records.utf8)), source: url, tableDigests: tableDigests)
        #else
        return RawCheckpoint(digest: hash(Data(all.utf8)), assetDigest: try assetDigest(url), columns: columns, schemaTables: schemaTables,
                             recordDigest: hash(Data(records.utf8)))
        #endif
    }

    static func verifyRetainedColumns(_ checkpoint: RawCheckpoint, at url: URL, allowedNewTables: Set<String> = []) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(canonicalSQLiteURL(url).path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = database else {
            if let database { sqlite3_close(database) }
            throw migrationError("The local copy could not be verified.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5_000)
        guard sqlite3_exec(db, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw sqliteFailure("The local copy snapshot could not be opened", database: db) }
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
        let entityNames = try entityNameMap(db)
        let destinationTables = try tableNames(db)
        for table in destinationTables.subtracting(checkpoint.schemaTables) {
            guard knownBookkeepingTables.contains(table) || allowedNewTables.contains(table) else {
                throw migrationError("The local schema added an unrecognized table. The copy was not selected.")
            }
            if allowedNewTables.contains(table), try diagnosticRowCount(db, table: table) != 0 {
                throw migrationError("The local schema unexpectedly populated a new table. The copy was not selected.")
            }
        }
        var records = ""
        #if DEBUG
        var actualTableDigests: [String: String] = [:]
        #endif
        for table in checkpoint.columns.keys.sorted() {
            let full = try tableDigest(db, table: table, columns: nil, entityNames: entityNames)
            guard full.columns == checkpoint.columns[table] else {
                throw migrationError("A persisted table gained or lost unrecognized columns. The copy was not selected.")
            }
            let row = try tableDigest(db, table: table, columns: checkpoint.columns[table], entityNames: entityNames)
            records += "\(table.utf8.count):\(table)\(row.digest)"
            #if DEBUG
            actualTableDigests[table] = row.digest
            #endif
        }
        let recordsMatch = hash(Data(records.utf8)) == checkpoint.recordDigest
        let assetsMatch = try assetDigest(url) == checkpoint.assetDigest
        guard recordsMatch, assetsMatch else {
            var message = "Opening the local schema changed an original record or asset. The copy was not selected."
            #if DEBUG
            message += " " + ((try? verificationDiagnostic(checkpoint, copy: db, actual: actualTableDigests, assetsMatch: assetsMatch)) ?? "Mismatch diagnostic unavailable.")
            #endif
            throw migrationError(message)
        }
    }

    /// Exact framework tables observed changing during the full-schema open.
    /// They remain in the literal pre-copy/source checksum above. None of the
    /// application's columns, row IDs or foreign keys are excluded here.
    private static let knownBookkeepingTables: Set<String> = [
        "Z_METADATA", "Z_PRIMARYKEY", "Z_MODELCACHE",
        "ACHANGE", "ATRANSACTION", "ATRANSACTIONSTRING"
    ]

    private static func tableNames(_ db: OpaquePointer) throws -> Set<String> {
        var query: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'", -1, &query, nil)
        guard prepared == SQLITE_OK, let query else {
            let failure = sqliteFailure("The destination schema could not be inspected", database: db)
            if let query { sqlite3_finalize(query) }
            throw failure
        }
        defer { sqlite3_finalize(query) }
        var result: Set<String> = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let name = sqlite3_column_text(query, 0) else {
                throw sqliteFailure("The destination schema could not be read", database: db)
            }
            result.insert(String(cString: name))
        }
        return result
    }

    private static func entityNameMap(_ db: OpaquePointer) throws -> [Int64: String] {
        var query: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY", -1, &query, nil)
        guard prepared == SQLITE_OK, let query else {
            let failure = sqliteFailure("The entity identity map could not be inspected", database: db)
            if let query { sqlite3_finalize(query) }
            throw failure
        }
        defer { sqlite3_finalize(query) }
        var result: [Int64: String] = [:]
        var names: Set<String> = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, sqlite3_column_type(query, 0) == SQLITE_INTEGER,
                  sqlite3_column_type(query, 1) == SQLITE_TEXT, let value = sqlite3_column_text(query, 1) else {
                throw migrationError("The entity identity map contains an unsupported entry.")
            }
            let id = sqlite3_column_int64(query, 0), name = String(cString: value)
            guard !name.isEmpty, result[id] == nil, names.insert(name).inserted else {
                throw migrationError("The entity identity map is ambiguous.")
            }
            result[id] = name
        }
        return result
    }

    #if DEBUG
    /// Diagnostic only: compare field fingerprints after the full-row guard
    /// has already failed. No values, IDs, paths or hashes leave this method.
    private static func verificationDiagnostic(_ checkpoint: RawCheckpoint, copy: OpaquePointer,
                                               actual: [String: String], assetsMatch: Bool) throws -> String {
        let changed = checkpoint.tableDigests.keys.sorted().filter { checkpoint.tableDigests[$0] != actual[$0] }
        return try withReadableSource(checkpoint.source) { sourceDB in
            try verificationDiagnostic(checkpoint, source: sourceDB, copy: copy, changed: changed, assetsMatch: assetsMatch)
        }
    }

    private static func verificationDiagnostic(_ checkpoint: RawCheckpoint, source sourceDB: OpaquePointer,
                                               copy: OpaquePointer, changed: [String], assetsMatch: Bool) throws -> String {
        let sourceNames = try entityNameMap(sourceDB), copyNames = try entityNameMap(copy)
        var descriptions: [String] = []
        for table in changed.prefix(4) {
            let original = try tableDigest(sourceDB, table: table, columns: checkpoint.columns[table], entityNames: sourceNames)
            guard original.digest == checkpoint.tableDigests[table] else {
                descriptions.append(table + ": source changed before diagnostic")
                continue
            }
            var fields: [String] = []
            for column in checkpoint.columns[table] ?? [] {
                if try tableDigest(sourceDB, table: table, columns: [column], entityNames: sourceNames).digest != tableDigest(copy, table: table, columns: [column], entityNames: copyNames).digest {
                    fields.append(column)
                }
            }
            let sourceCount = try diagnosticRowCount(sourceDB, table: table)
            let copyCount = try diagnosticRowCount(copy, table: table)
            descriptions.append("\(table) rows \(sourceCount)->\(copyCount): "
                + (fields.isEmpty ? "row associations changed" : fields.prefix(12).joined(separator: ",")))
        }
        return "Records changed: \(!changed.isEmpty); assets changed: \(!assetsMatch). " + descriptions.joined(separator: "; ")
    }

    #endif

    private static func diagnosticRowCount(_ db: OpaquePointer, table: String) throws -> Int64 {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT count(*) FROM \(quote(table))", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw migrationError("Diagnostic row count unavailable.")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw migrationError("Diagnostic row count unavailable.") }
        return sqlite3_column_int64(statement, 0)
    }

    private static func quote(_ identifier: String) -> String { "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private static func sqliteFailure(_ operation: String, database: OpaquePointer) -> OwnershipError {
        // SQLite's diagnostic contains schema/locking information, never any
        // queried row content. It distinguishes retryable contention from an
        // unsupported/corrupt schema without logging personal record values.
        var detail = "SQLite \(sqlite3_extended_errcode(database)), OS \(sqlite3_system_errno(database)): \(String(cString: sqlite3_errmsg(database)))"
        #if DEBUG
        if let filename = sqlite3_db_filename(database, "main") {
            let path = String(cString: filename)
            let manager = FileManager.default
            let metadata = ["main": path, "WAL": path + "-wal", "SHM": path + "-shm"].map { label, file in
                "\(label)=\(manager.fileExists(atPath: file) ? "present" : "absent")/\(manager.isReadableFile(atPath: file) ? "readable" : "unreadable")"
            }.sorted().joined(separator: ", ")
            detail += "; " + metadata
        }
        #endif
        return migrationError("\(operation) (\(detail)).")
    }

    private static func tableDigest(_ db: OpaquePointer, table: String, columns: [String]?, entityNames: [Int64: String]? = nil) throws -> (columns: [String], digest: String) {
        let fields = columns.map { $0.map(quote).joined(separator: ",") } ?? "*"
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT \(fields) FROM \(quote(table))", -1, &statement, nil)
        guard prepared == SQLITE_OK, let query = statement else {
            let failure = sqliteFailure("A persisted table or field could not be verified", database: db)
            if let statement { sqlite3_finalize(statement) }
            throw failure
        }
        defer { sqlite3_finalize(query) }
        let names = (0..<sqlite3_column_count(query)).map { String(cString: sqlite3_column_name(query, $0)) }
        var rows: [String] = []
        while true {
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteFailure("A persisted row could not be verified", database: db) }
            var bytes = Data()
            for index in 0..<sqlite3_column_count(query) {
                let type = sqlite3_column_type(query, index)
                if names[Int(index)] == "Z_ENT", let entityNames {
                    guard type == SQLITE_INTEGER, let meaning = entityNames[sqlite3_column_int64(query, index)] else {
                        throw migrationError("A persisted row has an unknown entity identity.")
                    }
                    let value = Data(meaning.utf8)
                    bytes.append(Data("entity:\(value.count):".utf8)); bytes.append(value)
                    continue
                }
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
