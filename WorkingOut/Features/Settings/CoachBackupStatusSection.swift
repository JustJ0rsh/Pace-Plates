import SwiftUI
import SwiftData

/// Says plainly that Coach data is on this iPhone only and when it was last
/// exported. Shown on the Backup & Data page.
struct CoachBackupStatusSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(CoachBackupReminder.lastExportKey) private var lastExportStored: Double = 0
    @State private var hasCoachRecords = false

    private var lastExport: Date? { CoachBackupReminder.date(fromStored: lastExportStored) }

    var body: some View {
        Section {
            Label("Stored on this iPhone only", systemImage: "iphone")
                .font(.headline)
            Text(CoachBackupReminder.onDeviceOnlyNotice)
                .font(.callout).foregroundStyle(.secondary)
            let due = CoachBackupReminder.isDue(lastExport: lastExport, hasCoachRecords: hasCoachRecords)
            Label(CoachBackupReminder.statusText(lastExport: lastExport),
                  systemImage: due ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.callout)
                .foregroundStyle(due ? Color.orange : Color.secondary)
                .accessibilityIdentifier("backup.coach.last_export")
        } header: {
            Text("Coach data")
        } footer: {
            Text("Workouts, runs, weight, and plan schedules sync through iCloud when it’s on.")
        }
        .accessibilityIdentifier("backup.coach.status")
        .task { hasCoachRecords = Self.hasCoachRecords(modelContext) }
    }

    static func hasCoachRecords(_ context: ModelContext) -> Bool {
        guard CoachPersistence.isLocal(context) else { return false }
        func any<T: PersistentModel>(_ type: T.Type) -> Bool {
            var descriptor = FetchDescriptor<T>(); descriptor.fetchLimit = 1
            return ((try? context.fetchCount(descriptor)) ?? 0) > 0
        }
        return any(CoachPlanRevision.self) || any(CoachSessionExecution.self) || any(CoachNutritionLog.self)
            || any(CoachRecoveryCheckIn.self) || any(CoachWaistMeasurement.self) || any(CoachProgressPhoto.self)
            || any(CoachPhaseReview.self)
    }
}
