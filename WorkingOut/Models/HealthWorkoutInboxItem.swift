import Foundation
import SwiftData

/// A wearable/Health workout waiting for the user to triage: link it to an
/// existing logged workout, create a new workout from it, or dismiss it.
@Model
final class HealthWorkoutInboxItem {
    enum Status: String {
        case pending
        case linked
        case dismissed
    }

    var id: UUID = UUID()
    // HKWorkout UUID; prevents re-import and allows deletion sync
    var healthWorkoutUUID: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    // Raw activity key, e.g. "traditionalStrengthTraining"
    var activityType: String = "traditionalStrengthTraining"
    var duration: TimeInterval = 0
    var calories: Double? = nil
    var avgHeartRate: Double? = nil
    // Recording device/app, e.g. "Apple Watch"
    var sourceName: String? = nil
    var statusRaw: String = Status.pending.rawValue
    var linkedWorkoutSessionID: UUID? = nil
    var createdAt: Date = Date()

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         healthWorkoutUUID: String,
         startDate: Date,
         endDate: Date,
         activityType: String,
         duration: TimeInterval,
         calories: Double? = nil,
         avgHeartRate: Double? = nil,
         sourceName: String? = nil) {
        self.id = id
        self.healthWorkoutUUID = healthWorkoutUUID
        self.startDate = startDate
        self.endDate = endDate
        self.activityType = activityType
        self.duration = duration
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.sourceName = sourceName
        self.statusRaw = Status.pending.rawValue
        self.createdAt = Date()
    }
}
