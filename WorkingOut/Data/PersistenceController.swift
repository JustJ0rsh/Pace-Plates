import SwiftUI
import SwiftData
import CryptoKit

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
            #if DEBUG
            if ProcessInfo.processInfo.environment["UITEST_COACH_DISK"] == "1" {
                return PersistenceController(isolatedUITestReset: launchConfiguration.shouldResetState)
            }
            #endif
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
    
    private(set) var container: ModelContainer
    private(set) var isCloudBacked: Bool = false
    private(set) var isCoachLocal: Bool = false
    private(set) var storageError: String?
    private(set) var storageGeneration = UUID()
    private(set) var needsLegacyMigration = false
    private(set) var isMigratingHistory = false
    private var storageRoot = CoachLocalOwnership.root
    private var retainedLegacyStore: URL?

    static var legacyModelTypes: [any PersistentModel.Type] {
        [ExerciseDefinition.self, WorkoutSession.self, ExerciseLog.self,
         RunningSession.self, RunningPlan.self, RunningPlanSession.self,
         TrainingPlan.self, PlannedSession.self, WeightEntry.self,
         AIConversation.self, WorkoutTemplate.self, TemplateExercise.self,
         HealthWorkoutInboxItem.self, CardioWorkoutInboxItem.self]
    }

    static var coachSchema: Schema { Schema(legacyModelTypes + CoachPersistence.modelTypes) }

    #if DEBUG
    init(sourceStoreForRegression: ModelContainer) {
        precondition(AppLaunchConfiguration.current.isUITest)
        container = sourceStoreForRegression
    }

    func adoptForStorageRegression(destination: URL, select: (URL, URL) throws -> Void) async throws {
        precondition(AppLaunchConfiguration.current.isUITest)
        try await adoptLocalOwnership(prepareDestination: {
            try CoachLocalOwnership.prepareDirectory(destination.deletingLastPathComponent())
            return destination
        }, select: select)
    }

    private init(isolatedUITestReset: Bool) {
        // A fixed, app-owned test directory lets lifecycle tests reopen synthetic
        // history without ever selecting or clearing the normal application store.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UITestCoachHistory", isDirectory: true)
        do {
            if isolatedUITestReset, FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            try CoachLocalOwnership.prepareDirectory(directory)
            container = try Self.makeLocalContainer(url: directory.appendingPathComponent("test.store"))
            isCoachLocal = true
        } catch { fatalError("Could not initialize disposable lifecycle-test storage: \(error)") }
    }
    #endif

    private static func makeLocalContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = coachSchema
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: url,
                                               cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(CoachPersistence.configurationName, schema: schema,
                                               isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func openSelectedLocalContainer(_ url: URL) throws -> ModelContainer {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CoachLocalOwnership.migrationError("The selected local history is missing. No stale source has been substituted.")
        }
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw CoachLocalOwnership.migrationError("The selected local history is not a regular storage file.")
        }
        return try makeLocalContainer(url: url)
    }
    
    /// Every live model container is explicitly local. A legacy database is
    /// detected without opening it; only the reviewed copy path may read it.
    convenience init(inMemory: Bool = false, cloudKitMode: CloudKitMode = .none) {
        let legacy = ModelConfiguration(schema: Schema(Self.legacyModelTypes), cloudKitDatabase: .none).url
        self.init(inMemory: inMemory, storageRoot: CoachLocalOwnership.root, legacyStore: legacy)
    }

    private init(inMemory: Bool, storageRoot: URL, legacyStore: URL) {
        self.storageRoot = storageRoot
        retainedLegacyStore = legacyStore
        do {
            if inMemory {
                container = try Self.makeLocalContainer(inMemory: true)
                isCoachLocal = true
                return
            }
            if let selectedURL = try CoachLocalOwnership.selectedStoreURL(root: storageRoot) {
                container = try Self.openSelectedLocalContainer(selectedURL)
                isCoachLocal = true
                return
            }
            let manager = FileManager.default
            let sourceExists = manager.fileExists(atPath: legacyStore.path)
            let support = legacyStore.deletingLastPathComponent().appendingPathComponent(".\(legacyStore.deletingPathExtension().lastPathComponent)_SUPPORT")
            let hasFragments = manager.fileExists(atPath: legacyStore.path + "-wal") || manager.fileExists(atPath: legacyStore.path + "-shm") || manager.fileExists(atPath: support.path)
            var hasUnselectedStorage = false
            if manager.fileExists(atPath: storageRoot.path) {
                hasUnselectedStorage = !(try manager.contentsOfDirectory(at: storageRoot, includingPropertiesForKeys: nil)).isEmpty
            }
            if sourceExists || hasFragments || hasUnselectedStorage {
                container = try Self.makeLocalContainer(inMemory: true)
                needsLegacyMigration = sourceExists
                storageError = sourceExists
                    ? "Your existing history needs a verified local copy before you can continue. New entries will stay on this device. Other devices and retained iCloud records will not be changed."
                    : "An incomplete history or migration was found. Its files are retained; recovery is needed before creating new history."
                return
            }
            let destination = try CoachLocalOwnership.newStagingStore(root: storageRoot)
            container = try Self.makeLocalContainer(url: destination)
            try container.mainContext.save()
            try CoachLocalOwnership.select(destination, legacy: legacyStore, root: storageRoot)
            isCoachLocal = true
        } catch {
            do { container = try Self.makeLocalContainer(inMemory: true) }
            catch { fatalError("Could not initialize storage recovery screen: \(error)") }
            storageError = error.localizedDescription
        }
    }

    #if DEBUG
    static func isSyntheticDescendant(_ child: URL, of parent: URL) -> Bool {
        // On iOS, resolving an entirely nonexistent tail may leave /var versus
        // /private/var aliases unresolved. Resolve its existing ancestor first.
        func canonicalParts(_ url: URL) -> [String]? {
            var ancestor = url.standardizedFileURL
            var tail: [String] = []
            while !FileManager.default.fileExists(atPath: ancestor.path) {
                if (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil { return nil }
                guard ancestor.path != "/" else { return nil }
                tail.append(ancestor.lastPathComponent)
                ancestor.deleteLastPathComponent()
            }
            if !tail.isEmpty {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return nil }
            }
            return ancestor.resolvingSymlinksInPath().standardizedFileURL.pathComponents + tail.reversed()
        }
        guard let childParts = canonicalParts(child), let parentParts = canonicalParts(parent) else { return false }
        return childParts.count > parentParts.count
            && Array(childParts.prefix(parentParts.count)) == parentParts
    }

    /// Uses the production startup decision with paths owned by a test fixture.
    convenience init(storageRootForRegression root: URL, legacyStoreForRegression legacy: URL) {
        precondition(Self.isSyntheticDescendant(root, of: FileManager.default.temporaryDirectory))
        precondition(Self.isSyntheticDescendant(legacy, of: root.deletingLastPathComponent()))
        self.init(inMemory: false, storageRoot: root, legacyStore: legacy)
    }

    func migrateForStorageRegression(interruptAfter: String?) async throws {
        try await migrateLegacyHistory(interruptAfter: interruptAfter)
    }
    #endif

    func adoptLocalOwnership() async throws { try await migrateLegacyHistory() }

    func migrateLegacyHistory() async throws {
        try await migrateLegacyHistory(interruptAfter: nil)
    }

    /// The hook is internal and the production call always passes nil. It is
    /// used by isolated Debug regression fixtures, never launch arguments.
    private func migrateLegacyHistory(interruptAfter: String?) async throws {
        guard !isCoachLocal, needsLegacyMigration, let source = retainedLegacyStore else { return }
        guard !isMigratingHistory else { throw CoachLocalOwnership.migrationError("A history copy is already in progress.") }
        guard !RunTracker.shared.hasRecoverableActivity else {
            throw CoachLocalOwnership.migrationError("Resolve the recoverable run before changing storage.")
        }
        isMigratingHistory = true
        defer { isMigratingHistory = false }
        do {
            let lock = try CoachLocalOwnership.MigrationLock(root: storageRoot)
            defer { withExtendedLifetime(lock) {} }
            // An earlier call may have committed selection immediately before
            // being interrupted. Reopen it, never recopy over later local work.
            if let selected = try CoachLocalOwnership.selectedStoreURL(root: storageRoot) {
                let old = container
                container = try Self.openSelectedLocalContainer(selected)
                WearableWorkoutInboxService.retireLocalStore(old)
                isCoachLocal = true; needsLegacyMigration = false; storageError = nil
                storageGeneration = UUID()
                return
            }
            var journal = try CoachLocalOwnership.beginMigration(source: source, root: storageRoot)
            if let checkpoint = journal.checkpoint {
                let current = try await Task.detached(priority: .userInitiated) { try CoachLocalOwnership.rawCheckpoint(source) }.value
                if current.identity != checkpoint {
                    // This is a new explicit retry, not automatic fallback. A
                    // changed source requires a fresh stage; retain the older
                    // stage and journal so neither history is lost.
                    journal = try CoachLocalOwnership.restartUnselectedMigration(journal, source: source, root: storageRoot)
                }
            }
            let destination = CoachLocalOwnership.destination(for: journal, root: storageRoot)
            if interruptAfter == "allocated" { throw CoachLocalOwnership.migrationError("Synthetic interruption after allocation.") }
            if journal.phase == "allocated" {
                let owned = destination.deletingLastPathComponent()
                // Only this journal-owned, unselected stage can be discarded.
                if FileManager.default.fileExists(atPath: owned.path) { try FileManager.default.removeItem(at: owned) }
                try CoachLocalOwnership.prepareDirectory(owned)
                let checkpoint = try await Task.detached(priority: .userInitiated) {
                    let before = try CoachLocalOwnership.rawCheckpoint(source)
                    try CoachLocalOwnership.copyStore(from: source, to: destination)
                    try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: destination)
                    let copy = try CoachLocalOwnership.rawCheckpoint(destination)
                    let after = try CoachLocalOwnership.rawCheckpoint(source)
                    guard before.identity == copy.identity, before.identity == after.identity else {
                        throw CoachLocalOwnership.migrationError("The original history changed while being copied. Nothing was selected.")
                    }
                    return before
                }.value
                journal.checkpoint = checkpoint.identity
                journal.phase = "copied"
                try CoachLocalOwnership.writeJournal(journal, root: storageRoot)
            }
            if interruptAfter == "copied" { throw CoachLocalOwnership.migrationError("Synthetic interruption after copy.") }
            try Task.checkCancellation()
            let checkpoint = try await Task.detached(priority: .userInitiated) { try CoachLocalOwnership.rawCheckpoint(source) }.value
            guard checkpoint.identity == journal.checkpoint else {
                throw CoachLocalOwnership.migrationError("The retained source changed after the copy. Recovery is needed before retrying.")
            }
            // A previous interrupted attempt may already have opened this
            // unselected copy with the full schema. Check every original field.
            try CoachLocalOwnership.verifyRetainedColumns(checkpoint, at: destination)
            let local = try Self.makeLocalContainer(url: destination)
            try CoachLocalOwnership.verifyRetainedColumns(checkpoint, at: destination)
            // Exercise typed model decoding as well as raw column fidelity.
            _ = try CoachLocalOwnership.identityInventory(local.mainContext)
            _ = try CoachLocalOwnership.snapshotDigest(local.mainContext)
            guard !RunTracker.shared.hasRecoverableActivity else {
                throw CoachLocalOwnership.migrationError("A recoverable run appeared during the copy. Nothing was selected.")
            }
            let currentSource = try await Task.detached(priority: .userInitiated) { try CoachLocalOwnership.rawCheckpoint(source) }.value
            guard currentSource.identity == checkpoint.identity else {
                throw CoachLocalOwnership.migrationError("The retained source changed during verification. Nothing was selected.")
            }
            guard !RunTracker.shared.hasRecoverableActivity else {
                throw CoachLocalOwnership.migrationError("A recoverable run appeared before selection. Nothing was switched.")
            }
            try Task.checkCancellation()
            journal.phase = "verified"
            try CoachLocalOwnership.writeJournal(journal, root: storageRoot)
            if interruptAfter == "verified" { throw CoachLocalOwnership.migrationError("Synthetic interruption after verification.") }
            try CoachLocalOwnership.select(destination, legacy: source, root: storageRoot, journal: journal)
            if interruptAfter == "selected" { throw CoachLocalOwnership.migrationError("Synthetic interruption after selection.") }
            journal.phase = "active"
            try CoachLocalOwnership.writeJournal(journal, root: storageRoot)
            let old = container
            container = local
            WearableWorkoutInboxService.retireLocalStore(old)
            isCoachLocal = true; needsLegacyMigration = false; storageError = nil
            storageGeneration = UUID()
        } catch {
            storageError = error.localizedDescription
            throw error
        }
    }

    private func adoptLocalOwnership(prepareDestination: () throws -> URL,
                                    select: (URL, URL) throws -> Void) async throws {
        guard !isCoachLocal, storageError == nil else { return }
        guard !RunTracker.shared.hasRecoverableActivity else {
            throw CoachLocalOwnership.OwnershipError.unavailable("Save or discard the active run before changing storage.")
        }
        try container.mainContext.save()
        let sourceContainer = container
        guard let source = sourceContainer.configurations.first?.url else {
            throw CoachLocalOwnership.OwnershipError.unavailable("The original store location could not be resolved.")
        }
        let before = try CoachLocalOwnership.identityInventory(sourceContainer.mainContext)
        let contentBefore = try CoachLocalOwnership.snapshotDigest(sourceContainer.mainContext)
        let destination = try prepareDestination()
        try await Task.detached(priority: .userInitiated) {
            try CoachLocalOwnership.copyStore(from: source, to: destination)
            try CoachLocalOwnership.copyAuxiliaryFiles(from: source, to: destination)
        }.value
        let localContainer = try Self.makeLocalContainer(url: destination)
        let after = try CoachLocalOwnership.identityInventory(localContainer.mainContext)
        let freshSource = ModelContext(sourceContainer)
        let latest = try CoachLocalOwnership.identityInventory(freshSource)
        let contentAfter = try CoachLocalOwnership.snapshotDigest(localContainer.mainContext)
        let contentLatest = try CoachLocalOwnership.snapshotDigest(freshSource)
        guard before == after, before == latest, contentBefore == contentAfter,
              contentBefore == contentLatest, !sourceContainer.mainContext.hasChanges else {
            throw CoachLocalOwnership.OwnershipError.unavailable("Records changed while preparing the local copy. Nothing was switched. Please retry.")
        }
        try select(destination, source)
        WearableWorkoutInboxService.retireLocalStore(sourceContainer)
        container = localContainer
        isCloudBacked = false
        isCoachLocal = true
        storageGeneration = UUID()
    }

    /// The signature changes after imports, cloud merges, library edits, or a
    /// maintenance-version bump. Only successful maintenance advances the gate.
    func reconcileExerciseLibraryIfNeeded(force: Bool = false) {
        let context = container.mainContext
        let key = "exerciseLibrary.maintenance.v1"
        func signature() throws -> String {
            let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>())
            let rows = definitions.map {
                "\($0.id.uuidString)|\($0.name)|\($0.muscleGroup)|\($0.isUserDefined)"
            }.sorted().joined(separator: "\n")
            return SHA256.hash(data: Data(rows.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        guard let before = try? signature() else { return }
        guard force || UserDefaults.standard.string(forKey: key) != before else { return }
        ExerciseLibrary.populateInitialExercises(context: context)
        deduplicateExerciseDefinitions()
        ensureDefaultExercisesPresent()
        unifySynonymousExerciseDefinitions()
        guard PersistenceSave.commit(context, action: "maintain exercise library"),
              let after = try? signature() else { return }
        UserDefaults.standard.set(after, forKey: key)
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
