import Foundation

enum WearableDevicePreference: String, CaseIterable, Identifiable {
    static let storageKey = "preferredWearableDevice"

    case none
    case appleWatch
    case ouraRing
    case fitbit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Apple Health Only"
        case .appleWatch: return "Apple Watch"
        case .ouraRing: return "Oura Ring"
        case .fitbit: return "Fitbit"
        }
    }

    var vitalsSubtitle: String {
        switch self {
        case .none: return "From Apple Health"
        case .appleWatch: return "Apple Watch via Apple Health"
        case .ouraRing: return "Oura Ring via Apple Health"
        case .fitbit: return "Fitbit via Apple Health"
        }
    }

    var healthSourceNameHints: [String] {
        switch self {
        case .none:
            return []
        case .appleWatch:
            return ["Apple Watch", "Watch"]
        case .ouraRing:
            return ["Oura", "Oura Ring"]
        case .fitbit:
            return ["Fitbit", "Google Health"]
        }
    }
}
