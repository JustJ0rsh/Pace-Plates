import Foundation

struct ScheduledRunTarget: Hashable, Codable, Sendable {
    enum PlanReference: Hashable, Codable, Sendable {
        case legacyRunningSession(UUID)
        case canonicalOccurrence(UUID)
    }

    let planReference: PlanReference?
    let executionID: UUID?
    let prescriptionRevisionID: UUID?
    let structuredSteps: [CoachRunStep]?
    var canonicalOccurrenceID: UUID? {
        if case let .canonicalOccurrence(id) = planReference { return id }
        return nil
    }
    var legacySessionID: UUID? {
        if canonicalOccurrenceID != nil { return nil }
        if case let .legacyRunningSession(id) = planReference { return id }
        return sessionID
    }
    let sessionID: UUID
    let sessionType: String
    let targetDistanceMeters: Double?
    let targetDurationSeconds: Double?
    let targetPaceMinPerMile: Double?
    let intensityLevel: String
    let notes: String?

    init(
        sessionID: UUID,
        sessionType: String,
        targetDistanceMeters: Double?,
        targetDurationSeconds: Double?,
        targetPaceMinPerMile: Double?,
        intensityLevel: String,
        notes: String?,
        planReference: PlanReference? = nil,
        executionID: UUID? = nil,
        prescriptionRevisionID: UUID? = nil,
        structuredSteps: [CoachRunStep]? = nil
    ) {
        self.planReference = planReference
        self.executionID = executionID
        self.prescriptionRevisionID = prescriptionRevisionID
        self.structuredSteps = structuredSteps
        self.sessionID = sessionID
        self.sessionType = sessionType
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetPaceMinPerMile = targetPaceMinPerMile
        self.intensityLevel = intensityLevel
        self.notes = notes
    }

}
