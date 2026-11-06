import Foundation
import CoreData
import CloudKit

enum CloudHistoryEventAdapter {
    static func failure(_ error: Error?) -> CloudHistorySyncState.Failure {
        guard let error else { return .other }
        var pending = [error as NSError]
        var inspected = 0
        while let next = pending.popLast(), inspected < 16 {
            inspected += 1
            if next.domain == CKErrorDomain, next.code == CKError.notAuthenticated.rawValue { return .accountUnavailable }
            // Core Data can wrap CloudKit errors. Keep only a safe category;
            // descriptions and userInfo may contain private record contents.
            if let underlying = next.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
            if let detailed = next.userInfo[NSDetailedErrorsKey] as? [NSError] { pending.append(contentsOf: detailed) }
            if let partial = next.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError] { pending.append(contentsOf: partial.values) }
        }
        return .other
    }

    static func event(_ value: NSPersistentCloudKitContainer.Event) -> CloudHistorySyncState.Event? {
        let kind: CloudHistorySyncState.Event.Kind
        switch value.type {
        case .setup: kind = .setup
        case .import: kind = .download
        case .export: kind = .upload
        @unknown default: return nil
        }
        return .init(storeIdentifier: value.storeIdentifier, kind: kind, completedAt: value.endDate,
                     succeeded: value.succeeded, failure: failure(value.error))
    }
}

/// Observes the existing owner only. It never opens or refreshes a store.
@MainActor
final class CloudHistoryEventObserver {
    private var token: NSObjectProtocol?
    private var storeIdentifier: String?
    private var buffered: [CloudHistorySyncState.Event] = []
    private var isStopped = false
    private let onEvent: @MainActor (CloudHistorySyncState.Event) -> Void

    init(onEvent: @escaping @MainActor (CloudHistorySyncState.Event) -> Void) {
        self.onEvent = onEvent
        token = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                       object: nil, queue: .main) { [weak self] notification in
            guard let value = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  let event = CloudHistoryEventAdapter.event(value) else { return }
            Task { @MainActor [weak self] in self?.receive(event) }
        }
    }

    func bind(to identifier: String) {
        guard !isStopped else { return }
        storeIdentifier = identifier
        let pending = buffered
        buffered.removeAll()
        for event in pending { receive(event) }
    }

    func receive(_ event: CloudHistorySyncState.Event) {
        guard !isStopped else { return }
        guard let storeIdentifier else {
            if buffered.count == 64 { buffered.removeFirst() }
            buffered.append(event)
            return
        }
        if event.storeIdentifier == storeIdentifier { onEvent(event) }
    }

    func stop() {
        isStopped = true
        if let token { NotificationCenter.default.removeObserver(token) }
        token = nil
        buffered.removeAll()
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
