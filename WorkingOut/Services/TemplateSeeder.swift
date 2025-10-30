import Foundation
import SwiftData

/// Service to seed built-in workout templates into the database
@MainActor
class TemplateSeeder {
    static let shared = TemplateSeeder()
    
    private init() {}
    
    /// Check if built-in templates have been seeded
    func hasSeeded(context: ModelContext) -> Bool {
        UserDefaults.standard.bool(forKey: "hasSeededBuiltInTemplates_v1")
    }
    
    /// Seed all built-in templates into the database
    func seedBuiltInTemplates(context: ModelContext) async throws {
        // Check if already seeded
        if hasSeeded(context: context) {
            print("✅ Built-in templates already seeded")
            return
        }
        
        print("🌱 Seeding built-in workout templates...")
        
        let allBuiltInTemplates = BuiltInTemplateLibrary.allTemplates
        var count = 0
        
        for templateData in allBuiltInTemplates {
            // Create the template
            let template = WorkoutTemplate(
                title: templateData.title,
                notes: templateData.description,
                createdDate: Date(),
                sourceAIConversationId: nil,
                isBuiltIn: true,
                experienceLevel: templateData.experienceLevel,
                goal: templateData.goal,
                difficulty: templateData.difficulty,
                estimatedDuration: templateData.estimatedDuration,
                equipment: templateData.equipment,
                muscleGroups: templateData.muscleGroups,
                templateDescription: templateData.description
            )
            
            context.insert(template)
            
            // Create exercises for this template
            for exerciseData in templateData.exercises {
                let exercise = TemplateExercise(
                    name: exerciseData.name,
                    order: exerciseData.order,
                    sets: exerciseData.sets,
                    reps: exerciseData.reps,
                    suggestedWeight: exerciseData.suggestedWeight,
                    weightUnit: exerciseData.weightUnit,
                    notes: exerciseData.notes
                )
                
                exercise.template = template
                context.insert(exercise)
            }
            
            count += 1
        }
        
        // Save all templates
        try context.save()
        
        // Mark as seeded
        UserDefaults.standard.set(true, forKey: "hasSeededBuiltInTemplates_v1")
        
        print("✅ Successfully seeded \(count) built-in workout templates")
    }
    
    /// Force reseed (for development/testing)
    func forceSeed(context: ModelContext) async throws {
        // Delete all built-in templates
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate<WorkoutTemplate> { $0.isBuiltIn == true }
        )
        
        let templates = try context.fetch(descriptor)
        for template in templates {
            context.delete(template)
        }
        
        try context.save()
        
        // Reset seeded flag
        UserDefaults.standard.set(false, forKey: "hasSeededBuiltInTemplates_v1")
        
        // Reseed
        try await seedBuiltInTemplates(context: context)
    }
}

