#if DEBUG
import SwiftUI
import SwiftData

/// Exercised only by the explicit UI-test fixture, using independent local stores.
@MainActor
struct OptimizationRegressionChecksView: View {
    @State private var result = "Checking optimizations…"

    var body: some View {
        Text(result).accessibilityIdentifier("optimization.checks")
            .task {
                do {
                    try await runChecks()
                    result = "Optimization checks passed"
                } catch {
                    result = "Optimization checks failed: \(error.localizedDescription)"
                }
            }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "OptimizationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private func runChecks() async throws {
        let source = PersistenceController(inMemory: true, cloudKitMode: .none)
        let context = source.container.mainContext
        let now = Date()
        for index in 0..<151 {
            context.insert(RunningSession(date: now.addingTimeInterval(Double(-index) * 86_400),
                distance: 1, distanceUnit: "mi", duration: 3600,
                notes: index == 150 ? "oldest needle" : nil,
                activityType: index == 1 ? "cycling" : "running"))
        }
        try context.save()
        let first = try RunHistoryStore.fetch(context: context, search: "", range: .all, activity: nil, limit: 30, now: now)
        let next = try RunHistoryStore.fetch(context: context, search: "", range: .all, activity: nil, limit: 60, now: now)
        try require(first.sessions.count == 30 && first.matchingCount == 151, "first database page")
        try require(next.sessions.count == 60 && Set(first.sessions.map(\.id)).isSubset(of: Set(next.sessions.map(\.id))), "expanded database page")
        let oldest = try RunHistoryStore.fetch(context: context, search: "needle", range: .all, activity: nil, limit: 30, now: now)
        try require(oldest.sessions.count == 1 && oldest.sessions[0].notes == "oldest needle", "search beyond loaded page")
        let cycle = try RunHistoryStore.fetch(context: context, search: "Cycle", range: .all, activity: nil, limit: 30, now: now)
        try require(cycle.matchingCount == 1, "display-name search")
        let recent = try RunHistoryStore.fetch(context: context, search: "", range: .days30, activity: nil, limit: 100, now: now)
        try require(recent.matchingCount == 30, "date filter")

        let export = try await DataBackupService.exportAll(context: context)
        defer { try? FileManager.default.removeItem(at: export) }
        let target = PersistenceController(inMemory: true, cloudKitMode: .none)
        try await DataBackupService.import(from: export, context: target.container.mainContext)
        try await DataBackupService.import(from: export, context: target.container.mainContext)
        let restored = try target.container.mainContext.fetch(FetchDescriptor<RunningSession>())
        let sourceIDs = Set(try context.fetch(FetchDescriptor<RunningSession>()).map(\.id))
        try require(restored.count == 151 && Set(restored.map(\.id)) == sourceIDs, "backup round trip and repeat import")

        let coordinates = [
            RunCoordinate(latitude: 0, longitude: 0, timestamp: now),
            RunCoordinate(latitude: 0, longitude: 0.0001, timestamp: now.addingTimeInterval(1)),
            RunCoordinate(latitude: 0, longitude: 0.0002, timestamp: now.addingTimeInterval(101))
        ]
        let route = RouteRenderPreparation.make(from: try JSONEncoder().encode(coordinates), duration: 101)
        try require(route.segments.map(\.pace) == [.run, .walk], "route speed uses irregular timestamps")
        let legacy = coordinates.map { RunCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let neutral = RouteRenderPreparation.make(from: try JSONEncoder().encode(legacy), duration: 101)
        try require(neutral.segments.allSatisfy { $0.pace == .unknown }, "legacy route does not invent pace")

        let recoveryURL = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryChecks-\(UUID())/run.json")
        defer { try? FileManager.default.removeItem(at: recoveryURL.deletingLastPathComponent()) }
        let recovery = RunRecoveryStore(url: recoveryURL)
        let snapshot = RunRecoverySnapshot(sessionID: UUID(), startDate: now, duration: 12,
            distanceMeters: 42, distanceUnit: "mi", activityType: "walking", plannedTarget: nil, points: [])
        recovery.save(snapshot)
        let loaded = await recovery.load()
        try require(loaded?.sessionID == snapshot.sessionID && loaded?.duration == 12, "ordered checkpoint write and read")
        recovery.clear()
        let cleared = await recovery.load()
        try require(cleared == nil, "discard removes checkpoint")

        source.reconcileExerciseLibraryIfNeeded(force: true)
        let definitions = try context.fetchCount(FetchDescriptor<ExerciseDefinition>())
        source.reconcileExerciseLibraryIfNeeded()
        let after = try context.fetchCount(FetchDescriptor<ExerciseDefinition>())
        try require(!context.hasChanges && after == definitions, "unchanged launch maintenance")
    }
}
#endif
