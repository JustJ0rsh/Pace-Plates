import Foundation

/// Durable snapshot of an in-progress cardio session (run, walk, hike, ...).
///
/// `RunTracker` writes a draft while a session is active so that a run
/// interrupted by process death survives relaunch instead of being lost. The
/// draft depends only on Foundation: the recovery math is exercised by
/// `scripts/run_draft_logic_test_main.swift` with the open-source Swift
/// toolchain, where Apple UI frameworks are unavailable.
struct RunDraft: Codable, Equatable {
    /// Bump when the persisted shape changes incompatibly. Drafts with a newer
    /// schema than the running app understands are ignored rather than misread.
    static let currentSchemaVersion = 1

    /// Drafts older than this are treated as abandoned, not recoverable.
    static let maxRecoverableAge: TimeInterval = 24 * 60 * 60

    struct RoutePoint: Codable, Equatable {
        var latitude: Double
        var longitude: Double
        var altitude: Double?
        var timestamp: Date?
    }

    /// Foundation-only mirror of `ScheduledRunTarget` so a planned session
    /// stays attached to a recovered run.
    struct PlannedTarget: Codable, Equatable {
        var sessionID: UUID
        var sessionType: String
        var targetDistanceMeters: Double?
        var targetDurationSeconds: Double?
        var targetPaceMinPerMile: Double?
        var intensityLevel: String
        var notes: String?
    }

    var schemaVersion: Int = RunDraft.currentSchemaVersion
    var activityType: String
    var startDate: Date
    /// When this snapshot was written.
    var savedAt: Date
    /// Whether the tracker was actively running (not paused) at `savedAt`.
    var wasRunning: Bool
    /// The moment the user paused, when the snapshot was taken while paused.
    var pausedAt: Date?
    /// Total time spent paused before `savedAt`, excluding an open pause.
    var pausedDuration: TimeInterval
    /// Active duration at `savedAt` (excludes paused time).
    var duration: TimeInterval
    var distanceMeters: Double
    var route: [RoutePoint]
    var plannedTarget: PlannedTarget?
}

extension RunDraft {
    /// Tracker state to apply when restoring after process death. The run is
    /// restored *paused*: the interval in which the app was dead is treated as
    /// paused time, so it never counts toward the active duration or pace.
    struct RestoredState: Equatable {
        var activityType: String
        var startDate: Date
        var pausedAt: Date
        var pausedDuration: TimeInterval
        var duration: TimeInterval
        var distanceMeters: Double
    }

    func isRecoverable(now: Date = Date()) -> Bool {
        guard schemaVersion <= Self.currentSchemaVersion else { return false }
        guard now.timeIntervalSince(savedAt) <= Self.maxRecoverableAge else { return false }
        return wasRunning || duration > 0 || distanceMeters > 0 || !route.isEmpty
    }

    func restoredState(now: Date = Date()) -> RestoredState {
        // If the app died while running, the run is retroactively paused at the
        // moment of the last snapshot; if it died while already paused, the
        // original pause instant is kept. Resuming later adds the entire gap to
        // `pausedDuration`, which excludes it from the active duration.
        let effectivePausedAt = wasRunning ? savedAt : (pausedAt ?? savedAt)
        return RestoredState(
            activityType: activityType,
            startDate: startDate,
            pausedAt: min(effectivePausedAt, now),
            pausedDuration: max(0, pausedDuration),
            duration: max(0, duration),
            distanceMeters: max(0, distanceMeters)
        )
    }
}

extension CodableFileStore where Value == RunDraft {
    /// Store for the single active-run draft.
    static var activeRunDraft: CodableFileStore<RunDraft> {
        CodableFileStore(name: "active-run-draft")
    }
}
