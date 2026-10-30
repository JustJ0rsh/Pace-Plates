import Foundation
import CoreData
import CloudKit

/// Creates conditional-insert payloads from current managed values. The caller
/// owns the asset directory until CloudKit saves and verifies the records.
enum CloudHistoryCloudRecordEncoder {
    enum EncodingError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let message): return message }
        }
    }

    /// Use only with the owning, initialized CloudKit container on the context
    /// queue. Native payloads are checked against current values before cloning.
    static func materializedRecords(objects: [NSManagedObject], container: NSPersistentCloudKitContainer,
                                    recordIDs: [NSManagedObjectID: CKRecord.ID], assetDirectory: URL) throws -> [CKRecord] {
        try validateMappings(recordIDs)
        guard Set(objects.map(\.objectID)).count == objects.count else {
            throw failure("The same physical record was requested more than once.")
        }
        try prepareAssetDirectory(assetDirectory)
        let native = container.records(for: objects.map(\.objectID))
        return try objects.map { object in
            guard let record = native[object.objectID] else {
                throw failure("Core Data did not materialize a CloudKit record.")
            }
            return try cloneMaterialized(record, for: object, recordIDs: recordIDs, assetDirectory: assetDirectory)
        }
    }

    fileprivate static func cloneMaterialized(_ native: CKRecord, for object: NSManagedObject,
                                              recordIDs: [NSManagedObjectID: CKRecord.ID], assetDirectory: URL) throws -> CKRecord {
        guard !object.objectID.isTemporaryID, !object.isDeleted, let entityName = object.entity.name,
              recordIDs[object.objectID] == native.recordID, native["CD_entityName"] as? String == entityName,
              native.share == nil, native.parent == nil else {
            throw failure("A native CloudKit record has an unsupported or inconsistent identity.")
        }
        var root = object.entity
        while let parent = root.superentity { root = parent }
        guard native.recordType == "CD_" + (root.name ?? "") else {
            throw failure("A native CloudKit record has an unexpected record type.")
        }
        var allowedKeys: Set<String> = ["CD_entityName"]
        var usedAssetKeys: Set<String> = []
        for (name, attribute) in object.entity.attributesByName where !attribute.isTransient {
            do {
            guard !(attribute is NSDerivedAttributeDescription) else {
                throw failure("Derived attributes require a reviewed CloudKit encoding rule.")
            }
            let key = "CD_" + name
            allowedKeys.insert(key)
            let usesAsset = [.stringAttributeType, .binaryDataAttributeType, .transformableAttributeType].contains(attribute.attributeType)
            if usesAsset { allowedKeys.insert(key + "_ckAsset") }
            let current = object.value(forKey: name)
            if current == nil || current is NSNull {
                guard attribute.isOptional, native[key] == nil, native[key + "_ckAsset"] == nil else {
                    throw failure("A native CloudKit record contains a stale value for an empty attribute.")
                }
                continue
            }
            guard let current else { throw failure("A current attribute could not be read.") }
            let matches: Bool
            switch attribute.attributeType {
            case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType,
                 .booleanAttributeType, .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                matches = (current as? NSNumber).map { expected in
                    (native[key] as? NSNumber).map { expected.isEqual(to: $0) } ?? false
                } ?? false
            case .dateAttributeType:
                matches = (current as? Date).map { $0 == native[key] as? Date } ?? false
            case .UUIDAttributeType:
                matches = (current as? UUID).map { expected in
                    (native[key] as? String).flatMap(UUID.init(uuidString:)) == expected
                } ?? false
            case .URIAttributeType:
                matches = (current as? URL).map { $0.absoluteString == native[key] as? String } ?? false
            case .stringAttributeType:
                if let string = current as? String {
                    matches = try variableData(native, key: key, string: true, usedAssets: &usedAssetKeys) == Data(string.utf8)
                } else { matches = false }
            case .binaryDataAttributeType:
                matches = try (current as? Data).map { try variableData(native, key: key, string: false, usedAssets: &usedAssetKeys) == $0 } ?? false
            case .transformableAttributeType:
                guard let name = attribute.valueTransformerName,
                      let transformer = ValueTransformer(forName: NSValueTransformerName(name)),
                      transformer is NSSecureUnarchiveFromDataTransformer,
                      let original = current as? NSObject,
                      let decoded = transformer.transformedValue(try variableData(native, key: key, string: false, usedAssets: &usedAssetKeys)) as? NSObject else {
                    throw failure("A native transformable attribute could not be verified.")
                }
                matches = original.isEqual(decoded)
            default: throw failure("The record model includes an unsupported attribute type.")
            }
            guard matches else { throw failure("A native CloudKit record is incomplete or differs from current local data.") }
            } catch EncodingError.unsupported(let message) {
                throw failure("\(entityName).\(name): \(message)")
            }
        }
        for (name, relationship) in object.entity.relationshipsByName where !relationship.isTransient {
            if relationship.isToMany {
                guard let inverse = relationship.inverseRelationship, !inverse.isToMany else {
                    throw failure("\(entityName).\(name): Unpaired or many-to-many relationship needs review.")
                }
                continue
            }
            let key = "CD_" + name
            allowedKeys.insert(key)
            let currentTarget = object.value(forKey: name)
            if let target = currentTarget as? NSManagedObject {
                guard let targetID = recordIDs[target.objectID], targetID.zoneID == native.recordID.zoneID,
                      native[key] as? String == targetID.recordName else {
                    throw failure("\(entityName).\(name): Native relationship is incomplete or differs from current data.")
                }
            } else if currentTarget != nil || native[key] != nil {
                throw failure("\(entityName).\(name): Native relationship contains a stale target.")
            }
        }
        guard Set(native.allKeys()).isSubset(of: allowedKeys) else {
            throw failure("A native CloudKit payload contains an unreviewed field.")
        }
        let result = CKRecord(recordType: native.recordType, recordID: native.recordID)
        for key in native.allKeys() {
            if key.hasSuffix("_ckAsset"), !usedAssetKeys.contains(key) { continue }
            if let asset = native[key] as? CKAsset {
                let data = try readAsset(asset)
                let url = try writeAsset(data, directory: assetDirectory)
                guard try readAsset(asset) == data else { throw failure("A native CloudKit asset changed while being copied.") }
                result[key] = CKAsset(fileURL: url)
            } else { result[key] = native[key] }
        }
        return result
    }

    private static func variableData(_ record: CKRecord, key: String, string: Bool,
                                     usedAssets: inout Set<String>) throws -> Data {
        // Core Data selects a nonempty inline value before its asset companion.
        // Ignore a stale asset when an authoritative inline value is available.
        if string, let inline = record[key] as? String, !inline.isEmpty { return Data(inline.utf8) }
        if !string, let inline = record[key] as? Data, !inline.isEmpty { return inline }
        if let asset = record[key + "_ckAsset"] as? CKAsset {
            // The native form decides serialization. Validate its sentinel and
            // exact bytes, then preserve that form in the conditional copy.
            if string {
                guard record[key] == nil || record[key] as? String == "" else {
                    throw failure("A native text asset has an invalid inline sentinel.")
                }
            } else {
                guard record[key] == nil || record[key] as? Data == Data() else {
                    throw failure("A native binary asset has an invalid inline sentinel.")
                }
            }
            usedAssets.insert(key + "_ckAsset")
            return try readAsset(asset)
        }
        if string, let inline = record[key] as? String { return Data(inline.utf8) }
        guard let data = record[key] as? Data else { throw failure("A native binary attribute is missing.") }
        return data
    }

    private static func readAsset(_ asset: CKAsset) throws -> Data {
        guard let url = asset.fileURL, url.isFileURL else { throw failure("A native CloudKit asset has no local file.") }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else {
            throw failure("A native CloudKit asset is not a regular file.")
        }
        return try Data(contentsOf: url)
    }

    #if DEBUG
    /// Fixture serializer only. Production clones validated native Core Data
    /// payloads instead of reconstructing their wire format.
    /// Call on the objects' context queue, with public mappings for the whole
    /// graph, including relationship targets that already exist on the server.
    static func encode(objects: [NSManagedObject], recordIDs: [NSManagedObjectID: CKRecord.ID],
                       ownedAssetDirectory: URL) throws -> [CKRecord] {
        try validateMappings(recordIDs)
        var emittedIDs: Set<CKRecord.ID> = []
        try prepareAssetDirectory(ownedAssetDirectory)
        return try objects.map { object in
            guard let recordID = recordIDs[object.objectID] else {
                throw failure("A record is missing its public CloudKit identity.")
            }
            guard emittedIDs.insert(recordID).inserted else {
                throw failure("The same physical record was requested more than once.")
            }
            return try encodePrepared(object, recordID: recordID, recordIDs: recordIDs,
                                      ownedAssetDirectory: ownedAssetDirectory)
        }
    }

    static func encode(_ object: NSManagedObject, recordID: CKRecord.ID,
                       recordIDs: [NSManagedObjectID: CKRecord.ID], ownedAssetDirectory: URL) throws -> CKRecord {
        try validateMappings(recordIDs)
        try prepareAssetDirectory(ownedAssetDirectory)
        return try encodePrepared(object, recordID: recordID, recordIDs: recordIDs,
                                  ownedAssetDirectory: ownedAssetDirectory)
    }

    private static func encodePrepared(_ object: NSManagedObject, recordID: CKRecord.ID,
                                       recordIDs: [NSManagedObjectID: CKRecord.ID], ownedAssetDirectory: URL) throws -> CKRecord {
        guard !object.objectID.isTemporaryID, !object.isDeleted,
              recordIDs[object.objectID] == recordID, let entityName = object.entity.name else {
            throw failure("A record's permanent CloudKit identity could not be verified.")
        }
        var rootEntity = object.entity
        while let parent = rootEntity.superentity { rootEntity = parent }
        guard let rootName = rootEntity.name else { throw failure("The record type could not be resolved.") }
        let record = CKRecord(recordType: "CD_" + rootName, recordID: recordID)
        record["CD_entityName"] = entityName as NSString
        // Leave ample room for field names, numbers and relationship IDs beneath
        // CloudKit's 1 MB record limit. Large values are always owned assets.
        var inlineBudget = 256 * 1_024
        for name in object.entity.attributesByName.keys.sorted() {
            guard let attribute = object.entity.attributesByName[name], !attribute.isTransient else { continue }
            guard !(attribute is NSDerivedAttributeDescription) else {
                throw failure("Derived attributes require a reviewed CloudKit encoding rule.")
            }
            guard let value = object.value(forKey: name), !(value is NSNull) else {
                guard attribute.isOptional else { throw failure("A required record attribute is missing.") }
                continue
            }
            let key = "CD_" + name
            switch attribute.attributeType {
            case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType, .booleanAttributeType:
                guard let number = value as? NSNumber else { throw failure("An integer attribute has an unsupported value.") }
                record[key] = number
            case .doubleAttributeType, .floatAttributeType, .decimalAttributeType:
                guard let number = value as? NSNumber, number.doubleValue.isFinite else {
                    throw failure("A numeric attribute has an unsupported value.")
                }
                record[key] = number
            case .dateAttributeType:
                guard let date = value as? Date else { throw failure("A date attribute has an unsupported value.") }
                record[key] = date as NSDate
            case .UUIDAttributeType:
                guard let id = value as? UUID else { throw failure("A UUID attribute has an unsupported value.") }
                record[key] = id.uuidString as NSString
            case .URIAttributeType:
                guard let url = value as? URL else { throw failure("A URL attribute has an unsupported value.") }
                record[key] = url.absoluteString as NSString
            case .stringAttributeType:
                guard let string = value as? String else { throw failure("A text attribute has an unsupported value.") }
                try setVariable(string as NSString, bytes: Data(string.utf8), key: key, record: record,
                                inlineBudget: &inlineBudget, assetDirectory: ownedAssetDirectory)
            case .binaryDataAttributeType:
                guard let data = value as? Data else { throw failure("A binary attribute has an unsupported value.") }
                try setVariable(data as NSData, bytes: data, key: key, record: record,
                                inlineBudget: &inlineBudget, assetDirectory: ownedAssetDirectory)
            case .transformableAttributeType:
                let data = try encodeTransformable(value, attribute: attribute)
                try setVariable(data as NSData, bytes: data, key: key, record: record,
                                inlineBudget: &inlineBudget, assetDirectory: ownedAssetDirectory)
            default:
                throw failure("The record model includes an unsupported attribute type.")
            }
        }
        for name in object.entity.relationshipsByName.keys.sorted() {
            guard let relationship = object.entity.relationshipsByName[name], !relationship.isTransient else { continue }
            if relationship.isToMany {
                guard let inverse = relationship.inverseRelationship, !inverse.isToMany else {
                    throw failure("Unpaired or many-to-many relationships require a reviewed CloudKit encoding rule.")
                }
                // The foreign key belongs to each inverse to-one record.
                continue
            }
            guard let value = object.value(forKey: name), !(value is NSNull) else { continue }
            guard let target = value as? NSManagedObject,
                  let targetID = recordIDs[target.objectID], targetID.zoneID == recordID.zoneID else {
                throw failure("A relationship is missing its CloudKit identity or crosses record zones.")
            }
            record["CD_" + name] = targetID.recordName as NSString
        }
        return record
    }
    #endif

    private static func validateMappings(_ recordIDs: [NSManagedObjectID: CKRecord.ID]) throws {
        guard Set(recordIDs.values).count == recordIDs.count else {
            throw failure("Distinct physical records map to the same CloudKit identity.")
        }
    }

    #if DEBUG
    private static func encodeTransformable(_ value: Any, attribute: NSAttributeDescription) throws -> Data {
        guard let name = attribute.valueTransformerName,
              let transformer = ValueTransformer(forName: NSValueTransformerName(name)),
              transformer is NSSecureUnarchiveFromDataTransformer,
              type(of: transformer).allowsReverseTransformation(),
              let original = value as? NSObject,
              let data = transformer.reverseTransformedValue(value) as? Data,
              let decoded = transformer.transformedValue(data) as? NSObject,
              original.isEqual(decoded) else {
            throw failure("A transformable attribute could not be encoded and verified with its registered transformer.")
        }
        return data
    }

    private static func setVariable(_ inline: CKRecordValue, bytes: Data, key: String, record: CKRecord,
                                    inlineBudget: inout Int, assetDirectory: URL) throws {
        if bytes.count <= 64 * 1_024, bytes.count <= inlineBudget {
            record[key] = inline
            inlineBudget -= bytes.count
            return
        }
        let url = try writeAsset(bytes, directory: assetDirectory)
        // Core Data uses the zero-length inline field to select its asset
        // counterpart. Preserve the field's String versus Binary Data type.
        if inline is NSString { record[key] = "" as NSString }
        else if inline is NSData { record[key] = Data() as NSData }
        else { throw failure("An asset attribute has an unsupported inline type.") }
        record[key + "_ckAsset"] = CKAsset(fileURL: url)
    }
    #endif

    private static func writeAsset(_ bytes: Data, directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".asset")
        try bytes.write(to: url, options: .atomic)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        var protectedURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        guard try Data(contentsOf: url) == bytes else { throw failure("A staged CloudKit asset did not match its source.") }
        return url
    }

    private static func prepareAssetDirectory(_ url: URL) throws {
        guard url.isFileURL else { throw failure("CloudKit assets require an owned local directory.") }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else {
            throw failure("The CloudKit asset directory is not an owned regular directory.")
        }
        var protectedURL = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }

    private static func failure(_ message: String) -> EncodingError { .unsupported(message) }
}

#if DEBUG
enum CloudHistoryCloudRecordEncoderRegressionChecks {
    static func run() throws -> Int {
        var count = 0
        func require(_ value: Bool) throws {
            count += 1
            guard value else { throw CloudHistoryCloudRecordEncoder.EncodingError.unsupported("CloudKit encoder regression failed.") }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CloudRecordEncoder-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entity = NSEntityDescription(); entity.name = "EncoderFixture"; entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true) -> NSAttributeDescription {
            let field = NSAttributeDescription(); field.name = name; field.attributeType = type; field.isOptional = optional
            return field
        }
        let tags = attribute("tags", .transformableAttributeType)
        tags.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        let parent = NSRelationshipDescription(); parent.name = "parent"; parent.destinationEntity = entity; parent.maxCount = 1; parent.isOptional = true
        let children = NSRelationshipDescription(); children.name = "children"; children.destinationEntity = entity; children.maxCount = 0; children.isOptional = true
        parent.inverseRelationship = children; children.inverseRelationship = parent
        entity.properties = [attribute("id", .UUIDAttributeType, optional: false), attribute("title", .stringAttributeType),
                             attribute("longText", .stringAttributeType), attribute("blob", .binaryDataAttributeType),
                             attribute("emptyBlob", .binaryDataAttributeType), attribute("date", .dateAttributeType),
                             attribute("number", .integer64AttributeType), tags, parent, children]
        let model = NSManagedObjectModel(); model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let result = Result { try context.performAndWait {
            let first = NSEntityDescription.insertNewObject(forEntityName: "EncoderFixture", into: context)
            let second = NSEntityDescription.insertNewObject(forEntityName: "EncoderFixture", into: context)
            let id = UUID(), date = Date(timeIntervalSince1970: 1_700_000_000)
            first.setValue(id, forKey: "id"); second.setValue(UUID(), forKey: "id")
            first.setValue("", forKey: "title")
            let longText = String(repeating: "abc", count: 30_000), blob = Data(repeating: 42, count: 80_000)
            first.setValue(longText, forKey: "longText"); first.setValue(blob, forKey: "blob")
            first.setValue(Data(), forKey: "emptyBlob"); first.setValue(date, forKey: "date")
            first.setValue(17, forKey: "number"); first.setValue(["alpha", "beta"], forKey: "tags")
            first.setValue(second, forKey: "parent")
            try context.save()
            let zone = CKRecordZone.ID(zoneName: "EncoderFixture", ownerName: CKCurrentUserDefaultName)
            let firstID = CKRecord.ID(recordName: "first", zoneID: zone), secondID = CKRecord.ID(recordName: "second", zoneID: zone)
            let mappings = [first.objectID: firstID, second.objectID: secondID]
            let records = try CloudHistoryCloudRecordEncoder.encode(objects: [first, second], recordIDs: mappings, ownedAssetDirectory: root)
            let record = records[0]
            try require(record.recordID == firstID && record.recordType == "CD_EncoderFixture" && record.recordChangeTag == nil)
            try require(record["CD_entityName"] as? String == "EncoderFixture")
            try require(record["CD_id"] as? String == id.uuidString)
            try require(record["CD_title"] as? String == "")
            try require(record["CD_emptyBlob"] as? Data == Data())
            try require(record["CD_longText"] as? String == "")
            try require(record["CD_blob"] as? Data == Data())
            try require(record["CD_date"] as? Date == date && record["CD_number"] as? Int == 17)
            try require(record["CD_parent"] as? String == secondID.recordName && record["CD_children"] == nil)
            try require(records[1]["CD_title"] == nil && records[1]["CD_parent"] == nil)
            guard let textURL = (record["CD_longText_ckAsset"] as? CKAsset)?.fileURL,
                  let dataURL = (record["CD_blob_ckAsset"] as? CKAsset)?.fileURL,
                  let tagData = record["CD_tags"] as? Data else {
                throw CloudHistoryCloudRecordEncoder.EncodingError.unsupported("CloudKit encoder assets were not created.")
            }
            try require(try String(contentsOf: textURL, encoding: .utf8) == longText)
            try require(try Data(contentsOf: dataURL) == blob)
            let transformer = NSSecureUnarchiveFromDataTransformer()
            try require(transformer.transformedValue(tagData) as? [String] == ["alpha", "beta"])
            var rejected = false
            do { _ = try CloudHistoryCloudRecordEncoder.encode(objects: [first], recordIDs: [first.objectID: firstID], ownedAssetDirectory: root) }
            catch { rejected = true }
            try require(rejected)
            rejected = false
            do {
                _ = try CloudHistoryCloudRecordEncoder.encode(objects: [first, second],
                    recordIDs: [first.objectID: firstID, second.objectID: firstID], ownedAssetDirectory: root)
            } catch { rejected = true }
            try require(rejected)
            rejected = false
            do {
                _ = try CloudHistoryCloudRecordEncoder.encode(objects: [first, first], recordIDs: mappings,
                                                              ownedAssetDirectory: root)
            } catch { rejected = true }
            try require(rejected)
            let clone = try CloudHistoryCloudRecordEncoder.cloneMaterialized(record, for: first,
                recordIDs: mappings, assetDirectory: root)
            try require(clone.recordID == firstID && clone.recordChangeTag == nil)
            let clonedTextURL = (clone["CD_longText_ckAsset"] as? CKAsset)?.fileURL
            try require(clonedTextURL != textURL)
            try require(try clonedTextURL.map { try String(contentsOf: $0, encoding: .utf8) } == longText)
            record["CD_longText"] = nil
            record["CD_blob"] = nil
            let omittedBaseClone = try CloudHistoryCloudRecordEncoder.cloneMaterialized(record, for: first,
                recordIDs: mappings, assetDirectory: root)
            try require(omittedBaseClone["CD_longText"] == nil && omittedBaseClone["CD_blob"] == nil)
            let omittedBlobURL = (omittedBaseClone["CD_blob_ckAsset"] as? CKAsset)?.fileURL
            try require(try omittedBlobURL.map { try Data(contentsOf: $0) } == blob)
            record["CD_blob"] = "wrong type" as NSString
            rejected = false
            do {
                _ = try CloudHistoryCloudRecordEncoder.cloneMaterialized(record, for: first,
                    recordIDs: mappings, assetDirectory: root)
            } catch { rejected = true }
            try require(rejected)
            record["CD_longText"] = longText as NSString
            record["CD_blob"] = blob as NSData
            let staleAsset = CKAsset(fileURL: root.appendingPathComponent("missing-stale-asset"))
            record["CD_longText_ckAsset"] = staleAsset
            record["CD_blob_ckAsset"] = staleAsset
            let inlineClone = try CloudHistoryCloudRecordEncoder.cloneMaterialized(record, for: first,
                recordIDs: mappings, assetDirectory: root)
            try require(inlineClone["CD_longText"] as? String == longText)
            try require(inlineClone["CD_blob"] as? Data == blob)
            try require(inlineClone["CD_longText_ckAsset"] == nil && inlineClone["CD_blob_ckAsset"] == nil)
            record["CD_number"] = 18 as NSNumber
            rejected = false
            do {
                _ = try CloudHistoryCloudRecordEncoder.cloneMaterialized(record, for: first,
                    recordIDs: mappings, assetDirectory: root)
            } catch { rejected = true }
            try require(rejected)
            records[1]["CD_title"] = "stale" as NSString
            rejected = false
            do {
                _ = try CloudHistoryCloudRecordEncoder.cloneMaterialized(records[1], for: second,
                    recordIDs: mappings, assetDirectory: root)
            } catch { rejected = true }
            try require(rejected)
        } }
        context.performAndWait { context.reset() }
        try coordinator.remove(store)
        try result.get()
        return count
    }
}
#endif
