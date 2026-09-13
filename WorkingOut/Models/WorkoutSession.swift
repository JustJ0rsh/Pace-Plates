import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    // Old records retain their historical meaning even when set checkboxes are false.
    var executionStatusRaw: String = "legacy_recorded"
    var plannedSessionID: UUID? = nil
    var coachExecutionID: UUID? = nil
    var endedAt: Date? = nil
    var completionProvenance: String? = nil

    var countsAsPerformedActivity: Bool {
        executionStatusRaw == "legacy_recorded"
            || (["in_progress", "completed", "partial"].contains(executionStatusRaw)
                && ((exerciseLogs ?? []).contains(where: { $0.isCompleted }) || (healthDuration ?? 0) > 0))
    }

    var date: Date = Date()
    var title: String = ""
    var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.workoutSession) var exerciseLogs: [ExerciseLog]?
    @Relationship(deleteRule: .nullify) var generatedTemplate: WorkoutTemplate?
    
    var shouldSaveAsTemplate: Bool = false
    var sourceTemplateID: UUID? // ID of the template this session was created from
    var isSampleData: Bool = false

    // Wearable link: set when this session is linked to an imported Health workout
    var healthWorkoutUUID: String? = nil
    var healthDuration: TimeInterval? = nil
    var healthCalories: Double? = nil
    var healthAvgHeartRate: Double? = nil
    var healthSourceName: String? = nil
    var healthActivityType: String? = nil
    
    init(id: UUID = UUID(), date: Date = Date(), notes: String? = nil, title: String? = nil, shouldSaveAsTemplate: Bool = false, sourceTemplateID: UUID? = nil, executionStatus: CoachExecutionStatus = .inProgress) {
        self.id = id
        self.executionStatusRaw = executionStatus.rawValue
        self.date = date
        self.notes = notes
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.title = title
        } else {
            self.title = "Gym Session"
        }
        self.shouldSaveAsTemplate = shouldSaveAsTemplate
        self.sourceTemplateID = sourceTemplateID
    }
} 
