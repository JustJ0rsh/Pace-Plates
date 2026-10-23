import Foundation
import CryptoKit
import SQLite3
import Darwin

/// Reads live stores through SQLite. A stable, sidecar-free WAL-format main
/// file is read through an owned COW clone: even a read-only SQLite connection
/// can otherwise create WAL/SHM files beside the original on Apple platforms.
/// The clone proves only the intact current main file, not missing WAL commits.
enum CoachSQLiteReadSnapshot {
    struct SnapshotError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func withReadOnlySource<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        try Task.checkCancellation()
        let source = try Source(url)
        // Decide before opening SQLite, which can create sidecars even with
        // SQLITE_OPEN_READONLY. No SQLite failure triggers a broader fallback.
        if try source.hasWALHeader(), try source.sidecarsAreAbsent() {
            return try withColdSnapshot(source, hooks: Hooks(), body)
        }
        return try withReadTransaction(source.url, body)
    }

    /// Also callable by focused host checks on platforms where cold WAL files
    /// happen to open normally. It uses exactly the production guarded path.
    static func withColdSnapshot<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        try withColdSnapshot(Source(url), hooks: Hooks(), body)
    }

    enum TestPhase {
        case sourceValidated, cloneCreated, cloneOpened, beforeCloneNormalization, cloneNormalized, beforeFinalVerification
    }

    #if DEBUG
    static func withColdSnapshotForTesting<T>(_ url: URL,
        onPhase: @escaping (TestPhase, URL) throws -> Void,
        _ body: (OpaquePointer) throws -> T) throws -> T {
        try withColdSnapshot(Source(url), hooks: Hooks(callback: onPhase), body)
    }
    #endif

    private struct Hooks {
        #if DEBUG
        var callback: ((TestPhase, URL) throws -> Void)? = nil
        #endif
        func reached(_ phase: TestPhase, directory: URL) throws {
            try Task.checkCancellation()
            #if DEBUG
            try callback?(phase, directory)
            #endif
        }
    }

    private static func withColdSnapshot<T>(_ source: Source, hooks: Hooks,
                                             _ body: (OpaquePointer) throws -> T) throws -> T {
        try Task.checkCancellation()
        let original = try source.fingerprint()
        guard try source.hasWALHeader() else { throw failure("The sidecar-free source is not a WAL-format store.") }
        let temporary = try TemporaryDirectory()
        defer { temporary.removeOwnedDirectory() }
        do {
            try hooks.reached(.sourceValidated, directory: temporary.url)
            // COW creation is atomic, but it is not SQLite writer coordination.
            // Refuse observed activity rather than assume that a writer stopped.
            try source.verify(original)
            let clone = temporary.url.appendingPathComponent("snapshot.store")
            guard fclonefileat(source.descriptor, temporary.descriptor, "snapshot.store",
                               UInt32(CLONE_NOFOLLOW | CLONE_NOOWNERCOPY)) == 0 else {
                throw failure("A safe disposable SQLite clone is unavailable (OS \(errno)).")
            }
            try hooks.reached(.cloneCreated, directory: temporary.url)
            let clonedSource = try Source(clone)
            let clonedFingerprint = try clonedSource.fingerprint()
            guard (clonedFingerprint.identity.device != original.identity.device || clonedFingerprint.identity.inode != original.identity.inode),
                  clonedFingerprint.digest == original.digest else {
                throw failure("The disposable SQLite clone does not match the retained source.")
            }
            try source.verify(original)
            try clonedSource.verifyPath()
            // Change permissions/protection only on our new clone. Its inherited
            // mode may be read-only, while normalization needs a private writer.
            try FileManager.default.setAttributes([
                .posixPermissions: 0o600,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ], ofItemAtPath: clone.path)
            try normalizeClone(clonedSource, opened: {
                try hooks.reached(.cloneOpened, directory: temporary.url)
            }, validated: {
                try hooks.reached(.beforeCloneNormalization, directory: temporary.url)
            })
            let normalized = try clonedSource.fingerprint()
            try hooks.reached(.cloneNormalized, directory: temporary.url)
            try clonedSource.verify(normalized)
            let result = try withReadTransaction(clonedSource.url, body)
            try hooks.reached(.beforeFinalVerification, directory: temporary.url)
            try clonedSource.verify(normalized)
            try source.verify(original)
            return result
        } catch {
            // Verification is also required when a consumer or test hook fails.
            // A detected source race takes precedence over that operation error.
            try source.verify(original, checkingCancellation: false)
            throw error
        }
    }

    private static func normalizeClone(_ source: Source, opened: () throws -> Void, validated: () throws -> Void) throws {
        try source.verifyPath()
        try withConnection(source.url, flags: SQLITE_OPEN_READWRITE) { db in
            try opened()
            try source.verifyPath()
            // Apple SQLite may preserve WAL/SHM by default. Configure only
            // this private writer to let SQLite clean up its own sidecars.
            var persistentWAL: Int32 = 0
            guard sqlite3_file_control(db, "main", SQLITE_FCNTL_PERSIST_WAL, &persistentWAL) == SQLITE_OK else {
                throw sqliteFailure("The disposable SQLite WAL could not be configured", db)
            }
            try integrityCheck(db)
            let before = try logicalDigest(db)
            try validated()
            try source.verifyPath()
            var logFrames: Int32 = -1, checkpointedFrames: Int32 = -1
            guard sqlite3_wal_checkpoint_v2(db, "main", SQLITE_CHECKPOINT_TRUNCATE, &logFrames, &checkpointedFrames) == SQLITE_OK,
                  logFrames == 0, checkpointedFrames == 0 else {
                throw sqliteFailure("The disposable SQLite WAL could not be fully checkpointed", db)
            }
            try expectSingleText(db, sql: "PRAGMA journal_mode=DELETE", expected: "delete")
            guard try logicalDigest(db) == before else {
                throw failure("Normalizing the disposable SQLite clone changed its records or schema.")
            }
            try integrityCheck(db)
        }
    }

    private static func withReadTransaction<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        try Task.checkCancellation()
        return try withConnection(url, flags: SQLITE_OPEN_READONLY) { db in
            try execute(db, "BEGIN")
            defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }
            // Start the read snapshot before handing the connection to either
            // raw inspection or SQLite's consistent backup API.
            try execute(db, "SELECT count(*) FROM sqlite_master")
            return try body(db)
        }
    }

    private static func withConnection<T>(_ url: URL, flags: Int32,
                                          _ body: (OpaquePointer) throws -> T) throws -> T {
        let canonicalURL = try canonicalFileURL(url)
        var database: OpaquePointer?
        let result = sqlite3_open_v2(canonicalURL.path, &database, flags | SQLITE_OPEN_NOFOLLOW, nil)
        guard result == SQLITE_OK, let db = database else {
            let error = database.map { sqliteFailure("SQLite could not open the retained snapshot", $0) }
                ?? failure("SQLite could not open the retained snapshot (SQLite \(result)).")
            if let database { sqlite3_close(database) }
            throw error
        }
        sqlite3_busy_timeout(db, 5_000)
        let value: T
        do { value = try body(db) }
        catch {
            sqlite3_close_v2(db)
            throw error
        }
        guard sqlite3_close(db) == SQLITE_OK else {
            let error = sqliteFailure("SQLite could not close the retained snapshot", db)
            sqlite3_close_v2(db)
            throw error
        }
        return value
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteFailure("The retained SQLite snapshot could not be read", db)
        }
    }

    private static func integrityCheck(_ db: OpaquePointer) throws {
        try expectSingleText(db, sql: "PRAGMA integrity_check", expected: "ok")
    }

    private static func expectSingleText(_ db: OpaquePointer, sql: String, expected: String) throws {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK, let query else {
            if let query { sqlite3_finalize(query) }
            throw sqliteFailure("The disposable SQLite clone could not be validated", db)
        }
        defer { sqlite3_finalize(query) }
        guard sqlite3_step(query) == SQLITE_ROW, sqlite3_column_count(query) == 1,
              sqlite3_column_type(query, 0) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(query, 0),
              sqlite3_column_bytes(query, 0) == expected.utf8.count,
              String(cString: bytes) == expected, sqlite3_step(query) == SQLITE_DONE else {
            throw failure("The disposable SQLite clone failed validation or journal normalization.")
        }
    }

    /// Includes every schema object, declared table column and selected stable
    /// header metadata, including SQLite and Core Data bookkeeping.
    private static func logicalDigest(_ db: OpaquePointer) throws -> SHA256.Digest {
        var digest = SHA256()
        for pragma in ["user_version", "application_id", "encoding", "page_size", "auto_vacuum", "schema_version"] {
            digest.update(data: Data(pragma.utf8))
            digest.update(data: try queryDigest(db, "PRAGMA \(pragma)"))
        }
        digest.update(data: try queryDigest(db, "SELECT type,name,tbl_name,rootpage,sql FROM sqlite_master"))
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", -1, &query, nil) == SQLITE_OK,
              let query else {
            if let query { sqlite3_finalize(query) }
            throw sqliteFailure("The disposable SQLite schema could not be inspected", db)
        }
        defer { sqlite3_finalize(query) }
        while true {
            try Task.checkCancellation()
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW, let bytes = sqlite3_column_text(query, 0) else {
                throw sqliteFailure("The disposable SQLite schema was incomplete", db)
            }
            let name = String(cString: bytes)
            digest.update(data: Data("\(name.utf8.count):\(name)".utf8))
            let quoted = "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            digest.update(data: try queryDigest(db, "SELECT * FROM \(quoted)"))
        }
        return digest.finalize()
    }

    private static func queryDigest(_ db: OpaquePointer, _ sql: String) throws -> Data {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK, let query else {
            if let query { sqlite3_finalize(query) }
            throw sqliteFailure("A disposable SQLite table could not be inspected", db)
        }
        defer { sqlite3_finalize(query) }
        var digest = SHA256(), rows: [Data] = []
        for index in 0..<sqlite3_column_count(query) {
            let name = String(cString: sqlite3_column_name(query, index))
            digest.update(data: Data("\(name.utf8.count):\(name)".utf8))
        }
        while true {
            try Task.checkCancellation()
            let step = sqlite3_step(query)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw sqliteFailure("A disposable SQLite row could not be inspected", db) }
            var row = SHA256()
            for index in 0..<sqlite3_column_count(query) {
                let type = sqlite3_column_type(query, index)
                let value: Data
                switch type {
                case SQLITE_NULL: value = Data()
                case SQLITE_INTEGER: value = Data(String(sqlite3_column_int64(query, index)).utf8)
                case SQLITE_FLOAT: value = Data(String(sqlite3_column_double(query, index).bitPattern).utf8)
                default:
                    let count = Int(sqlite3_column_bytes(query, index))
                    if count > 0, let bytes = sqlite3_column_blob(query, index) { value = Data(bytes: bytes, count: count) }
                    else { value = Data() }
                }
                row.update(data: Data("\(type):\(value.count):".utf8)); row.update(data: value)
            }
            rows.append(Data(row.finalize()))
        }
        for row in rows.sorted(by: { $0.lexicographicallyPrecedes($1) }) { digest.update(data: row) }
        return Data(digest.finalize())
    }

    private struct FileIdentity: Equatable {
        let device: dev_t, inode: ino_t, size: off_t
        let modifiedSeconds: Int, modifiedNanoseconds: Int
        let changedSeconds: Int, changedNanoseconds: Int
        init(_ value: stat) throws {
            guard value.st_mode & S_IFMT == S_IFREG else { throw failure("The retained SQLite source is not a regular file.") }
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private struct Fingerprint: Equatable {
        let identity: FileIdentity
        let digest: Data
    }

    private final class Source {
        let url: URL
        let descriptor: Int32
        init(_ url: URL) throws {
            // Resolve the existing parent only; never resolve the file tail.
            self.url = try canonicalFileURL(url)
            let opened = Darwin.open(self.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard opened >= 0 else { throw failure("The retained SQLite file could not be opened without following links (OS \(errno)).") }
            do {
                var held = stat(), named = stat()
                guard fstat(opened, &held) == 0, lstat(self.url.path, &named) == 0,
                      try FileIdentity(held) == FileIdentity(named) else {
                    throw failure("The retained SQLite pathname changed while being opened.")
                }
            } catch { Darwin.close(opened); throw error }
            descriptor = opened
        }
        deinit { Darwin.close(descriptor) }

        func identity() throws -> FileIdentity {
            var value = stat()
            guard fstat(descriptor, &value) == 0 else { throw failure("The retained SQLite file could not be inspected (OS \(errno)).") }
            return try FileIdentity(value)
        }
        func verifyPath() throws {
            var value = stat()
            guard lstat(url.path, &value) == 0, try FileIdentity(value) == identity() else {
                throw failure("The retained SQLite pathname changed during the snapshot.")
            }
        }
        func sidecarsAreAbsent() throws -> Bool {
            for suffix in ["-wal", "-shm", "-journal"] {
                var value = stat()
                if lstat(url.path + suffix, &value) == 0 { return false }
                guard errno == ENOENT else { throw failure("The retained SQLite sidecars could not be inspected (OS \(errno)).") }
            }
            return true
        }
        func hasWALHeader() throws -> Bool {
            var bytes = [UInt8](repeating: 0, count: 20)
            var count: Int
            repeat { count = pread(descriptor, &bytes, bytes.count, 0) } while count < 0 && errno == EINTR
            guard count >= 0 else { throw failure("The retained SQLite header could not be read (OS \(errno)).") }
            return count == 20 && Data(bytes.prefix(16)) == Data("SQLite format 3\0".utf8) && bytes[18] == 2 && bytes[19] == 2
        }
        func fingerprint(checkingCancellation: Bool = true) throws -> Fingerprint {
            try verifyPath()
            guard try sidecarsAreAbsent() else { throw failure("The retained SQLite source has sidecars; a cold snapshot is unsafe.") }
            let before = try identity()
            var digest = SHA256(), offset: off_t = 0
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                if checkingCancellation { try Task.checkCancellation() }
                var count: Int
                repeat { count = pread(descriptor, &buffer, buffer.count, offset) } while count < 0 && errno == EINTR
                guard count >= 0 else { throw failure("The retained SQLite bytes could not be read (OS \(errno)).") }
                if count == 0 { break }
                offset += off_t(count)
                guard offset <= before.size else { throw failure("The retained SQLite file grew during the snapshot.") }
                digest.update(data: Data(buffer.prefix(count)))
            }
            guard offset == before.size, try identity() == before else { throw failure("The retained SQLite file changed during the snapshot.") }
            try verifyPath()
            guard try sidecarsAreAbsent() else { throw failure("The retained SQLite source became active during the snapshot.") }
            return Fingerprint(identity: before, digest: Data(digest.finalize()))
        }
        func verify(_ original: Fingerprint, checkingCancellation: Bool = true) throws {
            guard try fingerprint(checkingCancellation: checkingCancellation) == original else { throw failure("The retained SQLite source changed during the disposable snapshot.") }
        }
    }

    private final class TemporaryDirectory {
        let url: URL
        let descriptor: Int32
        private let device: dev_t
        private let inode: ino_t
        init() throws {
            let parent = try canonicalDirectory(FileManager.default.temporaryDirectory)
            var template = Array(parent.appendingPathComponent("coach-sqlite-XXXXXX").path.utf8CString)
            guard let path = mkdtemp(&template) else { throw failure("A private SQLite snapshot directory could not be created (OS \(errno)).") }
            let createdURL = URL(fileURLWithPath: String(cString: path), isDirectory: true)
            let opened = Darwin.open(createdURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            var value = stat()
            guard opened >= 0, fstat(opened, &value) == 0 else {
                if opened >= 0 { Darwin.close(opened) }
                try? FileManager.default.removeItem(at: createdURL)
                throw failure("The private SQLite snapshot directory could not be inspected.")
            }
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700,
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: createdURL.path)
                var protectedURL = createdURL, values = URLResourceValues()
                values.isExcludedFromBackup = true
                try protectedURL.setResourceValues(values)
            } catch {
                Darwin.close(opened)
                try? FileManager.default.removeItem(at: createdURL)
                throw error
            }
            url = createdURL; descriptor = opened
            device = value.st_dev; inode = value.st_ino
        }
        deinit { Darwin.close(descriptor) }
        func removeOwnedDirectory() {
            var value = stat()
            guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFDIR,
                  value.st_dev == device, value.st_ino == inode else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Foundation preserves some Apple system aliases such as /var even after
    /// resolvingSymlinksInPath(). SQLite NOFOLLOW rejects those parent aliases.
    /// Resolve only an existing parent with POSIX realpath, never the file tail.
    private static func canonicalFileURL(_ url: URL) throws -> URL {
        try canonicalDirectory(url.deletingLastPathComponent()).appendingPathComponent(url.lastPathComponent)
    }

    private static func canonicalDirectory(_ url: URL) throws -> URL {
        guard let path = realpath(url.path, nil) else {
            throw failure("The retained SQLite directory could not be resolved (OS \(errno)).")
        }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    private static func failure(_ message: String) -> SnapshotError { SnapshotError(message: message) }
    private static func sqliteFailure(_ operation: String, _ db: OpaquePointer) -> SnapshotError {
        failure("\(operation) (SQLite \(sqlite3_extended_errcode(db)), OS \(sqlite3_system_errno(db)): \(String(cString: sqlite3_errmsg(db)))).")
    }
}
