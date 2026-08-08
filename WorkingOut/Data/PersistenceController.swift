import SwiftUI
import SwiftData

@MainActor
@Observable
class PersistenceController {
    enum CloudKitMode {
        case automatic
        case none
    }

    static let shared: PersistenceController = {
        let launchConfiguration = AppLaunchConfiguration.current
        if launchConfiguration.usesIsolatedStore {
            return PersistenceController(inMemory: true, cloudKitMode: .none)
        }
        return PersistenceController()
    }()
    
    // Add a static instance for previews using an in-memory store
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true, cloudKitMode: .none)
        let context = controller.container.mainContext
        
        // Populate initial exercises
        ExerciseLibrary.populateInitialExercises(context: context)
        
        // Add sample weight entry
        let weightEntry = WeightEntry(date: Date(), weight: 185.0, weightUnit: "lbs")
        context.insert(weightEntry)
        
        // Add sample running session
        let run = RunningSession(date: Date().addingTimeInterval(-86400), // Yesterday
                                 distance: 5.0,
                                 distanceUnit: "km",
                                 duration: 1800, // 30 minutes
                                 locations: Data()) // Empty location data for preview
        context.insert(run)
        
        // Add sample workout session
        let workout = WorkoutSession(date: Date().addingTimeInterval(-172800)) // Day before yesterday
        context.insert(workout)
        // You could add sample ExerciseLogs to the workout here too
        
        do {
            try context.save()
        } catch {
            print("Failed to save preview context: \(error)")
        }
        
        return controller
    }()
    
    let container: ModelContainer
    private(set) var isCloudBacked: Bool = false
    
    // Modify init to accept inMemory flag
    init(inMemory: Bool = false, cloudKitMode: CloudKitMode = .automatic) {
        let schema = Schema([
            ExerciseDefinition.self,
            WorkoutSession.self,
            ExerciseLog.self,
            RunningSession.self,
            RunningPlan.self,
            RunningPlanSession.self,
            TrainingPlan.self,
            PlannedSession.self,
            WeightEntry.self,
            AIConversation.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            HealthWorkoutInboxItem.self,
            CardioWorkoutInboxItem.self
        ])

        // Build a configuration; enable CloudKit (will fall back to local if not available)
        var config: ModelConfiguration
        if #available(iOS 17.0, *) {
            let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = (cloudKitMode == .automatic) ? .automatic : .none
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: cloudKitDatabase
            )
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }

        // Try to create the container; if CloudKit is not fully available at runtime, this will throw and we will retry locally.
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            #if canImport(CloudKit)
            if #available(iOS 17.0, *), !inMemory, cloudKitMode == .automatic {
                isCloudBacked = true
            } else {
                isCloudBacked = false
            }
            #else
            isCloudBacked = false
            #endif
        } catch {
            print("Primary ModelContainer failed (CloudKit may not be available): \(error). Falling back to local store…")
            let local: ModelConfiguration
            if #available(iOS 17.0, *) {
                local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            } else {
                local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            }
            do {
                container = try ModelContainer(for: schema, configurations: [local])
                isCloudBacked = false
            } catch {
                fatalError("Could not initialize local ModelContainer: \(error)")
            }
        }
    }

    // Re-seed the library definitions if they were removed
    func ensureDefaultExercisesPresent() {
        let context = container.mainContext
        let defs = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let hasBuiltIns = defs.contains(where: { !$0.isUserDefined })
        if !hasBuiltIns {
            ExerciseLibrary.populateInitialExercises(context: context)
            _ = PersistenceSave.commit(context, action: "save changes")
        }
        // Reclassify arm exercises to Biceps/Triceps when possible
        reclassifyArmExercises()
    }
    
    // Remove duplicated exercise definitions (same name + muscle group),
    // preferring built-ins over user-defined. Reassign any logs pointing
    // at duplicates to the kept definition before deletion.
    // Remove duplicated exercise definitions (same name, ignoring case/whitespace),
    // preferring built-ins over user-defined. Reassign any logs pointing
    // at duplicates to the kept definition before deletion.
    // Returns the number of duplicates removed.
    @discardableResult
    func deduplicateExerciseDefinitions() -> Int {
        let context = container.mainContext
        guard let defs = try? context.fetch(FetchDescriptor<ExerciseDefinition>()) else { return 0 }
        
        // Group by normalized name (robust to case, spacing, and common punctuation variants)
        func normalize(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Normalize smart punctuation to ASCII
            t = t.replacingOccurrences(of: "\u{2019}", with: "'") // curly apostrophe
            t = t.replacingOccurrences(of: "\u{2018}", with: "'") // left single quote
            t = t.replacingOccurrences(of: "\u{2013}", with: "-") // en dash
            t = t.replacingOccurrences(of: "\u{2014}", with: "-") // em dash
            // Replace non-alphanumerics with spaces and collapse spaces
            t = t.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }.reduce("") { $0 + String($1) }
            while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var groups: [String: [ExerciseDefinition]] = [:]
        for d in defs {
            let key = normalize(d.name)
            groups[key, default: []].append(d)
        }
        
        var removedCount = 0
        var changed = false
        
        for (_, items) in groups where items.count > 1 {
            // Determine keeper:
            // 1. Built-in (isUserDefined == false)
            // 2. If multiple built-ins (unlikely) or all user-defined, pick the one with the most logs (if we could check easily) or just the oldest created (by ID sorting or similar stability).
            // For now: Prefer built-in, then first one found.
            
            let builtIn = items.first(where: { !$0.isUserDefined })
            let keeper = builtIn ?? items.first!
            
            let toDelete = items.filter { $0.id != keeper.id }
            if toDelete.isEmpty { continue }
            
            // Repoint logs
            for dup in toDelete {
                if let dupId = dup.id as UUID? {
                    let pred = #Predicate<ExerciseLog> { $0.exerciseDefinition?.id == dupId }
                    let fd = FetchDescriptor<ExerciseLog>(predicate: pred)
                    if let logs = try? context.fetch(fd) {
                        for log in logs { 
                            log.exerciseDefinition = keeper 
                            // If the log had the duplicate's name snapshot, update it to the keeper's name
                            if (log.exerciseName ?? "").lowercased() == dup.name.lowercased() {
                                log.exerciseName = keeper.name
                            }
                        }
                    }
                }
                context.delete(dup)
                removedCount += 1
                changed = true
            }
        }
        
        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
        return removedCount
    }

    /// Unify synonymous exercise names to a single canonical definition
    /// This safely repoints existing logs to the canonical definition and removes the synonym.
    func unifySynonymousExerciseDefinitions() {
        let context = container.mainContext
        let mappings: [(from: String, to: String, group: String)] = [
            (from: "Flat Bench Press", to: "Bench Press", group: "Chest"),
            (from: "Incline Bench", to: "Incline Bench Press", group: "Chest"),
            (from: "Romanian Deadlifts (RDLs)", to: "Romanian Deadlifts", group: "Back"),
            (from: "Rows", to: "Barbell Rows", group: "Back")
        ]

        var changed = false
        for map in mappings {
            let to = map.to
            let group = map.group
            let from = map.from
            // Find canonical; create if missing
            let canonicalPred = #Predicate<ExerciseDefinition> { $0.name == to && $0.muscleGroup == group }
            let canonicalFD = FetchDescriptor<ExerciseDefinition>(predicate: canonicalPred)
            let canonical = (try? context.fetch(canonicalFD))?.first ?? {
                let def = ExerciseDefinition(name: to, muscleGroup: group, isUserDefined: false)
                context.insert(def)
                return def
            }()

            // Find all synonyms matching 'from' in the same group
            let fromPred = #Predicate<ExerciseDefinition> { $0.name == from && $0.muscleGroup == group }
            let fromFD = FetchDescriptor<ExerciseDefinition>(predicate: fromPred)
            guard let synonyms = try? context.fetch(fromFD), !synonyms.isEmpty else { continue }

            for syn in synonyms {
                // Repoint logs
                if let synId = syn.id as UUID? {
                    let logPred = #Predicate<ExerciseLog> { $0.exerciseDefinition?.id == synId }
                    let logFD = FetchDescriptor<ExerciseLog>(predicate: logPred)
                    if let logs = try? context.fetch(logFD) {
                        for log in logs {
                            log.exerciseDefinition = canonical
                            if (log.exerciseName ?? syn.name) == syn.name {
                                log.exerciseName = canonical.name
                            }
                            changed = true
                        }
                    }
                }
                // Delete the synonym definition
                context.delete(syn)
                changed = true
            }
        }

        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
    }
    
    // MARK: - Exercise Definition Methods
    
    func addExerciseDefinition(name: String, muscleGroup: String) {
        let exercise = ExerciseDefinition(name: name, muscleGroup: muscleGroup, isUserDefined: true)
        container.mainContext.insert(exercise)
        _ = PersistenceSave.commit(container.mainContext, action: "save changes")
    }
    
    func fetchExerciseDefinitions() -> [ExerciseDefinition] {
        let descriptor = FetchDescriptor<ExerciseDefinition>()
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    // Split legacy "Arms" group into "Biceps" and "Triceps" when names match
    private func reclassifyArmExercises() {
        let context = container.mainContext
        let fd = FetchDescriptor<ExerciseDefinition>(predicate: #Predicate { $0.muscleGroup == "Arms" })
        guard let defs = try? context.fetch(fd), !defs.isEmpty else { return }
        let bicepsNames: Set<String> = [
            "bicep curls", "dumbbell bicep curls", "machine bicep curls",
            "hammer curls", "preacher curls", "concentration curls", "reverse grip curls"
        ]
        let tricepsNames: Set<String> = [
            "tricep pushdowns", "tricep pushdowns (cable)", "tricep extensions",
            "overhead tricep extension (dumbbell)", "skull crushers", "close grip bench press", "dips"
        ]
        var changed = false
        for d in defs {
            let key = d.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if bicepsNames.contains(key) { d.muscleGroup = "Biceps"; changed = true; continue }
            if tricepsNames.contains(key) { d.muscleGroup = "Triceps"; changed = true; continue }
        }
        if changed { _ = PersistenceSave.commit(context, action: "save changes") }
    }
    
    // MARK: - Workout Session Methods
    
    func addWorkoutSession(date: Date = Date(), notes: String? = nil) -> WorkoutSession {
        let session = WorkoutSession(date: date, notes: notes)
        container.mainContext.insert(session)
        _ = PersistenceSave.commit(container.mainContext, action: "save changes")
        return session
    }
    
    func fetchWorkoutSessions() -> [WorkoutSession] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Running Session Methods
    
    func addRunningSession(distance: Double, duration: TimeInterval, notes: String? = nil, locations: Data? = nil) -> RunningSession {
        let session = RunningSession(distance: distance, duration: duration, notes: notes, locations: locations)
        container.mainContext.insert(session)
        _ = PersistenceSave.commit(container.mainContext, action: "save changes")
        return session
    }
    
    func fetchRunningSessions() -> [RunningSession] {
        let descriptor = FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Weight Entry Methods
    
    func addWeightEntry(weight: Double) -> WeightEntry {
        let entry = WeightEntry(weight: weight)
        container.mainContext.insert(entry)
        _ = PersistenceSave.commit(container.mainContext, action: "save changes")
        return entry
    }
    
    func fetchWeightEntries() -> [WeightEntry] {
        let descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
} 
