import Foundation
import SwiftData
import UserNotifications

@MainActor
enum CoachExecutionCoordinator {
    enum ExecutionError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
    }

    static func snapshot(_ execution: CoachSessionExecution) throws -> CoachExecutionSnapshot {
        guard let data = execution.snapshotData else { return CoachExecutionSnapshot() }
        return try JSONDecoder().decode(CoachExecutionSnapshot.self, from: data)
    }

    static func startStrength(_ occurrence: PlannedSession, context: ModelContext) throws -> CoachSessionExecution {
        let execution = try CoachRepository(context: context).beginExecution(occurrenceID: occurrence.id)
        if execution.workoutSessionID == nil {
            guard execution.statusRaw == "in_progress" else { return execution }
            let workout = WorkoutSession(date: execution.startedAt, title: occurrence.title)
            workout.plannedSessionID = occurrence.id
            workout.coachExecutionID = execution.id
            workout.executionStatusRaw = "in_progress"
            context.insert(workout)
            execution.workoutSessionID = workout.id
            do { try CoachRepository(context: context).saveExecution(execution) }
            catch {
                execution.workoutSessionID = nil
                context.delete(workout)
                throw error
            }
        }
        return execution
    }

    static func save(_ snapshot: CoachExecutionSnapshot, execution: CoachSessionExecution, context: ModelContext) throws {
        guard CoachPersistence.isLocal(context) else { throw ExecutionError.invalid("Enable local Coach storage before recording an execution.") }
        guard snapshot.setResults.allSatisfy(\.isValid) else { throw ExecutionError.invalid("Actual values must be finite and nonnegative; effort must use RPE or RIR from 0 to 10.") }
        guard Set(snapshot.setResults.map(\.id)).count == snapshot.setResults.count,
              Set(snapshot.setResults.map { $0.exerciseID + "/" + $0.setID }).count == snapshot.setResults.count else {
            throw ExecutionError.invalid("Each prescribed set can have only one actual result.")
        }
        if let data = execution.prescriptionData,
           case let .strength(strength) = try JSONDecoder().decode(CoachSessionTemplate.self, from: data) {
            let prescribedIDs = Set(strength.exercises.flatMap { exercise in exercise.sets.map { exercise.id + "/" + $0.id } })
            guard snapshot.setResults.allSatisfy({ prescribedIDs.contains($0.exerciseID + "/" + $0.setID) }) else {
                throw ExecutionError.invalid("A recorded set does not belong to this execution's saved prescription.")
            }
        }
        guard snapshot.intervalState?.isValid ?? true else { throw ExecutionError.invalid("The saved interval measurements are invalid.") }
        guard snapshot.effort.map({ $0.isFinite && (0...10).contains($0) && ["rpe", "rir"].contains(snapshot.effortScale) }) ?? true else {
            throw ExecutionError.invalid("Session effort must use RPE or RIR from 0 to 10.")
        }
        var updated = snapshot
        updated.updatedAt = Date()
        execution.snapshotData = try JSONEncoder().encode(updated)
        execution.notes = updated.notes
        execution.effortScale = updated.effort == nil ? nil : updated.effortScale
        execution.effort = updated.effort
        if let workoutID = execution.workoutSessionID {
            let workout = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == workoutID })).first
            if let workout { synchronizeActualLogs(updated, workout: workout, context: context) }
        }
        try CoachRepository(context: context).saveExecution(execution)
        // Evidence revisions include the full actual snapshot, so changes to any
        // result invalidate pending decisions before they can be accepted.
        try CoachProgressionEvaluator.invalidateChangedEvidence(context: context)
    }

    private static func synchronizeActualLogs(_ snapshot: CoachExecutionSnapshot, workout: WorkoutSession, context: ModelContext) {
        let existing = workout.exerciseLogs ?? []
        let recordedIDs = Set(snapshot.setResults.filter { $0.state == .completed }.map(\.id))
        for log in existing where log.coachSetResultID.map({ !recordedIDs.contains($0) }) == true { context.delete(log) }
        for (index, result) in snapshot.setResults.enumerated() where result.state == .completed {
            let log = existing.first { $0.coachSetResultID == result.id } ?? ExerciseLog()
            if log.modelContext == nil { context.insert(log) }
            log.workoutSession = workout
            log.coachSetResultID = result.id
            log.actualReps = result.reps
            log.actualWeight = result.load
            log.actualDurationSeconds = result.durationSeconds
            log.actualEffort = result.effort
            log.actualEffortScale = result.effortScale
            log.performedExerciseKey = result.performedExerciseID
            log.prescriptionBasis = result.repCounting
            log.loadBasis = result.loadBasis
            log.reps = result.reps ?? 0
            log.weight = result.load ?? 0
            log.weightUnit = result.loadUnit == "lb" ? "lbs" : (result.loadUnit ?? "kg")
            log.durationSeconds = result.durationSeconds.map { Int($0) }
            log.exerciseName = result.performedExerciseName
            log.exerciseOrder = index
            log.setNumber = index + 1
            log.notes = result.notes
            log.isCompleted = true
            log.isIsolated = result.repCounting == "perSide"
        }
        workout.notes = snapshot.notes
    }

    static func finish(_ execution: CoachSessionExecution, snapshot: CoachExecutionSnapshot, status: CoachExecutionStatus,
                       explanation: String?, context: ModelContext) throws {
        try save(snapshot, execution: execution, context: context)
        if let workoutID = execution.workoutSessionID,
           let workout = try context.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == workoutID })).first {
            workout.executionStatusRaw = status.rawValue
            workout.endedAt = Date()
            workout.completionProvenance = explanation == nil ? "recorded" : "manual_attestation"
        }
        try CoachRepository(context: context).finishExecution(executionID: execution.id, status: status,
            notes: explanation ?? snapshot.notes, provenance: explanation == nil ? "recorded" : "manual_attestation")
        if let timer = snapshot.restTimer { CoachRestNotifications.cancel(timer.notificationID) }
        StreakService.refreshAndReport(using: context)
    }

    static func runTarget(_ occurrence: PlannedSession, execution: CoachSessionExecution) throws -> ScheduledRunTarget {
        guard let data = execution.prescriptionData ?? occurrence.prescriptionData else { throw ExecutionError.invalid("This occurrence has no saved prescription.") }
        let template = try JSONDecoder().decode(CoachSessionTemplate.self, from: data)
        let steps = try runSteps(template)
        return ScheduledRunTarget(sessionID: occurrence.id, sessionType: occurrence.activityType,
            targetDistanceMeters: nil, targetDurationSeconds: nil, targetPaceMinPerMile: nil,
            intensityLevel: "planned", notes: occurrence.notes ?? template.notes, planReference: .canonicalOccurrence(occurrence.id),
            executionID: execution.id, prescriptionRevisionID: execution.prescriptionRevisionID, structuredSteps: steps)
    }

    static func runSteps(_ template: CoachSessionTemplate) throws -> [CoachRunStep] {
        let executable = try CoachSchedule.steps(for: template)
        let steps: [CoachRunStep] = executable.compactMap { item in
            guard case let .segment(segment) = item.payload else { return nil }
            let seconds: Double?
            let meters: Double?
            switch segment.target {
            case let .duration(value): seconds = Double(value); meters = nil
            case let .distance(value): seconds = nil; meters = value.value * (value.unit == .km ? 1_000 : value.unit == .mi ? 1_609.344 : 1)
            }
            let pace = segment.intensity?.pace.map { "Pace \($0.minSeconds)–\($0.maxSeconds) sec/\($0.per.rawValue)" }
            let effort = segment.intensity?.rpe.map { "\($0.scale.rawValue.uppercased()) \($0.min.formatted())–\($0.max.formatted())" }
            let guidance = [segment.intensity?.cue, pace, effort, segment.notes].compactMap { $0 }.joined(separator: " · ")
            return CoachRunStep(id: item.id, label: segment.title ?? segment.activity.rawValue.capitalized,
                repeatIndex: item.iteration ?? 0, targetSeconds: seconds, targetMeters: meters, guidance: guidance.isEmpty ? nil : guidance)
        }
        guard !steps.isEmpty else { throw ExecutionError.invalid("This prescription has no executable cardio intervals.") }
        return steps
    }

    static func mirrorRunCheckpoint(_ checkpoint: RunRecoverySnapshot, context: ModelContext) throws {
        guard CoachPersistence.isLocal(context), checkpoint.isValid,
              let target = checkpoint.plannedTarget, let id = target.executionID,
              let occurrenceID = target.canonicalOccurrenceID,
              let execution = try context.fetch(FetchDescriptor<CoachSessionExecution>(predicate: #Predicate { $0.id == id })).first,
              execution.statusRaw == "in_progress", execution.plannedSessionID == occurrenceID,
              target.prescriptionRevisionID == execution.prescriptionRevisionID else { return }
        var snapshot = try Self.snapshot(execution)
        if let existingData = snapshot.runRecoveryData,
           let existing = try? JSONDecoder().decode(RunRecoverySnapshot.self, from: existingData),
           (existing.recordedAt ?? existing.startDate) > (checkpoint.recordedAt ?? checkpoint.startDate) { return }
        snapshot.runRecoveryData = try JSONEncoder().encode(checkpoint)
        snapshot.intervalState = checkpoint.intervalState
        execution.snapshotData = try JSONEncoder().encode(snapshot)
        try CoachRepository(context: context).saveExecution(execution)
    }

    static func backedUpRunCheckpoint(context: ModelContext) throws -> RunRecoverySnapshot? {
        let records = try context.fetch(FetchDescriptor<CoachSessionExecution>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        for record in records where record.statusRaw == "in_progress" {
            guard let data = try snapshot(record).runRecoveryData,
                  let checkpoint = try? JSONDecoder().decode(RunRecoverySnapshot.self, from: data), checkpoint.isValid,
                  checkpoint.plannedTarget?.executionID == record.id,
                  checkpoint.plannedTarget?.canonicalOccurrenceID == record.plannedSessionID else { continue }
            return checkpoint
        }
        return nil
    }

    static func saveRun(_ session: RunningSession, target: ScheduledRunTarget, intervalState: CoachRunIntervalState?, context: ModelContext) throws {
        try CoachRepository(context: context).requireLocal()
        guard let occurrenceID = target.canonicalOccurrenceID, let executionID = target.executionID else { return }
        guard let execution = try context.fetch(FetchDescriptor<CoachSessionExecution>(predicate: #Predicate { $0.id == executionID })).first,
              execution.plannedSessionID == occurrenceID else { throw ExecutionError.invalid("The saved run no longer has its original Coach execution.") }
        guard execution.statusRaw == "in_progress" || execution.runSessionID == session.id else { throw ExecutionError.invalid("This occurrence already has a finished execution.") }
        guard let prescriptionData = execution.prescriptionData else { throw CoachRepositoryError.missingRecord }
        let prescribedSteps = try runSteps(JSONDecoder().decode(CoachSessionTemplate.self, from: prescriptionData))
        guard let intervalState, intervalState.isValid, let targetSteps = target.structuredSteps,
              intervalState.steps.count == prescribedSteps.count, targetSteps.count == prescribedSteps.count,
              zip(intervalState.steps, prescribedSteps).allSatisfy({ $0.matchesPrescription($1) }),
              zip(targetSteps, prescribedSteps).allSatisfy({ $0.matchesPrescription($1) }),
              target.prescriptionRevisionID == execution.prescriptionRevisionID,
              intervalState.prescriptionRevisionID == execution.prescriptionRevisionID else {
            throw ExecutionError.invalid("The run intervals do not match this execution's saved prescription and revision.")
        }
        var snapshot = try Self.snapshot(execution)
        snapshot.intervalState = intervalState
        snapshot.runRecoveryData = nil
        execution.snapshotData = try JSONEncoder().encode(snapshot)
        execution.runSessionID = session.id
        session.canonicalPlannedSessionID = occurrenceID
        session.coachExecutionID = executionID
        session.intervalResultsData = try JSONEncoder().encode(intervalState)
        let status: CoachExecutionStatus = intervalState.completedAll ? .completed : .partial
        session.executionStatusRaw = status.rawValue
        try CoachRepository(context: context).finishExecution(executionID: executionID, status: status,
            notes: snapshot.notes, provenance: "tracked")
    }
}

@MainActor
enum CoachRestNotifications {
    private static var requested: [String: Date] = [:]
    static func cancelAll() {
        requested.removeAll()
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("coach.rest.") }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
    static func cancel(_ id: String) {
        requested.removeValue(forKey: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
    static func schedule(_ timer: CoachRestTimerState) {
        cancel(timer.notificationID)
        guard timer.pausedRemaining == nil, timer.remaining() > 0 else { return }
        requested[timer.notificationID] = timer.lastChangedAt
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            Task { @MainActor in
                guard requested[timer.notificationID] == timer.lastChangedAt, timer.remaining() > 0 else { return }
                let content = UNMutableNotificationContent()
                content.title = "Rest finished"
                content.body = "Your next set is ready when you are."
                content.sound = .default
                let request = UNNotificationRequest(identifier: timer.notificationID, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.remaining()), repeats: false))
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }
}
