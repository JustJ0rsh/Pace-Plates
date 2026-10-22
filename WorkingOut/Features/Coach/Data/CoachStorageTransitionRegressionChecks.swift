#if DEBUG
import Foundation
import HealthKit
import SwiftData

@MainActor
enum CoachStorageTransitionRegressionChecks {
    private final class Gate {
        private var suspended: CheckedContinuation<Void, Never>?
        private var observer: CheckedContinuation<Void, Never>?
        func pause() async {
            await withCheckedContinuation { continuation in
                suspended = continuation
                observer?.resume(); observer = nil
            }
        }
        func waitForPause() async {
            if suspended != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func resume() { suspended?.resume(); suspended = nil }
    }

    static func run() async throws -> Int {
        precondition(AppLaunchConfiguration.current.isUITest)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CoachStorageTransitionChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) {
            count += 1
            if !condition { failures.append(message) }
        }
        func makeStore(_ name: String, coach: Bool = false) throws -> (PersistenceController, ModelContainer, URL) {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(folder)
            let schema = coach ? PersistenceController.coachSchema : Schema(PersistenceController.legacyModelTypes)
            let source = try ModelContainer(for: schema, configurations: [ModelConfiguration(coach ? CoachPersistence.configurationName : "LegacyFixture",
                schema: schema, url: folder.appendingPathComponent("source.store"), cloudKitDatabase: .none)])
            source.mainContext.insert(WeightEntry(date: Date(timeIntervalSince1970: 1_700_000_000), weight: 75, weightUnit: "kg"))
            try source.mainContext.save()
            return (PersistenceController(sourceStoreForRegression: source), source, folder.appendingPathComponent("selected/default.store"))
        }
        func adopt(_ controller: PersistenceController, _ destination: URL) async throws {
            try await controller.adoptForStorageRegression(destination: destination) { selected, _ in
                // The exact production adoption path commits only this disposable marker.
                try Data(selected.lastPathComponent.utf8).write(to: destination.deletingLastPathComponent().appendingPathComponent("selected.txt"), options: .atomic)
            }
        }
        func digest(_ container: ModelContainer) throws -> String {
            try CoachLocalOwnership.snapshotDigest(ModelContext(container))
        }
        func workout(_ type: HKWorkoutActivityType) -> HKWorkout {
            let start = Date(timeIntervalSince1970: 1_900_000_000)
            return HKWorkout(activityType: type, start: start, end: start.addingTimeInterval(60), duration: 60,
                totalEnergyBurned: nil, totalDistance: HKQuantity(unit: .meter(), doubleValue: 100), metadata: nil)
        }
        func changes(_ workout: HKWorkout? = nil) -> HealthKitManager.CardioWorkoutChanges {
            .init(added: workout.map { [$0] } ?? [], deleted: [], newAnchor: HKQueryAnchor(fromValue: 7))
        }

        // Suspend the actual strength import pipeline before its synthetic query returns.
        do {
            let (controller, source, destination) = try makeStore("strength")
            let before = try digest(source)
            let generation = WearableWorkoutInboxService.localDataPurgeGeneration
            let gate = Gate(); var anchors = 0; var reads = 0
            let batch = changes(workout(.traditionalStrengthTraining))
            let pending = Task { @MainActor in
                await WearableWorkoutInboxService.syncForStorageRegression(context: source.mainContext,
                    fetchChanges: { reads += 1; await gate.pause(); return batch }, persistAnchor: { _ in anchors += 1 })
            }
            await gate.waitForPause()
            try await adopt(controller, destination)
            gate.resume(); _ = await pending.value
            check(!WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation), "strength: switch invalidates suspended epoch")
            check(try digest(source) == before, "strength: suspended result cannot write legacy history")
            check(try digest(controller.container) == before, "strength: selected copy preserves pre-import history")
            check(anchors == 0, "strength: canceled result cannot advance anchor")
            _ = await WearableWorkoutInboxService.syncForStorageRegression(context: source.mainContext,
                fetchChanges: { reads += 1; return batch }, persistAnchor: { _ in anchors += 1 })
            check(reads == 1 && anchors == 0, "strength: new operation on retired context stops before query")
            let priorAnchors = anchors
            for _ in 0..<2 {
                _ = await WearableWorkoutInboxService.syncForStorageRegression(context: controller.container.mainContext,
                    fetchChanges: { batch }, persistAnchor: { _ in anchors += 1 })
            }
            check(try controller.container.mainContext.fetchCount(FetchDescriptor<HealthWorkoutInboxItem>()) == 1 && anchors == priorAnchors + 2,
                  "strength: unconsumed batch retries idempotently on selected storage")
        }

        // Authorization, initial query, and metric detail are separate suspension points.
        for stage in ["authorization", "query", "details"] {
            let (controller, source, destination) = try makeStore("cardio-" + stage)
            let before = try digest(source)
            let gate = Gate(); var anchors = 0; var reads = 0
            let batch = changes(workout(.running))
            var authorize: (@MainActor () async throws -> Void)? = nil
            if stage == "authorization" { authorize = { await gate.pause() } }
            var beforeDetails: (@MainActor () async -> Void)? = nil
            if stage == "details" { beforeDetails = { await gate.pause() } }
            let pending = Task<CardioWorkoutInboxService.SyncResult, Never> { @MainActor in
                await CardioWorkoutInboxService.syncForStorageRegression(context: source.mainContext,
                    authorize: authorize,
                    fetchChanges: { reads += 1; if stage == "query" { await gate.pause() }; return batch },
                    beforeDetails: beforeDetails,
                    persistAnchor: { _ in anchors += 1 })
            }
            await gate.waitForPause()
            if stage == "details" {
                let pendingCount = try source.mainContext.fetchCount(FetchDescriptor<CardioWorkoutInboxItem>())
                check(!source.mainContext.hasChanges && pendingCount == 0,
                      "cardio details: pending candidate is isolated from the autosaving source before selection")
            }
            try await adopt(controller, destination)
            gate.resume(); _ = await pending.value
            check(try digest(source) == before, "cardio \(stage): suspended result cannot write legacy history or autosave a partial page")
            check(try digest(controller.container) == before, "cardio \(stage): selected copy preserves pre-import history")
            check(anchors == 0, "cardio \(stage): canceled result cannot advance anchor")
            let priorReads = reads
            _ = await CardioWorkoutInboxService.syncForStorageRegression(context: source.mainContext,
                fetchChanges: { reads += 1; return batch }, persistAnchor: { _ in anchors += 1 })
            check(reads == priorReads && anchors == 0, "cardio \(stage): new operation on retired context stops before query")
            if stage == "authorization" { check(reads == 0, "cardio: authorization completion cannot recapture a valid epoch on retired storage") }
            let priorAnchors = anchors
            for _ in 0..<2 {
                _ = await CardioWorkoutInboxService.syncForStorageRegression(context: controller.container.mainContext,
                    fetchChanges: { batch }, persistAnchor: { _ in anchors += 1 })
            }
            check(try controller.container.mainContext.fetchCount(FetchDescriptor<CardioWorkoutInboxItem>()) == 1 && anchors == priorAnchors + 2,
                  "cardio \(stage): selected storage accepts idempotent retry")
        }

        do {
            let (controller, source, destination) = try makeStore("weight", coach: true)
            let before = try digest(source)
            let gate = Gate(); var anchors = 0; var reads = 0
            let sample = CoachHealthWeightSample(id: UUID().uuidString, observedAt: Date(), kilograms: 80, sourceName: "Synthetic source")
            let pending = Task { @MainActor in
                do {
                    return try await CoachWeightRepository.importForStorageRegression(context: source.mainContext,
                        fetchChanges: { reads += 1; await gate.pause(); return ([sample], [], HKQueryAnchor(fromValue: 7)) },
                        persistAnchor: { _ in anchors += 1 })
                } catch is CancellationError { return 0 }
            }
            await gate.waitForPause()
            try await adopt(controller, destination)
            gate.resume(); _ = try await pending.value
            check(try digest(source) == before, "weight: suspended result cannot write retired history")
            check(try digest(controller.container) == before, "weight: selected copy preserves pre-import history")
            check(anchors == 0, "weight: canceled result cannot advance anchor")
            do {
                _ = try await CoachWeightRepository.importForStorageRegression(context: source.mainContext,
                    fetchChanges: { reads += 1; return ([sample], [], nil) }, persistAnchor: { _ in anchors += 1 })
            } catch is CancellationError { }
            check(reads == 1 && anchors == 0, "weight: new operation on retired context stops before query")
            let priorAnchors = anchors
            for _ in 0..<2 {
                _ = try await CoachWeightRepository.importForStorageRegression(context: controller.container.mainContext,
                    fetchChanges: { ([sample], [], HKQueryAnchor(fromValue: 7)) }, persistAnchor: { _ in anchors += 1 })
            }
            check(try controller.container.mainContext.fetchCount(FetchDescriptor<WeightEntry>()) == 2 && anchors == priorAnchors + 2,
                  "weight: selected storage retains legacy row and one exact-ID observation after retry")
        }

        // Failed selection cannot retire a valid source or invalidate unrelated work.
        do {
            let (controller, source, destination) = try makeStore("failed-selection")
            let generation = WearableWorkoutInboxService.localDataPurgeGeneration
            do {
                try await controller.adoptForStorageRegression(destination: destination) { _, _ in
                    throw CoachRepositoryError.invalidValue("synthetic marker failure")
                }
                failures.append("failed selection unexpectedly succeeded")
            } catch CoachRepositoryError.invalidValue { count += 1 }
            check(!controller.isCoachLocal && controller.container === source,
                  "failed selection keeps original container selected")
            check(WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation, context: source.mainContext),
                  "failed selection leaves source writable and epoch unchanged")
        }
        if !failures.isEmpty {
            throw CoachRepositoryError.invalidValue("storage transition regression: " + failures.joined(separator: "; "))
        }
        return count
    }
}
#endif
