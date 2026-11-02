#if DEBUG
import Foundation
import SwiftData
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum CoachDuplicateBackupRegressionChecks {
    /// Actual archive export, deliberate saved copy, public import, disk reopen
    /// and repeat import. Every model type has synthetic data; no CloudKit owner.
    static func run() async throws -> Int {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("CoachDuplicateBackupChecks-\(UUID())", isDirectory: true)
        try CoachLocalOwnership.prepareDirectory(root)
        defer { try? files.removeItem(at: root) }
        func store(_ name: String) throws -> ModelContainer {
            let schema = PersistenceController.coachSchema
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: root.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)])
        }
        var count = try deduplicationIdentityChecks()
        func require(_ condition: Bool, _ message: String) throws {
            count += 1
            if !condition { throw CoachRepositoryError.invalidValue("duplicate backup regression: " + message) }
        }
        let source = try store("source"), context = source.mainContext
        let repository = CoachRepository(context: context)
        let date = Date()
        let template = CoachSessionTemplate.strength(.init(id: "lift", title: "Synthetic lift", exercises: [
            .init(id: "press", exercise: .init(key: "press", name: "Synthetic archive press", equipment: ["dumbbell"]),
                  prescriptionBasis: .perSide, loadBasis: .perImplement,
                  sets: [.init(id: "work", role: .working, target: .reps(min: 6, max: 10))])
        ]))
        let document = CoachPlanDocument(programId: "duplicate_archive_\(UUID())", title: "Synthetic archive program", goal: "Preserve history",
            nutritionTargets: .init(caloriesKcal: 2100, proteinGrams: 120),
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)], sessionTemplates: [template],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "lift")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let planID = try await repository.importPlan(document: document, startDate: date, activate: true, allowCreatingExercises: true)
        let occurrence = try repository.occurrences(planID: planID).first!
        let revision = try context.fetch(FetchDescriptor<CoachPlanRevision>()).first!
        let definitionID = UUID(), workoutID = UUID(), logID = UUID(), runID = UUID(), runSlotID = UUID()
        let leftDefinition = ExerciseDefinition(id: definitionID, name: "Synthetic left definition", muscleGroup: "Chest", isUserDefined: true)
        let rightDefinition = ExerciseDefinition(id: definitionID, name: "Synthetic right definition", muscleGroup: "Back", isUserDefined: true)
        let leftWorkout = WorkoutSession(id: workoutID, date: date, notes: "Left workout payload", title: "Synthetic left workout", executionStatus: .completed)
        let rightWorkout = WorkoutSession(id: workoutID, date: date.addingTimeInterval(3600), notes: "Right workout payload", title: "Synthetic right workout", executionStatus: .partial)
        let leftLog = ExerciseLog(id: logID, reps: 7, weight: 41, weightUnit: "kg", setNumber: 1, notes: "Synthetic left set", isCompleted: true)
        let rightLog = ExerciseLog(id: logID, reps: 11, weight: 53, weightUnit: "kg", setNumber: 2, notes: "Synthetic right set", isCompleted: true)
        leftLog.exerciseDefinition = leftDefinition; leftLog.workoutSession = leftWorkout; leftLog.actualWeight = 41
        rightLog.exerciseDefinition = rightDefinition; rightLog.workoutSession = rightWorkout; rightLog.actualWeight = 53
        let route = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 17 &+ 19) })
        let leftRun = RunningSession(id: runID, date: date, distance: 3.25, duration: 900, notes: "Synthetic left run", locations: route)
        let rightRun = RunningSession(id: runID, date: date.addingTimeInterval(3600), distance: 8.75, duration: 2400, notes: "Synthetic right run")
        let runningPlan = RunningPlan(name: "Synthetic running plan", style: "hybrid", targetDistanceMeters: 5000,
            primaryGoal: "consistency", durationWeeks: 1, daysPerWeek: 2, startDate: date)
        let leftSlot = RunningPlanSession(id: runSlotID, plan: runningPlan, completedRun: leftRun, weekIndex: 0, dayIndex: 0,
            sessionType: "easy", intensityLevel: "easy", notes: "Synthetic left slot", status: "completed", completedRunSessionID: runID)
        let rightSlot = RunningPlanSession(id: runSlotID, plan: runningPlan, completedRun: rightRun, weekIndex: 0, dayIndex: 1,
            sessionType: "long", intensityLevel: "moderate", notes: "Synthetic right slot", status: "completed", completedRunSessionID: runID)
        runningPlan.sessions = [leftSlot, rightSlot]
        leftRun.plannedSession = leftSlot; leftRun.plannedSessionID = runSlotID
        rightRun.plannedSession = rightSlot; rightRun.plannedSessionID = runSlotID
        let conversation = AIConversation(mode: "workout", goal: "Synthetic goal", prompt: "Synthetic prompt", response: "Synthetic response", model: "fixture")
        let savedTemplate = WorkoutTemplate(title: "Synthetic saved template", notes: "Keep source relationship", sourceAIConversationId: conversation.id, exerciseCount: 1)
        savedTemplate.sourceSession = leftWorkout
        let exercise = TemplateExercise(name: "Synthetic template exercise", order: 0, sets: 3, reps: 8, suggestedWeight: 12.5, weightUnit: "kg")
        exercise.template = savedTemplate
        for row in [leftDefinition, rightDefinition] { context.insert(row) }
        for row in [leftWorkout, rightWorkout] { context.insert(row) }
        for row in [leftLog, rightLog] { context.insert(row) }
        for row in [leftRun, rightRun] { context.insert(row) }
        context.insert(runningPlan); context.insert(leftSlot); context.insert(rightSlot)
        context.insert(conversation); context.insert(savedTemplate); context.insert(exercise)
        let execution = CoachSessionExecution()
        execution.plannedSessionID = occurrence.id; execution.workoutSessionID = leftWorkout.id; execution.runSessionID = leftRun.id
        execution.prescriptionRevisionID = revision.id; execution.prescriptionData = try JSONEncoder().encode(template)
        execution.snapshotData = try JSONEncoder().encode(CoachExecutionSnapshot()); execution.statusRaw = "completed"
        occurrence.executionID = execution.id; occurrence.status = "completed"; occurrence.completedAt = date
        let suggestion = CoachProgressionSuggestion()
        suggestion.planID = planID; suggestion.ruleID = "synthetic"; suggestion.sourceTemplateID = "lift"
        suggestion.evidenceIDsData = try JSONEncoder().encode([execution.id]); suggestion.evidenceFingerprint = "synthetic"
        suggestion.proposedPrescriptionData = try JSONEncoder().encode(template); suggestion.reason = "Synthetic evidence"
        let phase = CoachPhaseReview(); phase.planID = planID; phase.phaseID = "phase"; phase.revisionID = revision.id; phase.notes = "Keep phase review"
        let calendar = CoachCalendarMapping(); calendar.plannedSessionID = occurrence.id; calendar.calendarID = "fixture"; calendar.eventID = "fixture-event"; calendar.requestedStartDate = date
        context.insert(execution); context.insert(suggestion); context.insert(phase); context.insert(calendar)
        try context.save()
        _ = try repository.saveNutrition(date: date, calories: 0, protein: nil, carbs: 50, fat: nil, isFinal: true)
        _ = try repository.saveRecovery(date: date, manualSleepHours: 7.5, soreness: 0, energy: nil, painScore: 0)
        _ = try repository.saveWeight(date: date, value: 80, unit: "kg")
        _ = try repository.saveWaist(date: date, value: 90, unit: "cm")
        let inboxID = UUID(), cardioID = UUID()
        for index in 0...1 {
            let inbox = HealthWorkoutInboxItem(id: inboxID, healthWorkoutUUID: "synthetic-shared-health", startDate: date, endDate: date.addingTimeInterval(900), activityType: "traditionalStrengthTraining", duration: Double(900 + index), sourceName: "Synthetic source \(index)")
            inbox.statusRaw = index == 0 ? "linked" : "dismissed"; inbox.linkedWorkoutSessionID = workoutID
            let cardio = CardioWorkoutInboxItem(id: cardioID, healthWorkoutUUID: "synthetic-shared-cardio", startDate: date, endDate: date.addingTimeInterval(900), activityType: "running", distanceMeters: Double(3000 + index), duration: 900)
            cardio.statusRaw = index == 0 ? "linked" : "dismissed"; cardio.linkedRunningSessionID = runID
            context.insert(inbox); context.insert(cardio)
        }
        let bitmap = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.5, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let jpeg = NSMutableData(), imageDestination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(imageDestination, bitmap.makeImage()!, nil)
        try require(CGImageDestinationFinalize(imageDestination), "synthetic JPEG encodes")
        let preparedPhoto = try CoachPhotoStore.prepare(data: jpeg as Data)
        try CoachPhotoStore.finalize(preparedPhoto)
        let photoURL = try CoachPhotoStore.assetURL(for: preparedPhoto.assetKey)
        defer {
            try? files.removeItem(at: photoURL)
            try? files.removeItem(at: CoachPhotoStore.directory.appendingPathComponent("\(preparedPhoto.id.uuidString).thumbnail.jpg"))
        }
        for pose in ["front", "back"] {
            let photo = CoachProgressPhoto(id: preparedPhoto.id)
            photo.assetKey = preparedPhoto.assetKey; photo.digest = preparedPhoto.digest; photo.byteCount = preparedPhoto.byteCount
            photo.pixelWidth = preparedPhoto.width; photo.pixelHeight = preparedPhoto.height; photo.pose = pose
            context.insert(photo)
        }
        try context.save()
        let expected = try DataBackupService.capture(context: context)
        try require(expected.formatVersion == 6 && Set(expected.physicalRecords!.rows.map(\.collection)).count == 24,
                    "all 24 populated types use physical archive identities")
        let originalBytes = try Data(contentsOf: photoURL)
        let transient = try await DataBackupService.exportAll(context: context, includePhotos: true)
        defer { try? files.removeItem(at: transient) }
        let saved = root.appendingPathComponent("saved-outside-export.pacebackup")
        try files.copyItem(at: transient, to: saved); try files.removeItem(at: transient)
        let originalArchive = try Data(contentsOf: saved)
        let prepared = try CoachHistoryArchive.prepareImport(from: saved)
        try require(prepared.manifest?.version == 6 && prepared.manifest?.assets.count == 1,
                    "duplicate photo metadata streams one verified image asset")
        prepared.discard()
        let noPhotos = try await DataBackupService.exportAll(context: context, includePhotos: false)
        defer { try? files.removeItem(at: noPhotos) }
        let withoutPhotos = try CoachHistoryArchive.prepareImport(from: noPhotos)
        try require(withoutPhotos.file.coach?.photos.isEmpty == true && withoutPhotos.manifest?.assets.isEmpty == true,
                    "photo-free v6 export omits both metadata and assets")
        withoutPhotos.discard()
        // A real read-only destination fails at the final save, after physical
        // rows have been staged. This exercises public rollback without a hook.
        try autoreleasepool { _ = try store("read-only") }
        let readOnlyURL = root.appendingPathComponent("read-only.store")
        let readOnlyBefore = try CoachLocalOwnership.rawCheckpoint(readOnlyURL).identity
        let schema = PersistenceController.coachSchema
        let readOnly = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: readOnlyURL, allowsSave: false, cloudKitDatabase: .none)])
        var saveRejected = false
        do { try await DataBackupService.import(from: noPhotos, context: readOnly.mainContext) }
        catch { saveRejected = true }
        try require(saveRejected, "read-only destination rejects the final staged save")
        let failedFile = try DataBackupService.capture(context: ModelContext(readOnly))
        try require(try BackupPhysicalGraph.capture(context: ModelContext(readOnly), file: failedFile).rows.isEmpty,
                    "failed public import leaves no rows or temporary IDs in the destination")
        try require(try CoachLocalOwnership.rawCheckpoint(readOnlyURL).identity == readOnlyBefore,
                    "late save failure leaves the persisted destination unchanged")
        let reopenedFailure = try store("read-only")
        let reopenedFailureFile = try DataBackupService.capture(context: ModelContext(reopenedFailure))
        try require(try BackupPhysicalGraph.capture(context: ModelContext(reopenedFailure), file: reopenedFailureFile).rows.isEmpty,
                    "late-failure rollback remains empty across disk reopen")
        try files.removeItem(at: photoURL)
        let restored = try store("restored")
        try await DataBackupService.import(from: saved, context: restored.mainContext)
        func assertGraph(_ container: ModelContainer, _ message: String) throws {
            let actual = try DataBackupService.capture(context: ModelContext(container))
            try require(try expected.physicalRecords!.hasSameContent(as: actual.physicalRecords!, file: expected, otherFile: actual), message)
            let logs = try ModelContext(container).fetch(FetchDescriptor<ExerciseLog>())
            let left = logs.first { $0.notes == "Synthetic left set" }!, right = logs.first { $0.notes == "Synthetic right set" }!
            try require(left.id == right.id && left.workoutSession?.id == right.workoutSession?.id
                        && left.exerciseDefinition?.name == "Synthetic left definition"
                        && right.exerciseDefinition?.name == "Synthetic right definition"
                        && left.workoutSession?.title == "Synthetic left workout"
                        && right.workoutSession?.title == "Synthetic right workout", "duplicate sets retain exact distinct definition and workout parents")
            let runs = try ModelContext(container).fetch(FetchDescriptor<RunningSession>())
            try require(runs.count == 2 && runs.first { $0.notes == "Synthetic left run" }?.plannedSession?.notes == "Synthetic left slot"
                        && runs.first { $0.notes == "Synthetic right run" }?.plannedSession?.notes == "Synthetic right slot",
                        "same-UUID runs retain distinct physical planned slots")
        }
        try assertGraph(restored, "saved-file public restore preserves all 24 model payloads and physical relationships")
        try require(try Data(contentsOf: photoURL) == originalBytes, "saved-file restore recovers exact JPEG bytes")
        let reopened = try store("restored")
        try assertGraph(reopened, "complete physical graph survives disk reopen")
        try await DataBackupService.import(from: saved, context: reopened.mainContext)
        try assertGraph(reopened, "exact-repeat import remains idempotent across reopen")
        let newWeight = WeightEntry(weight: 81.25, weightUnit: "kg"); context.insert(newWeight); try context.save()
        let extended = try await DataBackupService.exportAll(context: context, includePhotos: true)
        defer { try? files.removeItem(at: extended) }
        try await DataBackupService.import(from: extended, context: reopened.mainContext)
        try require(try ModelContext(reopened).fetchCount(FetchDescriptor<WeightEntry>()) == 2,
                    "unchanged duplicate components allow a new disconnected record")
        let beforeRejected = try DataBackupService.capture(context: ModelContext(reopened))
        leftLog.weight = 999
        context.insert(WeightEntry(weight: 82.5, weightUnit: "kg")); try context.save()
        let changed = try await DataBackupService.exportAll(context: context, includePhotos: true)
        defer { try? files.removeItem(at: changed) }
        do {
            try await DataBackupService.import(from: changed, context: reopened.mainContext)
            throw CoachRepositoryError.invalidValue("changed ambiguous component was accepted")
        } catch is CoachHistoryArchive.ArchiveError { count += 1 }
        let afterRejected = try DataBackupService.capture(context: ModelContext(reopened))
        try require(try beforeRejected.physicalRecords!.hasSameContent(as: afterRejected.physicalRecords!, file: beforeRejected, otherFile: afterRejected),
                    "changed ambiguous component rejects before inserting unrelated records or altering history")
        var malformed = expected
        malformed.physicalRecords!.rows[0].index = Int.max
        do { try malformed.validateForRestore(); throw CoachRepositoryError.invalidValue("invalid physical index accepted") }
        catch is CoachHistoryArchive.ArchiveError { count += 1 }
        malformed = expected
        if let index = malformed.physicalRecords!.rows.firstIndex(where: { !$0.relationships.isEmpty }),
           let name = malformed.physicalRecords!.rows[index].relationships.keys.first {
            malformed.physicalRecords!.rows[index].relationships[name] = [String(repeating: "0", count: 64)]
            do { try malformed.validateForRestore(); throw CoachRepositoryError.invalidValue("missing physical target accepted") }
            catch is CoachHistoryArchive.ArchiveError { count += 1 }
        }
        try require(try Data(contentsOf: saved) == originalArchive && Data(contentsOf: photoURL) == originalBytes,
                    "repeated/rejected imports leave saved backup and photo bytes intact")
        return count + (try await CoachLegacyDuplicateBackupRegressionChecks.run())
    }
    private static func deduplicationIdentityChecks() throws -> Int {
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachRepositoryError.invalidValue("recovered-history dedup regression: " + message) }
        }
        let date = Date(), id = UUID()
        let left = WorkoutSession(id: id, date: date, title: "Synthetic identical workout", executionStatus: .completed)
        let right = WorkoutSession(id: id, date: date, title: left.title, executionStatus: .completed)
        let leftSet = ExerciseLog(reps: 7, weight: 40, weightUnit: "kg"), rightSet = ExerciseLog(reps: 8, weight: 40, weightUnit: "kg")
        left.exerciseLogs = [leftSet]; right.exerciseLogs = [rightSet]
        try require(!DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "same UUID with different set values is retained")
        rightSet.reps = leftSet.reps
        try require(DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "exact legacy workout contents remain duplicates")
        right.plannedSessionID = UUID()
        try require(!DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "different Coach links are retained")
        right.plannedSessionID = nil; leftSet.actualWeight = 40; rightSet.actualWeight = 42
        try require(!DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "different optional actuals are retained")
        rightSet.actualWeight = leftSet.actualWeight
        let definitionID = UUID()
        let firstDefinition = ExerciseDefinition(id: definitionID, name: "Synthetic first parent", muscleGroup: "Chest")
        let secondDefinition = ExerciseDefinition(id: definitionID, name: "Synthetic second parent", muscleGroup: "Back")
        leftSet.exerciseDefinition = firstDefinition; rightSet.exerciseDefinition = secondDefinition
        try require(!DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "different physical definition parents survive equal UUIDs")
        rightSet.exerciseDefinition = firstDefinition
        try require(DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "identical actuals and physical parents remain duplicates")
        let templateID = UUID()
        left.generatedTemplate = WorkoutTemplate(id: templateID, title: "Synthetic first template")
        right.generatedTemplate = WorkoutTemplate(id: templateID, title: "Synthetic second template")
        try require(!DataBackupService.areWorkoutSessionsDefiniteDuplicates(left, right), "different physical template links are retained")
        let run = RunningSession(id: id, date: date, distance: 5, duration: 1800, notes: "left", locations: Data([1]))
        let otherRun = RunningSession(id: id, date: date, distance: 5, duration: 1800, notes: "right", locations: Data([1]))
        try require(!DataBackupService.areRunningSessionsDefiniteDuplicates(run, otherRun), "same UUID with different run notes is retained")
        otherRun.notes = run.notes; otherRun.locations = Data([2])
        try require(!DataBackupService.areRunningSessionsDefiniteDuplicates(run, otherRun), "different routes are retained")
        otherRun.locations = run.locations; otherRun.intervalResultsData = Data([3])
        try require(!DataBackupService.areRunningSessionsDefiniteDuplicates(run, otherRun), "different interval actuals are retained")
        otherRun.intervalResultsData = nil; otherRun.hasMeasuredDistance = false
        try require(!DataBackupService.areRunningSessionsDefiniteDuplicates(run, otherRun), "unknown distance remains distinct from measured distance")
        otherRun.hasMeasuredDistance = true
        try require(DataBackupService.areRunningSessionsDefiniteDuplicates(run, otherRun), "exact run contents remain duplicates")
        let weight = WeightEntry(id: id, date: date, weight: 80, weightUnit: "kg")
        let otherWeight = WeightEntry(id: id, date: date, weight: 81, weightUnit: "kg")
        try require(!DataBackupService.areWeightEntriesDefiniteDuplicates(weight, otherWeight), "same UUID with different weight is retained")
        otherWeight.weight = weight.weight; otherWeight.sourceHealthSampleID = "different-observation"
        try require(!DataBackupService.areWeightEntriesDefiniteDuplicates(weight, otherWeight), "different Health observations are retained")
        otherWeight.sourceHealthSampleID = nil; otherWeight.sourceName = "different-source"
        try require(!DataBackupService.areWeightEntriesDefiniteDuplicates(weight, otherWeight), "different source names are retained")
        otherWeight.sourceName = nil; otherWeight.provenance = "different-provenance"
        try require(!DataBackupService.areWeightEntriesDefiniteDuplicates(weight, otherWeight), "different provenance is retained")
        otherWeight.provenance = weight.provenance
        try require(DataBackupService.areWeightEntriesDefiniteDuplicates(weight, otherWeight), "exact weight contents remain duplicates")
        return count
    }

}
#endif
