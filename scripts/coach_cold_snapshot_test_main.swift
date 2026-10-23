// Host checks of the actual production snapshot helper. All databases are
// disposable fixtures; no application container or user path is accepted.
import Foundation
import SQLite3
import CryptoKit
import Darwin

private enum ProbeError: Error { case failed(String), interrupted }

@main struct ColdSnapshotTests {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("pace-cold-tests-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        var checks = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw ProbeError.failed(label) }
            checks += 1
        }
        func execute(_ db: OpaquePointer, _ sql: String) throws {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw ProbeError.failed("Fixture SQL failed: " + String(cString: sqlite3_errmsg(db)))
            }
        }
        func connection<T>(_ url: URL, _ flags: Int32, _ body: (OpaquePointer) throws -> T) throws -> T {
            var pointer: OpaquePointer?
            let opened = sqlite3_open_v2(url.path, &pointer, flags, nil)
            guard opened == SQLITE_OK, let db = pointer else {
                if let pointer { sqlite3_close(pointer) }
                throw ProbeError.failed("Fixture connection failed")
            }
            let result: T
            do { result = try body(db) }
            catch { sqlite3_close_v2(db); throw error }
            guard sqlite3_close(db) == SQLITE_OK else { sqlite3_close_v2(db); throw ProbeError.failed("Fixture did not close") }
            return result
        }
        func text(_ db: OpaquePointer, _ sql: String) throws -> String {
            var query: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &query, nil) == SQLITE_OK, let statement = query else {
                if let query { sqlite3_finalize(query) }
                throw ProbeError.failed("Fixture query could not prepare")
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
                throw ProbeError.failed("Fixture query returned no text")
            }
            return String(cString: value)
        }
        func fixture(_ name: String) throws -> URL {
            print("Cold fixture: " + name)
            fflush(stdout)
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("source.store")
            try connection(url, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) { db in
                try execute(db, "PRAGMA foreign_keys=ON; CREATE TABLE parent(id INTEGER PRIMARY KEY, uuid TEXT UNIQUE, actual REAL, note TEXT, payload BLOB); CREATE TABLE child(id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent(id), done INTEGER); CREATE INDEX child_parent ON child(parent_id); INSERT INTO parent VALUES(1,'synthetic-stable-id',NULL,'historical note',zeroblob(131072)); INSERT INTO child VALUES(2,1,0)")
                try check(try text(db, "PRAGMA journal_mode=WAL") == "wal", name + ": WAL mode set")
                var keep: Int32 = 0
                try check(sqlite3_file_control(db, "main", SQLITE_FCNTL_PERSIST_WAL, &keep) == SQLITE_OK, name + ": persistent WAL disabled")
                var frames: Int32 = -1, copied: Int32 = -1
                try check(sqlite3_wal_checkpoint_v2(db, "main", SQLITE_CHECKPOINT_TRUNCATE, &frames, &copied) == SQLITE_OK && frames == 0 && copied == 0, name + ": fully checkpointed")
            }
            let bytes = try Data(contentsOf: url)
            try check(bytes.count > 100 && bytes[18] == 2 && bytes[19] == 2, name + ": cold WAL header")
            try check(!manager.fileExists(atPath: url.path + "-wal") && !manager.fileExists(atPath: url.path + "-shm"), name + ": no sidecars")
            return url
        }
        func reject(_ label: String, _ action: () throws -> Void) throws {
            var threw = false
            do { try action() } catch { threw = true }
            try check(threw, label)
        }
        func append(_ url: URL) throws {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: Data([1]))
        }

        let source = try fixture("success")
        let bytes = try Data(contentsOf: source)
        let items = try manager.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        var temporary: URL?
        let value = try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(source, onPhase: { phase, folder in
            temporary = folder
            print("Initial snapshot phase: \(phase)")
            fflush(stdout)
        }) { db in
            try check(sqlite3_db_readonly(db, "main") == 1, "consumer receives readonly clone")
            try check(try text(db, "PRAGMA journal_mode") == "delete", "clone is independently readable")
            try check(try text(db, "PRAGMA integrity_check") == "ok", "clone integrity")
            try check(try text(db, "SELECT uuid || ':' || note || ':' || length(payload) || ':' || (actual IS NULL) FROM parent") == "synthetic-stable-id:historical note:131072:1", "fields and null preserved")
            try check(try text(db, "SELECT parent.uuid || ':' || child.done FROM child JOIN parent ON child.parent_id=parent.id") == "synthetic-stable-id:0", "relationship and incomplete flag preserved")
            try check(sqlite3_exec(db, "UPDATE parent SET note='must not write'", nil, nil, nil) != SQLITE_OK, "consumer cannot mutate snapshot")
            return 42
        }
        try check(value == 42, "consumer result returned after final verification")
        try check(try Data(contentsOf: source) == bytes, "source exact bytes retained")
        try check(try manager.contentsOfDirectory(atPath: source.deletingLastPathComponent().path) == items, "source directory unchanged")
        try check(temporary != nil && !manager.fileExists(atPath: temporary!.path), "owned snapshot cleaned after success")
        try CoachSQLiteReadSnapshot.withReadOnlySource(source) { db in
            try check(try text(db, "SELECT count(*) FROM parent") == "1", "automatic production cold routing")
        }
        try check(try Data(contentsOf: source) == bytes && !manager.fileExists(atPath: source.path + "-shm"), "automatic routing leaves original cold")

        for phase in [CoachSQLiteReadSnapshot.TestPhase.sourceValidated, .cloneCreated, .cloneOpened, .beforeCloneNormalization, .cloneNormalized, .beforeFinalVerification] {
            let url = try fixture("interrupt-\(checks)")
            let before = try Data(contentsOf: url)
            var staging: URL?
            try reject("injected interruption rejected") {
                try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(url, onPhase: { current, folder in
                    staging = folder
                    if current == phase { throw ProbeError.interrupted }
                }) { _ in }
            }
            try check(try Data(contentsOf: url) == before, "interruption retains source")
            try check(staging != nil && !manager.fileExists(atPath: staging!.path), "interruption cleans owned staging")
            try CoachSQLiteReadSnapshot.withReadOnlySource(url) { db in
                try check(try text(db, "SELECT count(*) FROM parent") == "1", "interruption retries without duplicate records")
            }
        }

        for phase in [CoachSQLiteReadSnapshot.TestPhase.cloneCreated, .beforeFinalVerification] {
            let url = try fixture("source-change-\(checks)")
            let before = try Data(contentsOf: url)
            var staging: URL?
            try reject("changed source rejects consumer result") {
                _ = try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(url, onPhase: { current, folder in
                    staging = folder
                    if current == phase { try append(url) }
                }) { _ in 99 }
            }
            try check(try Data(contentsOf: url) == before + Data([1]), "source mutation is never undone or overwritten")
            try check(staging != nil && !manager.fileExists(atPath: staging!.path), "source race staging cleaned")
        }

        let sidecar = try fixture("sidecar-arrival")
        try reject("new WAL rejects cold snapshot") {
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(sidecar, onPhase: { phase, _ in
                if phase == .cloneCreated { try Data("new writer".utf8).write(to: URL(fileURLWithPath: sidecar.path + "-wal")) }
            }) { _ in }
        }
        try check(manager.fileExists(atPath: sidecar.path + "-wal"), "new sidecar retained for recovery")

        let dangling = try fixture("dangling-sidecar")
        let danglingURL = URL(fileURLWithPath: dangling.path + "-shm")
        try manager.createSymbolicLink(at: danglingURL, withDestinationURL: root.appendingPathComponent("absent-target"))
        try reject("dangling sidecar is not absence") { try CoachSQLiteReadSnapshot.withColdSnapshot(dangling) { _ in } }
        try check((try? manager.destinationOfSymbolicLink(atPath: danglingURL.path)) != nil, "dangling sidecar is retained")

        let replace = try fixture("replaced-path")
        let originalBytes = try Data(contentsOf: replace)
        let moved = replace.deletingLastPathComponent().appendingPathComponent("retained-original.store")
        try reject("replaced source pathname rejected") {
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(replace, onPhase: { phase, _ in
                if phase == .cloneCreated {
                    try manager.moveItem(at: replace, to: moved)
                    try originalBytes.write(to: replace)
                }
            }) { _ in }
        }
        try check(try Data(contentsOf: moved) == originalBytes && Data(contentsOf: replace) == originalBytes, "both original and replacement retained")

        let corruptedClone = try fixture("clone-tamper")
        let intactBytes = try Data(contentsOf: corruptedClone)
        try reject("clone corruption rejected before normalization") {
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(corruptedClone, onPhase: { phase, folder in
                if phase == .cloneCreated { try Data("damaged copy".utf8).write(to: folder.appendingPathComponent("snapshot.store")) }
            }) { _ in }
        }
        try check(try Data(contentsOf: corruptedClone) == intactBytes, "clone tamper leaves source exact")

        let normalizedTamper = try fixture("normalized-tamper")
        let normalizedBefore = try Data(contentsOf: normalizedTamper)
        try reject("post-normalization clone changes rejected") {
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(normalizedTamper, onPhase: { phase, folder in
                if phase == .cloneNormalized {
                    try connection(folder.appendingPathComponent("snapshot.store"), SQLITE_OPEN_READWRITE) { db in
                        try execute(db, "UPDATE parent SET note='post-normalization tamper'")
                    }
                }
            }) { _ in }
        }
        try check(try Data(contentsOf: normalizedTamper) == normalizedBefore, "normalized clone tamper preserves original")

        for mutation in ["UPDATE parent SET note='changed'", "PRAGMA user_version=7", "CREATE TABLE unexpected(value TEXT)"] {
            let url = try fixture("logical-tamper-\(checks)")
            let before = try Data(contentsOf: url)
            try reject("logical normalization tamper rejected") {
                try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(url, onPhase: { phase, folder in
                    if phase == .beforeCloneNormalization {
                        try connection(folder.appendingPathComponent("snapshot.store"), SQLITE_OPEN_READWRITE) { db in try execute(db, mutation) }
                    }
                }) { _ in }
            }
            try check(try Data(contentsOf: url) == before, "logical tamper leaves original exact")
        }

        for hardlink in [true, false] {
            let url = try fixture("clone-link-\(hardlink)")
            let before = try Data(contentsOf: url)
            let originalMode = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
            try reject("clone cannot link to original") {
                try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(url, onPhase: { phase, folder in
                    if phase == .cloneCreated {
                        let clone = folder.appendingPathComponent("snapshot.store")
                        try manager.removeItem(at: clone)
                        if hardlink { try manager.linkItem(at: url, to: clone) }
                        else { try manager.createSymbolicLink(at: clone, withDestinationURL: url) }
                    }
                }) { _ in }
            }
            try check(try Data(contentsOf: url) == before, "linked clone does not change source bytes")
            try check(try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber == originalMode, "linked clone does not change source permissions")
        }

        let readOnly = try fixture("readonly-source")
        let readOnlyFolder = readOnly.deletingLastPathComponent()
        try manager.setAttributes([.posixPermissions: 0o400], ofItemAtPath: readOnly.path)
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnlyFolder.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnlyFolder.path) }
        let readOnlyBytes = try Data(contentsOf: readOnly)
        try CoachSQLiteReadSnapshot.withReadOnlySource(readOnly) { db in
            try check(try text(db, "SELECT count(*) FROM child") == "1", "readonly source and directory migrate via disposable clone")
        }
        try check(try Data(contentsOf: readOnly) == readOnlyBytes, "readonly original bytes retained")
        try check(try manager.attributesOfItem(atPath: readOnly.path)[.posixPermissions] as! NSNumber == 0o400, "readonly original mode retained")

        let truncated = try fixture("truncated")
        var truncatedBytes = try Data(contentsOf: truncated); truncatedBytes.removeLast(512)
        try truncatedBytes.write(to: truncated)
        try reject("incomplete WAL-format main file rejected") { try CoachSQLiteReadSnapshot.withReadOnlySource(truncated) { _ in } }
        try check(try Data(contentsOf: truncated) == truncatedBytes, "incomplete source retained")

        let linked = root.appendingPathComponent("linked.store")
        try manager.createSymbolicLink(at: linked, withDestinationURL: source)
        try reject("source link rejected") { try CoachSQLiteReadSnapshot.withReadOnlySource(linked) { _ in } }
        let fifo = root.appendingPathComponent("pipe.store")
        try check(mkfifo(fifo.path, 0o600) == 0, "FIFO fixture created")
        try reject("nonregular source fails without blocking") { try CoachSQLiteReadSnapshot.withReadOnlySource(fifo) { _ in } }

        let bodyFailure = try fixture("body-failure")
        let bodyBefore = try Data(contentsOf: bodyFailure)
        var bodyFolder: URL?
        try reject("consumer error propagated") {
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(bodyFailure, onPhase: { _, folder in bodyFolder = folder }) { _ in throw ProbeError.interrupted }
        }
        try check(try Data(contentsOf: bodyFailure) == bodyBefore && bodyFolder != nil && !manager.fileExists(atPath: bodyFolder!.path), "consumer failure preserves source and cleans snapshot")

        let cancelled = try fixture("task-cancelled")
        let cancelledBefore = try Data(contentsOf: cancelled)
        var cancelledFolder: URL?
        let cancellation = Task { @MainActor in
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(cancelled, onPhase: { phase, folder in
                cancelledFolder = folder
                if phase == .cloneOpened { withUnsafeCurrentTask { $0?.cancel() } }
            }) { _ in }
        }
        var cancellationObserved = false
        do { try await cancellation.value } catch is CancellationError { cancellationObserved = true }
        try check(cancellationObserved, "actual task cancellation is propagated")
        try check(try Data(contentsOf: cancelled) == cancelledBefore && cancelledFolder != nil && !manager.fileExists(atPath: cancelledFolder!.path), "task cancellation verifies source and cleans staging")

        let cancelledRace = try fixture("cancelled-source-race")
        let raceBefore = try Data(contentsOf: cancelledRace)
        let racingCancellation = Task { @MainActor in
            try CoachSQLiteReadSnapshot.withColdSnapshotForTesting(cancelledRace, onPhase: { phase, _ in
                if phase == .cloneNormalized {
                    try append(cancelledRace)
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }) { _ in }
        }
        var sourceRaceObserved = false
        do { try await racingCancellation.value }
        catch is CoachSQLiteReadSnapshot.SnapshotError { sourceRaceObserved = true }
        try check(sourceRaceObserved, "source race takes precedence over cancellation")
        try check(try Data(contentsOf: cancelledRace) == raceBefore + Data([1]), "cancelled source race is not overwritten")

        print("Cold SQLite snapshots: \(checks) checks passed; original files never opened for writes by production helper")
    }
}
