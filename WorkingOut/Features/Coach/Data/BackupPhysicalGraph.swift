import Foundation
import SwiftData
import CryptoKit

/// Version 6 keeps app UUIDs in the ordinary snapshots and records physical
/// relationships separately. Archive keys never become committed app IDs.
struct BackupPhysicalGraph: Codable, Sendable {
    struct Row: Codable, Sendable {
        var key: String
        var collection: String
        var index: Int
        var applicationID: UUID
        var relationships: [String: [String]]
    }
    var version = 1
    var rows: [Row]

    static func sorted<T: PersistentModel>(_ rows: [T]) -> [T] {
        rows.sorted { String(describing: $0.persistentModelID) < String(describing: $1.persistentModelID) }
    }

    static func needsPhysicalIdentities(_ file: BackupFile) -> Bool {
        let collections: [[UUID]] = [
            file.exerciseDefinitions.map(\.id), file.workoutSessions.map(\.id), file.exerciseLogs.map(\.id),
            file.runningSessions.map(\.id), file.weightEntries.map(\.id), (file.runningPlans ?? []).map(\.id),
            (file.runningPlanSessions ?? []).map(\.id), (file.aiConversations ?? []).map(\.id),
            (file.workoutTemplates ?? []).map(\.id), (file.templateExercises ?? []).map(\.id),
            (file.healthWorkoutInboxItems ?? []).map(\.id), (file.cardioWorkoutInboxItems ?? []).map(\.id),
            (file.coach?.trainingPlans ?? []).map(\.id), (file.coach?.plannedSessions ?? []).map(\.id),
            (file.coach?.revisions ?? []).map(\.id), (file.coach?.executions ?? []).map(\.id),
            (file.coach?.suggestions ?? []).map(\.id), (file.coach?.targets ?? []).map(\.id),
            (file.coach?.nutrition ?? []).map(\.id), (file.coach?.recovery ?? []).map(\.id),
            (file.coach?.waist ?? []).map(\.id), (file.coach?.photos ?? []).map(\.id),
            (file.coach?.phaseReviews ?? []).map(\.id), (file.coach?.calendarMappings ?? []).map(\.id)
        ]
        return collections.contains { Set($0).count != $0.count }
    }

    var containsDuplicateApplicationIDs: Bool {
        Set(rows.map { Self.applicationKey($0.collection, $0.applicationID) }).count != rows.count
    }

    private static func applicationKey(_ collection: String, _ id: UUID) -> String { collection + "/" + id.uuidString }
    private static func failure(_ message: String) -> CoachHistoryArchive.ArchiveError { .invalid(message) }
    private static func archiveKey(_ collection: String, _ identifier: PersistentIdentifier) -> String {
        SHA256.hash(data: Data((collection + "/" + String(describing: identifier)).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func collections(in file: BackupFile) throws -> [String: [[String: Any]]] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as! [String: Any]
        let coach = object["coach"] as? [String: Any] ?? [:]
        return Dictionary(uniqueKeysWithValues: collectionNames.map { name in
            let value = name.hasPrefix("coach.") ? coach[String(name.dropFirst(6))] : object[name]
            return (name, value as? [[String: Any]] ?? [])
        })
    }

    static func replacingCollections(in file: BackupFile, with collections: [String: [[String: Any]]]) throws -> BackupFile {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(file)) as! [String: Any]
        var coach = object["coach"] as? [String: Any] ?? [:]
        for (name, entries) in collections {
            if name.hasPrefix("coach.") { coach[String(name.dropFirst(6))] = entries }
            else { object[name] = entries }
        }
        object["coach"] = coach
        object["formatVersion"] = 5
        object.removeValue(forKey: "physicalRecords")
        return try JSONDecoder().decode(BackupFile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func validate(in file: BackupFile) throws {
        guard version == 1, rows.count <= 100_000 else { throw Self.failure("Unsupported physical record graph") }
        let snapshots = try Self.collections(in: file)
        guard rows.count == snapshots.values.reduce(0, { $0 + $1.count }),
              Set(rows.map(\.key)).count == rows.count,
              Set(rows.map { $0.collection + "/" + String($0.index) }).count == rows.count else {
            throw Self.failure("Physical record graph does not identify every snapshot exactly once")
        }
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        for row in rows {
            guard row.key.count == 64, row.key.allSatisfy(\.isHexDigit),
                  let entries = snapshots[row.collection], entries.indices.contains(row.index),
                  let rawID = entries[row.index]["id"] as? String, UUID(uuidString: rawID) == row.applicationID,
                  Set(row.relationships.keys) == Set(Self.relationships[row.collection]?.keys ?? Dictionary<String, Relation>().keys) else {
                throw Self.failure("Invalid physical record identity or relationship names")
            }
            for (name, targets) in row.relationships {
                if let field = Self.relationshipForeignKeys[row.collection + "/" + name] {
                    let raw = entries[row.index][field] as? String
                    let storedID = raw.flatMap(UUID.init(uuidString:))
                    guard storedID == targets.first.flatMap({ byKey[$0]?.applicationID }) else {
                        throw Self.failure("Physical relationship disagrees with its UUID snapshot")
                    }
                }
                guard let relation = Self.relationships[row.collection]?[name],
                      relation.many || targets.count <= 1,
                      Set(targets).count == targets.count,
                      targets.allSatisfy({ byKey[$0]?.collection == relation.collection }) else {
                    throw Self.failure("Invalid physical relationship target")
                }
            }
        }
        for row in rows {
            for (name, targets) in row.relationships {
                guard let inverse = Self.inverseRelationships[row.collection + "/" + name] else { continue }
                for target in targets where byKey[target]?.relationships[inverse]?.contains(row.key) != true {
                    throw Self.failure("Inconsistent physical inverse relationships")
                }
            }
        }
    }

    /// Old archives have array-entry identity but only UUID foreign keys.
    /// Upgrade only explicit, uniquely resolvable links; never use content or
    /// timing heuristics to choose a parent among duplicate application IDs.
    static func upgradingLegacy(_ file: BackupFile) throws -> BackupFile {
        guard (1...5).contains(file.formatVersion ?? 1), file.physicalRecords == nil,
              needsPhysicalIdentities(file) else { return file }
        var snapshots = try collections(in: file)
        // Match the pre-existing constructors for fields absent in older DTOs.
        // Optional actual measurements stay nil; only legacy defaults are filled.
        let defaults: [String: [String: Any]] = [
            "workoutSessions": ["shouldSaveAsTemplate": false, "isSampleData": false, "executionStatusRaw": "legacy_recorded"],
            "exerciseLogs": ["exerciseOrder": 0, "exerciseType": "strength", "isCompleted": false, "isIsolated": false],
            "runningSessions": ["isSampleData": false, "linkedHealthWorkoutUUIDsRaw": "", "executionStatusRaw": "legacy_recorded", "hasMeasuredDistance": true],
            "weightEntries": ["provenance": "manual_or_legacy"],
            "healthWorkoutInboxItems": ["alternateHealthWorkoutUUIDsRaw": ""],
            "cardioWorkoutInboxItems": ["alternateHealthWorkoutUUIDsRaw": "", "healthSyncVersionsByStableIdentityRaw": ""]
        ]
        for collection in collectionNames {
            for index in snapshots[collection]!.indices {
                for (field, value) in defaults[collection] ?? [:] where snapshots[collection]![index][field] == nil {
                    snapshots[collection]![index][field] = value
                }
                if collection == "workoutSessions", (snapshots[collection]![index]["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    snapshots[collection]![index]["title"] = "Gym Session"
                }
                if collection == "coach.plannedSessions", snapshots[collection]![index]["localScheduleOverride"] == nil {
                    snapshots[collection]![index]["localScheduleOverride"] = (snapshots[collection]![index]["scheduleRevision"] as? Int ?? 0) > 0
                }
            }
        }
        var rows: [Row] = []
        for collection in collectionNames {
            for (index, snapshot) in snapshots[collection]!.enumerated() {
                guard let text = snapshot["id"] as? String, let id = UUID(uuidString: text) else {
                    throw failure("An older backup has an invalid record ID")
                }
                let key = SHA256.hash(data: Data(("legacy/" + collection + "/" + String(index)).utf8))
                    .map { String(format: "%02x", $0) }.joined()
                rows.append(Row(key: key, collection: collection, index: index, applicationID: id,
                    relationships: (relationships[collection] ?? [:]).mapValues { _ in [] }))
            }
        }
        let indices = Dictionary(uniqueKeysWithValues: rows.indices.map { (rows[$0].key, $0) })
        let targets = Dictionary(grouping: rows, by: { applicationKey($0.collection, $0.applicationID) })
        func incompatible(_ detail: String) -> CoachHistoryArchive.ArchiveError {
            failure("This older backup has " + detail + ". Its saved IDs do not identify a unique relationship. Export a new backup from an updated installation if available, and keep this original file for recovery; no parent will be guessed")
        }
        func assign(_ source: String, _ name: String, _ target: String) throws {
            let index = indices[source]!, relation = relationships[rows[index].collection]![name]!
            let existing = rows[index].relationships[name]!
            guard relation.many || existing.isEmpty || existing == [target] else {
                throw incompatible("conflicting saved parent links")
            }
            if !existing.contains(target) { rows[index].relationships[name]!.append(target) }
        }
        for index in rows.indices {
            let row = rows[index], snapshot = snapshots[row.collection]![row.index]
            for (name, relation) in relationships[row.collection] ?? [:] {
                let field: String?
                if row.collection == "runningSessions", name == "plannedSession" { field = "plannedSessionID" }
                else if row.collection == "runningPlanSessions", name == "completedRun" { field = "completedRunSessionID" }
                else { field = relationshipForeignKeys[row.collection + "/" + name] }
                guard let field, let text = snapshot[field] as? String, let id = UUID(uuidString: text) else { continue }
                let candidates = targets[applicationKey(relation.collection, id)] ?? []
                guard candidates.count == 1 else {
                    throw incompatible(candidates.isEmpty ? "a missing referenced parent record" : "ambiguous references to duplicate parent IDs")
                }
                let target = candidates[0]
                try assign(row.key, name, target.key)
                if let inverse = inverseRelationships[row.collection + "/" + name] {
                    try assign(target.key, inverse, row.key)
                }
            }
        }
        for index in rows.indices {
            rows[index].relationships = rows[index].relationships.mapValues { $0.sorted() }
            // A declared inverse can determine a projection omitted by an older
            // DTO. Preserve UUID-valued query links that are not physical FKs.
            for (name, targets) in rows[index].relationships {
                guard let field = relationshipForeignKeys[rows[index].collection + "/" + name],
                      let target = targets.first else { continue }
                snapshots[rows[index].collection]![rows[index].index][field] = rows[indices[target]!].applicationID.uuidString
            }
        }
        var upgraded = try replacingCollections(in: file, with: snapshots)
        upgraded.formatVersion = 6; upgraded.physicalRecords = BackupPhysicalGraph(rows: rows)
        do { try upgraded.physicalRecords!.validate(in: upgraded) }
        catch { throw incompatible("inconsistent saved inverse links") }
        try upgraded.coach?.validate(allowDuplicateIdentities: true)
        return upgraded
    }

    @MainActor static func capture(context: ModelContext, file: BackupFile) throws -> BackupPhysicalGraph {
        let live = try liveRows(context: context)
        let keys = Dictionary(uniqueKeysWithValues: live.map { ($0.model.persistentModelID, $0.key) })
        var indices: [String: Int] = [:]
        let rows = try live.map { row in
            let index = indices[row.collection, default: 0]; indices[row.collection] = index + 1
            var links: [String: [String]] = [:]
            for (name, targets) in row.getRelationships() {
                links[name] = try targets.map { target in
                    guard let key = keys[target] else { throw failure("A physical relationship points outside the backup") }
                    return key
                }.sorted()
            }
            return Row(key: row.key, collection: row.collection, index: index, applicationID: row.id, relationships: links)
        }
        let graph = BackupPhysicalGraph(rows: rows)
        try graph.validate(in: file)
        return graph
    }

    private func components() -> [[Row]] {
        let byKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        var edges: [String: Set<String>] = [:]
        for row in rows {
            for target in row.relationships.values.flatMap({ $0 }) {
                edges[row.key, default: []].insert(target); edges[target, default: []].insert(row.key)
            }
        }
        var unseen = Set(byKey.keys), result: [[Row]] = []
        while let first = unseen.first {
            var pending = [first], component: [Row] = []; unseen.remove(first)
            while let key = pending.popLast() {
                component.append(byKey[key]!)
                for target in edges[key] ?? [] where unseen.remove(target) != nil { pending.append(target) }
            }
            result.append(component.sorted { $0.key < $1.key })
        }
        return result
    }

    private static func payloads(_ graph: BackupPhysicalGraph, file: BackupFile) throws -> [String: Data] {
        let snapshots = try collections(in: file)
        return try Dictionary(uniqueKeysWithValues: graph.rows.map { row in
            (row.key, try JSONSerialization.data(withJSONObject: snapshots[row.collection]![row.index], options: [.sortedKeys]))
        })
    }

    /// Only tests graph equivalence; it never chooses a destination for a write.
    /// Iterative backtracking also handles physically distinct identical twins.
    private static func equivalent(_ source: [Row], _ destination: [Row], sourcePayload: [String: Data], destinationPayload: [String: Data]) throws -> Bool {
        guard source.count == destination.count else { return false }
        let sourceByKey = Dictionary(uniqueKeysWithValues: source.map { ($0.key, $0) })
        let destinationByKey = Dictionary(uniqueKeysWithValues: destination.map { ($0.key, $0) })
        var candidates: [String: [String]] = [:]
        for row in source {
            let matches = destination.filter { target in
                target.collection == row.collection && sourcePayload[row.key] == destinationPayload[target.key]
                    && row.relationships.mapValues(\.count) == target.relationships.mapValues(\.count)
            }.map(\.key).sorted()
            guard !matches.isEmpty else { return false }
            candidates[row.key] = matches
        }
        let ordered = source.sorted { (candidates[$0.key]!.count, $0.key) < (candidates[$1.key]!.count, $1.key) }
        var mapping: [String: String] = [:], used: Set<String> = [], next = Array(repeating: 0, count: ordered.count)
        var depth = 0, budget = 100_000
        func compatible(_ row: Row, _ target: Row) -> Bool {
            let proposed = mapping.merging([row.key: target.key]) { _, new in new }
            let reverse = Dictionary(uniqueKeysWithValues: proposed.map { ($0.value, $0.key) })
            for (sourceKey, destinationKey) in proposed {
                for (name, links) in sourceByKey[sourceKey]!.relationships {
                    let actual = Set(destinationByKey[destinationKey]!.relationships[name] ?? [])
                    for link in links { if let mapped = proposed[link], !actual.contains(mapped) { return false } }
                    for link in actual { if let mapped = reverse[link], !links.contains(mapped) { return false } }
                }
            }
            return true
        }
        while depth >= 0 && depth < ordered.count {
            let row = ordered[depth], options = candidates[row.key]!
            var advanced = false
            while next[depth] < options.count {
                budget -= 1
                guard budget >= 0 else { throw failure("Duplicate history is too ambiguous to merge safely; restore into empty history") }
                let key = options[next[depth]]; next[depth] += 1
                guard !used.contains(key), compatible(row, destinationByKey[key]!) else { continue }
                mapping[row.key] = key; used.insert(key); depth += 1; advanced = true
                if depth < ordered.count { next[depth] = 0 }
                break
            }
            if !advanced {
                next[depth] = 0; depth -= 1
                if depth >= 0, let removed = mapping.removeValue(forKey: ordered[depth].key) { used.remove(removed) }
            }
        }
        return depth == ordered.count
    }

    #if DEBUG
    func hasSameContent(as other: BackupPhysicalGraph, file: BackupFile, otherFile: BackupFile) throws -> Bool {
        let sourcePayload = try Self.payloads(self, file: file), destinationPayload = try Self.payloads(other, file: otherFile)
        let destinations = other.components()
        var consumed: Set<Int> = []
        for component in components() {
            var match: Int?
            for index in destinations.indices where !consumed.contains(index) {
                if try Self.equivalent(component, destinations[index], sourcePayload: sourcePayload, destinationPayload: destinationPayload) { match = index; break }
            }
            guard let match else { return false }; consumed.insert(match)
        }
        return consumed.count == destinations.count
    }
    #endif

    @MainActor func restore(file: BackupFile, context: ModelContext) throws {
        try validate(in: file)
        try file.coach?.validateMerge(context: context, ignoreAmbiguousIdentities: true)
        let existingFile = try DataBackupService.capture(context: context)
        let existingGraph = try Self.capture(context: context, file: existingFile)
        let current = try Self.liveRows(context: context)
        let currentByKey = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0) })
        let sourceGroups = Dictionary(grouping: rows, by: { Self.applicationKey($0.collection, $0.applicationID) })
        let existingGroups = Dictionary(grouping: existingGraph.rows, by: { Self.applicationKey($0.collection, $0.applicationID) })
        let existingComponents = existingGraph.components()
        let sourcePayload = try Self.payloads(self, file: file), existingPayload = try Self.payloads(existingGraph, file: existingFile)
        var consumedComponents: Set<Int> = [], newKeys: Set<String> = [], resolved: [String: LiveRow] = [:]
        for component in components() {
            let hasAmbiguity = component.contains { row in
                let key = Self.applicationKey(row.collection, row.applicationID)
                return sourceGroups[key]!.count > 1 || (existingGroups[key]?.count ?? 0) > 1
            }
            if !hasAmbiguity {
                for row in component {
                    if let existing = existingGroups[Self.applicationKey(row.collection, row.applicationID)]?.first {
                        resolved[row.key] = currentByKey[existing.key]!
                    } else { newKeys.insert(row.key) }
                }
                continue
            }
            let overlapping = component.contains { existingGroups[Self.applicationKey($0.collection, $0.applicationID)] != nil }
            if !overlapping { newKeys.formUnion(component.map(\.key)); continue }
            var match: Int?
            for index in existingComponents.indices where !consumedComponents.contains(index) {
                if try Self.equivalent(component, existingComponents[index], sourcePayload: sourcePayload, destinationPayload: existingPayload) { match = index; break }
            }
            guard let match else {
                throw Self.failure("Existing duplicate history differs from this backup; no ambiguous records were merged")
            }
            consumedComponents.insert(match)
        }
        guard !newKeys.isEmpty else { return }
        // Reject reparenting of a retained row before creating any new models.
        for row in rows where newKeys.contains(row.key) {
            for (name, targets) in row.relationships {
                guard let inverse = Self.inverseRelationships[row.collection + "/" + name] else { continue }
                for target in targets {
                    if let existing = resolved[target], Self.relationships[existing.collection]?[inverse]?.many == false,
                       existing.getRelationships()[inverse]?.isEmpty == false {
                        throw Self.failure("A retained physical record already has another parent")
                    }
                }
            }
        }
        var temporary: [String: UUID] = [:], reverse: [UUID: UUID] = [:]
        let reserved = Set(rows.map(\.applicationID) + current.map(\.id))
        for row in rows where newKeys.contains(row.key) {
            var id = UUID(); while reserved.contains(id) || reverse[id] != nil { id = UUID() }
            temporary[row.key] = id; reverse[id] = row.applicationID
        }
        let snapshots = try Self.collections(in: file)
        var staged: [String: [[String: Any]]] = [:]
        for row in rows where newKeys.contains(row.key) {
            var snapshot = snapshots[row.collection]![row.index]
            snapshot["id"] = temporary[row.key]!.uuidString
            for (field, collection) in Self.uuidReferences[row.collection] ?? [:] {
                guard let text = snapshot[field] as? String, let id = UUID(uuidString: text),
                      let group = sourceGroups[Self.applicationKey(collection, id)], group.count == 1,
                      let replacement = temporary[group[0].key] else { continue }
                snapshot[field] = replacement.uuidString
            }
            staged[row.collection, default: []].append(snapshot)
        }
        for collection in Self.collectionNames where staged[collection] == nil { staged[collection] = [] }
        // Inbox import normally reconciles Health replacements. A physical archive
        // must retain its separate stored rows, so construct these without merging.
        let healthRows = staged["healthWorkoutInboxItems"]!, cardioRows = staged["cardioWorkoutInboxItems"]!
        staged["healthWorkoutInboxItems"] = []; staged["cardioWorkoutInboxItems"] = []
        let legacy = try Self.replacingCollections(in: file, with: staged)
        try DataBackupService.restoreLegacy(legacy, context: context, validate: false, save: false, preservePhysicalRows: true)
        try Self.insertInbox(healthRows: healthRows, cardioRows: cardioRows, context: context)
        let insertedGroups = Dictionary(grouping: try Self.liveRows(context: context), by: { Self.applicationKey($0.collection, $0.id) })
        for row in rows where newKeys.contains(row.key) {
            guard let matches = insertedGroups[Self.applicationKey(row.collection, temporary[row.key]!)], matches.count == 1 else {
                throw Self.failure("A restored physical record could not be resolved")
            }
            resolved[row.key] = matches[0]
        }
        for row in rows where newKeys.contains(row.key) {
            let live = resolved[row.key]!
            live.rewriteUUIDs(reverse); live.setID(row.applicationID)
        }
        for row in rows where newKeys.contains(row.key) {
            var links: [String: [any PersistentModel]] = [:]
            for (name, keys) in row.relationships {
                links[name] = try keys.map { key in
                    guard let target = resolved[key] else { throw Self.failure("A physical relationship cannot be resolved without choosing an ambiguous row") }
                    return target.model
                }
            }
            try resolved[row.key]!.setRelationships(links)
        }
        for row in rows where newKeys.contains(row.key) {
            let actual = resolved[row.key]!.getRelationships()
            for (name, keys) in row.relationships {
                let expected = Set(keys.compactMap { resolved[$0]?.model.persistentModelID })
                guard Set(actual[name] ?? []) == expected else { throw Self.failure("The restored physical relationships differ from the archive") }
            }
        }
        try DataBackupService.requireLocalRestoreDestination(context, generation: WearableWorkoutInboxService.localDataPurgeGeneration)
        try context.save()
    }

    private struct Relation { var collection: String; var many: Bool }
    private static let collectionNames = ["exerciseDefinitions", "workoutSessions", "exerciseLogs", "runningSessions", "weightEntries", "runningPlans", "runningPlanSessions", "aiConversations", "workoutTemplates", "templateExercises", "healthWorkoutInboxItems", "cardioWorkoutInboxItems", "coach.trainingPlans", "coach.plannedSessions", "coach.revisions", "coach.executions", "coach.suggestions", "coach.targets", "coach.nutrition", "coach.recovery", "coach.waist", "coach.photos", "coach.phaseReviews", "coach.calendarMappings"]
    private static let relationships: [String: [String: Relation]] = [
        "exerciseDefinitions": ["logs": Relation(collection: "exerciseLogs", many: true)],
        "workoutSessions": ["exerciseLogs": Relation(collection: "exerciseLogs", many: true), "generatedTemplate": Relation(collection: "workoutTemplates", many: false)],
        "exerciseLogs": ["exerciseDefinition": Relation(collection: "exerciseDefinitions", many: false), "workoutSession": Relation(collection: "workoutSessions", many: false)],
        "runningSessions": ["plannedSession": Relation(collection: "runningPlanSessions", many: false)],
        "weightEntries": [:],
        "runningPlans": ["sessions": Relation(collection: "runningPlanSessions", many: true)],
        "runningPlanSessions": ["plan": Relation(collection: "runningPlans", many: false), "completedRun": Relation(collection: "runningSessions", many: false)],
        "aiConversations": [:],
        "workoutTemplates": ["exercises": Relation(collection: "templateExercises", many: true), "sourceSession": Relation(collection: "workoutSessions", many: false)],
        "templateExercises": ["template": Relation(collection: "workoutTemplates", many: false)],
        "healthWorkoutInboxItems": [:],
        "cardioWorkoutInboxItems": [:],
        "coach.trainingPlans": ["sessions": Relation(collection: "coach.plannedSessions", many: true)],
        "coach.plannedSessions": ["plan": Relation(collection: "coach.trainingPlans", many: false)],
        "coach.revisions": [:],
        "coach.executions": [:],
        "coach.suggestions": [:],
        "coach.targets": [:],
        "coach.nutrition": [:],
        "coach.recovery": [:],
        "coach.waist": [:],
        "coach.photos": [:],
        "coach.phaseReviews": [:],
        "coach.calendarMappings": [:],
    ]
    private static let uuidReferences: [String: [String: String]] = [
        "workoutSessions": ["sourceTemplateID": "workoutTemplates", "generatedTemplateID": "workoutTemplates", "plannedSessionID": "coach.plannedSessions", "coachExecutionID": "coach.executions"],
        "exerciseLogs": ["exerciseDefinitionId": "exerciseDefinitions", "workoutSessionId": "workoutSessions"],
        "runningSessions": ["plannedSessionID": "runningPlanSessions", "canonicalPlannedSessionID": "coach.plannedSessions", "coachExecutionID": "coach.executions"],
        "runningPlanSessions": ["planId": "runningPlans", "completedRunSessionID": "runningSessions"],
        "workoutTemplates": ["sourceAIConversationId": "aiConversations", "importSourceSessionID": "workoutSessions", "sourceSessionId": "workoutSessions"],
        "templateExercises": ["templateId": "workoutTemplates"],
        "healthWorkoutInboxItems": ["linkedWorkoutSessionID": "workoutSessions"],
        "cardioWorkoutInboxItems": ["linkedRunningSessionID": "runningSessions", "suggestedRunningSessionID": "runningSessions"],
        "coach.trainingPlans": ["currentRevisionID": "coach.revisions", "sourceAIConversationID": "aiConversations", "sourceRunningPlanID": "runningPlans"],
        "coach.plannedSessions": ["revisionID": "coach.revisions", "executionID": "coach.executions", "workoutTemplateID": "workoutTemplates", "runningPlanSessionID": "runningPlanSessions", "completedWorkoutSessionID": "workoutSessions", "completedRunningSessionID": "runningSessions", "planID": "coach.trainingPlans"],
        "coach.revisions": ["planID": "coach.trainingPlans"],
        "coach.executions": ["plannedSessionID": "coach.plannedSessions", "workoutSessionID": "workoutSessions", "runSessionID": "runningSessions", "prescriptionRevisionID": "coach.revisions"],
        "coach.suggestions": ["planID": "coach.trainingPlans"],
        "coach.targets": ["planID": "coach.trainingPlans", "revisionID": "coach.revisions"],
        "coach.phaseReviews": ["planID": "coach.trainingPlans", "revisionID": "coach.revisions"],
        "coach.calendarMappings": ["plannedSessionID": "coach.plannedSessions"],
    ]
    private static let relationshipForeignKeys = [
        "exerciseLogs/exerciseDefinition": "exerciseDefinitionId", "exerciseLogs/workoutSession": "workoutSessionId",
        "workoutSessions/generatedTemplate": "generatedTemplateID", "workoutTemplates/sourceSession": "sourceSessionId",
        "templateExercises/template": "templateId", "runningPlanSessions/plan": "planId", "coach.plannedSessions/plan": "planID"
    ]
    private static let inverseRelationships = [
        "exerciseDefinitions/logs": "exerciseDefinition", "exerciseLogs/exerciseDefinition": "logs",
        "workoutSessions/exerciseLogs": "workoutSession", "exerciseLogs/workoutSession": "exerciseLogs",
        "workoutSessions/generatedTemplate": "sourceSession", "workoutTemplates/sourceSession": "generatedTemplate",
        "workoutTemplates/exercises": "template", "templateExercises/template": "exercises",
        "runningPlans/sessions": "plan", "runningPlanSessions/plan": "sessions",
        "runningSessions/plannedSession": "completedRun", "runningPlanSessions/completedRun": "plannedSession",
        "coach.trainingPlans/sessions": "plan", "coach.plannedSessions/plan": "sessions",
    ]

    @MainActor private struct LiveRow {
        var collection: String
        var model: any PersistentModel
        var idValue: () -> UUID
        var setID: (UUID) -> Void
        var rewriteUUIDs: ([UUID: UUID]) -> Void
        var getRelationships: () -> [String: [PersistentIdentifier]]
        var setRelationships: ([String: [any PersistentModel]]) throws -> Void
        var id: UUID { idValue() }
        var key: String { archiveKey(collection, model.persistentModelID) }
    }
    @MainActor private struct LiveRelation<Model: PersistentModel> {
        var name: String
        var get: (Model) -> [PersistentIdentifier]
        var set: (Model, [any PersistentModel]) throws -> Void
    }
    @MainActor private static func one<Model: PersistentModel, Target: PersistentModel>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, Target?>) -> LiveRelation<Model> {
        LiveRelation(name: name, get: { $0[keyPath: keyPath].map { [$0.persistentModelID] } ?? [] }, set: { model, values in
            guard values.count <= 1, values.isEmpty || values[0] is Target else { throw failure("Wrong physical relationship type") }
            model[keyPath: keyPath] = values.first as? Target
        })
    }
    @MainActor private static func many<Model: PersistentModel, Target: PersistentModel>(_ name: String, _ keyPath: ReferenceWritableKeyPath<Model, [Target]?>) -> LiveRelation<Model> {
        LiveRelation(name: name, get: { ($0[keyPath: keyPath] ?? []).map(\.persistentModelID) }, set: { model, values in
            guard let typed = values as? [Target] else { throw failure("Wrong physical relationship type") }
            model[keyPath: keyPath] = typed
        })
    }
    @MainActor private static func liveRows(context: ModelContext) throws -> [LiveRow] {
        var result: [LiveRow] = []
        func add<Model: PersistentModel>(_ type: Model.Type, _ collection: String, _ id: ReferenceWritableKeyPath<Model, UUID>, uuid: [ReferenceWritableKeyPath<Model, UUID?>] = [], requiredUUID: [ReferenceWritableKeyPath<Model, UUID>] = [], relations: [LiveRelation<Model>] = [], include: (Model) -> Bool = { _ in true }) throws {
            for model in sorted(try context.fetch(FetchDescriptor<Model>())).filter(include) {
                result.append(LiveRow(collection: collection, model: model, idValue: { model[keyPath: id] }, setID: { model[keyPath: id] = $0 }, rewriteUUIDs: { mapping in
                    for path in uuid { if let value = model[keyPath: path], let original = mapping[value] { model[keyPath: path] = original } }
                    for path in requiredUUID { if let original = mapping[model[keyPath: path]] { model[keyPath: path] = original } }
                }, getRelationships: {
                    Dictionary(uniqueKeysWithValues: relations.map { ($0.name, $0.get(model)) })
                }, setRelationships: { values in
                    for relation in relations { try relation.set(model, values[relation.name] ?? []) }
                }))
            }
        }
        try add(ExerciseDefinition.self, "exerciseDefinitions", \.id , relations: [many("logs", \.logs)])
        try add(WorkoutSession.self, "workoutSessions", \.id , uuid: [\.sourceTemplateID, \.plannedSessionID, \.coachExecutionID], relations: [many("exerciseLogs", \.exerciseLogs), one("generatedTemplate", \.generatedTemplate)])
        try add(ExerciseLog.self, "exerciseLogs", \.id , relations: [one("exerciseDefinition", \.exerciseDefinition), one("workoutSession", \.workoutSession)])
        try add(RunningSession.self, "runningSessions", \.id , uuid: [\.canonicalPlannedSessionID, \.coachExecutionID, \.plannedSessionID], relations: [one("plannedSession", \.plannedSession)])
        try add(WeightEntry.self, "weightEntries", \.id)
        try add(RunningPlan.self, "runningPlans", \.id , relations: [many("sessions", \.sessions)])
        try add(RunningPlanSession.self, "runningPlanSessions", \.id , uuid: [\.completedRunSessionID], relations: [one("plan", \.plan), one("completedRun", \.completedRun)])
        try add(AIConversation.self, "aiConversations", \.id)
        try add(WorkoutTemplate.self, "workoutTemplates", \.id , uuid: [\.sourceAIConversationId, \.importSourceSessionID], relations: [many("exercises", \.exercises), one("sourceSession", \.sourceSession)])
        try add(TemplateExercise.self, "templateExercises", \.id , relations: [one("template", \.template)])
        try add(HealthWorkoutInboxItem.self, "healthWorkoutInboxItems", \.id , uuid: [\.linkedWorkoutSessionID], include: { $0.healthDeletionObservedAt == nil })
        try add(CardioWorkoutInboxItem.self, "cardioWorkoutInboxItems", \.id , uuid: [\.linkedRunningSessionID, \.suggestedRunningSessionID], include: { $0.healthDeletionObservedAt == nil })
        try add(TrainingPlan.self, "coach.trainingPlans", \.id , uuid: [\.currentRevisionID, \.sourceAIConversationID, \.sourceRunningPlanID], relations: [many("sessions", \.sessions)])
        try add(PlannedSession.self, "coach.plannedSessions", \.id , uuid: [\.revisionID, \.executionID, \.workoutTemplateID, \.runningPlanSessionID, \.completedWorkoutSessionID, \.completedRunningSessionID], relations: [one("plan", \.plan)])
        if CoachPersistence.isLocal(context) {
        try add(CoachPlanRevision.self, "coach.revisions", \.id , requiredUUID: [\.planID])
        try add(CoachSessionExecution.self, "coach.executions", \.id , uuid: [\.plannedSessionID, \.workoutSessionID, \.runSessionID, \.prescriptionRevisionID])
        try add(CoachProgressionSuggestion.self, "coach.suggestions", \.id , requiredUUID: [\.planID])
        try add(CoachNutritionTargetPeriod.self, "coach.targets", \.id , uuid: [\.planID, \.revisionID])
        try add(CoachNutritionLog.self, "coach.nutrition", \.id)
        try add(CoachRecoveryCheckIn.self, "coach.recovery", \.id)
        try add(CoachWaistMeasurement.self, "coach.waist", \.id)
        try add(CoachProgressPhoto.self, "coach.photos", \.id)
        try add(CoachPhaseReview.self, "coach.phaseReviews", \.id , uuid: [\.revisionID], requiredUUID: [\.planID])
        try add(CoachCalendarMapping.self, "coach.calendarMappings", \.id , requiredUUID: [\.plannedSessionID])
        }
        return result
    }

    @MainActor private static func insertInbox(healthRows: [[String: Any]], cardioRows: [[String: Any]], context: ModelContext) throws {
        let decoder = JSONDecoder()
        for object in healthRows {
            let row = try decoder.decode(BackupFile.HealthWorkoutInboxItemDTO.self, from: JSONSerialization.data(withJSONObject: object))
            let model = HealthWorkoutInboxItem(id: row.id, healthWorkoutUUID: row.healthWorkoutUUID, startDate: row.startDate, endDate: row.endDate, activityType: row.activityType, duration: row.duration, calories: row.calories, avgHeartRate: row.avgHeartRate, sourceName: row.sourceName, sourceBundleIdentifier: row.sourceBundleIdentifier, healthSyncIdentifier: row.healthSyncIdentifier, healthSyncVersion: row.healthSyncVersion, healthExternalUUID: row.healthExternalUUID, alternateHealthWorkoutUUIDsRaw: row.alternateHealthWorkoutUUIDsRaw ?? "")
            model.statusRaw = row.statusRaw; model.linkedWorkoutSessionID = row.linkedWorkoutSessionID; model.createdAt = row.createdAt
            context.insert(model)
        }
        for object in cardioRows {
            let row = try decoder.decode(BackupFile.CardioWorkoutInboxItemDTO.self, from: JSONSerialization.data(withJSONObject: object))
            let model = CardioWorkoutInboxItem(id: row.id, healthWorkoutUUID: row.healthWorkoutUUID, startDate: row.startDate, endDate: row.endDate, activityType: row.activityType, distanceMeters: row.distanceMeters, duration: row.duration, calories: row.calories, avgHeartRate: row.avgHeartRate, maxHeartRate: row.maxHeartRate, minHeartRate: row.minHeartRate, sourceName: row.sourceName, sourceBundleIdentifier: row.sourceBundleIdentifier, healthSyncIdentifier: row.healthSyncIdentifier, healthSyncVersion: row.healthSyncVersion, healthExternalUUID: row.healthExternalUUID, healthSyncVersionsByStableIdentityRaw: row.healthSyncVersionsByStableIdentityRaw ?? "", metricSourceHealthWorkoutUUID: row.metricSourceHealthWorkoutUUID, metricSourceName: row.metricSourceName, metricSourceBundleIdentifier: row.metricSourceBundleIdentifier)
            model.alternateHealthWorkoutUUIDsRaw = row.alternateHealthWorkoutUUIDsRaw ?? ""; model.statusRaw = row.statusRaw; model.linkedRunningSessionID = row.linkedRunningSessionID; model.suggestedRunningSessionID = row.suggestedRunningSessionID; model.createdAt = row.createdAt
            context.insert(model)
        }
    }
}
