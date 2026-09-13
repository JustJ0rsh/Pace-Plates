import Foundation
import CryptoKit

struct CoachProgressionEvidence: Codable, Sendable {
    var executionID: UUID
    var endedAt: Date
    var status: String
    var prescription: CoachStrengthSession
    var results: [CoachSetResult]
    var revision: String
    var painScore: Int? = nil
    var soreness: Int? = nil
    var readinessReviewed: Bool? = nil
    var recoveryCheckInID: UUID? = nil
    var phaseReviewID: UUID? = nil
}

struct CoachProgressionProposal: Codable, Sendable {
    var templateID: String
    var exerciseID: String
    var increment: CoachWeight
    var newLoads: [String: CoachWeight]
    var evidenceIDs: [UUID]
    var evidenceFingerprint: String
    var loadBasis: CoachLoadBasis
    var exerciseKey: String
    var equipment: [String]
    var prescriptionBasis: CoachPrescriptionBasis
    var reason: String
    var workingSetPrescription: [CoachStrengthSet]? = nil
}

enum CoachProgressionRules {
    enum Evaluation {
        case propose(CoachProgressionProposal)
        case hold(String)
    }
    static func shouldHoldForRecovery(civilDate: String, timeZoneIdentifier: String, painScore: Int?, soreness: Int?, now: Date = Date()) -> Bool {
        guard (painScore ?? 0) > 0 || (soreness ?? 0) >= 7 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        func civil(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        let parts = civilDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), civil(date) == civilDate,
              let earliest = calendar.date(byAdding: .day, value: -6, to: now) else { return false }
        return civilDate >= civil(earliest) && civilDate <= civil(now)
    }
    static func fingerprint(_ evidence: [CoachProgressionEvidence]) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let normalized = evidence.map { item in
            var value = item
            value.revision = ""
            value.results = item.results.map { result in
                var value = result; value.updatedAt = Date(timeIntervalSince1970: 0); return value
            }.sorted { $0.id < $1.id }
            return value
        }.sorted { $0.executionID.uuidString < $1.executionID.uuidString }
        return SHA256.hash(data: try encoder.encode(normalized)).map { String(format: "%02x", $0) }.joined()
    }
    static func evaluate(rule: CoachDoubleProgressionRule, evidence: [CoachProgressionEvidence], holdForRecovery: Bool) throws -> Evaluation {
        if holdForRecovery { return .hold("Recent pain or high soreness calls for a review. No load increase is proposed.") }
        let relevant = evidence.filter { $0.prescription.id == rule.sessionTemplateId }.sorted { $0.endedAt > $1.endedAt }
        guard relevant.count >= rule.requiredSuccessfulOccurrences else { return .hold("Record \(rule.requiredSuccessfulOccurrences) comparable sessions before reviewing an increase.") }
        let selected = Array(relevant.prefix(rule.requiredSuccessfulOccurrences))
        guard selected.allSatisfy({ $0.status == "completed" }) else {
            return .hold("Recent occurrences include incomplete, partial, or skipped work. Record the required consecutive comparable completed sessions before increasing load.")
        }
        guard selected.allSatisfy({ $0.painScore == 0 && ($0.soreness ?? 0) < 7 && $0.readinessReviewed == true }) else {
            return .hold("Review pain feedback and phase readiness for every supporting session. Missing pain feedback is unknown; it does not document a pain-free session.")
        }
        guard let latestExercise = selected.first?.prescription.exercises.first(where: { $0.id == rule.exerciseId }) else { return .hold("This exercise has no comparable baseline.") }
        guard latestExercise.loadBasis != .assistance else {
            return .hold("Review assistance changes manually. Adding assistance reduces resistance, so this load-increase rule cannot prescribe that change.")
        }
        let latestWorking = latestExercise.sets.filter { $0.role == .working }.sorted { $0.id < $1.id }
        var baselineLoads: [String: CoachWeight] = [:]
        for item in selected {
            guard item.status == "completed", let exercise = item.prescription.exercises.first(where: { $0.id == rule.exerciseId }),
                  exercise.exercise.key == latestExercise.exercise.key,
                  exercise.exercise.equipment.sorted() == latestExercise.exercise.equipment.sorted(),
                  exercise.prescriptionBasis == latestExercise.prescriptionBasis, exercise.loadBasis == latestExercise.loadBasis else {
                return .hold("Recent sessions differ in completion, exercise, equipment, or counting basis.")
            }
            let working = exercise.sets.filter { $0.role == .working }.sorted { $0.id < $1.id }
            guard !working.isEmpty else { return .hold("No prescribed working sets are available for this rule.") }
            guard working.count == latestWorking.count,
                  zip(working, latestWorking).allSatisfy({ $0.id == $1.id && $0.target == $1.target && $0.effort == $1.effort }) else {
                return .hold("The prescribed working sets or rep and effort targets changed. Establish the required successful sessions at the current prescription.")
            }
            for set in working {
                guard case let .reps(_, upper) = set.target,
                      let actual = item.results.first(where: { $0.exerciseID == exercise.id && $0.setID == set.id }),
                      actual.isValid, actual.state == .completed, actual.reps.map({ $0 >= upper }) == true,
                      actual.repCounting == exercise.prescriptionBasis.rawValue,
                      actual.loadBasis == exercise.loadBasis.rawValue,
                      (actual.performedExerciseID == exercise.exercise.key || actual.substitutionIsEquivalent),
                      (actual.equipment == exercise.exercise.equipment.sorted().joined(separator: ",") || actual.substitutionIsEquivalent),
                      actual.effortScale == "rir", actual.effort.map({ $0 >= rule.minimumRIR }) == true else {
                    return .hold("Every prescribed working set must reach its upper rep target with recorded RIR of at least \(rule.minimumRIR.formatted()). Warm-ups, skipped sets, partial data, and unapproved substitutions do not qualify.")
                }
                guard let actualLoad = actual.load, actualLoad.isFinite,
                      let actualUnit = actual.loadUnit.flatMap(CoachWeightUnit.init(rawValue:)) else {
                    return .hold("Establish an actual load baseline first. An unspecified target or actual load is not zero.")
                }
                let normalized = convert(actualLoad, from: actualUnit, to: rule.increment.unit)
                if let baseline = baselineLoads[set.id], abs(baseline.value - normalized) > 0.001 {
                    return .hold("Recent actual loads differ. Establish the required successful sessions at one comparable baseline.")
                }
                baselineLoads[set.id] = CoachWeight(value: normalized, unit: rule.increment.unit)
            }
        }
        let fingerprint = try Self.fingerprint(selected)
        return .propose(.init(templateID: rule.sessionTemplateId, exerciseID: rule.exerciseId, increment: rule.increment,
            newLoads: baselineLoads.mapValues { CoachWeight(value: $0.value + rule.increment.value, unit: rule.increment.unit) },
            evidenceIDs: selected.map(\.executionID), evidenceFingerprint: fingerprint, loadBasis: latestExercise.loadBasis,
            exerciseKey: latestExercise.exercise.key, equipment: latestExercise.exercise.equipment, prescriptionBasis: latestExercise.prescriptionBasis,
            reason: "All working sets reached their upper rep targets with RIR ≥ \(rule.minimumRIR.formatted()) in \(selected.count) comparable sessions. Proposed increment: \(rule.increment.value.formatted()) \(rule.increment.unit.rawValue).",
            workingSetPrescription: latestWorking))
    }
    static func convert(_ value: Double, from: CoachWeightUnit, to: CoachWeightUnit) -> Double {
        if from == to { return value }
        return from == .lb ? value * 0.45359237 : value / 0.45359237
    }
}
