import Foundation

/// Actual values remain absent until the user records them. Prescription values
/// are deliberately kept in the execution's immutable prescription snapshot.
struct CoachSetResult: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var exerciseID: String
    var setID: String
    var performedExerciseID: String
    var performedExerciseName: String
    var equipment: String?
    var reps: Int?
    var load: Double?
    var loadUnit: String?
    var loadBasis: String?
    var repCounting: String?
    var durationSeconds: Double?
    var effortScale: String?
    var effort: Double?
    var notes: String?
    var state: State = .unlogged
    var updatedAt: Date = Date()
    var substitutionIsEquivalent: Bool = false

    enum State: String, Codable, Sendable { case unlogged, completed, skipped }
    var hasMeasurement: Bool { reps != nil || durationSeconds != nil || load != nil }
    var isValid: Bool {
        (reps.map { $0 >= 0 && $0 <= 10_000 } ?? true)
        && [load, durationSeconds].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
        && (durationSeconds.map { $0 < Double(Int.max) } ?? true)
        && (load == nil || ["kg", "lb"].contains(loadUnit ?? ""))
        && (loadBasis.map { CoachLoadBasis(rawValue: $0) != nil } ?? true)
        && (repCounting.map { CoachPrescriptionBasis(rawValue: $0) != nil } ?? true)
        && (effort.map { $0.isFinite && $0 >= 0 && $0 <= 10 } ?? true)
        && (effort == nil || ["rpe", "rir"].contains(effortScale ?? ""))
    }
}

struct CoachExecutionSnapshot: Codable, Sendable {
    var version = 1
    var setResults: [CoachSetResult] = []
    var restTimer: CoachRestTimerState?
    var intervalState: CoachRunIntervalState?
    // Encoded RunRecoverySnapshot includes bounded GPS points and exact run identity.
    var runRecoveryData: Data?
    var notes: String = ""
    var effortScale: String = "rpe"
    var effort: Double?
    var updatedAt: Date = Date()
}

struct CoachRestTimerState: Codable, Equatable, Sendable {
    var setResultID: String
    var deadline: Date?
    var pausedRemaining: TimeInterval?
    var lastChangedAt: Date
    var maximumRemaining: TimeInterval
    var notificationID: String

    init(setResultID: String, seconds: TimeInterval, now: Date = Date()) {
        self.setResultID = setResultID
        maximumRemaining = max(0, seconds)
        deadline = now.addingTimeInterval(maximumRemaining)
        pausedRemaining = nil
        lastChangedAt = now
        notificationID = "coach.rest.\(UUID().uuidString)"
    }
    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return max(0, pausedRemaining) }
        guard let deadline else { return 0 }
        // A clock moving backwards must not extend a prescribed rest indefinitely.
        return min(maximumRemaining, max(0, deadline.timeIntervalSince(now)))
    }
    mutating func pause(at now: Date = Date()) {
        pausedRemaining = remaining(at: now)
        deadline = nil
        lastChangedAt = now
    }
    mutating func resume(at now: Date = Date()) {
        let value = remaining(at: now)
        maximumRemaining = value
        deadline = now.addingTimeInterval(value)
        pausedRemaining = nil
        lastChangedAt = now
    }
    mutating func adjust(by seconds: TimeInterval, at now: Date = Date()) {
        let value = max(0, remaining(at: now) + seconds)
        maximumRemaining = value
        if pausedRemaining != nil { pausedRemaining = value } else { deadline = now.addingTimeInterval(value) }
        lastChangedAt = now
    }
}

struct CoachRunStep: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    var repeatIndex: Int
    var targetSeconds: Double?
    var targetMeters: Double?
    var guidance: String?
    func matchesPrescription(_ other: CoachRunStep) -> Bool {
        id == other.id && repeatIndex == other.repeatIndex && targetSeconds == other.targetSeconds && targetMeters == other.targetMeters
    }
}

struct CoachRunIntervalResult: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var stepID: String
    var repeatIndex: Int
    var activeDuration: Double
    var distanceMeters: Double?
    var state: State
    var completionMethod: Method
    var effortScale: String?
    var effort: Double?
    var measurementSource: String
    enum State: String, Codable, Sendable { case completed, partial, skipped }
    enum Method: String, Codable, Sendable { case target, manual, earlyFinish, skip }
    var paceSecondsPerKilometer: Double? {
        guard let distanceMeters, distanceMeters > 0, activeDuration > 0 else { return nil }
        return activeDuration / distanceMeters * 1_000
    }
}

/// The run's active clock excludes pauses. Boundary updates consume only the
/// current observed interval; a delayed GPS sample never fabricates later steps.
struct CoachRunIntervalState: Codable, Hashable, Sendable {
    var steps: [CoachRunStep]
    var prescriptionRevisionID: UUID?
    var stepIndex = 0
    var baselineDuration: Double = 0
    var baselineMeters: Double?
    var results: [CoachRunIntervalResult] = []
    var lastKnownDuration: Double = 0
    var lastKnownMeters: Double?
    var recoveredGap = false
    var current: CoachRunStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }
    var isComplete: Bool { stepIndex >= steps.count }
    var completedAll: Bool { isComplete && results.count == steps.count && results.allSatisfy { $0.state == .completed } }
    var isValid: Bool {
        !steps.isEmpty && stepIndex >= 0 && stepIndex <= steps.count && steps.count <= 4_096
        && results.count == stepIndex && Set(steps.map(\.id)).count == steps.count
        && results.enumerated().allSatisfy { index, result in
            index < steps.count && result.id == steps[index].id && result.stepID == steps[index].id && result.repeatIndex == steps[index].repeatIndex
            && result.activeDuration.isFinite && result.activeDuration >= 0
            && (result.distanceMeters.map { $0.isFinite && $0 >= 0 } ?? true)
            && (result.effort.map { $0.isFinite && (0...10).contains($0) } ?? true)
            && (result.effort == nil || ["rir", "rpe"].contains(result.effortScale ?? ""))
            && ((result.completionMethod == .skip) == (result.state == .skipped))
            && ((result.completionMethod == .earlyFinish) == (result.state == .partial))
        }
        && baselineDuration.isFinite && baselineDuration >= 0
        && lastKnownDuration.isFinite && lastKnownDuration >= baselineDuration
        && [baselineMeters, lastKnownMeters].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
        && steps.allSatisfy { step in
            (step.targetSeconds != nil) != (step.targetMeters != nil)
            && [step.targetSeconds, step.targetMeters].compactMap { $0 }.allSatisfy { $0.isFinite && $0 > 0 }
        }
    }
    mutating func observe(duration: Double, meters: Double?, allowAutomaticAdvance: Bool = true) {
        guard duration.isFinite, duration >= lastKnownDuration else { return }
        lastKnownDuration = duration
        if let meters, meters.isFinite, meters >= 0 {
            if baselineMeters == nil { baselineMeters = meters }
            lastKnownMeters = meters
        }
        guard allowAutomaticAdvance, let step = current else { return }
        let elapsed = max(0, duration - baselineDuration)
        let distance = intervalDistance(meters)
        if step.targetSeconds.map({ elapsed >= $0 }) == true
            || step.targetMeters.flatMap({ target in distance.map { $0 >= target } }) == true {
            advance(duration: duration, meters: meters, method: .target)
        }
    }
    mutating func advance(duration: Double, meters: Double?, method: CoachRunIntervalResult.Method) {
        guard let step = current, duration.isFinite, duration >= lastKnownDuration,
              meters.map({ $0.isFinite && $0 >= 0 }) ?? true else { return }
        let state: CoachRunIntervalResult.State = method == .skip ? .skipped : (method == .earlyFinish ? .partial : .completed)
        results.append(.init(id: step.id, stepID: step.id, repeatIndex: step.repeatIndex,
            activeDuration: max(0, duration - baselineDuration), distanceMeters: intervalDistance(meters),
            state: state, completionMethod: method, measurementSource: intervalDistance(meters) == nil ? "active_clock" : "gps"))
        stepIndex += 1
        baselineDuration = max(baselineDuration, duration)
        baselineMeters = meters
        lastKnownDuration = max(lastKnownDuration, duration)
        lastKnownMeters = meters
    }
    mutating func restorePaused(at duration: Double) {
        // A newer run-clock checkpoint can outlive the last observed interval
        // boundary. Keep measured progress and exclude that uncertain gap.
        baselineDuration += max(0, duration - lastKnownDuration)
        lastKnownDuration = max(lastKnownDuration, duration)
        recoveredGap = true
    }
    mutating func finishEarly(duration: Double, meters: Double?) {
        guard current != nil else { return }
        advance(duration: duration, meters: meters, method: .earlyFinish)
    }
    private func intervalDistance(_ meters: Double?) -> Double? {
        guard let meters, let baselineMeters, meters.isFinite, meters >= baselineMeters else { return nil }
        return meters - baselineMeters
    }
}
