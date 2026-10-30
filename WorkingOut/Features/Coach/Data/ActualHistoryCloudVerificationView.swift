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
        var scope = "Normal history IDs read only; fresh private iCloud download; no record values or IDs in receipt"
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
        var recordMapProbeOnly = false
        var recordMapProbeTotal: Int?
        var recordMapProbeMapped: Int?
        var representativeRecordKeyCounts: [String: Int]?
        var representativeRecordContainsCDID: [String: Bool]?
        var activeProbeSetupSucceeded = false
        var activeProbeSetupFailed = false
        var nativeValidationRequested = false
        var nativeValidatedCount = 0
        var nativeValidationAssetFileCount = 0
        var nativeValidationSucceeded = false
        var missingRepairRequested = false
        var missingRepairReport: CloudHistoryMissingRecordRepair.Report?
        var error: String?
        var errorDomain: String?
        var errorCode: Int?
        var lastCloudErrorDomain: String?
        var lastCloudErrorCode: Int?
    }

    private enum VerificationError: String, Error {
        case optInRequired, isolatedLaunchUnsupported, normalCloudStoreUnavailable
        case accountUnavailable, modelUnavailable, sourceEmpty, missingStableIdentity
        case sourceMissing, unexpectedCloudContainer, missingSourceStoreIdentifier
        case timedOutWaitingForImport, timedOutWaitingForHistory
        case activeProbeSetupFailed, activeProbeSetupTimedOut
        case nativeValidationMissingMappings, nativeValidationCountMismatch
        case missingRepairRequiresValidation, missingRepairIncomplete
    }

    private var isIsolatedRecordMapProbe: Bool {
        AppLaunchConfiguration.current.isUITest
            && AppLaunchConfiguration.current.fixtureName == "user_record_map_probe"
    }
    private var isActiveRecordMapProbe: Bool {
        AppLaunchConfiguration.current.liveCloudRunID != nil
            && AppLaunchConfiguration.current.liveCloudPhase == "active-record-map-probe"
    }
    private var root: URL {
        if isIsolatedRecordMapProbe {
            return FileManager.default.temporaryDirectory.appendingPathComponent("UserRecordMapProbe", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ActualHistoryCloudVerification", isDirectory: true)
    }
    private var receipt = Receipt()
    private var activeContainer: ModelContainer?
    private var observer: NSObjectProtocol?
    private var sourceStoreIdentifier: String?
    private var freshStoreIdentifier: String?

    func run(update: @escaping (String) -> Void) async {
        do {
            if isIsolatedRecordMapProbe {
                receipt.scope = "Disposable saved-store copy; read-only record mapping probe; no iCloud account or sync delegate"
            } else if isActiveRecordMapProbe {
                guard ProcessInfo.processInfo.environment["PP_USER_CLOUD_VERIFY"] == "1" else {
                    throw VerificationError.optInRequired
                }
                receipt.scope = "Single active CloudKit store; normal app persistence in memory; record mapping and field counts only"
            } else {
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
            }
            try CoachLocalOwnership.prepareDirectory(root)
            try writeReceipt()
            let schema = Schema(PersistenceController.legacyModelTypes)
            // SwiftData records the combined container model in store metadata,
            // even though this configuration contains only the legacy entities.
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
                throw VerificationError.modelUnavailable
            }
            let sourceURL = isIsolatedRecordMapProbe
                ? root.appendingPathComponent("default.store")
                : ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
            if isIsolatedRecordMapProbe {
                // The retained copy may predate the combined schema metadata.
                // Only this disposable fixture may undergo lightweight migration.
                try prepareCopiedStore(at: sourceURL, model: model)
            }
            let (expected, sourceIdentifier) = try snapshot(at: sourceURL, model: model)
            guard !sourceIdentifier.isEmpty else { throw VerificationError.missingSourceStoreIdentifier }
            sourceStoreIdentifier = sourceIdentifier
            receipt.sourceSnapshotClosed = true
            receipt.sourceCounts = counts(expected)
            receipt.sourceTotal = receipt.sourceCounts.values.reduce(0, +)
            guard receipt.sourceTotal > 0 else { throw VerificationError.sourceEmpty }
            if isIsolatedRecordMapProbe || isActiveRecordMapProbe
                || ProcessInfo.processInfo.environment["PP_RECORD_MAP_PROBE"] == "1" {
                receipt.recordMapProbeOnly = true
                receipt.action = isActiveRecordMapProbe ? "startingSingleCloudKitDelegate" : "readingRecordMappingsWithoutSyncDelegate"
                try writeReceipt()
                let mapping = try await recordMappingProbe(at: sourceURL, model: model, activeCloud: isActiveRecordMapProbe)
                receipt.recordMapProbeTotal = mapping.total
                receipt.recordMapProbeMapped = mapping.mapped
                receipt.representativeRecordKeyCounts = mapping.keyCounts
                receipt.representativeRecordContainsCDID = mapping.containsCDID
                receipt.result = "passed"
                receipt.action = "recordMappingProbeCompleted"
                try writeReceipt()
                update("Record mapping probe: \(mapping.mapped) of \(mapping.total) rows have mappings.")
                return
            }
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
            receipt.action = "waitingForFreshStoreImport"
            try writeReceipt()
            update("Waiting for iCloud to download \(receipt.sourceTotal) history records…")

            let deadline = Date().addingTimeInterval(600)
            while Date() < deadline {
                try Task.checkCancellation()
                if receipt.successfulImports > 0 {
                    let downloaded = try downloadedInventory(in: container)
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
            else if let failure = error as? CloudHistoryCloudRecordEncoder.EncodingError {
                // Encoder diagnostics contain reviewed model/field names only.
                receipt.error = failure.localizedDescription
            }
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
        let pinLiveGeneration = !isIsolatedRecordMapProbe
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        let captured = Result { try context.performAndWait { () throws -> Inventory in
            if pinLiveGeneration { try context.setQueryGenerationFrom(.current) }
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

    private func prepareCopiedStore(at url: URL, model: NSManagedObjectModel) throws {
        guard isIsolatedRecordMapProbe, FileManager.default.fileExists(atPath: url.path) else {
            throw VerificationError.sourceMissing
        }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSPersistentHistoryTrackingKey: true,
                      NSMigratePersistentStoresAutomaticallyOption: true,
                      NSInferMappingModelAutomaticallyOption: true])
        try coordinator.remove(store)
    }

    private func counts(_ inventory: Inventory) -> [String: Int] {
        inventory.mapValues { $0.values.reduce(0, +) }
    }

    private func recordMappingProbe(at url: URL, model: NSManagedObjectModel, activeCloud: Bool = false) async throws
        -> (total: Int, mapped: Int, keyCounts: [String: Int], containsCDID: [String: Bool]) {
        let probeModel: NSManagedObjectModel
        if activeCloud {
            guard let combined = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
                throw VerificationError.modelUnavailable
            }
            let names = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
            combined.setEntities(combined.entities.filter { names.contains($0.name ?? "") }, forConfigurationName: "History")
            probeModel = combined
        } else {
            probeModel = model
        }
        let container = NSPersistentCloudKitContainer(name: "ActualHistoryRecordMapProbe", managedObjectModel: probeModel)
        let description = NSPersistentStoreDescription(url: url)
        if activeCloud {
            description.configuration = "History"
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.workingout.jorsh")
            options.databaseScope = .private
            description.cloudKitContainerOptions = options
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        } else {
            description.cloudKitContainerOptions = nil
            description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        }
        description.setOption(false as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(false as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]
        var setupObserver: NSObjectProtocol?
        if activeCloud {
            setupObserver = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor [weak self] in
                    guard let self, event.storeIdentifier == self.sourceStoreIdentifier,
                          event.type == .setup, event.endDate != nil else { return }
                    self.receipt.activeProbeSetupSucceeded = event.succeeded
                    self.receipt.activeProbeSetupFailed = !event.succeeded
                    self.receipt.lastCloudErrorDomain = event.error.map { ($0 as NSError).domain }
                    self.receipt.lastCloudErrorCode = event.error.map { ($0 as NSError).code }
                    try? self.writeReceipt()
                }
            }
        }
        var closed = false
        defer {
            if let setupObserver { NotificationCenter.default.removeObserver(setupObserver) }
            if !closed {
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        if activeCloud {
            receipt.action = "waitingForActiveCloudKitSetup"
            try writeReceipt()
            let deadline = Date().addingTimeInterval(120)
            while !receipt.activeProbeSetupSucceeded && !receipt.activeProbeSetupFailed && Date() < deadline {
                try await Task.sleep(for: .seconds(1))
            }
            if receipt.activeProbeSetupFailed { throw VerificationError.activeProbeSetupFailed }
            guard receipt.activeProbeSetupSucceeded else { throw VerificationError.activeProbeSetupTimedOut }
        }
        let context = container.newBackgroundContext()
        context.undoManager = nil
        let entityNames = PersistenceController.legacyModelTypes.map { String(describing: $0) }.sorted()
        let pinLiveGeneration = !isIsolatedRecordMapProbe
        receipt.action = "readingSourceObjectIDs"
        try writeReceipt()
        let captured = Result { try context.performAndWait { () throws -> [String: [NSManagedObjectID]] in
            if pinLiveGeneration { try context.setQueryGenerationFrom(.current) }
            var objects: [String: [NSManagedObjectID]] = [:]
            for entity in entityNames {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
                request.resultType = .managedObjectIDResultType
                request.includesPendingChanges = false
                objects[entity] = try context.fetch(request)
            }
            return objects
        } }
        // Only permanent IDs survive the capture. Release the snapshot before
        // mapping APIs read CloudKit metadata on another coordinator context.
        try context.performAndWait {
            context.reset()
            if pinLiveGeneration { try context.setQueryGenerationFrom(nil) }
        }
        let objects = try captured.get()
        let allObjectIDs = entityNames.flatMap { objects[$0] ?? [] }
        receipt.action = "readingBulkRecordMappings"
        receipt.recordMapProbeTotal = allObjectIDs.count
        try writeReceipt()
        let mappings = await context.perform { container.recordIDs(for: allObjectIDs) }
        receipt.recordMapProbeMapped = mappings.count
        receipt.action = "readingRepresentativeRecords"
        try writeReceipt()
        var keyCounts: [String: Int] = [:]
        var containsCDID: [String: Bool] = [:]
        for entity in entityNames {
            let objectIDs = objects[entity] ?? []
            let representative = objectIDs.first { mappings[$0] != nil }
            if let representative, let record = await context.perform({ container.record(for: representative) }) {
                let keys = record.allKeys()
                keyCounts[entity] = keys.count
                containsCDID[entity] = keys.contains("CD_id")
            } else {
                keyCounts[entity] = -1
                containsCDID[entity] = false
            }
            receipt.representativeRecordKeyCounts = keyCounts
            receipt.representativeRecordContainsCDID = containsCDID
            try writeReceipt()
        }
        if activeCloud && ProcessInfo.processInfo.environment["PP_VALIDATE_NATIVE_RECORDS"] == "1" {
            receipt.nativeValidationRequested = true
            receipt.action = "validatingNativeRecordPayloads"
            try writeReceipt()
            guard mappings.count == allObjectIDs.count else {
                throw VerificationError.nativeValidationMissingMappings
            }
            let assetDirectory = root.appendingPathComponent("NativeValidation-" + UUID().uuidString, isDirectory: true)
            try CoachLocalOwnership.prepareDirectory(assetDirectory)
            defer { try? FileManager.default.removeItem(at: assetDirectory) }
            for offset in stride(from: 0, to: allObjectIDs.count, by: 100) {
                try Task.checkCancellation()
                let batch = Array(allObjectIDs[offset..<min(offset + 100, allObjectIDs.count)])
                let validated = try await context.perform {
                    defer { context.reset() }
                    let sourceObjects = try batch.map { try context.existingObject(with: $0) }
                    let records = try CloudHistoryCloudRecordEncoder.materializedRecords(
                        objects: sourceObjects, container: container, recordIDs: mappings,
                        assetDirectory: assetDirectory)
                    return records.count
                }
                guard validated == batch.count else { throw VerificationError.nativeValidationCountMismatch }
                receipt.nativeValidatedCount += validated
                try writeReceipt()
                await Task.yield()
            }
            receipt.nativeValidationAssetFileCount = try assetFileCount(in: assetDirectory)
            receipt.nativeValidationSucceeded = receipt.nativeValidatedCount == allObjectIDs.count
            try writeReceipt()
        }
        if activeCloud && ProcessInfo.processInfo.environment["PP_PERFORM_MISSING_REPAIR"] == "1" {
            receipt.missingRepairRequested = true
            guard receipt.nativeValidationSucceeded,
                  receipt.nativeValidatedCount == allObjectIDs.count,
                  mappings.count == allObjectIDs.count else {
                throw VerificationError.missingRepairRequiresValidation
            }
            receipt.action = "performingConditionalMissingRecordRepair"
            try writeReceipt()
            let repairContext = container.newBackgroundContext()
            repairContext.undoManager = nil
            let report: CloudHistoryMissingRecordRepair.Report
            do {
                report = try await CloudHistoryMissingRecordRepair.repair(
                    container: container, context: repairContext,
                    accountContainer: CKContainer(identifier: "iCloud.com.workingout.jorsh"),
                    onProgress: { [weak self] progress in
                        guard let self else { return }
                        self.receipt.missingRepairReport = progress
                        try? self.writeReceipt()
                    })
                try await repairContext.perform {
                    repairContext.reset()
                    try repairContext.setQueryGenerationFrom(nil)
                }
            } catch {
                try? await repairContext.perform {
                    repairContext.reset()
                    try repairContext.setQueryGenerationFrom(nil)
                }
                throw error
            }
            receipt.missingRepairReport = report
            try writeReceipt()
            guard report.allMappedRecordsPresent, report.unmappedPending == 0,
                  report.pendingReason == nil, report.accountUnchanged else {
                throw VerificationError.missingRepairIncomplete
            }
        }
        context.performAndWait { context.reset() }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        closed = true
        return (total: allObjectIDs.count, mapped: mappings.count, keyCounts: keyCounts, containsCDID: containsCDID)
    }

    private func assetFileCount(in directory: URL) throws -> Int {
        var count = 0
        if let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private func downloadedInventory(in container: ModelContainer) throws -> Inventory {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var inventory: Inventory = [:]
        func capture<Model: PersistentModel>(_ type: Model.Type, id: KeyPath<Model, UUID>) throws {
            var descriptor = FetchDescriptor<Model>()
            descriptor.propertiesToFetch = [id]
            var identifiers: [UUID: Int] = [:]
            for record in try context.fetch(descriptor) {
                identifiers[record[keyPath: id], default: 0] += 1
            }
            inventory[String(describing: type)] = identifiers
        }
        try capture(ExerciseDefinition.self, id: \.id)
        try capture(WorkoutSession.self, id: \.id)
        try capture(ExerciseLog.self, id: \.id)
        try capture(RunningSession.self, id: \.id)
        try capture(RunningPlan.self, id: \.id)
        try capture(RunningPlanSession.self, id: \.id)
        try capture(TrainingPlan.self, id: \.id)
        try capture(PlannedSession.self, id: \.id)
        try capture(WeightEntry.self, id: \.id)
        try capture(AIConversation.self, id: \.id)
        try capture(WorkoutTemplate.self, id: \.id)
        try capture(TemplateExercise.self, id: \.id)
        try capture(HealthWorkoutInboxItem.self, id: \.id)
        try capture(CardioWorkoutInboxItem.self, id: \.id)
        return inventory
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
                guard let self, let source = self.sourceStoreIdentifier,
                      event.storeIdentifier != source else { return }
                // The normal source and this fresh download are the only active
                // cloud stores; Coach is local. Never open a second coordinator
                // on the fresh store while CloudKit is setting it up.
                if self.freshStoreIdentifier == nil { self.freshStoreIdentifier = event.storeIdentifier }
                guard event.storeIdentifier == self.freshStoreIdentifier,
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
