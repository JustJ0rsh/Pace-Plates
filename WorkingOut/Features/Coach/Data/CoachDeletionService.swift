import Foundation
import SwiftData

@MainActor
enum CoachDeletionService {
    /// Called within the activity deletion's transaction. Exact stored IDs are
    /// cleared; terminal occurrence status is preserved as recorded history.
    static func detachActual(workoutID: UUID? = nil, runID: UUID? = nil, context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<PlannedSession>()) {
            if let workoutID, row.completedWorkoutSessionID == workoutID { row.completedWorkoutSessionID = nil; row.completionProvenance = "activity_deleted" }
            if let runID, row.completedRunningSessionID == runID { row.completedRunningSessionID = nil; row.completionProvenance = "activity_deleted" }
        }
        guard CoachPersistence.isLocal(context) else { return }
        var removedEvidence = Set<UUID>()
        for execution in try context.fetch(FetchDescriptor<CoachSessionExecution>()) {
            let matchesWorkout = workoutID != nil && execution.workoutSessionID == workoutID
            let matchesRun = runID != nil && execution.runSessionID == runID
            guard matchesWorkout || matchesRun else { continue }
            removedEvidence.insert(execution.id)
            if matchesWorkout { execution.workoutSessionID = nil }
            if matchesRun { execution.runSessionID = nil }
            execution.provenance = "activity_deleted"
            execution.snapshotData = nil
            execution.effort = nil; execution.effortScale = nil
            if execution.statusRaw == "in_progress" {
                execution.statusRaw = "canceled"; execution.endedAt = Date()
                if let id = execution.plannedSessionID,
                   let row = try context.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == id }) {
                    row.status = "skipped"; row.completionProvenance = "activity_deleted"
                }
            }
        }
        for suggestion in try context.fetch(FetchDescriptor<CoachProgressionSuggestion>()) where suggestion.statusRaw == "pending" {
            let evidence = (try? JSONDecoder().decode([UUID].self, from: suggestion.evidenceIDsData)) ?? []
            if !removedEvidence.isDisjoint(with: evidence) { suggestion.statusRaw = "stale" }
        }
    }

    /// Add to the existing Delete All transaction before its single save.
    static func markAllForDeletion(context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<PlannedSession>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<TrainingPlan>()) { context.delete(row) }
        guard CoachPersistence.isLocal(context) else { return }
        for row in try context.fetch(FetchDescriptor<CoachPlanRevision>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachSessionExecution>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachProgressionSuggestion>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachNutritionTargetPeriod>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachNutritionLog>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachWaistMeasurement>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachProgressPhoto>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachPhaseReview>()) { context.delete(row) }
        for row in try context.fetch(FetchDescriptor<CoachCalendarMapping>()) { context.delete(row) }
    }

    /// Called only after the model deletion has saved. Preserve the local store
    /// and ownership marker; only app-owned personal assets/staging are removed.
    static func removeAssetsAfterPurge() throws {
        for directory in [CoachPhotoStore.directory, CoachPhotoStore.stagingDirectory, CoachHistoryArchive.restoreDirectory] {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        }
        try CoachWeightRepository.removeAnchorAfterPurge()
        DataBackupService.removeStaleExportFiles()
    }
}
