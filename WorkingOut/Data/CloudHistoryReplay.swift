import Foundation
import CoreData
import SwiftData

/// Replays the local-only interval into a disposable copy of the original
/// CloudKit store. Normal context saves create fresh export history while the
/// original store identity and mirroring metadata remain intact.
enum CloudHistoryReplay {
    private static let author = "icloud-restoration-v1"

    @MainActor
    static func replay(baselineURL: URL, localSnapshotURL: URL, destinationURL: URL,
                       allowDeletions: Bool) throws {
        let paths = [baselineURL, localSnapshotURL, destinationURL]
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        guard Set(paths).count == paths.count else {
            throw failure("History replay requires separate disposable source and destination files.")
        }
        let legacySchema = Schema(PersistenceController.legacyModelTypes)
        let names = Set(PersistenceController.legacyModelTypes.map { String(describing: $0) })
        guard let legacyModel = NSManagedObjectModel.makeManagedObjectModel(for: legacySchema),
              let fullModel = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema) else {
            throw failure("The history replay model could not be prepared.")
        }
        // The baseline is itself an owned copy. Additive schema migration may
        // populate defaults there, but neither retained original is opened here.
        let baseline = try withStore(at: baselineURL, model: legacyModel, readOnly: false) {
            try capture($0, entityNames: names).graph
        }
        let local = try withStore(at: localSnapshotURL, model: fullModel, readOnly: true) {
            try capture($0, entityNames: names).graph
        }
        try withStore(at: destinationURL, model: legacyModel, readOnly: false) { context in
            let before = try capture(context, entityNames: names)
            guard before.graph == baseline else {
                throw failure("The destination no longer matches its retained baseline.")
            }
            let deletions = allowDeletions ? Set(baseline.keys).subtracting(local.keys) : []
            let expected = try desiredGraph(baseline: baseline, local: local, deletions: deletions, model: legacyModel)
            try validateRelationships(expected)

            let previousToken = try history(context, after: nil).max { $0.transactionNumber < $1.transactionNumber }?.token
            context.transactionAuthor = author
            var objects = before.objects
            var inserted: [NSManagedObject] = []
            var updated: [NSManagedObject] = []
            var deletedIDs: Set<NSManagedObjectID> = []

            // Allocate the full graph before connecting any relationships.
            for key in expected.keys.sorted() where baseline[key] == nil {
                let object = NSEntityDescription.insertNewObject(forEntityName: key.entity, into: context)
                objects[key] = object
                inserted.append(object)
            }
            for key in expected.keys.sorted() {
                guard let row = expected[key], let object = objects[key] else {
                    throw failure("A replay record could not be resolved.")
                }
                let previous = baseline[key]
                if let previous {
                    guard previous.attributes.keys.sorted() == row.attributes.keys.sorted(),
                          previous.relationships.keys.sorted() == row.relationships.keys.sorted() else {
                        throw failure("The replay source and destination models disagree.")
                    }
                }
                var changed = false
                for (name, value) in row.attributes where previous?.attributes[name] != value {
                    object.setValue(value.foundationValue, forKey: name)
                    changed = true
                }
                for (name, value) in row.relationships where previous?.relationships[name] != value {
                    object.setValue(try value.foundationValue(objects: objects), forKey: name)
                    changed = true
                }
                if changed, previous != nil { updated.append(object) }
            }
            // Relationships have their final values before cascade rules run.
            for key in deletions.sorted() {
                guard let object = objects[key] else { throw failure("A deleted record could not be resolved.") }
                deletedIDs.insert(object.objectID)
                context.delete(object)
            }
            if context.hasChanges { try context.save() }
            // Inserted rows receive destination object IDs on save. Retain their
            // source identity for verification without conflating equal app UUIDs.
            var aliases: [NSManagedObjectID: RecordKey] = [:]
            for (identity, object) in objects where expected[identity] != nil {
                guard !object.objectID.isTemporaryID,
                      aliases[object.objectID] == nil else {
                    throw failure("The replay did not preserve distinct record identities.")
                }
                aliases[object.objectID] = identity
            }
            guard try capture(context, entityNames: names, aliases: aliases).graph == expected else {
                throw failure("Replaying the local changes did not preserve the expected history.")
            }

            if !inserted.isEmpty || !updated.isEmpty || !deletedIDs.isEmpty {
                let changes = try history(context, after: previousToken)
                    .filter { $0.author == author }.flatMap { $0.changes ?? [] }
                let insertedIDs = Set(changes.filter { $0.changeType == .insert }.map(\.changedObjectID))
                let updatedIDs = Set(changes.filter { $0.changeType == .update }.map(\.changedObjectID))
                let recordedDeletes = Set(changes.filter { $0.changeType == .delete }.map(\.changedObjectID))
                guard Set(inserted.map(\.objectID)).isSubset(of: insertedIDs),
                      Set(updated.map(\.objectID)).isSubset(of: updatedIDs),
                      deletedIDs.isSubset(of: recordedDeletes) else {
                    throw failure("The replay saved records without the required synchronization history.")
                }
            }
        }
    }

    @MainActor
    static func verifyCoachCopy(sourceURL: URL, destinationURL: URL) throws {
        let names = Set(CoachPersistence.modelTypes.map { String(describing: $0) })
        guard let full = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceController.coachSchema),
              let local = NSManagedObjectModel.makeManagedObjectModel(for: CoachPersistence.modelTypes) else {
            throw failure("The Coach verification model could not be prepared.")
        }
        let source = try withStore(at: sourceURL, model: full, readOnly: true) { try capture($0, entityNames: names).graph }
        let copy = try withStore(at: destinationURL, model: local, readOnly: true) { try capture($0, entityNames: names).graph }
        guard source == copy else { throw failure("The local Coach copy did not preserve every stored value.") }
    }

    private struct RecordKey: Hashable, Comparable {
        let entity: String
        let id: UUID
        let rowIdentity: String

        static func < (lhs: RecordKey, rhs: RecordKey) -> Bool {
            if lhs.entity != rhs.entity { return lhs.entity < rhs.entity }
            if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.rowIdentity < rhs.rowIdentity
        }
    }

    private struct Row: Equatable {
        let attributes: [String: Value]
        let relationships: [String: Relationship]
    }

    private struct Snapshot {
        let graph: [RecordKey: Row]
        let objects: [RecordKey: NSManagedObject]
    }

    /// Immutable Foundation representations cover the current schema, including
    /// transformable arrays. Unsupported custom classes fail before installation.
    private indirect enum Value: Equatable {
        case null, string(String), uuid(UUID), date(Date), data(Data), url(URL), number(NSNumber)
        case array([Value]), dictionary([String: Value])

        init(_ raw: Any?) throws {
            guard let raw, !(raw is NSNull) else { self = .null; return }
            switch raw {
            case let value as UUID: self = .uuid(value)
            case let value as Date: self = .date(value)
            case let value as Data: self = .data(value)
            case let value as URL: self = .url(value)
            case let value as String: self = .string(value)
            case let value as NSNumber: self = .number(value)
            case let value as [Any]: self = .array(try value.map(Value.init))
            case let value as [String: Any]: self = .dictionary(try value.mapValues(Value.init))
            default: throw CloudHistoryReplay.failure("A stored attribute has an unsupported value type.")
            }
        }

        var foundationValue: Any? {
            switch self {
            case .null: return nil
            case .string(let value): return value as NSString
            case .uuid(let value): return value as NSUUID
            case .date(let value): return value as NSDate
            case .data(let value): return value as NSData
            case .url(let value): return value as NSURL
            case .number(let value): return value
            case .array(let values): return values.map { $0.foundationValue ?? NSNull() } as NSArray
            case .dictionary(let values): return values.mapValues { $0.foundationValue ?? NSNull() } as NSDictionary
            }
        }
    }

    private enum Relationship: Equatable {
        case one(RecordKey?)
        case many([RecordKey], ordered: Bool)

        var targets: [RecordKey] {
            switch self {
            case .one(let key): return key.map { [$0] } ?? []
            case .many(let keys, _): return keys
            }
        }

        var empty: Relationship {
            switch self {
            case .one: return .one(nil)
            case .many(_, let ordered): return .many([], ordered: ordered)
            }
        }

        func adding(_ key: RecordKey) -> Relationship {
            switch self {
            case .one: return .one(key)
            case .many(let keys, let ordered):
                let combined = keys.contains(key) ? keys : keys + [key]
                return .many(ordered ? combined : combined.sorted(), ordered: ordered)
            }
        }

        func removing(_ key: RecordKey) -> Relationship {
            switch self {
            case .one(let target): return .one(target == key ? nil : target)
            case .many(let keys, let ordered): return .many(keys.filter { $0 != key }, ordered: ordered)
            }
        }

        func retainingMissingTargets(from baseline: Relationship, retained: Set<RecordKey>) -> Relationship {
            switch self {
            case .one(nil):
                return baseline.targets.contains(where: retained.contains) ? baseline : self
            case .one: return self
            case .many:
                return baseline.targets.filter(retained.contains).reduce(self) { $0.adding($1) }
            }
        }

        func foundationValue(objects: [RecordKey: NSManagedObject]) throws -> Any? {
            let resolved = try targets.map { key in
                guard let object = objects[key] else { throw CloudHistoryReplay.failure("A replay relationship target is missing.") }
                return object
            }
            switch self {
            case .one: return resolved.first
            case .many(_, let ordered): return ordered ? NSOrderedSet(array: resolved) : NSSet(array: resolved)
            }
        }
    }

    /// Retained rows need their inverse links retained too. Reconcile the desired
    /// graph using the same inverse relationships that Core Data applies on save.
    private static func desiredGraph(baseline: [RecordKey: Row], local: [RecordKey: Row],
                                     deletions: Set<RecordKey>, model: NSManagedObjectModel) throws -> [RecordKey: Row] {
        var graph = baseline
        let retained = Set(baseline.keys).subtracting(local.keys).subtracting(deletions)
        for (key, row) in local {
            graph[key] = Row(attributes: row.attributes,
                             relationships: baseline[key]?.relationships ?? row.relationships.mapValues(\.empty))
        }
        for key in local.keys.sorted() {
            guard let row = local[key] else { continue }
            for name in row.relationships.keys.sorted() {
                guard let value = row.relationships[name] else { continue }
                let desired = baseline[key]?.relationships[name].map {
                    value.retainingMissingTargets(from: $0, retained: retained)
                } ?? value
                try setRelationship(desired, named: name, owner: key, graph: &graph, model: model)
            }
        }
        for key in deletions.sorted() {
            guard let row = graph[key] else { continue }
            for (name, value) in row.relationships {
                try setRelationship(value.empty, named: name, owner: key, graph: &graph, model: model)
            }
            graph.removeValue(forKey: key)
        }
        return graph
    }

    private static func setRelationship(_ value: Relationship, named name: String, owner: RecordKey,
                                        graph: inout [RecordKey: Row], model: NSManagedObjectModel) throws {
        guard let row = graph[owner], let previous = row.relationships[name] else {
            throw failure("The replay relationship model could not be resolved.")
        }
        guard previous != value else { return }
        var relationships = row.relationships
        relationships[name] = value
        graph[owner] = Row(attributes: row.attributes, relationships: relationships)
        guard let inverse = model.entitiesByName[owner.entity]?.relationshipsByName[name]?.inverseRelationship else { return }
        let removed = Set(previous.targets).subtracting(value.targets)
        let added = Set(value.targets).subtracting(previous.targets)
        for target in removed.sorted() {
            guard let back = graph[target]?.relationships[inverse.name] else {
                throw failure("An inverse replay relationship is missing.")
            }
            try setRelationship(back.removing(owner), named: inverse.name, owner: target, graph: &graph, model: model)
        }
        for target in added.sorted() {
            guard let back = graph[target]?.relationships[inverse.name] else {
                throw failure("An inverse replay relationship is missing.")
            }
            try setRelationship(back.adding(owner), named: inverse.name, owner: target, graph: &graph, model: model)
        }
    }

    private static func key(for object: NSManagedObject,
                            aliases: [NSManagedObjectID: RecordKey]) throws -> RecordKey {
        if let alias = aliases[object.objectID] { return alias }
        guard let entity = object.entity.name, let id = object.value(forKey: "id") as? UUID else {
            throw failure("A stored record is missing its stable identity.")
        }
        guard !object.objectID.isTemporaryID else { throw failure("A stored record has no permanent row identity.") }
        // Both source stores descend from the same SQLite graph. Their row
        // suffix survives copying, unlike the store UUID changed for Coach.
        let rowIdentity = object.objectID.uriRepresentation().lastPathComponent
        guard !rowIdentity.isEmpty else { throw failure("A stored record has an invalid row identity.") }
        return RecordKey(entity: entity, id: id, rowIdentity: rowIdentity)
    }

    private static func capture(_ context: NSManagedObjectContext, entityNames: Set<String>,
                                aliases: [NSManagedObjectID: RecordKey] = [:]) throws -> Snapshot {
        var graph: [RecordKey: Row] = [:]
        var objects: [RecordKey: NSManagedObject] = [:]
        for entityName in entityNames.sorted() {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.returnsObjectsAsFaults = false
            for object in try context.fetch(request) {
                let identity = try key(for: object, aliases: aliases)
                guard graph[identity] == nil else { throw failure("History contains a repeated physical record identity.") }
                var attributes: [String: Value] = [:]
                for (name, attribute) in object.entity.attributesByName where !attribute.isTransient {
                    guard !(attribute is NSDerivedAttributeDescription) else {
                        throw failure("A derived attribute requires a reviewed replay rule.")
                    }
                    attributes[name] = try Value(object.value(forKey: name))
                }
                var relationships: [String: Relationship] = [:]
                for (name, relationship) in object.entity.relationshipsByName where !relationship.isTransient {
                    let raw = object.value(forKey: name)
                    if relationship.isToMany {
                        let members: [NSManagedObject]
                        if let ordered = raw as? NSOrderedSet, let values = ordered.array as? [NSManagedObject] {
                            members = values
                        } else if let unordered = raw as? NSSet, let values = unordered.allObjects as? [NSManagedObject] {
                            members = values
                        } else if raw == nil { members = [] }
                        else { throw failure("A stored relationship has an unsupported collection.") }
                        let keys = try members.map { try key(for: $0, aliases: aliases) }
                        relationships[name] = .many(relationship.isOrdered ? keys : keys.sorted(), ordered: relationship.isOrdered)
                    } else if let target = raw as? NSManagedObject {
                        relationships[name] = .one(try key(for: target, aliases: aliases))
                    } else if raw == nil { relationships[name] = .one(nil) }
                    else { throw failure("A stored relationship has an unsupported target.") }
                }
                graph[identity] = Row(attributes: attributes, relationships: relationships)
                objects[identity] = object
            }
        }
        try validateRelationships(graph)
        return Snapshot(graph: graph, objects: objects)
    }

    private static func validateRelationships(_ graph: [RecordKey: Row]) throws {
        let identities = Set(graph.keys)
        guard graph.values.allSatisfy({ row in
            row.relationships.values.allSatisfy { Set($0.targets).isSubset(of: identities) }
        }) else { throw failure("History contains an unresolved relationship.") }
    }

    private static func history(_ context: NSManagedObjectContext, after token: NSPersistentHistoryToken?) throws -> [NSPersistentHistoryTransaction] {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.resultType = .transactionsAndChanges
        guard let result = try context.execute(request) as? NSPersistentHistoryResult else {
            throw failure("The synchronization history could not be inspected.")
        }
        guard let raw = result.result else { return [] }
        guard let transactions = raw as? [NSPersistentHistoryTransaction] else {
            throw failure("The synchronization history returned an unsupported result.")
        }
        return transactions
    }

    private static func withStore<T>(at url: URL, model: NSManagedObjectModel, readOnly: Bool,
                                     operation: (NSManagedObjectContext) throws -> T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { throw failure("A history replay source file is missing.") }
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [AnyHashable: Any] = [
            NSPersistentHistoryTrackingKey: true,
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: true,
            NSReadOnlyPersistentStoreOption: readOnly,
            NSMigratePersistentStoresAutomaticallyOption: !readOnly,
            NSInferMappingModelAutomaticallyOption: !readOnly
        ]
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: options)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        let result = Result { try context.performAndWait { try operation(context) } }
        context.performAndWait { context.reset() }
        // Removal is checked even after the operation fails; the caller must not
        // install a candidate that an offline coordinator still has open.
        try coordinator.remove(store)
        return try result.get()
    }

    private static func failure(_ message: String) -> CoachLocalOwnership.OwnershipError {
        .unavailable(message + " The original history is retained; iCloud restoration was not committed.")
    }
}
