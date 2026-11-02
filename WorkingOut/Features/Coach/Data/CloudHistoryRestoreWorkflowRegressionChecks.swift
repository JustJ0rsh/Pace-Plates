#if DEBUG
import Foundation
import CloudKit

@MainActor
enum CloudHistoryRestoreWorkflowRegressionChecks {
    private final class MemoryStore: CloudHistoryRestorePlanStoring {
        var review: CloudHistoryRestorePlan?
        var permission: CloudHistoryRestoreAuthorization?
        var receiptsLocked = false
        var consumed: [UUID] = []
        func plan() throws -> CloudHistoryRestorePlan? { review }
        func authorization() throws -> CloudHistoryRestoreAuthorization? { permission }
        func save(_ plan: CloudHistoryRestorePlan) throws { review = plan }
        func approve() {
            permission = .init(version: 1, reviewID: review!.review.id, state: .pending, updatedAt: Date())
        }
        func consume(reviewID: UUID) throws {
            guard !receiptsLocked else { throw CloudHistoryRestoreError.receiptUnavailable }
            guard permission?.reviewID == reviewID, permission?.state == .pending else { throw CloudHistoryRestoreError.authorizationUnavailable }
            permission = .init(version: 1, reviewID: reviewID, state: .consumed, updatedAt: Date())
            consumed.append(reviewID)
        }
        func reject(reviewID: UUID) throws {
            guard !receiptsLocked else { throw CloudHistoryRestoreError.receiptUnavailable }
            permission = .init(version: 1, reviewID: reviewID, state: .rejected, updatedAt: Date())
        }
        func clearReview() throws { review = nil; permission = nil }
        func finishInspection() throws {}
    }

    private final class Server {
        var identity = CloudHistoryRestoreWorkflow.Identity(store: "10000000-0000-0000-0000-000000000001", account: String(repeating: "a", count: 64))
        var local: [CKRecord.ID: CKRecord] = [:]
        var remote: [CKRecord.ID: CKRecord] = [:]
        var saved: [CKRecord.ID] = []
        var presenceCalls = 0
        var beforePresence: ((Int) -> Void)?
        var beforeSave: (() -> Void)?
        var failAfterFirstSave = false

        func dependencies(store: MemoryStore) -> CloudHistoryRestoreWorkflow.Dependencies {
            .init(identity: { self.identity }, records: { requested in
                try requested.map { id in
                    guard let record = self.local[id] else { throw CloudHistoryRestoreError.snapshotChanged }
                    return record
                }
            }, presence: { requested in
                self.presenceCalls += 1
                self.beforePresence?(self.presenceCalls)
                return Set(requested.filter { self.remote[$0] != nil })
            }, save: { records in
                guard store.permission?.state == .consumed else { throw CloudHistoryRestoreError.authorizationUnavailable }
                self.beforeSave?()
                var result: [CKRecord.ID: CloudHistoryRestoreWorkflow.Saved] = [:]
                for record in records {
                    if self.remote[record.recordID] != nil { result[record.recordID] = .concurrentExisting }
                    else {
                        self.remote[record.recordID] = record
                        self.saved.append(record.recordID)
                        result[record.recordID] = .created
                        if self.failAfterFirstSave { self.failAfterFirstSave = false; throw CloudHistoryRestoreError.incompleteResponse }
                    }
                }
                return result
            })
        }
    }

    static func run() async throws -> Int {
        var checks = 0
        func require(_ value: Bool, _ reason: String) throws {
            checks += 1
            guard value else { throw CloudHistoryRestoreError.invalidReview }
        }
        func record(_ name: String, weight: Double = 70) -> CKRecord {
            let row = CKRecord(recordType: "CD_WeightEntry", recordID: .init(recordName: name))
            row["CD_entityName"] = "WeightEntry" as NSString
            row["CD_weight"] = weight as NSNumber
            row["CD_date"] = Date(timeIntervalSince1970: 1_700_000_000) as NSDate
            return row
        }
        func inspect(_ server: Server, _ store: MemoryStore) async throws -> CloudHistoryRestoreWorkflow.Outcome {
            try await CloudHistoryRestoreWorkflow.run(localIDs: Array(server.local.keys), identity: server.identity,
                store: store, dependencies: server.dependencies(store: store))
        }
        func candidate(_ names: [String] = ["old-a"]) async throws -> (Server, MemoryStore) {
            let server = Server(), store = MemoryStore()
            for name in names { let row = record(name); server.local[row.recordID] = row }
            _ = try await inspect(server, store)
            return (server, store)
        }
        func rejected(_ server: Server, _ store: MemoryStore, _ reason: String) async throws {
            var rejected = false
            do { _ = try await inspect(server, store) } catch { rejected = true }
            try require(rejected && server.saved.isEmpty, reason)
        }

        let race = Server(), raceStore = MemoryStore()
        let deleted = record("deleted-on-other-device"), kept = record("kept", weight: 90)
        race.local = [deleted.recordID: deleted, kept.recordID: kept]
        race.remote = race.local
        race.beforePresence = { call in if call == 1 { race.remote.removeValue(forKey: deleted.recordID) } }
        let review = try await inspect(race, raceStore)
        try require(race.saved.isEmpty && race.remote[deleted.recordID] == nil,
                    "automatic inspection never resurrects a deletion between inventory and presence")
        try require(review.review?.recordCount == 1 && raceStore.review?.records.map(\.recordID) == [deleted.recordID],
                    "the exact missing record is retained for explicit review")
        try require(race.remote[kept.recordID]?["CD_weight"] as? Double == 90,
                    "unchanged existing server rows survive inspection")

        raceStore.approve()
        let originalReviewID = raceStore.review!.review.id
        let newMissing = record("new-unapproved-missing")
        race.local[newMissing.recordID] = newMissing
        race.remote.removeValue(forKey: kept.recordID)
        let restored = try await inspect(race, raceStore)
        try require(Set(race.saved) == [deleted.recordID] && restored.created == 1,
                    "explicit restoration saves only the exact reviewed set")
        try require(race.remote[kept.recordID] == nil && race.remote[newMissing.recordID] == nil,
                    "new remote deletions and newly missing local IDs never join an approved batch")
        try require(raceStore.consumed == [originalReviewID] && restored.review?.id != originalReviewID && restored.review?.recordCount == 2,
                    "authorization is consumed before writes and remaining records require a new review")
        race.remote.removeValue(forKey: deleted.recordID)
        _ = try await inspect(race, raceStore)
        try require(race.saved.count == 1 && race.remote[deleted.recordID] == nil,
                    "the next launch cannot reuse consumed permission to recreate records again")

        for change in ["account", "store", "payload", "removed-local"] {
            let (server, store) = try await candidate()
            store.approve()
            switch change {
            case "account": server.identity = .init(store: server.identity.store, account: String(repeating: "b", count: 64))
            case "store": server.identity = .init(store: "20000000-0000-0000-0000-000000000002", account: server.identity.account)
            case "payload": server.local.values.first!["CD_weight"] = 80 as NSNumber
            default: server.local.removeAll()
            }
            try await rejected(server, store, "changed \(change) rejects before any network save")
            try require(store.permission?.state == .rejected, "rejected review cannot remain queued for later automatic use")
        }

        let (canceled, canceledStore) = try await candidate()
        canceledStore.approve()
        canceledStore.permission = .init(version: 1, reviewID: canceledStore.review!.review.id, state: .canceled, updatedAt: Date())
        _ = try await inspect(canceled, canceledStore)
        try require(canceled.saved.isEmpty, "a canceled authorization permits inspection only")
        let (cancelTask, cancelTaskStore) = try await candidate()
        cancelTaskStore.approve()
        var canceledDependencies = cancelTask.dependencies(store: cancelTaskStore)
        canceledDependencies.check = { throw CancellationError() }
        var taskRejected = false
        do {
            _ = try await CloudHistoryRestoreWorkflow.run(localIDs: Array(cancelTask.local.keys), identity: cancelTask.identity,
                store: cancelTaskStore, dependencies: canceledDependencies)
        } catch is CancellationError { taskRejected = true }
        try require(taskRejected && cancelTask.saved.isEmpty, "a canceled invocation never starts saving")
        let (locked, lockedStore) = try await candidate()
        lockedStore.approve(); lockedStore.receiptsLocked = true
        try await rejected(locked, lockedStore, "a locked consumption receipt blocks every network save")
        try require(lockedStore.consumed.isEmpty, "failed durable consumption cannot be treated as permission")

        let (partial, partialStore) = try await candidate(["partial-a", "partial-b"])
        partialStore.approve()
        let partialReviewID = partialStore.review!.review.id
        partial.failAfterFirstSave = true
        var interrupted = false
        do { _ = try await inspect(partial, partialStore) } catch { interrupted = true }
        try require(interrupted && partial.saved.count == 1 && partialStore.permission?.state == .consumed,
                    "a partial save leaves a durable consumed authorization")
        let afterPartial = try await inspect(partial, partialStore)
        try require(partial.saved.count == 1 && afterPartial.review?.recordCount == 1 && afterPartial.review?.id != partialReviewID,
                    "interruption requires fresh review of the remainder instead of automatic recreation")

        let (concurrent, concurrentStore) = try await candidate()
        concurrentStore.approve()
        let approvedID = concurrent.local.keys.first!
        concurrent.beforeSave = { concurrent.remote[approvedID] = record("old-a", weight: 99) }
        let concurrentResult = try await inspect(concurrent, concurrentStore)
        try require(concurrentResult.concurrentExisting == 1 && concurrent.saved.isEmpty && concurrent.remote[approvedID]?["CD_weight"] as? Double == 99,
                    "conditional creation preserves a concurrent server record's payload")
        let (existing, existingStore) = try await candidate()
        existingStore.approve(); existing.remote = existing.local
        let noWrite = try await inspect(existing, existingStore)
        try require(existing.saved.isEmpty && noWrite.attempted && existingStore.consumed.count == 1,
                    "records already restored by another client are skipped while approval is consumed")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RestoreReviewReceipts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let (diskSource, diskPlan) = try await candidate()
        let disk = CloudHistoryRestorePlanStore(directory: root)
        let savedPlan = diskPlan.review!
        try disk.save(savedPlan)
        try require(savedPlan.reviewForDisplay(storeIdentifier: savedPlan.storeIdentifier, authorization: nil) == savedPlan.review,
                    "an unapproved review remains available after an ordinary relaunch")
        try require(try !disk.preflightIsRequested(), "an unapproved review does not block routine launches")
        try disk.authorize(reviewID: savedPlan.review.id)
        try require(try disk.preflightIsRequested(), "explicit pending restoration requests sole-owner preflight")
        try require(try disk.authorization()?.state == .pending, "explicit authorization survives reopening its protected receipt")
        try disk.consume(reviewID: savedPlan.review.id)
        try require(try savedPlan.reviewForDisplay(storeIdentifier: savedPlan.storeIdentifier, authorization: disk.authorization()) == nil,
                    "a consumed review cannot offer a stale restore button on later launches")
        try require(try !disk.preflightIsRequested(), "a consumed restoration does not hold later launches behind a cloud check")
        try require(try CloudHistoryRestorePlanStore(directory: root).authorization()?.state == .consumed,
                    "consumption is persisted before a cloud save could begin")
        var replayRejected = false
        do { try disk.authorize(reviewID: savedPlan.review.id) } catch { replayRejected = true }
        try require(replayRejected && diskSource.saved.isEmpty, "a consumed review cannot be authorized again")
        try disk.requestInspection()
        try require(try disk.preflightIsRequested(), "explicit inspection requests sole-owner preflight")
        try require(try disk.hasPendingWork() && disk.inspectionIsRequested(), "users can request read-only inspection despite an old completion receipt")
        try disk.finishInspection()
        try require(try !disk.inspectionIsRequested(), "completed inspection clears its request")

        func rejectsReceipt(_ action: () throws -> Void) throws {
            var rejected = false
            do { try action() } catch CloudHistoryRestoreError.receiptUnavailable { rejected = true }
            try require(rejected, "linked receipt paths must be rejected")
        }
        let manager = FileManager.default
        let outside = root.appendingPathComponent("outside"), alias = root.appendingPathComponent("linked-root")
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: alias, withDestinationURL: outside)
        let redirected = CloudHistoryRestorePlanStore(directory: alias)
        try rejectsReceipt { try redirected.save(savedPlan) }
        try rejectsReceipt { _ = try redirected.plan() }
        try rejectsReceipt { try redirected.requestInspection() }
        try rejectsReceipt { try redirected.clearReview() }
        try require(try manager.contentsOfDirectory(atPath: outside.path).isEmpty,
                    "a linked directory cannot redirect reads, writes, or removals outside the plan root")
        let nested = CloudHistoryRestorePlanStore(directory: alias.appendingPathComponent("nested"))
        try rejectsReceipt { try nested.save(savedPlan) }
        try require(!manager.fileExists(atPath: outside.appendingPathComponent("nested").path),
                    "linked ancestors cannot redirect directory creation")

        let fileRoot = root.appendingPathComponent("file-links"), fileStore = CloudHistoryRestorePlanStore(directory: fileRoot)
        try fileStore.save(savedPlan)
        let witness = outside.appendingPathComponent("witness.json")
        let witnessBytes = try JSONEncoder().encode(savedPlan)
        try witnessBytes.write(to: witness)
        let linkedPlan = fileRoot.appendingPathComponent("restore-review.json")
        try manager.removeItem(at: linkedPlan)
        try manager.createSymbolicLink(at: linkedPlan, withDestinationURL: witness)
        try rejectsReceipt { _ = try fileStore.plan() }
        try rejectsReceipt { try fileStore.save(savedPlan) }
        try rejectsReceipt { try fileStore.clearReview() }
        try require(try Data(contentsOf: witness) == witnessBytes && manager.destinationOfSymbolicLink(atPath: linkedPlan.path) == witness.path,
                    "a linked final file cannot be read, overwritten, or unlinked as a receipt")
        try manager.removeItem(at: linkedPlan)
        try fileStore.save(savedPlan)
        let linkedAuthorization = fileRoot.appendingPathComponent("restore-authorization.json")
        try manager.createSymbolicLink(at: linkedAuthorization, withDestinationURL: witness)
        try rejectsReceipt { try fileStore.authorize(reviewID: savedPlan.review.id) }
        try rejectsReceipt { try fileStore.consume(reviewID: savedPlan.review.id) }
        try rejectsReceipt { try fileStore.cancel() }
        try require(try Data(contentsOf: witness) == witnessBytes,
                    "symlinked authorization cannot write or consume a receipt outside protected storage")
        return checks
    }
}
#endif
