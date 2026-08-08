import Foundation
import SwiftData

/// Service to seed built-in workout templates into the database
@MainActor
class TemplateSeeder {
    static let shared = TemplateSeeder()

    private init() {}
    
    /// Check if built-in templates have been seeded
    func hasSeeded(context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate<WorkoutTemplate> { $0.isBuiltIn == true }
        )
        descriptor.fetchLimit = 1
        let hasAnyBuiltIns = ((try? context.fetch(descriptor)) ?? []).isEmpty == false
        if hasAnyBuiltIns {
            // Heal legacy state where the DB was restored but UserDefaults didn't come along.
            UserDefaults.standard.set(true, forKey: "hasSeededBuiltInTemplates_v1")
        }
        return hasAnyBuiltIns
    }
    
    /// Seed all built-in templates into the database
    func seedBuiltInTemplates(context: ModelContext) async throws {
        // Older app versions incorrectly marked user-created templates as built-in.
        // Repair them before built-in cleanup so a title collision cannot delete
        // the user's template.
        _ = migrateLegacyCustomTemplates(context: context)
        // Run idempotent rename/migration pass for advanced template names
        try? await renameAdvancedTemplateTitlesIfNeeded(context: context)
        // Remove any previously-created duplicates before we decide what to insert
        _ = deduplicateBuiltInTemplates(context: context)
        _ = deduplicateImportedTemplates(context: context)
        _ = backfillExerciseCountsIfNeeded(context: context)
        _ = backfillAITemplateMetadataIfNeeded(context: context)

        let allBuiltInTemplates = BuiltInTemplateLibrary.allTemplates

        // Fetch existing built-ins by title so seeding is idempotent even if
        // UserDefaults is lost (e.g., app redownload with CloudKit restore).
        let existingBuiltIns = (try? context.fetch(FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        ))) ?? []
        let existingTitles = Set(existingBuiltIns.map { $0.title })

        var insertedCount = 0
        for templateData in allBuiltInTemplates where !existingTitles.contains(templateData.title) {
            let template = WorkoutTemplate(
                title: templateData.title,
                notes: templateData.description,
                createdDate: Date(),
                sourceAIConversationId: nil,
                importSourceSessionID: nil,
                exerciseCount: templateData.exercises.count,
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

            insertedCount += 1
        }

        if insertedCount > 0 {
            print("🌱 Seeding built-in workout templates... (adding \(insertedCount) new)")
            try context.save()
            print("✅ Successfully seeded \(insertedCount) built-in workout templates")
        } else {
            print("✅ Built-in templates already seeded")
        }

        // Mark as seeded (legacy flag)
        UserDefaults.standard.set(true, forKey: "hasSeededBuiltInTemplates_v1")
    }
    
    /// Force reseed (for development/testing)
    func forceSeed(context: ModelContext) async throws {
        // Protect legacy user-created templates before deleting built-ins.
        _ = migrateLegacyCustomTemplates(context: context)

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
    /// User-created templates were labeled built-in in older releases. Reclassify
    /// only the legacy Custom category, which is not used by the built-in library.
    @discardableResult
    func migrateLegacyCustomTemplates(context: ModelContext) -> Int {
        let fetch = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate {
                $0.isBuiltIn == true &&
                $0.experienceLevel == "Custom"
            }
        )
        guard let templates = try? context.fetch(fetch), !templates.isEmpty else {
            return 0
        }

        for template in templates {
            template.isBuiltIn = false
        }
        _ = PersistenceSave.commit(context, action: "save changes")
        return templates.count
    }

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
        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
    }

    /// Remove duplicate built-in templates by title, keeping a single copy.
    /// Returns the number of templates deleted. Safe to call multiple times.
    @discardableResult
    func deduplicateBuiltInTemplates(context: ModelContext) -> Int {
        let fetch = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.isBuiltIn == true }
        )
        guard let items = try? context.fetch(fetch), items.count > 1 else { return 0 }

        func normalize(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var groups: [String: [WorkoutTemplate]] = [:]
        for t in items {
            groups[normalize(t.title), default: []].append(t)
        }

        var deleted = 0
        var changed = false
        for (_, group) in groups where group.count > 1 {
            // Keep the one with the earliest createdDate (more stable for users who customized titles/notes later).
            let keeper = group.sorted { $0.createdDate < $1.createdDate }.first!
            for dup in group where dup.id != keeper.id {
                context.delete(dup)
                deleted += 1
                changed = true
            }
        }

        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
        return deleted
    }

    /// Remove duplicate imported templates created from the same shared session id,
    /// keeping a single copy. Returns the number of templates deleted.
    @discardableResult
    func deduplicateImportedTemplates(context: ModelContext) -> Int {
        let fetch = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate {
                $0.isBuiltIn == false &&
                $0.importSourceSessionID != nil
            }
        )
        guard let items = try? context.fetch(fetch), items.count > 1 else { return 0 }

        var groups: [UUID: [WorkoutTemplate]] = [:]
        for t in items {
            guard let id = t.importSourceSessionID else { continue }
            groups[id, default: []].append(t)
        }

        var deleted = 0
        var changed = false
        for (_, group) in groups where group.count > 1 {
            let keeper = group.sorted { $0.createdDate < $1.createdDate }.first!
            for dup in group where dup.id != keeper.id {
                context.delete(dup)
                deleted += 1
                changed = true
            }
        }

        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
        return deleted
    }

    /// Fill `exerciseCount` without faulting the exercises relationship for built-ins.
    /// Safe to call multiple times.
    @discardableResult
    func backfillExerciseCountsIfNeeded(context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        guard !all.isEmpty else { return 0 }

        let builtInCounts = Dictionary(
            uniqueKeysWithValues: BuiltInTemplateLibrary.allTemplates.map { ($0.title, $0.exercises.count) }
        )

        var changed = 0
        for t in all where t.exerciseCount <= 0 {
            if t.isBuiltIn, let count = builtInCounts[t.title] {
                t.exerciseCount = count
                changed += 1
                continue
            }
            // For non-built-ins (usually small), fall back to relationship count.
            if let exercises = t.exercises {
                t.exerciseCount = exercises.count
                changed += 1
            }
        }

        if changed > 0 { _ = PersistenceSave.commit(context, action: "save changes") }
        return changed
    }

    /// Backfill AI template grouping fields for older templates created before we stored plan metadata.
    /// Safe to call multiple times.
    @discardableResult
    func backfillAITemplateMetadataIfNeeded(context: ModelContext) -> Int {
        let fetch = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate {
                $0.isBuiltIn == false &&
                $0.experienceLevel != "Imported" &&
                $0.aiPlanHash == nil &&
                $0.sourceAIConversationId != nil
            }
        )
        guard let items = try? context.fetch(fetch), !items.isEmpty else { return 0 }

        func parseDayPrefix(_ title: String) -> (index: Int?, dayTitle: String) {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let n = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) {
                let dayTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return (max(0, n - 1), dayTitle.isEmpty ? trimmed : dayTitle)
            }
            return (nil, trimmed)
        }

        var changed = 0
        for t in items {
            guard let convoID = t.sourceAIConversationId else { continue }
            t.aiPlanHash = convoID.uuidString
            if t.aiPlanTitle == nil { t.aiPlanTitle = "AI Plan" }
            if t.aiWeekTitle == nil { t.aiWeekTitle = "Week 1" }

            let parsed = parseDayPrefix(t.title)
            if t.aiDayIndex == nil { t.aiDayIndex = parsed.index }
            if t.aiDayTitle == nil { t.aiDayTitle = parsed.dayTitle }

            changed += 1
        }

        if changed > 0 { _ = PersistenceSave.commit(context, action: "save changes") }
        return changed
    }
}
