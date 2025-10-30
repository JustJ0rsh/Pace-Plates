import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

final class WorkoutTemplateService {
    static let shared = WorkoutTemplateService()
    private init() {}
    
    /// Creates a WorkoutTemplate from an AI conversation's structured plan
    /// - Parameters:
    ///   - conversation: The AI conversation containing a structured plan JSON
    ///   - dayIndex: Which day from the first week to use (default: 0, the first day)
    ///   - context: The ModelContext to insert the template into
    /// - Returns: The created WorkoutTemplate, or nil if parsing fails
    func createTemplateFromAIPlan(conversation: AIConversation, dayIndex: Int = 0, context: ModelContext) -> WorkoutTemplate? {
        #if canImport(FoundationModels)
        guard let jsonString = conversation.structuredPlanJSON else {
            print("❌ No structured plan JSON found in conversation")
            return nil
        }
        
        guard let data = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert JSON string to data")
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let plan = try decoder.decode(WorkoutPlan.self, from: data)
            
            // Get the first week
            guard let week = plan.weeks.first else {
                print("❌ No weeks found in plan")
                return nil
            }
            
            // Get the specified day (or first strength day if index out of bounds)
            guard dayIndex < week.days.count else {
                print("❌ Day index \(dayIndex) out of bounds (week has \(week.days.count) days)")
                return nil
            }
            
            let day = week.days[dayIndex]
            
            // Only create templates for workout days (not rest days)
            if day.type == .rest || day.type == .activeRecovery {
                print("⚠️ Selected day is a rest/recovery day, no exercises to template")
                return nil
            }
            
            // Create the template
            let template = WorkoutTemplate(
                title: day.title,
                notes: day.items.first?.notes,
                sourceAIConversationId: conversation.id
            )
            
            context.insert(template)
            
            // Create template exercises from the day's items
            for (index, item) in day.items.enumerated() {
                // Only include strength exercises (with sets/reps)
                guard let sets = item.sets, let reps = item.reps else {
                    continue
                }
                
                // Parse suggested weight if available
                let suggestedWeight: Double?
                let weightUnit: String
                
                if let weightString = item.suggestedWeight, !weightString.isEmpty {
                    // Try to extract number from string like "185 lbs" or "80kg"
                    let components = weightString.components(separatedBy: .whitespaces)
                    suggestedWeight = Double(components.first ?? "")
                    
                    // Determine unit
                    if weightString.lowercased().contains("kg") {
                        weightUnit = "kg"
                    } else {
                        weightUnit = "lbs"
                    }
                } else {
                    suggestedWeight = nil
                    weightUnit = plan.unit.lowercased().contains("kg") ? "kg" : "lbs"
                }
                
                let templateExercise = TemplateExercise(
                    name: item.name,
                    order: index,
                    sets: sets,
                    reps: reps,
                    suggestedWeight: suggestedWeight,
                    weightUnit: weightUnit,
                    notes: item.notes
                )
                
                templateExercise.template = template
                context.insert(templateExercise)
            }
            
            try? context.save()
            print("✅ Created template '\(template.title)' with \(day.items.count) exercises")
            return template
            
        } catch {
            print("❌ Failed to decode workout plan: \(error)")
            return nil
        }
        #else
        print("❌ FoundationModels not available")
        return nil
        #endif
    }
    
    /// Creates a WorkoutSession from a template
    /// - Parameters:
    ///   - template: The template to create a workout from
    ///   - context: The ModelContext to insert the session into
    /// - Returns: The created WorkoutSession
    func createWorkoutFromTemplate(template: WorkoutTemplate, context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(
            date: Date(),
            notes: template.notes,
            title: template.title
        )
        
        context.insert(session)
        
        // Create exercise logs from template exercises
        guard let exercises = template.exercises?.sorted(by: { $0.order < $1.order }) else {
            return session
        }
        
        for templateExercise in exercises {
            // Create all sets for each exercise (not just one!)
            for setNumber in 1...templateExercise.sets {
                let log = ExerciseLog(
                    reps: templateExercise.reps,
                    weight: templateExercise.suggestedWeight ?? 0,
                    weightUnit: templateExercise.weightUnit,
                    setNumber: setNumber,
                    exerciseName: templateExercise.name,
                    exerciseOrder: templateExercise.order
                )
                
                log.workoutSession = session
                context.insert(log)
            }
        }
        
        try? context.save()
        print("✅ Created workout session from template '\(template.title)'")
        return session
    }
    
    /// Gets all available workout days from an AI conversation's plan
    /// - Parameter conversation: The AI conversation containing a structured plan
    /// - Returns: Array of day titles and indices, or empty array if parsing fails
    func getAvailableWorkoutDays(from conversation: AIConversation) -> [(index: Int, title: String, type: String)] {
        #if canImport(FoundationModels)
        guard let jsonString = conversation.structuredPlanJSON,
              let data = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let plan = try decoder.decode(WorkoutPlan.self, from: data)
            
            guard let week = plan.weeks.first else {
                return []
            }
            
            return week.days.enumerated()
                .filter { $0.element.type != .rest && $0.element.type != .activeRecovery }
                .map { (index: $0.offset, title: $0.element.title, type: String(describing: $0.element.type)) }
            
        } catch {
            print("❌ Failed to parse plan: \(error)")
            return []
        }
        #else
        return []
        #endif
    }
}

