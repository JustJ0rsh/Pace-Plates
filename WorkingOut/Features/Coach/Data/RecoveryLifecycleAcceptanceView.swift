#if DEBUG
import SwiftUI
import SwiftData

/// A process boundary probe for a disposable Simulator installation. It never
/// opens CloudKit and is unavailable without the explicit isolated fixture.
struct RecoveryLifecycleAcceptanceView: View {
    @State private var result = "Checking recovery lifecycle…"
    @State private var started = false

    var body: some View {
        Text(result)
            .padding()
            .accessibilityIdentifier("recovery.lifecycle.result")
            .task {
                guard !started else { return }
                started = true
                result = await RecoveryLifecycleAcceptance.run()
            }
    }
}

@MainActor
private enum RecoveryLifecycleAcceptance {
    enum Phase: String {
        case retained, reinstalled251, export, empty, restore, reopened
    }
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let text) = self { return text }
            return nil
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var receipts: URL { documents.appendingPathComponent("RecoveryAudit", isDirectory: true) }
    static var backup: URL { documents.appendingPathComponent("recovery-before-reinstall.pacebackup") }
    static func id(_ suffix: String) -> UUID {
        UUID(uuidString: "7E570000-0000-4000-8000-0000000000" + suffix)!
    }

    static func run() async -> String {
        var receipt = ["scope": "Disposable Simulator; CloudKit disabled", "result": "failed"]
        let environment = ProcessInfo.processInfo.environment
        guard let phase = environment["UITEST_RECOVERY_PHASE"].flatMap(Phase.init(rawValue:)),
              environment["UITEST_RECOVERY_SCOPE"].flatMap(UUID.init(uuidString:)) != nil,
              AppLaunchConfiguration.current.usesIsolatedStore,
              AppLaunchConfiguration.current.fixtureName == "recovery_lifecycle" else {
            return "FAIL: An explicit isolated lifecycle fixture and UUID scope are required."
        }
        receipt["phase"] = phase.rawValue
        do {
            #if !targetEnvironment(simulator)
            throw Failure.invalid("This lifecycle probe is Simulator-only.")
            #else
            let legacy = ModelConfiguration(schema: Schema(PersistenceController.legacyModelTypes), cloudKitDatabase: .none).url
            let coach = try CloudSyncRestoration.prepare(legacyURL: legacy, ownershipRoot: CoachLocalOwnership.root)
            let container = try CloudSyncRestoration.makeContainer(legacyURL: legacy, coachURL: coach, cloudKitMode: .none)
            let context = container.mainContext
            switch phase {
            case .retained:
                try verifyHistorical(context)
                receipt["verified"] = "Five historical identities, original values, exact links and 2.5 MB route preserved after actual installed updates."
            case .reinstalled251:
                try verifyPostReinstall(context)
                try seedDuplicateGraph(context)
                try verifyDuplicateGraph(context)
                receipt["verified"] = "Post-reinstall weight and Coach entry retained through update; original deleted records absent; duplicate graph seeded."
            case .export:
                try verifyPostReinstall(context)
                try verifyDuplicateGraph(context)
                let temporary = try await DataBackupService.exportAll(context: context, includePhotos: false)
                if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
                try FileManager.default.copyItem(at: temporary, to: backup)
                try FileManager.default.removeItem(at: temporary)
                receipt["verified"] = "Actual backup export saved for copying outside the app before OS uninstall."
                receipt["backupBytes"] = String(try Data(contentsOf: backup).count)
            case .empty:
                try require(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0, "Fresh reinstall contains an unexpected workout")
                try require(try context.fetchCount(FetchDescriptor<RunningSession>()) == 0, "Fresh reinstall contains an unexpected run")
                try require(try context.fetchCount(FetchDescriptor<WeightEntry>()) == 0, "Fresh reinstall contains an unexpected weight")
                try require(try context.fetchCount(FetchDescriptor<CoachNutritionLog>()) == 0, "Fresh reinstall contains an unexpected Coach entry")
                receipt["verified"] = "Actual OS uninstall removed old app-local records; fresh container opens empty."
            case .restore:
                try await DataBackupService.import(from: backup, context: context)
                try verifyPostReinstall(context)
                try verifyDuplicateGraph(context)
                let first = try counts(context)
                try await DataBackupService.import(from: backup, context: context)
                try require(try counts(context) == first, "Repeated import created extra rows")
                try verifyDuplicateGraph(context)
                receipt["verified"] = "Actual saved-file import restores UUID duplicates and exact relationships after OS reinstall; repeat import is idempotent."
            case .reopened:
                try verifyPostReinstall(context)
                try verifyDuplicateGraph(context)
                receipt["verified"] = "Restored history and links survive another process launch and installed update."
            }
            receipt["counts"] = try counts(context).map(String.init).joined(separator: ",")
            receipt["result"] = "passed"
            #endif
        } catch {
            receipt["message"] = error.localizedDescription
        }
        do {
            try FileManager.default.createDirectory(at: receipts, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(receipt).write(to: receipts.appendingPathComponent(phase.rawValue + ".json"), options: .atomic)
        } catch { return "FAIL: Could not save lifecycle evidence: \(error.localizedDescription)" }
        return receipt["result"] == "passed" ? "PASS: \(receipt["verified"] ?? phase.rawValue)" : "FAIL: \(receipt["message"] ?? phase.rawValue)"
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.invalid(message) }
    }

    private static func manifest(_ name: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(contentsOf: receipts.appendingPathComponent(name)))
    }

    private static func verifyHistorical(_ context: ModelContext) throws {
        let expected = try manifest("expected.json")
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
        let runs = try context.fetch(FetchDescriptor<RunningSession>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        guard let workout = workouts.first(where: { $0.id.uuidString == expected["workout"] }),
              let log = logs.first(where: { $0.id.uuidString == expected["log"] }),
              let run = runs.first(where: { $0.id.uuidString == expected["run"] }),
              let weight = weights.first(where: { $0.id.uuidString == expected["weight"] }) else {
            throw Failure.invalid("An original historical identity is missing")
        }
        try require(workout.notes == "Original old workout" && log.reps == 8 && !log.isCompleted, "Historical workout/set values changed")
        try require(log.workoutSession?.persistentModelID == workout.persistentModelID && log.exerciseDefinition?.id.uuidString == expected["definition"], "Historical physical relationships changed")
        let route = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 17) })
        try require(run.locations == route && run.duration == 700 && run.distance == 2, "Historical route or run values changed")
        try require(weight.weight == 77 && weight.weightUnit == "kg", "Historical weight changed")
    }

    private static func verifyPostReinstall(_ context: ModelContext) throws {
        let expected = try manifest("post-reinstall.json")
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let nutrition = try context.fetch(FetchDescriptor<CoachNutritionLog>())
        try require(weights.contains { $0.id.uuidString == expected["weight"] && $0.weight == 88 && $0.weightUnit == "kg" }, "Post-reinstall weight was lost or changed")
        try require(nutrition.contains { $0.id.uuidString == expected["nutrition"] && $0.protein == 150 }, "Post-reinstall Coach entry was lost or changed")
        if let old = try? manifest("expected.json") {
            try require(!weights.contains { $0.id.uuidString == old["weight"] }, "Deleted old weight was unexpectedly recreated offline")
            try require(!context.fetch(FetchDescriptor<RunningSession>()).contains { $0.id.uuidString == old["run"] }, "Deleted old run was unexpectedly recreated offline")
        }
    }

    private static func seedDuplicateGraph(_ context: ModelContext) throws {
        guard try !context.fetch(FetchDescriptor<RunningSession>()).contains(where: { $0.id == id("01") }) else { return }
        for index in 0..<2 {
            let name = index == 0 ? "Lifecycle left" : "Lifecycle right"
            let workout = WorkoutSession(id: id(index == 0 ? "02" : "03"), notes: name, title: name)
            let definition = ExerciseDefinition(id: id("04"), name: name, muscleGroup: "Chest", isUserDefined: true)
            let log = ExerciseLog(id: id("05"), reps: 8 + index, weight: Double(40 + index), weightUnit: "kg", setNumber: 1, exerciseName: name)
            log.workoutSession = workout; log.exerciseDefinition = definition
            let run = RunningSession(id: id("01"), distance: Double(3 + index), distanceUnit: "km", duration: Double(900 + index), notes: name, locations: Data(repeating: UInt8(index + 1), count: 4_096))
            context.insert(workout); context.insert(definition); context.insert(log); context.insert(run)
        }
        try context.save()
    }

    private static func verifyDuplicateGraph(_ context: ModelContext) throws {
        let runs = try context.fetch(FetchDescriptor<RunningSession>()).filter { $0.id == id("01") }
        let definitions = try context.fetch(FetchDescriptor<ExerciseDefinition>()).filter { $0.id == id("04") }
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>()).filter { $0.id == id("05") }
        try require(runs.count == 2 && definitions.count == 2 && logs.count == 2, "Distinct duplicate-UUID rows were lost or multiplied")
        try require(Set(runs.map(\.persistentModelID)).count == 2 && Set(definitions.map(\.persistentModelID)).count == 2, "Physical identities were conflated")
        for index in 0..<2 {
            let name = index == 0 ? "Lifecycle left" : "Lifecycle right"
            guard let run = runs.first(where: { $0.notes == name }), let log = logs.first(where: { $0.exerciseName == name }) else {
                throw Failure.invalid("A duplicate record payload is missing")
            }
            try require(run.distance == Double(3 + index) && run.locations == Data(repeating: UInt8(index + 1), count: 4_096), "Duplicate run payload changed")
            try require(log.reps == 8 + index && log.weight == Double(40 + index), "Duplicate set actuals changed")
            try require(log.workoutSession?.title == name && log.exerciseDefinition?.name == name, "Duplicate relationship targets were conflated")
        }
    }

    private static func counts(_ context: ModelContext) throws -> [Int] {
        [try context.fetchCount(FetchDescriptor<WorkoutSession>()), try context.fetchCount(FetchDescriptor<ExerciseDefinition>()),
         try context.fetchCount(FetchDescriptor<ExerciseLog>()), try context.fetchCount(FetchDescriptor<RunningSession>()),
         try context.fetchCount(FetchDescriptor<WeightEntry>()), try context.fetchCount(FetchDescriptor<CoachNutritionLog>())]
    }
}
#endif
