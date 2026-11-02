import Foundation
import CoreData
import CloudKit
import CryptoKit
import SwiftData

/// Repairs missing records during a sole-owner CloudKit preflight. It never changes the
/// local graph or sends updates/deletions for records found on the server.
@MainActor
enum CloudHistoryMissingRecordRepair {
    private static let containerIdentifier = "iCloud.com.workingout.jorsh"
    private static let batchSize = 100

    // Completed recovery is skipped using the account-and-store-bound marker.
    static var isEnabledForLaunch: Bool { true }

    struct Report: Codable, Sendable {
        var inspectedObjects = 0
        var mappedRecords = 0
        var unmappedPending = 0
        var existingServerRecords = 0
        var initiallyMissingRecords = 0
        var createdRecords = 0
        var concurrentExistingRecords = 0
        var verifiedServerRecords = 0
        var stillMissingRecords = 0
        var accountUnchanged = false
        var sourceSnapshotPinned = false
        var allMappedRecordsPresent = false
        // Existence readback is not a payload or relationship round-trip test.
        var payloadVerified = false
        var awaitingInitialDownload: Bool? = nil
        var restoreReview: CloudHistoryRestoreReview? = nil
        var restoreAttempted: Bool? = nil
        var pendingReason: String?
        var errorDomain: String?
        var errorCode: Int?
        /// Distinguishes an account/startup probe from a record repair that started.
        var failureStage: String? = nil

        var requiresRepair: Bool {
            if awaitingInitialDownload == true { return false }
            if unmappedPending > 0 || pendingReason == "unmappedLocalRecords" || pendingReason == "restoreReviewRequired" {
                return true
            }
            // A failed account or startup probe has not left record recovery unfinished.
            if failureStage == "account" || failureStage == "startup" { return false }
            if pendingReason != nil { return true }
            return !allMappedRecordsPresent
        }

        var userAttention: String? {
            guard let pendingReason else { return nil }
            switch pendingReason {
            case "accountUnavailable", "accountChanged":
                return "Pace & Plates could not use this iCloud account. In Settings, check the Apple Account and turn on iCloud for Pace & Plates."
            case "setupTimedOut", "initialImportTimedOut":
                return "iCloud did not finish opening history. Leave Pace & Plates open for a minute, then reopen it."
            case "budgetExpired":
                return "The iCloud check ran out of time. Leave Pace & Plates open, then reopen it to continue. Your history on this phone was kept."
            case "storeIdentityUnavailable":
                return "The history file on this phone could not be identified, so the iCloud check stopped. Your files were kept."
            case "cancelled":
                return "The iCloud check was interrupted. Reopen Pace & Plates and leave it in the foreground until it finishes."
            case "receiptUnavailable":
                return "The on-phone recovery receipt could not be read, so the iCloud check stopped. Your history was kept."
            case "unmappedLocalRecords":
                return "Some history on this phone does not have an iCloud record yet. Reopen Pace & Plates and leave it open so recovery can continue."
            case "restoreReviewRequired":
                return nil
            case "operationFailed":
                return operationAttention
            default:
                return "iCloud recovery did not finish (\(pendingReason)). History on this phone was kept."
            }
        }

        private var operationAttention: String {
            guard errorDomain == CKErrorDomain, let errorCode else {
                return "The iCloud check failed before recovery could finish. History on this phone was kept."
            }
            switch errorCode {
            case CKError.permissionFailure.rawValue, CKError.notAuthenticated.rawValue,
                 CKError.missingEntitlement.rawValue, CKError.managedAccountRestricted.rawValue:
                return "iCloud is signed in, but Pace & Plates cannot use it yet. Open Settings, tap your Apple Account, then iCloud, and turn on Pace & Plates."
            case CKError.networkUnavailable.rawValue, CKError.networkFailure.rawValue,
                 CKError.serviceUnavailable.rawValue, CKError.requestRateLimited.rawValue,
                 CKError.zoneBusy.rawValue, CKError.serverResponseLost.rawValue:
                return "Pace & Plates could not reach iCloud. Check the connection, then reopen the app and leave it open."
            default:
                return "The iCloud check failed (CloudKit error \(errorCode)). History on this phone was kept."
            }
        }

        var accountIsUnavailable: Bool {
            ["accountUnavailable", "accountChanged"].contains(pendingReason ?? "")
                || (errorDomain == CKErrorDomain && errorCode == CKError.notAuthenticated.rawValue)
        }
    }

    private struct Inventory: Sendable {
        let objectIDs: [NSManagedObjectID]
        let recordIDs: [NSManagedObjectID: CKRecord.ID]
    }

    private struct Presence: Sendable {
        var present: Set<CKRecord.ID> = []
        var missing: Set<CKRecord.ID> = []
    }

    private enum RepairError: String, Error {
        case wrongContainer, wrongDatabase, wrongContext, pendingLocalChanges
        case accountUnavailable, accountChanged, ambiguousRecordMapping
        case incompleteFetchResponse, incompleteSaveResponse, sourceChanged
        case invalidEncodedRecords, unexpectedDeleteResult
        case modelUnavailable, storeIdentityUnavailable, setupTimedOut, initialImportTimedOut, budgetExpired
    }

    private struct Completion: Codable {
        let version: Int
        let storeIdentifier: String
        let accountFingerprint: String
        let verifiedAt: Date
        let report: Report
    }

    struct LocalVerification {
        let report: Report
        let accountFingerprint: String
    }

    private struct RepairRequest: Codable {
        let version: Int
        let storeIdentifier: String
    }

    /// Store identity and the saved verification are enough to skip the startup
    /// gate. The account fingerprint is confirmed after the app is open.
    static func verifiedLocally(legacyURL: URL, stateRoot: URL? = nil, hasPendingWork: Bool? = nil) -> LocalVerification? {
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let root = stateRoot ?? repairStateRoot
        guard let identifier = try? readStoreIdentifier(at: legacyURL) else { return nil }
        if let request = repairRequest(in: root), request.storeIdentifier == identifier { return nil }
        let pending = hasPendingWork ?? ((try? CloudHistoryRestorePlanStore().hasPendingWork()) ?? true)
        guard !pending else { return nil }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("completed.json")),
              let completion = try? JSONDecoder().decode(Completion.self, from: data),
              completion.version == 1, completion.storeIdentifier == identifier,
              completion.report.allMappedRecordsPresent, completion.report.unmappedPending == 0,
              completion.report.pendingReason == nil, completion.report.accountUnchanged else { return nil }
        return LocalVerification(report: completion.report, accountFingerprint: completion.accountFingerprint)
    }

    static func markRepairRequired(legacyURL: URL) {
        guard let identifier = try? readStoreIdentifier(at: legacyURL) else { return }
        let request = RepairRequest(version: 1, storeIdentifier: identifier)
        persistRepairRequest(request)
    }

    /// nil means the account could not be checked. The saved verification stays in force.
    static func accountMatchesVerifiedFingerprint(_ expected: String) async -> Bool? {
        do {
            let account = try await accountIdentity(CKContainer(identifier: containerIdentifier),
                                                    deadline: Date().addingTimeInterval(45))
            return fingerprint(for: account) == expected
        } catch {
            return nil
        }
    }

    private static var repairStateRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudHistoryRepair", isDirectory: true)
    }

    private static func fingerprint(for account: CKRecord.ID) -> String {
        SHA256.hash(data: Data((account.zoneID.ownerName + ":" + account.recordName).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func repairRequest(in root: URL) -> RepairRequest? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("repair-next-launch.json")),
              let request = try? JSONDecoder().decode(RepairRequest.self, from: data),
              request.version == 1 else { return nil }
        return request
    }

    private static func persistRepairRequest(_ request: RepairRequest) {
        let root = repairStateRoot
        do {
            try CoachLocalOwnership.prepareDirectory(root)
            try JSONEncoder().encode(request).write(to: root.appendingPathComponent("repair-next-launch.json"), options: .atomic)
        } catch { }
    }

    private static func clearRepairRequest(in root: URL) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("repair-next-launch.json"))
    }

    #if DEBUG
    static func writeVerifiedReceiptForTesting(storeIdentifier: String, accountFingerprint: String,
                                               report: Report, stateRoot: URL) throws {
        let completion = Completion(version: 1, storeIdentifier: storeIdentifier,
                                    accountFingerprint: accountFingerprint, verifiedAt: Date(), report: report)
        try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(completion).write(to: stateRoot.appendingPathComponent("completed.json"), options: .atomic)
    }
    #endif

    @MainActor
    private final class SetupObserver {
        private var token: NSObjectProtocol?
        private var results: [String: Result<Void, NSError>] = [:]

        init() {
            token = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                      event.type == .setup || event.type == .import, event.endDate != nil else { return }
                Task { @MainActor [weak self] in
                    let key = event.storeIdentifier + ":" + String(event.type.rawValue)
                    if event.succeeded { self?.results[key] = .success(()) }
                    else {
                        let error = event.error as NSError?
                        self?.results[key] = .failure(NSError(
                            domain: error?.domain ?? "CloudKitSetup", code: error?.code ?? 0))
                    }
                }
            }
        }

        func wait(for identifier: String, type: NSPersistentCloudKitContainer.EventType, until deadline: Date) async throws {
            let key = identifier + ":" + String(type.rawValue)
            while Date() < deadline {
                try Task.checkCancellation()
                if let result = results[key] { return try result.get() }
                try await Task.sleep(for: .seconds(1))
            }
            throw type == .import ? RepairError.initialImportTimedOut : RepairError.setupTimedOut
        }

        func stop() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }

    /// Opens the sole temporary owner, performs the opt-in repair, and releases
    /// every store before returning control to the normal SwiftData initializer.
    static func preflight(legacyURL: URL) async throws -> Report {
        let deadline = Date().addingTimeInterval(180)
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            var report = Report()
            report.awaitingInitialDownload = true
            return report
        }
        let accountContainer = CKContainer(identifier: containerIdentifier)
        var report = Report()
        let account: CKRecord.ID
        let storeIdentifier: String
        let accountFingerprint: String
        let stateRoot = repairStateRoot
        let completionURL = stateRoot.appendingPathComponent("completed.json")
        let restoreStore = CloudHistoryRestorePlanStore()

        do {
            try Task.checkCancellation()
            account = try await accountIdentity(accountContainer, deadline: deadline)
            let identifier = try readStoreIdentifier(at: legacyURL)
            storeIdentifier = identifier
            accountFingerprint = fingerprint(for: account)
            if try !restoreStore.hasPendingWork(), let data = try? Data(contentsOf: completionURL),
               let completion = try? JSONDecoder().decode(Completion.self, from: data),
               completion.version == 1, completion.storeIdentifier == identifier,
               completion.accountFingerprint == accountFingerprint,
               completion.report.allMappedRecordsPresent, completion.report.unmappedPending == 0,
               completion.report.pendingReason == nil {
                clearRepairRequest(in: stateRoot)
                return completion.report
            }
        } catch {
            let failed = pendingReport(report, error: error, stage: "account")
            persist(failed, to: stateRoot)
            return failed
        }

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
            let failed = pendingReport(report, error: RepairError.modelUnavailable, stage: "startup")
            persist(failed, to: stateRoot)
            return failed
        }
        let historyNames = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
        let historyEntities = model.entities.filter { historyNames.contains($0.name ?? "") }
        guard historyEntities.count == historyNames.count else {
            let failed = pendingReport(report, error: RepairError.modelUnavailable, stage: "startup")
            persist(failed, to: stateRoot)
            return failed
        }
        model.setEntities(historyEntities, forConfigurationName: "History")
        let observer = SetupObserver()
        let container = NSPersistentCloudKitContainer(name: "PaceCloudHistoryRepair", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: legacyURL)
        description.configuration = "History"
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldAddStoreAsynchronously = true
        container.persistentStoreDescriptions = [description]
        var context: NSManagedObjectContext?
        let initialImportDeadline = min(deadline, Date().addingTimeInterval(30))
        var stage = "startup"
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.loadPersistentStores { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: ()) }
                }
            }
            guard let loaded = container.persistentStoreCoordinator.persistentStores.first?.identifier,
                  loaded == storeIdentifier else { throw RepairError.storeIdentityUnavailable }
            try await observer.wait(for: loaded, type: .setup, until: initialImportDeadline)
            try await observer.wait(for: loaded, type: .import, until: initialImportDeadline)
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
            let repairContext = container.newBackgroundContext()
            context = repairContext
            stage = "repair"
            report = try await repair(container: container, context: repairContext, accountContainer: accountContainer,
                                      deadline: deadline, restoreStore: restoreStore)
            stage = "startup"
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
        } catch {
            report = pendingReport(report, error: error, stage: stage)
        }
        observer.stop()
        if let context { context.performAndWait { context.reset() } }
        // A failed close is different from offline repair: opening SwiftData
        // while this owner survives would repeat the dual-owner storage bug.
        do {
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
        } catch {
            throw CoachLocalOwnership.OwnershipError.unavailable(
                "History recovery could not release its storage. Close and reopen the app to retry. Your files are retained.")
        }

        // Receipt/marker failure does not block access to otherwise healthy local
        // history. No completion marker is written until server presence verifies.
        persist(report, to: stateRoot)
        do {
            if report.accountUnchanged, report.allMappedRecordsPresent,
               report.unmappedPending == 0, report.pendingReason == nil {
                let completion = Completion(version: 1, storeIdentifier: storeIdentifier,
                                            accountFingerprint: accountFingerprint, verifiedAt: Date(), report: report)
                try CoachLocalOwnership.prepareDirectory(stateRoot)
                try JSONEncoder().encode(completion).write(to: completionURL, options: .atomic)
                clearRepairRequest(in: stateRoot)
            }
        } catch { }
        return report
    }

    private static func persist(_ report: Report, to stateRoot: URL) {
        do {
            try CoachLocalOwnership.prepareDirectory(stateRoot)
            try JSONEncoder().encode(report).write(to: stateRoot.appendingPathComponent("last-result.json"), options: .atomic)
        } catch { }
    }

    /// Metadata can expose the store UUID as a string or as UUID. The sqlite
    /// metadata row is the same identity the restoration journal records.
    private static func readStoreIdentifier(at url: URL) throws -> String {
        if let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url) {
            if let value = metadata[NSStoreUUIDKey] as? String, let uuid = UUID(uuidString: value) {
                return uuid.uuidString
            }
            if let uuid = metadata[NSStoreUUIDKey] as? UUID { return uuid.uuidString }
        }
        do { return try CoachLocalOwnership.persistentStoreID(at: url) }
        catch { throw RepairError.storeIdentityUnavailable }
    }

    private static func pendingReport(_ original: Report, error: Error, stage: String) -> Report {
        var report = original
        report.failureStage = stage
        if let failure = error as? RepairError { report.pendingReason = failure.rawValue }
        else if let failure = error as? CloudHistoryRestoreError { report.pendingReason = failure.rawValue }
        else if error is CancellationError { report.pendingReason = "cancelled" }
        else {
            report.pendingReason = "operationFailed"
            report.errorDomain = (error as NSError).domain
            report.errorCode = (error as NSError).code
        }
        report.allMappedRecordsPresent = false
        return report
    }

    /// The caller retains exclusive store ownership, with a clean context, until
    /// this operation returns. Its read generation remains pinned until closure.
    static func repair(
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext,
        accountContainer: CKContainer = CKContainer(identifier: "iCloud.com.workingout.jorsh"),
        deadline: Date = Date().addingTimeInterval(180),
        restoreStore: (any CloudHistoryRestorePlanStoring)? = nil,
        onProgress: (@MainActor (Report) -> Void)? = nil
    ) async throws -> Report {
        var report = Report()
        var assetDirectory: URL?
        defer {
            if let assetDirectory { try? FileManager.default.removeItem(at: assetDirectory) }
        }

        do {
            try checkBudget(deadline)
            let database = accountContainer.privateCloudDatabase
            guard database.databaseScope == .private else { throw RepairError.wrongDatabase }
            guard accountContainer.containerIdentifier == containerIdentifier else { throw RepairError.wrongContainer }
            let options = container.persistentStoreDescriptions.compactMap(\.cloudKitContainerOptions)
            guard !options.isEmpty, options.allSatisfy({
                $0.containerIdentifier == containerIdentifier && $0.databaseScope == .private
            }) else { throw RepairError.wrongContainer }
            let account = try await accountIdentity(accountContainer, deadline: deadline)

            let entityNames = PersistenceController.legacyModelTypes.map { String(describing: $0) }
            let inventory = try await context.perform {
                guard context.persistentStoreCoordinator === container.persistentStoreCoordinator else {
                    throw RepairError.wrongContext
                }
                guard !context.hasChanges else { throw RepairError.pendingLocalChanges }
                try context.setQueryGenerationFrom(.current)
                var objectIDs: [NSManagedObjectID] = []
                for entityName in entityNames {
                    let request = NSFetchRequest<NSManagedObjectID>(entityName: entityName)
                    request.resultType = .managedObjectIDResultType
                    request.includesPendingChanges = false
                    request.includesSubentities = false
                    objectIDs.append(contentsOf: try context.fetch(request))
                }
                return Inventory(objectIDs: objectIDs, recordIDs: container.recordIDs(for: objectIDs))
            }
            try checkBudget(deadline)
            report.inspectedObjects = inventory.objectIDs.count
            report.sourceSnapshotPinned = true
            guard Set(inventory.recordIDs.keys).isSubset(of: Set(inventory.objectIDs)) else {
                throw RepairError.ambiguousRecordMapping
            }
            report.mappedRecords = inventory.recordIDs.count
            report.unmappedPending = inventory.objectIDs.count - inventory.recordIDs.count
            let mappedIDs = Array(inventory.recordIDs.values)
            guard Set(mappedIDs).count == mappedIDs.count else { throw RepairError.ambiguousRecordMapping }
            onProgress?(report)

            let objectsByRecord = Dictionary(uniqueKeysWithValues: inventory.recordIDs.map { ($0.value, $0.key) })
            guard let storeID = container.persistentStoreCoordinator.persistentStores.first?.identifier else {
                throw RepairError.storeIdentityUnavailable
            }
            let accountFingerprint = SHA256.hash(data: Data((account.zoneID.ownerName + ":" + account.recordName).utf8))
                .map { String(format: "%02x", $0) }.joined()
            let identity = CloudHistoryRestoreWorkflow.Identity(store: storeID, account: accountFingerprint)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CloudHistoryMissingRecordRepair-" + UUID().uuidString, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(directory)
            assetDirectory = directory
            let dependencies = CloudHistoryRestoreWorkflow.Dependencies(
                identity: {
                    try checkBudget(deadline)
                    try await requireSameAccount(account, container: accountContainer, deadline: deadline)
                    guard container.persistentStoreCoordinator.persistentStores.first?.identifier == storeID else {
                        throw CloudHistoryRestoreError.accountOrStoreChanged
                    }
                    return identity
                }, records: { requested in
                    var payloads: [CKRecord] = []
                    for batch in batches(requested) {
                        try checkBudget(deadline)
                        let records = try await context.perform {
                            guard !context.hasChanges else { throw RepairError.pendingLocalChanges }
                            let objectIDs = try batch.map { recordID -> NSManagedObjectID in
                                guard let objectID = objectsByRecord[recordID] else { throw RepairError.sourceChanged }
                                return objectID
                            }
                            let currentMapping = container.recordIDs(for: objectIDs)
                            let missingObjects = try batch.map { recordID -> NSManagedObject in
                                guard let objectID = objectsByRecord[recordID], currentMapping[objectID] == recordID else {
                                    throw RepairError.sourceChanged
                                }
                                let object = try context.existingObject(with: objectID)
                                guard !object.isDeleted else { throw RepairError.sourceChanged }
                                return object
                            }
                            return try CloudHistoryCloudRecordEncoder.materializedRecords(
                                objects: missingObjects, container: container,
                                recordIDs: inventory.recordIDs, assetDirectory: directory)
                        }
                        payloads.append(contentsOf: records)
                    }
                    return payloads
                }, presence: { requested in
                    try await presence(of: requested, in: database, deadline: deadline).present
                }, save: { records in
                    try checkBudget(deadline)
                    try await requireSameAccount(account, container: accountContainer, deadline: deadline)
                    let configuration = try networkConfiguration(deadline: deadline)
                    report.restoreAttempted = true
                    let result = try await database.configuredWith(configuration: configuration) { configured in
                        try await configured.modifyRecords(
                            saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                    }
                    guard result.deleteResults.isEmpty else { throw RepairError.unexpectedDeleteResult }
                    var savedRecords: [CKRecord.ID: CloudHistoryRestoreWorkflow.Saved] = [:]
                    for recordID in records.map(\.recordID) {
                        guard let saved = result.saveResults[recordID] else { throw RepairError.incompleteSaveResponse }
                        switch saved {
                        case .success:
                            savedRecords[recordID] = .created
                            report.createdRecords += 1
                        case .failure(let error):
                            // Another client may create the record after the
                            // absence check. Its version is deliberately kept.
                            if let cloudError = error as? CKError, cloudError.code == .serverRecordChanged {
                                savedRecords[recordID] = .concurrentExisting
                                report.concurrentExistingRecords += 1
                            } else {
                                throw error
                            }
                        }
                    }
                    return savedRecords
                }, check: { try checkBudget(deadline) })
            let outcome = try await CloudHistoryRestoreWorkflow.run(localIDs: mappedIDs, identity: identity,
                store: restoreStore ?? CloudHistoryRestorePlanStore(), dependencies: dependencies)
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
            report.accountUnchanged = true
            report.existingServerRecords = outcome.initialPresent
            report.initiallyMissingRecords = outcome.initialMissing
            report.createdRecords = outcome.created
            report.concurrentExistingRecords = outcome.concurrentExisting
            report.verifiedServerRecords = outcome.present
            report.stillMissingRecords = outcome.missing
            report.restoreReview = outcome.review
            report.restoreAttempted = outcome.attempted
            report.allMappedRecordsPresent = outcome.missing == 0
            if report.unmappedPending > 0 { report.pendingReason = "unmappedLocalRecords" }
            else if outcome.review != nil { report.pendingReason = "restoreReviewRequired" }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Neither CKError descriptions nor userInfo are safe receipts: they
            // can include private record IDs, values, and access-bearing URLs.
            report.failureStage = "repair"
            if let failure = error as? RepairError {
                report.pendingReason = failure.rawValue
            } else if let failure = error as? CloudHistoryRestoreError {
                report.pendingReason = failure.rawValue
            } else {
                report.pendingReason = "operationFailed"
                report.errorDomain = (error as NSError).domain
                report.errorCode = (error as NSError).code
            }
        }
        onProgress?(report)
        return report
    }

    private static func accountIdentity(_ container: CKContainer, deadline: Date) async throws -> CKRecord.ID {
        var lastError: Error = RepairError.accountUnavailable
        for attempt in 0..<2 {
            do {
                try checkBudget(deadline)
                // The first identity lookup after launch can outlive the short
                // operation timeout while CloudKit starts. A second try uses the
                // connection that attempt already opened.
                let configuration = try networkConfiguration(deadline: deadline, requestTimeout: 30, resourceTimeout: 60)
                let identity = try await container.configuredWith(configuration: configuration) { configured in
                    guard try await configured.accountStatus() == .available else { throw RepairError.accountUnavailable }
                    return try await configured.userRecordID()
                }
                try checkBudget(deadline)
                return identity
            } catch {
                lastError = error
                if attempt == 0, shouldRetryAccountProbe(error), Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private static func shouldRetryAccountProbe(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        switch cloud.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost:
            return true
        default:
            return false
        }
    }

    private static func requireSameAccount(_ expected: CKRecord.ID, container: CKContainer, deadline: Date) async throws {
        guard try await accountIdentity(container, deadline: deadline) == expected else { throw RepairError.accountChanged }
    }

    private static func presence(of ids: [CKRecord.ID], in database: CKDatabase, deadline: Date,
                                 onProgress: (@MainActor (Presence) -> Void)? = nil) async throws -> Presence {
        var result = Presence()
        for batch in batches(ordered(Set(ids))) {
            try checkBudget(deadline)
            let configuration = try networkConfiguration(deadline: deadline)
            let fetched = try await database.configuredWith(configuration: configuration) { configured in
                try await configured.records(for: batch, desiredKeys: [])
            }
            try checkBudget(deadline)
            for recordID in batch {
                guard let record = fetched[recordID] else { throw RepairError.incompleteFetchResponse }
                switch record {
                case .success: result.present.insert(recordID)
                case .failure(let error):
                    if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                        result.missing.insert(recordID)
                    } else {
                        // Permission, zone, network and partial errors are not
                        // evidence that a private record should be recreated.
                        throw error
                    }
                }
            }
            onProgress?(result)
        }
        return result
    }

    private static func checkBudget(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard Date() < deadline else { throw RepairError.budgetExpired }
    }

    private static func networkConfiguration(deadline: Date, requestTimeout: TimeInterval = 15,
                                             resourceTimeout: TimeInterval = 30) throws -> CKOperation.Configuration {
        try checkBudget(deadline)
        let remaining = deadline.timeIntervalSinceNow
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = min(requestTimeout, remaining)
        configuration.timeoutIntervalForResource = min(resourceTimeout, remaining)
        return configuration
    }

    private static func ordered(_ ids: Set<CKRecord.ID>) -> [CKRecord.ID] {
        ids.sorted {
            if $0.zoneID.ownerName != $1.zoneID.ownerName { return $0.zoneID.ownerName < $1.zoneID.ownerName }
            if $0.zoneID.zoneName != $1.zoneID.zoneName { return $0.zoneID.zoneName < $1.zoneID.zoneName }
            return $0.recordName < $1.recordName
        }
    }

    private static func batches(_ ids: [CKRecord.ID]) -> [[CKRecord.ID]] {
        stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }
    }
}
