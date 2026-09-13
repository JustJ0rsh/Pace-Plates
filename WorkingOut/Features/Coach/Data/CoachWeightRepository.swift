import Foundation
import SwiftData
import HealthKit

struct CoachHealthWeightSample: Sendable {
    let id: String
    let observedAt: Date
    let kilograms: Double
    let sourceName: String
}

@MainActor
enum CoachWeightRepository {
    private static var anchorURL: URL { CoachPersistence.directory.appendingPathComponent("weight-anchor.data") }

    /// A UUID identifies a Health observation. Multiple observations on a day
    /// remain separate, and exact Health deletion IDs remove only their copy.
    static func importHealth(context: ModelContext, preferredUnit: String = "kg") async throws -> Int {
        guard CoachPersistence.isLocal(context) else { throw CoachRepositoryError.localOwnershipRequired }
        guard HKHealthStore.isHealthDataAvailable(), let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 0 }
        let generation = WearableWorkoutInboxService.localDataPurgeGeneration
        let cutoff = WearableWorkoutInboxService.localDataPurgeCutoffDate
        let store = HKHealthStore()
        try await store.requestAuthorization(toShare: [], read: [type])
        let anchor: HKQueryAnchor? = (try? Data(contentsOf: anchorURL)).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
        let result: ([CoachHealthWeightSample], [String], HKQueryAnchor?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, added, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                let samples = (added as? [HKQuantitySample] ?? []).map {
                    CoachHealthWeightSample(id: $0.uuid.uuidString, observedAt: $0.endDate,
                                            kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), sourceName: $0.sourceRevision.source.name)
                }
                continuation.resume(returning: (samples, (deleted ?? []).map { $0.uuid.uuidString }, nextAnchor))
            }
            store.execute(query)
        }
        try Task.checkCancellation()
        guard WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation) else { throw CancellationError() }
        let isolated = ModelContext(context.container); isolated.autosaveEnabled = false
        do {
            let records = try isolated.fetch(FetchDescriptor<WeightEntry>())
            var bySource: [String: WeightEntry] = [:]
            for record in records { if let source = record.sourceHealthSampleID { bySource[source] = record } }
            for id in result.1 { if let record = bySource.removeValue(forKey: id) { isolated.delete(record) } }
            var count = 0
            for sample in result.0 where cutoff.map({ sample.observedAt > $0 }) ?? true {
                guard sample.kilograms.isFinite && sample.kilograms > 0 else { continue }
                let record: WeightEntry
                if let existing = bySource[sample.id] { record = existing }
                else {
                    // Legacy rows have unknown provenance. Equal timestamp/value
                    // is insufficient evidence to attach a Health deletion identity.
                    record = WeightEntry(date: sample.observedAt, weight: sample.kilograms, weightUnit: preferredUnit)
                    isolated.insert(record)
                    bySource[sample.id] = record; count += 1
                }
                record.date = sample.observedAt; record.weightUnit = UnitConverter.canonicalWeightUnit(preferredUnit)
                record.weight = UnitConverter.weight(sample.kilograms, from: "kg", to: record.weightUnit)
                record.sourceHealthSampleID = sample.id; record.sourceName = sample.sourceName; record.provenance = "health"
            }
            try isolated.save()
            if let next = result.2 {
                try CoachPersistence.protect(CoachPersistence.directory, isDirectory: true)
                try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true).write(to: anchorURL, options: [.atomic, .completeFileProtectionUnlessOpen])
                try CoachPersistence.protect(anchorURL)
            }
            return count
        } catch { isolated.rollback(); throw error }
    }

    static func removeAnchorAfterPurge() throws {
        if FileManager.default.fileExists(atPath: anchorURL.path) { try FileManager.default.removeItem(at: anchorURL) }
    }
}

extension CoachRepository {
    @discardableResult
    func importHealthWeights(preferredUnit: String = "kg") async throws -> Int {
        try await CoachWeightRepository.importHealth(context: context, preferredUnit: preferredUnit)
    }
}
