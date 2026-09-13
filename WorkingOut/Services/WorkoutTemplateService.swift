import Foundation
import SwiftData
import CryptoKit

#if canImport(FoundationModels)
import FoundationModels
#endif

final class WorkoutTemplateService {
    static let shared = WorkoutTemplateService()
    private init() {}

    // MARK: - AI Plan Template Creation (Idempotent)

    func createTemplatesFromPlan(conversation: AIConversation, context: ModelContext) -> [WorkoutTemplate] {
        #if canImport(FoundationModels)
        if let json = conversation.structuredPlanJSON,
           let plan = decodePlan(jsonString: json)
        {
            return createTemplatesFromStructuredPlan(plan: plan, conversation: conversation, context: context)
        }
        #endif
        return createTemplatesFromMarkdownPlan(conversation: conversation, context: context, includeRestDays: true)
    }

    #if canImport(FoundationModels)
    private func createTemplatesFromStructuredPlan(plan: WorkoutPlan, conversation: AIConversation, context: ModelContext) -> [WorkoutTemplate] {
        guard !plan.weeks.isEmpty else { return [] }

        let planHash = stablePlanHash(structuredPlanJSON: conversation.structuredPlanJSON, markdown: conversation.response)
        let planTitle = plan.title

        var result: [WorkoutTemplate] = []
        var globalDayIndex = 0
        for week in plan.weeks {
            for day in week.days {
                let dayIndex = globalDayIndex
                let title = prefixedDayTitle(day.title, dayIndex: dayIndex)
                let existing = findExistingTemplate(planHash: planHash, dayIndex: dayIndex, context: context)

                let template = existing ?? WorkoutTemplate(
                    title: title,
                    notes: nil,
                    sourceAIConversationId: conversation.id,
                    aiPlanHash: planHash,
                    aiPlanTitle: planTitle,
                    aiWeekTitle: week.title,
                    aiDayIndex: dayIndex,
                    aiDayType: day.type.rawValue,
                    aiDayTitle: day.title,
                    isBuiltIn: false
                )

                template.title = title
                template.sourceAIConversationId = conversation.id
                template.aiPlanHash = planHash
                template.aiPlanTitle = planTitle
                template.aiWeekTitle = week.title
                template.aiDayIndex = dayIndex
                template.aiDayType = day.type.rawValue
                template.aiDayTitle = day.title
                template.isBuiltIn = false
                template.templateDescription = templateDescription(for: day)
                template.notes = notesSummary(for: day)

                if existing == nil { context.insert(template) }
                deleteTemplateExercises(template, context: context)

                var createdExercises = 0
                for (index, item) in day.items.enumerated() {
                    let mapped = mapItemToTemplateExercise(item, order: index, defaultWeightUnit: plan.unit)
                    let templateExercise = TemplateExercise(
                        name: mapped.name,
                        order: mapped.order,
                        sets: mapped.sets,
                        reps: mapped.reps,
                        suggestedWeight: mapped.suggestedWeight,
                        weightUnit: mapped.weightUnit,
                        notes: mapped.notes
                    )
                    templateExercise.template = template
                    context.insert(templateExercise)
                    if mapped.countsTowardExerciseCount { createdExercises += 1 }
                }

                template.exerciseCount = createdExercises
                result.append(template)
                globalDayIndex += 1
            }
        }

        _ = PersistenceSave.commit(context, action: "save changes")
        return result
    }
    #endif

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
            
            let planHash = stablePlanHash(structuredPlanJSON: jsonString, markdown: conversation.response)
            let planTitle = plan.title
            let title = prefixedDayTitle(day.title, dayIndex: dayIndex)

            // Idempotent: update an existing template for this plan/day if present.
            let existing = findExistingTemplate(planHash: planHash, dayIndex: dayIndex, context: context)

            let template = existing ?? WorkoutTemplate(
                title: title,
                notes: nil,
                sourceAIConversationId: conversation.id,
                aiPlanHash: planHash,
                aiPlanTitle: planTitle,
                aiWeekTitle: plan.weeks.first?.title,
                aiDayIndex: dayIndex,
                aiDayType: day.type.rawValue,
                aiDayTitle: day.title,
                isBuiltIn: false
            )

            template.title = title
            template.aiPlanHash = planHash
            template.aiPlanTitle = planTitle
            template.aiWeekTitle = plan.weeks.first?.title
            template.aiDayIndex = dayIndex
            template.aiDayType = day.type.rawValue
            template.aiDayTitle = day.title
            template.isBuiltIn = false

            // Provide a useful summary even for rest/recovery/yoga-style days.
            template.templateDescription = templateDescription(for: day)
            template.notes = notesSummary(for: day)
            
            if existing == nil { context.insert(template) }
            deleteTemplateExercises(template, context: context)
            
            // Create template exercises from the day's items
            var createdExercises = 0
            for (index, item) in day.items.enumerated() {
                let mapped = mapItemToTemplateExercise(item, order: index, defaultWeightUnit: plan.unit)
                let templateExercise = TemplateExercise(
                    name: mapped.name,
                    order: mapped.order,
                    sets: mapped.sets,
                    reps: mapped.reps,
                    suggestedWeight: mapped.suggestedWeight,
                    weightUnit: mapped.weightUnit,
                    notes: mapped.notes
                )
                
                templateExercise.template = template
                context.insert(templateExercise)
                if mapped.countsTowardExerciseCount { createdExercises += 1 }
            }
            
            template.exerciseCount = createdExercises
            _ = PersistenceSave.commit(context, action: "save changes")
            print("✅ Created template '\(template.title)' with \(createdExercises) exercises")
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
    
    /// Creates a WorkoutTemplate from a completed WorkoutSession
    /// - Parameters:
    ///   - session: The workout session to template-ize
    ///   - context: The ModelContext
    /// - Returns: The created WorkoutTemplate
    func createTemplateFromWorkout(session: WorkoutSession, context: ModelContext) -> WorkoutTemplate {
        let template = WorkoutTemplate(
            title: session.title.isEmpty ? "Custom Workout" : session.title,
            notes: session.notes,
            isBuiltIn: false,
            experienceLevel: "Custom",
            goal: "Custom",
            difficulty: 3, // Default to Medium
            estimatedDuration: nil,
            equipment: [],
            muscleGroups: [],
            templateDescription: "Created from workout on \(session.date.formatted(date: .abbreviated, time: .omitted))"
        )
        
        context.insert(template)
        
        let logs = session.exerciseLogs ?? []
        // Group by exercise name
        let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Exercise" }
        
        // Sort groups by the minimum exerciseOrder to preserve workout order
        let sortedNames = groups.keys.sorted { name1, name2 in
            let order1 = groups[name1]?.map { $0.exerciseOrder }.min() ?? Int.min
            let order2 = groups[name2]?.map { $0.exerciseOrder }.min() ?? Int.min
            return order1 < order2 // Lower order first
        }
        
        for (index, name) in sortedNames.enumerated() {
            guard let exerciseLogs = groups[name] else { continue }
            let values = templateValues(from: exerciseLogs)
            
            let templateExercise = TemplateExercise(
                name: name,
                order: index,
                sets: values.sets,
                reps: values.reps,
                suggestedWeight: values.weight,
                weightUnit: values.weightUnit,
                notes: values.notes
            )
            
            templateExercise.template = template
            context.insert(templateExercise)
        }
        
        template.exerciseCount = sortedNames.count
        _ = PersistenceSave.commit(context, action: "save changes")
        print("✅ Created custom template '\(template.title)'")
        return template
    }
    
    /// Updates an existing WorkoutTemplate from a WorkoutSession
    func updateTemplate(template: WorkoutTemplate, from session: WorkoutSession, context: ModelContext) {
        template.title = session.title.isEmpty ? "Custom Workout" : session.title
        template.notes = session.notes
        template.templateDescription = "Updated from workout on \(session.date.formatted(date: .abbreviated, time: .omitted))"
        
        // Clear existing exercises
        if let existing = template.exercises {
            for ex in existing {
                context.delete(ex)
            }
        }
        
        // Re-add exercises from session
        let logs = session.exerciseLogs ?? []
        let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Exercise" }
        
        let sortedNames = groups.keys.sorted { name1, name2 in
            let order1 = groups[name1]?.map { $0.exerciseOrder }.min() ?? Int.min
            let order2 = groups[name2]?.map { $0.exerciseOrder }.min() ?? Int.min
            return order1 < order2
        }
        
        for (index, name) in sortedNames.enumerated() {
            guard let exerciseLogs = groups[name] else { continue }
            let values = templateValues(from: exerciseLogs)
            
            let templateExercise = TemplateExercise(
                name: name,
                order: index,
                sets: values.sets,
                reps: values.reps,
                suggestedWeight: values.weight,
                weightUnit: values.weightUnit,
                notes: values.notes
            )
            
            templateExercise.template = template
            context.insert(templateExercise)
        }
        
        template.exerciseCount = sortedNames.count
        _ = PersistenceSave.commit(context, action: "save changes")
        print("✅ Updated custom template '\(template.title)'")
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
            title: template.title,
            sourceTemplateID: template.id
        )
        
        session.executionStatusRaw = "in_progress"
        context.insert(session)
        
        // Create exercise logs from template exercises
        let exercises = template.exercises?.sorted(by: { $0.order < $1.order }) ?? []
        
        for templateExercise in exercises {
            // Check if notes contain detailed per-set data (from imported workouts)
            let perSetData = parsePerSetData(from: templateExercise.notes)
            
            // Detect exercise type (cardio if notes contain duration/distance data)
            let isCardio = perSetData.first?.durationSeconds != nil
                || perSetData.first?.distance != nil
                || perSetData.first?.caloriesBurned != nil
                || perSetData.first?.avgHeartRate != nil
            
            if !perSetData.isEmpty {
                // Use the detailed per-set data
                for (index, setData) in perSetData.enumerated() {
                    let log = ExerciseLog(
                        reps: setData.reps,
                        weight: setData.weight,
                        weightUnit: setData.weightUnit,
                        setNumber: index + 1,
                        exerciseName: templateExercise.name,
                        exerciseOrder: templateExercise.order,
                        exerciseType: isCardio ? "cardio" : "strength",
                        durationSeconds: setData.durationSeconds,
                        distance: setData.distance,
                        distanceUnit: setData.distanceUnit,
                        caloriesBurned: setData.caloriesBurned,
                        avgHeartRate: setData.avgHeartRate,
                        notes: setData.notes
                    )
                    
                    log.workoutSession = session
                    context.insert(log)
                }
            } else {
                // Use the template's suggested values (standard template behavior)
                guard templateExercise.sets > 0 else { continue }
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
        }
        
        _ = PersistenceSave.commit(context, action: "save changes")
        print("✅ Created workout session from template '\(template.title)'")
        return session
    }
    
    /// Parses per-set data from notes string
    /// Format: "Set 1: 34 reps @ 110.0 lbs\nSet 2: 20 reps @ 160.0 lbs"
    private func parsePerSetData(from notes: String?) -> [(reps: Int, weight: Double, weightUnit: String, durationSeconds: Int?, distance: Double?, distanceUnit: String?, caloriesBurned: Int?, avgHeartRate: Int?, notes: String?)] {
        guard let notes = notes, !notes.isEmpty else { return [] }
        
        var result: [(Int, Double, String, Int?, Double?, String?, Int?, Int?, String?)] = []
        let lines = notes.components(separatedBy: .newlines)
        
        for line in lines {
            // Parse strength format: "Set 1: 34 reps @ 110.0 lbs | optional notes"
            if let match = try? NSRegularExpression(pattern: "^Set\\s+(\\d+):\\s+(\\d+)\\s+reps\\s+@\\s+([0-9.]+)\\s+([^\\s|]+)(?:\\s+\\|\\s*(.*))?$", options: [])
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let repsRange = Range(match.range(at: 2), in: line),
                   let weightRange = Range(match.range(at: 3), in: line),
                   let unitRange = Range(match.range(at: 4), in: line) {
                    
                    let reps = Int(String(line[repsRange])) ?? 0
                    let weight = Double(String(line[weightRange])) ?? 0
                    let unit = String(line[unitRange])
                    let setNotes = capturedString(at: 5, from: match, in: line)
                    
                    result.append((reps, weight, unit, nil, nil, nil, nil, nil, setNotes))
                }
            }
            // Parse cardio format:
            // "Set 1: 30:00 5.0 mi ; calories=250 ; avgHR=145 | optional notes"
            // Metric annotations are optional, so existing template notes still parse.
            else if let match = try? NSRegularExpression(pattern: "^Set\\s+(\\d+):\\s+(\\d+):(\\d+)(?:\\s+([0-9.]+)(?:\\s+([^\\s;|]+))?)?(?:\\s*;\\s*calories=(\\d+))?(?:\\s*;\\s*avgHR=(\\d+))?(?:\\s+\\|\\s*(.*))?$", options: [])
                .firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                if let minRange = Range(match.range(at: 2), in: line),
                   let secRange = Range(match.range(at: 3), in: line) {
                    
                    let minutes = Int(String(line[minRange])) ?? 0
                    let seconds = Int(String(line[secRange])) ?? 0
                    let totalSeconds = minutes * 60 + seconds
                    
                    var distance: Double? = nil
                    var distanceUnit: String? = nil
                    
                    if match.numberOfRanges >= 6,
                       let distRange = Range(match.range(at: 4), in: line),
                       let unitRange = Range(match.range(at: 5), in: line) {
                        distance = Double(String(line[distRange]))
                        distanceUnit = String(line[unitRange])
                    } else if let distRange = Range(match.range(at: 4), in: line) {
                        distance = Double(String(line[distRange]))
                    }
                    
                    let calories = capturedInt(at: 6, from: match, in: line)
                    let avgHeartRate = capturedInt(at: 7, from: match, in: line)
                    let setNotes = capturedString(at: 8, from: match, in: line)
                    result.append((0, 0, "lbs", totalSeconds, distance, distanceUnit, calories, avgHeartRate, setNotes))
                }
            }
        }
        
        return result
    }

    private func capturedString(
        at index: Int,
        from match: NSTextCheckingResult,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source)
        else {
            return nil
        }
        let value = String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func capturedInt(
        at index: Int,
        from match: NSTextCheckingResult,
        in source: String
    ) -> Int? {
        capturedString(at: index, from: match, in: source).flatMap(Int.init)
    }

    private func templateValues(
        from logs: [ExerciseLog]
    ) -> (sets: Int, reps: Int, weight: Double, weightUnit: String, notes: String?) {
        let sortedLogs = logs.sorted {
            if $0.setNumber != $1.setNumber { return $0.setNumber < $1.setNumber }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let firstLog = sortedLogs.first else {
            return (0, 0, 0, "lbs", nil)
        }

        let lines = sortedLogs.map { log -> String in
            let isCardio = log.isCardio || log.durationSeconds != nil || log.distance != nil
            let base: String
            if isCardio {
                let totalSeconds = max(log.durationSeconds ?? 0, 0)
                let minutes = totalSeconds / 60
                let seconds = totalSeconds % 60
                var cardio = "Set \(log.setNumber): \(minutes):\(String(format: "%02d", seconds))"
                if let distance = log.distance {
                    cardio += " \(String(format: "%.6g", distance))"
                    if let unit = log.distanceUnit, !unit.isEmpty {
                        cardio += " \(unit)"
                    }
                }
                if let calories = log.caloriesBurned {
                    cardio += " ; calories=\(calories)"
                }
                if let avgHeartRate = log.avgHeartRate {
                    cardio += " ; avgHR=\(avgHeartRate)"
                }
                base = cardio
            } else {
                base = "Set \(log.setNumber): \(log.effectiveReps) reps @ \(String(format: "%.6g", log.weight)) \(log.weightUnit)"
            }

            guard let notes = log.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !notes.isEmpty
            else {
                return base
            }
            return "\(base) | \(notes.replacingOccurrences(of: "\n", with: " "))"
        }

        return (
            sortedLogs.count,
            firstLog.effectiveReps,
            firstLog.weight,
            firstLog.weightUnit,
            lines.joined(separator: "\n")
        )
    }
    
    /// Creates templates from markdown-based AI plan (creates a template for each workout day)
    /// - Parameters:
    ///   - conversation: The AI conversation containing markdown plan
    ///   - context: The ModelContext to insert templates into
    /// - Returns: Array of created templates
    func createTemplatesFromMarkdownPlan(conversation: AIConversation, context: ModelContext) -> [WorkoutTemplate] {
        createTemplatesFromMarkdownPlan(conversation: conversation, context: context, includeRestDays: false)
    }

    func createTemplatesFromMarkdownPlan(conversation: AIConversation, context: ModelContext, includeRestDays: Bool) -> [WorkoutTemplate] {
        let workoutDays = parseWorkoutDaysFromMarkdown(text: conversation.response)
        var templates: [WorkoutTemplate] = []
        // Build baselines once for recommended weights
        #if canImport(Foundation)
        let preferredUnit = UserDefaults.standard.string(forKey: "weightUnit") ?? "lbs"
        let baselines = ExerciseRecommendationService.baselines(context: context, preferredUnit: preferredUnit)
        // Avoid crashing on duplicate keys (e.g., "Bench Press" vs "bench press")
        var baselineMap: [String: ExerciseBaseline] = [:]
        for baseline in baselines {
            let key = baseline.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existing = baselineMap[key] {
                // Prefer the baseline with more history; tie-breaker: higher e1RM.
                if baseline.occurrences > existing.occurrences || (baseline.occurrences == existing.occurrences && baseline.e1rm > existing.e1rm) {
                    baselineMap[key] = baseline
                }
            } else {
                baselineMap[key] = baseline
            }
        }
        #else
        let preferredUnit = "lbs"
        let baselineMap: [String: ExerciseBaseline] = [:]
        #endif

        let planHash = stablePlanHash(structuredPlanJSON: conversation.structuredPlanJSON, markdown: conversation.response)
        let planTitle = derivePlanTitle(conversation: conversation)
        
        for (dayIndex, day) in workoutDays.enumerated() {
            let isRest = day.title.lowercased().contains("rest") ||
                day.title.lowercased().contains("recovery") ||
                day.details.lowercased().contains("rest day")

            if isRest && !includeRestDays { continue }

            let title = prefixedDayTitle(day.title, dayIndex: dayIndex)
            let existing = findExistingTemplate(planHash: planHash, dayIndex: dayIndex, context: context)
            let template = existing ?? WorkoutTemplate(
                title: title,
                notes: day.details,
                sourceAIConversationId: conversation.id,
                aiPlanHash: planHash,
                aiPlanTitle: planTitle,
                aiWeekTitle: "Week 1",
                aiDayIndex: dayIndex,
                aiDayType: isRest ? "rest" : "workout",
                aiDayTitle: day.title,
                isBuiltIn: false
            )

            template.title = title
            template.notes = day.details
            template.sourceAIConversationId = conversation.id
            template.aiPlanHash = planHash
            template.aiPlanTitle = planTitle
            template.aiWeekTitle = "Week 1"
            template.aiDayIndex = dayIndex
            template.aiDayType = isRest ? "rest" : "workout"
            template.aiDayTitle = day.title
            template.isBuiltIn = false
            template.templateDescription = isRest ? "Rest / Recovery" : "AI plan day"
            
            if existing == nil { context.insert(template) }
            templates.append(template)
            deleteTemplateExercises(template, context: context)
            
            // Parse exercises from markdown details
            let exercises = parseExercisesFromMarkdown(details: day.details, weightUnit: preferredUnit)
            
            for (exerciseIndex, exercise) in exercises.enumerated() {
                // Choose safe, realistic suggested weight:
                // - Prefer user's last working set at same reps
                // - Otherwise derive conservatively from e1RM
                // - If AI provided a number, clamp it to safe bounds
                let suggested: Double? = safeSuggestedWeight(
                    ai: exercise.weight,
                    name: exercise.name,
                    reps: exercise.reps,
                    unit: preferredUnit,
                    baselines: baselineMap
                )
                let templateExercise = TemplateExercise(
                    name: exercise.name,
                    order: exerciseIndex,
                    sets: exercise.sets,
                    reps: exercise.reps,
                    suggestedWeight: suggested,
                    weightUnit: preferredUnit,
                    notes: exercise.notes
                )
                
                templateExercise.template = template
                context.insert(templateExercise)
            }

            template.exerciseCount = exercises.count
            
            print("✅ Created template '\(template.title)' from markdown")
        }
        
        _ = PersistenceSave.commit(context, action: "save changes")
        return templates
    }

    func getAvailableWorkoutDays(from conversation: AIConversation) -> [(index: Int, title: String, type: String)] {
        #if canImport(FoundationModels)
        if let jsonString = conversation.structuredPlanJSON,
           let plan = decodePlan(jsonString: jsonString),
           let week = plan.weeks.first
        {
            return week.days.enumerated().map { (index: $0.offset, title: $0.element.title, type: String(describing: $0.element.type)) }
        }
        #endif
        let workoutDays = parseWorkoutDaysFromMarkdown(text: conversation.response)
        if workoutDays.isEmpty { return [] }
        return workoutDays.enumerated().map { (index: $0.offset, title: $0.element.title, type: $0.element.title.lowercased().contains("rest") ? "rest" : "day") }
    }

    // MARK: - Helpers

    #if canImport(FoundationModels)
    private func decodePlan(jsonString: String) -> WorkoutPlan? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkoutPlan.self, from: data)
    }
    #endif

    private func stablePlanHash(structuredPlanJSON: String?, markdown: String) -> String {
        let source = (structuredPlanJSON?.isEmpty == false ? structuredPlanJSON! : markdown)
        let data = Data(source.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func derivePlanTitle(conversation: AIConversation) -> String {
        #if canImport(FoundationModels)
        if let jsonString = conversation.structuredPlanJSON,
           let plan = decodePlan(jsonString: jsonString)
        {
            return plan.title
        }
        #endif
        let firstLine = conversation.response.split(separator: "\n").first.map(String.init) ?? ""
        let trimmedFirst = firstLine.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if trimmedFirst.count >= 6 { return trimmedFirst }
        let prompt = conversation.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.isEmpty ? "AI Plan" : prompt
    }

    private func findExistingTemplate(planHash: String, dayIndex: Int, context: ModelContext) -> WorkoutTemplate? {
        let hash: String? = planHash
        let idx: Int? = dayIndex
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { t in
                t.aiPlanHash == hash && t.aiDayIndex == idx
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private func deleteTemplateExercises(_ template: WorkoutTemplate, context: ModelContext) {
        if let existing = template.exercises {
            for ex in existing { context.delete(ex) }
        }
    }

    #if canImport(FoundationModels)
    private func templateDescription(for day: Day) -> String {
        switch day.type {
        case .rest: return "Rest day"
        case .activeRecovery: return "Active recovery"
        case .runEasy, .runTempo, .runIntervals, .longRun: return "Run"
        case .cyclingEndurance: return "Cycling"
        case .rowing: return "Rowing"
        case .swimming: return "Swimming"
        case .strengthUpper, .strengthLower, .fullBodyStrength: return "Strength training"
        }
    }

    private func notesSummary(for day: Day) -> String? {
        // Prefer a compact summary; keep per-item detail inside TemplateExercise notes.
        if day.items.isEmpty {
            return day.type == .rest ? "Rest and recover. Light walking and mobility optional." : nil
        }
        // If there’s a single activity with no sets/reps, surface it.
        if day.items.count == 1, let item = day.items.first, item.sets == nil, item.reps == nil {
            return activitySummary(item: item)
        }
        return nil
    }

    private struct MappedItem {
        let name: String
        let order: Int
        let sets: Int
        let reps: Int
        let suggestedWeight: Double?
        let weightUnit: String
        let notes: String?
        let countsTowardExerciseCount: Bool
    }

    private func mapItemToTemplateExercise(_ item: Item, order: Int, defaultWeightUnit: String) -> MappedItem {
        if let sets = item.sets, let reps = item.reps {
            let (suggestedWeight, weightUnit) = parseSuggestedWeight(item.suggestedWeight, defaultUnit: defaultWeightUnit)
            return MappedItem(
                name: item.name,
                order: order,
                sets: sets,
                reps: reps,
                suggestedWeight: suggestedWeight,
                weightUnit: weightUnit,
                notes: item.notes,
                countsTowardExerciseCount: true
            )
        }

        // Cardio / yoga / recovery activity:
        // - If duration/distance present, encode a "Set 1: mm:ss ..." line so workout creation can generate a cardio log.
        // - Otherwise store a summary and avoid generating logs later by using 0 sets.
        let summary = activitySummary(item: item)
        if item.durationMinutes != nil || item.distance != nil {
            let firstLine = cardioSetLine(item: item)
            var lines: [String] = [firstLine]
            if let pace = item.pace, !pace.isEmpty { lines.append("Pace: \(pace)") }
            if let effort = item.effort, !effort.isEmpty { lines.append("Effort: \(effort)") }
            if let notes = item.notes, !notes.isEmpty { lines.append(notes) }
            return MappedItem(
                name: item.name,
                order: order,
                sets: 1,
                reps: 0,
                suggestedWeight: nil,
                weightUnit: defaultWeightUnit.lowercased().contains("kg") ? "kg" : "lbs",
                notes: lines.joined(separator: "\n"),
                countsTowardExerciseCount: true
            )
        }
        return MappedItem(
            name: item.name,
            order: order,
            sets: 0,
            reps: 0,
            suggestedWeight: nil,
            weightUnit: defaultWeightUnit.lowercased().contains("kg") ? "kg" : "lbs",
            notes: summary,
            countsTowardExerciseCount: true
        )
    }

    private func parseSuggestedWeight(_ weightString: String?, defaultUnit: String) -> (Double?, String) {
        guard let weightString, !weightString.isEmpty else {
            return (nil, defaultUnit.lowercased().contains("kg") ? "kg" : "lbs")
        }
        let components = weightString.components(separatedBy: .whitespaces)
        let suggestedWeight = Double(components.first ?? "")
        let unit: String
        if weightString.lowercased().contains("kg") {
            unit = "kg"
        } else {
            unit = "lbs"
        }
        return (suggestedWeight, unit)
    }

    private func activitySummary(item: Item) -> String {
        var parts: [String] = []
        if let minutes = item.durationMinutes {
            parts.append("Duration: \(minutes) min")
        }
        if let dist = item.distance, let unit = item.distanceUnit {
            parts.append("Distance: \(String(format: "%.2f", dist)) \(unit)")
        }
        if let pace = item.pace, !pace.isEmpty {
            parts.append("Pace: \(pace)")
        }
        if let effort = item.effort, !effort.isEmpty {
            parts.append("Effort: \(effort)")
        }
        if let notes = item.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? (item.notes ?? "") : parts.joined(separator: " • ")
    }

    private func cardioSetLine(item: Item) -> String {
        let minutes = item.durationMinutes ?? 0
        let seconds = 0
        let time = "\(minutes):\(String(format: "%02d", seconds))"
        if let dist = item.distance, let unit = item.distanceUnit {
            return "Set 1: \(time) \(String(format: "%.2f", dist)) \(unit)"
        }
        return "Set 1: \(time)"
    }

    #endif

    private func prefixedDayTitle(_ title: String, dayIndex: Int) -> String {
        let prefix = "\(dayIndex + 1):"
        if title.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) { return title }
        return "\(dayIndex + 1): \(title)"
    }
    
    // MARK: - Private Markdown Parsing Helpers
    
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
        // More flexible patterns for various AI output formats
        let patterns = [
            // "### Day 1: Title" or "## Day 1" (1-6 hash marks)
            "^#{1,6}\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "- Day 1: Title" or "• Day 1" (bullet lists)
            "^[-•*]\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "1. Day 1: Title" (numbered lists)
            "^\\d+\\.\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "**Day 1: Title**" (bold without prefix)
            "^\\*{2}\\s*Day\\s+(\\d+)\\s*[:\\-–]?\\s*(.*)\\*{0,2}$",
            // "Day 1: Title" (no prefix at all)
            "^Day\\s+(\\d+)\\s*[:\\-–]?\\s*(.*)$",
            // "### Week 1, Day 1: Title" or "Week 1 - Day 1"
            "^#{0,6}\\s*\\*{0,2}\\s*Week\\s*\\d+[,:\\-–\\s]+Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // Weekday patterns: "### Monday: Title"
            "^#{1,6}\\s*\\*{0,2}\\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s*\\*{0,2}\\s*[:\\-–](.*)$",
            // Weekday bullet: "- Monday: Title"
            "^[-•*]\\s*\\*{0,2}\\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s*\\*{0,2}\\s*[:\\-–](.*)$",
            // Weekday no prefix: "Monday: Title" or "**Monday: Title**"
            "^\\*{0,2}\\s*(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)\\s*\\*{0,2}\\s*[:\\-–](.*)$"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 {
                    if let dayRange = Range(match.range(at: 1), in: line) {
                        let day = String(line[dayRange]).trimmingCharacters(in: .whitespaces)
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
        // Multiple flexible patterns for various AI output formats
        // All patterns capture: (1) name, (2) sets, (3) reps, (4) weight?, (5) unit?, (6) notes?
        let patterns = [
            // "Exercise Name - 4 sets of 6 reps (185 lbs)"
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*sets?\\s*(?:of\\s*)?(\\d+)\\s*reps?(?:\\s*\\(?([0-9.]+)\\s*(lbs|kg)?\\)?)?(.*)$",
            // "Exercise Name: 4x6 @ 185 lbs"
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*[xX×]\\s*(\\d+)(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?(.*)$",
            // "Exercise Name (3x10)" or "Exercise Name (3 x 10)"
            "^([^(]+)\\s*\\((\\d+)\\s*[xX×]\\s*(\\d+)(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?\\)(.*)$",
            // "Exercise Name: 3 sets, 10 reps" (comma separated)
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*sets?,?\\s*(\\d+)\\s*reps?(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?(.*)$",
            // "Exercise Name - 3 sets x 10 reps"
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*sets?\\s*[xX×]\\s*(\\d+)\\s*reps?(?:\\s*\\(?([0-9.]+)\\s*(lbs|kg)?\\)?)?(.*)$",
            // "Exercise Name – 3x10-12" (rep ranges, take first number)
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*[xX×]\\s*(\\d+)(?:\\s*[-–]\\s*\\d+)?(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?(.*)$",
            // "Exercise Name: 3 x 10 reps @ 135 lbs" (spaces around x)
            "^([^-–:]+)[-–:]\\s*(\\d+)\\s*[xX×]\\s*(\\d+)\\s*(?:reps?)?(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?(.*)$",
            // "Exercise Name 3x10" (no separator, space before sets)
            "^([A-Za-z][A-Za-z\\s]+?)\\s+(\\d+)\\s*[xX×]\\s*(\\d+)(?:\\s*[@at]\\s*([0-9.]+)\\s*(lbs|kg)?)?$"
        ]

        for pattern in patterns {
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

    // MARK: - Recommended weights using baselines + progressive overload
    private func safeSuggestedWeight(ai: Double?, name: String, reps: Int, unit: String, baselines: [String: ExerciseBaseline]) -> Double? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        let baseline = baselines[key] ?? baselines.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value
        if let b = baseline {
            if let last = b.lastByReps[reps] {
                if let ai, ai <= last * 1.05, ai >= last * 0.95 { return roundToPlates(ai, unit: unit) }
                return roundToPlates(last, unit: unit)
            }
            let loads = ExerciseRecommendationService.suggestedLoads(e1rm: b.e1rm, unit: unit, repTargets: [reps])
            let base = (loads[reps] ?? (b.e1rm * 0.7)) * 0.9
            if let ai, ai > 0 { return roundDownToPlates(min(ai, base), unit: unit) }
            return roundDownToPlates(base, unit: unit)
        }
        if let ai, ai > 0 { return roundDownToPlates(ai, unit: unit) }
        return nil
    }

    private func recommendedWeight(for name: String, reps: Int, unit: String, baselines: [String: ExerciseBaseline]) -> Double? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let b = baselines[key] { return computeFromBaseline(b, reps: reps, unit: unit) }
        if let b = baselines.first(where: { key.contains($0.key) || $0.key.contains(key) })?.value {
            return computeFromBaseline(b, reps: reps, unit: unit)
        }
        return nil
    }

    private func computeFromBaseline(_ baseline: ExerciseBaseline, reps: Int, unit: String) -> Double {
        // If we have a recent set at this rep target, use that value (no auto‑increase to avoid overshooting).
        if let last = baseline.lastByReps[reps] {
            return roundToPlates(last, unit: unit)
        }
        // Otherwise derive a conservative load from e1RM and round down to plates.
        let loads = ExerciseRecommendationService.suggestedLoads(e1rm: baseline.e1rm, unit: unit, repTargets: [reps])
        let aggressive = loads[reps] ?? (baseline.e1rm * 0.7)
        let conservative = aggressive * 0.9 // nudge down to avoid overestimation
        return roundDownToPlates(conservative, unit: unit)
    }

    private func roundToPlates(_ value: Double, unit: String) -> Double {
        if unit.lowercased() == "kg" {
            return (value / 2.5).rounded() * 2.5
        } else {
            return (value / 5.0).rounded() * 5.0
        }
    }

    private func roundDownToPlates(_ value: Double, unit: String) -> Double {
        if unit.lowercased() == "kg" {
            return floor(value / 2.5) * 2.5
        } else {
            return floor(value / 5.0) * 5.0
        }
    }
}
