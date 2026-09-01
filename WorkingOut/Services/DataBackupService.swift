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
        // Added in v3. Optional so v1/v2 backups remain decodable.
        let shouldSaveAsTemplate: Bool?
        let sourceTemplateID: UUID?
        let generatedTemplateID: UUID?
        let isSampleData: Bool?
        let healthWorkoutUUID: String?
        let healthDuration: TimeInterval?
        let healthCalories: Double?
        let healthAvgHeartRate: Double?
        let healthSourceName: String?
        let healthActivityType: String?
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
        // Added in v3. Optional so v1/v2 backups remain decodable.
        let exerciseOrder: Int?
        let exerciseType: String?
        let durationSeconds: Int?
        let distance: Double?
        let distanceUnit: String?
        let caloriesBurned: Int?
        let avgHeartRate: Int?
        let notes: String?
        let isCompleted: Bool?
        let isIsolated: Bool?
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
        // Added in v4. Optional so older backups remain decodable.
        let metricSourceHealthWorkoutUUID: String?
        let linkedHealthWorkoutUUIDsRaw: String?
        let healthMetricSourceName: String?
        let plannedSessionID: UUID?
        let activityType: String
        // Added in v3. Optional so v1/v2 backups remain decodable.
        let isSampleData: Bool?
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let minHeartRate: Double?
        let avgCadence: Double?
        let maxCadence: Double?
        let avgStrideLength: Double?
        let verticalOscillation: Double?
        let groundContactTime: Double?
        let totalAscent: Double?
        let totalDescent: Double?
        let minElevation: Double?
        let maxElevation: Double?
        let avgPower: Double?
        let maxPower: Double?
    }

    struct HealthWorkoutInboxItemDTO: Codable {
        let id: UUID
        let healthWorkoutUUID: String
        let startDate: Date
        let endDate: Date
        let activityType: String
        let duration: TimeInterval
        let calories: Double?
        let avgHeartRate: Double?
        let sourceName: String?
        let sourceBundleIdentifier: String?
        let healthSyncIdentifier: String?
        let healthSyncVersion: Int?
        let healthExternalUUID: String?
        let alternateHealthWorkoutUUIDsRaw: String?
        let statusRaw: String
        let linkedWorkoutSessionID: UUID?
        let createdAt: Date
    }

    struct CardioWorkoutInboxItemDTO: Codable {
        let id: UUID
        let healthWorkoutUUID: String
        let alternateHealthWorkoutUUIDsRaw: String?
        let startDate: Date
        let endDate: Date
        let activityType: String
        let distanceMeters: Double
        let duration: TimeInterval
        let calories: Double?
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let minHeartRate: Double?
        let sourceName: String?
        let sourceBundleIdentifier: String?
        let healthSyncIdentifier: String?
        let healthSyncVersion: Int?
        let healthExternalUUID: String?
        let healthSyncVersionsByStableIdentityRaw: String?
        let metricSourceHealthWorkoutUUID: String?
        let metricSourceName: String?
        let metricSourceBundleIdentifier: String?
        let statusRaw: String
        let linkedRunningSessionID: UUID?
        let suggestedRunningSessionID: UUID?
        let createdAt: Date
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

    var formatVersion: Int? = 4
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
    var healthWorkoutInboxItems: [HealthWorkoutInboxItemDTO]?
    var cardioWorkoutInboxItems: [CardioWorkoutInboxItemDTO]? = nil
}

@MainActor
enum DataBackupService {
    /// Upper bound for a backup file accepted by `import(from:)`. A complete
    /// multi-year history with route payloads is on the order of a few MB, so
    /// this leaves ample headroom while preventing a hostile or corrupted file
    /// from being read fully into memory before `JSONDecoder` runs.
    nonisolated static let maxImportFileSizeBytes = 64 * 1_024 * 1_024

    nonisolated private static let backupFileNamePrefix = "Pace&Plates-Backup-"

    enum ImportError: LocalizedError {
        case fileTooLarge(bytes: Int)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let bytes):
                let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                let limit = ByteCountFormatter.string(
                    fromByteCount: Int64(DataBackupService.maxImportFileSizeBytes),
                    countStyle: .file
                )
                return "This backup is \(size), which exceeds the \(limit) limit for imports."
            }
        }
    }

    /// Deletes any backup files a previous export left in the temporary
    /// directory (for example when the app was terminated while the share sheet
    /// was open), so plaintext health and location data does not linger on disk.
    static func removeStaleExportFiles() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        guard let contents = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix(backupFileNamePrefix) {
            try? fm.removeItem(at: url)
        }
    }

    static func exportAll(context: ModelContext) throws -> URL {
        // A backup must be complete. Propagate fetch failures instead of silently
        // writing an apparently successful file with an empty entity collection.
        let defs = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
        let runs = try context.fetch(FetchDescriptor<RunningSession>())
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        let plans = try context.fetch(FetchDescriptor<RunningPlan>())
        let planSessions = try context.fetch(FetchDescriptor<RunningPlanSession>())
        let conversations = try context.fetch(FetchDescriptor<AIConversation>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        // Replacement tombstones are transient reconciliation state, not user
        // records. Excluding them prevents a deleted pending card from returning
        // after a backup restore.
        let inboxItems = try context.fetch(FetchDescriptor<HealthWorkoutInboxItem>())
            .filter { $0.healthDeletionObservedAt == nil }
        let cardioInboxItems = try context.fetch(FetchDescriptor<CardioWorkoutInboxItem>())
            .filter { $0.healthDeletionObservedAt == nil }

        let file = BackupFile(
            exportedAt: Date(),
            exerciseDefinitions: defs.map { .init(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, isUserDefined: $0.isUserDefined) },
            workoutSessions: sessions.map {
                .init(
                    id: $0.id,
                    date: $0.date,
                    notes: $0.notes,
                    title: $0.title,
                    shouldSaveAsTemplate: $0.shouldSaveAsTemplate,
                    sourceTemplateID: $0.sourceTemplateID,
                    generatedTemplateID: $0.generatedTemplate?.id,
                    isSampleData: $0.isSampleData,
                    healthWorkoutUUID: $0.healthWorkoutUUID,
                    healthDuration: $0.healthDuration,
                    healthCalories: $0.healthCalories,
                    healthAvgHeartRate: $0.healthAvgHeartRate,
                    healthSourceName: $0.healthSourceName,
                    healthActivityType: $0.healthActivityType
                )
            },
            exerciseLogs: logs.map {
                .init(
                    id: $0.id,
                    reps: $0.reps,
                    weight: $0.weight,
                    weightUnit: $0.weightUnit,
                    setNumber: $0.setNumber,
                    exerciseName: $0.exerciseName,
                    exerciseDefinitionId: $0.exerciseDefinition?.id,
                    workoutSessionId: $0.workoutSession?.id,
                    exerciseOrder: $0.exerciseOrder,
                    exerciseType: $0.exerciseType,
                    durationSeconds: $0.durationSeconds,
                    distance: $0.distance,
                    distanceUnit: $0.distanceUnit,
                    caloriesBurned: $0.caloriesBurned,
                    avgHeartRate: $0.avgHeartRate,
                    notes: $0.notes,
                    isCompleted: $0.isCompleted,
                    isIsolated: $0.isIsolated
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
                    metricSourceHealthWorkoutUUID: $0.metricSourceHealthWorkoutUUID,
                    linkedHealthWorkoutUUIDsRaw: $0.linkedHealthWorkoutUUIDsRaw,
                    healthMetricSourceName: $0.healthMetricSourceName,
                    plannedSessionID: $0.plannedSessionID,
                    activityType: $0.activityType,
                    isSampleData: $0.isSampleData,
                    avgHeartRate: $0.avgHeartRate,
                    maxHeartRate: $0.maxHeartRate,
                    minHeartRate: $0.minHeartRate,
                    avgCadence: $0.avgCadence,
                    maxCadence: $0.maxCadence,
                    avgStrideLength: $0.avgStrideLength,
                    verticalOscillation: $0.verticalOscillation,
                    groundContactTime: $0.groundContactTime,
                    totalAscent: $0.totalAscent,
                    totalDescent: $0.totalDescent,
                    minElevation: $0.minElevation,
                    maxElevation: $0.maxElevation,
                    avgPower: $0.avgPower,
                    maxPower: $0.maxPower
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
            },
            healthWorkoutInboxItems: inboxItems.map {
                .init(
                    id: $0.id,
                    healthWorkoutUUID: $0.healthWorkoutUUID,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    activityType: $0.activityType,
                    duration: $0.duration,
                    calories: $0.calories,
                    avgHeartRate: $0.avgHeartRate,
                    sourceName: $0.sourceName,
                    sourceBundleIdentifier: $0.sourceBundleIdentifier,
                    healthSyncIdentifier: $0.healthSyncIdentifier,
                    healthSyncVersion: $0.healthSyncVersion,
                    healthExternalUUID: $0.healthExternalUUID,
                    alternateHealthWorkoutUUIDsRaw: $0.alternateHealthWorkoutUUIDsRaw,
                    statusRaw: $0.statusRaw,
                    linkedWorkoutSessionID: $0.linkedWorkoutSessionID,
                    createdAt: $0.createdAt
                )
            },
            cardioWorkoutInboxItems: cardioInboxItems.map {
                .init(
                    id: $0.id,
                    healthWorkoutUUID: $0.healthWorkoutUUID,
                    alternateHealthWorkoutUUIDsRaw: $0.alternateHealthWorkoutUUIDsRaw,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    activityType: $0.activityType,
                    distanceMeters: $0.distanceMeters,
                    duration: $0.duration,
                    calories: $0.calories,
                    avgHeartRate: $0.avgHeartRate,
                    maxHeartRate: $0.maxHeartRate,
                    minHeartRate: $0.minHeartRate,
                    sourceName: $0.sourceName,
                    sourceBundleIdentifier: $0.sourceBundleIdentifier,
                    healthSyncIdentifier: $0.healthSyncIdentifier,
                    healthSyncVersion: $0.healthSyncVersion,
                    healthExternalUUID: $0.healthExternalUUID,
                    healthSyncVersionsByStableIdentityRaw:
                        $0.healthSyncVersionsByStableIdentityRaw,
                    metricSourceHealthWorkoutUUID:
                        $0.metricSourceHealthWorkoutUUID,
                    metricSourceName: $0.metricSourceName,
                    metricSourceBundleIdentifier:
                        $0.metricSourceBundleIdentifier,
                    statusRaw: $0.statusRaw,
                    linkedRunningSessionID: $0.linkedRunningSessionID,
                    suggestedRunningSessionID: $0.suggestedRunningSessionID,
                    createdAt: $0.createdAt
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(file)

        removeStaleExportFiles()

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(backupFileNamePrefix)\(formatter.string(from: Date())).json"
        let url = tmp.appendingPathComponent(name)
        // The file holds GPS routes, body weight, and AI conversations in plaintext.
        // `.completeFileProtectionUnlessOpen` keeps it encrypted at rest whenever
        // the device is locked, while still letting a share extension that already
        // opened it finish reading.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        return url
    }

    static func `import`(from url: URL, context: ModelContext) throws {
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maxImportFileSizeBytes {
            throw ImportError.fileTooLarge(bytes: size)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(BackupFile.self, from: data)

        let existingDefs = try context.fetch(FetchDescriptor<ExerciseDefinition>())
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

        var existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let existingSessionIDs = Set(existingSessions.map(\.id))
        let existingLogs = try context.fetch(FetchDescriptor<ExerciseLog>())
        let existingLogIDs = Set(existingLogs.map(\.id))
        var existingRuns = try context.fetch(FetchDescriptor<RunningSession>())
        let existingRunIDs = Set(existingRuns.map(\.id))
        var existingWeights = try context.fetch(FetchDescriptor<WeightEntry>())
        let existingWeightIDs = Set(existingWeights.map(\.id))
        let existingPlanIDs = Set(try context.fetch(FetchDescriptor<RunningPlan>()).map(\.id))
        let existingPlanSessionIDs = Set(try context.fetch(FetchDescriptor<RunningPlanSession>()).map(\.id))
        let existingConversationIDs = Set(try context.fetch(FetchDescriptor<AIConversation>()).map(\.id))
        let existingTemplateIDs = Set(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id))
        let existingTemplateExerciseIDs = Set(try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id))
        var existingInboxItems = try context.fetch(FetchDescriptor<HealthWorkoutInboxItem>())
        func knownHealthWorkoutUUIDs(
            primary: String,
            alternatesRaw: String?
        ) -> Set<String> {
            var identifiers = Set(
                (alternatesRaw ?? "")
                    .split(whereSeparator: \.isNewline)
                    .map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .filter { !$0.isEmpty }
            )
            let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPrimary.isEmpty {
                identifiers.insert(trimmedPrimary)
            }
            return identifiers
        }
        let importedLogsBySessionID = Dictionary(
            grouping: file.exerciseLogs.compactMap { dto -> BackupFile.ExerciseLogDTO? in
                dto.workoutSessionId == nil ? nil : dto
            },
            by: { $0.workoutSessionId! }
        )

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
        var contentMatchedSessionIDs: Set<UUID> = []
        for dto in file.workoutSessions {
            if existingSessionIDs.contains(dto.id) {
                let pred = #Predicate<WorkoutSession> { $0.id == dto.id }
                if let existing = try? context.fetch(FetchDescriptor<WorkoutSession>(predicate: pred)).first {
                    sessionsById[dto.id] = existing
                }
                continue
            }

            let dtoLogs = importedLogsBySessionID[dto.id] ?? []
            if let duplicate = existingSessions.first(where: {
                areWorkoutSessionContentsEqual(dto: dto, logs: dtoLogs, model: $0)
            }) {
                sessionsById[dto.id] = duplicate
                contentMatchedSessionIDs.insert(dto.id)
                continue
            }

            let model = WorkoutSession(
                id: dto.id,
                date: dto.date,
                notes: dto.notes,
                title: dto.title,
                shouldSaveAsTemplate: dto.shouldSaveAsTemplate ?? false,
                sourceTemplateID: dto.sourceTemplateID
            )
            model.isSampleData = dto.isSampleData ?? false
            model.healthWorkoutUUID = dto.healthWorkoutUUID
            model.healthDuration = dto.healthDuration
            model.healthCalories = dto.healthCalories
            model.healthAvgHeartRate = dto.healthAvgHeartRate
            model.healthSourceName = dto.healthSourceName
            model.healthActivityType = dto.healthActivityType
            context.insert(model)
            sessionsById[dto.id] = model
            existingSessions.append(model)
        }

        for dto in file.exerciseLogs {
            if existingLogIDs.contains(dto.id) { continue }
            if let sessionID = dto.workoutSessionId, contentMatchedSessionIDs.contains(sessionID) {
                continue
            }
            let model = ExerciseLog(
                id: dto.id,
                reps: dto.reps,
                weight: dto.weight,
                weightUnit: dto.weightUnit,
                setNumber: dto.setNumber,
                exerciseName: dto.exerciseName,
                exerciseOrder: dto.exerciseOrder ?? 0,
                exerciseType: dto.exerciseType ?? "strength",
                durationSeconds: dto.durationSeconds,
                distance: dto.distance,
                distanceUnit: dto.distanceUnit,
                caloriesBurned: dto.caloriesBurned,
                avgHeartRate: dto.avgHeartRate,
                notes: dto.notes,
                isCompleted: dto.isCompleted ?? false
            )
            model.isIsolated = dto.isIsolated ?? false

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

        func mergeRunningHealthLinks(
            from dto: BackupFile.RunningSessionDTO,
            into run: RunningSession
        ) {
            var identifiers = CardioWorkoutInboxService.knownHealthUUIDs(for: run)
            if let uuid = dto.healthWorkoutUUID, !uuid.isEmpty {
                identifiers.insert(uuid)
            }
            if let uuid = dto.metricSourceHealthWorkoutUUID, !uuid.isEmpty {
                identifiers.insert(uuid)
            }
            identifiers.formUnion(
                (dto.linkedHealthWorkoutUUIDsRaw ?? "")
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
                    .filter { !$0.isEmpty }
            )
            run.linkedHealthWorkoutUUIDsRaw = identifiers
                .sorted()
                .joined(separator: "\n")

            if run.healthWorkoutUUID?.isEmpty ?? true {
                run.healthWorkoutUUID = dto.healthWorkoutUUID
            }
            if run.metricSourceHealthWorkoutUUID?.isEmpty ?? true {
                run.metricSourceHealthWorkoutUUID =
                    dto.metricSourceHealthWorkoutUUID
            }
            if run.healthMetricSourceName?.isEmpty ?? true {
                run.healthMetricSourceName = dto.healthMetricSourceName
            }

            // A restore augments an existing local activity; it never replaces
            // its route, notes, distance, or other user-authored core fields.
            if run.calories == nil { run.calories = dto.calories }
            if run.avgHeartRate == nil { run.avgHeartRate = dto.avgHeartRate }
            if run.maxHeartRate == nil { run.maxHeartRate = dto.maxHeartRate }
            if run.minHeartRate == nil { run.minHeartRate = dto.minHeartRate }
            if run.avgCadence == nil { run.avgCadence = dto.avgCadence }
            if run.maxCadence == nil { run.maxCadence = dto.maxCadence }
            if run.avgStrideLength == nil {
                run.avgStrideLength = dto.avgStrideLength
            }
            if run.verticalOscillation == nil {
                run.verticalOscillation = dto.verticalOscillation
            }
            if run.groundContactTime == nil {
                run.groundContactTime = dto.groundContactTime
            }
            if run.totalAscent == nil { run.totalAscent = dto.totalAscent }
            if run.totalDescent == nil { run.totalDescent = dto.totalDescent }
            if run.minElevation == nil { run.minElevation = dto.minElevation }
            if run.maxElevation == nil { run.maxElevation = dto.maxElevation }
            if run.avgPower == nil { run.avgPower = dto.avgPower }
            if run.maxPower == nil { run.maxPower = dto.maxPower }
        }

        // Every backup run ID resolves to the canonical local row selected by
        // same-ID/content deduplication. Inbox links are remapped through this
        // table later so a restore cannot create dangling relationships.
        var runsByBackupID: [UUID: RunningSession] = [:]
        for dto in file.runningSessions {
            if existingRunIDs.contains(dto.id),
               let existing = existingRuns.first(where: { $0.id == dto.id }) {
                mergeRunningHealthLinks(from: dto, into: existing)
                runsByBackupID[dto.id] = existing
                continue
            }
            if let duplicate = existingRuns.first(where: {
                areRunningSessionContentsEqual(dto: dto, model: $0)
            }) {
                mergeRunningHealthLinks(from: dto, into: duplicate)
                runsByBackupID[dto.id] = duplicate
                continue
            }

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
                metricSourceHealthWorkoutUUID: dto.metricSourceHealthWorkoutUUID,
                linkedHealthWorkoutUUIDsRaw: dto.linkedHealthWorkoutUUIDsRaw ?? "",
                healthMetricSourceName: dto.healthMetricSourceName,
                plannedSessionID: dto.plannedSessionID,
                activityType: dto.activityType,
                avgHeartRate: dto.avgHeartRate,
                maxHeartRate: dto.maxHeartRate,
                minHeartRate: dto.minHeartRate,
                avgCadence: dto.avgCadence,
                maxCadence: dto.maxCadence,
                avgStrideLength: dto.avgStrideLength,
                verticalOscillation: dto.verticalOscillation,
                groundContactTime: dto.groundContactTime,
                totalAscent: dto.totalAscent,
                totalDescent: dto.totalDescent,
                minElevation: dto.minElevation,
                maxElevation: dto.maxElevation,
                avgPower: dto.avgPower,
                maxPower: dto.maxPower
            )
            model.isSampleData = dto.isSampleData ?? false
            context.insert(model)
            existingRuns.append(model)
            runsByBackupID[dto.id] = model
        }

        for dto in file.weightEntries {
            if existingWeightIDs.contains(dto.id) { continue }

            if existingWeights.contains(where: {
                areWeightEntryContentsEqual(dto: dto, model: $0)
            }) { continue }

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

        let restoredPlanSessions = try context.fetch(FetchDescriptor<RunningPlanSession>())
        let restoredPlanSessionsByID = Dictionary(
            uniqueKeysWithValues: restoredPlanSessions.map { ($0.id, $0) }
        )
        for run in existingRuns {
            guard let plannedSessionID = run.plannedSessionID,
                  let plannedSession = restoredPlanSessionsByID[plannedSessionID] else { continue }
            run.plannedSession = plannedSession
            if plannedSession.completedRun == nil {
                plannedSession.completedRun = run
            }
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

        let inboxDTOs = file.healthWorkoutInboxItems ?? []
        var remainingInboxIndices = Array(inboxDTOs.indices)

        func inboxStatusPriority(_ statusRaw: String) -> Int {
            switch statusRaw {
            case HealthWorkoutInboxItem.Status.linked.rawValue:
                return 3
            case HealthWorkoutInboxItem.Status.dismissed.rawValue:
                return 2
            default:
                return 1
            }
        }

        func inboxDTOScore(_ dto: BackupFile.HealthWorkoutInboxItemDTO) -> Int {
            inboxStatusPriority(dto.statusRaw) * 1_000 +
                (dto.linkedWorkoutSessionID == nil ? 0 : 100) +
                (dto.avgHeartRate == nil ? 0 : 20) +
                (dto.calories == nil ? 0 : 10) +
                (dto.healthSyncIdentifier?.isEmpty == false ? 4 : 0) +
                (dto.healthExternalUUID?.isEmpty == false ? 2 : 0) +
                (dto.sourceBundleIdentifier?.isEmpty == false ? 1 : 0)
        }

        func inboxItemScore(_ item: HealthWorkoutInboxItem) -> Int {
            inboxStatusPriority(item.statusRaw) * 1_000 +
                (item.linkedWorkoutSessionID == nil ? 0 : 100) +
                (item.avgHeartRate == nil ? 0 : 20) +
                (item.calories == nil ? 0 : 10) +
                (item.healthSyncIdentifier?.isEmpty == false ? 4 : 0) +
                (item.healthExternalUUID?.isEmpty == false ? 2 : 0) +
                (item.sourceBundleIdentifier?.isEmpty == false ? 1 : 0)
        }

        func normalizedInboxString(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func inboxSourceIdentity(
            name: String?,
            bundle: String?
        ) -> String? {
            let normalizedBundle = normalizedInboxString(bundle)?.lowercased()
            let normalizedName = normalizedInboxString(name)?.lowercased()
            if normalizedBundle == "com.ouraring.oura" ||
                normalizedBundle?.hasPrefix("com.ouraring.") == true ||
                normalizedName == "oura" ||
                normalizedName == "oura ring" {
                return "oura"
            }
            return normalizedBundle ?? normalizedName
        }

        func adoptInboxIdentity(
            sourceName: String?,
            sourceBundleIdentifier: String?,
            healthSyncIdentifier: String?,
            healthSyncVersion: Int?,
            healthExternalUUID: String?,
            into canonical: HealthWorkoutInboxItem
        ) {
            canonical.sourceName = normalizedInboxString(sourceName)
            canonical.sourceBundleIdentifier =
                normalizedInboxString(sourceBundleIdentifier)
            canonical.healthSyncIdentifier =
                normalizedInboxString(healthSyncIdentifier)
            canonical.healthSyncVersion = healthSyncVersion
            canonical.healthExternalUUID =
                normalizedInboxString(healthExternalUUID)
        }

        func stableInboxKeyPart(_ value: String?) -> String {
            let value = value ?? ""
            return "\(value.utf8.count):\(value)"
        }

        func stableInboxDouble(_ value: Double?) -> String? {
            value.map { String($0.bitPattern, radix: 16) }
        }

        func inboxDTOStableKey(
            _ dto: BackupFile.HealthWorkoutInboxItemDTO
        ) -> String {
            [
                dto.id.uuidString.lowercased(),
                dto.healthWorkoutUUID,
                String(dto.startDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
                String(dto.endDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
                dto.activityType,
                stableInboxDouble(dto.duration),
                stableInboxDouble(dto.calories),
                stableInboxDouble(dto.avgHeartRate),
                dto.sourceName,
                dto.sourceBundleIdentifier,
                dto.healthSyncIdentifier,
                dto.healthSyncVersion.map(String.init),
                dto.healthExternalUUID,
                dto.alternateHealthWorkoutUUIDsRaw,
                dto.statusRaw,
                dto.linkedWorkoutSessionID?.uuidString.lowercased(),
                String(dto.createdAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
            ]
            .map(stableInboxKeyPart)
            .joined()
        }

        func inboxItemStableKey(_ item: HealthWorkoutInboxItem) -> String {
            [
                item.id.uuidString.lowercased(),
                item.healthWorkoutUUID,
                String(item.startDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
                String(item.endDate.timeIntervalSinceReferenceDate.bitPattern, radix: 16),
                item.activityType,
                stableInboxDouble(item.duration),
                stableInboxDouble(item.calories),
                stableInboxDouble(item.avgHeartRate),
                item.sourceName,
                item.sourceBundleIdentifier,
                item.healthSyncIdentifier,
                item.healthSyncVersion.map(String.init),
                item.healthExternalUUID,
                item.alternateHealthWorkoutUUIDsRaw,
                item.healthDeletionObservedAt.map {
                    String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
                },
                item.statusRaw,
                item.linkedWorkoutSessionID?.uuidString.lowercased(),
                String(item.createdAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
            ]
            .map(stableInboxKeyPart)
            .joined()
        }

        func prefersInboxDTO(
            _ lhs: BackupFile.HealthWorkoutInboxItemDTO,
            over rhs: BackupFile.HealthWorkoutInboxItemDTO
        ) -> Bool {
            let lhsScore = inboxDTOScore(lhs)
            let rhsScore = inboxDTOScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsVersion = lhs.healthSyncVersion ?? Int.min
            let rhsVersion = rhs.healthSyncVersion ?? Int.min
            if lhsVersion != rhsVersion {
                return lhsVersion > rhsVersion
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return inboxDTOStableKey(lhs) < inboxDTOStableKey(rhs)
        }

        func prefersInboxItem(
            _ lhs: HealthWorkoutInboxItem,
            over rhs: HealthWorkoutInboxItem
        ) -> Bool {
            let lhsScore = inboxItemScore(lhs)
            let rhsScore = inboxItemScore(rhs)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            let lhsIsLive = lhs.healthDeletionObservedAt == nil
            let rhsIsLive = rhs.healthDeletionObservedAt == nil
            if lhsIsLive != rhsIsLive {
                return lhsIsLive
            }

            let lhsVersion = lhs.healthSyncVersion ?? Int.min
            let rhsVersion = rhs.healthSyncVersion ?? Int.min
            if lhsVersion != rhsVersion {
                return lhsVersion > rhsVersion
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return inboxItemStableKey(lhs) < inboxItemStableKey(rhs)
        }

        func mergeInboxFields(
            from donor: HealthWorkoutInboxItem,
            into canonical: HealthWorkoutInboxItem
        ) {
            if canonical.duration <= 0, donor.duration > 0 {
                canonical.startDate = donor.startDate
                canonical.endDate = donor.endDate
                canonical.activityType = donor.activityType
                canonical.duration = donor.duration
            }
            if canonical.calories == nil {
                canonical.calories = donor.calories
            }
            if canonical.avgHeartRate == nil {
                canonical.avgHeartRate = donor.avgHeartRate
            }
            // Inbox aliases can intentionally span sources (for example, Oura
            // and Apple Watch copies of one workout). Stable identifiers are
            // source-scoped, so retain the canonical tuple as a unit. Only a
            // source-less canonical may adopt the first deterministically
            // ordered donor's complete identity tuple.
            if inboxSourceIdentity(
                name: canonical.sourceName,
                bundle: canonical.sourceBundleIdentifier
            ) == nil,
               inboxSourceIdentity(
                    name: donor.sourceName,
                    bundle: donor.sourceBundleIdentifier
               ) != nil {
                adoptInboxIdentity(
                    sourceName: donor.sourceName,
                    sourceBundleIdentifier: donor.sourceBundleIdentifier,
                    healthSyncIdentifier: donor.healthSyncIdentifier,
                    healthSyncVersion: donor.healthSyncVersion,
                    healthExternalUUID: donor.healthExternalUUID,
                    into: canonical
                )
            }

            let canonicalStatusPriority =
                inboxStatusPriority(canonical.statusRaw)
            let donorStatusPriority = inboxStatusPriority(donor.statusRaw)
            if donorStatusPriority > canonicalStatusPriority {
                canonical.statusRaw = donor.statusRaw
                canonical.linkedWorkoutSessionID = donor.linkedWorkoutSessionID
            } else if donorStatusPriority == canonicalStatusPriority,
                      canonical.linkedWorkoutSessionID == nil {
                canonical.linkedWorkoutSessionID =
                    donor.linkedWorkoutSessionID
            }

            canonical.createdAt = min(canonical.createdAt, donor.createdAt)
            if canonical.healthDeletionObservedAt == nil ||
                donor.healthDeletionObservedAt == nil {
                canonical.healthDeletionObservedAt = nil
            } else {
                canonical.healthDeletionObservedAt = min(
                    canonical.healthDeletionObservedAt!,
                    donor.healthDeletionObservedAt!
                )
            }
        }

        func mergeInboxFields(
            from dto: BackupFile.HealthWorkoutInboxItemDTO,
            into canonical: HealthWorkoutInboxItem
        ) {
            if canonical.duration <= 0, dto.duration > 0 {
                canonical.startDate = dto.startDate
                canonical.endDate = dto.endDate
                canonical.activityType = dto.activityType
                canonical.duration = dto.duration
            }
            if canonical.calories == nil {
                canonical.calories = dto.calories
            }
            if canonical.avgHeartRate == nil {
                canonical.avgHeartRate = dto.avgHeartRate
            }
            if inboxSourceIdentity(
                name: canonical.sourceName,
                bundle: canonical.sourceBundleIdentifier
            ) == nil,
               inboxSourceIdentity(
                    name: dto.sourceName,
                    bundle: dto.sourceBundleIdentifier
               ) != nil {
                adoptInboxIdentity(
                    sourceName: dto.sourceName,
                    sourceBundleIdentifier: dto.sourceBundleIdentifier,
                    healthSyncIdentifier: dto.healthSyncIdentifier,
                    healthSyncVersion: dto.healthSyncVersion,
                    healthExternalUUID: dto.healthExternalUUID,
                    into: canonical
                )
            }

            let canonicalStatusPriority =
                inboxStatusPriority(canonical.statusRaw)
            let dtoStatusPriority = inboxStatusPriority(dto.statusRaw)
            let resolvedLinkedSessionID = dto.linkedWorkoutSessionID.map {
                sessionsById[$0]?.id ?? $0
            }
            if dtoStatusPriority > canonicalStatusPriority {
                canonical.statusRaw = dto.statusRaw
                canonical.linkedWorkoutSessionID = resolvedLinkedSessionID
            } else if dtoStatusPriority == canonicalStatusPriority,
                      canonical.linkedWorkoutSessionID == nil {
                canonical.linkedWorkoutSessionID = resolvedLinkedSessionID
            }

            canonical.createdAt = min(canonical.createdAt, dto.createdAt)
            // Restoring a live backup component only clears local reconciliation
            // state. It never deletes or modifies the HealthKit workout.
            canonical.healthDeletionObservedAt = nil
        }

        while let seedIndex = remainingInboxIndices.first {
            remainingInboxIndices.removeFirst()
            var componentIndices = [seedIndex]
            var combinedIDs = Set([inboxDTOs[seedIndex].id])
            var combinedUUIDs = knownHealthWorkoutUUIDs(
                primary: inboxDTOs[seedIndex].healthWorkoutUUID,
                alternatesRaw: inboxDTOs[seedIndex].alternateHealthWorkoutUUIDsRaw
            )
            var matchingExistingItems: [HealthWorkoutInboxItem] = []
            var matchingExistingObjectIDs: Set<ObjectIdentifier> = []

            // Alternate DTO and existing-row expansion to a fixed point. This
            // handles bridges in either source and makes the result independent
            // of backup and SwiftData fetch order.
            var didExpandComponent = true
            while didExpandComponent {
                didExpandComponent = false
                for offset in remainingInboxIndices.indices.reversed() {
                    let candidateIndex = remainingInboxIndices[offset]
                    let candidateUUIDs = knownHealthWorkoutUUIDs(
                        primary: inboxDTOs[candidateIndex].healthWorkoutUUID,
                        alternatesRaw: inboxDTOs[candidateIndex].alternateHealthWorkoutUUIDsRaw
                    )
                    let sharesUUID =
                        !candidateUUIDs.isEmpty &&
                        !combinedUUIDs.isDisjoint(with: candidateUUIDs)
                    let sharesID = combinedIDs.contains(
                        inboxDTOs[candidateIndex].id
                    )
                    guard sharesUUID || sharesID else {
                        continue
                    }
                    componentIndices.append(candidateIndex)
                    combinedIDs.insert(inboxDTOs[candidateIndex].id)
                    combinedUUIDs.formUnion(candidateUUIDs)
                    remainingInboxIndices.remove(at: offset)
                    didExpandComponent = true
                }

                for item in existingInboxItems {
                    let objectID = ObjectIdentifier(item)
                    guard !matchingExistingObjectIDs.contains(objectID) else {
                        continue
                    }
                    let itemUUIDs = knownHealthWorkoutUUIDs(
                        primary: item.healthWorkoutUUID,
                        alternatesRaw: item.alternateHealthWorkoutUUIDsRaw
                    )
                    let sharesUUID =
                        !itemUUIDs.isEmpty &&
                        !combinedUUIDs.isDisjoint(with: itemUUIDs)
                    guard combinedIDs.contains(item.id) || sharesUUID else {
                        continue
                    }
                    matchingExistingItems.append(item)
                    matchingExistingObjectIDs.insert(objectID)
                    combinedIDs.insert(item.id)
                    combinedUUIDs.formUnion(itemUUIDs)
                    didExpandComponent = true
                }
            }

            if !matchingExistingItems.isEmpty {
                let orderedExistingItems = matchingExistingItems.sorted {
                    prefersInboxItem($0, over: $1)
                }
                guard let canonical = orderedExistingItems.first else {
                    continue
                }

                // Keep exactly one local owner for the full alias component.
                // Workout sessions and HealthKit records are not deleted.
                for duplicate in orderedExistingItems.dropFirst() {
                    mergeInboxFields(from: duplicate, into: canonical)
                    context.delete(duplicate)
                    existingInboxItems.removeAll { $0 === duplicate }
                }
                for dto in componentIndices
                    .map({ inboxDTOs[$0] })
                    .sorted(by: { prefersInboxDTO($0, over: $1) }) {
                    mergeInboxFields(from: dto, into: canonical)
                }

                let primary = combinedUUIDs.contains(canonical.healthWorkoutUUID)
                    ? canonical.healthWorkoutUUID
                    : (combinedUUIDs.sorted().first ?? "")
                canonical.healthWorkoutUUID = primary
                canonical.alternateHealthWorkoutUUIDsRaw = combinedUUIDs
                    .subtracting([primary])
                    .sorted()
                    .joined(separator: "\n")
                continue
            }

            let orderedDTOs = componentIndices
                .map { inboxDTOs[$0] }
                .sorted { prefersInboxDTO($0, over: $1) }
            guard let dto = orderedDTOs.first else {
                continue
            }

            let primaryUUID = combinedUUIDs.contains(dto.healthWorkoutUUID)
                ? dto.healthWorkoutUUID
                : (combinedUUIDs.sorted().first ?? "")
            let item = HealthWorkoutInboxItem(
                id: dto.id,
                healthWorkoutUUID: primaryUUID,
                startDate: dto.startDate,
                endDate: dto.endDate,
                activityType: dto.activityType,
                duration: dto.duration,
                calories: dto.calories,
                avgHeartRate: dto.avgHeartRate,
                sourceName: dto.sourceName,
                sourceBundleIdentifier: dto.sourceBundleIdentifier,
                healthSyncIdentifier: dto.healthSyncIdentifier,
                healthSyncVersion: dto.healthSyncVersion,
                healthExternalUUID: dto.healthExternalUUID,
                alternateHealthWorkoutUUIDsRaw: combinedUUIDs
                    .subtracting([primaryUUID])
                    .sorted()
                    .joined(separator: "\n")
            )
            item.statusRaw = dto.statusRaw
            if let linkedSessionID = dto.linkedWorkoutSessionID {
                item.linkedWorkoutSessionID =
                    sessionsById[linkedSessionID]?.id ?? linkedSessionID
            }
            item.createdAt = dto.createdAt
            for donor in orderedDTOs.dropFirst() {
                mergeInboxFields(from: donor, into: item)
            }
            context.insert(item)
            existingInboxItems.append(item)
        }

        var existingCardioInboxItems = try context.fetch(
            FetchDescriptor<CardioWorkoutInboxItem>()
        )

        func resolvedRunningSessionID(_ backupID: UUID?) -> UUID? {
            guard let backupID else { return nil }
            if let mapped = runsByBackupID[backupID] {
                return mapped.id
            }
            return existingRuns.first(where: { $0.id == backupID })?.id
        }

        func cardioUUIDs(
            primary: String,
            alternatesRaw: String?
        ) -> Set<String> {
            knownHealthWorkoutUUIDs(
                primary: primary,
                alternatesRaw: alternatesRaw
            )
        }

        func cardioSyncVersionLedger(_ raw: String?) -> [String: Int] {
            guard let data = raw?.data(using: .utf8), !data.isEmpty else {
                return [:]
            }
            return (try? JSONDecoder().decode([String: Int].self, from: data))
                ?? [:]
        }

        func mergedCardioSyncVersionLedger(
            _ firstRaw: String?,
            _ secondRaw: String?
        ) -> String {
            var merged = cardioSyncVersionLedger(firstRaw)
            for (key, version) in cardioSyncVersionLedger(secondRaw) {
                merged[key] = max(merged[key] ?? Int.min, version)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard !merged.isEmpty,
                  let data = try? encoder.encode(merged) else {
                return ""
            }
            return String(decoding: data, as: UTF8.self)
        }

        func cardioLedgersShareStableIdentity(
            _ firstRaw: String?,
            _ secondRaw: String?
        ) -> Bool {
            let firstKeys = Set(cardioSyncVersionLedger(firstRaw).keys)
            let secondKeys = Set(cardioSyncVersionLedger(secondRaw).keys)
            return !firstKeys.isEmpty && !firstKeys.isDisjoint(with: secondKeys)
        }

        func cardioStableIdentityMatches(
            sourceName lhsName: String?,
            sourceBundle lhsBundle: String?,
            syncIdentifier lhsSync: String?,
            externalUUID lhsExternal: String?,
            sourceName rhsName: String?,
            sourceBundle rhsBundle: String?,
            syncIdentifier rhsSync: String?,
            externalUUID rhsExternal: String?
        ) -> Bool {
            guard let lhsSource = inboxSourceIdentity(
                name: lhsName,
                bundle: lhsBundle
            ), lhsSource == inboxSourceIdentity(
                name: rhsName,
                bundle: rhsBundle
            ) else {
                return false
            }

            let normalizedLhsSync = normalizedInboxString(lhsSync)?.lowercased()
            let normalizedRhsSync = normalizedInboxString(rhsSync)?.lowercased()
            if let normalizedLhsSync, let normalizedRhsSync {
                return normalizedLhsSync == normalizedRhsSync
            }

            let normalizedLhsExternal =
                normalizedInboxString(lhsExternal)?.lowercased()
            let normalizedRhsExternal =
                normalizedInboxString(rhsExternal)?.lowercased()
            if let normalizedLhsExternal, let normalizedRhsExternal {
                return normalizedLhsExternal == normalizedRhsExternal
            }
            return false
        }

        func cardioItemsMatch(
            _ lhs: CardioWorkoutInboxItem,
            _ rhs: CardioWorkoutInboxItem
        ) -> Bool {
            if lhs.id == rhs.id { return true }
            let lhsUUIDs = CardioWorkoutInboxService.knownHealthUUIDs(for: lhs)
            let rhsUUIDs = CardioWorkoutInboxService.knownHealthUUIDs(for: rhs)
            if !lhsUUIDs.isEmpty && !lhsUUIDs.isDisjoint(with: rhsUUIDs) {
                return true
            }
            if cardioLedgersShareStableIdentity(
                lhs.healthSyncVersionsByStableIdentityRaw,
                rhs.healthSyncVersionsByStableIdentityRaw
            ) {
                return true
            }
            return cardioStableIdentityMatches(
                sourceName: lhs.sourceName,
                sourceBundle: lhs.sourceBundleIdentifier,
                syncIdentifier: lhs.healthSyncIdentifier,
                externalUUID: lhs.healthExternalUUID,
                sourceName: rhs.sourceName,
                sourceBundle: rhs.sourceBundleIdentifier,
                syncIdentifier: rhs.healthSyncIdentifier,
                externalUUID: rhs.healthExternalUUID
            )
        }

        func cardioItemMatchesDTO(
            _ item: CardioWorkoutInboxItem,
            _ dto: BackupFile.CardioWorkoutInboxItemDTO
        ) -> Bool {
            if item.id == dto.id { return true }
            let dtoUUIDs = cardioUUIDs(
                primary: dto.healthWorkoutUUID,
                alternatesRaw: dto.alternateHealthWorkoutUUIDsRaw
            )
            let itemUUIDs = CardioWorkoutInboxService.knownHealthUUIDs(for: item)
            if !dtoUUIDs.isEmpty && !dtoUUIDs.isDisjoint(with: itemUUIDs) {
                return true
            }
            if cardioLedgersShareStableIdentity(
                item.healthSyncVersionsByStableIdentityRaw,
                dto.healthSyncVersionsByStableIdentityRaw
            ) {
                return true
            }
            return cardioStableIdentityMatches(
                sourceName: item.sourceName,
                sourceBundle: item.sourceBundleIdentifier,
                syncIdentifier: item.healthSyncIdentifier,
                externalUUID: item.healthExternalUUID,
                sourceName: dto.sourceName,
                sourceBundle: dto.sourceBundleIdentifier,
                syncIdentifier: dto.healthSyncIdentifier,
                externalUUID: dto.healthExternalUUID
            )
        }

        func normalizeCardioLinks(_ item: CardioWorkoutInboxItem) {
            item.linkedRunningSessionID = resolvedRunningSessionID(
                item.linkedRunningSessionID
            )
            item.suggestedRunningSessionID = resolvedRunningSessionID(
                item.suggestedRunningSessionID
            )
            if item.statusRaw == CardioWorkoutInboxItem.Status.linked.rawValue,
               item.linkedRunningSessionID == nil {
                item.statusRaw = CardioWorkoutInboxItem.Status.pending.rawValue
            }
        }

        func cardioItemScore(_ item: CardioWorkoutInboxItem) -> Int {
            inboxStatusPriority(item.statusRaw) * 1_000 +
                (item.linkedRunningSessionID == nil ? 0 : 100) +
                (item.avgHeartRate == nil ? 0 : 20) +
                (item.calories == nil ? 0 : 10) +
                (item.healthSyncIdentifier?.isEmpty == false ? 4 : 0) +
                (item.healthExternalUUID?.isEmpty == false ? 2 : 0) +
                (item.sourceBundleIdentifier?.isEmpty == false ? 1 : 0)
        }

        func setCardioUUIDs(
            _ identifiers: Set<String>,
            on item: CardioWorkoutInboxItem,
            preferredPrimary: String?
        ) {
            let cleaned = Set(identifiers.filter { !$0.isEmpty })
            guard !cleaned.isEmpty else { return }
            let primary: String
            if let preferredPrimary, cleaned.contains(preferredPrimary) {
                primary = preferredPrimary
            } else if cleaned.contains(item.healthWorkoutUUID) {
                primary = item.healthWorkoutUUID
            } else {
                primary = cleaned.sorted().first!
            }
            item.healthWorkoutUUID = primary
            item.alternateHealthWorkoutUUIDsRaw = cleaned
                .subtracting([primary])
                .sorted()
                .joined(separator: "\n")
        }

        func cardioRevisionOrder(
            currentSourceName: String?,
            currentSourceBundle: String?,
            currentSyncIdentifier: String?,
            currentExternalUUID: String?,
            currentVersion: Int?,
            currentVersionLedgerRaw: String?,
            candidateSourceName: String?,
            candidateSourceBundle: String?,
            candidateSyncIdentifier: String?,
            candidateExternalUUID: String?,
            candidateVersion: Int?,
            candidateVersionLedgerRaw: String?
        ) -> (older: Bool, newer: Bool) {
            let currentLedger = cardioSyncVersionLedger(
                currentVersionLedgerRaw
            )
            let candidateLedger = cardioSyncVersionLedger(
                candidateVersionLedgerRaw
            )
            let sharedKeys = Set(currentLedger.keys)
                .intersection(candidateLedger.keys)
            if !sharedKeys.isEmpty {
                let currentMaximum = sharedKeys.compactMap {
                    currentLedger[$0]
                }.max() ?? Int.min
                let candidateMaximum = sharedKeys.compactMap {
                    candidateLedger[$0]
                }.max() ?? Int.min
                return (
                    candidateMaximum < currentMaximum,
                    candidateMaximum > currentMaximum
                )
            }
            guard cardioStableIdentityMatches(
                sourceName: currentSourceName,
                sourceBundle: currentSourceBundle,
                syncIdentifier: currentSyncIdentifier,
                externalUUID: currentExternalUUID,
                sourceName: candidateSourceName,
                sourceBundle: candidateSourceBundle,
                syncIdentifier: candidateSyncIdentifier,
                externalUUID: candidateExternalUUID
            ) else {
                return (false, false)
            }
            if let currentVersion {
                guard let candidateVersion else { return (true, false) }
                return (
                    candidateVersion < currentVersion,
                    candidateVersion > currentVersion
                )
            }
            return (false, candidateVersion != nil)
        }

        func mergeCardioFields(
            from donor: CardioWorkoutInboxItem,
            into canonical: CardioWorkoutInboxItem
        ) {
            normalizeCardioLinks(donor)
            normalizeCardioLinks(canonical)
            let revision = cardioRevisionOrder(
                currentSourceName: canonical.sourceName,
                currentSourceBundle: canonical.sourceBundleIdentifier,
                currentSyncIdentifier: canonical.healthSyncIdentifier,
                currentExternalUUID: canonical.healthExternalUUID,
                currentVersion: canonical.healthSyncVersion,
                currentVersionLedgerRaw:
                    canonical.healthSyncVersionsByStableIdentityRaw,
                candidateSourceName: donor.sourceName,
                candidateSourceBundle: donor.sourceBundleIdentifier,
                candidateSyncIdentifier: donor.healthSyncIdentifier,
                candidateExternalUUID: donor.healthExternalUUID,
                candidateVersion: donor.healthSyncVersion,
                candidateVersionLedgerRaw:
                    donor.healthSyncVersionsByStableIdentityRaw
            )
            let richerHeartRate =
                canonical.avgHeartRate == nil && donor.avgHeartRate != nil
            let shouldAdopt = !revision.older &&
                (revision.newer || richerHeartRate ||
                    inboxSourceIdentity(
                        name: canonical.sourceName,
                        bundle: canonical.sourceBundleIdentifier
                    ) == nil)

            var identifiers = CardioWorkoutInboxService.knownHealthUUIDs(
                for: canonical
            )
            identifiers.formUnion(
                CardioWorkoutInboxService.knownHealthUUIDs(for: donor)
            )
            setCardioUUIDs(
                identifiers,
                on: canonical,
                preferredPrimary: shouldAdopt
                    ? donor.healthWorkoutUUID
                    : canonical.healthWorkoutUUID
            )
            canonical.healthSyncVersionsByStableIdentityRaw =
                mergedCardioSyncVersionLedger(
                    canonical.healthSyncVersionsByStableIdentityRaw,
                    donor.healthSyncVersionsByStableIdentityRaw
                )

            if let donorMetricUUID = donor.metricSourceHealthWorkoutUUID,
               identifiers.contains(donorMetricUUID),
               canonical.metricSourceHealthWorkoutUUID == nil ||
                shouldAdopt || richerHeartRate {
                canonical.metricSourceHealthWorkoutUUID = donorMetricUUID
                canonical.metricSourceName = donor.metricSourceName
                canonical.metricSourceBundleIdentifier =
                    donor.metricSourceBundleIdentifier
            }
            if let metricUUID = canonical.metricSourceHealthWorkoutUUID,
               !identifiers.contains(metricUUID) {
                canonical.metricSourceHealthWorkoutUUID = nil
                canonical.metricSourceName = nil
                canonical.metricSourceBundleIdentifier = nil
            }

            if shouldAdopt {
                canonical.startDate = donor.startDate
                canonical.endDate = donor.endDate
                canonical.activityType = donor.activityType
                canonical.distanceMeters = donor.distanceMeters
                canonical.duration = donor.duration
                canonical.sourceName = donor.sourceName
                canonical.sourceBundleIdentifier = donor.sourceBundleIdentifier
                canonical.healthSyncIdentifier = donor.healthSyncIdentifier
                canonical.healthSyncVersion = donor.healthSyncVersion
                canonical.healthExternalUUID = donor.healthExternalUUID
            }
            if !revision.older {
                if canonical.calories == nil || revision.newer {
                    canonical.calories = donor.calories ?? canonical.calories
                }
                if canonical.avgHeartRate == nil || revision.newer {
                    canonical.avgHeartRate = donor.avgHeartRate ?? canonical.avgHeartRate
                }
                if canonical.maxHeartRate == nil || revision.newer {
                    canonical.maxHeartRate = donor.maxHeartRate ?? canonical.maxHeartRate
                }
                if canonical.minHeartRate == nil || revision.newer {
                    canonical.minHeartRate = donor.minHeartRate ?? canonical.minHeartRate
                }
            }

            let canonicalPriority = inboxStatusPriority(canonical.statusRaw)
            let donorPriority = inboxStatusPriority(donor.statusRaw)
            if donorPriority > canonicalPriority {
                canonical.statusRaw = donor.statusRaw
                canonical.linkedRunningSessionID = donor.linkedRunningSessionID
            } else if donorPriority == canonicalPriority,
                      canonical.linkedRunningSessionID == nil {
                canonical.linkedRunningSessionID = donor.linkedRunningSessionID
            }
            if canonical.suggestedRunningSessionID == nil {
                canonical.suggestedRunningSessionID =
                    donor.suggestedRunningSessionID
            }
            canonical.createdAt = min(canonical.createdAt, donor.createdAt)
            if canonical.healthDeletionObservedAt == nil ||
                donor.healthDeletionObservedAt == nil {
                canonical.healthDeletionObservedAt = nil
            } else {
                canonical.healthDeletionObservedAt = min(
                    canonical.healthDeletionObservedAt!,
                    donor.healthDeletionObservedAt!
                )
            }
            normalizeCardioLinks(canonical)
        }

        func mergeCardioFields(
            from dto: BackupFile.CardioWorkoutInboxItemDTO,
            into canonical: CardioWorkoutInboxItem
        ) {
            normalizeCardioLinks(canonical)
            let revision = cardioRevisionOrder(
                currentSourceName: canonical.sourceName,
                currentSourceBundle: canonical.sourceBundleIdentifier,
                currentSyncIdentifier: canonical.healthSyncIdentifier,
                currentExternalUUID: canonical.healthExternalUUID,
                currentVersion: canonical.healthSyncVersion,
                currentVersionLedgerRaw:
                    canonical.healthSyncVersionsByStableIdentityRaw,
                candidateSourceName: dto.sourceName,
                candidateSourceBundle: dto.sourceBundleIdentifier,
                candidateSyncIdentifier: dto.healthSyncIdentifier,
                candidateExternalUUID: dto.healthExternalUUID,
                candidateVersion: dto.healthSyncVersion,
                candidateVersionLedgerRaw:
                    dto.healthSyncVersionsByStableIdentityRaw
            )
            let richerHeartRate =
                canonical.avgHeartRate == nil && dto.avgHeartRate != nil
            let shouldAdopt = !revision.older &&
                (revision.newer || richerHeartRate ||
                    inboxSourceIdentity(
                        name: canonical.sourceName,
                        bundle: canonical.sourceBundleIdentifier
                    ) == nil)

            var identifiers = CardioWorkoutInboxService.knownHealthUUIDs(
                for: canonical
            )
            identifiers.formUnion(
                cardioUUIDs(
                    primary: dto.healthWorkoutUUID,
                    alternatesRaw: dto.alternateHealthWorkoutUUIDsRaw
                )
            )
            setCardioUUIDs(
                identifiers,
                on: canonical,
                preferredPrimary: shouldAdopt
                    ? dto.healthWorkoutUUID
                    : canonical.healthWorkoutUUID
            )
            canonical.healthSyncVersionsByStableIdentityRaw =
                mergedCardioSyncVersionLedger(
                    canonical.healthSyncVersionsByStableIdentityRaw,
                    dto.healthSyncVersionsByStableIdentityRaw
                )

            if let dtoMetricUUID = dto.metricSourceHealthWorkoutUUID,
               identifiers.contains(dtoMetricUUID),
               canonical.metricSourceHealthWorkoutUUID == nil ||
                shouldAdopt || richerHeartRate {
                canonical.metricSourceHealthWorkoutUUID = dtoMetricUUID
                canonical.metricSourceName = dto.metricSourceName
                canonical.metricSourceBundleIdentifier =
                    dto.metricSourceBundleIdentifier
            }
            if let metricUUID = canonical.metricSourceHealthWorkoutUUID,
               !identifiers.contains(metricUUID) {
                canonical.metricSourceHealthWorkoutUUID = nil
                canonical.metricSourceName = nil
                canonical.metricSourceBundleIdentifier = nil
            }

            if shouldAdopt {
                canonical.startDate = dto.startDate
                canonical.endDate = dto.endDate
                canonical.activityType = dto.activityType
                canonical.distanceMeters = dto.distanceMeters
                canonical.duration = dto.duration
                canonical.sourceName = dto.sourceName
                canonical.sourceBundleIdentifier = dto.sourceBundleIdentifier
                canonical.healthSyncIdentifier = dto.healthSyncIdentifier
                canonical.healthSyncVersion = dto.healthSyncVersion
                canonical.healthExternalUUID = dto.healthExternalUUID
            }
            if !revision.older {
                if canonical.calories == nil || revision.newer {
                    canonical.calories = dto.calories ?? canonical.calories
                }
                if canonical.avgHeartRate == nil || revision.newer {
                    canonical.avgHeartRate = dto.avgHeartRate ?? canonical.avgHeartRate
                }
                if canonical.maxHeartRate == nil || revision.newer {
                    canonical.maxHeartRate = dto.maxHeartRate ?? canonical.maxHeartRate
                }
                if canonical.minHeartRate == nil || revision.newer {
                    canonical.minHeartRate = dto.minHeartRate ?? canonical.minHeartRate
                }
            }

            let resolvedLinkedID = resolvedRunningSessionID(
                dto.linkedRunningSessionID
            )
            let resolvedSuggestedID = resolvedRunningSessionID(
                dto.suggestedRunningSessionID
            )
            let dtoStatus =
                dto.statusRaw == CardioWorkoutInboxItem.Status.linked.rawValue &&
                    resolvedLinkedID == nil
                ? CardioWorkoutInboxItem.Status.pending.rawValue
                : dto.statusRaw
            let canonicalPriority = inboxStatusPriority(canonical.statusRaw)
            let dtoPriority = inboxStatusPriority(dtoStatus)
            if dtoPriority > canonicalPriority {
                canonical.statusRaw = dtoStatus
                canonical.linkedRunningSessionID = resolvedLinkedID
            } else if dtoPriority == canonicalPriority,
                      canonical.linkedRunningSessionID == nil {
                canonical.linkedRunningSessionID = resolvedLinkedID
            }
            if canonical.suggestedRunningSessionID == nil {
                canonical.suggestedRunningSessionID = resolvedSuggestedID
            }
            canonical.createdAt = min(canonical.createdAt, dto.createdAt)
            canonical.healthDeletionObservedAt = nil
            normalizeCardioLinks(canonical)
        }

        for item in existingCardioInboxItems {
            normalizeCardioLinks(item)
        }
        for dto in file.cardioWorkoutInboxItems ?? [] {
            let directMatches = existingCardioInboxItems.filter {
                cardioItemMatchesDTO($0, dto)
            }
            let canonical: CardioWorkoutInboxItem
            if let selected = directMatches.sorted(by: {
                let lhsScore = cardioItemScore($0)
                let rhsScore = cardioItemScore($1)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                let lhsVersion = $0.healthSyncVersion ?? Int.min
                let rhsVersion = $1.healthSyncVersion ?? Int.min
                if lhsVersion != rhsVersion { return lhsVersion > rhsVersion }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }).first {
                canonical = selected
                for duplicate in directMatches where duplicate !== canonical {
                    mergeCardioFields(from: duplicate, into: canonical)
                    context.delete(duplicate)
                    existingCardioInboxItems.removeAll { $0 === duplicate }
                }
                mergeCardioFields(from: dto, into: canonical)
            } else {
                let resolvedLinkedID = resolvedRunningSessionID(
                    dto.linkedRunningSessionID
                )
                let item = CardioWorkoutInboxItem(
                    id: dto.id,
                    healthWorkoutUUID: dto.healthWorkoutUUID,
                    startDate: dto.startDate,
                    endDate: dto.endDate,
                    activityType: dto.activityType,
                    distanceMeters: dto.distanceMeters,
                    duration: dto.duration,
                    calories: dto.calories,
                    avgHeartRate: dto.avgHeartRate,
                    maxHeartRate: dto.maxHeartRate,
                    minHeartRate: dto.minHeartRate,
                    sourceName: dto.sourceName,
                    sourceBundleIdentifier: dto.sourceBundleIdentifier,
                    healthSyncIdentifier: dto.healthSyncIdentifier,
                    healthSyncVersion: dto.healthSyncVersion,
                    healthExternalUUID: dto.healthExternalUUID,
                    healthSyncVersionsByStableIdentityRaw:
                        dto.healthSyncVersionsByStableIdentityRaw ?? "",
                    metricSourceHealthWorkoutUUID:
                        dto.metricSourceHealthWorkoutUUID,
                    metricSourceName: dto.metricSourceName,
                    metricSourceBundleIdentifier:
                        dto.metricSourceBundleIdentifier,
                    alternateHealthWorkoutUUIDsRaw:
                        dto.alternateHealthWorkoutUUIDsRaw ?? "",
                    suggestedRunningSessionID: resolvedRunningSessionID(
                        dto.suggestedRunningSessionID
                    )
                )
                item.statusRaw =
                    dto.statusRaw ==
                        CardioWorkoutInboxItem.Status.linked.rawValue &&
                        resolvedLinkedID == nil
                    ? CardioWorkoutInboxItem.Status.pending.rawValue
                    : dto.statusRaw
                item.linkedRunningSessionID = resolvedLinkedID
                item.createdAt = dto.createdAt
                context.insert(item)
                existingCardioInboxItems.append(item)
                canonical = item
            }

            // Collapse any transitive bridge exposed by the DTO's aliases or
            // stable identity, independent of backup/fetch ordering.
            var mergedAnotherItem = true
            while mergedAnotherItem {
                mergedAnotherItem = false
                if let duplicate = existingCardioInboxItems.first(where: {
                    $0 !== canonical && cardioItemsMatch($0, canonical)
                }) {
                    mergeCardioFields(from: duplicate, into: canonical)
                    context.delete(duplicate)
                    existingCardioInboxItems.removeAll { $0 === duplicate }
                    mergedAnotherItem = true
                }
            }
        }

        try context.save()
    }

    /// Returns true only when two sessions have the same persisted content.
    ///
    /// Dates alone are deliberately not treated as identity: two real workouts can
    /// start at the same time (or within the same sync window). This conservative
    /// comparison is shared by backup import and the Settings deduplication tool.
    static func areWorkoutSessionsDefiniteDuplicates(
        _ lhs: WorkoutSession,
        _ rhs: WorkoutSession
    ) -> Bool {
        if lhs.id == rhs.id { return true }

        return sessionContent(for: lhs) == sessionContent(for: rhs)
            && exerciseContents(for: lhs.exerciseLogs ?? [])
                == exerciseContents(for: rhs.exerciseLogs ?? [])
    }

    static func areRunningSessionsDefiniteDuplicates(
        _ lhs: RunningSession,
        _ rhs: RunningSession
    ) -> Bool {
        lhs.id == rhs.id || runningSessionContent(for: lhs) == runningSessionContent(for: rhs)
    }

    static func areWeightEntriesDefiniteDuplicates(
        _ lhs: WeightEntry,
        _ rhs: WeightEntry
    ) -> Bool {
        lhs.id == rhs.id || weightEntryContent(for: lhs) == weightEntryContent(for: rhs)
    }

    private struct WorkoutSessionContent: Hashable {
        let date: Date
        let title: String
        let notes: String?
        let shouldSaveAsTemplate: Bool
        let sourceTemplateID: UUID?
        let generatedTemplateID: UUID?
        let isSampleData: Bool
        let healthWorkoutUUID: String?
        let healthDuration: TimeInterval?
        let healthCalories: Double?
        let healthAvgHeartRate: Double?
        let healthSourceName: String?
        let healthActivityType: String?
    }

    private struct ExerciseLogContent: Hashable {
        let reps: Int
        let weight: Double
        let weightUnit: String
        let setNumber: Int
        let exerciseName: String?
        let exerciseDefinitionID: UUID?
        let exerciseOrder: Int
        let exerciseType: String?
        let durationSeconds: Int?
        let distance: Double?
        let distanceUnit: String?
        let caloriesBurned: Int?
        let avgHeartRate: Int?
        let notes: String?
        let isCompleted: Bool
        let isIsolated: Bool
    }

    private struct RunningSessionContent: Hashable {
        let date: Date
        let distance: Double
        let distanceUnit: String
        let duration: TimeInterval
        let calories: Double?
        let notes: String?
        let locations: Data
        let healthWorkoutUUID: String?
        let metricSourceHealthWorkoutUUID: String?
        let linkedHealthWorkoutUUIDsRaw: String
        let healthMetricSourceName: String?
        let activityType: String
        let isSampleData: Bool
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let minHeartRate: Double?
        let avgCadence: Double?
        let maxCadence: Double?
        let avgStrideLength: Double?
        let verticalOscillation: Double?
        let groundContactTime: Double?
        let totalAscent: Double?
        let totalDescent: Double?
        let minElevation: Double?
        let maxElevation: Double?
        let avgPower: Double?
        let maxPower: Double?
    }

    private struct WeightEntryContent: Hashable {
        let date: Date
        let weight: Double
        let weightUnit: String
    }

    private static func areWorkoutSessionContentsEqual(
        dto: BackupFile.WorkoutSessionDTO,
        logs: [BackupFile.ExerciseLogDTO],
        model: WorkoutSession
    ) -> Bool {
        sessionContent(for: dto) == sessionContent(for: model)
            && exerciseContents(for: logs)
                == exerciseContents(for: model.exerciseLogs ?? [])
    }

    private static func sessionContent(for dto: BackupFile.WorkoutSessionDTO) -> WorkoutSessionContent {
        WorkoutSessionContent(
            date: dto.date,
            title: resolvedWorkoutTitle(dto.title),
            notes: dto.notes,
            shouldSaveAsTemplate: dto.shouldSaveAsTemplate ?? false,
            sourceTemplateID: dto.sourceTemplateID,
            generatedTemplateID: dto.generatedTemplateID,
            isSampleData: dto.isSampleData ?? false,
            healthWorkoutUUID: dto.healthWorkoutUUID,
            healthDuration: dto.healthDuration,
            healthCalories: dto.healthCalories,
            healthAvgHeartRate: dto.healthAvgHeartRate,
            healthSourceName: dto.healthSourceName,
            healthActivityType: dto.healthActivityType
        )
    }

    private static func sessionContent(for model: WorkoutSession) -> WorkoutSessionContent {
        WorkoutSessionContent(
            date: model.date,
            title: model.title,
            notes: model.notes,
            shouldSaveAsTemplate: model.shouldSaveAsTemplate,
            sourceTemplateID: model.sourceTemplateID,
            generatedTemplateID: model.generatedTemplate?.id,
            isSampleData: model.isSampleData,
            healthWorkoutUUID: model.healthWorkoutUUID,
            healthDuration: model.healthDuration,
            healthCalories: model.healthCalories,
            healthAvgHeartRate: model.healthAvgHeartRate,
            healthSourceName: model.healthSourceName,
            healthActivityType: model.healthActivityType
        )
    }

    private static func areRunningSessionContentsEqual(
        dto: BackupFile.RunningSessionDTO,
        model: RunningSession
    ) -> Bool {
        runningSessionContent(for: dto) == runningSessionContent(for: model)
    }

    private static func runningSessionContent(
        for dto: BackupFile.RunningSessionDTO
    ) -> RunningSessionContent {
        RunningSessionContent(
            date: dto.date,
            distance: dto.distance,
            distanceUnit: dto.distanceUnit,
            duration: dto.duration,
            calories: dto.calories,
            notes: dto.notes,
            locations: dto.locations,
            healthWorkoutUUID: dto.healthWorkoutUUID,
            metricSourceHealthWorkoutUUID: dto.metricSourceHealthWorkoutUUID,
            linkedHealthWorkoutUUIDsRaw: dto.linkedHealthWorkoutUUIDsRaw ?? "",
            healthMetricSourceName: dto.healthMetricSourceName,
            activityType: dto.activityType,
            isSampleData: dto.isSampleData ?? false,
            avgHeartRate: dto.avgHeartRate,
            maxHeartRate: dto.maxHeartRate,
            minHeartRate: dto.minHeartRate,
            avgCadence: dto.avgCadence,
            maxCadence: dto.maxCadence,
            avgStrideLength: dto.avgStrideLength,
            verticalOscillation: dto.verticalOscillation,
            groundContactTime: dto.groundContactTime,
            totalAscent: dto.totalAscent,
            totalDescent: dto.totalDescent,
            minElevation: dto.minElevation,
            maxElevation: dto.maxElevation,
            avgPower: dto.avgPower,
            maxPower: dto.maxPower
        )
    }

    private static func runningSessionContent(for model: RunningSession) -> RunningSessionContent {
        RunningSessionContent(
            date: model.date,
            distance: model.distance,
            distanceUnit: model.distanceUnit,
            duration: model.duration,
            calories: model.calories,
            notes: model.notes,
            locations: model.locations,
            healthWorkoutUUID: model.healthWorkoutUUID,
            metricSourceHealthWorkoutUUID: model.metricSourceHealthWorkoutUUID,
            linkedHealthWorkoutUUIDsRaw: model.linkedHealthWorkoutUUIDsRaw,
            healthMetricSourceName: model.healthMetricSourceName,
            activityType: model.activityType,
            isSampleData: model.isSampleData,
            avgHeartRate: model.avgHeartRate,
            maxHeartRate: model.maxHeartRate,
            minHeartRate: model.minHeartRate,
            avgCadence: model.avgCadence,
            maxCadence: model.maxCadence,
            avgStrideLength: model.avgStrideLength,
            verticalOscillation: model.verticalOscillation,
            groundContactTime: model.groundContactTime,
            totalAscent: model.totalAscent,
            totalDescent: model.totalDescent,
            minElevation: model.minElevation,
            maxElevation: model.maxElevation,
            avgPower: model.avgPower,
            maxPower: model.maxPower
        )
    }

    private static func areWeightEntryContentsEqual(
        dto: BackupFile.WeightEntryDTO,
        model: WeightEntry
    ) -> Bool {
        WeightEntryContent(date: dto.date, weight: dto.weight, weightUnit: dto.weightUnit)
            == weightEntryContent(for: model)
    }

    private static func weightEntryContent(for model: WeightEntry) -> WeightEntryContent {
        WeightEntryContent(
            date: model.date,
            weight: model.weight,
            weightUnit: model.weightUnit
        )
    }

    private static func exerciseContents(
        for dtos: [BackupFile.ExerciseLogDTO]
    ) -> [ExerciseLogContent: Int] {
        countedContents(dtos.map {
            ExerciseLogContent(
                reps: $0.reps,
                weight: $0.weight,
                weightUnit: $0.weightUnit,
                setNumber: $0.setNumber,
                exerciseName: $0.exerciseName,
                exerciseDefinitionID: $0.exerciseDefinitionId,
                exerciseOrder: $0.exerciseOrder ?? 0,
                exerciseType: $0.exerciseType ?? "strength",
                durationSeconds: $0.durationSeconds,
                distance: $0.distance,
                distanceUnit: $0.distanceUnit,
                caloriesBurned: $0.caloriesBurned,
                avgHeartRate: $0.avgHeartRate,
                notes: $0.notes,
                isCompleted: $0.isCompleted ?? false,
                isIsolated: $0.isIsolated ?? false
            )
        })
    }

    private static func exerciseContents(for logs: [ExerciseLog]) -> [ExerciseLogContent: Int] {
        countedContents(logs.map {
            ExerciseLogContent(
                reps: $0.reps,
                weight: $0.weight,
                weightUnit: $0.weightUnit,
                setNumber: $0.setNumber,
                exerciseName: $0.exerciseName,
                exerciseDefinitionID: $0.exerciseDefinition?.id,
                exerciseOrder: $0.exerciseOrder,
                exerciseType: $0.exerciseType,
                durationSeconds: $0.durationSeconds,
                distance: $0.distance,
                distanceUnit: $0.distanceUnit,
                caloriesBurned: $0.caloriesBurned,
                avgHeartRate: $0.avgHeartRate,
                notes: $0.notes,
                isCompleted: $0.isCompleted,
                isIsolated: $0.isIsolated
            )
        })
    }

    private static func countedContents<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func resolvedWorkoutTitle(_ title: String?) -> String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Gym Session"
        }
        return title
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
