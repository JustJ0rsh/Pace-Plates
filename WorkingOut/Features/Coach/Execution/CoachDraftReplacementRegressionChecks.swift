#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachDraftReplacementRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachDraftReplacementChecks-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: directory.appendingPathComponent("draft.store"), cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let repository = CoachRepository(context: context)
        var verificationContexts: [ModelContext] = []
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            checks += 1
            guard condition else { throw CoachRepositoryError.invalidValue("draft replacement regression: " + message) }
        }
        func fresh() -> ModelContext {
            let value = ModelContext(container)
            value.autosaveEnabled = false
            verificationContexts.append(value)
            return value
        }
        func graphData() throws -> Data {
            var graph = try CoachBackupGraph.capture(context: fresh())
            graph.trainingPlans.sort { $0.id.uuidString < $1.id.uuidString }
            graph.plannedSessions.sort { $0.id.uuidString < $1.id.uuidString }
            graph.revisions.sort { $0.id.uuidString < $1.id.uuidString }
            graph.phaseReviews.sort { $0.id.uuidString < $1.id.uuidString }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try encoder.encode(graph)
        }
        var document = CoachPlanDocument(programId: "draft_replacement_regression", title: "Synthetic reviewed draft", goal: "General fitness",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .reviewRequired)],
            sessionTemplates: [.recovery(.init(id: "recovery", title: "Recovery", durationSeconds: 60, instructions: "Synthetic fixture only"))],
            weekPatterns: [.init(id: "pattern", title: "Pattern", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "recovery")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let zone = TimeZone(secondsFromGMT: 0)!
        let anchor = try CoachRepository.date("2030-01-01", timeZone: zone)
        let planID = try await repository.importPlan(document: document, startDate: anchor, activate: false, timeZone: zone)
        // Avoid making the race depend on the resolution of two consecutive clock reads.
        try repository.transaction { isolated in
            let draft = try isolated.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == planID }!
            draft.updatedAt = Date(timeIntervalSinceReferenceDate: 0)
        }
        let reviewContext = fresh()
        let reviewedDraft = try CoachRepository(context: reviewContext).plans().first { $0.id == planID }!
        let reviewedRevisionID = reviewedDraft.currentRevisionID
        let reviewedUpdatedAt = reviewedDraft.updatedAt
        let editor = CoachRepository(context: fresh())
        let occurrenceID = try editor.occurrences(planID: planID).first!.id
        let changes = try editor.schedulePreview(planID: planID, selected: [occurrenceID], dayOffset: 2)
        try editor.applySchedule(changes, planID: planID, expectedUpdatedAt: reviewedUpdatedAt)
        let movedDraft = try CoachRepository(context: fresh()).plans().first { $0.id == planID }!
        try require(movedDraft.currentRevisionID == reviewedRevisionID && movedDraft.updatedAt != reviewedUpdatedAt,
            "schedule editing changes the reviewed draft state without changing its prescription revision")
        let beforeRejectedReplacement = try graphData()
        document.revision = 2
        document.title = "Synthetic incoming revision"
        var rejected = false
        do {
            _ = try await repository.importPlan(document: document, startDate: anchor, activate: false,
                replacingDraftID: planID, expectedRevisionID: reviewedRevisionID, expectedDraftUpdatedAt: reviewedUpdatedAt, timeZone: zone)
        } catch CoachRepositoryError.revisionConflict { rejected = true }
        let savedRows = try CoachRepository(context: fresh()).occurrences(planID: planID)
        let retainedMove = savedRows.contains { $0.id == occurrenceID && $0.currentCivilDate == changes.first?.to && $0.localScheduleOverride }
        try require(rejected, "stale same-revision review must reject; moved occurrence retained: \(retainedMove)")
        try require(try graphData() == beforeRejectedReplacement,
            "rejecting the stale replacement preserves the complete plan, occurrence, revision, and readiness graph")
        try require(retainedMove, "the newer schedule edit retains its exact occurrence identity and date")
        var missingStateRejected = false
        do {
            _ = try await repository.importPlan(document: document, startDate: anchor, activate: false,
                replacingDraftID: planID, expectedRevisionID: reviewedRevisionID, timeZone: zone)
        } catch CoachRepositoryError.revisionConflict { missingStateRejected = true }
        let afterMissingStateReplacement = try graphData()
        try require(missingStateRejected && afterMissingStateReplacement == beforeRejectedReplacement,
            "a replacement without a reviewed state token rejects and preserves the complete graph")
        let refreshedDraft = try CoachRepository(context: fresh()).plans().first { $0.id == planID }!
        let replacementID = try await repository.importPlan(document: document, startDate: anchor, activate: false,
            replacingDraftID: planID, expectedRevisionID: refreshedDraft.currentRevisionID,
            expectedDraftUpdatedAt: refreshedDraft.updatedAt, timeZone: zone)
        let savedDraft = try CoachRepository(context: fresh()).plans().first { $0.id == planID }!
        let replacementRows = try CoachRepository(context: fresh()).occurrences(planID: planID)
        try require(replacementID == planID && savedDraft.sourceRevision == 2 && savedDraft.title == document.title
            && savedDraft.currentRevisionID != reviewedRevisionID,
            "a refreshed explicit review replaces the same draft with the new prescription revision")
        try require(replacementRows.count == 1 && replacementRows[0].id != occurrenceID
            && replacementRows[0].currentCivilDate == "2030-01-01" && !replacementRows[0].localScheduleOverride,
            "an accepted reviewed replacement regenerates the authored schedule")
        try require(try fresh().fetchCount(FetchDescriptor<WorkoutSession>()) == 0
            && fresh().fetchCount(FetchDescriptor<RunningSession>()) == 0
            && fresh().fetchCount(FetchDescriptor<ExerciseDefinition>()) == 0,
            "rejected synthetic replacement creates no activity or exercise history")
        return checks
    }
}
#endif
