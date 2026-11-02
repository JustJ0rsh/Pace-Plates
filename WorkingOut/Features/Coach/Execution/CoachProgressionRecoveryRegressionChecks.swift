#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachProgressionRecoveryRegressionChecks {
    static func run() throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachProgressionRecoveryChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        var count = 0
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachExecutionCoordinator.ExecutionError.invalid("Progression recovery regression: " + message) }
        }
        func fixture(_ name: String) throws -> (ModelContainer, TrainingPlan, PlannedSession, CoachRecoveryCheckIn) {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none)])
            let context = container.mainContext
            context.autosaveEnabled = false
            let zone = TimeZone.current
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let today = calendar.startOfDay(for: Date())
            let exercise = CoachStrengthExercise(id: "press", exercise: .init(key: "press", name: "Synthetic Recovery Press", equipment: ["barbell"]),
                prescriptionBasis: .total, loadBasis: .totalExternal,
                sets: [.init(id: "working", role: .working, target: .reps(min: 8, max: 12), effort: .init(scale: .rir, min: 2, max: 4))])
            let strength = CoachStrengthSession(id: "lift", title: "Lift", exercises: [exercise])
            let template = CoachSessionTemplate.strength(strength)
            let rule = CoachDoubleProgressionRule(id: "rule", title: "Reviewed increase", sessionTemplateId: "lift", exerciseId: "press",
                requiredSuccessfulOccurrences: 2, minimumRIR: 2, increment: .init(value: 2.5, unit: .kg))
            let document = CoachPlanDocument(programId: "recovery_regression", title: "Synthetic recovery", goal: "General fitness",
                phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)], sessionTemplates: [template],
                weekPatterns: [.init(id: "pattern", title: "Week", slots: [
                    .init(id: "first", dayOffset: 0, sessionTemplateId: "lift"),
                    .init(id: "second", dayOffset: 1, sessionTemplateId: "lift"),
                    .init(id: "future", dayOffset: 4, sessionTemplateId: "lift")])],
                weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")], progressionRules: [.doubleProgression(rule)])
            let plan = TrainingPlan(title: document.title, goal: document.goal, source: "coach_import",
                startDate: calendar.date(byAdding: .day, value: -2, to: today)!)
            plan.timeZoneIdentifier = zone.identifier; plan.sourceProgramID = document.programId; plan.sourceRevision = document.revision
            let revision = CoachPlanRevision(); revision.planID = plan.id
            revision.documentData = try JSONEncoder().encode(document); plan.currentRevisionID = revision.id
            context.insert(plan); context.insert(revision)
            for offset in [-2, -1] {
                let date = calendar.date(byAdding: .day, value: offset, to: today)!
                let row = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: date, weekIndex: 0, dayIndex: offset + 3)
                row.phaseID = "phase"; row.revisionID = revision.id; row.sourceTemplateID = "lift"; row.status = "completed"
                row.currentCivilDate = CoachSchedule.civilDate(date, timeZone: zone); row.prescriptionData = try JSONEncoder().encode(template)
                let execution = CoachSessionExecution(); execution.plannedSessionID = row.id; execution.prescriptionRevisionID = revision.id
                execution.prescriptionData = row.prescriptionData; execution.statusRaw = "completed"
                execution.startedAt = date; execution.endedAt = date; row.executionID = execution.id
                var snapshot = CoachExecutionSnapshot()
                snapshot.setResults = [.init(id: "press/working", exerciseID: "press", setID: "working", performedExerciseID: "press",
                    performedExerciseName: "Synthetic Recovery Press", equipment: "barbell", reps: 12, load: 30, loadUnit: "kg",
                    loadBasis: "totalExternal", repCounting: "total", effortScale: "rir", effort: 2, state: .completed)]
                execution.snapshotData = try JSONEncoder().encode(snapshot)
                let check = CoachRecoveryCheckIn(); check.civilDate = row.currentCivilDate!; check.timeZoneIdentifier = zone.identifier; check.painScore = 0
                context.insert(row); context.insert(execution); context.insert(check)
            }
            let futureDate = calendar.date(byAdding: .day, value: 2, to: today)!
            let future = PlannedSession(plan: plan, title: "Lift", activityType: "strength", scheduledDate: futureDate, weekIndex: 0, dayIndex: 5)
            future.phaseID = "phase"; future.revisionID = revision.id; future.sourceTemplateID = "lift"
            future.currentCivilDate = CoachSchedule.civilDate(futureDate, timeZone: zone); future.prescriptionData = try JSONEncoder().encode(template)
            let feedback = CoachRecoveryCheckIn(); feedback.civilDate = CoachSchedule.civilDate(today, timeZone: zone)
            feedback.timeZoneIdentifier = zone.identifier; feedback.painScore = 0
            context.insert(future); context.insert(feedback); try context.save()
            return (container, plan, future, feedback)
        }

        let (container, plan, _, feedback) = try fixture("holds")
        let context = container.mainContext
        let generated = try CoachProgressionEvaluator.generate(plan: plan, context: context)
        guard let suggestion = generated.suggestions.first else { throw CoachRepositoryError.missingRecord }
        let suggestionID = suggestion.id
        try require(generated.suggestions.count == 1 && suggestion.statusRaw == "pending" && generated.holds.isEmpty,
            "comparable actual evidence produces one actionable suggestion")
        let repeated = try CoachProgressionEvaluator.generate(plan: plan, context: context)
        try require(repeated.suggestions.count == 1 && repeated.suggestions[0].id == suggestionID, "refresh without changed evidence is idempotent")
        for cycle in 0..<2 {
            feedback.painScore = cycle == 0 ? 1 : 0; feedback.soreness = cycle == 1 ? 7 : nil; try context.save()
            for _ in 0..<2 {
                let held = try CoachProgressionEvaluator.generate(plan: plan, context: context)
                try require(held.suggestions.count == 1 && held.suggestions[0].id == suggestionID
                    && held.suggestions[0].statusRaw == "stale" && !held.holds.isEmpty,
                    "repeated recovery holds suspend the same suggestion")
            }
            feedback.painScore = 0; feedback.soreness = nil; try context.save()
            for _ in 0..<2 {
                let cleared = try CoachProgressionEvaluator.generate(plan: plan, context: context)
                try require(cleared.suggestions.count == 1 && cleared.suggestions[0].id == suggestionID
                    && cleared.suggestions[0].statusRaw == "pending" && cleared.holds.isEmpty,
                    "clearing a hold restores the existing suggestion without duplicates")
            }
        }
        let verification = ModelContext(container)
        let saved = try verification.fetch(FetchDescriptor<CoachProgressionSuggestion>())
        try require(saved.count == 1 && saved[0].id == suggestionID && saved[0].statusRaw == "pending", "restored action is persisted once")

        for decision in ["dismissed", "accepted", "edited"] {
            let (store, decisionPlan, future, check) = try fixture(decision)
            let decisionContext = store.mainContext
            let initial = try CoachProgressionEvaluator.generate(plan: decisionPlan, context: decisionContext)
            guard let proposal = initial.suggestions.first else { throw CoachRepositoryError.missingRecord }
            if decision == "dismissed" {
                try CoachRepository(context: decisionContext).transaction { isolated in
                    let row = try isolated.fetch(FetchDescriptor<CoachProgressionSuggestion>()).first { $0.id == proposal.id }!
                    row.statusRaw = "dismissed"; row.decidedAt = Date()
                }
            } else {
                try CoachProgressionEvaluator.accept(suggestionID: proposal.id, selectedIDs: [future.id],
                    increment: decision == "accepted" ? 2.5 : 1.25, confirmedPerImplement: false, context: decisionContext)
            }
            // Re-fetch through a new context so transaction writes, rather than
            // cached objects, drive the recovery and duplicate checks.
            let fresh = ModelContext(store)
            let freshPlan = try fresh.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == decisionPlan.id }!
            let freshCheck = try fresh.fetch(FetchDescriptor<CoachRecoveryCheckIn>()).first { $0.id == check.id }!
            for pain in [0, 1, 0, 0] {
                freshCheck.painScore = pain; try fresh.save()
                let result = try CoachProgressionEvaluator.generate(plan: freshPlan, context: fresh)
                try require(result.suggestions.count == 1 && result.suggestions[0].id == proposal.id
                    && result.suggestions[0].statusRaw == decision,
                    "\(decision) decisions do not resurface after refresh or a cleared hold")
            }
        }
        return count
    }
}
#endif
