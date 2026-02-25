import Foundation
import SwiftData

struct BackupFile: Codable {
    struct ExerciseDefinitionDTO: Codable {
        let id: UUID
        let name: String
        let muscleGroup: String
        let isUserDefined: Bool
    }

    struct WorkoutSessionDTO: Codable {
        let id: UUID
        let date: Date
        let notes: String?
        let title: String?
    }

    struct ExerciseLogDTO: Codable {
        let id: UUID
        let reps: Int
        let weight: Double
        let weightUnit: String
        let setNumber: Int
        let exerciseName: String?
        let exerciseDefinitionId: UUID?
        let workoutSessionId: UUID?
    }

    struct RunningSessionDTO: Codable {
        let id: UUID
        let date: Date
        let distance: Double
        let distanceUnit: String
        let duration: TimeInterval
        let calories: Double?
        let notes: String?
        let locations: Data
        let healthWorkoutUUID: String?
        let activityType: String
    }

    struct WeightEntryDTO: Codable {
        let id: UUID
        let date: Date
        let weight: Double
        let weightUnit: String
    }

    struct RunningPlanDTO: Codable {
        let id: UUID
        let name: String
        let source: String
        let style: String
        let targetDistanceMeters: Double
        let primaryGoal: String
        let durationWeeks: Int
        let daysPerWeek: Int
        let startDate: Date
        let isActive: Bool
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
        let profileSnapshotJSON: String?
        let aiPrompt: String?
    }

    struct RunningPlanSessionDTO: Codable {
        let id: UUID
        let planId: UUID?
        let weekIndex: Int
        let dayIndex: Int
        let scheduledDate: Date?
        let sessionType: String
        let targetDistanceMeters: Double?
        let targetDurationSeconds: Double?
        let targetPaceMinPerMile: Double?
        let intensityLevel: String
        let notes: String?
        let status: String
        let completionSource: String?
        let completedAt: Date?
        let completedRunSessionID: UUID?
    }

    struct AIConversationDTO: Codable {
        let id: UUID
        let date: Date
        let mode: String
        let goal: String
        let prompt: String
        let response: String
        let model: String
        let structuredPlanJSON: String?
    }

    struct WorkoutTemplateDTO: Codable {
        let id: UUID
        let title: String
        let notes: String?
        let createdDate: Date
        let sourceAIConversationId: UUID?
        let importSourceSessionID: UUID?
        let exerciseCount: Int
        let aiPlanHash: String?
        let aiPlanTitle: String?
        let aiWeekTitle: String?
        let aiDayIndex: Int?
        let aiDayType: String?
        let aiDayTitle: String?
        let sourceSessionId: UUID?
        let isBuiltIn: Bool
        let experienceLevel: String?
        let goal: String?
        let difficulty: Int?
        let estimatedDuration: Int?
        let equipment: [String]?
        let muscleGroups: [String]?
        let templateDescription: String?
    }

    struct TemplateExerciseDTO: Codable {
        let id: UUID
        let name: String
        let order: Int
        let sets: Int
        let reps: Int
        let suggestedWeight: Double?
        let weightUnit: String
        let notes: String?
        let templateId: UUID?
    }

    var formatVersion: Int? = 2
    var exportedAt: Date
    var exerciseDefinitions: [ExerciseDefinitionDTO]
    var workoutSessions: [WorkoutSessionDTO]
    var exerciseLogs: [ExerciseLogDTO]
    var runningSessions: [RunningSessionDTO]
    var weightEntries: [WeightEntryDTO]
    var runningPlans: [RunningPlanDTO]?
    var runningPlanSessions: [RunningPlanSessionDTO]?
    var aiConversations: [AIConversationDTO]?
    var workoutTemplates: [WorkoutTemplateDTO]?
    var templateExercises: [TemplateExerciseDTO]?
}

@MainActor
enum DataBackupService {
    static func exportAll(context: ModelContext) throws -> URL {
        let defs: [ExerciseDefinition] = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let sessions: [WorkoutSession] = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let logs: [ExerciseLog] = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let weights: [WeightEntry] = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let plans: [RunningPlan] = (try? context.fetch(FetchDescriptor<RunningPlan>())) ?? []
        let planSessions: [RunningPlanSession] = (try? context.fetch(FetchDescriptor<RunningPlanSession>())) ?? []
        let conversations: [AIConversation] = (try? context.fetch(FetchDescriptor<AIConversation>())) ?? []
        let templates: [WorkoutTemplate] = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        let templateExercises: [TemplateExercise] = (try? context.fetch(FetchDescriptor<TemplateExercise>())) ?? []

        let file = BackupFile(
            exportedAt: Date(),
            exerciseDefinitions: defs.map { .init(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, isUserDefined: $0.isUserDefined) },
            workoutSessions: sessions.map { .init(id: $0.id, date: $0.date, notes: $0.notes, title: $0.title) },
            exerciseLogs: logs.map {
                .init(
                    id: $0.id,
                    reps: $0.reps,
                    weight: $0.weight,
                    weightUnit: $0.weightUnit,
                    setNumber: $0.setNumber,
                    exerciseName: $0.exerciseName,
                    exerciseDefinitionId: $0.exerciseDefinition?.id,
                    workoutSessionId: $0.workoutSession?.id
                )
            },
            runningSessions: runs.map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    distance: $0.distance,
                    distanceUnit: $0.distanceUnit,
                    duration: $0.duration,
                    calories: $0.calories,
                    notes: $0.notes,
                    locations: $0.locations,
                    healthWorkoutUUID: $0.healthWorkoutUUID,
                    activityType: $0.activityType
                )
            },
            weightEntries: weights.map { .init(id: $0.id, date: $0.date, weight: $0.weight, weightUnit: $0.weightUnit) },
            runningPlans: plans.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    source: $0.source,
                    style: $0.style,
                    targetDistanceMeters: $0.targetDistanceMeters,
                    primaryGoal: $0.primaryGoal,
                    durationWeeks: $0.durationWeeks,
                    daysPerWeek: $0.daysPerWeek,
                    startDate: $0.startDate,
                    isActive: $0.isActive,
                    isArchived: $0.isArchived,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    profileSnapshotJSON: $0.profileSnapshotJSON,
                    aiPrompt: $0.aiPrompt
                )
            },
            runningPlanSessions: planSessions.map {
                .init(
                    id: $0.id,
                    planId: $0.plan?.id,
                    weekIndex: $0.weekIndex,
                    dayIndex: $0.dayIndex,
                    scheduledDate: $0.scheduledDate,
                    sessionType: $0.sessionType,
                    targetDistanceMeters: $0.targetDistanceMeters,
                    targetDurationSeconds: $0.targetDurationSeconds,
                    targetPaceMinPerMile: $0.targetPaceMinPerMile,
                    intensityLevel: $0.intensityLevel,
                    notes: $0.notes,
                    status: $0.status,
                    completionSource: $0.completionSource,
                    completedAt: $0.completedAt,
                    completedRunSessionID: $0.completedRunSessionID
                )
            },
            aiConversations: conversations.map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    mode: $0.mode,
                    goal: $0.goal,
                    prompt: $0.prompt,
                    response: $0.response,
                    model: $0.model,
                    structuredPlanJSON: $0.structuredPlanJSON
                )
            },
            workoutTemplates: templates.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    notes: $0.notes,
                    createdDate: $0.createdDate,
                    sourceAIConversationId: $0.sourceAIConversationId,
                    importSourceSessionID: $0.importSourceSessionID,
                    exerciseCount: $0.exerciseCount,
                    aiPlanHash: $0.aiPlanHash,
                    aiPlanTitle: $0.aiPlanTitle,
                    aiWeekTitle: $0.aiWeekTitle,
                    aiDayIndex: $0.aiDayIndex,
                    aiDayType: $0.aiDayType,
                    aiDayTitle: $0.aiDayTitle,
                    sourceSessionId: $0.sourceSession?.id,
                    isBuiltIn: $0.isBuiltIn,
                    experienceLevel: $0.experienceLevel,
                    goal: $0.goal,
                    difficulty: $0.difficulty,
                    estimatedDuration: $0.estimatedDuration,
                    equipment: $0.equipment,
                    muscleGroups: $0.muscleGroups,
                    templateDescription: $0.templateDescription
                )
            },
            templateExercises: templateExercises.map {
                .init(
                    id: $0.id,
                    name: $0.name,
                    order: $0.order,
                    sets: $0.sets,
                    reps: $0.reps,
                    suggestedWeight: $0.suggestedWeight,
                    weightUnit: $0.weightUnit,
                    notes: $0.notes,
                    templateId: $0.template?.id
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(file)

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "Pace&Plates-Backup-\(formatter.string(from: Date())).json"
        let url = tmp.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func `import`(from url: URL, context: ModelContext) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(BackupFile.self, from: data)

        let existingDefs = (try? context.fetch(FetchDescriptor<ExerciseDefinition>())) ?? []
        let existingDefIDs = Set(existingDefs.map(\.id))
        var defsByNameGroup: [String: ExerciseDefinition] = {
            var map: [String: ExerciseDefinition] = [:]
            for definition in existingDefs {
                let key = definition.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "||" + definition.muscleGroup.lowercased()
                if let current = map[key] {
                    if !definition.isUserDefined && current.isUserDefined { map[key] = definition }
                } else {
                    map[key] = definition
                }
            }
            return map
        }()

        var existingSessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let existingSessionIDs = Set(existingSessions.map(\.id))
        let existingLogIDs = Set(((try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []).map(\.id))
        var existingRuns = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let existingRunIDs = Set(existingRuns.map(\.id))
        var existingWeights = (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []
        let existingWeightIDs = Set(existingWeights.map(\.id))
        let existingPlanIDs = Set(((try? context.fetch(FetchDescriptor<RunningPlan>())) ?? []).map(\.id))
        let existingPlanSessionIDs = Set(((try? context.fetch(FetchDescriptor<RunningPlanSession>())) ?? []).map(\.id))
        let existingConversationIDs = Set(((try? context.fetch(FetchDescriptor<AIConversation>())) ?? []).map(\.id))
        let existingTemplateIDs = Set(((try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []).map(\.id))
        let existingTemplateExerciseIDs = Set(((try? context.fetch(FetchDescriptor<TemplateExercise>())) ?? []).map(\.id))

        var defsById: [UUID: ExerciseDefinition] = [:]
        for dto in file.exerciseDefinitions {
            if existingDefIDs.contains(dto.id) {
                let pred = #Predicate<ExerciseDefinition> { $0.id == dto.id }
                if let existing = try? context.fetch(FetchDescriptor<ExerciseDefinition>(predicate: pred)).first {
                    defsById[dto.id] = existing
                }
                continue
            }

            let key = dto.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "||" + dto.muscleGroup.lowercased()
            if let existingByName = defsByNameGroup[key] {
                defsById[dto.id] = existingByName
                continue
            }

            let model = ExerciseDefinition(id: dto.id, name: dto.name, muscleGroup: dto.muscleGroup, isUserDefined: dto.isUserDefined)
            context.insert(model)
            defsById[dto.id] = model
            defsByNameGroup[key] = model
        }

        var sessionsById: [UUID: WorkoutSession] = [:]
        for dto in file.workoutSessions {
            if existingSessionIDs.contains(dto.id) {
                let pred = #Predicate<WorkoutSession> { $0.id == dto.id }
                if let existing = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: pred)).first {
                    sessionsById[dto.id] = existing
                }
                continue
            }

            if let similar = existingSessions.first(where: { abs($0.date.timeIntervalSince(dto.date)) < 120 }) {
                sessionsById[dto.id] = similar
                continue
            }

            let model = WorkoutSession(id: dto.id, date: dto.date, notes: dto.notes, title: dto.title)
            context.insert(model)
            sessionsById[dto.id] = model
            existingSessions.append(model)
        }

        for dto in file.exerciseLogs {
            if existingLogIDs.contains(dto.id) { continue }
            let model = ExerciseLog(
                id: dto.id,
                reps: dto.reps,
                weight: dto.weight,
                weightUnit: dto.weightUnit,
                setNumber: dto.setNumber,
                exerciseName: dto.exerciseName
            )

            if let defId = dto.exerciseDefinitionId, let resolved = defsById[defId] {
                model.exerciseDefinition = resolved
            } else if let name = dto.exerciseName {
                let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + "||" + (resolvedMuscleGroupForName(name) ?? "")
                model.exerciseDefinition = defsByNameGroup[key]
            }

            if let sessionId = dto.workoutSessionId, let session = sessionsById[sessionId] {
                model.workoutSession = session
                if var arr = session.exerciseLogs {
                    arr.append(model)
                    session.exerciseLogs = arr
                } else {
                    session.exerciseLogs = [model]
                }
            }

            context.insert(model)
        }

        var existingRunUUIDs = Set(existingRuns.compactMap { run -> String? in
            guard let uuid = run.healthWorkoutUUID, !uuid.isEmpty else { return nil }
            return uuid
        })

        for dto in file.runningSessions {
            if existingRunIDs.contains(dto.id) { continue }
            if let healthUUID = dto.healthWorkoutUUID, !healthUUID.isEmpty, existingRunUUIDs.contains(healthUUID) {
                continue
            }

            let isSimilar = existingRuns.contains { existing in
                let dateDiff = abs(existing.date.timeIntervalSince(dto.date))
                let distanceDiff = abs(existing.distance - dto.distance)
                let durationDiff = abs(existing.duration - dto.duration)
                return dateDiff < 120
                    && existing.distanceUnit == dto.distanceUnit
                    && distanceDiff < 0.07
                    && durationDiff < 30
            }
            if isSimilar { continue }

            let model = RunningSession(
                id: dto.id,
                date: dto.date,
                distance: dto.distance,
                distanceUnit: dto.distanceUnit,
                duration: dto.duration,
                calories: dto.calories,
                notes: dto.notes,
                locations: dto.locations,
                healthWorkoutUUID: dto.healthWorkoutUUID,
                activityType: dto.activityType
            )
            context.insert(model)
            existingRuns.append(model)
            if let uuid = dto.healthWorkoutUUID, !uuid.isEmpty {
                existingRunUUIDs.insert(uuid)
            }
        }

        for dto in file.weightEntries {
            if existingWeightIDs.contains(dto.id) { continue }

            let isSimilar = existingWeights.contains { existing in
                let sameDay = Calendar.current.isDate(existing.date, inSameDayAs: dto.date)
                let weightDiff = abs(existing.weight - dto.weight)
                return sameDay && existing.weightUnit == dto.weightUnit && weightDiff < 0.5
            }
            if isSimilar { continue }

            let model = WeightEntry(id: dto.id, date: dto.date, weight: dto.weight, weightUnit: dto.weightUnit)
            context.insert(model)
            existingWeights.append(model)
        }

        var plansById: [UUID: RunningPlan] = [:]
        for dto in file.runningPlans ?? [] {
            if existingPlanIDs.contains(dto.id) {
                let pred = #Predicate<RunningPlan> { $0.id == dto.id }
                if let existing = try? context.fetch(FetchDescriptor<RunningPlan>(predicate: pred)).first {
                    plansById[dto.id] = existing
                }
                continue
            }

            let plan = RunningPlan(
                id: dto.id,
                name: dto.name,
                source: dto.source,
                style: dto.style,
                targetDistanceMeters: dto.targetDistanceMeters,
                primaryGoal: dto.primaryGoal,
                durationWeeks: dto.durationWeeks,
                daysPerWeek: dto.daysPerWeek,
                startDate: dto.startDate,
                isActive: dto.isActive,
                isArchived: dto.isArchived,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                profileSnapshotJSON: dto.profileSnapshotJSON,
                aiPrompt: dto.aiPrompt
            )
            context.insert(plan)
            plansById[dto.id] = plan
        }

        for dto in file.runningPlanSessions ?? [] {
            if existingPlanSessionIDs.contains(dto.id) { continue }
            let session = RunningPlanSession(
                id: dto.id,
                plan: dto.planId.flatMap { plansById[$0] },
                weekIndex: dto.weekIndex,
                dayIndex: dto.dayIndex,
                scheduledDate: dto.scheduledDate,
                sessionType: dto.sessionType,
                targetDistanceMeters: dto.targetDistanceMeters,
                targetDurationSeconds: dto.targetDurationSeconds,
                targetPaceMinPerMile: dto.targetPaceMinPerMile,
                intensityLevel: dto.intensityLevel,
                notes: dto.notes,
                status: dto.status,
                completionSource: dto.completionSource,
                completedAt: dto.completedAt,
                completedRunSessionID: dto.completedRunSessionID
            )
            context.insert(session)
        }

        for dto in file.aiConversations ?? [] {
            if existingConversationIDs.contains(dto.id) { continue }
            let conversation = AIConversation(
                id: dto.id,
                date: dto.date,
                mode: dto.mode,
                goal: dto.goal,
                prompt: dto.prompt,
                response: dto.response,
                model: dto.model,
                structuredPlanJSON: dto.structuredPlanJSON
            )
            context.insert(conversation)
        }

        var templatesById: [UUID: WorkoutTemplate] = [:]
        for dto in file.workoutTemplates ?? [] {
            if existingTemplateIDs.contains(dto.id) {
                let pred = #Predicate<WorkoutTemplate> { $0.id == dto.id }
                if let existing = try? context.fetch(FetchDescriptor<WorkoutTemplate>(predicate: pred)).first {
                    templatesById[dto.id] = existing
                }
                continue
            }

            let template = WorkoutTemplate(
                id: dto.id,
                title: dto.title,
                notes: dto.notes,
                createdDate: dto.createdDate,
                sourceAIConversationId: dto.sourceAIConversationId,
                importSourceSessionID: dto.importSourceSessionID,
                exerciseCount: dto.exerciseCount,
                aiPlanHash: dto.aiPlanHash,
                aiPlanTitle: dto.aiPlanTitle,
                aiWeekTitle: dto.aiWeekTitle,
                aiDayIndex: dto.aiDayIndex,
                aiDayType: dto.aiDayType,
                aiDayTitle: dto.aiDayTitle,
                isBuiltIn: dto.isBuiltIn,
                experienceLevel: dto.experienceLevel,
                goal: dto.goal,
                difficulty: dto.difficulty,
                estimatedDuration: dto.estimatedDuration,
                equipment: dto.equipment,
                muscleGroups: dto.muscleGroups,
                templateDescription: dto.templateDescription
            )
            if let sourceSessionId = dto.sourceSessionId {
                template.sourceSession = sessionsById[sourceSessionId]
            }
            context.insert(template)
            templatesById[dto.id] = template
        }

        for dto in file.templateExercises ?? [] {
            if existingTemplateExerciseIDs.contains(dto.id) { continue }
            let exercise = TemplateExercise(
                id: dto.id,
                name: dto.name,
                order: dto.order,
                sets: dto.sets,
                reps: dto.reps,
                suggestedWeight: dto.suggestedWeight,
                weightUnit: dto.weightUnit,
                notes: dto.notes
            )
            if let templateId = dto.templateId, let template = templatesById[templateId] {
                exercise.template = template
                if var arr = template.exercises {
                    arr.append(exercise)
                    template.exercises = arr
                } else {
                    template.exercises = [exercise]
                }
            }
            context.insert(exercise)
        }

        try context.save()
    }

    private static func resolvedMuscleGroupForName(_ name: String) -> String? {
        let map: [String: String] = [
            "bench press": "Chest",
            "incline bench press": "Chest",
            "squats": "Legs",
            "deadlifts": "Back"
        ]
        return map[name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}
