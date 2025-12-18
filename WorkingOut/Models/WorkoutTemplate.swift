import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String?
    var createdDate: Date = Date()
    var sourceAIConversationId: UUID?
    var importSourceSessionID: UUID?
    var exerciseCount: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template) var exercises: [TemplateExercise]?
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.generatedTemplate) var sourceSession: WorkoutSession?
    
    // Built-in template properties
    var isBuiltIn: Bool = false
    var experienceLevel: String? = nil // "beginner", "intermediate", "advanced"
    var goal: String? = nil // "full_body_foundation", "muscle_building", etc.
    var difficulty: Int? = nil // 1-5 scale
    var estimatedDuration: Int? = nil // minutes
    var equipment: [String]? = nil // ["barbell", "dumbbells", etc.]
    var muscleGroups: [String]? = nil // ["chest", "back", "legs", etc.]
    var templateDescription: String? = nil // Detailed description
    
    init(id: UUID = UUID(), 
         title: String, 
         notes: String? = nil, 
         createdDate: Date = Date(), 
         sourceAIConversationId: UUID? = nil,
         importSourceSessionID: UUID? = nil,
         exerciseCount: Int = 0,
         isBuiltIn: Bool = false,
         experienceLevel: String? = nil,
         goal: String? = nil,
         difficulty: Int? = nil,
         estimatedDuration: Int? = nil,
         equipment: [String]? = nil,
         muscleGroups: [String]? = nil,
         templateDescription: String? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.createdDate = createdDate
        self.sourceAIConversationId = sourceAIConversationId
        self.importSourceSessionID = importSourceSessionID
        self.exerciseCount = exerciseCount
        self.isBuiltIn = isBuiltIn
        self.experienceLevel = experienceLevel
        self.goal = goal
        self.difficulty = difficulty
        self.estimatedDuration = estimatedDuration
        self.equipment = equipment
        self.muscleGroups = muscleGroups
        self.templateDescription = templateDescription
    }
}
