import SwiftUI
import UIKit

struct CloudHistoryStatusBanner: View {
    let controller: PersistenceController
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails = true } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "icloud")
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.isUsingContinuedHistory ? "Using new local history" : controller.cloudHistoryStatus.title).font(.subheadline.bold())
                    Text("View history status").font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(12)
            .foregroundStyle(.primary)
            .background(.regularMaterial)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cloud.history.banner")
        .sheet(isPresented: $showingDetails) {
            NavigationStack { CloudHistoryStatusDetailView(controller: controller) }
        }
    }
}

struct CloudHistoryStatusSettingsSection: View {
    let controller: PersistenceController

    var body: some View {
        if controller.cloudHistoryStatus.isEnabled {
            Section(controller.isUsingContinuedHistory ? "Local History" : "iCloud History") {
                NavigationLink {
                    CloudHistoryStatusDetailView(controller: controller)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(controller.cloudHistoryStatus.title, systemImage: "icloud")
                        Text(controller.cloudHistoryStatus.message)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("cloud.history.settings")
            }
        }
    }
}

struct CloudHistoryStatusDetailView: View {
    let controller: PersistenceController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingRestore = false
    @State private var actionError: String?

    var body: some View {
        Form {
            Section {
                Text(controller.cloudHistoryStatus.title).font(.headline)
                    .accessibilityIdentifier("cloud.history.title")
                Text(controller.cloudHistoryStatus.message)
                if !controller.isUsingContinuedHistory {
                    switch controller.cloudHistoryStatus.account {
                    case .available: Text("Your iCloud account is available.")
                    case .unavailable: Text("Your iCloud account is currently unavailable.")
                    case .unknown: Text("Account availability has not been confirmed.")
                    }
                }
            }
            if controller.isUsingContinuedHistory {
                Section("Keep both histories") {
                    Text("New workouts, runs, and check-ins are saved in this local history. The earlier history files have not been replaced.")
                    Text("Use Settings → Backup & Data → Export Data to keep a copy of new entries before recovering or combining older records. Reopening the app keeps this same local history.")
                }
            } else {
                Section("Check iCloud") {
                    Button(controller.isCheckingCloudAccount ? "Checking Account…" : "Check iCloud Account") {
                        Task { await controller.checkCloudAccountStatus() }
                    }
                    .disabled(controller.isCheckingCloudAccount)
                    .accessibilityIdentifier("cloud.history.accountCheck")
                    Button("Open App Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Text("In Settings, confirm you use the same Apple Account and that iCloud access is enabled for Pace & Plates. Apple controls when downloads run.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                restoreSection
                Section("If older history is missing") {
                    Text("You can keep using your available history. Use the retained-history check above if older entries are missing. Keep the app installed while recovery is checked.")
                    Text("Additional Coach records and photos stay on this device. After app removal, entries that never reached iCloud need a backup kept elsewhere to restore them.")
                }
            }
        }
        .navigationTitle(controller.isUsingContinuedHistory ? "Local History" : "iCloud History")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("cloud.history.details")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .alert("Restore these retained records to iCloud?", isPresented: $confirmingRestore) {
            if let review = controller.cloudRestoreReview {
                Button("Schedule Restore of \(review.recordCount) Records") {
                    perform { try controller.scheduleCloudRestore(reviewID: review.id) }
                }
                .accessibilityIdentifier("cloud.history.confirmRestore")
            }
            Button("Keep Records Local", role: .cancel) { }
                .accessibilityIdentifier("cloud.history.cancelReview")
        } message: {
            Text("This explicitly restores the reviewed records even if they were intentionally deleted on another device. Existing iCloud records are kept. Restoration runs once on the next launch.")
        }
        .alert("Recovery Request Not Saved", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    @ViewBuilder private var restoreSection: some View {
        if let review = controller.cloudRestoreReview {
            Section("Review retained records") {
                Text("At the last check, \(review.recordCount) records retained on this device were missing from iCloud.")
                    .accessibilityIdentifier("cloud.history.review")
                Text("Checked \(review.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(review.entityCounts.keys.sorted(), id: \.self) { entity in
                    LabeledContent(category(entity), value: (review.entityCounts[entity] ?? 0).formatted())
                }
                if let first = review.earliestDate, let last = review.latestDate {
                    Text("Dated entries: \(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                Text("Missing records may include entries intentionally deleted on another device. Choose restoration only if you want these retained records back in iCloud.")
                if controller.cloudRestoreScheduled {
                    Text("Restoration is scheduled for the next launch. Close and reopen the app to start it.")
                        .accessibilityIdentifier("cloud.history.restoreScheduled")
                    Button("Cancel Scheduled Restore", role: .destructive) {
                        perform { try controller.cancelCloudRestore() }
                    }
                    .accessibilityIdentifier("cloud.history.cancelRestore")
                } else {
                    Button("Restore These Records on Next Launch") { confirmingRestore = true }
                        .accessibilityIdentifier("cloud.history.scheduleRestore")
                }
            }
        }
        Section("Retained-history check") {
            Button("Check Retained History on Next Launch") {
                perform { try controller.requestCloudHistoryReview() }
            }
            .disabled(controller.cloudRestoreScheduled || controller.cloudReviewRequested)
            .accessibilityIdentifier("cloud.history.requestReview")
            if controller.cloudReviewRequested { Text("Close and reopen the app to run this read-only check.") }
            Text("This checks records still held on this device. It does not restore records without your review, or recreate entries that disappeared when the app was deleted.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { actionError = error.localizedDescription }
    }
    private func category(_ entity: String) -> String {
        switch entity {
        case "WorkoutSession": return "Workouts"
        case "ExerciseLog": return "Workout sets"
        case "RunningSession": return "Runs and cardio"
        case "WeightEntry": return "Weight entries"
        case "ExerciseDefinition": return "Exercises"
        case "TrainingPlan", "RunningPlan": return "Plans"
        case "PlannedSession", "RunningPlanSession": return "Planned sessions"
        case "AIConversation": return "AI conversations"
        case "WorkoutTemplate", "TemplateExercise": return "Workout templates"
        case "HealthWorkoutInboxItem", "CardioWorkoutInboxItem": return "Workout inbox records"
        default: return "Other history"
        }
    }
}
