// File-copy integration test using the actual SQLite and external-asset copiers.
import Foundation
import SwiftData

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
        let support = source.deletingLastPathComponent().appendingPathComponent(".default_SUPPORT")
        let link = support.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let unsafe = try url("unsafe")
        do { try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: unsafe); fatalError("Expected symlink rejection") }
        catch { checks += 1 }
        print("Coach migration file copy: \(checks) checks passed")
    }
}
