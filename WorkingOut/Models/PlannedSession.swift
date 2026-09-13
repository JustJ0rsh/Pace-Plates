import Foundation
import SwiftData

@Model
final class PlannedSession {
    var id: UUID = UUID()

    var sourceWeekID: String? = nil
    var sourceSlotID: String? = nil
    var sourceTemplateID: String? = nil
    var phaseID: String? = nil
    @Attribute(.externalStorage) var prescriptionData: Data? = nil
    var revisionID: UUID? = nil
    var originalCivilDate: String? = nil
    var currentCivilDate: String? = nil
    var intraDayOrder: Int = 0
    var isOptional: Bool = false
    var executionID: UUID? = nil
    var scheduleRevision: Int = 0
    var localScheduleOverride: Bool = false
    var completionProvenance: String? = nil


    var plan: TrainingPlan?

    var title: String = ""
    var activityType: String = "workout" // strength | run | cardio | recovery | rest | workout
    var scheduledDate: Date = Date()
    var weekIndex: Int = 0
    var dayIndex: Int = 0
    var status: String = "pending" // pending | completed | skipped
    var notes: String? = nil

    var targetDistanceMeters: Double? = nil
    var targetDurationSeconds: Double? = nil
    var targetPaceMinPerMile: Double? = nil
    var intensityLevel: String? = nil

    // Executable links into the existing strength and running flows.
    var workoutTemplateID: UUID? = nil
    var runningPlanSessionID: UUID? = nil
    var completedWorkoutSessionID: UUID? = nil
    var completedRunningSessionID: UUID? = nil
    var completedAt: Date? = nil

    init(
        id: UUID = UUID(),
        plan: TrainingPlan? = nil,
        title: String,
        activityType: String,
        scheduledDate: Date,
        weekIndex: Int,
        dayIndex: Int,
        status: String = "pending",
        notes: String? = nil,
        targetDistanceMeters: Double? = nil,
        targetDurationSeconds: Double? = nil,
        targetPaceMinPerMile: Double? = nil,
        intensityLevel: String? = nil,
        workoutTemplateID: UUID? = nil,
        runningPlanSessionID: UUID? = nil,
        completedWorkoutSessionID: UUID? = nil,
        completedRunningSessionID: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.plan = plan
        self.title = title
        self.activityType = activityType
        self.scheduledDate = scheduledDate
        self.weekIndex = weekIndex
        self.dayIndex = dayIndex
        self.status = status
        self.notes = notes
        self.targetDistanceMeters = targetDistanceMeters
        self.targetDurationSeconds = targetDurationSeconds
        self.targetPaceMinPerMile = targetPaceMinPerMile
        self.intensityLevel = intensityLevel
        self.workoutTemplateID = workoutTemplateID
        self.runningPlanSessionID = runningPlanSessionID
        self.completedWorkoutSessionID = completedWorkoutSessionID
        self.completedRunningSessionID = completedRunningSessionID
        self.completedAt = completedAt
    }
}
