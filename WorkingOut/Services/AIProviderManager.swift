import Foundation
import Security

#if canImport(FoundationModels)
import FoundationModels
#endif

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
    let appleIntelligenceStatus: AppleIntelligenceStatus

    var canGenerateNow: Bool {
        appleIntelligenceStatus.canGenerateNow
    }

    var needsSystemSettings: Bool {
        appleIntelligenceStatus == .notEnabled
    }

    var providerGroupTitle: String {
        "Apple Intelligence (On-device)"
    }

    var providerReadyDescription: String {
        "On-device model ready"
    }

    var unavailableTitle: String {
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
    }

    var unavailableDescription: String {
        switch appleIntelligenceStatus {
        case .notEnabled:
            return "Apple Intelligence is supported on this device, but it is turned off. Enable it in Settings > Apple Intelligence & Siri to use AI features."
        case .modelNotReady:
            return "The Apple Intelligence model is still downloading or preparing on this device. Please wait for it to finish and try again."
        case .unsupported:
            return "This device does not support Apple Intelligence, so AI features are unavailable."
        case .unavailable:
            return "Apple Intelligence is currently unavailable on this device. Try again later."
        case .available:
            return "Apple Intelligence is ready."
        }
    }
}

enum AIProviderManager {
    static let appleIntelligenceModelIdentifier = "apple-intelligence"

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
        if AppLaunchConfiguration.current.isUITest {
            return AIProviderStatus(appleIntelligenceStatus: .available)
        }
        return AIProviderStatus(appleIntelligenceStatus: appleIntelligenceStatus())
    }

    /// One-time removal of artifacts from the retired OpenRouter integration:
    /// the API key stored in Keychain and its orphaned UserDefaults keys.
    static func cleanUpLegacyOpenRouterArtifacts() {
        let defaults = UserDefaults.standard
        let cleanupFlagKey = "didCleanUpOpenRouterArtifacts"
        guard !defaults.bool(forKey: cleanupFlagKey) else { return }

        let keychainQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "PaceAndPlates",
            kSecAttrAccount as String: "openrouter.api_key"
        ]
        SecItemDelete(keychainQuery as CFDictionary)

        [
            "aiProviderPreference",
            "openRouterKeyConfigured",
            "openRouterResolvedFreeModel",
            "openRouterUsage.dailyLimit",
            "openRouterUsage.dayBucket",
            "openRouterUsage.dayCount",
            "openRouterUsage.recentRequestTimestamps",
            "openRouterUsage.cooldownUntil"
        ].forEach { defaults.removeObject(forKey: $0) }

        defaults.set(true, forKey: cleanupFlagKey)
    }
}
