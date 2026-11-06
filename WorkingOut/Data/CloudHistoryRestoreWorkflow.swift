import Foundation
import CloudKit

/// Automatic inspection is read-only. Missing records are restored only by a
/// one-use authorization of the exact reviewed identities and retained payloads.
@MainActor
enum CloudHistoryRestoreWorkflow {
    struct Identity: Equatable { let store: String; let account: String }
    enum Saved { case created, concurrentExisting }
    struct Dependencies {
        var identity: @MainActor () async throws -> Identity
        var records: @MainActor ([CKRecord.ID]) async throws -> [CKRecord]
        var presence: @MainActor ([CKRecord.ID]) async throws -> Set<CKRecord.ID>
        var save: @MainActor ([CKRecord]) async throws -> [CKRecord.ID: Saved]
        var check: @MainActor () throws -> Void = { try Task.checkCancellation() }
    }
    struct Outcome {
        var created = 0
        var concurrentExisting = 0
        var present = 0
        var missing = 0
        var attempted = false
        var initialPresent = 0
        var initialMissing = 0
        var review: CloudHistoryRestoreReview?
    }

    static func run(localIDs: [CKRecord.ID], identity: Identity, store: any CloudHistoryRestorePlanStoring,
                    dependencies: Dependencies) async throws -> Outcome {
        var outcome = Outcome()
        try dependencies.check()
        guard try await dependencies.identity() == identity else { throw CloudHistoryRestoreError.accountOrStoreChanged }
        let initialPresent = try await dependencies.presence(localIDs)
        guard initialPresent.isSubset(of: Set(localIDs)) else { throw CloudHistoryRestoreError.incompleteResponse }
        outcome.initialPresent = initialPresent.count
        outcome.initialMissing = localIDs.count - initialPresent.count
        let plan = try store.plan(), authorization = try store.authorization()
        if let authorization, authorization.state == .pending {
            var consumed = false
            do {
                guard let plan, plan.review.id == authorization.reviewID else { throw CloudHistoryRestoreError.invalidReview }
                try plan.validate()
                guard plan.storeIdentifier == identity.store, plan.accountFingerprint == identity.account else {
                    throw CloudHistoryRestoreError.accountOrStoreChanged
                }
                let approved = plan.records.map(\.recordID)
                guard Set(approved).isSubset(of: Set(localIDs)) else { throw CloudHistoryRestoreError.snapshotChanged }
                let payloads = try await dependencies.records(approved)
                try validate(payloads, expected: approved)
                guard try CloudHistoryCloudRecordEncoder.fingerprint(payloads) == plan.payloadFingerprint else {
                    throw CloudHistoryRestoreError.snapshotChanged
                }
                try dependencies.check()
                guard try await dependencies.identity() == identity else { throw CloudHistoryRestoreError.accountOrStoreChanged }
                let existing = try await dependencies.presence(approved)
                guard existing.isSubset(of: Set(approved)) else { throw CloudHistoryRestoreError.incompleteResponse }
                // A durable consumed receipt is mandatory even if no write is
                // needed. Interruptions cannot replay this restoration later.
                try store.consume(reviewID: plan.review.id)
                consumed = true
                outcome.attempted = true
                let missingPayloads = oldestFirst(payloads.filter { !existing.contains($0.recordID) })
                for offset in stride(from: 0, to: missingPayloads.count, by: 100) {
                    let batch = Array(missingPayloads[offset..<min(offset + 100, missingPayloads.count)])
                    try dependencies.check()
                    guard try await dependencies.identity() == identity else { throw CloudHistoryRestoreError.accountOrStoreChanged }
                    let saved = try await dependencies.save(batch)
                    guard Set(saved.keys) == Set(batch.map(\.recordID)) else { throw CloudHistoryRestoreError.incompleteResponse }
                    for result in saved.values {
                        switch result {
                        case .created: outcome.created += 1
                        case .concurrentExisting: outcome.concurrentExisting += 1
                        }
                    }
                }
            } catch {
                if !consumed { try? store.reject(reviewID: authorization.reviewID) }
                throw error
            }
        }

        try dependencies.check()
        guard try await dependencies.identity() == identity else { throw CloudHistoryRestoreError.accountOrStoreChanged }
        let present = outcome.attempted ? try await dependencies.presence(localIDs) : initialPresent
        guard present.isSubset(of: Set(localIDs)) else { throw CloudHistoryRestoreError.incompleteResponse }
        let missing = localIDs.filter { !present.contains($0) }
        outcome.present = present.count; outcome.missing = missing.count
        if !missing.isEmpty {
            let records = try await dependencies.records(missing)
            try validate(records, expected: missing)
            let fingerprint = try CloudHistoryCloudRecordEncoder.fingerprint(records)
            var counts: [String: Int] = [:], dates: [Date] = []
            for record in records {
                let entity = record["CD_entityName"] as? String ?? "Other history"
                counts[entity, default: 0] += 1
                if let date = record["CD_date"] as? Date { dates.append(date) }
            }
            let review = CloudHistoryRestoreReview(id: UUID(), recordCount: records.count, entityCounts: counts,
                earliestDate: dates.min(), latestDate: dates.max(), createdAt: Date())
            let next = CloudHistoryRestorePlan(version: 1, review: review, storeIdentifier: identity.store,
                accountFingerprint: identity.account, records: missing.map(CloudHistoryRestorePlan.RecordIdentity.init), payloadFingerprint: fingerprint)
            try dependencies.check()
            guard try await dependencies.identity() == identity else { throw CloudHistoryRestoreError.accountOrStoreChanged }
            try store.save(next)
            outcome.review = review
        } else { try store.clearReview() }
        try store.finishInspection()
        return outcome
    }

    // These are the app-controlled uploads; Core Data controls automatic downloads.
    // Undated records follow dated records, with stable ordering for equal dates.
    private static func oldestFirst(_ records: [CKRecord]) -> [CKRecord] {
        func date(_ record: CKRecord) -> Date? {
            for key in ["CD_date", "CD_startDate", "CD_startedAt", "CD_createdAt"] {
                if let value = record[key] as? Date { return value }
            }
            return nil
        }
        return records.sorted { lhs, rhs in
            switch (date(lhs), date(rhs)) {
            case let (left?, right?) where left != right: return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                let left = lhs.recordID, right = rhs.recordID
                if left.zoneID.ownerName != right.zoneID.ownerName { return left.zoneID.ownerName < right.zoneID.ownerName }
                if left.zoneID.zoneName != right.zoneID.zoneName { return left.zoneID.zoneName < right.zoneID.zoneName }
                return left.recordName < right.recordName
            }
        }
    }

    private static func validate(_ records: [CKRecord], expected: [CKRecord.ID]) throws {
        guard records.count == expected.count, Set(records.map(\.recordID)) == Set(expected),
              records.allSatisfy({ $0.recordChangeTag == nil }) else { throw CloudHistoryRestoreError.snapshotChanged }
    }
}
