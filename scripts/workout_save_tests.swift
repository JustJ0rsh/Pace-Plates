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
        print("PASS: \(checks) workout save regression checks")
    }
}
