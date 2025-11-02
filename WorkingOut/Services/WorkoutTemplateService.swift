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
            // Try markdown parsing if no structured JSON
            return getAvailableWorkoutDaysFromMarkdown(conversation: conversation)
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
            return getAvailableWorkoutDaysFromMarkdown(conversation: conversation)
        }
        #else
        return []
        #endif
    }
    
    /// Creates templates from markdown-based AI plan (creates a template for each workout day)
    /// - Parameters:
    ///   - conversation: The AI conversation containing markdown plan
    ///   - context: The ModelContext to insert templates into
    /// - Returns: Array of created templates
    func createTemplatesFromMarkdownPlan(conversation: AIConversation, context: ModelContext) -> [WorkoutTemplate] {
        let workoutDays = parseWorkoutDaysFromMarkdown(text: conversation.response)
        var templates: [WorkoutTemplate] = []
        
        for (_, day) in workoutDays.enumerated() {
            // Skip rest days
            let isRest = day.title.lowercased().contains("rest") || 
                         day.title.lowercased().contains("recovery") ||
                         day.details.lowercased().contains("rest day")
            
            if isRest { continue }
            
            // Create template
            let template = WorkoutTemplate(
                title: day.title,
                notes: day.details,
                sourceAIConversationId: conversation.id,
                isBuiltIn: false
            )
            
            context.insert(template)
            templates.append(template)
            
            // Parse exercises from markdown details
            let exercises = parseExercisesFromMarkdown(details: day.details, weightUnit: "lbs")
            
            for (exerciseIndex, exercise) in exercises.enumerated() {
                let templateExercise = TemplateExercise(
                    name: exercise.name,
                    order: exerciseIndex,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    suggestedWeight: exercise.weight,
                    weightUnit: exercise.weightUnit,
                    notes: exercise.notes
                )
                
                templateExercise.template = template
                context.insert(templateExercise)
            }
            
            print("✅ Created template '\(template.title)' from markdown")
        }
        
        try? context.save()
        return templates
    }
    
    // MARK: - Private Markdown Parsing Helpers
    
    private func getAvailableWorkoutDaysFromMarkdown(conversation: AIConversation) -> [(index: Int, title: String, type: String)] {
        let workoutDays = parseWorkoutDaysFromMarkdown(text: conversation.response)
        return workoutDays.enumerated()
            .filter { !$0.element.title.lowercased().contains("rest") && !$0.element.title.lowercased().contains("recovery") }
            .map { (index: $0.offset, title: $0.element.title, type: "workout") }
    }
    
    private func parseWorkoutDaysFromMarkdown(text: String) -> [(title: String, details: String)] {
        var workoutDays: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines)
        var currentDay: String?
        var currentDetails: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            // Check for day headers
            if let dayTitle = extractDayTitleFromLine(line: trimmed) {
                // Save previous day
                if let day = currentDay, !currentDetails.isEmpty {
                    workoutDays.append((day, currentDetails.joined(separator: "\n")))
                }
                currentDay = dayTitle
                currentDetails = []
            } else if currentDay != nil {
                // Skip headers
                if !trimmed.hasPrefix("#") && !trimmed.lowercased().contains("training plan") {
                    currentDetails.append(trimmed)
                }
            }
        }
        
        // Save last day
        if let day = currentDay, !currentDetails.isEmpty {
            workoutDays.append((day, currentDetails.joined(separator: "\n")))
        }
        
        return workoutDays
    }
    
    private func extractDayTitleFromLine(line: String) -> String? {
        // Match patterns like "#### Day 1: Upper Body" or "### Monday: Strength"
        let patterns = [
            "^#{1,6}\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*:?\\s*(.*)$",
            "^#{1,6}\\s*\\*{0,2}\\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\\s*\\*{0,2}\\s*:(.*)$"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 {
                    if let dayRange = Range(match.range(at: 1), in: line) {
                        let day = String(line[dayRange])
                        let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                        let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                        return title.isEmpty ? day : "\(day): \(title)"
                    }
                }
            }
        }
        return nil
    }
    
    private struct ParsedExercise {
        let name: String
        let sets: Int
        let reps: Int
        let weight: Double?
        let weightUnit: String
        let notes: String?
    }
    
    private func parseExercisesFromMarkdown(details: String, weightUnit: String) -> [ParsedExercise] {
        var exercises: [ParsedExercise] = []
        let lines = details.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "- ", with: "")
                .replacingOccurrences(of: "• ", with: "")
            
            if trimmed.isEmpty { continue }
            
            // Skip summary lines like "Compound Lifts:" or "Accessory Work:"
            if trimmed.hasSuffix(":") && !trimmed.contains("sets") { continue }
            
            // Try to parse exercise with sets/reps
            // Patterns like "Bench Press - 4 sets of 6 reps" or "Squats: 3x8"
            if let exercise = parseExerciseLine(line: trimmed, defaultWeightUnit: weightUnit) {
                exercises.append(exercise)
            }
        }
        
        return exercises
    }
    
    private func parseExerciseLine(line: String, defaultWeightUnit: String) -> ParsedExercise? {
        // Pattern 1: "Exercise Name - 4 sets of 6 reps (185 lbs)"
        let pattern1 = "^([^-:]+)[-:]\\s*(\\d+)\\s*sets\\s*of\\s*(\\d+)\\s*reps?(?:\\s*\\(?([0-9.]+)\\s*(lbs|kg)?\\)?)?(.*)$"
        
        // Pattern 2: "Exercise Name: 4x6 @ 185 lbs"
        let pattern2 = "^([^-:]+)[-:]\\s*(\\d+)\\s*[x×]\\s*(\\d+)(?:\\s*@\\s*([0-9.]+)\\s*(lbs|kg)?)?(.*)$"
        
        for pattern in [pattern1, pattern2] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range) {
                    guard let nameRange = Range(match.range(at: 1), in: line),
                          let setsRange = Range(match.range(at: 2), in: line),
                          let repsRange = Range(match.range(at: 3), in: line) else {
                        continue
                    }
                    
                    let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                    let sets = Int(String(line[setsRange])) ?? 3
                    let reps = Int(String(line[repsRange])) ?? 10
                    
                    var weight: Double? = nil
                    var unit = defaultWeightUnit
                    
                    if match.numberOfRanges >= 5, let weightRange = Range(match.range(at: 4), in: line) {
                        weight = Double(String(line[weightRange]))
                    }
                    
                    if match.numberOfRanges >= 6, let unitRange = Range(match.range(at: 5), in: line) {
                        unit = String(line[unitRange])
                    }
                    
                    var notes: String? = nil
                    if match.numberOfRanges >= 7, let notesRange = Range(match.range(at: 6), in: line) {
                        let notesText = String(line[notesRange]).trimmingCharacters(in: .whitespaces)
                        if !notesText.isEmpty {
                            notes = notesText
                        }
                    }
                    
                    return ParsedExercise(name: name, sets: sets, reps: reps, weight: weight, weightUnit: unit, notes: notes)
                }
            }
        }
        
        return nil
    }
}

