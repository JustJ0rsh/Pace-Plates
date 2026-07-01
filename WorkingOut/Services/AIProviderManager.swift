import Foundation
import Security

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIProviderPreference: String, CaseIterable, Identifiable {
    case appleIntelligence
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .openRouter:
            return "OpenRouter"
        }
    }

    var subtitle: String {
        switch self {
        case .appleIntelligence:
            return "On-device generation for supported iPhones."
        case .openRouter:
            return "Cloud generation using your OpenRouter API key."
        }
    }
}

enum AIResolvedProvider: String {
    case appleIntelligence = "apple-intelligence"
    case openRouter = "openrouter"

    var displayName: String {
        switch self {
        case .appleIntelligence:
            return "Apple Intelligence"
        case .openRouter:
            return "OpenRouter"
        }
    }

    var badgeText: String {
        switch self {
        case .appleIntelligence:
            return "On-device"
        case .openRouter:
            return "Cloud"
        }
    }
}

enum AppleIntelligenceStatus: Equatable {
    case available
    case notEnabled
    case modelNotReady
    case unsupported
    case unavailable

    var isCapable: Bool {
        switch self {
        case .available, .notEnabled, .modelNotReady:
            return true
        case .unsupported, .unavailable:
            return false
        }
    }

    var canGenerateNow: Bool {
        self == .available
    }
}

struct AIProviderStatus: Equatable {
    let preference: AIProviderPreference
    let effectiveProvider: AIResolvedProvider
    let appleIntelligenceStatus: AppleIntelligenceStatus
    let hasOpenRouterKey: Bool
    let openRouterModelID: String?

    var isProviderSelectionLocked: Bool {
        !appleIntelligenceStatus.isCapable
    }

    var canGenerateNow: Bool {
        switch effectiveProvider {
        case .appleIntelligence:
            return appleIntelligenceStatus.canGenerateNow
        case .openRouter:
            return hasOpenRouterKey
        }
    }

    var needsSystemSettings: Bool {
        effectiveProvider == .appleIntelligence && appleIntelligenceStatus == .notEnabled
    }

    var needsAppConfiguration: Bool {
        effectiveProvider == .openRouter && !hasOpenRouterKey
    }

    var providerGroupTitle: String {
        switch effectiveProvider {
        case .appleIntelligence:
            return "Apple Intelligence (On-device)"
        case .openRouter:
            return "OpenRouter (Cloud)"
        }
    }

    var providerReadyDescription: String {
        switch effectiveProvider {
        case .appleIntelligence:
            return "On-device model ready"
        case .openRouter:
            if let openRouterModelID, !openRouterModelID.isEmpty {
                return "Using free-tier model: \(openRouterModelID)"
            }
            return "Using the current OpenRouter free-tier model"
        }
    }

    var unavailableTitle: String {
        switch effectiveProvider {
        case .appleIntelligence:
            switch appleIntelligenceStatus {
            case .notEnabled:
                return "Apple Intelligence Not Enabled"
            case .modelNotReady:
                return "AI Model Not Ready"
            case .unsupported:
                return "Device Not Supported"
            case .unavailable:
                return "Apple Intelligence Unavailable"
            case .available:
                return "Apple Intelligence Ready"
            }
        case .openRouter:
            return hasOpenRouterKey ? "OpenRouter Unavailable" : "OpenRouter API Key Required"
        }
    }

    var unavailableDescription: String {
        switch effectiveProvider {
        case .appleIntelligence:
            switch appleIntelligenceStatus {
            case .notEnabled:
                return "Apple Intelligence is supported on this device, but it is turned off. Enable it in Settings > Apple Intelligence & Siri, or switch to OpenRouter in the app's settings."
            case .modelNotReady:
                return "The Apple Intelligence model is still downloading or preparing on this device. You can wait for it to finish, or switch to OpenRouter in the app's settings."
            case .unsupported:
                return "This device does not support Apple Intelligence. Pace & Plates uses OpenRouter on older phones instead."
            case .unavailable:
                return "Apple Intelligence is currently unavailable on this device. Try again later or switch to OpenRouter in the app's settings."
            case .available:
                return "Apple Intelligence is ready."
            }
        case .openRouter:
            if hasOpenRouterKey {
                return "OpenRouter is selected, but the last request could not be completed. Check your key, rate limits, or network connection."
            }
            if appleIntelligenceStatus.isCapable {
                return "OpenRouter is selected, but no API key is saved yet. Add your OpenRouter key in Settings to use cloud AI, or switch back to Apple Intelligence."
            }
            return "This device does not support Apple Intelligence, so Pace & Plates uses OpenRouter here. Add your OpenRouter API key in Settings to enable AI."
        }
    }
}

extension Notification.Name {
    static let aiProviderConfigurationDidChange = Notification.Name("aiProviderConfigurationDidChange")
}

enum AIProviderManager {
    static let providerPreferenceKey = "aiProviderPreference"
    static let openRouterKeyConfiguredKey = "openRouterKeyConfigured"
    static let openRouterResolvedModelKey = "openRouterResolvedFreeModel"

    private static let keychainAccount = "openrouter.api_key"
    private static let keychainService = Bundle.main.bundleIdentifier ?? "PaceAndPlates"

    static func providerPreference() -> AIProviderPreference {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: providerPreferenceKey),
           let preference = AIProviderPreference(rawValue: raw) {
            return preference
        }

        let inferred: AIProviderPreference = appleIntelligenceStatus().isCapable ? .appleIntelligence : .openRouter
        defaults.set(inferred.rawValue, forKey: providerPreferenceKey)
        return inferred
    }

    static func setProviderPreference(_ preference: AIProviderPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: providerPreferenceKey)
        postConfigurationChanged()
    }

    static func appleIntelligenceStatus() -> AppleIntelligenceStatus {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .notEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable(.deviceNotEligible):
                return .unsupported
            case .unavailable:
                return .unavailable
            @unknown default:
                return .unavailable
            }
            #endif
        }
        #endif
        return .unsupported
    }

    static func currentStatus() -> AIProviderStatus {
        bootstrapOpenRouterKeyIfAvailable()

        let appleStatus = appleIntelligenceStatus()
        let preference = providerPreference()
        let effectiveProvider: AIResolvedProvider

        if appleStatus.isCapable {
            effectiveProvider = preference == .openRouter ? .openRouter : .appleIntelligence
        } else {
            effectiveProvider = .openRouter
        }

        return AIProviderStatus(
            preference: preference,
            effectiveProvider: effectiveProvider,
            appleIntelligenceStatus: appleStatus,
            hasOpenRouterKey: keychainOpenRouterKey() != nil,
            openRouterModelID: currentOpenRouterModelID()
        )
    }

    static func bootstrapOpenRouterKeyIfAvailable() {
        if keychainOpenRouterKey() != nil {
            synchronizeOpenRouterKeyFlag()
            return
        }

        let environmentKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let environmentKey, !environmentKey.isEmpty {
            _ = saveOpenRouterKey(environmentKey)
            return
        }

        synchronizeOpenRouterKeyFlag()
    }

    @discardableResult
    static func saveOpenRouterKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteOpenRouterKey() }

        guard let data = trimmed.data(using: .utf8) else { return false }

        let query = baseKeychainQuery()
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        let didSave = status == errSecSuccess
        synchronizeOpenRouterKeyFlag()
        if didSave {
            postConfigurationChanged()
        }
        return didSave
    }

    static func isUsableOpenRouterKeyCandidate(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return false }
        return trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    @discardableResult
    static func deleteOpenRouterKey() -> Bool {
        let status = SecItemDelete(baseKeychainQuery() as CFDictionary)
        let didDelete = status == errSecSuccess || status == errSecItemNotFound
        synchronizeOpenRouterKeyFlag()
        if didDelete {
            postConfigurationChanged()
        }
        return didDelete
    }

    static func loadOpenRouterKey() -> String? {
        bootstrapOpenRouterKeyIfAvailable()
        return keychainOpenRouterKey()
    }

    static func setCurrentOpenRouterModelID(_ modelID: String?) {
        let defaults = UserDefaults.standard
        let trimmed = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: openRouterResolvedModelKey)
        } else {
            defaults.removeObject(forKey: openRouterResolvedModelKey)
        }
        postConfigurationChanged()
    }

    static func currentOpenRouterModelID() -> String? {
        UserDefaults.standard.string(forKey: openRouterResolvedModelKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keychainOpenRouterKey() -> String? {
        var query = baseKeychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func synchronizeOpenRouterKeyFlag() {
        let hasKey = keychainOpenRouterKey() != nil
        let defaults = UserDefaults.standard
        if defaults.object(forKey: openRouterKeyConfiguredKey) as? Bool != hasKey {
            defaults.set(hasKey, forKey: openRouterKeyConfiguredKey)
        }
    }

    private static func postConfigurationChanged() {
        synchronizeOpenRouterKeyFlag()
        NotificationCenter.default.post(name: .aiProviderConfigurationDidChange, object: nil)
    }

    private static func baseKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
    }
}
