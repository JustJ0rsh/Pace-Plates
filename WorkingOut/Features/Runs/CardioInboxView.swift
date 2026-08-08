import SwiftData
import SwiftUI
import UIKit

/// Review surface for runs, walks, hikes, and other cardio recorded by Oura,
/// Apple Watch, or another app through Apple Health.
struct CardioInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("distanceUnit") private var distanceUnit = "mi"

    @Query(
        filter: #Predicate<CardioWorkoutInboxItem> {
            $0.statusRaw == "pending" && $0.healthDeletionObservedAt == nil
        },
        sort: [SortDescriptor<CardioWorkoutInboxItem>(\.startDate, order: .reverse)]
    )
    private var pendingItems: [CardioWorkoutInboxItem]

    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)])
    private var runningSessions: [RunningSession]

    @State private var linkingItem: CardioWorkoutInboxItem?
    @State private var createdSession: RunningSession?
    @State private var workingItemID: UUID?
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                explanationCard

                if isSyncing && pendingItems.isEmpty {
                    ProgressView("Checking Apple Health…")
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .accessibilityIdentifier("cardio.inbox.syncing")
                } else if pendingItems.isEmpty {
                    emptyState
                } else {
                    ForEach(pendingItems) { item in
                        let suggestion = runningSessions.first {
                            $0.id == item.suggestedRunningSessionID
                        }
                        CardioInboxRow(
                            item: item,
                            suggestedSession: suggestion,
                            distanceUnit: distanceUnit,
                            isWorking: workingItemID == item.id,
                            onLinkSuggested: {
                                guard let suggestion else { return }
                                link(item, to: suggestion)
                            },
                            onReview: { linkingItem = item },
                            onCreate: { createActivity(from: item) },
                            onDismiss: { dismissItem(item) }
                        )
                    }
                }

                if let syncErrorMessage {
                    syncErrorCard(syncErrorMessage)
                }
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.vertical)
        }
        .accessibilityIdentifier("cardio.inbox.ready")
        .navigationTitle("Cardio Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground(AppTheme.gradientRuns)
        .foregroundStyle(AppTheme.textColor)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .tint(AppTheme.accentColor)
        .refreshable { await syncNow(requestAuthorization: true) }
        .task { await syncNow() }
        .sheet(item: $linkingItem) { item in
            NavigationStack {
                CardioLinkPickerView(item: item)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $createdSession) { session in
            RunSessionDetailView(session: session)
        }
        .id(appTheme)
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title2)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 40, height: 40)
                .background(AppTheme.accentColor.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Combine recordings, not activities")
                    .font(.headline)
                Text("Pair an Oura or Apple Health activity with the walk, run, or ride you tracked here. Pace & Plates keeps one activity and adds heart rate, calories, and other available metrics.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingTile()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Inbox Empty",
                systemImage: "tray",
                description: Text("New cardio workouts from Oura, Apple Watch, and other Apple Health sources will appear here for review.")
            )
            .frame(maxWidth: .infinity, minHeight: 200)

            Button {
                Task { await syncNow(requestAuthorization: true) }
            } label: {
                Label("Check Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier("cardio.inbox.empty")
    }

    private func syncErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn’t check Apple Health", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryTextColor)
            Button("Try Again") {
                Task { await syncNow(requestAuthorization: true) }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("cardio.inbox.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingTile()
        .accessibilityIdentifier("cardio.inbox.error")
    }

    private func syncNow(requestAuthorization: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncErrorMessage = nil
        let result = await CardioWorkoutInboxService.sync(
            context: modelContext,
            requestAuthorization: requestAuthorization
        )
        syncErrorMessage = result.errorMessage
        isSyncing = false
    }

    private func link(
        _ item: CardioWorkoutInboxItem,
        to session: RunningSession
    ) {
        guard workingItemID == nil else { return }
        workingItemID = item.id
        Task {
            let didLink = await CardioWorkoutInboxService.link(
                item,
                to: session,
                context: modelContext
            )
            workingItemID = nil
            if didLink {
                Haptics.notify(.success)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Activity linked"
                )
            }
        }
    }

    private func createActivity(from item: CardioWorkoutInboxItem) {
        guard workingItemID == nil else { return }
        workingItemID = item.id
        Task {
            let session = await CardioWorkoutInboxService.createSession(
                from: item,
                context: modelContext
            )
            workingItemID = nil
            if let session {
                Haptics.notify(.success)
                createdSession = session
            }
        }
    }

    private func dismissItem(_ item: CardioWorkoutInboxItem) {
        withAnimation {
            CardioWorkoutInboxService.dismiss(item, context: modelContext)
        }
    }
}

private struct CardioInboxRow: View {
    let item: CardioWorkoutInboxItem
    let suggestedSession: RunningSession?
    let distanceUnit: String
    let isWorking: Bool
    let onLinkSuggested: () -> Void
    let onReview: () -> Void
    let onCreate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: CardioWorkoutInboxService.activityIcon(for: item.activityType))
                    .font(.title3)
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accentColor.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(CardioWorkoutInboxService.activityDisplayName(for: item.activityType))
                        .font(.headline)
                        .accessibilityIdentifier("cardio.inbox.item.\(item.id).summary")
                    Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }

                Spacer()

                if let source = item.sourceName, !source.isEmpty {
                    Label(source, systemImage: "heart.text.square.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentColor.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { metrics }
                VStack(alignment: .leading, spacing: 6) { metrics }
            }

            if let suggestedSession {
                suggestedMatch(suggestedSession)
                Button(action: onLinkSuggested) {
                    if isWorking {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Link Suggested Activity", systemImage: "link.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
                .accessibilityIdentifier("cardio.inbox.item.\(item.id).link")

                Button("Review Other Matches", action: onReview)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("cardio.inbox.item.\(item.id).review")
            } else {
                Text("No confident match found. Create a new activity or choose one yourself.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)

                HStack(spacing: 10) {
                    Button(action: onCreate) {
                        Label("Create Activity", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    .accessibilityIdentifier("cardio.inbox.item.\(item.id).create")

                    Button(action: onReview) {
                        Label("Link…", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cardio.inbox.item.\(item.id).review")
                }
            }

            Button(role: .destructive, action: onDismiss) {
                Text("Dismiss")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryTextColor)
        }
        .floatingTile()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metrics: some View {
        metric(icon: "clock", text: cardioDuration(item.duration))
        if item.distanceMeters > 0 {
            let distance = distanceUnit == "mi"
                ? item.distanceMeters / 1609.34
                : item.distanceMeters / 1000
            metric(icon: "location", text: String(format: "%.2f %@", distance, distanceUnit))
        }
        if let heartRate = item.avgHeartRate {
            metric(icon: "heart.fill", text: "\(Int(heartRate.rounded())) bpm")
        }
        if let calories = item.calories {
            metric(icon: "flame", text: "\(Int(calories.rounded())) kcal")
        }
    }

    private func suggestedMatch(_ session: RunningSession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppTheme.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Suggested match")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentColor)
                Text(
                    "\(CardioWorkoutInboxService.activityDisplayName(for: session.activityType)) · \(session.date.formatted(date: .omitted, time: .shortened)) · \(String(format: "%.2f", session.distance)) \(session.distanceUnit)"
                )
                .font(.subheadline.weight(.medium))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding(10)
        .background(AppTheme.accentColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.secondaryTextColor)
    }
}

private struct CardioLinkPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: CardioWorkoutInboxItem

    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)])
    private var allSessions: [RunningSession]

    @State private var linkingSessionID: UUID?
    @State private var errorMessage: String?

    private var candidates: [RunningSession] {
        CardioWorkoutInboxService.rankedCandidates(
            for: item,
            in: allSessions
        )
    }

    var body: some View {
        List {
            if candidates.isEmpty {
                ContentUnavailableView(
                    "No Activities to Link",
                    systemImage: "figure.run",
                    description: Text("Track or log a matching \(CardioWorkoutInboxService.activityDisplayName(for: item.activityType).lowercased()) first, or create a new activity from the inbox.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(candidates) { session in
                        Button {
                            link(to: session)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: CardioWorkoutInboxService.activityIcon(for: session.activityType))
                                    .foregroundStyle(AppTheme.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(CardioWorkoutInboxService.activityDisplayName(for: session.activityType))
                                            .font(.body.weight(.medium))
                                        if session.id == item.suggestedRunningSessionID {
                                            Text("Suggested")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(AppTheme.accentColor)
                                        }
                                    }
                                    Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.2f", session.distance)) \(session.distanceUnit) · \(cardioDuration(session.duration))")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                }
                                Spacer()
                                if linkingSessionID == session.id {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(AppTheme.secondaryTextColor)
                                }
                            }
                        }
                        .disabled(linkingSessionID != nil)
                        .accessibilityIdentifier("cardio.inbox.candidate.\(session.id)")
                    }
                } header: {
                    Text("Choose the app activity recorded at the same time")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Link Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func link(to session: RunningSession) {
        guard linkingSessionID == nil else { return }
        linkingSessionID = session.id
        errorMessage = nil
        Task {
            let didLink = await CardioWorkoutInboxService.link(
                item,
                to: session,
                context: modelContext
            )
            linkingSessionID = nil
            if didLink {
                Haptics.notify(.success)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: "Activity linked"
                )
                dismiss()
            } else {
                errorMessage = "This activity could not be linked. Please try again."
            }
        }
    }
}

private func cardioDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = max(Int(duration / 60), 1)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
