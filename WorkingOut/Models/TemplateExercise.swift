import Foundation
import SwiftData

@Model
final class TemplateExercise {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var sets: Int = 0
    var reps: Int = 0
    var suggestedWeight: Double?
    var weightUnit: String = "lbs"
    var notes: String?
    @Relationship(deleteRule: .nullify) var template: WorkoutTemplate?
    
    init(id: UUID = UUID(), name: String, order: Int, sets: Int, reps: Int, suggestedWeight: Double? = nil, weightUnit: String = "lbs", notes: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.sets = sets
        self.reps = reps
        self.suggestedWeight = suggestedWeight
        self.weightUnit = weightUnit
        self.notes = notes
    }
}

