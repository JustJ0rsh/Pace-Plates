import Foundation
import Observation
import Security
import os

/// Numeric profile values retain their own units even when app preferences are
/// removed during reinstall. Untagged measurements stay private until reviewed.
@MainActor
@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()

    struct Profile: Codable, Equatable {
        var age: Int = 0
        var sex: String = ""
        var heightValue: Double = 0
        var targetWeight: Double = 0
        var heightUnit: String? = nil
        var weightUnit: String? = nil
        var unitReviewRequired: Bool? = nil
        var isEmpty: Bool { age == 0 && sex.isEmpty && heightValue == 0 && targetWeight == 0 }
    }

    enum ReadResult { case found(Data), missing, unavailable }
    struct Storage {
        var read: () -> ReadResult
        var write: (Data) -> Bool
    }

    private static let legacyDefaultsKeys = ["age", "sex", "heightValue", "targetWeight"]
    private static let unitReviewKey = "profileMeasurementsNeedUnitReview"
    private static let keychainAccount = "user.profile"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.paceandplates", category: "profile")
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let preferenceDomain: String?
    @ObservationIgnored private let storage: Storage?
    @ObservationIgnored private var legacyHeightUnit: String?
    @ObservationIgnored private var legacyWeightUnit: String?
    private var profile = Profile()
    private(set) var isAvailable = true
    private(set) var storageError: String?

    var needsUnitReview: Bool {
        isAvailable && ((profile.heightValue > 0 && storedHeightUnit == nil) || (profile.targetWeight > 0 && storedWeightUnit == nil))
    }
    var age: Int {
        get { profile.age }
        set { var value = resolvedProfile; value.age = max(0, newValue); _ = commit(value) }
    }
    var sex: String {
        get { profile.sex }
        set { var value = resolvedProfile; value.sex = newValue; _ = commit(value) }
    }
    var heightValue: Double {
        get {
            guard let source = storedHeightUnit else { return 0 }
            return Self.height(profile.heightValue, from: source, to: preferredHeightUnit)
        }
        set {
            var value = resolvedProfile
            value.heightValue = Self.measurement(newValue); value.heightUnit = preferredHeightUnit
            _ = commit(value)
        }
    }
    var targetWeight: Double {
        get {
            guard let source = storedWeightUnit else { return 0 }
            return UnitConverter.weight(profile.targetWeight, from: source, to: preferredWeightUnit)
        }
        set {
            var value = resolvedProfile
            value.targetWeight = Self.measurement(newValue); value.weightUnit = preferredWeightUnit
            _ = commit(value)
        }
    }
    var hasBasicProfile: Bool { isAvailable && !needsUnitReview && profile.age > 0 && heightValue > 0 }
    private var storedHeightUnit: String? { Self.heightUnit(profile.heightUnit) ?? legacyHeightUnit }
    private var storedWeightUnit: String? { Self.weightUnit(profile.weightUnit) ?? legacyWeightUnit }
    private var preferredHeightUnit: String { Self.heightUnit(defaults.string(forKey: "heightUnit")) ?? storedHeightUnit ?? "in" }
    private var preferredWeightUnit: String { Self.weightUnit(defaults.string(forKey: "weightUnit")) ?? storedWeightUnit ?? "lbs" }
    private var resolvedProfile: Profile {
        var value = profile; value.heightUnit = storedHeightUnit; value.weightUnit = storedWeightUnit; return value
    }

    private convenience init() {
        let launch = AppLaunchConfiguration.current
        let isolated = launch.usesIsolatedStore && !launch.usesNaturalProfileForTesting
        self.init(defaults: .standard, preferenceDomain: Bundle.main.bundleIdentifier,
                  storage: isolated ? nil : Storage(read: Self.readFromKeychain, write: Self.writeToKeychain))
    }

    /// Injectable storage and a unique defaults suite keep regressions away from
    /// the real profile item. A nil storage is the ordinary UI-test memory mode.
    init(defaults: UserDefaults, preferenceDomain: String? = nil, storage: Storage?) {
        self.defaults = defaults; self.preferenceDomain = preferenceDomain; self.storage = storage
        load()
    }

    func retryLoadingIfUnavailable() { if !isAvailable { load() } }

    @discardableResult
    func saveProfile(age: Int, sex: String, height: Double, heightUnit: String, targetWeight: Double, weightUnit: String) -> Bool {
        guard let heightUnit = Self.heightUnit(heightUnit), let weightUnit = Self.weightUnit(weightUnit) else { return false }
        return commit(Profile(age: max(0, age), sex: sex, heightValue: Self.measurement(height), targetWeight: Self.measurement(targetWeight), heightUnit: heightUnit, weightUnit: weightUnit))
    }

    /// Convert from the units stored beside each value, so retries and callers
    /// that already changed display preferences cannot convert a value twice.
    @discardableResult
    func changeMeasurementSystem(to system: String) -> Bool {
        guard system == "metric" || system == "imperial", isAvailable else { return false }
        let heightUnit = system == "metric" ? "cm" : "in", weightUnit = system == "metric" ? "kg" : "lbs"
        var value = resolvedProfile
        if let source = storedHeightUnit { value.heightValue = Self.height(profile.heightValue, from: source, to: heightUnit); value.heightUnit = heightUnit }
        else if profile.heightValue == 0 { value.heightUnit = heightUnit }
        if let source = storedWeightUnit { value.targetWeight = UnitConverter.weight(profile.targetWeight, from: source, to: weightUnit); value.weightUnit = weightUnit }
        else if profile.targetWeight == 0 { value.weightUnit = weightUnit }
        guard commit(value) else { return false }
        defaults.set(system, forKey: "measurementSystem"); defaults.set(heightUnit, forKey: "heightUnit")
        defaults.set(weightUnit, forKey: "weightUnit"); defaults.set(system == "metric" ? "km" : "mi", forKey: "distanceUnit")
        return true
    }

    func restoreUnitPreferences() {
        guard isAvailable else { return }
        if explicitString("heightUnit") == nil, let unit = storedHeightUnit { defaults.set(unit, forKey: "heightUnit") }
        if explicitString("weightUnit") == nil, let unit = storedWeightUnit { defaults.set(unit, forKey: "weightUnit") }
        if explicitString("measurementSystem") == nil {
            let system = storedHeightUnit.map { $0 == "cm" ? "metric" : "imperial" }
                ?? storedWeightUnit.map { $0 == "kg" ? "metric" : "imperial" }
            if let system {
                defaults.set(system, forKey: "measurementSystem")
                if explicitString("distanceUnit") == nil { defaults.set(system == "metric" ? "km" : "mi", forKey: "distanceUnit") }
            }
        }
    }

    private func load() {
        let result = storage?.read() ?? .missing
        let loaded: Profile
        switch result {
        case .unavailable:
            isAvailable = false; storageError = "Your profile is unavailable. Unlock your device and try again."
            return
        case let .found(data):
            guard let decoded = try? JSONDecoder().decode(Profile.self, from: data) else {
                isAvailable = false; storageError = "Your saved profile could not be read. It has been kept unchanged."
                return
            }
            loaded = decoded
        case .missing:
            loaded = Profile(age: max(0, defaults.integer(forKey: "age")), sex: defaults.string(forKey: "sex") ?? "",
                heightValue: Self.measurement(defaults.double(forKey: "heightValue")), targetWeight: Self.measurement(defaults.double(forKey: "targetWeight")))
        }
        isAvailable = true; profile = loaded; storageError = nil
        // Capture only preferences that really survived. Never infer units from
        // AppStorage's registered defaults or preferences written later in launch.
        let system = explicitString("measurementSystem")
        let quarantined = loaded.unitReviewRequired == true || defaults.bool(forKey: Self.unitReviewKey)
        legacyHeightUnit = quarantined ? nil : Self.heightUnit(explicitString("heightUnit")) ?? (system == "metric" ? "cm" : system == "imperial" ? "in" : nil)
        legacyWeightUnit = quarantined ? nil : Self.weightUnit(explicitString("weightUnit")) ?? (system == "metric" ? "kg" : system == "imperial" ? "lbs" : nil)
        if needsUnitReview { defaults.set(true, forKey: Self.unitReviewKey) }
        let value = resolvedProfile
        let needsWrite: Bool
        if case .missing = result { needsWrite = true } else { needsWrite = value != loaded || (needsUnitReview && loaded.unitReviewRequired != true) }
        if !needsWrite || commit(value) { Self.legacyDefaultsKeys.forEach { defaults.removeObject(forKey: $0) } }
        restoreUnitPreferences()
    }

    @discardableResult
    private func commit(_ proposed: Profile) -> Bool {
        guard isAvailable else { return false }
        var value = proposed
        let unknownUnits = (value.heightValue > 0 && Self.heightUnit(value.heightUnit) == nil)
            || (value.targetWeight > 0 && Self.weightUnit(value.weightUnit) == nil)
        value.unitReviewRequired = unknownUnits ? true : nil
        if let storage {
            guard let data = try? JSONEncoder().encode(value), storage.write(data) else {
                storageError = "Your profile changes could not be saved. Unlock your device and try again."
                return false
            }
        }
        profile = value; storageError = nil
        Self.legacyDefaultsKeys.forEach { defaults.removeObject(forKey: $0) }
        if unknownUnits { defaults.set(true, forKey: Self.unitReviewKey) }
        else { defaults.removeObject(forKey: Self.unitReviewKey) }
        return true
    }

    private func explicitString(_ key: String) -> String? {
        if let preferenceDomain { return defaults.persistentDomain(forName: preferenceDomain)?[key] as? String }
        return defaults.object(forKey: key) as? String
    }
    private static func measurement(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
    private static func heightUnit(_ unit: String?) -> String? { ["cm", "in"].contains(unit ?? "") ? unit : nil }
    private static func weightUnit(_ unit: String?) -> String? {
        guard let unit, ["kg", "lb", "lbs"].contains(unit) else { return nil }; return unit == "lb" ? "lbs" : unit
    }
    private static func height(_ value: Double, from: String, to: String) -> Double { from == to ? value : from == "cm" ? value / 2.54 : value * 2.54 }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
    }
    private static var keychainService: String {
        let appService = Bundle.main.bundleIdentifier ?? "PaceAndPlates"
        if let scope = AppLaunchConfiguration.current.naturalProfileTestScope { return appService + ".synthetic-natural-profile." + scope }
        return appService
    }
    private static func readFromKeychain() -> ReadResult {
        var query = baseQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = item as? Data else {
            logger.error("Keychain read failed status=\(status)"); return .unavailable
        }
        return .found(data)
    }
    private static func writeToKeychain(_ data: Data) -> Bool {
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { logger.error("Keychain update failed status=\(status)"); return false }
        var add = baseQuery; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(add as CFDictionary, nil)
        if added != errSecSuccess { logger.error("Keychain add failed status=\(added)") }
        return added == errSecSuccess
    }

    #if DEBUG && targetEnvironment(simulator)
    static func seedSyntheticProfileForTesting(_ profile: Profile) -> Bool {
        guard AppLaunchConfiguration.current.usesNaturalProfileForTesting,
              let data = try? JSONEncoder().encode(profile) else { return false }
        return writeToKeychain(data)
    }
    static func syntheticProfileForTesting() -> Profile? {
        guard AppLaunchConfiguration.current.usesNaturalProfileForTesting,
              case let .found(data) = readFromKeychain() else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }
    func reloadSyntheticProfileForTesting() {
        guard AppLaunchConfiguration.current.usesNaturalProfileForTesting else { return }
        load()
    }

    var naturalProfileTestStatus: String {
        guard AppLaunchConfiguration.current.usesNaturalProfileForTesting else { return "disabled" }
        let matches: Bool
        if case let .found(data) = Self.readFromKeychain() { matches = (try? JSONDecoder().decode(Profile.self, from: data)) == profile } else { matches = false }
        let cleared = Self.legacyDefaultsKeys.allSatisfy { defaults.object(forKey: $0) == nil }
        return "keychain=\(matches);defaultsCleared=\(cleared);age=\(profile.age);height=\(heightValue);target=\(targetWeight);sex=\(profile.sex)"
    }
    #endif
}
