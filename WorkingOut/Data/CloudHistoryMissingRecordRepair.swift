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
        var pendingReason: String?
        var errorDomain: String?
        var errorCode: Int?
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
        let accountContainer = CKContainer(identifier: containerIdentifier)
        var report = Report()
        let account: CKRecord.ID
        let storeIdentifier: String
        let accountFingerprint: String
        let stateRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudHistoryRepair", isDirectory: true)
        let completionURL = stateRoot.appendingPathComponent("completed.json")

        do {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: legacyURL.path) else {
                report.allMappedRecordsPresent = true
                return report
            }
            account = try await accountIdentity(accountContainer, deadline: deadline)
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: legacyURL)
            guard let identifier = metadata[NSStoreUUIDKey] as? String else { throw RepairError.storeIdentityUnavailable }
            storeIdentifier = identifier
            accountFingerprint = SHA256.hash(data: Data((account.zoneID.ownerName + ":" + account.recordName).utf8))
                .map { String(format: "%02x", $0) }.joined()
            if let data = try? Data(contentsOf: completionURL),
               let completion = try? JSONDecoder().decode(Completion.self, from: data),
               completion.version == 1, completion.storeIdentifier == identifier,
               completion.accountFingerprint == accountFingerprint,
               completion.report.allMappedRecordsPresent, completion.report.unmappedPending == 0,
               completion.report.pendingReason == nil {
                return completion.report
            }
        } catch {
            return pendingReport(report, error: error)
        }

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
            return pendingReport(report, error: RepairError.modelUnavailable)
        }
        let historyNames = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
        let historyEntities = model.entities.filter { historyNames.contains($0.name ?? "") }
        guard historyEntities.count == historyNames.count else {
            return pendingReport(report, error: RepairError.modelUnavailable)
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
            report = try await repair(container: container, context: repairContext, accountContainer: accountContainer,
                                      deadline: deadline)
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
        } catch {
            report = pendingReport(report, error: error)
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
        do {
            try CoachLocalOwnership.prepareDirectory(stateRoot)
            try JSONEncoder().encode(report).write(to: stateRoot.appendingPathComponent("last-result.json"), options: .atomic)
            if report.accountUnchanged, report.allMappedRecordsPresent,
               report.unmappedPending == 0, report.pendingReason == nil {
                let completion = Completion(version: 1, storeIdentifier: storeIdentifier,
                                            accountFingerprint: accountFingerprint, verifiedAt: Date(), report: report)
                try JSONEncoder().encode(completion).write(to: completionURL, options: .atomic)
            }
        } catch { }
        return report
    }

    private static func pendingReport(_ original: Report, error: Error) -> Report {
        var report = original
        if let failure = error as? RepairError { report.pendingReason = failure.rawValue }
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

            let initial = try await presence(of: mappedIDs, in: database, deadline: deadline) { partial in
                report.existingServerRecords = partial.present.count
                report.initiallyMissingRecords = partial.missing.count
                onProgress?(report)
            }
            report.existingServerRecords = initial.present.count
            report.initiallyMissingRecords = initial.missing.count
            onProgress?(report)
            let objectsByRecord = Dictionary(uniqueKeysWithValues: inventory.recordIDs.map { ($0.value, $0.key) })
            let missing = ordered(initial.missing)

            if !missing.isEmpty {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CloudHistoryMissingRecordRepair-" + UUID().uuidString, isDirectory: true)
                try CoachLocalOwnership.prepareDirectory(directory)
                assetDirectory = directory
                for batch in batches(missing) {
                    try checkBudget(deadline)
                    try await requireSameAccount(account, container: accountContainer, deadline: deadline)
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
                    guard records.count == batch.count,
                          Set(records.map(\.recordID)) == Set(batch),
                          records.allSatisfy({ $0.recordChangeTag == nil }) else {
                        throw RepairError.invalidEncodedRecords
                    }
                    try checkBudget(deadline)
                    try await requireSameAccount(account, container: accountContainer, deadline: deadline)
                    let configuration = try networkConfiguration(deadline: deadline)
                    let result = try await database.configuredWith(configuration: configuration) { configured in
                        try await configured.modifyRecords(
                            saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                    }
                    guard result.deleteResults.isEmpty else { throw RepairError.unexpectedDeleteResult }
                    for recordID in batch {
                        guard let saved = result.saveResults[recordID] else { throw RepairError.incompleteSaveResponse }
                        switch saved {
                        case .success: report.createdRecords += 1
                        case .failure(let error):
                            // Another client may create the record after the
                            // absence check. Its version is deliberately kept.
                            if let cloudError = error as? CKError, cloudError.code == .serverRecordChanged {
                                report.concurrentExistingRecords += 1
                            } else {
                                throw error
                            }
                        }
                    }
                    onProgress?(report)
                }
            }

            try checkBudget(deadline)
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
            let verified = try await presence(of: mappedIDs, in: database, deadline: deadline) { partial in
                report.verifiedServerRecords = partial.present.count
                report.stillMissingRecords = partial.missing.count
                onProgress?(report)
            }
            try await requireSameAccount(account, container: accountContainer, deadline: deadline)
            report.accountUnchanged = true
            report.verifiedServerRecords = verified.present.count
            report.stillMissingRecords = verified.missing.count
            report.allMappedRecordsPresent = verified.missing.isEmpty
            if report.unmappedPending > 0 { report.pendingReason = "unmappedLocalRecords" }
            else if !verified.missing.isEmpty { report.pendingReason = "serverRecordsStillMissing" }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Neither CKError descriptions nor userInfo are safe receipts: they
            // can include private record IDs, values, and access-bearing URLs.
            if let failure = error as? RepairError {
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
        try checkBudget(deadline)
        let configuration = try networkConfiguration(deadline: deadline)
        let identity = try await container.configuredWith(configuration: configuration) { configured in
            guard try await configured.accountStatus() == .available else { throw RepairError.accountUnavailable }
            return try await configured.userRecordID()
        }
        try checkBudget(deadline)
        return identity
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

    private static func networkConfiguration(deadline: Date) throws -> CKOperation.Configuration {
        try checkBudget(deadline)
        let remaining = deadline.timeIntervalSinceNow
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = min(15, remaining)
        configuration.timeoutIntervalForResource = min(30, remaining)
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
