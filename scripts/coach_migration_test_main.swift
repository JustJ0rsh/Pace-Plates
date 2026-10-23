// File-copy integration test using the actual SQLite and external-asset copiers.
import Foundation
import SwiftData
import SQLite3

@Model final class RouteMigrationProbe {
    var id: UUID = UUID()
    var date: Date = Date()
    var unit: String = "mi"
    var status: String = "partial"
    @Attribute(.externalStorage) var payload: Data = Data()
    @Relationship(deleteRule: .cascade, inverse: \ChildMigrationProbe.parent) var children: [ChildMigrationProbe]?
    init(_ payload: Data) { self.payload = payload }
}
@Model final class ChildMigrationProbe {
    var id: UUID = UUID()
    var value: Double? = nil
    var parent: RouteMigrationProbe?
    init(value: Double?) { self.value = value }
}
// The production copier's inventory references are irrelevant to these file
// boundary tests; the app's CoachPersistenceRegressionChecks tests real models.
typealias ExerciseDefinition = RouteMigrationProbe
typealias WorkoutSession = RouteMigrationProbe
typealias ExerciseLog = RouteMigrationProbe
typealias RunningSession = RouteMigrationProbe
typealias RunningPlan = RouteMigrationProbe
typealias RunningPlanSession = RouteMigrationProbe
typealias TrainingPlan = RouteMigrationProbe
typealias PlannedSession = RouteMigrationProbe
typealias WeightEntry = RouteMigrationProbe
typealias AIConversation = RouteMigrationProbe
typealias WorkoutTemplate = RouteMigrationProbe
typealias TemplateExercise = RouteMigrationProbe
typealias HealthWorkoutInboxItem = RouteMigrationProbe
typealias CardioWorkoutInboxItem = RouteMigrationProbe

@main struct MigrationTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coach-copy-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var checks = 0
        func check(_ value: Bool, _ description: String) { guard value else { fatalError(description) }; checks += 1 }
        func url(_ folder: String) throws -> URL {
            let directory = root.appendingPathComponent(folder, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(directory)
            return directory.appendingPathComponent("default.store")
        }
        let schema = Schema([RouteMigrationProbe.self, ChildMigrationProbe.self])
        func open(_ url: URL) throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration("Probe", schema: schema, url: url, cloudKitDatabase: .none)])
        }
        let source = try url("source"); let container = try open(source)
        let payload = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 41 &+ 123) })
        let row = RouteMigrationProbe(payload); row.date = Date(timeIntervalSince1970: 1_741_493_123)
        let child = ChildMigrationProbe(value: nil); child.parent = row
        container.mainContext.insert(row); container.mainContext.insert(child); try container.mainContext.save()
        check(FileManager.default.fileExists(atPath: source.path + "-wal"), "Writes are in WAL-backed live store")
        let destination = try url("destination")
        try CoachLocalOwnership.copyStore(from: source, to: destination)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: destination)
        let restored = try open(destination)
        let copy = try restored.mainContext.fetch(FetchDescriptor<RouteMigrationProbe>())[0]
        check(copy.id == row.id, "Stable UUID copied")
        check(copy.payload == payload, "External 2.5MB payload copied exactly")
        check(copy.date == row.date && copy.status == "partial" && copy.unit == "mi", "Historical date, status and unit")
        check(copy.children?.first?.id == child.id && copy.children?.first?.value == nil, "Relationship and unknown actual preserved")
        let reopened = try open(destination)
        check(try reopened.mainContext.fetch(FetchDescriptor<RouteMigrationProbe>())[0].payload == payload, "External payload survives relaunch")
        check(try container.mainContext.fetch(FetchDescriptor<RouteMigrationProbe>())[0].payload == payload, "Original remains readable")
        let partial = try url("partial")
        try CoachLocalOwnership.copyStore(from: source, to: partial)
        check(FileManager.default.fileExists(atPath: partial.path), "Interrupted unselected copy is separate")

        // Exercise the real cold reader and copier using this two-model
        // SwiftData probe graph plus external bytes, not only raw SQLite.
        let cold = try url("cold")
        try CoachLocalOwnership.copyStore(from: source, to: cold)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: cold)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(cold.path, &pointer, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let db = pointer else { fatalError("Cold fixture open failed") }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK else { fatalError("Cold fixture WAL failed") }
        var persist: Int32 = 0, frames: Int32 = -1, copied: Int32 = -1
        check(sqlite3_file_control(db, "main", SQLITE_FCNTL_PERSIST_WAL, &persist) == SQLITE_OK, "Cold fixture cleanup configured")
        check(sqlite3_wal_checkpoint_v2(db, "main", SQLITE_CHECKPOINT_TRUNCATE, &frames, &copied) == SQLITE_OK && frames == 0 && copied == 0, "Cold fixture fully checkpointed")
        check(sqlite3_close(db) == SQLITE_OK, "Cold fixture closed")
        let coldBytes = try Data(contentsOf: cold)
        check(coldBytes[18] == 2 && coldBytes[19] == 2 && !FileManager.default.fileExists(atPath: cold.path + "-wal") && !FileManager.default.fileExists(atPath: cold.path + "-shm"), "Closed WAL source has no sidecars")
        let coldCheckpoint = try CoachLocalOwnership.rawCheckpoint(cold)
        let coldDestination = try url("cold-destination")
        try CoachLocalOwnership.copyStore(from: cold, to: coldDestination)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: cold, to: coldDestination)
        let coldRestored = try open(coldDestination)
        let coldRows = try coldRestored.mainContext.fetch(FetchDescriptor<RouteMigrationProbe>())
        check(coldRows.count == 1 && coldRows[0].id == row.id, "Cold migration preserves stable ID once")
        check(coldRows[0].payload == payload, "Cold migration preserves full external payload")
        check(coldRows[0].date == row.date && coldRows[0].unit == row.unit && coldRows[0].status == row.status, "Cold migration preserves scalar values")
        check(coldRows[0].children?.first?.id == child.id && coldRows[0].children?.first?.value == nil, "Cold migration preserves relationship and missing actual")
        try CoachLocalOwnership.verifyRetainedColumns(coldCheckpoint, at: coldDestination)
        check(true, "Cold destination passes original raw field and asset verification")
        check(try Data(contentsOf: cold) == coldBytes, "Cold source bytes remain identical")
        check(!FileManager.default.fileExists(atPath: cold.path + "-wal") && !FileManager.default.fileExists(atPath: cold.path + "-shm"), "Cold source receives no sidecars")
        let retriedCold = try url("cold-retry")
        try CoachLocalOwnership.copyStore(from: cold, to: retriedCold)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: cold, to: retriedCold)
        let retryContainer = try open(retriedCold)
        check(try retryContainer.mainContext.fetchCount(FetchDescriptor<RouteMigrationProbe>()) == 1, "Cold copy retry does not duplicate records")
        check(try CoachLocalOwnership.rawCheckpoint(cold).identity == coldCheckpoint.identity, "Cold source records and external asset digest remain exact")
        let support = source.deletingLastPathComponent().appendingPathComponent(".default_SUPPORT")
        let link = support.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let unsafe = try url("unsafe")
        do { try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: unsafe); fatalError("Expected symlink rejection") }
        catch { checks += 1 }
        print("Coach migration file copy: \(checks) checks passed")
    }
}
