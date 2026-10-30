#if DEBUG
import SwiftUI
import SwiftData
import CoreData
import CloudKit
import CryptoKit
import UIKit

/// Opt-in acceptance check: read the normal history, then download into a new store.
struct ActualHistoryCloudVerificationView: View {
    @State private var status = "Preparing history download verification…"
    @State private var runner: ActualHistoryCloudVerificationRunner?

    var body: some View {
        VStack(spacing: 20) {
            Text("History iCloud verification").font(.title2.bold())
            Text(status).accessibilityIdentifier("actual-history-cloud.result")
        }
        .padding()
        .task {
            guard runner == nil else { return }
            let driver = ActualHistoryCloudVerificationRunner()
            runner = driver
            UIApplication.shared.isIdleTimerDisabled = true
            await driver.run { status = $0 }
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            runner?.stopObserving()
        }
    }
}

@MainActor
private final class ActualHistoryCloudVerificationRunner {
    private typealias Inventory = [String: [UUID: Int]]

    private struct Receipt: Encodable {
        let suite = "actual_history_cloud_verification"
        let scope = "Normal history IDs read only; fresh private iCloud download; no record values or IDs in receipt"
        let startedAt = Date()
        var updatedAt = Date()
        var result = "running"
        var action = "starting"
        var sourceCounts: [String: Int] = [:]
        var downloadedCounts: [String: Int] = [:]
        var missingCounts: [String: Int] = [:]
        var sourceTotal = 0
        var downloadedTotal = 0
        var missingTotal = 0
        var sourceSnapshotClosed = false
        var freshStoreCreated = false
        var accountAvailable = false
        var expectedCloudContainer = false
        var successfulImports = 0
        var failedImports = 0
        var sourceIDMultiplicitiesPresent = false
        var sourceIDMultisetDigestMatches = false
        var error: String?
        var errorDomain: String?
        var errorCode: Int?
        var lastCloudErrorDomain: String?
        var lastCloudErrorCode: Int?
    }

    private enum VerificationError: String, Error {
        case optInRequired, isolatedLaunchUnsupported, normalCloudStoreUnavailable
        case accountUnavailable, modelUnavailable, sourceEmpty, missingStableIdentity
        case sourceMissing, unexpectedCloudContainer, missingFreshStoreIdentifier
        case timedOutWaitingForImport, timedOutWaitingForHistory
    }

    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ActualHistoryCloudVerification", isDirectory: true)
    private var receipt = Receipt()
    private var activeContainer: ModelContainer?
    private var observer: NSObjectProtocol?
    private var freshStoreIdentifier: String?

    func run(update: @escaping (String) -> Void) async {
        do {
            guard ProcessInfo.processInfo.environment["PP_USER_CLOUD_VERIFY"] == "1" else {
                throw VerificationError.optInRequired
            }
            guard !AppLaunchConfiguration.current.usesIsolatedStore else {
                throw VerificationError.isolatedLaunchUnsupported
            }
            guard PersistenceController.shared.storageError == nil,
                  PersistenceController.shared.isCloudBacked else {
                throw VerificationError.normalCloudStoreUnavailable
            }
            try CoachLocalOwnership.prepareDirectory(root)
            try writeReceipt()
            let schema = Schema(PersistenceController.legacyModelTypes)
            // SwiftData records the combined container model in store metadata,
            // even though this configuration contains only the legacy entities.
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
                throw VerificationError.modelUnavailable
            }
            let sourceURL = ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
            let (expected, _) = try snapshot(at: sourceURL, model: model)
            receipt.sourceSnapshotClosed = true
            receipt.sourceCounts = counts(expected)
            receipt.sourceTotal = receipt.sourceCounts.values.reduce(0, +)
            guard receipt.sourceTotal > 0 else { throw VerificationError.sourceEmpty }
            let expectedDigest = fingerprint(expected)

            guard try await CKContainer(identifier: "iCloud.com.workingout.jorsh").accountStatus() == .available else {
                throw VerificationError.accountUnavailable
            }
            receipt.accountAvailable = true
            let runRoot = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(runRoot)
            let downloadURL = runRoot.appendingPathComponent("download.store")
            receipt.freshStoreCreated = !FileManager.default.fileExists(atPath: downloadURL.path)
            startObserving()
            let container = try CloudSyncRestoration.makeContainer(
                legacyURL: downloadURL, coachURL: runRoot.appendingPathComponent("coach.store"),
                cloudKitMode: .automatic
            )
            activeContainer = container
            let configuration = container.configurations.first { $0.url.standardizedFileURL == downloadURL.standardizedFileURL }
            receipt.expectedCloudContainer = configuration?.cloudKitContainerIdentifier == "iCloud.com.workingout.jorsh"
            guard receipt.expectedCloudContainer else { throw VerificationError.unexpectedCloudContainer }
            let (_, identifier) = try snapshot(at: downloadURL, model: model)
            guard !identifier.isEmpty else { throw VerificationError.missingFreshStoreIdentifier }
            freshStoreIdentifier = identifier
            receipt.action = "waitingForFreshStoreImport"
            try writeReceipt()
            update("Waiting for iCloud to download \(receipt.sourceTotal) history records…")

            let deadline = Date().addingTimeInterval(600)
            while Date() < deadline {
                try Task.checkCancellation()
                if receipt.successfulImports > 0 {
                    let (downloaded, _) = try snapshot(at: downloadURL, model: model)
                    receipt.downloadedCounts = counts(downloaded)
                    receipt.downloadedTotal = receipt.downloadedCounts.values.reduce(0, +)
                    var missingByEntity = expected.mapValues { _ in 0 }
                    var projection: Inventory = [:]
                    for (entity, identifiers) in expected {
                        var present: [UUID: Int] = [:]
                        for (id, required) in identifiers {
                            let found = min(required, downloaded[entity]?[id] ?? 0)
                            missingByEntity[entity, default: 0] += required - found
                            if found > 0 { present[id] = found }
                        }
                        projection[entity] = present
                    }
                    receipt.missingCounts = missingByEntity
                    receipt.missingTotal = missingByEntity.values.reduce(0, +)
                    receipt.sourceIDMultiplicitiesPresent = receipt.missingTotal == 0
                    receipt.sourceIDMultisetDigestMatches = fingerprint(projection) == expectedDigest
                    receipt.action = "checkingDownloadedHistory"
                    try writeReceipt()
                    if receipt.sourceIDMultiplicitiesPresent && receipt.sourceIDMultisetDigestMatches {
                        receipt.result = "passed"
                        receipt.action = "completed"
                        update("PASS: All \(receipt.sourceTotal) source records downloaded with their original ID multiplicities.")
                        break
                    }
                    update("iCloud download verified \(receipt.sourceTotal - receipt.missingTotal) of \(receipt.sourceTotal) source records…")
                }
                try await Task.sleep(for: .seconds(2))
            }
            guard receipt.result == "passed" else {
                throw receipt.successfulImports == 0
                    ? VerificationError.timedOutWaitingForImport : VerificationError.timedOutWaitingForHistory
            }
        } catch {
            receipt.result = "failed"
            receipt.action = "stopped"
            if let failure = error as? VerificationError { receipt.error = failure.rawValue }
            else if error is CancellationError { receipt.error = "cancelled" }
            else {
                receipt.error = "operationFailed"
                receipt.errorDomain = (error as NSError).domain
                receipt.errorCode = (error as NSError).code
            }
            update("FAIL: \(receipt.error ?? "operationFailed")")
        }
        stopObserving()
        do { try writeReceipt() }
        catch { update("FAIL: Could not save history verification receipt.") }
    }

    private func snapshot(at url: URL, model: NSManagedObjectModel) throws -> (Inventory, String) {
        guard FileManager.default.fileExists(atPath: url.path) else { throw VerificationError.sourceMissing }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSReadOnlyPersistentStoreOption: true,
                      NSMigratePersistentStoresAutomaticallyOption: false,
                      NSInferMappingModelAutomaticallyOption: false])
        let identifier = store.identifier ?? ""
        let entityNames = PersistenceController.legacyModelTypes.map { String(describing: $0) }.sorted()
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        let captured = Result { try context.performAndWait { () throws -> Inventory in
            try context.setQueryGenerationFrom(.current)
            var inventory: Inventory = [:]
            for entity in entityNames {
                let request = NSFetchRequest<NSDictionary>(entityName: entity)
                request.resultType = .dictionaryResultType
                request.propertiesToFetch = ["id"]
                request.includesPendingChanges = false
                var identifiers: [UUID: Int] = [:]
                for row in try context.fetch(request) {
                    guard let id = row["id"] as? UUID else { throw VerificationError.missingStableIdentity }
                    identifiers[id, default: 0] += 1
                }
                inventory[entity] = identifiers
            }
            return inventory
        } }
        context.performAndWait { context.reset() }
        try coordinator.remove(store)
        return (try captured.get(), identifier)
    }

    private func counts(_ inventory: Inventory) -> [String: Int] {
        inventory.mapValues { $0.values.reduce(0, +) }
    }

    private func fingerprint(_ inventory: Inventory) -> Data {
        let rows = inventory.keys.sorted().flatMap { entity in
            (inventory[entity] ?? [:]).map { entity + ":" + $0.key.uuidString + ":" + String($0.value) }.sorted()
        }
        return Data(SHA256.hash(data: Data(rows.joined(separator: "\n").utf8)))
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in
                guard let self, event.storeIdentifier == self.freshStoreIdentifier,
                      event.type == .import, event.endDate != nil else { return }
                if event.succeeded { self.receipt.successfulImports += 1 }
                else {
                    self.receipt.failedImports += 1
                    self.receipt.lastCloudErrorDomain = event.error.map { ($0 as NSError).domain }
                    self.receipt.lastCloudErrorCode = event.error.map { ($0 as NSError).code }
                }
                try? self.writeReceipt()
            }
        }
    }

    func stopObserving() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func writeReceipt() throws {
        receipt.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(receipt).write(to: root.appendingPathComponent("result.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
#endif
