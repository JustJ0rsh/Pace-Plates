import Foundation
import SwiftData
import CoreLocation

@Model
final class RunningSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var distance: Double = 0
    var distanceUnit: String = "km"
    var duration: TimeInterval = 0
    // Calories (kcal) if known (e.g., imported from Health)
    var calories: Double? = nil
    var notes: String?
    var locations: Data = Data() // Stores encoded [CLLocationCoordinate2D]
    // If imported from Health, store the HKWorkout UUID to prevent duplicates and allow deletions
    var healthWorkoutUUID: String? = nil
    
    init(id: UUID = UUID(), date: Date = Date(), distance: Double, distanceUnit: String = "km", duration: TimeInterval, calories: Double? = nil, notes: String? = nil, locations: Data? = nil, healthWorkoutUUID: String? = nil) {
        self.id = id
        self.date = date
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.duration = duration
        self.calories = calories
        self.notes = notes
        self.locations = locations ?? Data()
        self.healthWorkoutUUID = healthWorkoutUUID
    }
} 
