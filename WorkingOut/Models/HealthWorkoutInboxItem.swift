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
    // Stable source/metadata identity used to reconcile HealthKit replacements.
    var sourceBundleIdentifier: String? = nil
    var healthSyncIdentifier: String? = nil
    var healthSyncVersion: Int? = nil
    var healthExternalUUID: String? = nil
    // Other HKWorkout UUIDs observed for this same logical workout. Health data
    // remains untouched; aliases only prevent duplicate local inbox cards.
    var alternateHealthWorkoutUUIDsRaw: String = ""
    // HealthKit replacements can report the deletion and addition in separate
    // anchored-query batches. Keep the local row hidden briefly so a later
    // replacement can inherit its linked/dismissed state and metrics.
    var healthDeletionObservedAt: Date? = nil
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
         sourceName: String? = nil,
         sourceBundleIdentifier: String? = nil,
         healthSyncIdentifier: String? = nil,
         healthSyncVersion: Int? = nil,
         healthExternalUUID: String? = nil,
         alternateHealthWorkoutUUIDsRaw: String = "") {
        self.id = id
        self.healthWorkoutUUID = healthWorkoutUUID
        self.startDate = startDate
        self.endDate = endDate
        self.activityType = activityType
        self.duration = duration
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.healthSyncIdentifier = healthSyncIdentifier
        self.healthSyncVersion = healthSyncVersion
        self.healthExternalUUID = healthExternalUUID
        self.alternateHealthWorkoutUUIDsRaw = alternateHealthWorkoutUUIDsRaw
        self.statusRaw = Status.pending.rawValue
        self.createdAt = Date()
    }
}
