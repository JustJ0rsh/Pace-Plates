import Foundation

@main struct CoachBackupReminderTests {
    static func main() throws {
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure(message) }
            checks += 1
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        try require(!CoachBackupReminder.isDue(lastExport: nil, hasCoachRecords: false, now: now), "no Coach data, no reminder")
        try require(CoachBackupReminder.isDue(lastExport: nil, hasCoachRecords: true, now: now), "never exported with Coach data is due")
        try require(!CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(-13 * day), hasCoachRecords: true, now: now), "recent export is not due")
        try require(CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(-14 * day), hasCoachRecords: true, now: now), "14-day-old export is due")
        try require(!CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(2 * day), hasCoachRecords: true, now: now), "small clock skew is tolerated")
        try require(CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(30 * day), hasCoachRecords: true, now: now), "far-future export date cannot hide the reminder")
        try require(!CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(-day), hasCoachRecords: true, newRecordsSinceExport: 19, now: now), "19 new records after a recent export is not due")
        try require(CoachBackupReminder.isDue(lastExport: now.addingTimeInterval(-day), hasCoachRecords: true, newRecordsSinceExport: 20, now: now), "20 new records since the last export is due")

        let suite = "CoachBackupReminderTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try require(CoachBackupReminder.lastExport(defaults) == nil, "no export recorded initially")
        CoachBackupReminder.recordExport(at: now, defaults: defaults)
        try require(CoachBackupReminder.lastExport(defaults) == now, "recorded export date round-trips")
        try require(CoachBackupReminder.statusText(lastExport: nil, now: now).contains("No backup"), "status text without export")
        try require(CoachBackupReminder.statusText(lastExport: now.addingTimeInterval(-day), now: now).hasPrefix("Last backup exported"), "status text with export")
        print("Coach backup reminder: \(checks) checks passed")
    }
    struct Failure: Error, CustomStringConvertible { let description: String; init(_ d: String) { description = d } }
}
