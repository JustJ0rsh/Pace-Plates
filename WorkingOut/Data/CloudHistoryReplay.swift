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
            var expected = baseline
            for (key, row) in local { expected[key] = row }
            let deletions = allowDeletions ? Set(baseline.keys).subtracting(local.keys) : []
            for key in deletions { expected.removeValue(forKey: key) }
            try validateRelationships(expected)

            let previousToken = try history(context, after: nil).max { $0.transactionNumber < $1.transactionNumber }?.token
            context.transactionAuthor = author
            var objects = before.objects
            var inserted: [NSManagedObject] = []
            var updated: [NSManagedObject] = []
            var deletedIDs: Set<NSManagedObjectID> = []

            // Allocate the full graph before connecting any relationships.
            for key in local.keys.sorted() where baseline[key] == nil {
                let object = NSEntityDescription.insertNewObject(forEntityName: key.entity, into: context)
                objects[key] = object
                inserted.append(object)
            }
            for key in local.keys.sorted() {
                guard let row = local[key], let object = objects[key] else {
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
            guard try capture(context, entityNames: names).graph == expected else {
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

        static func < (lhs: RecordKey, rhs: RecordKey) -> Bool {
            lhs.entity == rhs.entity ? lhs.id.uuidString < rhs.id.uuidString : lhs.entity < rhs.entity
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

    private static func key(for object: NSManagedObject) throws -> RecordKey {
        guard let entity = object.entity.name, let id = object.value(forKey: "id") as? UUID else {
            throw failure("A stored record is missing its stable identity.")
        }
        return RecordKey(entity: entity, id: id)
    }

    private static func capture(_ context: NSManagedObjectContext, entityNames: Set<String>) throws -> Snapshot {
        var graph: [RecordKey: Row] = [:]
        var objects: [RecordKey: NSManagedObject] = [:]
        for entityName in entityNames.sorted() {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.returnsObjectsAsFaults = false
            for object in try context.fetch(request) {
                let identity = try key(for: object)
                guard graph[identity] == nil else { throw failure("History contains duplicate stable identities.") }
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
                        let keys = try members.map(key(for:))
                        relationships[name] = .many(relationship.isOrdered ? keys : keys.sorted(), ordered: relationship.isOrdered)
                    } else if let target = raw as? NSManagedObject {
                        relationships[name] = .one(try key(for: target))
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
