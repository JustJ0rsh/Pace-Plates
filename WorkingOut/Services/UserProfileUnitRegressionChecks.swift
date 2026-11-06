#if DEBUG
import Foundation

@MainActor
enum UserProfileUnitRegressionChecks {
    private final class Item {
        var data: Data?
        var unavailable = false
        var failWrites = false
        var writes = 0
        var storage: UserProfileStore.Storage {
            .init(read: { self.unavailable ? .unavailable : self.data.map(UserProfileStore.ReadResult.found) ?? .missing },
                  write: { data in self.writes += 1; guard !self.failWrites else { return false }; self.data = data; return true })
        }
    }
    static func run() throws -> Int {
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw NSError(domain: "UserProfileUnitChecks", code: checks, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let suite = "SyntheticProfileUnits-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func clear() { defaults.removePersistentDomain(forName: suite) }
        func load(_ item: Item) -> UserProfileStore { UserProfileStore(defaults: defaults, preferenceDomain: suite, storage: item.storage) }
        func encoded(_ profile: UserProfileStore.Profile) throws -> Item { let item = Item(); item.data = try JSONEncoder().encode(profile); return item }
        // Registered AppStorage fallbacks must never masquerade as preferences
        // that survived an uninstall.
        defaults.register(defaults: ["measurementSystem": "imperial", "heightUnit": "in", "weightUnit": "lbs"])
        for system in ["metric", "imperial"] {
            clear()
            let metric = system == "metric"
            let item = try encoded(.init(age: 37, sex: "male", heightValue: metric ? 180 : 70, targetWeight: metric ? 80 : 165,
                                         heightUnit: metric ? "cm" : "in", weightUnit: metric ? "kg" : "lbs"))
            let store = load(item)
            try require(store.hasBasicProfile && !store.needsUnitReview, "tagged \(system) profile suppresses fresh onboarding safely")
            try require(store.heightValue == (metric ? 180 : 70) && store.targetWeight == (metric ? 80 : 165), "\(system) measurements keep their numerical meaning")
            try require(defaults.string(forKey: "measurementSystem") == system && defaults.string(forKey: "heightUnit") == (metric ? "cm" : "in") && defaults.string(forKey: "weightUnit") == (metric ? "kg" : "lbs"), "\(system) tags restore erased preferences")
            clear()
            let reopened = load(item)
            try require(reopened.heightValue == store.heightValue && reopened.targetWeight == store.targetWeight, "\(system) retained profile survives a second defaults reset")
            let initialHeight = reopened.heightValue, initialWeight = reopened.targetWeight
            let other = metric ? "imperial" : "metric"
            try require(reopened.changeMeasurementSystem(to: other), "explicit system conversion saves")
            let onceHeight = reopened.heightValue, onceWeight = reopened.targetWeight
            try require(reopened.changeMeasurementSystem(to: other) && reopened.heightValue == onceHeight && reopened.targetWeight == onceWeight, "repeated conversion to the same system does not convert twice")
            try require(reopened.changeMeasurementSystem(to: system) && abs(reopened.heightValue - initialHeight) < 0.000001 && abs(reopened.targetWeight - initialWeight) < 0.000001, "metric/imperial conversion is symmetric")
        }
        for system in ["metric", "imperial"] {
            clear(); defaults.set(system, forKey: "measurementSystem")
            let metric = system == "metric"
            let item = try encoded(.init(age: 37, heightValue: metric ? 180 : 70, targetWeight: metric ? 80 : 165))
            let store = load(item)
            let saved = try JSONDecoder().decode(UserProfileStore.Profile.self, from: item.data!)
            try require(!store.needsUnitReview && saved.heightUnit == (metric ? "cm" : "in") && saved.weightUnit == (metric ? "kg" : "lbs"), "legacy \(system) JSON acquires tags from surviving explicit preferences")
        }
        clear()
        let unknown = try encoded(.init(age: 37, sex: "female", heightValue: 180, targetWeight: 80))
        var unknownStore = load(unknown)
        try require(unknownStore.needsUnitReview && !unknownStore.hasBasicProfile && unknownStore.heightValue == 0 && unknownStore.targetWeight == 0, "unknown legacy units require review and expose no reinterpreted numbers")
        var raw = try JSONDecoder().decode(UserProfileStore.Profile.self, from: unknown.data!)
        try require(raw.heightValue == 180 && raw.targetWeight == 80 && raw.heightUnit == nil && raw.weightUnit == nil && raw.unitReviewRequired == true, "unknown legacy measurements are retained with a durable review marker")
        try require(unknownStore.changeMeasurementSystem(to: "metric"), "choosing display units does not claim unknown measurements")
        unknownStore = load(unknown)
        try require(unknownStore.needsUnitReview && unknownStore.heightValue == 0 && unknownStore.targetWeight == 0, "newly selected preferences do not reinterpret quarantined measurements on relaunch")
        clear(); unknownStore = load(unknown)
        try require(unknownStore.needsUnitReview, "review requirement survives defaults erasure through its Keychain marker")
        try require(unknownStore.saveProfile(age: 37, sex: "female", height: 175, heightUnit: "cm", targetWeight: 70, weightUnit: "kg"), "explicit review can replace unknown measurements")
        raw = try JSONDecoder().decode(UserProfileStore.Profile.self, from: unknown.data!)
        try require(!unknownStore.needsUnitReview && raw.heightValue == 175 && raw.targetWeight == 70 && raw.heightUnit == "cm" && raw.weightUnit == "kg", "review saves values and unit tags together")

        clear(); defaults.set("metric", forKey: "measurementSystem"); defaults.set(36, forKey: "age"); defaults.set(180, forKey: "heightValue"); defaults.set(80, forKey: "targetWeight")
        let failed = Item(); failed.failWrites = true
        let failedStore = load(failed)
        try require(defaults.integer(forKey: "age") == 36 && defaults.double(forKey: "heightValue") == 180 && failed.data == nil, "failed legacy migration preserves defaults and the existing item")
        failedStore.age = 40
        try require(failedStore.age == 36 && !failedStore.changeMeasurementSystem(to: "imperial") && defaults.string(forKey: "measurementSystem") == "metric", "write failures preserve the visible profile and unit preferences")
        failed.failWrites = false
        try require(failedStore.saveProfile(age: 36, sex: "", height: 180, heightUnit: "cm", targetWeight: 80, weightUnit: "kg"), "retry saves after storage becomes writable")

        clear()
        let locked = try encoded(.init(age: 37, heightValue: 180, targetWeight: 80, heightUnit: "cm", weightUnit: "kg"))
        locked.unavailable = true
        let lockedBytes = locked.data
        let lockedStore = load(locked)
        lockedStore.heightValue = 68
        try require(!lockedStore.isAvailable && locked.writes == 0 && locked.data == lockedBytes && defaults.persistentDomain(forName: suite)?["heightUnit"] == nil, "locked Keychain never becomes a missing profile or overwrites retained data")
        locked.unavailable = false; lockedStore.retryLoadingIfUnavailable()
        try require(lockedStore.isAvailable && lockedStore.heightValue == 180 && lockedStore.targetWeight == 80, "unlock retries restore the original tagged measurements")
        let corrupt = Item(); corrupt.data = Data("invalid-json".utf8)
        let corruptStore = load(corrupt)
        try require(!corruptStore.isAvailable && corrupt.writes == 0 && corrupt.data == Data("invalid-json".utf8), "unreadable payloads are preserved")
        clear()
        let fresh = load(Item())
        try require(fresh.isAvailable && !fresh.hasBasicProfile && !fresh.needsUnitReview && fresh.heightValue == 0 && fresh.targetWeight == 0, "a fresh empty profile retains optional onboarding behavior")
        return checks
    }
}
#endif
