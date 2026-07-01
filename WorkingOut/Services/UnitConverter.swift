import Foundation

enum UnitConverter {
    static func weight(_ value: Double, from sourceUnit: String, to targetUnit: String) -> Double {
        guard let from = massUnit(for: sourceUnit), let to = massUnit(for: targetUnit) else {
            return value
        }
        return Measurement(value: value, unit: from).converted(to: to).value
    }

    static func distance(_ value: Double, from sourceUnit: String, to targetUnit: String) -> Double {
        guard let from = lengthUnit(for: sourceUnit), let to = lengthUnit(for: targetUnit) else {
            return value
        }
        return Measurement(value: value, unit: from).converted(to: to).value
    }

    static func canonicalWeightUnit(_ unit: String) -> String {
        massUnit(for: unit) == .kilograms ? "kg" : "lbs"
    }

    static func canonicalDistanceUnit(_ unit: String) -> String {
        lengthUnit(for: unit) == .kilometers ? "km" : "mi"
    }

    private static func massUnit(for unit: String) -> UnitMass? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "kg", "kgs", "kilogram", "kilograms":
            return .kilograms
        case "lb", "lbs", "pound", "pounds":
            return .pounds
        default:
            return nil
        }
    }

    private static func lengthUnit(for unit: String) -> UnitLength? {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "km", "kilometer", "kilometers":
            return .kilometers
        case "mi", "mile", "miles":
            return .miles
        default:
            return nil
        }
    }
}
