import Foundation

/// Read-only workout statistics. Manual entries are logged values; planned
/// targets contribute only after their set is checked. No history is rewritten.
@MainActor
enum WorkoutStatistics {
    private enum Measurement {
        case strength(reps: Int, weight: Double)
        case duration(Double)
    }

    static func isPlanned(_ session: WorkoutSession) -> Bool {
        session.sourceTemplateID != nil || session.coachExecutionID != nil
            || session.plannedSessionID != nil || session.completionProvenance == "planned_workout"
    }

    static func confirmedLogs(in session: WorkoutSession) -> [ExerciseLog] {
        guard isEligibleStatus(session) else { return [] }
        return (session.exerciseLogs ?? []).filter {
            // The parent array is authoritative for older rows without an
            // inverse. A conflicting explicit owner is never counted here.
            acceptsParentMembership(ownerID: $0.workoutSession?.id, sessionID: session.id)
                && measurement($0, in: session) != nil
        }
    }

    /// Kept as an explicit value boundary: SwiftData may eagerly reconstruct
    /// inverses, while older decoded graphs can provide only parent membership.
    static func acceptsParentMembership(ownerID: UUID?, sessionID: UUID) -> Bool {
        ownerID == nil || ownerID == sessionID
    }

    static func hasActivity(_ session: WorkoutSession) -> Bool {
        guard isEligibleStatus(session) else { return false }
        if session.executionStatusRaw == "legacy_recorded" && !isPlanned(session) { return true }
        if let duration = session.healthDuration, duration.isFinite && duration > 0 { return true }
        return !confirmedLogs(in: session).isEmpty
    }

    static func volume(for session: WorkoutSession, unit: String, category: String? = nil,
                       logIDs: Set<UUID>? = nil) -> Double {
        guard isWeightUnit(unit) else { return 0 }
        let filter = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        var total = 0.0
        for log in confirmedLogs(in: session) {
            if let logIDs, !logIDs.contains(log.id) { continue }
            if let filter, !filter.isEmpty, filter != "All",
               (log.exerciseDefinition?.muscleGroup ?? "").trimmingCharacters(in: .whitespacesAndNewlines) != filter {
                continue
            }
            guard case let .strength(reps, weight) = measurement(log, in: session) else { continue }
            let converted = UnitConverter.weight(weight, from: log.weightUnit, to: unit)
            guard converted.isFinite && converted >= 0 else { continue }
            // Convert before multiplying so an Int.max unilateral value cannot trap.
            let repetitions = Double(reps) * (log.isIsolated ? 2 : 1)
            let contribution = repetitions * converted
            let next = total + contribution
            guard contribution.isFinite && contribution >= 0 && next.isFinite else { continue }
            total = next
        }
        return total
    }

    /// Shares the same finite, nonnegative boundary with day/chart totals.
    static func sumFiniteVolumes(_ values: [Double]) -> Double {
        values.reduce(0) { total, value in
            guard value.isFinite && value >= 0 else { return total }
            let next = total + value
            return next.isFinite ? next : total
        }
    }

    private static func isEligibleStatus(_ session: WorkoutSession) -> Bool {
        ["legacy_recorded", "in_progress", "completed", "partial"].contains(session.executionStatusRaw)
    }

    private static func measurement(_ log: ExerciseLog, in session: WorkoutSession) -> Measurement? {
        guard isEligibleStatus(session) else { return nil }
        if isPlanned(session) {
            guard log.isCompleted else { return nil }
            // A recorded zero or invalid actual must not become the planned
            // nonzero target. Only older checked sets with no actuals use raw values.
            if log.actualReps != nil || log.actualWeight != nil || log.actualDurationSeconds != nil {
                return explicitMeasurement(log)
            }
            return savedMeasurement(log)
        }
        // The manual editor stores entered values here. Old actual fields may be
        // stale; reading raw values also keeps ordinary manual edits immediate.
        return savedMeasurement(log)
    }

    private static func explicitMeasurement(_ log: ExerciseLog) -> Measurement? {
        if log.isCardio {
            return positiveDuration(log.actualDurationSeconds).map(Measurement.duration)
        }
        if let reps = log.actualReps {
            guard reps >= 0 else { return nil }
            if reps > 0 {
                guard let weight = log.actualWeight, validWeight(weight, unit: log.weightUnit) else { return nil }
                return .strength(reps: reps, weight: weight)
            }
        }
        if let weight = log.actualWeight, !validWeight(weight, unit: log.weightUnit) { return nil }
        return positiveDuration(log.actualDurationSeconds).map(Measurement.duration)
    }

    private static func savedMeasurement(_ log: ExerciseLog) -> Measurement? {
        if log.isCardio {
            return positiveDuration(log.durationSeconds.map(Double.init)).map(Measurement.duration)
        }
        guard log.reps >= 0, validWeight(log.weight, unit: log.weightUnit) else { return nil }
        if log.reps > 0 { return .strength(reps: log.reps, weight: log.weight) }
        return positiveDuration(log.durationSeconds.map(Double.init)).map(Measurement.duration)
    }

    private static func positiveDuration(_ value: Double?) -> Double? {
        guard let value, value.isFinite && value > 0 else { return nil }
        return value
    }

    private static func validWeight(_ value: Double, unit: String) -> Bool {
        value.isFinite && value >= 0 && isWeightUnit(unit)
    }

    private static func isWeightUnit(_ unit: String) -> Bool {
        ["kg", "kgs", "kilogram", "kilograms", "lb", "lbs", "pound", "pounds"]
            .contains(unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
