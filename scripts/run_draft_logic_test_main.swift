import Foundation

/// Standalone test for the run-draft recovery logic and its file store.
///
/// Compile with the app sources it exercises (no Apple UI frameworks needed):
///
///   swiftc -swift-version 5 \
///     WorkingOut/Models/RunDraft.swift \
///     WorkingOut/Services/CodableFileStore.swift \
///     scripts/run_draft_logic_test_main.swift \
///     -o /tmp/run_draft_test && /tmp/run_draft_test
@main
struct RunDraftLogicTestMain {
    static func main() {
        testRecoverability()
        testRestoreAfterDeathWhileRunning()
        testRestoreAfterDeathWhilePaused()
        testSaveDirectlyFromRestoredState()
        testStoreRoundTripAndCorruption()
        print("PASS: run-draft logic test")
    }

    // MARK: Fixtures

    static func makeDraft(
        start: Date,
        savedAt: Date,
        wasRunning: Bool,
        pausedAt: Date? = nil,
        pausedDuration: TimeInterval = 0,
        duration: TimeInterval,
        distance: Double = 1500,
        schemaVersion: Int = RunDraft.currentSchemaVersion
    ) -> RunDraft {
        RunDraft(
            schemaVersion: schemaVersion,
            activityType: "running",
            startDate: start,
            savedAt: savedAt,
            wasRunning: wasRunning,
            pausedAt: pausedAt,
            pausedDuration: pausedDuration,
            duration: duration,
            distanceMeters: distance,
            route: [
                RunDraft.RoutePoint(latitude: 37.33, longitude: -122.01, altitude: 12, timestamp: start),
                RunDraft.RoutePoint(latitude: 37.34, longitude: -122.02, altitude: 14, timestamp: savedAt)
            ],
            plannedTarget: RunDraft.PlannedTarget(
                sessionID: UUID(),
                sessionType: "easy",
                targetDistanceMeters: 5000,
                targetDurationSeconds: nil,
                targetPaceMinPerMile: nil,
                intensityLevel: "low",
                notes: "recovery jog"
            )
        )
    }

    // MARK: Recoverability policy

    static func testRecoverability() {
        let now = Date()
        let fresh = makeDraft(start: now.addingTimeInterval(-600), savedAt: now.addingTimeInterval(-30), wasRunning: true, duration: 570)
        expect(fresh.isRecoverable(now: now), "fresh running draft is recoverable")

        let stale = makeDraft(start: now.addingTimeInterval(-90000), savedAt: now.addingTimeInterval(-(RunDraft.maxRecoverableAge + 1)), wasRunning: true, duration: 600)
        expect(!stale.isRecoverable(now: now), "draft older than \(Int(RunDraft.maxRecoverableAge))s is abandoned")

        var empty = makeDraft(start: now, savedAt: now, wasRunning: false, duration: 0, distance: 0)
        empty.route = []
        expect(!empty.isRecoverable(now: now), "draft with no progress and not running is not recoverable")

        let newerSchema = makeDraft(start: now, savedAt: now, wasRunning: true, duration: 60, schemaVersion: RunDraft.currentSchemaVersion + 1)
        expect(!newerSchema.isRecoverable(now: now), "draft from a newer schema is ignored")

        let justStarted = makeDraft(start: now.addingTimeInterval(-2), savedAt: now.addingTimeInterval(-1), wasRunning: true, duration: 1, distance: 0)
        expect(justStarted.isRecoverable(now: now), "a run that just started is still recoverable")
    }

    // MARK: Restore math
    //
    // Mirrors RunTracker's accounting:
    //   resume:  pausedDuration += resumeTime - pausedAt
    //   running: duration(t) = t - startDate - pausedDuration

    static func simulateResume(_ state: RunDraft.RestoredState, at resumeTime: Date) -> TimeInterval {
        let pausedDuration = state.pausedDuration + resumeTime.timeIntervalSince(state.pausedAt)
        return resumeTime.timeIntervalSince(state.startDate) - pausedDuration
    }

    static func testRestoreAfterDeathWhileRunning() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let savedAt = start.addingTimeInterval(600)          // snapshot 10 min in
        let draft = makeDraft(start: start, savedAt: savedAt, wasRunning: true, pausedDuration: 60, duration: 540)

        let relaunch = savedAt.addingTimeInterval(3600)      // dead for an hour
        let restored = draft.restoredState(now: relaunch)

        expect(restored.startDate == start, "restore keeps the true wall-clock start")
        expect(restored.pausedAt == savedAt, "death while running pauses retroactively at the last snapshot")
        expect(restored.duration == 540, "restored duration matches the snapshot")
        expect(restored.distanceMeters == 1500, "restored distance matches the snapshot")

        // Resuming 30 s after relaunch: dead hour + 30 s must not count.
        let resumeTime = relaunch.addingTimeInterval(30)
        let durationAtResume = simulateResume(restored, at: resumeTime)
        expect(abs(durationAtResume - 540) < 0.001, "dead time is excluded from the resumed duration (got \(durationAtResume))")
    }

    static func testRestoreAfterDeathWhilePaused() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let pausedAt = start.addingTimeInterval(300)         // paused 5 min in
        let savedAt = pausedAt.addingTimeInterval(45)        // snapshot while paused
        let draft = makeDraft(start: start, savedAt: savedAt, wasRunning: false, pausedAt: pausedAt, pausedDuration: 0, duration: 300)

        let relaunch = savedAt.addingTimeInterval(7200)
        let restored = draft.restoredState(now: relaunch)

        expect(restored.pausedAt == pausedAt, "death while paused keeps the original pause instant")

        let resumeTime = relaunch.addingTimeInterval(10)
        let durationAtResume = simulateResume(restored, at: resumeTime)
        expect(abs(durationAtResume - 300) < 0.001, "pause + dead time is excluded after restore (got \(durationAtResume))")
    }

    static func testSaveDirectlyFromRestoredState() {
        // Mirrors RunTracker.stopRun() when saving without resuming:
        //   pausedDuration += now - pausedAt
        //   activeDuration = now - startDate - pausedDuration
        //   duration = max(duration, activeDuration)
        let start = Date(timeIntervalSince1970: 3_000_000)
        let savedAt = start.addingTimeInterval(1200)
        let draft = makeDraft(start: start, savedAt: savedAt, wasRunning: true, pausedDuration: 0, duration: 1200)

        let relaunch = savedAt.addingTimeInterval(500)
        let restored = draft.restoredState(now: relaunch)

        let stopTime = relaunch.addingTimeInterval(20)
        let pausedDuration = restored.pausedDuration + stopTime.timeIntervalSince(restored.pausedAt)
        let activeDuration = max(0, stopTime.timeIntervalSince(restored.startDate) - pausedDuration)
        let finalDuration = max(restored.duration, activeDuration)
        expect(abs(finalDuration - 1200) < 0.001, "saving without resuming keeps the snapshot duration (got \(finalDuration))")
    }

    // MARK: File store behavior

    static func testStoreRoundTripAndCorruption() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("run-draft-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableFileStore<RunDraft>(fileURL: directory.appendingPathComponent("draft.json"))

        expect(store.load() == nil, "load returns nil when no draft was saved")

        let now = Date()
        let draft = makeDraft(start: now.addingTimeInterval(-900), savedAt: now, wasRunning: true, pausedDuration: 30, duration: 870)
        store.save(draft)
        expect(store.load() == draft, "draft round-trips through the store, including route and planned target")

        store.save(draft)
        expect(store.load() == draft, "overwriting with the same draft is idempotent")

        store.clear()
        expect(store.load() == nil, "clear removes the draft")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("not json".utf8).write(to: directory.appendingPathComponent("draft.json"))
        expect(store.load() == nil, "corrupt draft decodes to nil")
        expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("draft.json").path),
               "corrupt draft file is discarded so it cannot wedge future launches")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }
}
