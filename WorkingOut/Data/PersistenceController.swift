import SwiftUI
import SwiftData

@MainActor
@Observable
class PersistenceController {
    static let shared = PersistenceController()
    
    // Add a static instance for previews using an in-memory store
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
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
    init(inMemory: Bool = false) {
        let schema = Schema([
            ExerciseDefinition.self,
            WorkoutSession.self,
            ExerciseLog.self,
            RunningSession.self,
            WeightEntry.self,
            AIConversation.self,
            WorkoutTemplate.self,
            TemplateExercise.self
        ])

        // Build a configuration; enable CloudKit (will fall back to local if not available)
        var config: ModelConfiguration
        if #available(iOS 17.0, *) {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .automatic)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }

        // Try to create the container; if CloudKit is not fully available at runtime, this will throw and we will retry locally.
        do {
            container = try ModelContainer(for: schema, configurations: [config])
            #if canImport(CloudKit)
            if #available(iOS 17.0, *), !inMemory {
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
            try? context.save()
        }
    }
    
    // Remove duplicated exercise definitions (same name + muscle group),
    // preferring built-ins over user-defined. Reassign any logs pointing
    // at duplicates to the kept definition before deletion.
    func deduplicateExerciseDefinitions() {
        let context = container.mainContext
        guard let defs = try? context.fetch(FetchDescriptor<ExerciseDefinition>()) else { return }
        var groups: [String: [ExerciseDefinition]] = [:]
        for d in defs {
            let key = (d.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) + "||" + d.muscleGroup.lowercased()
            groups[key, default: []].append(d)
        }
        var changed = false
        for (_, items) in groups where items.count > 1 {
            // Keep built-in if present, otherwise first
            let keeper: ExerciseDefinition = items.first(where: { !$0.isUserDefined }) ?? items.first!
            let toDelete = items.filter { $0.id != keeper.id }
            if toDelete.isEmpty { continue }
            // Repoint logs
            for dup in toDelete {
                if let dupId = dup.id as UUID? {
                    let pred = #Predicate<ExerciseLog> { $0.exerciseDefinition?.id == dupId }
                    let fd = FetchDescriptor<ExerciseLog>(predicate: pred)
                    if let logs = try? context.fetch(fd) {
                        for log in logs { log.exerciseDefinition = keeper }
                    }
                }
                context.delete(dup)
                changed = true
            }
        }
        if changed { try? context.save() }
    }
    
    // MARK: - Exercise Definition Methods
    
    func addExerciseDefinition(name: String, muscleGroup: String) {
        let exercise = ExerciseDefinition(name: name, muscleGroup: muscleGroup, isUserDefined: true)
        container.mainContext.insert(exercise)
        try? container.mainContext.save()
    }
    
    func fetchExerciseDefinitions() -> [ExerciseDefinition] {
        let descriptor = FetchDescriptor<ExerciseDefinition>()
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Workout Session Methods
    
    func addWorkoutSession(date: Date = Date(), notes: String? = nil) -> WorkoutSession {
        let session = WorkoutSession(date: date, notes: notes)
        container.mainContext.insert(session)
        try? container.mainContext.save()
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
        try? container.mainContext.save()
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
        try? container.mainContext.save()
        return entry
    }
    
    func fetchWeightEntries() -> [WeightEntry] {
        let descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
} 
