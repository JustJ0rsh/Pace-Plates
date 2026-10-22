import Foundation

@main
struct WorkoutSaveTests {
    @MainActor
    static func main() {
        struct SetEntry: Equatable {
            var completed: Bool
            var reps: Int?
            var weight: Double?
        }
        struct Draft: Equatable {
            var title: String
            var notes: String
            var status: String
            var sets: [SetEntry]
        }
        enum Failure: Error { case diskFull }
        let draft = Draft(title: "My session", notes: "Unfinished on purpose", status: "in_progress", sets: [
            SetEntry(completed: true, reps: 7, weight: 42.5),
            SetEntry(completed: false, reps: 3, weight: 20),
            SetEntry(completed: false, reps: nil, weight: nil)
        ])
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        for trigger in [WorkoutSaveBoundary.Trigger.finish, .done, .dismissal] {
            let boundary = WorkoutSaveBoundary()
            var records: [Draft] = []
            check(boundary.save(trigger, persist: { records.append(draft) }, onFailure: { _ in fatalError() }), "close saves")
            check(records == [draft], "all entry values and incomplete flags preserved")
            check(boundary.save(.dismissal, persist: { records.append(draft) }, onFailure: { _ in fatalError() }), "duplicate callback succeeds")
            check(records.count == 1, "duplicate callback does not duplicate records")
            check(boundary.claimMaintenance(), "maintenance available after successful save")
            check(!boundary.claimMaintenance(), "maintenance happens once")
            boundary.beginPresentation()
            check(boundary.save(.done, persist: { records.append(draft) }, onFailure: { _ in fatalError() }), "reopened editor saves again")
            check(records.count == 2, "new presentation is not suppressed")
        }
        let boundary = WorkoutSaveBoundary()
        var errors = 0
        var records: [Draft] = []
        check(!boundary.save(.finish, persist: { throw Failure.diskFull }, onFailure: { _ in errors += 1 }), "failure prevents close")
        check(errors == 1, "failure is surfaced")
        check(!boundary.claimMaintenance(), "failed saves cannot delete or report workouts")
        check(boundary.save(.done, persist: { records.append(draft) }, onFailure: { _ in fatalError() }), "failure stays retryable")
        check(records == [draft], "retry preserves entire draft")
        let reentrant = WorkoutSaveBoundary()
        var writes = 0
        check(reentrant.save(.finish, persist: {
            writes += 1
            check(!reentrant.save(.dismissal, persist: { writes += 1 }, onFailure: { _ in fatalError() }), "in-flight callback blocked")
        }, onFailure: { _ in fatalError() }), "outer save completes")
        check(writes == 1, "reentrant callback cannot duplicate records")
        // The store owns complete drafts independently of any presented alert.
        final class HeldDraft {
            let value: Draft
            init(_ value: Draft) { self.value = value }
        }
        let store = WorkoutSaveRecoveryStore()
        let firstID = UUID(), secondID = UUID()
        var held: HeldDraft? = HeldDraft(draft)
        weak var weakDraft = held
        var maySave = false
        var recovered: Draft?
        var first: WorkoutSaveRecovery? = WorkoutSaveRecovery(id: firstID, title: "First", message: "Disk full") { [retained = held!] in
            guard maySave else { return false }
            recovered = retained.value
            return true
        }
        store.enqueue(first!)
        first = nil
        held = nil
        var alertID: UUID? = firstID
        alertID = nil // Later, swipe-dismissed alert, or a different alert.
        check(alertID == nil && store.pending.count == 1, "postponing does not remove pending recovery")
        check(weakDraft != nil, "store keeps full draft alive after editor and alert go away")
        store.enqueue(WorkoutSaveRecovery(id: secondID, title: "Second", message: "Validation failed") { false })
        check(store.pending.count == 2, "multiple failed drafts coexist")
        check(!store.retry(id: firstID), "retry failure reported")
        check(store.pending.count == 2, "retry failure removes nothing")
        check(weakDraft?.value == draft, "all fields retained after retry failure")
        // Retrying may synchronously publish another failure for the same draft.
        store.enqueue(WorkoutSaveRecovery(id: secondID, title: "Second", message: "Still invalid") {
            store.enqueue(WorkoutSaveRecovery(id: secondID, title: "Second", message: "Still invalid") { false })
            return false
        })
        check(store.pending.count == 2, "repeated notification replaces only matching draft")
        check(!store.retry(id: secondID), "nested notification retry remains failed")
        check(store.pending.count == 2, "nested notification cannot duplicate queue entries")
        maySave = true
        check(store.retry(id: firstID), "successful retry reported")
        check(recovered == draft, "successful retry persists full original draft")
        check(weakDraft == nil, "successful recovery releases retained editor draft")
        check(store.pending.count == 1 && store.pending.first?.id == secondID, "success removes only saved draft")
        check(store.recovery(id: firstID) == nil, "saved recovery no longer pending")
        check(store.recovery(id: secondID)?.message == "Still invalid", "other draft remains available later")
        print("PASS: \(checks) workout save regression checks")
    }
}
