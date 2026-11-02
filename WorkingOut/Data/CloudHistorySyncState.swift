import Foundation

/// Download evidence is separate from opening a local store or checking whether
/// locally known records exist on the server. None proves complete old history.
struct CloudHistorySyncState: Equatable, Sendable {
    enum Phase: String, Sendable {
        case disabled, preparing, waitingForDownload, importConfirmed
        case repairPending, offlineFallback, accountUnavailable, syncUnavailable
        case restoreReviewRequired, restoreScheduled, reviewRequested
    }
    enum AccountAvailability: Sendable { case unknown, available, unavailable }
    enum Failure: Sendable { case accountUnavailable, other }
    struct Event: Equatable, Sendable {
        enum Kind: Hashable, Sendable { case setup, download, upload }
        let storeIdentifier: String
        let kind: Kind
        let completedAt: Date?
        let succeeded: Bool
        var failure: Failure = .other
    }

    private(set) var isEnabled = false
    private(set) var isPreparing = false
    private(set) var isCloudBacked = false
    private(set) var needsRepair = false
    private(set) var account: AccountAvailability = .unknown
    private(set) var lastImportAt: Date?
    private(set) var storeIdentifier: String?
    private var unidentifiedStore = false
    // Import success cannot establish that a failed export or setup recovered.
    private var resultDates: [Event.Kind: Date] = [:]
    private var failures: [Event.Kind: Failure] = [:]
    private var accountResultAt: Date?
    private var restoreReviewCount: Int?
    private var restoreScheduled = false
    private var reviewRequested = false
    private(set) var attention: String?

    var phase: Phase {
        guard isEnabled else { return .disabled }
        if isPreparing { return .preparing }
        if !isCloudBacked { return .offlineFallback }
        if account == .unavailable { return .accountUnavailable }
        if unidentifiedStore || !failures.isEmpty { return .syncUnavailable }
        if restoreScheduled { return .restoreScheduled }
        if (restoreReviewCount ?? 0) > 0 { return .restoreReviewRequired }
        if reviewRequested { return .reviewRequested }
        if needsRepair { return .repairPending }
        if attention?.isEmpty == false { return .syncUnavailable }
        return lastImportAt == nil ? .waitingForDownload : .importConfirmed
    }

    mutating func prepare() {
        self = Self()
        isEnabled = true
        isPreparing = true
    }

    mutating func openStore(identifier: String?, cloudBacked: Bool, repairPending: Bool,
                            accountUnavailable: Bool = false, attention: String? = nil) {
        isEnabled = true
        isPreparing = false
        isCloudBacked = cloudBacked
        storeIdentifier = identifier
        needsRepair = repairPending
        account = accountUnavailable ? .unavailable : .unknown
        lastImportAt = nil
        resultDates.removeAll()
        failures.removeAll()
        accountResultAt = nil
        unidentifiedStore = cloudBacked && identifier == nil
        restoreReviewCount = nil; restoreScheduled = false; reviewRequested = false
        self.attention = attention
    }

    /// The open store belongs to a different iCloud account than the saved verification.
    mutating func noteDifferentAccount() {
        attention = "This iCloud account is different from the last verified history. Pace & Plates will recheck it the next time you open the app."
    }

    /// A receipt that already verified this store is not a new download.
    mutating func noteVerifiedHistory(at date: Date) {
        guard isEnabled, isCloudBacked, !needsRepair, failures.isEmpty, account != .unavailable,
              !(attention?.isEmpty == false) else { return }
        lastImportAt = date
    }

    mutating func setRestoreReview(count: Int?, scheduled: Bool, inspectionRequested: Bool) {
        restoreReviewCount = count; restoreScheduled = scheduled; reviewRequested = inspectionRequested
    }

    mutating func checkedAccount(_ availability: AccountAvailability, at date: Date = Date()) {
        guard accountResultAt.map({ date >= $0 }) ?? true else { return }
        if availability == .unknown && account == .unavailable { return }
        account = availability
        accountResultAt = date
    }

    mutating func receive(_ event: Event) {
        guard isEnabled, !isPreparing, isCloudBacked,
              let storeIdentifier, event.storeIdentifier == storeIdentifier,
              let completed = event.completedAt,
              resultDates[event.kind].map({ completed >= $0 }) ?? true else { return }
        resultDates[event.kind] = completed
        if !event.succeeded {
            failures[event.kind] = event.failure
            if event.kind == .download { lastImportAt = nil }
            if event.failure == .accountUnavailable { checkedAccount(.unavailable, at: completed) }
        } else {
            failures.removeValue(forKey: event.kind)
            if event.kind == .download { lastImportAt = completed }
            if event.kind != .setup { checkedAccount(.available, at: completed) }
        }
    }

    var title: String {
        switch phase {
        case .disabled: return "Local history"
        case .preparing: return "Preparing iCloud history"
        case .waitingForDownload: return "Waiting for iCloud download"
        case .importConfirmed: return "iCloud check completed"
        case .repairPending: return "iCloud recovery needs a retry"
        case .offlineFallback: return "History is open without iCloud sync"
        case .accountUnavailable: return "iCloud account unavailable"
        case .syncUnavailable: return "iCloud sync needs attention"
        case .restoreReviewRequired: return "Review retained history for iCloud"
        case .restoreScheduled: return "iCloud restoration scheduled"
        case .reviewRequested: return "Retained-history check scheduled"
        }
    }

    var message: String {
        switch phase {
        case .disabled: return "This history is stored locally."
        case .preparing: return "Your retained files are being checked before history opens."
        case .waitingForDownload: return "Older entries may still be downloading. Keep the app open and check your iCloud account."
        case .importConfirmed: return "A download check completed on this launch. This does not confirm that every older entry exists in iCloud."
        case .repairPending: return attention ?? "Local history is available, but recovery has unfinished work. Close and reopen the app to retry."
        case .offlineFallback: return attention ?? "Your history is available locally. Close and reopen the app to retry iCloud sync."
        case .accountUnavailable: return "Check that the same Apple Account is signed in and iCloud access is enabled for Pace & Plates."
        case .syncUnavailable: return attention ?? "An iCloud operation failed. Check your connection and account; synchronization may retry automatically."
        case .restoreReviewRequired: return "The last check found \(restoreReviewCount ?? 0) retained records missing from iCloud. Review them before choosing whether to restore them."
        case .restoreScheduled: return "Close and reopen the app to restore the exact records you approved. You can cancel this request before relaunching."
        case .reviewRequested: return "Close and reopen the app to check retained records. This check will not restore records without your review."
        }
    }
}
