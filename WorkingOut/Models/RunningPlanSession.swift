import Foundation
import SwiftData

@Model
final class RunningPlanSession {
    var id: UUID = UUID()

    @Relationship(deleteRule: .nullify)
    var plan: RunningPlan?

    var completedRun: RunningSession?

    var weekIndex: Int = 0
    var dayIndex: Int = 0
    var scheduledDate: Date? = nil
    var sessionType: String = "easy" // easy | interval | tempo | long | recovery | rest
    var targetDistanceMeters: Double? = nil
    var targetDurationSeconds: Double? = nil
    var targetPaceMinPerMile: Double? = nil
    var intensityLevel: String = "moderate" // easy | moderate | hard
    var notes: String? = nil
    var status: String = "pending" // pending | completed | skipped
    var completionSource: String? = nil // manual | auto | tracked
    var completedAt: Date? = nil
    var completedRunSessionID: UUID? = nil

    init(
        id: UUID = UUID(),
        plan: RunningPlan? = nil,
        completedRun: RunningSession? = nil,
        weekIndex: Int,
        dayIndex: Int,
        scheduledDate: Date? = nil,
        sessionType: String,
        targetDistanceMeters: Double? = nil,
        targetDurationSeconds: Double? = nil,
        targetPaceMinPerMile: Double? = nil,
        intensityLevel: String,
        notes: String? = nil,
        status: String = "pending",
        completionSource: String? = nil,
        completedAt: Date? = nil,
        completedRunSessionID: UUID? = nil
    ) {
        self.id = id
        self.plan = plan
        self.completedRun = completedRun
        self.weekIndex = weekIndex
        self.dayIndex = dayIndex
        self.scheduledDate = scheduledDate
        self.sessionType = sessionType
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetPaceMinPerMile = targetPaceMinPerMile
        self.intensityLevel = intensityLevel
        self.notes = notes
        self.status = status
        self.completionSource = completionSource
        self.completedAt = completedAt
        self.completedRunSessionID = completedRunSessionID
    }
}

/// A value snapshot of a scheduled run that can safely travel through SwiftUI
/// presentation state without keeping a SwiftData model alive across sheets.
struct ScheduledRunTarget: Hashable {
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

    init(session: RunningPlanSession) {
        self.init(
            sessionID: session.id,
            sessionType: session.sessionType,
            targetDistanceMeters: session.targetDistanceMeters,
            targetDurationSeconds: session.targetDurationSeconds,
            targetPaceMinPerMile: session.targetPaceMinPerMile,
            intensityLevel: session.intensityLevel,
            notes: session.notes
        )
    }
}
