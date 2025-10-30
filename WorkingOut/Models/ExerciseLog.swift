import Foundation
import SwiftData

@Model
final class ExerciseLog {
    var id: UUID = UUID()
    var reps: Int = 0
    var weight: Double = 0
    var weightUnit: String = "lbs"
    var setNumber: Int = 0
    var exerciseOrder: Int = 0  // Preserves the order exercises should be displayed in
    // Snapshot of the exercise's display name at the time of logging
    var exerciseName: String?
    @Relationship(deleteRule: .nullify) var exerciseDefinition: ExerciseDefinition?
    @Relationship(deleteRule: .nullify) var workoutSession: WorkoutSession?
    
    init(id: UUID = UUID(), reps: Int, weight: Double, weightUnit: String = "lbs", setNumber: Int, exerciseName: String? = nil, exerciseOrder: Int = 0) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.setNumber = setNumber
        self.exerciseName = exerciseName
        self.exerciseOrder = exerciseOrder
    }
} 
