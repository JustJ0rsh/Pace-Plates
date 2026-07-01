import Foundation
import SwiftData

@Model
final class RunningPlanSession {
    var id: UUID = UUID()

    @Relationship(deleteRule: .nullify)
    var plan: RunningPlan?

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
    var completionSource: String? = nil // manual | auto
    var completedAt: Date? = nil
    var completedRunSessionID: UUID? = nil

    init(
        id: UUID = UUID(),
        plan: RunningPlan? = nil,
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
