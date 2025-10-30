import Foundation
import SwiftData

@Model
final class ExerciseDefinition {
    var id: UUID = UUID()
    var name: String = ""
    var muscleGroup: String = ""
    var isUserDefined: Bool = false
    @Relationship(deleteRule: .nullify, inverse: \ExerciseLog.exerciseDefinition) var logs: [ExerciseLog]?
    
    init(id: UUID = UUID(), name: String, muscleGroup: String, isUserDefined: Bool = false) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.isUserDefined = isUserDefined
    }
} 
