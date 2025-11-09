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
            // Run idempotent rename/migration pass for advanced template names
            try? await renameAdvancedTemplateTitlesIfNeeded(context: context)
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
        // Apply any post-seed migrations (e.g., title renames)
        try? await renameAdvancedTemplateTitlesIfNeeded(context: context)
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

// MARK: - Lightweight migrations
extension TemplateSeeder {
    /// Rename advanced template titles to clearer names. Safe to call multiple times.
    func renameAdvancedTemplateTitlesIfNeeded(context: ModelContext) async throws {
        let mapping: [String: String] = [
            "Advanced Powerlifting - Sheiko Heavy Squat": "Powerlifting (Advanced) – Sheiko Heavy Squat Day",
            "Advanced Powerlifting - Smolov Squat Cycle": "Powerlifting (Advanced) – Smolov Squat Cycle",
            "Advanced Powerlifting - Westside Max Effort Squat": "Powerlifting (Advanced) – Westside Max Effort Squat",
            "Advanced Powerlifting - Westside Speed Bench": "Powerlifting (Advanced) – Westside Speed Bench",
            "Advanced Powerlifting - Bulgarian Daily Max Squat": "Powerlifting (Advanced) – Bulgarian Daily Max Squat"
        ]
        if mapping.isEmpty { return }
        let fetch = FetchDescriptor<WorkoutTemplate>(predicate: #Predicate { $0.isBuiltIn == true && $0.experienceLevel == "advanced" })
        let items = (try? context.fetch(fetch)) ?? []
        var changed = false
        for t in items {
            if let newName = mapping[t.title], t.title != newName {
                t.title = newName
                changed = true
            }
        }
        if changed { try? context.save() }
    }
}
