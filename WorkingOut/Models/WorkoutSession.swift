import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID = UUID()
    var date: Date = Date()
    var title: String = ""
    var notes: String?
    @Relationship(deleteRule: .nullify, inverse: \ExerciseLog.workoutSession) var exerciseLogs: [ExerciseLog]?
    
    init(id: UUID = UUID(), date: Date = Date(), notes: String? = nil, title: String? = nil) {
        self.id = id
        self.date = date
        self.notes = notes
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.title = title
        } else {
            self.title = "Gym Session"
        }
    }
} 
