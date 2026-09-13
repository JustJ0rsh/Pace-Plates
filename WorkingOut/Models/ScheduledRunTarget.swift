import Foundation

struct ScheduledRunTarget: Hashable, Codable, Sendable {
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
        notes: String?
    ) {
        self.sessionID = sessionID
        self.sessionType = sessionType
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetPaceMinPerMile = targetPaceMinPerMile
        self.intensityLevel = intensityLevel
        self.notes = notes
    }

}
