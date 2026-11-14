import Foundation

/// Coach records and progress photos are stored only on this device. They are
/// not in iCloud or in device backups, so a deliberate export is the only copy
/// that survives deleting the app or moving to a new phone.
enum CoachBackupReminder {
    static let lastExportKey = "backup.lastCompletedExportAt"
    static let staleAfterDays = 14

    static func lastExport(_ defaults: UserDefaults = .standard) -> Date? {
        date(fromStored: defaults.double(forKey: lastExportKey))
    }

    /// Stored as seconds since 1970 so SwiftUI's `@AppStorage` can observe it.
    static func date(fromStored value: Double) -> Date? {
        value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Call only after the share sheet reports that the file was saved or sent.
    static func recordExport(at date: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(date.timeIntervalSince1970, forKey: lastExportKey)
    }

    /// A reminder is due when there is Coach data and no export in the last
    /// `staleAfterDays` days. A clock moved backwards never hides the reminder
    /// for longer than the stale window.
    static func isDue(lastExport: Date?, hasCoachRecords: Bool, now: Date = Date()) -> Bool {
        guard hasCoachRecords else { return false }
        guard let lastExport else { return true }
        let age = now.timeIntervalSince(lastExport)
        return age < 0 ? -age > Double(staleAfterDays) * 86_400 : age >= Double(staleAfterDays) * 86_400
    }

    static func statusText(lastExport: Date?, now: Date = Date()) -> String {
        guard let lastExport else { return "No backup exported from this device yet." }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last backup exported \(formatter.localizedString(for: lastExport, relativeTo: now))."
    }

    static let onDeviceOnlyNotice = "Coach programs, results, nutrition, recovery check-ins, waist measurements, and progress photos are stored only on this iPhone. They are not in iCloud and not in iPhone backups. Export a backup to keep them if you delete the app or move to a new phone."
}
