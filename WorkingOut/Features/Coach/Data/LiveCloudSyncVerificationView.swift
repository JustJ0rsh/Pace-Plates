#if DEBUG
import SwiftUI
import SwiftData
import CloudKit
import CryptoKit
import CoreData
import UIKit

/// Explicit device-only acceptance harness. The caller supplies an isolated
/// launch configuration; no normal application store or defaults are selected.
struct LiveCloudSyncVerificationView: View {
    let runID: UUID
    let phase: String
    @State private var status = "Preparing live iCloud verification…"
    @State private var runner: LiveCloudSyncVerificationRunner?

    var body: some View {
        VStack(spacing: 20) {
            Text("Live iCloud verification").font(.title2.bold())
            Text(status).accessibilityIdentifier("live-cloud-sync.result")
        }
        .padding()
        .task {
            guard runner == nil else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            let driver = LiveCloudSyncVerificationRunner(runID: runID, phase: phase)
            runner = driver
            status = "Running \(phase)…"
            await driver.run()
            status = driver.status
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            runner?.stopObserving()
        }
    }
}

@MainActor
private final class LiveCloudSyncVerificationRunner {
    private struct Manifest: Codable {
        let runID: UUID
        let exerciseA: UUID
        let exerciseB: UUID
        let exerciseC: UUID
        let nutrition: UUID

        init(runID: UUID) {
            self.runID = runID
            exerciseA = Self.identifier(runID, "exercise-a")
            exerciseB = Self.identifier(runID, "exercise-b")
            exerciseC = Self.identifier(runID, "exercise-c")
            nutrition = Self.identifier(runID, "nutrition")
        }

        private static func identifier(_ runID: UUID, _ kind: String) -> UUID {
            let digest = Array(SHA256.hash(data: Data((runID.uuidString + ":" + kind).utf8)))
            return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5],
                               digest[6], digest[7], digest[8], digest[9], digest[10], digest[11],
                               digest[12], digest[13], digest[14], digest[15]))
        }
    }

    private struct CloudEvent: Codable {
        let type: String
        let completed: Bool
        let succeeded: Bool
        let error: String?
        let observedAt: Date
    }

    private struct Receipt: Codable {
        let runID: UUID
        let phase: String
        var status: String
        var error: String?
        var checks: [String: Bool]
        var syntheticServerRecordCount: Int?
        var updatedAt = Date()
        var action = "starting"
        var cloudEvents: [CloudEvent] = []
    }

    private enum VerificationError: String, Error {
        case invalidPhase
        case missingManifest
        case mismatchedManifest
        case accountUnavailable
        case seedNotPresentLocally
        case missingSelectedHistory
        case localCoachDataMissing
        case schemaRequiresDevelopmentProfile
        case schemaModelUnavailable
        case schemaModelMismatch
        case timedOut
    }

    private let runID: UUID
    private let phase: String
    private let root: URL
    private let cloud = CKContainer(identifier: "iCloud.com.workingout.jorsh")
    private var activeContainer: ModelContainer?
    private var schemaContainer: NSPersistentCloudKitContainer?
    private var cloudEventObserver: NSObjectProtocol?
    private var receipt: Receipt
    private(set) var status = "Preparing live iCloud verification…"

    private var legacyURL: URL { root.appendingPathComponent("default.store") }
    private var ownershipRoot: URL { root.appendingPathComponent("ownership", isDirectory: true) }
    private var prefix: String { "PP-Sync-" + runID.uuidString }
    private var originalA: String { prefix + "-A" }
    private var originalB: String { prefix + "-B" }
    private var editedA: String { prefix + "-A-edited" }
    private var newC: String { prefix + "-C-new" }
    private var manifestURL: URL { root.appendingPathComponent("manifest.json") }
    private var receiptURL: URL { root.appendingPathComponent("result-" + phase + ".json") }

    init(runID: UUID, phase: String) {
        self.runID = runID
        self.phase = phase
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveCloudSync", isDirectory: true)
            .appendingPathComponent(runID.uuidString, isDirectory: true)
        receipt = Receipt(runID: runID, phase: phase, status: "running", checks: [:])
    }

    func run() async {
        do {
            guard ["schema", "seed", "offline", "restore", "download", "cleanup"].contains(phase) else {
                throw VerificationError.invalidPhase
            }
            try CoachLocalOwnership.prepareDirectory(root)
            startObserving()
            try writeReceipt()
            let manifest = try loadManifest()
            if phase != "offline" {
                guard try await cloud.accountStatus() == .available else {
                    throw VerificationError.accountUnavailable
                }
                receipt.checks["accountAvailable"] = true
            }
            switch phase {
            case "schema": try await initializeSchema()
            case "seed": try await seed(manifest)
            case "offline": try offline(manifest)
            case "restore": try await restore(manifest)
            case "download": try await download(manifest)
            case "cleanup": try await cleanup()
            default: throw VerificationError.invalidPhase
            }
            receipt.status = "passed"
            receipt.action = "completed"
            status = "PASS: \(phase)"
        } catch {
            receipt.status = "failed"
            // External errors can contain record values or identifiers. Persist
            // only a stable code, never their descriptions or userInfo.
            if let failure = error as? VerificationError {
                receipt.error = failure.rawValue
            } else if error is CancellationError {
                receipt.error = "cancelled"
            } else {
                let failure = error as NSError
                receipt.error = "\(failure.domain):\(failure.code)"
            }
            status = "FAIL: \(phase) — \(receipt.error ?? "unknown")"
        }
        do { try writeReceipt() }
        catch { status += " (receipt could not be saved)" }
    }

    private func loadManifest() throws -> Manifest {
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
            guard manifest.runID == runID else { throw VerificationError.mismatchedManifest }
            return manifest
        }
        guard phase == "seed" || phase == "schema" else { throw VerificationError.missingManifest }
        let manifest = Manifest(runID: runID)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return manifest
    }

    private func writeReceipt() throws {
        receipt.updatedAt = Date()
        try JSONEncoder().encode(receipt).write(to: receiptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func startObserving() {
        guard cloudEventObserver == nil else { return }
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in self?.record(event) }
        }
    }

    func stopObserving() {
        if let cloudEventObserver { NotificationCenter.default.removeObserver(cloudEventObserver) }
        cloudEventObserver = nil
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        let type: String
        switch event.type {
        case .setup: type = "Setup"
        case .import: type = "Import"
        case .export: type = "Export"
        @unknown default: type = "Unknown"
        }
        let completed = event.endDate != nil
        let error = event.error.map { "\(($0 as NSError).domain):\(($0 as NSError).code)" }
        receipt.cloudEvents.append(CloudEvent(type: type.lowercased(), completed: completed,
                                              succeeded: completed && event.succeeded,
                                              error: error, observedAt: Date()))
        if receipt.cloudEvents.count > 40 { receipt.cloudEvents.removeFirst(receipt.cloudEvents.count - 40) }
        if completed {
            receipt.checks["cloud\(type)Completed"] = true
            if event.succeeded { receipt.checks["cloud\(type)Succeeded"] = true }
            else { receipt.checks["cloud\(type)Failed"] = true }
        }
        try? writeReceipt()
    }

    private func recordCloudConfiguration(_ container: ModelContainer, historyURL: URL) throws {
        let history = container.configurations.first { $0.url.standardizedFileURL == historyURL.standardizedFileURL }
        receipt.checks["historyCloudContainerMatches"] = history?.cloudKitContainerIdentifier == "iCloud.com.workingout.jorsh"
        try writeReceipt()
    }

    private func initializeSchema() async throws {
        receipt.action = "initializingDevelopmentSchema"
        // The release pipeline must also verify the actual code-signing
        // entitlement. This check refuses distribution profiles on-device.
        guard try hasDevelopmentCloudKitProfile() else {
            throw VerificationError.schemaRequiresDevelopmentProfile
        }
        receipt.checks["developmentProvisioningProfile"] = true
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.legacyModelTypes) else {
            throw VerificationError.schemaModelUnavailable
        }
        let expected = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
        guard Set(model.entities.compactMap(\.name)) == expected else {
            throw VerificationError.schemaModelMismatch
        }
        receipt.checks["legacyModelsOnly"] = true
        let container = NSPersistentCloudKitContainer(name: "PaceSchemaBootstrap", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: root.appendingPathComponent("schema-bootstrap.store"))
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.workingout.jorsh")
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = true
        container.persistentStoreDescriptions = [description]
        schemaContainer = container
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
        receipt.checks["schemaBootstrapStoreLoaded"] = true
        try writeReceipt()
        try await Task.detached(priority: .userInitiated) {
            try container.initializeCloudKitSchema(options: [])
        }.value
        receipt.checks["schemaInitialized"] = true
    }

    private func hasDevelopmentCloudKitProfile() throws -> Bool {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else { return false }
        let data = try Data(contentsOf: url)
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return false }
        let payload = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let profile = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any] else { return false }
        let environment = entitlements["com.apple.developer.icloud-container-environment"]
        if let value = environment as? String { return value == "Development" }
        if let allowed = environment as? [String] {
            return allowed.contains("Development") && entitlements["get-task-allow"] as? Bool == true
        }
        return false
    }

    private func seed(_ manifest: Manifest) async throws {
        receipt.action = "openingSeedStore"
        let container = try CloudSyncRestoration.makeContainer(
            legacyURL: legacyURL, coachURL: root.appendingPathComponent("coach.store"), cloudKitMode: .automatic)
        activeContainer = container
        try recordCloudConfiguration(container, historyURL: legacyURL)
        let context = container.mainContext
        let existing = Set(try context.fetch(FetchDescriptor<ExerciseDefinition>()).map(\.id))
        if !existing.contains(manifest.exerciseA) {
            context.insert(ExerciseDefinition(id: manifest.exerciseA, name: originalA, muscleGroup: "Synthetic", isUserDefined: true))
        }
        if !existing.contains(manifest.exerciseB) {
            context.insert(ExerciseDefinition(id: manifest.exerciseB, name: originalB, muscleGroup: "Synthetic", isUserDefined: true))
        }
        try context.save()
        receipt.checks["seedSavedLocally"] = true
        receipt.action = "waitingForSeedExport"
        try writeReceipt()
        try await waitForServer(expected: [originalA, originalB])
        receipt.checks["seedReadBackFromServer"] = true
    }

    private func offline(_ manifest: Manifest) throws {
        receipt.action = "savingOfflineChanges"
        let selected: URL
        let baselineCheckpoint: String
        if let retained = try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot) {
            selected = retained
            baselineCheckpoint = try CoachLocalOwnership.readJournal(root: ownershipRoot)?.checkpoint
                ?? CoachLocalOwnership.rawCheckpoint(legacyURL).identity
        } else {
            selected = try CoachLocalOwnership.newStagingStore(root: ownershipRoot)
            baselineCheckpoint = try autoreleasepool {
                let schema = Schema(PersistenceController.legacyModelTypes)
                let source = try ModelContainer(for: schema, configurations: [
                    ModelConfiguration(schema: schema, url: legacyURL, cloudKitDatabase: .none)
                ])
                let definitions = try source.mainContext.fetch(FetchDescriptor<ExerciseDefinition>())
                guard definitions.contains(where: { $0.id == manifest.exerciseA && $0.name == originalA }),
                      definitions.contains(where: { $0.id == manifest.exerciseB && $0.name == originalB }) else {
                    throw VerificationError.seedNotPresentLocally
                }
                try source.mainContext.save()
                let before = try CoachLocalOwnership.rawCheckpoint(legacyURL).identity
                try CoachLocalOwnership.copyStore(from: legacyURL, to: selected)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: legacyURL, to: selected)
                guard try CoachLocalOwnership.rawCheckpoint(legacyURL).identity == before else {
                    throw VerificationError.seedNotPresentLocally
                }
                receipt.checks["sourceUnchangedByCopy"] = true
                return before
            }
        }
        try autoreleasepool {
            let schema = PersistenceController.coachSchema
            let local = try ModelContainer(for: schema, configurations: [
                ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: selected, cloudKitDatabase: .none)
            ])
            let context = local.mainContext
            let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
            guard let a = definitions.first(where: { $0.id == manifest.exerciseA }) else {
                throw VerificationError.seedNotPresentLocally
            }
            a.name = editedA
            for b in definitions where b.id == manifest.exerciseB { context.delete(b) }
            if !definitions.contains(where: { $0.id == manifest.exerciseC }) {
                context.insert(ExerciseDefinition(id: manifest.exerciseC, name: newC, muscleGroup: "Synthetic", isUserDefined: true))
            }
            if !(try context.fetch(FetchDescriptor<CoachNutritionLog>()).contains(where: { $0.id == manifest.nutrition })) {
                let nutrition = CoachNutritionLog(id: manifest.nutrition)
                nutrition.civilDate = "2001-01-01"; nutrition.timeZoneIdentifier = "UTC"
                nutrition.protein = 123; nutrition.notes = prefix
                context.insert(nutrition)
            }
            try context.save()
        }
        let journal = CoachLocalOwnership.MigrationJournal(
            id: UUID(), source: legacyURL.standardizedFileURL.path,
            directory: selected.deletingLastPathComponent().lastPathComponent,
            phase: "verified", checkpoint: baselineCheckpoint)
        try CoachLocalOwnership.writeJournal(journal, root: ownershipRoot)
        try CoachLocalOwnership.select(selected, legacy: legacyURL, root: ownershipRoot, journal: journal)
        receipt.checks["offlineEditDeletionAndInsertionSaved"] = true
        receipt.checks["selectedLocalHistory"] = true
    }

    private func restore(_ manifest: Manifest) async throws {
        receipt.action = "preparingRestoration"
        guard try CoachLocalOwnership.selectedStoreURL(root: ownershipRoot) != nil else {
            throw VerificationError.missingSelectedHistory
        }
        let coachURL = try CloudSyncRestoration.prepare(legacyURL: legacyURL, ownershipRoot: ownershipRoot)
        let container = try CloudSyncRestoration.makeContainer(legacyURL: legacyURL, coachURL: coachURL, cloudKitMode: .automatic)
        activeContainer = container
        try recordCloudConfiguration(container, historyURL: legacyURL)
        guard try container.mainContext.fetch(FetchDescriptor<CoachNutritionLog>()).contains(where: {
            $0.id == manifest.nutrition && $0.protein == 123 && $0.notes == prefix
        }) else { throw VerificationError.localCoachDataMissing }
        receipt.checks["localCoachDataPreserved"] = true
        receipt.action = "waitingForRestoredExport"
        try writeReceipt()
        try await waitForServer(expected: [editedA, newC])
        receipt.checks["editAndInsertionReadBackFromServer"] = true
        receipt.checks["deletionReadBackFromServer"] = true
        receipt.checks["noSyntheticServerDuplicates"] = true
    }

    private func download(_ manifest: Manifest) async throws {
        receipt.action = "waitingForFreshImport"
        let directory = root.appendingPathComponent("download", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(directory)
        let container = try CloudSyncRestoration.makeContainer(
            legacyURL: directory.appendingPathComponent("default.store"),
            coachURL: directory.appendingPathComponent("coach.store"), cloudKitMode: .automatic)
        activeContainer = container
        try recordCloudConfiguration(container, historyURL: directory.appendingPathComponent("default.store"))
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let context = ModelContext(container)
            let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
                .filter { $0.name.hasPrefix(prefix) }
            let names = definitions.map(\.name)
            try writeReceipt()
            if names.count == 2 && Set(names) == Set([editedA, newC])
                && Set(definitions.map(\.id)) == Set([manifest.exerciseA, manifest.exerciseC]) {
                receipt.checks["freshStoreDownloadedEditAndInsertion"] = true
                receipt.checks["freshStoreHasNoDeletedRecord"] = true
                receipt.checks["freshStoreHasNoSyntheticDuplicates"] = true
                receipt.checks["freshStorePreservesSyntheticIDs"] = true
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw VerificationError.timedOut
    }

    private func cleanup() async throws {
        receipt.action = "waitingForCleanupExport"
        let coachURL = try CloudSyncRestoration.prepare(legacyURL: legacyURL, ownershipRoot: ownershipRoot)
        let container = try CloudSyncRestoration.makeContainer(legacyURL: legacyURL, coachURL: coachURL, cloudKitMode: .automatic)
        activeContainer = container
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let context = ModelContext(container)
            let synthetic = try context.fetch(FetchDescriptor<ExerciseDefinition>()).filter { $0.name.hasPrefix(prefix) }
            for definition in synthetic { context.delete(definition) }
            if context.hasChanges { try context.save() }
            let names = try await serverNames(deadline: deadline)
            receipt.syntheticServerRecordCount = names.count
            if names.isEmpty {
                receipt.checks["syntheticServerRecordsRemoved"] = true
                receipt.checks["onlyRunPrefixedDefinitionsDeleted"] = true
                return
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw VerificationError.timedOut
    }

    private func waitForServer(expected: Set<String>) async throws {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try Task.checkCancellation()
            let names = try await serverNames(deadline: deadline)
            receipt.syntheticServerRecordCount = names.count
            try writeReceipt()
            if names.count == expected.count && Set(names) == expected { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw VerificationError.timedOut
    }

    /// Only run-prefixed exercise names survive this readback. Other private
    /// records are neither retained nor written to a receipt or console.
    private func serverNames(deadline: Date) async throws -> [String] {
        let database = cloud.privateCloudDatabase
        let zones = try await database.allRecordZones()
        var names: [CKRecord.ID: String] = [:]
        for zone in zones where zone.zoneID != CKRecordZone.default().zoneID {
            var token: CKServerChangeToken?
            var more = true
            while more {
                try Task.checkCancellation()
                guard Date() < deadline else { throw VerificationError.timedOut }
                let page = try await database.recordZoneChanges(
                    inZoneWith: zone.zoneID, since: token,
                    desiredKeys: ["CD_name"], resultsLimit: 200)
                for (recordID, modification) in page.modificationResultsByID {
                    let record = try modification.get().record
                    if record.recordType == "CD_ExerciseDefinition",
                       let name = record["CD_name"] as? String, name.hasPrefix(prefix) {
                        names[recordID] = name
                    }
                }
                for deletion in page.deletions { names.removeValue(forKey: deletion.recordID) }
                token = page.changeToken
                more = page.moreComing
            }
        }
        return Array(names.values)
    }
}
#endif
