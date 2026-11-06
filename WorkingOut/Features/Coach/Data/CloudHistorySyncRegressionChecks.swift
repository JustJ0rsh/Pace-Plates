#if DEBUG
import Foundation
import SwiftData
import CoreData
import CloudKit

@MainActor
enum CloudHistorySyncRegressionChecks {
    /// Pure state/events plus disposable local stores. No CloudKit container is
    /// initialized and no account, server, or selected application store is read.
    static func run() async throws -> Int {
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            guard condition else { throw CoachRepositoryError.invalidValue("cloud status regression: " + message) }
        }
        let first = Date(timeIntervalSince1970: 100), later = first.addingTimeInterval(1)
        func event(_ kind: CloudHistorySyncState.Event.Kind, success: Bool = true,
                   at date: Date? = Date(timeIntervalSince1970: 100), store: String = "history",
                   failure: CloudHistorySyncState.Failure = .other) -> CloudHistorySyncState.Event {
            .init(storeIdentifier: store, kind: kind, completedAt: date, succeeded: success, failure: failure)
        }

        var state = CloudHistorySyncState()
        try require(state.phase == .disabled, "isolated/local histories do not advertise iCloud")
        state.prepare()
        try require(state.phase == .preparing, "preflight has a distinct preparing state")
        state.openStore(identifier: "history", cloudBacked: true, repairPending: false)
        try require(state.phase == .waitingForDownload && state.lastImportAt == nil,
                    "opening the normal container does not claim that cloud history downloaded")
        state.receive(event(.setup)); state.receive(event(.upload))
        try require(state.phase == .waitingForDownload, "setup and upload success never confirm a download")
        state.receive(event(.download, at: nil))
        try require(state.phase == .waitingForDownload, "an unfinished download is not success")
        state.receive(event(.download, store: "another-store"))
        try require(state.phase == .waitingForDownload, "another store's import cannot confirm this history")
        state.receive(event(.download))
        try require(state.phase == .importConfirmed && state.lastImportAt == first,
                    "only a successful completed import for this store confirms a download check")
        state.receive(event(.download, success: false, at: first.addingTimeInterval(-1)))
        try require(state.phase == .importConfirmed, "a delayed older failure cannot replace newer evidence")
        state.receive(event(.download, success: false, at: later, failure: .accountUnavailable))
        try require(state.phase == .accountUnavailable && state.lastImportAt == nil,
                    "account failure invalidates stale download success")
        state.checkedAccount(.unknown)
        try require(state.phase == .accountUnavailable, "a failed account check cannot hide an authentication failure")
        state.checkedAccount(.available)
        try require(state.phase == .syncUnavailable, "an available account alone neither confirms a download nor clears its failed operation")
        state.receive(event(.download, success: false, at: later.addingTimeInterval(1)))
        try require(state.phase == .syncUnavailable, "other sync errors remain visible")
        state.checkedAccount(.available)
        try require(state.phase == .syncUnavailable, "account checks do not hide a failed sync operation")
        state.receive(event(.download, at: later.addingTimeInterval(2)))
        try require(state.phase == .importConfirmed, "a subsequent import clears a transient sync failure")

        state.openStore(identifier: "history", cloudBacked: true, repairPending: false)
        state.receive(event(.upload, success: false))
        state.receive(event(.download, at: later))
        try require(state.phase == .syncUnavailable && state.lastImportAt == later,
                    "a successful download preserves an outstanding upload or quota failure")
        state.receive(event(.upload, at: first.addingTimeInterval(-1)))
        try require(state.phase == .syncUnavailable, "an older upload success cannot hide a newer upload failure")
        state.receive(event(.upload, at: first.addingTimeInterval(0.5)))
        try require(state.phase == .importConfirmed,
                    "upload success clears its own failure even when a newer download completed")
        state.receive(event(.download, success: false, at: later.addingTimeInterval(1)))
        state.receive(event(.upload, at: later.addingTimeInterval(2)))
        try require(state.phase == .syncUnavailable && state.lastImportAt == nil,
                    "a successful upload cannot hide a failed download or claim download completion")
        state.receive(event(.download, at: later.addingTimeInterval(0.5)))
        try require(state.phase == .syncUnavailable, "a delayed older download success cannot clear its newer failure")
        state.receive(event(.download, at: later.addingTimeInterval(1.5)))
        try require(state.phase == .importConfirmed,
                    "download success clears its own failure independently of later upload timestamps")
        state.receive(event(.setup, success: false, at: later.addingTimeInterval(3)))
        state.receive(event(.upload, at: later.addingTimeInterval(4)))
        state.receive(event(.download, at: later.addingTimeInterval(5)))
        try require(state.phase == .syncUnavailable, "other successful operations cannot hide a failed setup")
        state.receive(event(.setup, at: later.addingTimeInterval(3.5)))
        try require(state.phase == .importConfirmed, "setup success clears only its own outstanding failure")
        state.receive(event(.upload, success: false, at: later.addingTimeInterval(6), failure: .accountUnavailable))
        state.receive(event(.download, at: later.addingTimeInterval(7)))
        try require(state.phase == .syncUnavailable && state.account == .available,
                    "newer download evidence confirms account availability while retaining the failed upload")
        state.receive(event(.setup, success: false, at: later.addingTimeInterval(4), failure: .accountUnavailable))
        try require(state.account == .available && state.phase == .syncUnavailable,
                    "a delayed cross-kind authentication failure cannot replace newer account evidence")

        state.openStore(identifier: "history", cloudBacked: true, repairPending: true)
        state.receive(event(.download))
        try require(state.phase == .repairPending && state.lastImportAt != nil,
                    "normal importing does not silently claim unfinished repair is complete")
        state.openStore(identifier: "history", cloudBacked: false, repairPending: true)
        state.checkedAccount(.available); state.receive(event(.download))
        try require(state.phase == .offlineFallback && state.lastImportAt == nil,
                    "account availability and notifications cannot turn an offline fallback into cloud sync")
        state.openStore(identifier: nil, cloudBacked: true, repairPending: false)
        try require(state.phase == .syncUnavailable, "missing store identity fails closed for download confirmation")
        state.openStore(identifier: "history", cloudBacked: true, repairPending: true)
        state.setRestoreReview(count: 3, scheduled: false, inspectionRequested: false)
        state.receive(event(.download))
        try require(state.phase == .restoreReviewRequired, "download success cannot hide required restore review")
        state.setRestoreReview(count: 3, scheduled: true, inspectionRequested: false)
        try require(state.phase == .restoreScheduled, "explicit restoration remains visibly scheduled until relaunch or cancellation")
        state.setRestoreReview(count: 3, scheduled: false, inspectionRequested: false)
        try require(state.phase == .restoreReviewRequired, "canceling scheduled restoration returns to an unapproved review")
        state.openStore(identifier: "history", cloudBacked: true, repairPending: false)
        state.setRestoreReview(count: nil, scheduled: false, inspectionRequested: true)
        try require(state.phase == .reviewRequested && state.lastImportAt == nil,
                    "requesting inspection neither approves restoration nor claims recovery completed")

        var received: [CloudHistorySyncState.Event] = []
        let observer = CloudHistoryEventObserver { received.append($0) }
        observer.receive(event(.download, store: "another-store"))
        observer.receive(event(.download))
        try require(received.isEmpty, "startup events are buffered before the store identity is known")
        observer.bind(to: "history")
        try require(received.count == 1 && received[0].storeIdentifier == "history",
                    "binding replays only this store's buffered events")
        observer.receive(event(.download, store: "another-store"))
        try require(received.count == 1, "unrelated live-store events are ignored")
        observer.stop(); observer.receive(event(.download))
        try require(received.count == 1, "a stopped observer cannot publish queued stale events")
        let authentication = NSError(domain: CKErrorDomain, code: CKError.notAuthenticated.rawValue)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134400, userInfo: [NSUnderlyingErrorKey: authentication])
        try require(CloudHistoryEventAdapter.failure(wrapped) == .accountUnavailable,
                    "wrapped CloudKit authentication failure maps to safe account guidance")
        let network = NSError(domain: CKErrorDomain, code: CKError.networkUnavailable.rawValue)
        try require(CloudHistoryEventAdapter.failure(network) == .other,
                    "network failure is not misreported as a missing account")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CloudStatusChecks-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // This path returns before constructing CKContainer or querying accounts.
        let pending = try await CloudHistoryMissingRecordRepair.preflight(legacyURL: root.appendingPathComponent("missing.store"))
        try require(pending.awaitingInitialDownload == true && !pending.allMappedRecordsPresent && !pending.requiresRepair,
                    "fresh installation is waiting for download, never a successful empty recovery")
        var legacyReport = CloudHistoryMissingRecordRepair.Report()
        legacyReport.allMappedRecordsPresent = true
        let decoded = try JSONDecoder().decode(CloudHistoryMissingRecordRepair.Report.self, from: JSONEncoder().encode(legacyReport))
        try require(decoded.awaitingInitialDownload == nil && !decoded.requiresRepair,
                    "existing completion receipts without the optional download field remain readable")
        var accountProbe = CloudHistoryMissingRecordRepair.Report()
        accountProbe.pendingReason = "operationFailed"
        accountProbe.failureStage = "account"
        accountProbe.errorDomain = CKErrorDomain
        accountProbe.errorCode = CKError.notAuthenticated.rawValue
        try require(!accountProbe.requiresRepair && accountProbe.userAttention?.contains("iCloud") == true,
                    "an account probe failure is not unfinished record recovery")
        var unfinished = CloudHistoryMissingRecordRepair.Report()
        unfinished.unmappedPending = 2
        unfinished.failureStage = "repair"
        try require(unfinished.requiresRepair, "unmapped local records still need recovery")
        var explained = CloudHistorySyncState()
        explained.prepare()
        explained.openStore(identifier: "history", cloudBacked: true, repairPending: false, attention: "Could not reach iCloud.")
        explained.checkedAccount(.available)
        try require(explained.phase == .syncUnavailable && explained.message == "Could not reach iCloud.",
                    "a later account-status success cannot relabel a failed probe as unfinished recovery")

        let schema = Schema([WeightEntry.self])
        let offlineURL = root.appendingPathComponent("offline.store")
        let local = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            url: offlineURL, cloudKitDatabase: .none)])
        let receiptRoot = root.appendingPathComponent("receipts")
        let storeID = try CoachLocalOwnership.persistentStoreID(at: offlineURL)
        var verifiedReport = CloudHistoryMissingRecordRepair.Report()
        verifiedReport.allMappedRecordsPresent = true
        verifiedReport.accountUnchanged = true
        try CloudHistoryMissingRecordRepair.writeVerifiedReceiptForTesting(
            storeIdentifier: storeID, accountFingerprint: "account", report: verifiedReport, stateRoot: receiptRoot)
        let verified = CloudHistoryMissingRecordRepair.verifiedLocally(
            legacyURL: offlineURL, stateRoot: receiptRoot, hasPendingWork: false)
        try require(verified?.accountFingerprint == "account" && verified?.report.allMappedRecordsPresent == true,
                    "a matching local verification opens without another iCloud recovery")
        let blocked = receiptRoot.appendingPathComponent("repair-next-launch.json")
        try Data(#"{"version":1,"storeIdentifier":"\#(storeID)"}"#.utf8).write(to: blocked)
        try require(CloudHistoryMissingRecordRepair.verifiedLocally(
            legacyURL: offlineURL, stateRoot: receiptRoot, hasPendingWork: false) == nil,
                    "an account change keeps the next launch on the recovery gate")
        let retainedID = UUID()
        local.mainContext.insert(WeightEntry(id: retainedID, weight: 80, weightUnit: "kg"))
        try local.mainContext.save()
        enum InjectedFailure: Error { case cloudOpen }
        var attemptedModes: [PersistenceController.CloudKitMode] = []
        let opened = try PersistenceController.openCloudHistory(mode: .automatic) { mode in
            attemptedModes.append(mode)
            if mode == .automatic { throw InjectedFailure.cloudOpen }
            return local
        }
        try require(attemptedModes == [.automatic, .none] && !opened.isCloudBacked && opened.container === local,
                    "an injected CloudKit open failure returns the retained local owner and explicit offline state")
        try require(try opened.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == retainedID,
                    "offline fallback retains existing local history")
        return checks
    }
}
#endif
