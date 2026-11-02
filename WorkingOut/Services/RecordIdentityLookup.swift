import Foundation

enum RecordIdentityLookup {
    /// Restored records can share application UUIDs. An ambiguous key must not
    /// pick a winner when attaching or updating another record.
    static func uniqueIndex<Value, Key: Hashable>(_ values: [Value], by key: (Value) -> Key) -> [Key: Value] {
        Dictionary(grouping: values, by: key).compactMapValues { $0.count == 1 ? $0[0] : nil }
    }
}
