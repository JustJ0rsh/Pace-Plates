import Foundation
import Combine

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

/// Owns the retry closure (and its full editor draft) until persistence succeeds.
@MainActor
final class WorkoutSaveRecovery: Identifiable {
    static let notification = Notification.Name("WorkoutSaveRecovery")
    let id: UUID
    let title: String
    let message: String
    let retry: () -> Bool

    init(id: UUID, title: String, message: String, retry: @escaping () -> Bool) {
        self.id = id
        self.title = title
        self.message = message
        self.retry = retry
    }

    func publish() {
        WorkoutSaveRecoveryStore.shared.enqueue(self)
        NotificationCenter.default.post(name: Self.notification, object: self)
    }
}

/// Alert visibility never owns recovery lifetime. Repeated failures replace only
/// the same session's entry; another failed workout cannot evict its draft.
@MainActor
final class WorkoutSaveRecoveryStore: ObservableObject {
    static let shared = WorkoutSaveRecoveryStore()
    @Published private(set) var pending: [WorkoutSaveRecovery] = []

    func enqueue(_ recovery: WorkoutSaveRecovery) {
        if let index = pending.firstIndex(where: { $0.id == recovery.id }) {
            pending[index] = recovery
        } else {
            pending.append(recovery)
        }
    }

    func recovery(id: UUID?) -> WorkoutSaveRecovery? {
        pending.first { $0.id == id }
    }

    @discardableResult
    func retry(id: UUID) -> Bool {
        guard let recovery = recovery(id: id) else { return true }
        guard recovery.retry() else { return false }
        didSave(id: id)
        return true
    }

    /// Call only after the draft's persistence operation has succeeded.
    func didSave(id: UUID) {
        pending.removeAll { $0.id == id }
    }
}
