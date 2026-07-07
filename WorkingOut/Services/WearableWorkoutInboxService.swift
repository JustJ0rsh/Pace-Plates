import Foundation
import SwiftData
import HealthKit

/// Syncs non-cardio wearable workouts (strength, HIIT, yoga, …) from Apple Health
/// into an inbox where the user links them to a logged workout, creates a new
/// workout from them, or dismisses them.
@MainActor
enum WearableWorkoutInboxService {
    private static let firstScanDateKey = "wearableInbox.firstScanDate"
    private static let initialLookbackDays = 30

    /// Fixed lower bound for the Health query, set 30 days back on first sync.
    private static func scanCutoffDate() -> Date {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: firstScanDateKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date()) ?? Date()
        defaults.set(cutoff.timeIntervalSince1970, forKey: firstScanDateKey)
        return cutoff
    }

    /// Pulls new/deleted wearable workouts from Health and updates inbox items.
    /// Returns the number of newly added inbox items.
    @discardableResult
    static func sync(context: ModelContext) async -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        guard !AppLaunchConfiguration.current.shouldSkipAutomationSideEffects else { return 0 }

        let changes: HealthKitManager.CardioWorkoutChanges
        do {
            changes = try await HealthKitManager.shared.fetchStrengthWorkoutChanges(since: scanCutoffDate())
        } catch {
            // Transient fetch failure: anchor not advanced, next sync retries.
            return 0
        }

        let existingItems = (try? context.fetch(FetchDescriptor<HealthWorkoutInboxItem>())) ?? []
        var itemsByUUID = Dictionary(existingItems.map { ($0.healthWorkoutUUID, $0) },
                                     uniquingKeysWith: { first, _ in first })

        // UUIDs already attached to a workout session (e.g. via an earlier link)
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let linkedSessionUUIDs = Set(sessions.compactMap(\.healthWorkoutUUID).filter { !$0.isEmpty })

        var inserted = 0
        for workout in changes.added {
            let uuid = workout.uuid.uuidString
            if itemsByUUID[uuid] != nil || linkedSessionUUIDs.contains(uuid) { continue }

            let calories = try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout)
            let avgHeartRate = try? await HealthKitManager.shared.averageHeartRate(for: workout)

            let item = HealthWorkoutInboxItem(
                healthWorkoutUUID: uuid,
                startDate: workout.startDate,
                endDate: workout.endDate,
                activityType: activityKey(for: workout.workoutActivityType),
                duration: workout.duration,
                calories: (calories ?? 0) > 0 ? calories : nil,
                avgHeartRate: avgHeartRate.flatMap { $0 },
                sourceName: workout.sourceRevision.source.name
            )
            context.insert(item)
            itemsByUUID[uuid] = item
            inserted += 1
        }

        // Workouts deleted from Health: drop their inbox rows (any status) and
        // unlink sessions that pointed at them.
        if !changes.deletedUUIDs.isEmpty {
            let deletedSet = Set(changes.deletedUUIDs)
            for item in existingItems where deletedSet.contains(item.healthWorkoutUUID) {
                context.delete(item)
            }
            for session in sessions where session.healthWorkoutUUID.map(deletedSet.contains) == true {
                clearHealthLink(on: session)
            }
        }

        let didCommit = PersistenceSave.commit(context, action: "sync wearable inbox")
        if didCommit {
            HealthKitManager.shared.persistStrengthWorkoutAnchor(changes.newAnchor)
        }
        return inserted
    }

    /// Links an inbox item to an existing logged workout, attaching the wearable metrics.
    @discardableResult
    static func link(_ item: HealthWorkoutInboxItem, to session: WorkoutSession, context: ModelContext) -> Bool {
        applyMetrics(from: item, to: session)
        item.status = .linked
        item.linkedWorkoutSessionID = session.id
        return PersistenceSave.commit(context, action: "link wearable workout")
    }

    /// Creates a new workout session from an inbox item and links it.
    static func createSession(from item: HealthWorkoutInboxItem, context: ModelContext) -> WorkoutSession? {
        let session = WorkoutSession(
            date: item.startDate,
            title: activityDisplayName(for: item.activityType)
        )
        applyMetrics(from: item, to: session)
        context.insert(session)
        item.status = .linked
        item.linkedWorkoutSessionID = session.id
        guard PersistenceSave.commit(context, action: "create workout from wearable") else { return nil }
        return session
    }

    static func dismiss(_ item: HealthWorkoutInboxItem, context: ModelContext) {
        item.status = .dismissed
        _ = PersistenceSave.commit(context, action: "dismiss wearable workout")
    }

    private static func applyMetrics(from item: HealthWorkoutInboxItem, to session: WorkoutSession) {
        session.healthWorkoutUUID = item.healthWorkoutUUID
        session.healthDuration = item.duration
        session.healthCalories = item.calories
        session.healthAvgHeartRate = item.avgHeartRate
        session.healthSourceName = item.sourceName
        session.healthActivityType = item.activityType
    }

    private static func clearHealthLink(on session: WorkoutSession) {
        session.healthWorkoutUUID = nil
        session.healthDuration = nil
        session.healthCalories = nil
        session.healthAvgHeartRate = nil
        session.healthSourceName = nil
        session.healthActivityType = nil
    }

    // MARK: - Activity naming

    static func activityKey(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .functionalStrengthTraining: return "functionalStrengthTraining"
        case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
        case .coreTraining: return "coreTraining"
        case .crossTraining: return "crossTraining"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .flexibility: return "flexibility"
        case .martialArts: return "martialArts"
        default: return "other"
        }
    }

    static func activityDisplayName(for key: String) -> String {
        switch key {
        case "traditionalStrengthTraining": return "Strength Training"
        case "functionalStrengthTraining": return "Functional Strength"
        case "highIntensityIntervalTraining": return "HIIT"
        case "coreTraining": return "Core Training"
        case "crossTraining": return "Cross Training"
        case "yoga": return "Yoga"
        case "pilates": return "Pilates"
        case "flexibility": return "Flexibility"
        case "martialArts": return "Martial Arts"
        default: return "Workout"
        }
    }

    static func activityIcon(for key: String) -> String {
        switch key {
        case "traditionalStrengthTraining", "functionalStrengthTraining": return "dumbbell.fill"
        case "highIntensityIntervalTraining": return "flame.fill"
        case "coreTraining": return "figure.core.training"
        case "crossTraining": return "figure.cross.training"
        case "yoga": return "figure.yoga"
        case "pilates": return "figure.pilates"
        case "flexibility": return "figure.flexibility"
        case "martialArts": return "figure.martial.arts"
        default: return "figure.strengthtraining.traditional"
        }
    }
}
