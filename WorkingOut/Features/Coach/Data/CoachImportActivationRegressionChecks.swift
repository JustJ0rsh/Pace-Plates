#if DEBUG
import Foundation
import SwiftData

@MainActor
enum CoachImportActivationRegressionChecks {
    static func run() async throws -> Int {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachActivationChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: directory.appendingPathComponent("history.store"), cloudKitDatabase: .none)])
        var count = 0
        func fresh() -> ModelContext {
            let context = ModelContext(container); context.autosaveEnabled = false; return context
        }
        func require(_ value: Bool, _ message: String) throws {
            count += 1
            if !value { throw CoachExecutionCoordinator.ExecutionError.invalid("Activation review regression: " + message) }
        }
        func document(_ id: String) -> CoachPlanDocument {
            CoachPlanDocument(programId: id, title: "Synthetic \(id)", goal: "Reviewed recovery",
                phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
                sessionTemplates: [.recovery(.init(id: "mobility", title: "Mobility", instructions: "Gentle mobility"))],
                weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "first", dayOffset: 0, sessionTemplateId: "mobility")])],
                weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        }
        let start = Date()
        let firstID = try await CoachRepository(context: fresh()).importPlan(document: document("first"), startDate: start,
            activate: true, activationReview: .init(activePlanID: nil))
        try require(try fresh().fetch(FetchDescriptor<TrainingPlan>()).first(where: { $0.id == firstID })?.status == "active",
                    "an explicitly reviewed empty active-plan state permits initial activation")

        let reviewedFirst = CoachActivationReview(activePlanID: firstID)
        // A separate context represents another window changing the active plan after review.
        let secondID = try await CoachRepository(context: fresh()).importPlan(document: document("second"), startDate: start, activate: true)
        let baseline = try CoachLocalOwnership.snapshotDigest(fresh())
        do {
            _ = try await CoachRepository(context: fresh()).importPlan(document: document("incoming"), startDate: start,
                activate: true, activationReview: reviewedFirst)
            throw CoachExecutionCoordinator.ExecutionError.invalid("A changed active-plan review was accepted")
        } catch CoachRepositoryError.activationReviewChanged { count += 1 }
        try require(try CoachLocalOwnership.snapshotDigest(fresh()) == baseline,
                    "a changed active-plan ID leaves every stored record, relationship, and occurrence unchanged")

        do {
            _ = try await CoachRepository(context: fresh()).importPlan(document: document("incoming"), startDate: start,
                activate: true, activationReview: .init(activePlanID: nil))
            throw CoachExecutionCoordinator.ExecutionError.invalid("An outdated empty active-plan review was accepted")
        } catch CoachRepositoryError.activationReviewChanged { count += 1 }
        try require(try CoachLocalOwnership.snapshotDigest(fresh()) == baseline,
                    "a none-to-active mismatch leaves every stored record, relationship, and occurrence unchanged")

        let incomingID = try await CoachRepository(context: fresh()).importPlan(document: document("incoming"), startDate: start,
            activate: true, activationReview: .init(activePlanID: secondID))
        let result = fresh()
        let plans = try result.fetch(FetchDescriptor<TrainingPlan>())
        try require(plans.count == 3 && plans.filter { $0.status == "active" }.map(\.id) == [incomingID]
                    && plans.first(where: { $0.id == secondID })?.status == "paused"
                    && plans.first(where: { $0.id == firstID })?.status == "paused",
                    "a matching review activates the incoming plan and pauses only the reviewed active plan")
        let occurrences = try result.fetch(FetchDescriptor<PlannedSession>())
        try require(occurrences.count == 3 && occurrences.allSatisfy { $0.status == "pending" && $0.executionID == nil }
                    && (try result.fetchCount(FetchDescriptor<WorkoutSession>())) == 0
                    && (try result.fetchCount(FetchDescriptor<RunningSession>())) == 0,
                    "rejected attempts create no schedules or actuals before the matching retry succeeds once")

        // A matching active-plan acknowledgement must not bypass the newer
        // draft timestamp guard restored from the reviewed safety stack.
        let draftDocument = document("draft-revision")
        let draftID = try await CoachRepository(context: fresh()).importPlan(document: draftDocument,
            startDate: start, activate: false)
        let draftReviewContext = fresh()
        let reviewedDraft = try draftReviewContext.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == draftID }!
        let reviewedRevisionID = reviewedDraft.currentRevisionID
        let reviewedUpdatedAt = reviewedDraft.updatedAt
        let movedID = reviewedDraft.sessions!.first!.id
        try CoachRepository(context: fresh()).moveSession(id: movedID, to: start.addingTimeInterval(86_400))
        let afterMove = try CoachLocalOwnership.snapshotDigest(fresh())
        var revisedDocument = draftDocument
        revisedDocument.revision += 1
        let replayID = try await CoachRepository(context: fresh()).importPlan(document: revisedDocument,
            startDate: start, activate: true, replacingDraftID: draftID,
            expectedRevisionID: reviewedRevisionID, expectedDraftUpdatedAt: reviewedUpdatedAt,
            activationReview: .init(activePlanID: incomingID))
        try require(replayID == draftID && (try CoachLocalOwnership.snapshotDigest(fresh())) == afterMove,
                    "unchanged-content replay retains existing identity, moved schedule and active plan without mutation")
        revisedDocument.title += " revised"
        do {
            _ = try await CoachRepository(context: fresh()).importPlan(document: revisedDocument,
                startDate: start, activate: true, replacingDraftID: draftID,
                expectedRevisionID: reviewedRevisionID, expectedDraftUpdatedAt: reviewedUpdatedAt,
                activationReview: .init(activePlanID: incomingID))
            throw CoachExecutionCoordinator.ExecutionError.invalid("A stale draft timestamp was accepted with a matching active-plan review")
        } catch CoachRepositoryError.revisionConflict { count += 1 }
        try require(try CoachLocalOwnership.snapshotDigest(fresh()) == afterMove,
                    "activation acknowledgement retains the reviewed stack's stale-draft rejection without mutations")

        let duplicateActive = fresh()
        let oldPlan = try duplicateActive.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == firstID }!
        oldPlan.status = "active"
        try duplicateActive.save()
        let duplicateBaseline = try CoachLocalOwnership.snapshotDigest(fresh())
        do {
            _ = try await CoachRepository(context: fresh()).importPlan(document: document("duplicate-active"),
                startDate: start, activate: true, activationReview: .init(activePlanID: incomingID))
            throw CoachExecutionCoordinator.ExecutionError.invalid("Multiple active plans were accepted as one reviewed active plan")
        } catch CoachRepositoryError.activationReviewChanged { count += 1 }
        try require(try CoachLocalOwnership.snapshotDigest(fresh()) == duplicateBaseline,
                    "ambiguous active-plan state is rejected without changing plans, schedules or actuals")
        return count
    }
}
#endif
