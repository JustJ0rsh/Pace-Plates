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
    
    // Activity type: "running", "walking", or "hiking"
    var activityType: String = "running"
    
    // Heart Rate metrics
    var avgHeartRate: Double? = nil // bpm
    var maxHeartRate: Double? = nil // bpm
    var minHeartRate: Double? = nil // bpm
    
    // Running dynamics
    var avgCadence: Double? = nil // steps per minute
    var maxCadence: Double? = nil // steps per minute
    var avgStrideLength: Double? = nil // meters
    var verticalOscillation: Double? = nil // centimeters
    var groundContactTime: Double? = nil // milliseconds
    
    // Elevation data
    var totalAscent: Double? = nil // meters
    var totalDescent: Double? = nil // meters
    var minElevation: Double? = nil // meters
    var maxElevation: Double? = nil // meters
    
    // Power metrics (for advanced runners with power meters)
    var avgPower: Double? = nil // watts
    var maxPower: Double? = nil // watts
    
    init(id: UUID = UUID(), 
         date: Date = Date(), 
         distance: Double, 
         distanceUnit: String = "km", 
         duration: TimeInterval, 
         calories: Double? = nil, 
         notes: String? = nil, 
         locations: Data? = nil, 
         healthWorkoutUUID: String? = nil, 
         activityType: String = "running",
         avgHeartRate: Double? = nil,
         maxHeartRate: Double? = nil,
         minHeartRate: Double? = nil,
         avgCadence: Double? = nil,
         maxCadence: Double? = nil,
         avgStrideLength: Double? = nil,
         verticalOscillation: Double? = nil,
         groundContactTime: Double? = nil,
         totalAscent: Double? = nil,
         totalDescent: Double? = nil,
         minElevation: Double? = nil,
         maxElevation: Double? = nil,
         avgPower: Double? = nil,
         maxPower: Double? = nil) {
        self.id = id
        self.date = date
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.duration = duration
        self.calories = calories
        self.notes = notes
        self.locations = locations ?? Data()
        self.healthWorkoutUUID = healthWorkoutUUID
        self.activityType = activityType
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.minHeartRate = minHeartRate
        self.avgCadence = avgCadence
        self.maxCadence = maxCadence
        self.avgStrideLength = avgStrideLength
        self.verticalOscillation = verticalOscillation
        self.groundContactTime = groundContactTime
        self.totalAscent = totalAscent
        self.totalDescent = totalDescent
        self.minElevation = minElevation
        self.maxElevation = maxElevation
        self.avgPower = avgPower
        self.maxPower = maxPower
    }
} 
