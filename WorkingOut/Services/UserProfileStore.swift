import Foundation
import Observation
import Security
import os

/// Personal profile attributes the user enters during onboarding or in
/// Settings: age, sex, height, and goal weight.
///
/// These used to live in `UserDefaults`, whose plist is stored unencrypted in
/// the app container and copied into device backups. They now live in a single
/// Keychain item (encrypted at rest, unlocked after first device unlock so the
/// app can read it on any launch). Existing values are migrated from
/// `UserDefaults` on first access and the legacy keys are removed.
///
/// Unit preferences (`heightUnit`, `weightUnit`, `measurementSystem`) are not
/// personal data and stay in `UserDefaults`.
@MainActor
@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()

    struct Profile: Codable, Equatable {
        /// 0 means not set.
        var age: Int = 0
        /// "male", "female", or "" when not set.
        var sex: String = ""
        /// Expressed in the unit selected by the `heightUnit` preference.
        var heightValue: Double = 0
        /// Expressed in the unit selected by the `weightUnit` preference.
        var targetWeight: Double = 0

        var isEmpty: Bool {
            age == 0 && sex.isEmpty && heightValue == 0 && targetWeight == 0
        }
    }

    private enum Backend {
        case keychain
        /// UI-test runs never touch the simulator keychain so state cannot leak
        /// between tests; values are seeded from the launch fixture in UserDefaults.
        case memory
    }

    private static let legacyDefaultsKeys = ["age", "sex", "heightValue", "targetWeight"]
    private static let keychainAccount = "user.profile"
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.paceandplates",
        category: "profile"
    )

    private let backend: Backend

    private var profile: Profile {
        didSet {
            guard profile != oldValue, backend == .keychain else { return }
            Self.writeToKeychain(profile)
        }
    }

    var age: Int {
        get { profile.age }
        set { profile.age = max(0, newValue) }
    }

    var sex: String {
        get { profile.sex }
        set { profile.sex = newValue }
    }

    var heightValue: Double {
        get { profile.heightValue }
        set { profile.heightValue = newValue.isFinite ? max(0, newValue) : 0 }
    }

    var targetWeight: Double {
        get { profile.targetWeight }
        set { profile.targetWeight = newValue.isFinite ? max(0, newValue) : 0 }
    }

    var hasBasicProfile: Bool {
        profile.age > 0 && profile.heightValue > 0
    }

    private init() {
        let defaults = UserDefaults.standard

        if AppLaunchConfiguration.current.usesIsolatedStore {
            backend = .memory
            profile = Self.readLegacyProfile(from: defaults)
            return
        }

        backend = .keychain
        if let stored = Self.readFromKeychain() {
            profile = stored
            Self.legacyDefaultsKeys.forEach { defaults.removeObject(forKey: $0) }
        } else {
            // First launch on this build: carry over whatever UserDefaults held
            // (possibly nothing) and make the Keychain item the source of truth.
            // The legacy keys are only cleared once the Keychain write succeeds,
            // so a device whose Keychain is unavailable keeps the data and retries
            // the migration on the next launch.
            let legacy = Self.readLegacyProfile(from: defaults)
            profile = legacy
            if Self.writeToKeychain(legacy) {
                Self.legacyDefaultsKeys.forEach { defaults.removeObject(forKey: $0) }
            }
        }
    }

    // MARK: - Legacy UserDefaults

    private static func readLegacyProfile(from defaults: UserDefaults) -> Profile {
        Profile(
            age: max(0, defaults.integer(forKey: "age")),
            sex: defaults.string(forKey: "sex") ?? "",
            heightValue: max(0, defaults.double(forKey: "heightValue")),
            targetWeight: max(0, defaults.double(forKey: "targetWeight"))
        )
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "PaceAndPlates",
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func readFromKeychain() -> Profile? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed status=\(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    @discardableResult
    private static func writeToKeychain(_ profile: Profile) -> Bool {
        guard let data = try? JSONEncoder().encode(profile) else { return false }

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("Keychain add failed status=\(addStatus)")
            }
            return addStatus == errSecSuccess
        default:
            logger.error("Keychain update failed status=\(updateStatus)")
            return false
        }
    }
}
