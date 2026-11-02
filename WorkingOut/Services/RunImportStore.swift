import Foundation
import SwiftData

struct NewRunPayload: Equatable {
    let date: Date
    let distance: Double
    let distanceUnit: String
    let duration: TimeInterval
    let calories: Double?
    let locations: Data?
    let healthWorkoutUUID: String
    let activityType: String
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let minHeartRate: Double?
    let avgCadence: Double?
    let maxCadence: Double?
    let totalAscent: Double?
    let totalDescent: Double?
    let minElevation: Double?
    let maxElevation: Double?
    let avgPower: Double?
    let maxPower: Double?
}

enum RunImportAction: Equatable {
    case update(
        recordID: PersistentIdentifier,
        healthWorkoutUUID: String,
        activityType: String,
        date: Date?,
        distance: Double?,
        distanceUnit: String?,
        duration: TimeInterval?,
        calories: Double?,
        locations: Data?
    )
    case unlink(healthWorkoutUUID: String)
    case insert(NewRunPayload)
}

@MainActor
enum RunImportStore {
    struct ApplyResult {
        let conflictingRecordCount: Int
        var needsReview: Bool { conflictingRecordCount > 0 }
    }

    @discardableResult
    static func apply(_ actions: [RunImportAction], context: ModelContext) throws -> ApplyResult {
        guard !actions.isEmpty else { return ApplyResult(conflictingRecordCount: 0) }
        var sessions = try context.fetch(FetchDescriptor<RunningSession>())
        let byRecord = RecordIdentityLookup.uniqueIndex(sessions, by: \.persistentModelID)
        let updates = actions.compactMap { action -> (PersistentIdentifier, RunImportAction)? in
            guard case let .update(recordID, _, _, _, _, _, _, _, _) = action else { return nil }
            return (recordID, action)
        }
        let conflictingTargets = Set(Dictionary(grouping: updates, by: { $0.0 }).filter { _, values in
            values.contains { $0.1 != values[0].1 }
        }.keys)
        var skippedTargets = conflictingTargets
        for action in actions {
            switch action {
            case let .update(recordID, uuid, activityType, date, distance, distanceUnit, duration, calories, locations):
                // The planner observes one saved snapshot. Multiple Health
                // candidates must not race to replace the same local record.
                guard !conflictingTargets.contains(recordID) else { continue }
                guard let session = byRecord[recordID],
                      !sessions.contains(where: { $0.persistentModelID != recordID && $0.healthWorkoutUUID == uuid }) else {
                    skippedTargets.insert(recordID)
                    continue
                }
                session.healthWorkoutUUID = uuid
                session.activityType = activityType
                if let date { session.date = date }
                if let distance { session.distance = distance }
                if let distanceUnit { session.distanceUnit = distanceUnit }
                if let duration { session.duration = duration }
                if let calories, calories > 0 { session.calories = calories }
                if session.locations.isEmpty, let locations, !locations.isEmpty { session.locations = locations }
            case let .unlink(uuid):
                // A Health deletion removes that external link from every copy;
                // the separate app records, notes and routes all remain intact.
                for session in sessions where session.healthWorkoutUUID == uuid { session.healthWorkoutUUID = nil }
            case let .insert(payload):
                guard !sessions.contains(where: { $0.healthWorkoutUUID == payload.healthWorkoutUUID }) else { continue }
                let session = RunningSession(date: payload.date, distance: payload.distance, distanceUnit: payload.distanceUnit,
                    duration: payload.duration, calories: payload.calories, locations: payload.locations,
                    healthWorkoutUUID: payload.healthWorkoutUUID, activityType: payload.activityType,
                    avgHeartRate: payload.avgHeartRate, maxHeartRate: payload.maxHeartRate, minHeartRate: payload.minHeartRate,
                    avgCadence: payload.avgCadence, maxCadence: payload.maxCadence, totalAscent: payload.totalAscent,
                    totalDescent: payload.totalDescent, minElevation: payload.minElevation, maxElevation: payload.maxElevation,
                    avgPower: payload.avgPower, maxPower: payload.maxPower)
                context.insert(session)
                sessions.append(session)
            }
        }
        try context.save()
        return ApplyResult(conflictingRecordCount: skippedTargets.count)
    }
}
