import Foundation
import SwiftData

struct BackupFile: Codable {
    struct ExerciseDefinitionDTO: Codable { let id: UUID; let name: String; let muscleGroup: String; let isUserDefined: Bool }
    struct WorkoutSessionDTO: Codable { let id: UUID; let date: Date; let notes: String?; let title: String? }
    struct ExerciseLogDTO: Codable { let id: UUID; let reps: Int; let weight: Double; let weightUnit: String; let setNumber: Int; let exerciseName: String?; let exerciseDefinitionId: UUID?; let workoutSessionId: UUID? }
    struct RunningSessionDTO: Codable { let id: UUID; let date: Date; let distance: Double; let distanceUnit: String; let duration: TimeInterval; let calories: Double?; let notes: String?; let locations: Data; let healthWorkoutUUID: String? }
    struct WeightEntryDTO: Codable { let id: UUID; let date: Date; let weight: Double; let weightUnit: String }

    var exportedAt: Date
    var exerciseDefinitions: [ExerciseDefinitionDTO]
    var workoutSessions: [WorkoutSessionDTO]
    var exerciseLogs: [ExerciseLogDTO]
    var runningSessions: [RunningSessionDTO]
    var weightEntries: [WeightEntryDTO]
}

@MainActor
enum DataBackupService {
    static func exportAll(context: ModelContext) throws -> URL {
        // Fetch all entities
        let defs: [ExerciseDefinition] = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let sessions: [WorkoutSession] = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let logs: [ExerciseLog] = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let weights: [WeightEntry] = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []

        let file = BackupFile(
            exportedAt: Date(),
            exerciseDefinitions: defs.map { .init(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, isUserDefined: $0.isUserDefined) },
            workoutSessions: sessions.map { .init(id: $0.id, date: $0.date, notes: $0.notes, title: $0.title) },
            exerciseLogs: logs.map { .init(id: $0.id, reps: $0.reps, weight: $0.weight, weightUnit: $0.weightUnit, setNumber: $0.setNumber, exerciseName: $0.exerciseName, exerciseDefinitionId: $0.exerciseDefinition?.id, workoutSessionId: $0.workoutSession?.id) },
            runningSessions: runs.map { .init(id: $0.id, date: $0.date, distance: $0.distance, distanceUnit: $0.distanceUnit, duration: $0.duration, calories: $0.calories, notes: $0.notes, locations: $0.locations, healthWorkoutUUID: $0.healthWorkoutUUID) },
            weightEntries: weights.map { .init(id: $0.id, date: $0.date, weight: $0.weight, weightUnit: $0.weightUnit) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(file)

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "WorkingOut-Backup-\(formatter.string(from: Date())).json"
        let url = tmp.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func `import`(from url: URL, context: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(BackupFile.self, from: data)

        // Build existing index to avoid duplicates on repeated imports
        let existingDefs = ((try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? [])
        let existingDefIDs = Set(existingDefs.map { $0.id })
        var defsByNameGroup: [String: ExerciseDefinition] = {
            var map: [String: ExerciseDefinition] = [:]
            for d in existingDefs {
                let key = (d.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) + "||" + d.muscleGroup.lowercased()
                // Prefer built-ins (isUserDefined == false)
                if let cur = map[key] {
                    if !d.isUserDefined && cur.isUserDefined { map[key] = d }
                } else { map[key] = d }
            }
            return map
        }()
        let existingSessionIDs = Set(((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map { $0.id })
        let existingLogIDs = Set(((try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []).map { $0.id })
        let existingRunIDs = Set(((try? context.fetch(FetchDescriptor<RunningSession>())) ?? []).map { $0.id })
        let existingWeightIDs = Set(((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []).map { $0.id })

        // Insert definitions
        var defsById: [UUID: ExerciseDefinition] = [:]
        for dto in file.exerciseDefinitions {
            if existingDefIDs.contains(dto.id) {
                // fetch existing by id
                let pred = #Predicate<ExerciseDefinition> { $0.id == dto.id }
                let fd = FetchDescriptor<ExerciseDefinition>(predicate: pred)
                if let existing = try? context.fetch(fd).first { defsById[dto.id] = existing }
                continue
            }
            let key = dto.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "||" + dto.muscleGroup.lowercased()
            if let existingByName = defsByNameGroup[key] {
                // Reuse existing built-in (or whichever is present) to avoid duplicates
                defsById[dto.id] = existingByName
                continue
            }
            let model = ExerciseDefinition(id: dto.id, name: dto.name, muscleGroup: dto.muscleGroup, isUserDefined: dto.isUserDefined)
            context.insert(model)
            defsById[dto.id] = model
            defsByNameGroup[key] = model
        }

        // Insert sessions
        var sessionsById: [UUID: WorkoutSession] = [:]
        for dto in file.workoutSessions {
            if existingSessionIDs.contains(dto.id) {
                let pred = #Predicate<WorkoutSession> { $0.id == dto.id }
                let fd = FetchDescriptor<WorkoutSession>(predicate: pred)
                if let existing = try? context.fetch(fd).first { sessionsById[dto.id] = existing }
                continue
            }
            let model = WorkoutSession(id: dto.id, date: dto.date, notes: dto.notes, title: dto.title ?? nil)
            context.insert(model)
            sessionsById[dto.id] = model
        }

        // Insert logs (after definitions and sessions)
        for dto in file.exerciseLogs {
            if existingLogIDs.contains(dto.id) { continue }
            let model = ExerciseLog(id: dto.id, reps: dto.reps, weight: dto.weight, weightUnit: dto.weightUnit, setNumber: dto.setNumber, exerciseName: dto.exerciseName)
            if let defId = dto.exerciseDefinitionId, let resolved = defsById[defId] {
                model.exerciseDefinition = resolved
            } else if let name = dto.exerciseName {
                let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "||" + (resolvedMuscleGroupForName(name) ?? "")
                model.exerciseDefinition = defsByNameGroup[key]
            }
            if let sessionId = dto.workoutSessionId, let sess = sessionsById[sessionId] {
                model.workoutSession = sess
                if var arr = sess.exerciseLogs {
                    arr.append(model)
                    sess.exerciseLogs = arr
                } else {
                    sess.exerciseLogs = [model]
                }
            }
            context.insert(model)
        }

        // Insert runs
        for dto in file.runningSessions {
            if existingRunIDs.contains(dto.id) { continue }
            let model = RunningSession(id: dto.id, date: dto.date, distance: dto.distance, distanceUnit: dto.distanceUnit, duration: dto.duration, calories: dto.calories, notes: dto.notes, locations: dto.locations, healthWorkoutUUID: dto.healthWorkoutUUID)
            context.insert(model)
        }

        // Insert weights
        for dto in file.weightEntries {
            if existingWeightIDs.contains(dto.id) { continue }
            let model = WeightEntry(id: dto.id, date: dto.date, weight: dto.weight, weightUnit: dto.weightUnit)
            context.insert(model)
        }

        try context.save()
    }

    // Heuristic: try to look up a muscle group by name among known defs
    private static func resolvedMuscleGroupForName(_ name: String) -> String? {
        // This helper is used only during import to form a key in the absence of explicit muscle group.
        // We keep a small mapping fallback (can be expanded or loaded from current store if needed).
        let map: [String: String] = [
            "bench press": "Chest", "incline bench press": "Chest", "squats": "Legs", "deadlifts": "Back",
        ]
        return map[name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}
