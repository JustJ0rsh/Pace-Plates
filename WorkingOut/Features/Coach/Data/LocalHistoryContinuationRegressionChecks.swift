#if DEBUG
import Foundation
import SwiftData

@MainActor
enum LocalHistoryContinuationRegressionChecks {
    static func run() async throws -> Int {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ContinueHistoryChecks-\(UUID())")
        let root = folder.appendingPathComponent("ownership")
        let legacy = folder.appendingPathComponent("default.store")
        let priorDirectory = LocalHistoryContinuation.activeDirectory
        defer {
            LocalHistoryContinuation.activate(storeURL: priorDirectory?.appendingPathComponent("default.store"))
            try? FileManager.default.removeItem(at: folder)
        }
        let restoration = root.appendingPathComponent("iCloudRestoration")
        try CoachLocalOwnership.prepareDirectory(restoration)
        let original = Data("unreadable-retained-history".utf8)
        let journal = Data("unreadable-retained-journal".utf8)
        let journalURL = restoration.appendingPathComponent("restoration.json")
        try original.write(to: legacy)
        try journal.write(to: journalURL)
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw CoachRepositoryError.invalidValue("continued history regression: " + message) }
        }
        let controller = PersistenceController(restoringCloudKit: .none, inMemory: false,
            legacyStore: legacy, ownershipRoot: root)
        try require(controller.storageError != nil && !controller.isCoachLocal,
                    "unreadable history never exposes writable temporary storage")
        controller.continueWithNewLocalHistory()
        try require(controller.storageError == nil && controller.isCoachLocal && controller.isUsingContinuedHistory,
                    "explicit continuation opens usable local history")
        try require(!controller.isCloudBacked && controller.container.configurations.allSatisfy { !$0.isStoredInMemoryOnly },
                    "new entries have durable disk storage without cloud upload")
        let weight = WeightEntry(weight: 88, weightUnit: "kg")
        controller.container.mainContext.insert(weight)
        let nutrition = CoachNutritionLog(); nutrition.protein = 150
        nutrition.civilDate = CoachDate.civil(Date()); nutrition.timeZoneIdentifier = TimeZone.current.identifier
        controller.container.mainContext.insert(nutrition)
        try controller.container.mainContext.save()
        let selected = try LocalHistoryContinuation.selectedStoreURL(root: root)
        try require(selected != nil && selected != legacy, "the continued history is separate and selected durably")
        try require(try Data(contentsOf: legacy) == original && Data(contentsOf: journalURL) == journal,
                    "continuation never replaces retained history or its recovery journal")
        let reopened = PersistenceController(restoringCloudKit: .none, inMemory: false,
            legacyStore: legacy, ownershipRoot: root)
        try require(reopened.storageError == nil && reopened.isUsingContinuedHistory,
                    "ordinary startup reopens continued history without retrying broken originals")
        try require(try reopened.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == weight.id
                    && reopened.container.mainContext.fetch(FetchDescriptor<CoachNutritionLog>()).first?.protein == 150,
                    "weight and Coach records retain their exact identities and values after reopening")
        try require(CoachPhotoStore.directory.path.hasPrefix(selected!.deletingLastPathComponent().path + "/")
                    && CoachHistoryArchive.restoreDirectory.path.hasPrefix(selected!.deletingLastPathComponent().path + "/"),
                    "new photo and backup recovery files stay separate from unavailable history")
        let export = try await DataBackupService.exportAll(context: reopened.container.mainContext)
        defer { try? FileManager.default.removeItem(at: export) }
        let destination = PersistenceController(inMemory: true, cloudKitMode: .none)
        try await DataBackupService.import(from: export, context: destination.container.mainContext)
        try require(try destination.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == weight.id,
                    "new local entries remain portable through a real export and import")
        let marker = root.appendingPathComponent("ContinuedHistory/selection.json")
        let markerBytes = try Data(contentsOf: marker)
        try Data("corrupt-selection".utf8).write(to: marker)
        var rejected = false
        do { _ = try LocalHistoryContinuation.selectedStoreURL(root: root) } catch { rejected = true }
        try require(rejected, "a damaged selection never silently creates another empty history")
        try markerBytes.write(to: marker)
        try require(try LocalHistoryContinuation.selectedStoreURL(root: root) == selected,
                    "the saved selection still identifies the original continued records")

        // A canceled network check must release its owner before the real local
        // history opens. The injected wait never contacts an account or server.
        let offlineRoot = folder.appendingPathComponent("cancel-check")
        let offlineLegacy = offlineRoot.appendingPathComponent("default.store")
        try CoachLocalOwnership.prepareDirectory(offlineRoot)
        let offlineID = UUID()
        try autoreleasepool {
            let schema = Schema(PersistenceController.legacyModelTypes)
            let local = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
                url: offlineLegacy, cloudKitDatabase: .none)])
            local.mainContext.insert(WeightEntry(id: offlineID, weight: 75, weightUnit: "kg"))
            try local.mainContext.save()
        }
        var waiting = false
        let cancelable = PersistenceController(deferredHistoryForRegression: offlineLegacy, ownershipRoot: offlineRoot) { _ in
            waiting = true
            do { try await Task.sleep(for: .seconds(60)) }
            catch { }
            var report = CloudHistoryMissingRecordRepair.Report(); report.pendingReason = "cancelled"
            return report
        }
        let pending = Task { await cancelable.prepareStorageIfNeeded() }
        let deadline = Date().addingTimeInterval(5)
        while !waiting && cancelable.isPreparingStorage && Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try require(waiting, "explicit inspection reaches its pending network check")
        cancelable.continueWithoutCloudCheck()
        await pending.value
        try require(!cancelable.isPreparingStorage && cancelable.storageError == nil && !cancelable.isCloudBacked,
                    "skipping the pending cloud check opens normal local history")
        try require(try cancelable.container.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.id == offlineID,
                    "canceling the cloud wait retains the existing on-disk records")
        return checks
    }
}
#endif
