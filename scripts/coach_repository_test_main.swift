import Foundation
import SwiftData
import SQLite3

// Host-only adapters: no notification service, Health service, or user store.
@MainActor final class UNUserNotificationCenter {
    static let fixture = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { fixture }
    func removePendingNotificationRequests(withIdentifiers: [String]) {}
}
@MainActor enum WearableWorkoutInboxService {
    static var localDataPurgeGeneration = UUID()
    static func isCurrentLocalDataPurgeGeneration(_ value: UUID, context: ModelContext) -> Bool {
        value == localDataPurgeGeneration
    }
}

@main struct CoachRepositoryTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachRepositoryChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.store")
        let schema = Schema([ExerciseDefinition.self, WorkoutSession.self, ExerciseLog.self,
            RunningSession.self, RunningPlan.self, RunningPlanSession.self, TrainingPlan.self,
            PlannedSession.self, WeightEntry.self, AIConversation.self, WorkoutTemplate.self,
            TemplateExercise.self, HealthWorkoutInboxItem.self, CardioWorkoutInboxItem.self] + CoachPersistence.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName,
            schema: schema, url: url, cloudKitDatabase: .none)])
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message) }
            checks += 1
        }
        func fresh() -> ModelContext { let c = ModelContext(container); c.autosaveEnabled = false; return c }
        func repository() -> CoachRepository { CoachRepository(context: fresh()) }
        func document(_ id: String, revision: Int = 1) -> CoachPlanDocument {
            var value = CoachPlanDocument(programId: id, title: "Fixture \(id)", goal: "Preserve reviewed plans",
                phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
                sessionTemplates: [.recovery(.init(id: "mobility", title: "Mobility", instructions: "Gentle mobility"))],
                weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "first", dayOffset: 0, sessionTemplateId: "mobility")])],
                weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
            value.revision = revision
            return value
        }
        func digest() throws -> [String: [String]] {
            var database: OpaquePointer?
            guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else { throw Failure("snapshot open") }
            defer { sqlite3_close(database) }
            func query(_ sql: String) throws -> [[String]] {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure("snapshot query") }
                defer { sqlite3_finalize(statement) }
                var rows: [[String]] = []
                var status = sqlite3_step(statement)
                while status == SQLITE_ROW {
                    rows.append((0..<sqlite3_column_count(statement)).map { column in
                        switch sqlite3_column_type(statement, column) {
                        case SQLITE_NULL: return "null"
                        case SQLITE_INTEGER: return "int:\(sqlite3_column_int64(statement, column))"
                        case SQLITE_FLOAT: return "float:\(sqlite3_column_double(statement, column).bitPattern)"
                        case SQLITE_BLOB:
                            let count = Int(sqlite3_column_bytes(statement, column))
                            return "blob:" + (sqlite3_column_blob(statement, column).map { Data(bytes: $0, count: count).base64EncodedString() } ?? "")
                        default: return "text:" + String(cString: sqlite3_column_text(statement, column))
                        }
                    })
                    status = sqlite3_step(statement)
                }
                guard status == SQLITE_DONE else { throw Failure("snapshot step") }
                return rows
            }
            let tables = try query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            var result: [String: [String]] = [:]
            for table in tables {
                let name = table[0].dropFirst(5).description
                result[name] = try query("SELECT * FROM \"\(name.replacingOccurrences(of: "\"", with: "\"\""))\"").map { row in
                    String(data: try! JSONEncoder().encode(row), encoding: .utf8)!
                }.sorted()
            }
            return result
        }
        let start = Date()
        let first = try await repository().importPlan(document: document("first"), startDate: start,
            activate: true, activationReview: .init(activePlanID: nil))
        try require(try fresh().fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == first }?.status == "active", "reviewed empty state starts first plan")
        let second = try await repository().importPlan(document: document("second"), startDate: start, activate: true)
        var before = try digest()
        do {
            _ = try await repository().importPlan(document: document("stale"), startDate: start,
                activate: true, activationReview: .init(activePlanID: first))
            throw Failure("stale review accepted")
        } catch CoachRepositoryError.activationReviewChanged { checks += 1 }
        try require(try digest() == before, "stale active review leaves every database value unchanged")
        do {
            _ = try await repository().importPlan(document: document("stale-none"), startDate: start,
                activate: true, activationReview: .init(activePlanID: nil))
            throw Failure("stale empty review accepted")
        } catch CoachRepositoryError.activationReviewChanged { checks += 1 }
        try require(try digest() == before, "stale empty review leaves every database value unchanged")
        let incoming = try await repository().importPlan(document: document("incoming"), startDate: start,
            activate: true, activationReview: .init(activePlanID: second))
        var plans = try fresh().fetch(FetchDescriptor<TrainingPlan>())
        try require(plans.filter { $0.status == "active" }.map(\.id) == [incoming], "matching review activates exactly one plan")
        try require(plans.first { $0.id == first }?.status == "paused" && plans.first { $0.id == second }?.status == "paused", "previous plans retain paused history")
        let duplicate = fresh()
        let old = try duplicate.fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == first }!
        old.status = "active"; try duplicate.save()
        before = try digest()
        do {
            _ = try await repository().importPlan(document: document("ambiguous"), startDate: start,
                activate: true, activationReview: .init(activePlanID: incoming))
            throw Failure("multiple active plans accepted")
        } catch CoachRepositoryError.activationReviewChanged { checks += 1 }
        try require(try digest() == before, "ambiguous active state leaves every database value unchanged")
        old.status = "paused"; try duplicate.save()
        let draftID = try await repository().importPlan(document: document("draft"), startDate: start, activate: false)
        let draft = try fresh().fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == draftID }!
        let revision = draft.currentRevisionID, updated = draft.updatedAt, occurrenceID = draft.sessions!.first!.id
        try repository().moveSession(id: occurrenceID, to: start.addingTimeInterval(86_400))
        before = try digest()
        let replayID = try await repository().importPlan(document: document("draft", revision: 2), startDate: start,
            activate: true, replacingDraftID: draftID, expectedRevisionID: revision, expectedDraftUpdatedAt: updated,
            activationReview: .init(activePlanID: incoming))
        try require(replayID == draftID, "unchanged-content replay keeps the existing draft identity")
        try require(try digest() == before, "unchanged-content replay does not mutate schedule or active plan")
        var updatedDraft = document("draft", revision: 2)
        updatedDraft.title += " revised"
        do {
            _ = try await repository().importPlan(document: updatedDraft, startDate: start,
                activate: true, replacingDraftID: draftID, expectedRevisionID: revision, expectedDraftUpdatedAt: updated,
                activationReview: .init(activePlanID: incoming))
            throw Failure("stale timestamp accepted")
        } catch CoachRepositoryError.revisionConflict { checks += 1 }
        try require(try digest() == before, "new active-plan review does not bypass old stale-draft protection")
        let currentDraft = try fresh().fetch(FetchDescriptor<TrainingPlan>()).first { $0.id == draftID }!
        do {
            _ = try await repository().importPlan(document: updatedDraft, startDate: start,
                activate: true, replacingDraftID: draftID, expectedRevisionID: revision, expectedDraftUpdatedAt: currentDraft.updatedAt,
                activationReview: .init(activePlanID: second))
            throw Failure("current draft bypassed stale active review")
        } catch CoachRepositoryError.activationReviewChanged { checks += 1 }
        try require(try digest() == before, "current draft cannot bypass stale activation protection")
        let revised = try await repository().importPlan(document: updatedDraft, startDate: start,
            activate: true, replacingDraftID: draftID, expectedRevisionID: revision, expectedDraftUpdatedAt: currentDraft.updatedAt,
            activationReview: .init(activePlanID: incoming))
        try require(revised == draftID, "matching current reviews replace the same draft identity")
        plans = try fresh().fetch(FetchDescriptor<TrainingPlan>())
        try require(plans.filter { $0.status == "active" }.map(\.id) == [draftID] && plans.count == 4, "matching retry activates once with no duplicate rejected plans")
        let removed = fresh()
        let occurrence = try removed.fetch(FetchDescriptor<PlannedSession>()).first { $0.plan?.id == draftID }!
        occurrence.completionProvenance = "removed_by_reviewed_revision"; try removed.save()
        before = try digest()
        do { try repository().markSession(id: occurrence.id, status: .skipped); throw Failure("removed occurrence skipped") }
        catch CoachRepositoryError.invalidValue { checks += 1 }
        try require(try digest() == before, "removed skip changes no stored values")
        do { _ = try repository().beginExecution(occurrenceID: occurrence.id); throw Failure("removed occurrence started") }
        catch CoachRepositoryError.invalidValue { checks += 1 }
        try require(try digest() == before, "removed start creates no execution or edits")
        occurrence.completionProvenance = nil; try removed.save()
        let execution = try repository().beginExecution(occurrenceID: occurrence.id)
        let resumed = try repository().beginExecution(occurrenceID: occurrence.id)
        try require(execution.id == resumed.id && (try fresh().fetchCount(FetchDescriptor<CoachSessionExecution>())) == 1,
                    "valid occurrence starts once and resumes the same execution")
        print("Coach repository: \(checks) checks passed")
    }
    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
}
