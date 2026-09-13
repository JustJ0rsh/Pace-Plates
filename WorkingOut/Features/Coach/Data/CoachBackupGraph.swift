import Foundation
import SwiftData

/// Complete value graph for deliberate personal-history backup. Photos are assets
/// in the archive, never base64 payloads in this graph.
struct CoachBackupGraph: Codable, Sendable {
    struct TrainingPlanSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var sourceProgramID: String?
        var sourceRevision: Int
        var fingerprint: String?
        var currentRevisionID: UUID?
        var startCivilDate: String?
        var timeZoneIdentifier: String
        var durationWeeks: Int
        var activatedAt: Date?
        var pausedAt: Date?
        var title: String
        var goal: String
        var overview: String?
        var guidance: String?
        var source: String
        var status: String
        var startDate: Date
        var createdAt: Date
        var updatedAt: Date
        var sourceAIConversationID: UUID?
        var sourceRunningPlanID: UUID?

        @MainActor init(_ model: TrainingPlan) {
            id = model.id
            sourceProgramID = model.sourceProgramID
            sourceRevision = model.sourceRevision
            fingerprint = model.fingerprint
            currentRevisionID = model.currentRevisionID
            startCivilDate = model.startCivilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            durationWeeks = model.durationWeeks
            activatedAt = model.activatedAt
            pausedAt = model.pausedAt
            title = model.title
            goal = model.goal
            overview = model.overview
            guidance = model.guidance
            source = model.source
            status = model.status
            startDate = model.startDate
            createdAt = model.createdAt
            updatedAt = model.updatedAt
            sourceAIConversationID = model.sourceAIConversationID
            sourceRunningPlanID = model.sourceRunningPlanID
        }

        @MainActor func apply(to model: TrainingPlan) {
            model.id = id
            model.sourceProgramID = sourceProgramID
            model.sourceRevision = sourceRevision
            model.fingerprint = fingerprint
            model.currentRevisionID = currentRevisionID
            model.startCivilDate = startCivilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.durationWeeks = durationWeeks
            model.activatedAt = activatedAt
            model.pausedAt = pausedAt
            model.title = title
            model.goal = goal
            model.overview = overview
            model.guidance = guidance
            model.source = source
            model.status = status
            model.startDate = startDate
            model.createdAt = createdAt
            model.updatedAt = updatedAt
            model.sourceAIConversationID = sourceAIConversationID
            model.sourceRunningPlanID = sourceRunningPlanID
        }
    }

    struct PlannedSessionSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var sourceWeekID: String?
        var sourceSlotID: String?
        var sourceTemplateID: String?
        var phaseID: String?
        var prescriptionData: Data?
        var revisionID: UUID?
        var originalCivilDate: String?
        var currentCivilDate: String?
        var intraDayOrder: Int
        var isOptional: Bool
        var executionID: UUID?
        var scheduleRevision: Int
        var localScheduleOverride: Bool?
        var completionProvenance: String?
        var title: String
        var activityType: String
        var scheduledDate: Date
        var weekIndex: Int
        var dayIndex: Int
        var status: String
        var notes: String?
        var targetDistanceMeters: Double?
        var targetDurationSeconds: Double?
        var targetPaceMinPerMile: Double?
        var intensityLevel: String?
        var workoutTemplateID: UUID?
        var runningPlanSessionID: UUID?
        var completedWorkoutSessionID: UUID?
        var completedRunningSessionID: UUID?
        var completedAt: Date?
        var planID: UUID?

        @MainActor init(_ model: PlannedSession) {
            id = model.id
            sourceWeekID = model.sourceWeekID
            sourceSlotID = model.sourceSlotID
            sourceTemplateID = model.sourceTemplateID
            phaseID = model.phaseID
            prescriptionData = model.prescriptionData
            revisionID = model.revisionID
            originalCivilDate = model.originalCivilDate
            currentCivilDate = model.currentCivilDate
            intraDayOrder = model.intraDayOrder
            isOptional = model.isOptional
            executionID = model.executionID
            scheduleRevision = model.scheduleRevision
            localScheduleOverride = model.localScheduleOverride
            completionProvenance = model.completionProvenance
            title = model.title
            activityType = model.activityType
            scheduledDate = model.scheduledDate
            weekIndex = model.weekIndex
            dayIndex = model.dayIndex
            status = model.status
            notes = model.notes
            targetDistanceMeters = model.targetDistanceMeters
            targetDurationSeconds = model.targetDurationSeconds
            targetPaceMinPerMile = model.targetPaceMinPerMile
            intensityLevel = model.intensityLevel
            workoutTemplateID = model.workoutTemplateID
            runningPlanSessionID = model.runningPlanSessionID
            completedWorkoutSessionID = model.completedWorkoutSessionID
            completedRunningSessionID = model.completedRunningSessionID
            completedAt = model.completedAt
            planID = model.plan?.id
        }

        @MainActor func apply(to model: PlannedSession) {
            model.id = id
            model.sourceWeekID = sourceWeekID
            model.sourceSlotID = sourceSlotID
            model.sourceTemplateID = sourceTemplateID
            model.phaseID = phaseID
            model.prescriptionData = prescriptionData
            model.revisionID = revisionID
            model.originalCivilDate = originalCivilDate
            model.currentCivilDate = currentCivilDate
            model.intraDayOrder = intraDayOrder
            model.isOptional = isOptional
            model.executionID = executionID
            model.scheduleRevision = scheduleRevision
            model.localScheduleOverride = localScheduleOverride ?? (scheduleRevision > 0)
            model.completionProvenance = completionProvenance
            model.title = title
            model.activityType = activityType
            model.scheduledDate = scheduledDate
            model.weekIndex = weekIndex
            model.dayIndex = dayIndex
            model.status = status
            model.notes = notes
            model.targetDistanceMeters = targetDistanceMeters
            model.targetDurationSeconds = targetDurationSeconds
            model.targetPaceMinPerMile = targetPaceMinPerMile
            model.intensityLevel = intensityLevel
            model.workoutTemplateID = workoutTemplateID
            model.runningPlanSessionID = runningPlanSessionID
            model.completedWorkoutSessionID = completedWorkoutSessionID
            model.completedRunningSessionID = completedRunningSessionID
            model.completedAt = completedAt
        }
    }

    struct CoachPlanRevisionSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var planID: UUID
        var documentData: Data
        var fingerprint: String
        var sourceProgramID: String
        var sourceRevision: Int
        var schemaVersion: Int
        var provenance: String
        var exerciseMappingsData: Data?
        var createdAt: Date

        @MainActor init(_ model: CoachPlanRevision) {
            id = model.id
            planID = model.planID
            documentData = model.documentData
            fingerprint = model.fingerprint
            sourceProgramID = model.sourceProgramID
            sourceRevision = model.sourceRevision
            schemaVersion = model.schemaVersion
            provenance = model.provenance
            exerciseMappingsData = model.exerciseMappingsData
            createdAt = model.createdAt
        }

        @MainActor func apply(to model: CoachPlanRevision) {
            model.id = id
            model.planID = planID
            model.documentData = documentData
            model.fingerprint = fingerprint
            model.sourceProgramID = sourceProgramID
            model.sourceRevision = sourceRevision
            model.schemaVersion = schemaVersion
            model.provenance = provenance
            model.exerciseMappingsData = exerciseMappingsData
            model.createdAt = createdAt
        }
    }

    struct CoachSessionExecutionSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var plannedSessionID: UUID?
        var workoutSessionID: UUID?
        var runSessionID: UUID?
        var startedAt: Date
        var endedAt: Date?
        var statusRaw: String
        var prescriptionRevisionID: UUID?
        var prescriptionData: Data?
        var snapshotData: Data?
        var provenance: String
        var effortScale: String?
        var effort: Double?
        var notes: String?
        var updatedAt: Date

        @MainActor init(_ model: CoachSessionExecution) {
            id = model.id
            plannedSessionID = model.plannedSessionID
            workoutSessionID = model.workoutSessionID
            runSessionID = model.runSessionID
            startedAt = model.startedAt
            endedAt = model.endedAt
            statusRaw = model.statusRaw
            prescriptionRevisionID = model.prescriptionRevisionID
            prescriptionData = model.prescriptionData
            snapshotData = model.snapshotData
            provenance = model.provenance
            effortScale = model.effortScale
            effort = model.effort
            notes = model.notes
            updatedAt = model.updatedAt
        }

        @MainActor func apply(to model: CoachSessionExecution) {
            model.id = id
            model.plannedSessionID = plannedSessionID
            model.workoutSessionID = workoutSessionID
            model.runSessionID = runSessionID
            model.startedAt = startedAt
            model.endedAt = endedAt
            model.statusRaw = statusRaw
            model.prescriptionRevisionID = prescriptionRevisionID
            model.prescriptionData = prescriptionData
            model.snapshotData = snapshotData
            model.provenance = provenance
            model.effortScale = effortScale
            model.effort = effort
            model.notes = notes
            model.updatedAt = updatedAt
        }
    }

    struct CoachProgressionSuggestionSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var planID: UUID
        var ruleID: String
        var exerciseID: String?
        var sourceTemplateID: String
        var evidenceIDsData: Data
        var evidenceFingerprint: String
        var proposedPrescriptionData: Data
        var reason: String
        var statusRaw: String
        var selectedOccurrenceIDsData: Data?
        var createdAt: Date
        var decidedAt: Date?

        @MainActor init(_ model: CoachProgressionSuggestion) {
            id = model.id
            planID = model.planID
            ruleID = model.ruleID
            exerciseID = model.exerciseID
            sourceTemplateID = model.sourceTemplateID
            evidenceIDsData = model.evidenceIDsData
            evidenceFingerprint = model.evidenceFingerprint
            proposedPrescriptionData = model.proposedPrescriptionData
            reason = model.reason
            statusRaw = model.statusRaw
            selectedOccurrenceIDsData = model.selectedOccurrenceIDsData
            createdAt = model.createdAt
            decidedAt = model.decidedAt
        }

        @MainActor func apply(to model: CoachProgressionSuggestion) {
            model.id = id
            model.planID = planID
            model.ruleID = ruleID
            model.exerciseID = exerciseID
            model.sourceTemplateID = sourceTemplateID
            model.evidenceIDsData = evidenceIDsData
            model.evidenceFingerprint = evidenceFingerprint
            model.proposedPrescriptionData = proposedPrescriptionData
            model.reason = reason
            model.statusRaw = statusRaw
            model.selectedOccurrenceIDsData = selectedOccurrenceIDsData
            model.createdAt = createdAt
            model.decidedAt = decidedAt
        }
    }

    struct CoachNutritionTargetPeriodSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var planID: UUID?
        var phaseID: String?
        var startCivilDate: String
        var endCivilDate: String?
        var timeZoneIdentifier: String
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var notes: String?
        var revisionID: UUID?
        var createdAt: Date

        @MainActor init(_ model: CoachNutritionTargetPeriod) {
            id = model.id
            planID = model.planID
            phaseID = model.phaseID
            startCivilDate = model.startCivilDate
            endCivilDate = model.endCivilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            calories = model.calories
            protein = model.protein
            carbs = model.carbs
            fat = model.fat
            notes = model.notes
            revisionID = model.revisionID
            createdAt = model.createdAt
        }

        @MainActor func apply(to model: CoachNutritionTargetPeriod) {
            model.id = id
            model.planID = planID
            model.phaseID = phaseID
            model.startCivilDate = startCivilDate
            model.endCivilDate = endCivilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.calories = calories
            model.protein = protein
            model.carbs = carbs
            model.fat = fat
            model.notes = notes
            model.revisionID = revisionID
            model.createdAt = createdAt
        }
    }

    struct CoachNutritionLogSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var civilDate: String
        var timeZoneIdentifier: String
        var calories: Double?
        var protein: Double?
        var carbs: Double?
        var fat: Double?
        var targetSnapshotData: Data?
        var statusRaw: String
        var notes: String?
        var createdAt: Date
        var updatedAt: Date

        @MainActor init(_ model: CoachNutritionLog) {
            id = model.id
            civilDate = model.civilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            calories = model.calories
            protein = model.protein
            carbs = model.carbs
            fat = model.fat
            targetSnapshotData = model.targetSnapshotData
            statusRaw = model.statusRaw
            notes = model.notes
            createdAt = model.createdAt
            updatedAt = model.updatedAt
        }

        @MainActor func apply(to model: CoachNutritionLog) {
            model.id = id
            model.civilDate = civilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.calories = calories
            model.protein = protein
            model.carbs = carbs
            model.fat = fat
            model.targetSnapshotData = targetSnapshotData
            model.statusRaw = statusRaw
            model.notes = notes
            model.createdAt = createdAt
            model.updatedAt = updatedAt
        }
    }

    struct CoachRecoveryCheckInSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var civilDate: String
        var timeZoneIdentifier: String
        var manualSleepHours: Double?
        var healthSleepHours: Double?
        var healthSleepSource: String?
        var healthSleepEndDate: Date?
        var healthSampleCoverageData: Data?
        var sleepSourceRaw: String
        var soreness: Int?
        var energy: Int?
        var painScore: Int?
        var painLocation: String?
        var notes: String?
        var createdAt: Date
        var updatedAt: Date

        @MainActor init(_ model: CoachRecoveryCheckIn) {
            id = model.id
            civilDate = model.civilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            manualSleepHours = model.manualSleepHours
            healthSleepHours = model.healthSleepHours
            healthSleepSource = model.healthSleepSource
            healthSleepEndDate = model.healthSleepEndDate
            healthSampleCoverageData = model.healthSampleCoverageData
            sleepSourceRaw = model.sleepSourceRaw
            soreness = model.soreness
            energy = model.energy
            painScore = model.painScore
            painLocation = model.painLocation
            notes = model.notes
            createdAt = model.createdAt
            updatedAt = model.updatedAt
        }

        @MainActor func apply(to model: CoachRecoveryCheckIn) {
            model.id = id
            model.civilDate = civilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.manualSleepHours = manualSleepHours
            model.healthSleepHours = healthSleepHours
            model.healthSleepSource = healthSleepSource
            model.healthSleepEndDate = healthSleepEndDate
            model.healthSampleCoverageData = healthSampleCoverageData
            model.sleepSourceRaw = sleepSourceRaw
            model.soreness = soreness
            model.energy = energy
            model.painScore = painScore
            model.painLocation = painLocation
            model.notes = notes
            model.createdAt = createdAt
            model.updatedAt = updatedAt
        }
    }

    struct CoachWaistMeasurementSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var observedAt: Date
        var civilDate: String
        var timeZoneIdentifier: String
        var value: Double
        var unit: String
        var notes: String?

        @MainActor init(_ model: CoachWaistMeasurement) {
            id = model.id
            observedAt = model.observedAt
            civilDate = model.civilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            value = model.value
            unit = model.unit
            notes = model.notes
        }

        @MainActor func apply(to model: CoachWaistMeasurement) {
            model.id = id
            model.observedAt = observedAt
            model.civilDate = civilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.value = value
            model.unit = unit
            model.notes = notes
        }
    }

    struct CoachProgressPhotoSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var observedAt: Date
        var civilDate: String
        var timeZoneIdentifier: String
        var pose: String?
        var assetKey: String
        var pixelWidth: Int
        var pixelHeight: Int
        var contentType: String
        var digest: String
        var byteCount: Int
        var importState: String
        var createdAt: Date

        @MainActor init(_ model: CoachProgressPhoto) {
            id = model.id
            observedAt = model.observedAt
            civilDate = model.civilDate
            timeZoneIdentifier = model.timeZoneIdentifier
            pose = model.pose
            assetKey = model.assetKey
            pixelWidth = model.pixelWidth
            pixelHeight = model.pixelHeight
            contentType = model.contentType
            digest = model.digest
            byteCount = model.byteCount
            importState = model.importState
            createdAt = model.createdAt
        }

        @MainActor func apply(to model: CoachProgressPhoto) {
            model.id = id
            model.observedAt = observedAt
            model.civilDate = civilDate
            model.timeZoneIdentifier = timeZoneIdentifier
            model.pose = pose
            model.assetKey = assetKey
            model.pixelWidth = pixelWidth
            model.pixelHeight = pixelHeight
            model.contentType = contentType
            model.digest = digest
            model.byteCount = byteCount
            model.importState = importState
            model.createdAt = createdAt
        }
    }

    struct CoachPhaseReviewSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var planID: UUID
        var phaseID: String
        var revisionID: UUID?
        var statusRaw: String
        var notes: String?
        var reviewedAt: Date?

        @MainActor init(_ model: CoachPhaseReview) {
            id = model.id
            planID = model.planID
            phaseID = model.phaseID
            revisionID = model.revisionID
            statusRaw = model.statusRaw
            notes = model.notes
            reviewedAt = model.reviewedAt
        }

        @MainActor func apply(to model: CoachPhaseReview) {
            model.id = id
            model.planID = planID
            model.phaseID = phaseID
            model.revisionID = revisionID
            model.statusRaw = statusRaw
            model.notes = notes
            model.reviewedAt = reviewedAt
        }
    }

    struct CoachCalendarMappingSnapshot: Codable, Equatable, Sendable {
        var id: UUID
        var plannedSessionID: UUID
        var calendarID: String
        var eventID: String
        var requestedStartDate: Date?
        var exportedScheduleRevision: Int
        var pendingProjection: Bool

        @MainActor init(_ model: CoachCalendarMapping) {
            id = model.id
            plannedSessionID = model.plannedSessionID
            calendarID = model.calendarID
            eventID = model.eventID
            requestedStartDate = model.requestedStartDate
            exportedScheduleRevision = model.exportedScheduleRevision
            pendingProjection = model.pendingProjection
        }

        @MainActor func apply(to model: CoachCalendarMapping) {
            model.id = id
            model.plannedSessionID = plannedSessionID
            model.calendarID = calendarID
            model.eventID = eventID
            model.requestedStartDate = requestedStartDate
            model.exportedScheduleRevision = exportedScheduleRevision
            model.pendingProjection = pendingProjection
        }
    }

    var trainingPlans: [TrainingPlanSnapshot] = []
    var plannedSessions: [PlannedSessionSnapshot] = []
    var revisions: [CoachPlanRevisionSnapshot] = []
    var executions: [CoachSessionExecutionSnapshot] = []
    var suggestions: [CoachProgressionSuggestionSnapshot] = []
    var targets: [CoachNutritionTargetPeriodSnapshot] = []
    var nutrition: [CoachNutritionLogSnapshot] = []
    var recovery: [CoachRecoveryCheckInSnapshot] = []
    var waist: [CoachWaistMeasurementSnapshot] = []
    var photos: [CoachProgressPhotoSnapshot] = []
    var phaseReviews: [CoachPhaseReviewSnapshot] = []
    var calendarMappings: [CoachCalendarMappingSnapshot] = []

    var hasPersonalRecords: Bool {
        trainingPlans.contains { $0.sourceProgramID != nil } || plannedSessions.contains { $0.prescriptionData != nil || $0.executionID != nil } || !revisions.isEmpty || !executions.isEmpty || !suggestions.isEmpty || !targets.isEmpty || !nutrition.isEmpty || !recovery.isEmpty || !waist.isEmpty || !photos.isEmpty || !phaseReviews.isEmpty || !calendarMappings.isEmpty
    }

    @MainActor static func capture(context: ModelContext) throws -> CoachBackupGraph {
        var graph = CoachBackupGraph()
        graph.trainingPlans = try context.fetch(FetchDescriptor<TrainingPlan>()).map(TrainingPlanSnapshot.init)
        graph.plannedSessions = try context.fetch(FetchDescriptor<PlannedSession>()).map(PlannedSessionSnapshot.init)
        if CoachPersistence.isLocal(context) {
            graph.revisions = try context.fetch(FetchDescriptor<CoachPlanRevision>()).map(CoachPlanRevisionSnapshot.init)
            graph.executions = try context.fetch(FetchDescriptor<CoachSessionExecution>()).map(CoachSessionExecutionSnapshot.init)
            graph.suggestions = try context.fetch(FetchDescriptor<CoachProgressionSuggestion>()).map(CoachProgressionSuggestionSnapshot.init)
            graph.targets = try context.fetch(FetchDescriptor<CoachNutritionTargetPeriod>()).map(CoachNutritionTargetPeriodSnapshot.init)
            graph.nutrition = try context.fetch(FetchDescriptor<CoachNutritionLog>()).map(CoachNutritionLogSnapshot.init)
            graph.recovery = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>()).map(CoachRecoveryCheckInSnapshot.init)
            graph.waist = try context.fetch(FetchDescriptor<CoachWaistMeasurement>()).map(CoachWaistMeasurementSnapshot.init)
            graph.photos = try context.fetch(FetchDescriptor<CoachProgressPhoto>()).map(CoachProgressPhotoSnapshot.init)
            graph.phaseReviews = try context.fetch(FetchDescriptor<CoachPhaseReview>()).map(CoachPhaseReviewSnapshot.init)
            graph.calendarMappings = try context.fetch(FetchDescriptor<CoachCalendarMapping>()).map(CoachCalendarMappingSnapshot.init)
        }
        return graph
    }

    func validate() throws {
        guard Set(trainingPlans.map(\.id)).count == trainingPlans.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate trainingPlans identity") }
        guard Set(plannedSessions.map(\.id)).count == plannedSessions.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate plannedSessions identity") }
        guard Set(revisions.map(\.id)).count == revisions.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate revisions identity") }
        guard Set(executions.map(\.id)).count == executions.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate executions identity") }
        guard Set(suggestions.map(\.id)).count == suggestions.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate suggestions identity") }
        guard Set(targets.map(\.id)).count == targets.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate targets identity") }
        guard Set(nutrition.map(\.id)).count == nutrition.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate nutrition identity") }
        guard Set(recovery.map(\.id)).count == recovery.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate recovery identity") }
        guard Set(waist.map(\.id)).count == waist.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate waist identity") }
        guard Set(photos.map(\.id)).count == photos.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate photos identity") }
        guard Set(phaseReviews.map(\.id)).count == phaseReviews.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate phaseReviews identity") }
        guard Set(calendarMappings.map(\.id)).count == calendarMappings.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate calendarMappings identity") }
        guard Set(nutrition.map(\.civilDate)).count == nutrition.count,
              Set(recovery.map(\.civilDate)).count == recovery.count else { throw CoachHistoryArchive.ArchiveError.invalid("More than one daily record has the same civil date") }
        let planIDs = Set(trainingPlans.map(\.id))
        guard plannedSessions.allSatisfy({ $0.planID == nil || planIDs.contains($0.planID!) }) else { throw CoachHistoryArchive.ArchiveError.invalid("Missing parent plan") }
        guard Set(photos.map(\.assetKey)).count == photos.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate photo asset path") }
        for photo in photos {
            guard CoachPhotoStore.isSafeAssetKey(photo.assetKey), UUID(uuidString: String(photo.assetKey.dropLast(4))) == photo.id,
                  photo.byteCount > 0, photo.byteCount <= CoachPhotoStore.maxSourceBytes,
                  (1...2048).contains(photo.pixelWidth), (1...2048).contains(photo.pixelHeight), photo.contentType == "image/jpeg",
                  photo.digest.count == 64, photo.digest.allSatisfy(\.isHexDigit) else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid photo metadata") }
        }
        for target in targets {
            guard [target.calories, target.protein, target.carbs, target.fat].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1_000_000).contains($0) }),
                  target.calories.map({ $0.rounded() == $0 }) ?? true,
                  target.endCivilDate.map({ $0 > target.startCivilDate }) ?? true else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid nutrition target period") }
        }
        for row in nutrition {
            guard [row.calories, row.protein, row.carbs, row.fat].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...1_000_000).contains($0) }), ["draft", "final"].contains(row.statusRaw) else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid daily nutrition record") }
        }
        for row in recovery {
            guard [row.manualSleepHours, row.healthSleepHours].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...48).contains($0) }),
                  row.soreness.map({ (0...10).contains($0) }) ?? true,
                  row.energy.map({ (1...5).contains($0) }) ?? true,
                  row.painScore.map({ (0...10).contains($0) }) ?? true else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid recovery record") }
        }
        for row in waist {
            guard row.value.isFinite && row.value > 0 && ["cm", "in"].contains(row.unit) else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid waist measurement") }
        }
        for execution in executions {
            guard CoachExecutionStatus(rawValue: execution.statusRaw) != nil else { throw CoachHistoryArchive.ArchiveError.invalid("Unknown execution state") }
            if let prescription = execution.prescriptionData {
                _ = try CoachSchedule.steps(for: JSONDecoder().decode(CoachSessionTemplate.self, from: prescription))
            }
            if let data = execution.snapshotData {
                let snapshot = try JSONDecoder().decode(CoachExecutionSnapshot.self, from: data)
                guard snapshot.version == 1, snapshot.setResults.count <= 10_000, Set(snapshot.setResults.map(\.id)).count == snapshot.setResults.count,
                      snapshot.setResults.allSatisfy(\.isValid),
                      snapshot.effort.map({ $0.isFinite && (0...10).contains($0) && ["rpe", "rir"].contains(snapshot.effortScale) }) ?? true,
                      snapshot.intervalState?.isValid ?? true else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid actual execution snapshot") }
                if let timer = snapshot.restTimer {
                    guard timer.maximumRemaining.isFinite && timer.maximumRemaining >= 0,
                          timer.pausedRemaining.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid rest timer") }
                }
                if let recoveryData = snapshot.runRecoveryData {
                    let checkpoint = try JSONDecoder().decode(RunRecoverySnapshot.self, from: recoveryData)
                    guard checkpoint.isValid else { throw CoachHistoryArchive.ArchiveError.invalid("Invalid run recovery snapshot") }
                    if execution.statusRaw == "in_progress" {
                        guard checkpoint.plannedTarget?.executionID == execution.id,
                              checkpoint.plannedTarget?.canonicalOccurrenceID == execution.plannedSessionID else { throw CoachHistoryArchive.ArchiveError.invalid("Run recovery identity does not match execution") }
                    }
                }
            }
        }
    }

    /// Check conflicts before any restore mutation. A backup cannot choose a
    /// field-by-field daily merge or overwrite immutable prescription/photo data.
    @MainActor func validateMerge(context: ModelContext) throws {
        guard CoachPersistence.isLocal(context) else { return }
        let existingPlans = try context.fetch(FetchDescriptor<TrainingPlan>())
        let existingPlanIDs = Set(existingPlans.map(\.id))
        if existingPlans.contains(where: { $0.status == "active" }),
           trainingPlans.contains(where: { $0.status == "active" && !existingPlanIDs.contains($0.id) }) {
            throw CoachHistoryArchive.ArchiveError.invalid("Another program is active; pause it before restoring a different active program")
        }
        let existingNutrition = try context.fetch(FetchDescriptor<CoachNutritionLog>())
        let nutritionIDs = Set(existingNutrition.map(\.id))
        for row in nutrition where !nutritionIDs.contains(row.id) {
            guard !existingNutrition.contains(where: { $0.civilDate == row.civilDate }) else {
                throw CoachHistoryArchive.ArchiveError.invalid("Nutrition already exists on \(row.civilDate); review the daily records before restoring")
            }
        }
        let existingRecovery = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
        let recoveryIDs = Set(existingRecovery.map(\.id))
        for row in recovery where !recoveryIDs.contains(row.id) {
            guard !existingRecovery.contains(where: { $0.civilDate == row.civilDate }) else {
                throw CoachHistoryArchive.ArchiveError.invalid("Recovery already exists on \(row.civilDate); review the daily records before restoring")
            }
        }
        let localRevisions = try context.fetch(FetchDescriptor<CoachPlanRevision>())
        for row in revisions {
            if let existing = localRevisions.first(where: { $0.id == row.id }), row != CoachPlanRevisionSnapshot(existing) {
                throw CoachHistoryArchive.ArchiveError.invalid("An existing immutable plan revision has different content")
            }
        }
        let localPhotos = try context.fetch(FetchDescriptor<CoachProgressPhoto>())
        for row in photos {
            if let existing = localPhotos.first(where: { $0.id == row.id }),
               existing.assetKey != row.assetKey || existing.digest != row.digest || existing.byteCount != row.byteCount {
                throw CoachHistoryArchive.ArchiveError.invalid("An existing photo identity has different image content")
            }
        }
    }

    @MainActor func restore(context: ModelContext) throws {
        let existingTrainingPlan = try context.fetch(FetchDescriptor<TrainingPlan>())
        let idsTrainingPlan = Set(existingTrainingPlan.map(\.id))
        for snapshot in trainingPlans where !idsTrainingPlan.contains(snapshot.id) {
            let model = TrainingPlan(title: snapshot.title, goal: snapshot.goal, source: snapshot.source, startDate: snapshot.startDate)
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingPlannedSession = try context.fetch(FetchDescriptor<PlannedSession>())
        let idsPlannedSession = Set(existingPlannedSession.map(\.id))
        for snapshot in plannedSessions where !idsPlannedSession.contains(snapshot.id) {
            let model = PlannedSession(title: snapshot.title, activityType: snapshot.activityType, scheduledDate: snapshot.scheduledDate, weekIndex: snapshot.weekIndex, dayIndex: snapshot.dayIndex)
            snapshot.apply(to: model)
            model.plan = try context.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == snapshot.planID }
            context.insert(model)
        }
        guard CoachPersistence.isLocal(context) else { return }
        let localRevisions = try context.fetch(FetchDescriptor<CoachPlanRevision>())
        for snapshot in revisions {
            if let existing = localRevisions.first(where: { $0.id == snapshot.id }),
               snapshot != CoachPlanRevisionSnapshot(existing) {
                throw CoachHistoryArchive.ArchiveError.invalid("An existing immutable plan revision has different content")
            }
        }
        let existingCoachPlanRevision = try context.fetch(FetchDescriptor<CoachPlanRevision>())
        let idsCoachPlanRevision = Set(existingCoachPlanRevision.map(\.id))
        for snapshot in revisions where !idsCoachPlanRevision.contains(snapshot.id) {
            let model = CoachPlanRevision()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachSessionExecution = try context.fetch(FetchDescriptor<CoachSessionExecution>())
        let idsCoachSessionExecution = Set(existingCoachSessionExecution.map(\.id))
        for snapshot in executions where !idsCoachSessionExecution.contains(snapshot.id) {
            let model = CoachSessionExecution()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachProgressionSuggestion = try context.fetch(FetchDescriptor<CoachProgressionSuggestion>())
        let idsCoachProgressionSuggestion = Set(existingCoachProgressionSuggestion.map(\.id))
        for snapshot in suggestions where !idsCoachProgressionSuggestion.contains(snapshot.id) {
            let model = CoachProgressionSuggestion()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachNutritionTargetPeriod = try context.fetch(FetchDescriptor<CoachNutritionTargetPeriod>())
        let idsCoachNutritionTargetPeriod = Set(existingCoachNutritionTargetPeriod.map(\.id))
        for snapshot in targets where !idsCoachNutritionTargetPeriod.contains(snapshot.id) {
            let model = CoachNutritionTargetPeriod()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachNutritionLog = try context.fetch(FetchDescriptor<CoachNutritionLog>())
        let idsCoachNutritionLog = Set(existingCoachNutritionLog.map(\.id))
        for snapshot in nutrition where !idsCoachNutritionLog.contains(snapshot.id) {
            let model = CoachNutritionLog()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachRecoveryCheckIn = try context.fetch(FetchDescriptor<CoachRecoveryCheckIn>())
        let idsCoachRecoveryCheckIn = Set(existingCoachRecoveryCheckIn.map(\.id))
        for snapshot in recovery where !idsCoachRecoveryCheckIn.contains(snapshot.id) {
            let model = CoachRecoveryCheckIn()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachWaistMeasurement = try context.fetch(FetchDescriptor<CoachWaistMeasurement>())
        let idsCoachWaistMeasurement = Set(existingCoachWaistMeasurement.map(\.id))
        for snapshot in waist where !idsCoachWaistMeasurement.contains(snapshot.id) {
            let model = CoachWaistMeasurement()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachProgressPhoto = try context.fetch(FetchDescriptor<CoachProgressPhoto>())
        let idsCoachProgressPhoto = Set(existingCoachProgressPhoto.map(\.id))
        for snapshot in photos where !idsCoachProgressPhoto.contains(snapshot.id) {
            let model = CoachProgressPhoto()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachPhaseReview = try context.fetch(FetchDescriptor<CoachPhaseReview>())
        let idsCoachPhaseReview = Set(existingCoachPhaseReview.map(\.id))
        for snapshot in phaseReviews where !idsCoachPhaseReview.contains(snapshot.id) {
            let model = CoachPhaseReview()
            snapshot.apply(to: model)
            context.insert(model)
        }
        let existingCoachCalendarMapping = try context.fetch(FetchDescriptor<CoachCalendarMapping>())
        let idsCoachCalendarMapping = Set(existingCoachCalendarMapping.map(\.id))
        for snapshot in calendarMappings where !idsCoachCalendarMapping.contains(snapshot.id) {
            let model = CoachCalendarMapping()
            snapshot.apply(to: model)
            context.insert(model)
        }
    }
}

extension BackupFile {
    func validateForRestore() throws {
        func unique(_ ids: [UUID], _ label: String) throws {
            guard Set(ids).count == ids.count else { throw CoachHistoryArchive.ArchiveError.invalid("Duplicate \(label) identity") }
        }
        try unique(exerciseDefinitions.map(\.id), "exercise")
        try unique(workoutSessions.map(\.id), "workout")
        try unique(exerciseLogs.map(\.id), "set")
        try unique(runningSessions.map(\.id), "run")
        try unique(weightEntries.map(\.id), "weight")
        try unique((runningPlans ?? []).map(\.id), "running plan")
        try unique((runningPlanSessions ?? []).map(\.id), "running plan session")
        try unique((aiConversations ?? []).map(\.id), "conversation")
        try unique((workoutTemplates ?? []).map(\.id), "template")
        try unique((templateExercises ?? []).map(\.id), "template exercise")
        try unique((healthWorkoutInboxItems ?? []).map(\.id), "Health inbox")
        try unique((cardioWorkoutInboxItems ?? []).map(\.id), "cardio inbox")
        try coach?.validate()
    }
}
