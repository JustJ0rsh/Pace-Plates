import SwiftUI
import SwiftData

// MARK: - Wearable Workout Inbox

/// Inbox of non-cardio wearable workouts imported from Apple Health.
/// Each item can be linked to an existing logged workout, turned into a
/// new workout, or dismissed.
struct WearableInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault

    @Query(
        filter: #Predicate<HealthWorkoutInboxItem> {
            $0.statusRaw == "pending" && $0.healthDeletionObservedAt == nil
        },
        sort: [SortDescriptor<HealthWorkoutInboxItem>(\.startDate, order: .reverse)]
    )
    private var pendingItems: [HealthWorkoutInboxItem]

    @State private var linkingItem: HealthWorkoutInboxItem? = nil
    @State private var createdSession: WorkoutSession? = nil
    @State private var isSyncing: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if pendingItems.isEmpty {
                    ContentUnavailableView(
                        "Inbox Empty",
                        systemImage: "tray",
                        description: Text("Workouts recorded on your Apple Watch or other wearables will appear here so you can link them to your training log.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(pendingItems) { item in
                        WearableInboxRow(
                            item: item,
                            onLink: { linkingItem = item },
                            onCreate: { createWorkout(from: item) },
                            onDismiss: { dismissItem(item) }
                        )
                    }
                }
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.top)
        }
        .navigationTitle("Workout Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground(AppTheme.gradientWorkouts)
        .foregroundColor(AppTheme.textColor)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .tint(AppTheme.accentColor)
        .refreshable { await syncNow() }
        .task { await syncNow() }
        .sheet(item: $linkingItem) { item in
            NavigationStack {
                WearableLinkPickerView(item: item) { session in
                    linkingItem = nil
                    _ = WearableWorkoutInboxService.link(item, to: session, context: modelContext)
                    Haptics.notify(.success)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $createdSession) { session in
            // The inbox service has already persisted and linked this workout.
            // It is not an expendable blank draft.
            WorkoutSessionDetailView(session: session, isNewSession: false)
        }
        .id(appTheme)
    }

    private func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        await WearableWorkoutInboxService.sync(context: modelContext)
        isSyncing = false
    }

    private func createWorkout(from item: HealthWorkoutInboxItem) {
        guard let session = WearableWorkoutInboxService.createSession(from: item, context: modelContext) else { return }
        Haptics.notify(.success)
        createdSession = session
    }

    private func dismissItem(_ item: HealthWorkoutInboxItem) {
        withAnimation {
            WearableWorkoutInboxService.dismiss(item, context: modelContext)
        }
    }
}

// MARK: - Row

private struct WearableInboxRow: View {
    let item: HealthWorkoutInboxItem
    let onLink: () -> Void
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: WearableWorkoutInboxService.activityIcon(for: item.activityType))
                    .font(.title3)
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accentColor.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(WearableWorkoutInboxService.activityDisplayName(for: item.activityType))
                        .font(.headline)
                    Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }

                Spacer()

                if let source = item.sourceName, !source.isEmpty {
                    Label(source, systemImage: "applewatch")
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentColor.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 14) {
                metric(icon: "clock", text: formattedDuration(item.duration))
                if let calories = item.calories {
                    metric(icon: "flame", text: "\(Int(calories.rounded())) kcal")
                }
                if let bpm = item.avgHeartRate {
                    metric(icon: "heart", text: "\(Int(bpm.rounded())) bpm")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button(action: onCreate) {
                    Label("Create Workout", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onLink) {
                    Label("Link…", systemImage: "link")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive, action: onDismiss) {
                Text("Dismiss")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryTextColor)
        }
        .padding()
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("wearable.inbox.item")
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AppTheme.secondaryTextColor)
    }
}

// MARK: - Link Picker

/// Lists logged workouts near the wearable workout's date so the user can
/// pick which one it belongs to.
private struct WearableLinkPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let item: HealthWorkoutInboxItem
    let onSelect: (WorkoutSession) -> Void

    @Query(sort: [SortDescriptor<WorkoutSession>(\.date, order: .reverse)])
    private var allSessions: [WorkoutSession]

    // Unlinked sessions within a week of the wearable workout, closest first;
    // falls back to recent sessions if none are nearby.
    private var candidates: [WorkoutSession] {
        let unlinked = allSessions.filter { ($0.healthWorkoutUUID ?? "").isEmpty }
        let nearby = unlinked
            .filter { abs($0.date.timeIntervalSince(item.startDate)) <= 7 * 86400 }
            .sorted { abs($0.date.timeIntervalSince(item.startDate)) < abs($1.date.timeIntervalSince(item.startDate)) }
        return nearby.isEmpty ? Array(unlinked.prefix(20)) : nearby
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                ContentUnavailableView(
                    "No Workouts to Link",
                    systemImage: "dumbbell",
                    description: Text("Log a workout first, or use Create Workout to start one from this activity.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(candidates) { session in
                        Button {
                            onSelect(session)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title.isEmpty ? "Gym Session" : session.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(AppTheme.textColor)
                                    Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.exerciseLogs?.count ?? 0) sets")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                }
                                Spacer()
                                if Calendar.current.isDate(session.date, inSameDayAs: item.startDate) {
                                    Text("Same day")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.accentColor.opacity(0.16))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                } header: {
                    Text("Link \(WearableWorkoutInboxService.activityDisplayName(for: item.activityType)) · \(item.startDate.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        }
        .navigationTitle("Link to Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - Helpers

fileprivate func formattedDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = Int(duration / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(max(totalMinutes, 1))m"
}
