#if DEBUG
import Foundation
import SwiftData

extension CoachPersistenceRegressionChecks {
    @MainActor static func runRevisionRestoreCases(root: URL) async throws -> Int {
        let schema = PersistenceController.coachSchema
        func store(_ name: String) throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
                schema: schema, url: root.appendingPathComponent("\(name).store"), cloudKitDatabase: .none)])
        }
        func fresh(_ container: ModelContainer) -> ModelContext {
            let context = ModelContext(container); context.autosaveEnabled = false; return context
        }
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            checks += 1
            guard value else { throw CoachRepositoryError.invalidValue("backup revision regression: " + message) }
        }
        func rejectRevision(_ operation: () throws -> Void) throws {
            do { try operation() }
            catch CoachHistoryArchive.ArchiveError.invalid(let reason) where reason.contains("different current revision") {
                checks += 1; return
            }
            throw CoachRepositoryError.invalidValue("backup revision regression: conflicting revision was accepted")
        }
        let source = try store("revision-source")
        let start = Date()
        var document = CoachPlanDocument(programId: "backup-revision-fixture", title: "Original draft", goal: "Recovery",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [.recovery(.init(id: "mobility", title: "Mobility", instructions: "Gentle mobility"))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "mobility")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let planID = try await CoachRepository(context: fresh(source)).importPlan(document: document, startDate: start, activate: false)
        let olderBackup = try DataBackupService.capture(context: fresh(source))
        try olderBackup.validateForRestore()
        let olderDigest = try CoachLocalOwnership.snapshotDigest(fresh(source))
        let oldRevisionID = olderBackup.coach!.trainingPlans[0].currentRevisionID
        let oldOccurrenceID = olderBackup.coach!.plannedSessions[0].id

        document.revision = 2; document.title = "Replacement draft"
        let reviewedDraft = try fresh(source).fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == planID }!
        _ = try await CoachRepository(context: fresh(source)).importPlan(document: document, startDate: start, activate: false,
            replacingDraftID: planID, expectedRevisionID: oldRevisionID, expectedDraftUpdatedAt: reviewedDraft.updatedAt)
        try CoachRepository(context: fresh(source)).activate(planID: planID)
        let current = try DataBackupService.capture(context: fresh(source))
        try require(current.coach?.trainingPlans.first?.currentRevisionID != oldRevisionID
                    && current.coach?.plannedSessions.contains(where: { $0.id == oldOccurrenceID }) == false,
                    "draft replacement retains its plan identity and replaces its occurrence identities")

        // An unrelated incoming record detects a late guard that would leave
        // partial legacy-model mutations in the caller's restore context.
        var conflicting = olderBackup
        conflicting.weightEntries.append(.init(id: UUID(), date: start, weight: 70, weightUnit: "kg"))
        try conflicting.validateForRestore()
        let baseline = try CoachLocalOwnership.snapshotDigest(fresh(source))
        let preflightContext = fresh(source)
        try rejectRevision { try conflicting.coach!.validateMerge(context: preflightContext) }
        try require(!preflightContext.hasChanges && (try CoachLocalOwnership.snapshotDigest(fresh(source))) == baseline,
                    "preflight rejects an older plan revision without changing current history")
        let restoreContext = fresh(source)
        try rejectRevision { try DataBackupService.restore(conflicting, context: restoreContext) }
        try require(!restoreContext.hasChanges && (try CoachLocalOwnership.snapshotDigest(fresh(source))) == baseline,
                    "public backup restore rejects before inserting unrelated records or obsolete sessions")
        let graphContext = fresh(source)
        try rejectRevision { try olderBackup.coach!.restore(context: graphContext) }
        try require(!graphContext.hasChanges && (try CoachLocalOwnership.snapshotDigest(fresh(source))) == baseline,
                    "direct graph restore also rejects obsolete session recovery before mutation")

        let recovered = try store("revision-empty-recovery")
        try DataBackupService.restore(olderBackup, context: fresh(recovered))
        try require(try CoachLocalOwnership.snapshotDigest(fresh(recovered)) == olderDigest,
                    "the older backup still recovers its complete original graph into empty history")
        try DataBackupService.restore(olderBackup, context: fresh(recovered))
        try require(try CoachLocalOwnership.snapshotDigest(fresh(recovered)) == olderDigest,
                    "same-current-revision recovery remains idempotent")

        // Historical occurrences may intentionally retain an earlier revision.
        // Conflict detection compares the plan's current revision, not each row.
        let historyContext = fresh(source)
        let currentPlan = try historyContext.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == planID }!
        let historical = PlannedSession(plan: currentPlan, title: "Earlier completed mobility", activityType: "recovery",
            scheduledDate: start.addingTimeInterval(-86_400), weekIndex: 0, dayIndex: 1, status: "completed", completedAt: start)
        historical.revisionID = oldRevisionID
        historyContext.insert(historical); try historyContext.save()
        let mixedBackup = try DataBackupService.capture(context: fresh(source))
        try mixedBackup.validateForRestore()
        let mixedDigest = try CoachLocalOwnership.snapshotDigest(fresh(source))
        try DataBackupService.restore(mixedBackup, context: fresh(source))
        try require(try CoachLocalOwnership.snapshotDigest(fresh(source)) == mixedDigest,
                    "same-current-revision merge preserves historical occurrences from earlier revisions")
        let mixedRecovered = try store("revision-mixed-recovery")
        try DataBackupService.restore(mixedBackup, context: fresh(mixedRecovered))
        try DataBackupService.restore(mixedBackup, context: fresh(mixedRecovered))
        try require(try CoachLocalOwnership.snapshotDigest(fresh(mixedRecovered)) == mixedDigest,
                    "mixed-revision history recovers completely and remains idempotent")
        return checks
    }
}
#endif
