import Foundation

@MainActor
enum WorkoutWeightUnitConversion {
    static func convert(_ log: ExerciseLog, to unit: String) {
        guard ["kg", "lb", "lbs"].contains(log.weightUnit), ["kg", "lbs"].contains(unit),
              log.weightUnit != unit else { return }
        let source = log.weightUnit
        log.weight = UnitConverter.weight(log.weight, from: source, to: unit)
        log.actualWeight = log.actualWeight.map { UnitConverter.weight($0, from: source, to: unit) }
        log.weightUnit = unit
    }
}
