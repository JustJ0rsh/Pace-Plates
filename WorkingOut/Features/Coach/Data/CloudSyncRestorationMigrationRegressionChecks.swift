#if DEBUG
import Foundation
import SwiftData
import CoreData
import SQLite3

@MainActor
enum CloudSyncRestorationMigrationRegressionChecks {
    static func run() throws -> Int {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("CloudMigrationCompatibility-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? manager.removeItem(at: root) }
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            guard condition else { throw CoachLocalOwnership.migrationError("Compatibility regression: " + message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() }
            catch { checks += 1; return }
            throw CoachLocalOwnership.migrationError("Compatibility regression accepted " + message)
        }
        func model(_ types: [any PersistentModel.Type]) throws -> NSManagedObjectModel {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
                throw CoachLocalOwnership.migrationError("Synthetic model unavailable.")
            }
            return model
        }
        func withStore<T>(_ url: URL, model: NSManagedObjectModel, _ body: (NSManagedObjectContext) throws -> T) throws -> T {
            try CoachLocalOwnership.prepareDirectory(url.deletingLastPathComponent())
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true,
                          NSPersistentHistoryTrackingKey: true])
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            do {
                let result = try context.performAndWait { try body(context) }
                context.performAndWait { context.reset() }
                try coordinator.remove(store)
                return result
            } catch {
                context.performAndWait { context.reset() }
                try? coordinator.remove(store)
                throw error
            }
        }
        func insertWeight(_ id: UUID, value: Double, context: NSManagedObjectContext) {
            let row = NSEntityDescription.insertNewObject(forEntityName: "WeightEntry", into: context)
            row.setValue(id, forKey: "id"); row.setValue(Date(timeIntervalSince1970: 123), forKey: "date")
            row.setValue(value, forKey: "weight"); row.setValue("kg", forKey: "weightUnit")
        }
        func weight(_ url: URL, model: NSManagedObjectModel) throws -> (UUID?, Double?) {
            try withStore(url, model: model) { context in
                let row = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WeightEntry")).first
                return (row?.value(forKey: "id") as? UUID, row?.value(forKey: "weight") as? Double)
            }
        }
        func mutate(_ url: URL, sql: String) throws {
            var database: OpaquePointer?
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else {
                if let database { sqlite3_close(database) }
                throw CoachLocalOwnership.migrationError("Synthetic SQL unavailable.")
            }
            defer { sqlite3_close(database) }
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw CoachLocalOwnership.migrationError("Synthetic SQL failed.")
            }
        }

        let legacyModel = try model(PersistenceController.legacyModelTypes)
        let fullModel = try model(PersistenceController.legacyModelTypes + CoachPersistence.modelTypes)
        let weightModel = try model([WeightEntry.self])
        // Recreate the real pre-Coach WeightEntry schema, including its original
        // four attribute definitions. A current-model-set fixture cannot test
        // the additive-column transition that blocked 2.5.1 upgrades.
        let oldWeightModel = weightModel.copy() as! NSManagedObjectModel
        let oldEntity = oldWeightModel.entitiesByName["WeightEntry"]!
        let historicalFields: Set<String> = ["id", "date", "weight", "weightUnit"]
        oldEntity.properties = oldEntity.properties.filter { historicalFields.contains($0.name) }
        let historicalSource = root.appendingPathComponent("historical/default.store")
        let historicalID = UUID()
        try withStore(historicalSource, model: oldWeightModel) { context in
            insertWeight(historicalID, value: 77, context: context); try context.save()
        }
        let original = try CoachLocalOwnership.rawCheckpoint(historicalSource)
        try require(Set(original.columns["ZWEIGHTENTRY"] ?? []) == Set(["Z_PK", "Z_ENT", "Z_OPT", "ZID", "ZDATE", "ZWEIGHT", "ZWEIGHTUNIT"]),
                    "historical fixture contains no current provenance columns")
        let historicalCopy = root.appendingPathComponent("historical-copy/default.store")
        try CoachLocalOwnership.prepareDirectory(historicalCopy.deletingLastPathComponent())
        try CoachLocalOwnership.copyStore(from: historicalSource, to: historicalCopy)
        try CoachLocalOwnership.copyAuxiliaryFiles(from: historicalSource, to: historicalCopy)
        let upgraded = try weight(historicalCopy, model: weightModel)
        try require(upgraded.0 == historicalID && upgraded.1 == 77, "actual lightweight migration retains the historical identity and value")
        try rejects("new columns without a compiled allowlist") { try CoachLocalOwnership.verifyRetainedColumns(original, at: historicalCopy) }
        let allowedColumns = try CoachLocalOwnership.compiledMigrationColumns(for: [WeightEntry.self])
        try CoachLocalOwnership.verifyRetainedColumns(original, at: historicalCopy, allowedNewColumns: allowedColumns)
        try require(true, "compiled provenance additions pass original-column verification")
        try mutate(historicalCopy, sql: "UPDATE ZWEIGHTENTRY SET ZWEIGHT=78")
        try rejects("changed original values despite compiled additions") { try CoachLocalOwnership.verifyRetainedColumns(original, at: historicalCopy, allowedNewColumns: allowedColumns) }
        try mutate(historicalCopy, sql: "UPDATE ZWEIGHTENTRY SET ZWEIGHT=77")
        try mutate(historicalCopy, sql: "ALTER TABLE ZWEIGHTENTRY ADD COLUMN ZUNRECOGNIZED TEXT")
        try rejects("an unknown added column") { try CoachLocalOwnership.verifyRetainedColumns(original, at: historicalCopy, allowedNewColumns: allowedColumns) }
        try mutate(historicalCopy, sql: "ALTER TABLE ZWEIGHTENTRY DROP COLUMN ZUNRECOGNIZED; ALTER TABLE ZWEIGHTENTRY DROP COLUMN ZDATE")
        try rejects("a removed original column") { try CoachLocalOwnership.verifyRetainedColumns(original, at: historicalCopy, allowedNewColumns: allowedColumns) }
        try require(try CoachLocalOwnership.rawCheckpoint(historicalSource).identity == original.identity, "historical source remains unchanged")

        for phase in ["allocated", "copied", "verified"] {
            for oldJournal in [false, true] {
                let base = root.appendingPathComponent("migration-\(phase)-\(oldJournal)/old")
                let source = base.appendingPathComponent("default.store"), ownership = base.appendingPathComponent("ownership")
                try withStore(source, model: weightModel) { context in insertWeight(UUID(), value: 80, context: context); try context.save() }
                var journal = try CoachLocalOwnership.beginMigration(source: source, root: ownership)
                let checkpoint = try CoachLocalOwnership.rawCheckpoint(source).identity
                if phase != "allocated" {
                    let destination = CoachLocalOwnership.destination(for: journal, root: ownership)
                    try CoachLocalOwnership.prepareDirectory(destination.deletingLastPathComponent())
                    try CoachLocalOwnership.copyStore(from: source, to: destination)
                    try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: destination)
                    journal.checkpoint = checkpoint; journal.phase = phase
                }
                if oldJournal { journal.sourceRootPath = nil; journal.sourceStoreID = nil }
                try CoachLocalOwnership.writeJournal(journal, root: ownership)
                let moved = base.deletingLastPathComponent().appendingPathComponent("moved")
                try manager.moveItem(at: base, to: moved)
                let movedSource = moved.appendingPathComponent("default.store"), movedOwnership = moved.appendingPathComponent("ownership")
                let resumed = try CoachLocalOwnership.beginMigration(source: movedSource, root: movedOwnership)
                try require(resumed.source == movedSource.standardizedFileURL.path && resumed.sourceStoreID != nil,
                            "\(phase) \(oldJournal ? "old" : "new") migration journal resumes across whole-container relocation")
                try require(try CoachLocalOwnership.rawCheckpoint(movedSource).identity == checkpoint, "rebasing a migration does not alter its source")
                if phase != "allocated" {
                    try require(try CoachLocalOwnership.rawCheckpoint(CoachLocalOwnership.destination(for: resumed, root: movedOwnership)).identity == checkpoint,
                                "relocation preserves the previously copied migration destination")
                } else if oldJournal {
                    try require(resumed.id != journal.id && manager.fileExists(atPath: movedOwnership.appendingPathComponent("retained-migration-\(journal.id.uuidString).json").path),
                                "an old unverified allocation is retained before starting a newly bound copy")
                }
                let savedID = try CoachLocalOwnership.persistentStoreID(at: movedSource)
                try manager.moveItem(at: movedSource, to: moved.appendingPathComponent("retained.store"))
                try withStore(movedSource, model: weightModel) { context in insertWeight(UUID(), value: 80, context: context); try context.save() }
                try require(try CoachLocalOwnership.persistentStoreID(at: movedSource) != savedID, "adversarial fixture is a different persistent store")
                try rejects("a different migration source store with matching values") { _ = try CoachLocalOwnership.beginMigration(source: movedSource, root: movedOwnership) }
            }
        }

        for interruption in ["prepared", "backedUp", "installed", "complete"] {
            for oldJournal in [false, true] {
                let base = root.appendingPathComponent("restoration-\(interruption)-\(oldJournal)/old")
                let source = base.appendingPathComponent("default.store"), ownership = base.appendingPathComponent("ownership")
                let id = UUID()
                try withStore(source, model: legacyModel) { context in insertWeight(id, value: 80, context: context); try context.save() }
                let baseline = try CoachLocalOwnership.rawCheckpoint(source).identity
                let selected = try CoachLocalOwnership.newStagingStore(root: ownership)
                try CoachLocalOwnership.copyStore(from: source, to: selected)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: selected)
                try withStore(selected, model: fullModel) { context in
                    let row = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WeightEntry")).first!
                    row.setValue(82.0, forKey: "weight"); try context.save()
                }
                let selectionJournal = CoachLocalOwnership.MigrationJournal(id: UUID(), source: source.path,
                    directory: selected.deletingLastPathComponent().lastPathComponent, phase: "verified", checkpoint: baseline)
                try CoachLocalOwnership.writeJournal(selectionJournal, root: ownership)
                try CoachLocalOwnership.select(selected, legacy: source, root: ownership, journal: selectionJournal)
                if interruption == "complete" { _ = try CloudSyncRestoration.prepare(legacyURL: source, ownershipRoot: ownership) }
                else {
                    var reached = false
                    do { _ = try CloudSyncRestoration.prepare(legacyURL: source, ownershipRoot: ownership, interruptAfter: interruption) }
                    catch { reached = error.localizedDescription.contains("Synthetic interruption") }
                    try require(reached, "the relocation fixture reaches \(interruption)")
                }
                let journalURL = ownership.appendingPathComponent("iCloudRestoration/restoration.json")
                if oldJournal {
                    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as! [String: Any]
                    for field in ["ownershipPath", "historyStoreID", "coachStoreID"] { object.removeValue(forKey: field) }
                    try JSONSerialization.data(withJSONObject: object).write(to: journalURL, options: .atomic)
                }
                if interruption == "complete" {
                    try withStore(source, model: legacyModel) { context in
                        let row = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WeightEntry")).first!
                        row.setValue(84.0, forKey: "weight"); try context.save()
                    }
                }
                let moved = base.deletingLastPathComponent().appendingPathComponent("moved")
                try manager.moveItem(at: base, to: moved)
                let movedSource = moved.appendingPathComponent("default.store"), movedOwnership = moved.appendingPathComponent("ownership")
                let coach = try CloudSyncRestoration.prepare(legacyURL: movedSource, ownershipRoot: movedOwnership)
                try require(manager.fileExists(atPath: coach.path), "relocated \(interruption) \(oldJournal ? "old" : "new") journal retains Coach storage")
                let row = try weight(movedSource, model: legacyModel)
                try require(row.0 == id && row.1 == (interruption == "complete" ? 84 : 82), "whole-container relocation preserves current history without stale replay")
                let currentCheckpoint = try CoachLocalOwnership.rawCheckpoint(movedSource).identity
                let differentLocation = moved.appendingPathComponent("different/default.store")
                try rejects("the same file name in a different relative location") { _ = try CloudSyncRestoration.prepare(legacyURL: differentLocation, ownershipRoot: movedOwnership) }
                try require(try CoachLocalOwnership.rawCheckpoint(movedSource).identity == currentCheckpoint, "rejecting an unrelated path leaves restored history unchanged")
                try manager.moveItem(at: movedSource, to: moved.appendingPathComponent("retained.store"))
                try withStore(movedSource, model: legacyModel) { context in insertWeight(id, value: row.1!, context: context); try context.save() }
                try rejects("a different restored store with matching record values") { _ = try CloudSyncRestoration.prepare(legacyURL: movedSource, ownershipRoot: movedOwnership) }
            }
        }
        // Installed iOS apps resolve the unnamed store into the shared app
        // group. Its container UUID and the main-app UUID move independently.
        func containerPaths(_ name: String) -> (base: URL, group: URL, app: URL, source: URL, ownership: URL) {
            let base = root.appendingPathComponent(name + "/Containers")
            let group = base.appendingPathComponent("Shared/AppGroup/" + UUID().uuidString)
            let app = base.appendingPathComponent("Data/Application/" + UUID().uuidString)
            return (base, group, app, group.appendingPathComponent("Library/Application Support/default.store"),
                    app.appendingPathComponent("Library/Application Support/CoachLocalOwnership"))
        }
        func moveContainers(_ paths: (base: URL, group: URL, app: URL, source: URL, ownership: URL)) throws -> (URL, URL) {
            let movedGroup = paths.base.appendingPathComponent("Shared/AppGroup/" + UUID().uuidString)
            let movedApp = paths.base.appendingPathComponent("Data/Application/" + UUID().uuidString)
            try manager.moveItem(at: paths.group, to: movedGroup)
            try manager.moveItem(at: paths.app, to: movedApp)
            return (movedGroup.appendingPathComponent("Library/Application Support/default.store"),
                    movedApp.appendingPathComponent("Library/Application Support/CoachLocalOwnership"))
        }
        for oldJournal in [false, true] {
            let paths = containerPaths("group-migration-\(oldJournal)")
            try withStore(paths.source, model: weightModel) { context in insertWeight(UUID(), value: 80, context: context); try context.save() }
            var journal = try CoachLocalOwnership.beginMigration(source: paths.source, root: paths.ownership)
            journal.phase = "copied"; journal.checkpoint = try CoachLocalOwnership.rawCheckpoint(paths.source).identity
            let destination = CoachLocalOwnership.destination(for: journal, root: paths.ownership)
            try CoachLocalOwnership.prepareDirectory(destination.deletingLastPathComponent())
            try CoachLocalOwnership.copyStore(from: paths.source, to: destination)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: paths.source, to: destination)
            if oldJournal { journal.sourceRootPath = nil; journal.sourceStoreID = nil }
            try CoachLocalOwnership.writeJournal(journal, root: paths.ownership)
            try require(CoachLocalOwnership.sameRelocatedLegacyStore(paths.source.resolvingSymlinksInPath(),
                root: paths.ownership.resolvingSymlinksInPath(), recordedPath: paths.source.path, recordedRoot: paths.ownership.path),
                "system path aliases identify the same main/app-group container pair")
            let (source, ownership) = try moveContainers(paths)
            let resumed = try CoachLocalOwnership.beginMigration(source: source, root: ownership)
            try require(resumed.source == source.path && resumed.checkpoint == journal.checkpoint,
                        "app-group legacy and main-app \(oldJournal ? "old" : "new") migration journal relocate independently")
            try require(try CoachLocalOwnership.rawCheckpoint(source).identity == journal.checkpoint,
                        "separate app-group relocation retains source values")
        }
        for phase in ["prepared", "backedUp", "installed", "complete"] {
            for oldJournal in [false, true] {
                let paths = containerPaths("group-restore-\(phase)-\(oldJournal)")
                let id = UUID()
                try withStore(paths.source, model: legacyModel) { context in insertWeight(id, value: 80, context: context); try context.save() }
                let baseline = try CoachLocalOwnership.rawCheckpoint(paths.source).identity
                let selected = try CoachLocalOwnership.newStagingStore(root: paths.ownership)
                try CoachLocalOwnership.copyStore(from: paths.source, to: selected)
                try CoachLocalOwnership.copyAuxiliaryFiles(from: paths.source, to: selected)
                try withStore(selected, model: fullModel) { context in
                    let row = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "WeightEntry")).first!
                    row.setValue(82.0, forKey: "weight"); try context.save()
                }
                let selection = CoachLocalOwnership.MigrationJournal(id: UUID(), source: paths.source.path,
                    directory: selected.deletingLastPathComponent().lastPathComponent, phase: "verified", checkpoint: baseline)
                try CoachLocalOwnership.writeJournal(selection, root: paths.ownership)
                try CoachLocalOwnership.select(selected, legacy: paths.source, root: paths.ownership, journal: selection)
                if phase == "complete" { _ = try CloudSyncRestoration.prepare(legacyURL: paths.source, ownershipRoot: paths.ownership) }
                else {
                    var reached = false
                    do { _ = try CloudSyncRestoration.prepare(legacyURL: paths.source, ownershipRoot: paths.ownership, interruptAfter: phase) }
                    catch { reached = error.localizedDescription.contains("Synthetic interruption") }
                    try require(reached, "separate-container fixture reaches \(phase)")
                }
                let journalURL = paths.ownership.appendingPathComponent("iCloudRestoration/restoration.json")
                if oldJournal {
                    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as! [String: Any]
                    for field in ["ownershipPath", "historyStoreID", "coachStoreID"] { object.removeValue(forKey: field) }
                    try JSONSerialization.data(withJSONObject: object).write(to: journalURL, options: .atomic)
                }
                let (source, ownership) = try moveContainers(paths)
                let coach = try CloudSyncRestoration.prepare(legacyURL: source, ownershipRoot: ownership)
                let row = try weight(source, model: legacyModel)
                try require(row.0 == id && row.1 == 82 && manager.fileExists(atPath: coach.path),
                            "separate main/group \(phase) \(oldJournal ? "old" : "new") recovery retains history")
                let unrelated = root.appendingPathComponent("unrelated/default.store")
                try rejects("an unrelated group source after \(phase)") {
                    _ = try CloudSyncRestoration.prepare(legacyURL: unrelated, ownershipRoot: ownership)
                }
            }
        }
        return checks
    }
}
#endif
