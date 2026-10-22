import Foundation

/// A successful close saves once, even when SwiftUI subsequently calls onDisappear.
/// A failed attempt stays retryable and never discards the caller's pending model edits.
@MainActor
final class WorkoutSaveBoundary {
    enum Trigger { case finish, done, dismissal }
    private var saving = false
    private var saved = false
    private var maintenanceScheduled = false

    func beginPresentation() {
        saved = false
        maintenanceScheduled = false
    }

    func claimMaintenance() -> Bool {
        guard saved, !maintenanceScheduled else { return false }
        maintenanceScheduled = true
        return true
    }

    @discardableResult
    func save(_ trigger: Trigger, persist: () throws -> Void, onFailure: (Error) -> Void) -> Bool {
        if saved { return true }
        guard !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            try persist()
            saved = true
            return true
        } catch {
            onFailure(error)
            return false
        }
    }
}

/// Keeps a dismissed editor's pending save reachable from the app's error alert.
@MainActor
final class WorkoutSaveRecovery {
    static let notification = Notification.Name("WorkoutSaveRecovery")
    let message: String
    let retry: () -> Bool

    init(message: String, retry: @escaping () -> Bool) {
        self.message = message
        self.retry = retry
    }
}
