import Foundation
import SwiftData

@Model
final class ExerciseLog {
    var id: UUID = UUID()
    
    // Strength training fields
    var reps: Int = 0
    var weight: Double = 0
    var weightUnit: String = "lbs"
    
    // Cardio fields (optional)
    var durationSeconds: Int? = nil  // Duration in seconds
    var distance: Double? = nil      // Distance covered
    var distanceUnit: String? = nil  // "mi" or "km"
    var caloriesBurned: Int? = nil   // Optional calories
    var avgHeartRate: Int? = nil     // Optional average heart rate
    var notes: String? = nil         // Optional notes for the set
    
    // Common fields
    var setNumber: Int = 0
    var exerciseOrder: Int = 0  // Preserves the order exercises should be displayed in
    // Snapshot of the exercise's display name at the time of logging
    var exerciseName: String?
    var exerciseType: String? = "strength"  // "strength" or "cardio"
    
    var isCompleted: Bool = false // Track if the set was completed
    
    @Relationship(deleteRule: .nullify) var exerciseDefinition: ExerciseDefinition?
    @Relationship(deleteRule: .nullify) var workoutSession: WorkoutSession?
    
    init(id: UUID = UUID(), 
         reps: Int = 0, 
         weight: Double = 0, 
         weightUnit: String = "lbs", 
         setNumber: Int = 0, 
         exerciseName: String? = nil, 
         exerciseOrder: Int = 0,
         exerciseType: String? = "strength",
         durationSeconds: Int? = nil,
         distance: Double? = nil,
         distanceUnit: String? = nil,
         caloriesBurned: Int? = nil,
         avgHeartRate: Int? = nil,
         notes: String? = nil,
         isCompleted: Bool = false) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.weightUnit = weightUnit
        self.setNumber = setNumber
        self.exerciseName = exerciseName
        self.exerciseOrder = exerciseOrder
        self.exerciseType = exerciseType
        self.durationSeconds = durationSeconds
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.caloriesBurned = caloriesBurned
        self.avgHeartRate = avgHeartRate
        self.notes = notes
        self.isCompleted = isCompleted
    }
    
    // Helper computed properties
    var isCardio: Bool {
        exerciseType == "cardio"
    }
    
    var formattedDuration: String? {
        guard let seconds = durationSeconds else { return nil }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        } else {
            return "\(remainingSeconds)s"
        }
    }
    
    var calculatedPace: String? {
        guard let distance = distance, distance > 0,
              let seconds = durationSeconds, seconds > 0,
              let unit = distanceUnit else { return nil }
        
        let paceMinPerUnit = (Double(seconds) / 60.0) / distance
        let mins = Int(paceMinPerUnit)
        let secs = Int((paceMinPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d/%@", mins, secs, unit)
    }
} 
