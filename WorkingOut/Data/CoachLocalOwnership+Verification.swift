import Foundation
import SwiftData
import CryptoKit

extension CoachLocalOwnership {
    /// Compare value snapshots and relationships in addition to row counts/IDs.
    /// Fetching through a fresh context detects concurrent edits in other contexts.
    @MainActor
    static func snapshotDigest(_ context: ModelContext) throws -> String {
        let fresh = ModelContext(context.container)
        var snapshot = try DataBackupService.capture(context: fresh)
        snapshot.exportedAt = Date(timeIntervalSince1970: 0)
        snapshot.exerciseDefinitions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.workoutSessions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.exerciseLogs.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.runningSessions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.weightEntries.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.runningPlans?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.runningPlanSessions?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.aiConversations?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.workoutTemplates?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.templateExercises?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.healthWorkoutInboxItems?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.cardioWorkoutInboxItems?.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.trainingPlans.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.plannedSessions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.revisions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.executions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.suggestions.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.targets.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.nutrition.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.recovery.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.waist.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.photos.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.phaseReviews.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.coach?.calendarMappings.sort { $0.id.uuidString < $1.id.uuidString }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(snapshot)).map { String(format: "%02x", $0) }.joined()
    }
}
