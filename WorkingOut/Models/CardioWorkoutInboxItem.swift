import Foundation
import SwiftData

/// A cardio workout from Apple Health waiting to be paired with the app's
/// activity log. This is intentionally separate from the strength inbox so a
/// run, walk, or ride can enrich a `RunningSession` without becoming a gym
/// workout.
@Model
final class CardioWorkoutInboxItem {
    enum Status: String {
        case pending
        case linked
        case dismissed
    }

    var id: UUID = UUID()
    var healthWorkoutUUID: String = ""
    /// Other Health UUIDs consolidated into this logical activity.
    var alternateHealthWorkoutUUIDsRaw: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var activityType: String = "running"
    var distanceMeters: Double = 0
    var duration: TimeInterval = 0
    var calories: Double? = nil
    var avgHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var minHeartRate: Double? = nil
    var sourceName: String? = nil
    var sourceBundleIdentifier: String? = nil
    var healthSyncIdentifier: String? = nil
    var healthSyncVersion: Int? = nil
    var healthExternalUUID: String? = nil
    /// Source-scoped maximum sync versions retained even when another Health
    /// representation becomes the item's primary identity.
    var healthSyncVersionsByStableIdentityRaw: String = ""
    /// The Health representation selected for wearable metrics. This can
    /// intentionally differ from `healthWorkoutUUID`.
    var metricSourceHealthWorkoutUUID: String? = nil
    var metricSourceName: String? = nil
    var metricSourceBundleIdentifier: String? = nil
    /// A deletion is held briefly so a corrected Health replacement can inherit
    /// the user's linked/dismissed decision.
    var healthDeletionObservedAt: Date? = nil
    var statusRaw: String = Status.pending.rawValue
    var linkedRunningSessionID: UUID? = nil
    var suggestedRunningSessionID: UUID? = nil
    var createdAt: Date = Date()
    /// Attempts, including unavailable metrics, advance the persisted refresh queue.
    var healthDetailsLastAttemptAt: Date? = nil
    var healthDistanceLastAttemptAt: Date? = nil

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        healthWorkoutUUID: String,
        startDate: Date,
        endDate: Date,
        activityType: String,
        distanceMeters: Double,
        duration: TimeInterval,
        calories: Double? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        minHeartRate: Double? = nil,
        sourceName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        healthSyncIdentifier: String? = nil,
        healthSyncVersion: Int? = nil,
        healthExternalUUID: String? = nil,
        healthSyncVersionsByStableIdentityRaw: String = "",
        metricSourceHealthWorkoutUUID: String? = nil,
        metricSourceName: String? = nil,
        metricSourceBundleIdentifier: String? = nil,
        alternateHealthWorkoutUUIDsRaw: String = "",
        suggestedRunningSessionID: UUID? = nil
    ) {
        self.id = id
        self.healthWorkoutUUID = healthWorkoutUUID
        self.alternateHealthWorkoutUUIDsRaw = alternateHealthWorkoutUUIDsRaw
        self.startDate = startDate
        self.endDate = endDate
        self.activityType = activityType
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.healthSyncIdentifier = healthSyncIdentifier
        self.healthSyncVersion = healthSyncVersion
        self.healthExternalUUID = healthExternalUUID
        self.healthSyncVersionsByStableIdentityRaw =
            healthSyncVersionsByStableIdentityRaw
        self.metricSourceHealthWorkoutUUID = metricSourceHealthWorkoutUUID
        self.metricSourceName = metricSourceName
        self.metricSourceBundleIdentifier = metricSourceBundleIdentifier
        self.suggestedRunningSessionID = suggestedRunningSessionID
        self.createdAt = Date()
    }
}
