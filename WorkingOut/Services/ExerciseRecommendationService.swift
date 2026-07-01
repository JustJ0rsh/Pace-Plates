import Foundation
import SwiftData

struct ExerciseBaseline: Identifiable {
    let id = UUID()
    let name: String
    let e1rm: Double // Estimated 1RM in user's preferred weight unit
    let lastByReps: [Int: Double] // reps -> last working weight
    let occurrences: Int
}

enum ExerciseRecommendationService {
    // Estimate 1RM via Epley formula and find last working sets per reps count
    static func baselines(context: ModelContext, preferredUnit: String) -> [ExerciseBaseline] {
        let logs: [ExerciseLog] = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        var grouped: [String: [ExerciseLog]] = [:]
        for l in logs {
            let rawName = l.exerciseDefinition?.name ?? l.exerciseName ?? "Unknown"
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            grouped[name, default: []].append(l)
        }
        var result: [ExerciseBaseline] = []
        for (name, arr) in grouped {
            guard !name.isEmpty else { continue }
            var bestE1RM: Double = 0
            var lastByReps: [Int: (date: Date, weight: Double)] = [:]

            for log in arr {
                let weight = convertWeight(log.weight, from: log.weightUnit, to: preferredUnit)
                let reps = max(log.effectiveReps, 1)
                let e1rm = epley1RM(weight: weight, reps: reps)
                if e1rm > bestE1RM { bestE1RM = e1rm }

                // Track most recent per reps
                let date = (log.workoutSession?.date) ?? Date.distantPast
                if let existing = lastByReps[reps] {
                    if date > existing.date { lastByReps[reps] = (date, weight) }
                } else {
                    lastByReps[reps] = (date, weight)
                }
            }

            let mapped = Dictionary(uniqueKeysWithValues: lastByReps.map { ($0.key, $0.value.weight) })
            result.append(ExerciseBaseline(name: name, e1rm: bestE1RM, lastByReps: mapped, occurrences: arr.count))
        }
        // Sort by frequency then by e1RM descending, return top 10
        return result.sorted { lhs, rhs in
            if lhs.occurrences == rhs.occurrences { return lhs.e1rm > rhs.e1rm }
            return lhs.occurrences > rhs.occurrences
        }
    }

    // For common rep targets, suggest weights as % of 1RM
    static func suggestedLoads(e1rm: Double, unit: String, repTargets: [Int]) -> [Int: Double] {
        var dict: [Int: Double] = [:]
        for r in repTargets {
            let pct = percent(forReps: r)
            let raw = e1rm * pct
            dict[r] = roundForPlates(raw, unit: unit)
        }
        return dict
    }

    private static func epley1RM(weight: Double, reps: Int) -> Double {
        if reps <= 1 { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    private static func percent(forReps reps: Int) -> Double {
        switch reps {
        case 3: return 0.90
        case 4: return 0.87
        case 5: return 0.85
        case 6: return 0.83
        case 7: return 0.80
        case 8: return 0.77
        case 9: return 0.75
        case 10: return 0.72
        case 12: return 0.67
        default:
            if reps < 3 { return 0.92 }
            if reps > 12 { return 0.60 }
            return 0.75
        }
    }

    private static func roundForPlates(_ value: Double, unit: String) -> Double {
        // Round to typical increments to match real plates
        if unit.lowercased() == "kg" {
            return (value / 2.5).rounded() * 2.5
        } else {
            return (value / 5.0).rounded() * 5.0
        }
    }

    private static func convertWeight(_ value: Double, from: String, to: String) -> Double {
        if from == to { return value }
        if from == "kg" && to == "lbs" { return value * 2.20462 }
        if from == "lbs" && to == "kg" { return value / 2.20462 }
        return value
    }
}

