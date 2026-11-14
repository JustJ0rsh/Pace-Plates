import SwiftUI
import SwiftData

/// Says plainly that Coach data is on this iPhone only and when it was last
/// exported. Shown on the Backup & Data page.
struct CoachBackupStatusSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CoachBackupReminder.lastExportKey) private var lastExportStored: Double = 0
    @State private var activity = Activity()

    private var lastExport: Date? { CoachBackupReminder.date(fromStored: lastExportStored) }

    var body: some View {
        Section {
            Label("Stored on this iPhone only", systemImage: "iphone")
                .font(.headline)
            Text(CoachBackupReminder.onDeviceOnlyNotice)
                .font(.callout).foregroundStyle(.secondary)
            let due = CoachBackupReminder.isDue(lastExport: lastExport, hasCoachRecords: activity.hasRecords,
                                                newRecordsSinceExport: activity.newSinceExport)
            Label(CoachBackupReminder.statusText(lastExport: lastExport),
                  systemImage: due ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.callout)
                .foregroundStyle(due ? Color.orange : Color.secondary)
                .accessibilityIdentifier("backup.coach.last_export")
        } header: {
            Text("Coach data")
        } footer: {
            Text("Workouts, runs, weight, and plan schedules sync with iCloud when it’s on.")
        }
        .accessibilityIdentifier("backup.coach.status")
        .task(id: lastExportStored) { activity = Self.activity(modelContext, since: lastExport) }
    }

    struct Activity: Equatable { var hasRecords = false; var newSinceExport = 0 }

    /// Counts Coach records by their creation dates. Calendar mappings and
    /// suggestions are derived, so they don't count as data to back up.
    static func activity(_ context: ModelContext, since lastExport: Date?) -> Activity {
        guard CoachPersistence.isLocal(context) else { return Activity() }
        let since = lastExport ?? .distantPast
        func count<T: PersistentModel>(_ predicate: Predicate<T>?) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
        }
        let totals = [
            count(nil as Predicate<CoachPlanRevision>?), count(nil as Predicate<CoachSessionExecution>?),
            count(nil as Predicate<CoachNutritionLog>?), count(nil as Predicate<CoachRecoveryCheckIn>?),
            count(nil as Predicate<CoachWaistMeasurement>?), count(nil as Predicate<CoachProgressPhoto>?),
            count(nil as Predicate<CoachPhaseReview>?)]
        guard totals.contains(where: { $0 > 0 }) else { return Activity() }
        let fresh = [
            count(#Predicate<CoachPlanRevision> { $0.createdAt > since }),
            count(#Predicate<CoachSessionExecution> { $0.startedAt > since }),
            count(#Predicate<CoachNutritionLog> { $0.createdAt > since }),
            count(#Predicate<CoachRecoveryCheckIn> { $0.createdAt > since }),
            count(#Predicate<CoachWaistMeasurement> { $0.observedAt > since }),
            count(#Predicate<CoachProgressPhoto> { $0.createdAt > since })]
        return Activity(hasRecords: true, newSinceExport: fresh.reduce(0, +))
    }
}
