import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct RunAssistantDashboardView: View {
    enum AIApprovalResult {
        case saved
        case started
    }

    @Environment(\.modelContext) private var modelContext

    @Binding var profile: RunAssistantProfile
    let onStartRun: () -> Void
    let onEditProfile: () -> Void

    @Query(sort: [SortDescriptor<RunningPlan>(\.updatedAt, order: .reverse)])
    private var plans: [RunningPlan]

    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)])
    private var runs: [RunningSession]

    @State private var generationError: String?
    @State private var successMessage: String?
    @State private var showAIGenerationSheet: Bool = false
    @State private var showBuiltInPlanSheet: Bool = false
    @State private var pendingAIStyle: String = "hybrid"
    @State private var pendingAITitle: String = "Generate Balanced Plan"
    @State private var restDayTargets: [Int: Int] = [:]
    @State private var selectedWeekOverride: Int? = nil
    @State private var statusRefreshTick: Int = 0

    private var currentAIProviderStatus: AIProviderStatus {
        _ = statusRefreshTick
        return AIProviderManager.currentStatus()
    }

    private var activePlan: RunningPlan? {
        plans.first(where: { $0.isActive && !$0.isArchived })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let plan = activePlan {
                    let displayedWeek = displayedWeekIndex(for: plan)
                    activePlanCard(plan)
                    todayCard(plan)
                    weekSessionsCard(plan, weekIndex: displayedWeek)
                    restDayMoveCard(plan, weekIndex: displayedWeek)
                } else {
                    ContentUnavailableView(
                        "No Active Plan",
                        systemImage: "figure.run",
                        description: Text("Select a saved plan or reopen onboarding to activate a plan.")
                    )
                    .frame(maxWidth: .infinity)
                }

                if currentAIProviderStatus.canGenerateNow {
                    aiCard
                } else {
                    aiUnavailableCard
                }

                savedPlansCard

                Button("Edit Profile") {
                    onEditProfile()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .alert("Running Assistant", isPresented: Binding(get: { generationError != nil }, set: { if !$0 { generationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(generationError ?? "")
        }
        .alert("Running Assistant", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .task {
            reconcileIfPossible()
            RunAssistantAIService.shared.prewarmIfPossible()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            statusRefreshTick += 1
        }
        .onChange(of: runs.count) { _, _ in
            reconcileIfPossible()
        }
        .onChange(of: activePlan?.id) { _, _ in
            selectedWeekOverride = nil
        }
        .sheet(isPresented: $showAIGenerationSheet) {
            RunAssistantAIGenerationSheet(
                title: pendingAITitle,
                style: pendingAIStyle,
                profile: $profile,
                onFinished: { result in
                    switch result {
                    case .success(.saved):
                        successMessage = "AI plan approved and saved."
                    case .success(.started):
                        successMessage = "AI plan approved, saved, and started."
                    case let .failure(error):
                        generationError = error.localizedDescription
                    }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBuiltInPlanSheet) {
            RunAssistantBuiltInPlanSheet(
                profile: $profile,
                onFinished: { started in
                    successMessage = started
                        ? "Pre-made plan saved and started."
                        : "Pre-made plan saved."
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func activePlanCard(_ plan: RunningPlan) -> some View {
        let all = (plan.sessions ?? [])
        let completed = all.filter { $0.status == "completed" }.count

        VStack(alignment: .leading, spacing: 8) {
            Text("Active Plan")
                .font(.headline)
            Text(plan.name)
                .font(.title3.bold())
            Text("\(completed)/\(all.count) sessions complete")
                .foregroundStyle(AppTheme.secondaryTextColor)
            Text("\(plan.durationWeeks) weeks • \(plan.style.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func todayCard(_ plan: RunningPlan) -> some View {
        let today = todaySession(for: plan)
        let upcoming = today == nil ? upcomingSession(for: plan) : nil

        VStack(alignment: .leading, spacing: 8) {
            Text(today != nil ? "Today's Session" : "Next Session")
                .font(.headline)

            if let session = today {
                sessionSummary(session)

                HStack {
                    Button("Start Run") {
                        onStartRun()
                    }
                    .buttonStyle(.borderedProminent)

                    if session.status == "completed" {
                        Button("Undo Complete") {
                            RunAssistantService.shared.markSession(
                                session.id,
                                status: "pending",
                                completionSource: nil,
                                completedRunSessionID: nil,
                                context: modelContext
                            )
                        }
                        .buttonStyle(.bordered)
                    } else if session.status == "skipped" {
                        Button("Undo Skip") {
                            RunAssistantService.shared.markSession(
                                session.id,
                                status: "pending",
                                completionSource: nil,
                                completedRunSessionID: nil,
                                context: modelContext
                            )
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Complete") {
                            RunAssistantService.shared.markSession(
                                session.id,
                                status: "completed",
                                completionSource: "manual",
                                completedRunSessionID: nil,
                                context: modelContext
                            )
                        }
                        .buttonStyle(.bordered)

                        Button("Skip") {
                            RunAssistantService.shared.markSession(
                                session.id,
                                status: "skipped",
                                completionSource: "manual",
                                completedRunSessionID: nil,
                                context: modelContext
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if let session = upcoming {
                Text("Rest day — nothing scheduled today.")
                    .foregroundStyle(AppTheme.secondaryTextColor)

                if let date = session.scheduledDate {
                    Text(upcomingLabel(for: date))
                        .font(.subheadline.bold())
                }
                sessionSummary(session)

                // Only "Start Run" is offered for a future session. We deliberately
                // omit "Complete"/"Skip" here so a session on another day is never
                // silently marked done from the today card.
                Button("Start Run") {
                    onStartRun()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No upcoming sessions scheduled.")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func upcomingLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Next Session · \(formatter.string(from: date))"
    }

    @ViewBuilder
    private func weekSessionsCard(_ plan: RunningPlan, weekIndex: Int) -> some View {
        let week = RunAssistantService.shared.sessionsForWeek(plan: plan, weekIndex: weekIndex)
        let weekCount = RunAssistantService.shared.totalWeekCount(plan: plan)
        let canGoPrev = weekIndex > 0
        let canGoNext = weekIndex < (weekCount - 1)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("Week \(weekIndex + 1) of \(weekCount)")
                    .font(.headline)

                Spacer()

                if selectedWeekOverride != nil {
                    Button("Auto") {
                        selectedWeekOverride = nil
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    guard canGoPrev else { return }
                    let target = RunAssistantService.shared.clampedWeekIndex(weekIndex - 1, plan: plan)
                    selectedWeekOverride = target
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canGoPrev)

                Button {
                    guard canGoNext else { return }
                    let target = RunAssistantService.shared.clampedWeekIndex(weekIndex + 1, plan: plan)
                    selectedWeekOverride = target
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .disabled(!canGoNext)
            }

            if week.isEmpty {
                Text("No sessions scheduled for this week.")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            } else {
                ForEach(week) { session in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(weekdayName(session)): \(session.sessionType.capitalized)")
                                .font(.subheadline.bold())
                            sessionSummary(session)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryTextColor)
                        }

                        Spacer()

                        if session.status == "completed" {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Button("Undo") {
                                    RunAssistantService.shared.markSession(
                                        session.id,
                                        status: "pending",
                                        completionSource: nil,
                                        completedRunSessionID: nil,
                                        context: modelContext
                                    )
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                            }
                        } else if session.status == "skipped" {
                            HStack(spacing: 8) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.orange)
                                Button("Undo") {
                                    RunAssistantService.shared.markSession(
                                        session.id,
                                        status: "pending",
                                        completionSource: nil,
                                        completedRunSessionID: nil,
                                        context: modelContext
                                    )
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Menu {
                                    Button("Easy") { RunAssistantService.shared.updateSessionIntensity(session.id, intensityLevel: "easy", context: modelContext) }
                                    Button("Moderate") { RunAssistantService.shared.updateSessionIntensity(session.id, intensityLevel: "moderate", context: modelContext) }
                                    Button("Hard") { RunAssistantService.shared.updateSessionIntensity(session.id, intensityLevel: "hard", context: modelContext) }
                                } label: {
                                    Text(session.intensityLevel.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppTheme.backgroundColor.opacity(0.25))
                                        .clipShape(Capsule())
                                }

                                Button {
                                    RunAssistantService.shared.markSession(
                                        session.id,
                                        status: "completed",
                                        completionSource: "manual",
                                        completedRunSessionID: nil,
                                        context: modelContext
                                    )
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                                .buttonStyle(.plain)

                                Button {
                                    RunAssistantService.shared.markSession(
                                        session.id,
                                        status: "skipped",
                                        completionSource: "manual",
                                        completedRunSessionID: nil,
                                        context: modelContext
                                    )
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func restDayMoveCard(_ plan: RunningPlan, weekIndex: Int) -> some View {
        let week = RunAssistantService.shared.sessionsForWeek(plan: plan, weekIndex: weekIndex)
        let restWeekdays = Array(Set(week.filter { $0.sessionType == "rest" }.map { weekdayNumber($0) })).sorted()
        let nonRestWeekdays = Array(Set(week.filter { $0.sessionType != "rest" }.map { weekdayNumber($0) })).sorted()

        VStack(alignment: .leading, spacing: 10) {
            Text("Move Rest Days")
                .font(.headline)

            if !restWeekdays.isEmpty && !nonRestWeekdays.isEmpty {
                ForEach(restWeekdays, id: \.self) { restDay in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest Day: \(weekdayName(restDay))")
                            .font(.subheadline)

                        HStack {
                            Picker("Move to", selection: bindingForRestTarget(restDay: restDay, candidates: nonRestWeekdays)) {
                                ForEach(nonRestWeekdays, id: \.self) { day in
                                    Text(weekdayName(day)).tag(day)
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Move") {
                                let destination = restDayTargets[restDay] ?? defaultTarget(for: restDay, candidates: nonRestWeekdays)
                                RunAssistantService.shared.moveRestDay(
                                    planID: plan.id,
                                    weekIndex: weekIndex,
                                    fromWeekday: restDay,
                                    toWeekday: destination,
                                    context: modelContext
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No movable rest day in this week.")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            normalizeRestTargets(restDays: restWeekdays, nonRestDays: nonRestWeekdays)
        }
        .onChange(of: restWeekdays) { _, newValue in
            normalizeRestTargets(restDays: newValue, nonRestDays: nonRestWeekdays)
        }
        .onChange(of: nonRestWeekdays) { _, newValue in
            normalizeRestTargets(restDays: restWeekdays, nonRestDays: newValue)
        }
    }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("More Plans")
                    .font(.headline)
                Spacer()
                Text("Apple Intelligence")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentColor.opacity(0.16))
                    .clipShape(Capsule())
            }
            Text("Generate personalized plans using your cardio and weight data.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)

            VStack(spacing: 8) {
                ForEach(aiPlanOptions) { option in
                    aiButton(option)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var aiUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("More Plans")
                    .font(.headline)
                Spacer()
                Text("Apple Required")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.20))
                    .clipShape(Capsule())
            }

            Text(currentAIProviderStatus.unavailableTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textColor)

            Text(currentAIProviderStatus.unavailableDescription)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)

            if currentAIProviderStatus.needsSystemSettings {
                Button {
                    openSettings()
                } label: {
                    Label("Open iPhone Settings", systemImage: "gear")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private struct AIPlanOption: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let style: String
    }

    private var aiPlanOptions: [AIPlanOption] {
        [
            AIPlanOption(
                id: "speed",
                title: "Generate Faster Plan",
                subtitle: "Build speed, intervals, and threshold focus",
                icon: "bolt.fill",
                style: "speed"
            ),
            AIPlanOption(
                id: "endurance",
                title: "Generate Endurance Plan",
                subtitle: "Increase base volume and long-run capacity",
                icon: "figure.run.circle",
                style: "endurance"
            ),
            AIPlanOption(
                id: "hybrid",
                title: "Generate Balanced Plan",
                subtitle: "Blend speed and endurance for all-around progress",
                icon: "dial.low.fill",
                style: "hybrid"
            )
        ]
    }

    @ViewBuilder
    private func aiButton(_ option: AIPlanOption) -> some View {
        Button {
            pendingAIStyle = option.style
            pendingAITitle = option.title
            showAIGenerationSheet = true
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: option.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(AppTheme.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textColor)
                    Text(option.subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(showAIGenerationSheet)
        .opacity(showAIGenerationSheet ? 0.65 : 1.0)
    }

    private var savedPlansCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Saved Plans")
                    .font(.headline)
                Spacer()
                Button {
                    showBuiltInPlanSheet = true
                } label: {
                    Label("Add Pre-Made Plan", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }

            ForEach(plans.filter { !$0.isArchived }) { plan in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(.subheadline.bold())
                        Text(plan.isActive ? "Active" : "Saved")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text("\(plan.source == "ai" ? "AI" : "Built-in") • Started \(formatPlanStartDate(plan.startDate))")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }

                    Spacer()

                    if !plan.isActive {
                        Button("Activate") {
                            RunAssistantService.shared.setActivePlan(plan.id, context: modelContext)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Archive") {
                        RunAssistantService.shared.archivePlan(plan.id, context: modelContext)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func reconcileIfPossible() {
        guard let activePlan else { return }
        RunAssistantService.shared.reconcileCompletions(activePlan: activePlan, runs: runs, context: modelContext)
    }

    private func displayedWeekIndex(for plan: RunningPlan) -> Int {
        let autoWeek = RunAssistantService.shared.autoDisplayWeekIndex(plan: plan)
        let base = selectedWeekOverride ?? autoWeek
        return RunAssistantService.shared.clampedWeekIndex(base, plan: plan)
    }

    /// A non-rest session actually scheduled for today, or nil on a rest/empty day.
    private func todaySession(for plan: RunningPlan) -> RunningPlanSession? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nonRest = (plan.sessions ?? []).filter { $0.sessionType != "rest" }

        let todays = nonRest.filter { session in
            guard let scheduledDate = session.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: today)
        }

        return todays.sorted(by: { $0.dayIndex < $1.dayIndex }).first
    }

    /// The soonest pending non-rest session scheduled after today. Used only when
    /// there is nothing scheduled today, so the card can offer a clearly-labeled
    /// "next" session instead of passing off a future session as today's.
    private func upcomingSession(for plan: RunningPlan) -> RunningPlanSession? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nonRest = (plan.sessions ?? []).filter { $0.sessionType != "rest" }

        let future = nonRest.filter { session in
            guard session.status == "pending", let scheduledDate = session.scheduledDate else { return false }
            return scheduledDate >= today
        }

        return future.sorted {
            ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture)
        }.first
    }

    private func weekdayName(_ session: RunningPlanSession) -> String {
        let day = weekdayNumber(session)
        return weekdayName(day)
    }

    private func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "Day"
        }
    }

    private func weekdayNumber(_ session: RunningPlanSession) -> Int {
        guard let date = session.scheduledDate else { return 1 }
        return RunAssistantWeekday.weekday(of: date)
    }

    @ViewBuilder
    private func sessionSummary(_ session: RunningPlanSession) -> some View {
        let miles = (session.targetDistanceMeters ?? 0) / 1609.34
        let minutes = (session.targetDurationSeconds ?? 0) / 60

        if session.sessionType == "rest" {
            Text("Rest day")
        } else {
            let parts = [
                miles > 0.01 ? "\(String(format: "%.2f", miles)) mi" : nil,
                minutes >= 1 ? "\(Int(minutes)) min" : nil
            ].compactMap { $0 }

            if parts.isEmpty {
                if let notes = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                } else {
                    Text("Planned training session")
                }
            } else {
                Text(parts.joined(separator: " • "))
            }
        }
    }

    private func bindingForRestTarget(restDay: Int, candidates: [Int]) -> Binding<Int> {
        Binding(
            get: {
                restDayTargets[restDay] ?? defaultTarget(for: restDay, candidates: candidates)
            },
            set: { newValue in
                restDayTargets[restDay] = newValue
            }
        )
    }

    private func defaultTarget(for restDay: Int, candidates: [Int]) -> Int {
        candidates.first(where: { $0 != restDay }) ?? candidates.first ?? restDay
    }

    private func normalizeRestTargets(restDays: [Int], nonRestDays: [Int]) {
        var next: [Int: Int] = [:]
        for rest in restDays {
            let existing = restDayTargets[rest]
            if let existing, nonRestDays.contains(existing), existing != rest {
                next[rest] = existing
            } else {
                next[rest] = defaultTarget(for: rest, candidates: nonRestDays)
            }
        }
        restDayTargets = next
    }

    private func formatPlanStartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

private struct RunAssistantBuiltInPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var profile: RunAssistantProfile
    let onFinished: (Bool) -> Void

    @State private var selectedTemplateID: String? = nil
    @State private var showAllPlans: Bool = false
    @State private var isSaving: Bool = false

    private var rankedTemplates: [RunPlanTemplateDescriptor] {
        RunAssistantService.shared.recommendedTemplates(for: profile)
    }

    private var visibleTemplates: [RunPlanTemplateDescriptor] {
        showAllPlans ? rankedTemplates : Array(rankedTemplates.prefix(6))
    }

    private var selectedTemplate: RunPlanTemplateDescriptor? {
        guard let selectedTemplateID else { return nil }
        return rankedTemplates.first(where: { $0.id == selectedTemplateID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose a built-in plan to save to your library. You can start it now or later.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)

                    ForEach(visibleTemplates) { template in
                        Button {
                            selectedTemplateID = template.id
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(template.name)
                                        .font(.headline)
                                    Spacer()
                                    if selectedTemplateID == template.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accentColor)
                                    }
                                }
                                Text("\(template.durationWeeks) weeks • \(template.primaryGoal.capitalized) • \(styleLabel(template.style))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.secondaryBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(showAllPlans ? "Show Fewer Plans" : "Show All 15 Plans") {
                        showAllPlans.toggle()
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding()
                .padding(.bottom, 96)
            }
            .navigationTitle("Add Pre-Made Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button("Save Plan") {
                        createPlan(activate: false)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedTemplate == nil || isSaving)

                    Button("Save & Start Plan") {
                        createPlan(activate: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedTemplate == nil || isSaving)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.secondaryBackgroundColor)
                .overlay(alignment: .top) {
                    Divider()
                }
            }
        }
    }

    private func createPlan(activate: Bool) {
        guard let selectedTemplate else { return }
        isSaving = true
        let plan = RunAssistantService.shared.createPlan(
            from: selectedTemplate,
            profile: profile,
            startDate: Date(),
            context: modelContext
        )
        if activate {
            RunAssistantService.shared.setActivePlan(plan.id, context: modelContext)
        }
        isSaving = false
        onFinished(activate)
        dismiss()
    }

    private func styleLabel(_ style: String) -> String {
        style.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private struct RunAssistantAIGenerationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let title: String
    let style: String
    @Binding var profile: RunAssistantProfile
    let onFinished: (Result<RunAssistantDashboardView.AIApprovalResult, Error>) -> Void

    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var draft: RunAssistantAIService.PlanDraft? = nil
    @State private var localError: String? = nil
    @State private var generationID: Int = 0
    @State private var streamingOpacity: Double = 0.5
    @State private var waitingForFirstChunk: Bool = true
    @State private var displayedStreamText: String = ""
    @State private var fullBufferedStreamText: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .bottom) {
                                Spacer(minLength: 40)
                                loadingBubble(text: loadingPromptText, isAssistant: false, isStreamingBubble: false)
                            }

                            HStack(alignment: .bottom) {
                                if waitingForFirstChunk {
                                    loadingBubble(text: "Generating…", isAssistant: true, isStreamingBubble: true)
                                } else {
                                    loadingBubble(
                                        text: displayedStreamText,
                                        isAssistant: true,
                                        isStreamingBubble: false
                                    )
                                }
                                Spacer(minLength: 40)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if let localError {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(localError)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Button("Close") { dismiss() }
                            .buttonStyle(.bordered)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let draft {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(draft.name)
                                    .font(.title3.bold())
                                Text("\(draft.durationWeeks) weeks • \(draft.primaryGoal.capitalized) • \(draft.daysPerWeek) days/week")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.secondaryBackgroundColor.opacity(0.92))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(AppTheme.textColor.opacity(0.10), lineWidth: 1)
                            )

                            ForEach(groupedWeekIndexes(draft), id: \.self) { week in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Week \(week + 1)")
                                        .font(.headline)

                                    ForEach(sessionsForWeek(draft, week: week), id: \._rowKey) { row in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(weekdayName(row.scheduledWeekday)) • \(row.sessionType.capitalized)")
                                                .font(.subheadline)
                                            Text(detailText(row))
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryTextColor)
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppTheme.secondaryBackgroundColor.opacity(0.92))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(AppTheme.textColor.opacity(0.10), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .safeAreaInset(edge: .bottom) {
                if draft != nil && !isLoading {
                    HStack(spacing: 10) {
                        Button {
                            savePlan(activate: false)
                        } label: {
                            Text("Approve Plan")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppTheme.accentColor.opacity(0.82)))
                        }
                        .disabled(isSaving)

                        Button {
                            savePlan(activate: true)
                        } label: {
                            Text("Approve & Start Plan")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(AppTheme.accentColor))
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        VStack(spacing: 0) {
                            Divider()
                            Rectangle()
                                .fill(.ultraThinMaterial)
                        }
                        .ignoresSafeArea()
                    )
                }
            }
            .task(id: generationID) {
                await generateDraft()
            }
        }
    }

    private func generateDraft() async {
        isLoading = true
        localError = nil
        draft = nil
        waitingForFirstChunk = true
        displayedStreamText = ""
        fullBufferedStreamText = ""
        streamingOpacity = 0.2
        withAnimation(.easeInOut(duration: 0.25)) {
            streamingOpacity = 1.0
        }
        do {
            draft = try await RunAssistantAIService.shared.generateDraft(
                style: style,
                profile: profile,
                context: modelContext,
                onStreamChunk: { chunk in
                    if waitingForFirstChunk && !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        waitingForFirstChunk = false
                    }
                    fullBufferedStreamText += chunk
                    displayedStreamText = sanitizeStreamPreview(fullBufferedStreamText)
                }
            )
            displayedStreamText = sanitizeStreamPreview(fullBufferedStreamText)
            isLoading = false
        } catch is CancellationError {
            // Expected when the user regenerates while a generation is in-flight.
            isLoading = false
        } catch {
            localError = error.localizedDescription
            onFinished(.failure(error))
            isLoading = false
        }
    }

    private func savePlan(activate: Bool) {
        guard let draft else { return }
        isSaving = true
        _ = RunAssistantAIService.shared.saveDraft(draft, profile: profile, context: modelContext, activate: activate)
        isSaving = false
        onFinished(.success(activate ? .started : .saved))
        dismiss()
    }

    private var loadingPromptText: String {
        "Build a \(style.replacingOccurrences(of: "_", with: " ")) running plan for me. \(profile.daysPerWeek) days per week, focused on \(profile.goalFocus)."
    }

    @ViewBuilder
    private func loadingBubble(text: String, isAssistant: Bool, isStreamingBubble: Bool) -> some View {
        let bubbleFill: Color = isAssistant
            ? AppTheme.secondaryBackgroundColor.opacity(0.90)
            : AppTheme.accentColor.opacity(0.22)
        let showGeneratingState = isAssistant && isStreamingBubble

        VStack(alignment: .leading, spacing: 0) {
            if showGeneratingState {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.textColor))
                        .scaleEffect(0.85)
                    Text(text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textColor)
                }
                .padding(14)
            } else {
                MarkdownView(text: text)
                    .padding(14)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(bubbleFill)

                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AppTheme.textColor.opacity(0.12), lineWidth: 1)
            }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .opacity(isAssistant && isStreamingBubble ? streamingOpacity : 1.0)
    }

    private func sanitizeStreamPreview(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var intro: [String] = []
        var weekOrder: [Int] = []
        var weekSections: [Int: [String]] = [:]
        var currentWeek: Int? = nil
        var seenWeeks: Set<Int> = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let weekNumber = weekNumber(from: trimmed) {
                currentWeek = weekNumber
                if seenWeeks.insert(weekNumber).inserted {
                    weekOrder.append(weekNumber)
                }
                // If the model loops and repeats week headings, keep the latest section only.
                weekSections[weekNumber] = []
                continue
            }

            if let currentWeek {
                weekSections[currentWeek, default: []].append(line)
            } else {
                intro.append(line)
            }
        }

        var output = collapseConsecutiveDuplicateLines(intro)
        if !output.isEmpty && !weekOrder.isEmpty {
            output.append("")
        }

        for (index, week) in weekOrder.enumerated() {
            output.append("Week \(week)")
            output.append(contentsOf: collapseConsecutiveDuplicateLines(weekSections[week] ?? []))
            if index < weekOrder.count - 1 {
                output.append("")
            }
        }

        let rendered = output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? "Generating running plan preview..." : rendered
    }

    private func collapseConsecutiveDuplicateLines(_ lines: [String]) -> [String] {
        var collapsed: [String] = []
        for line in lines {
            if collapsed.last != line {
                collapsed.append(line)
            }
        }
        return collapsed
    }

    private func weekNumber(from line: String) -> Int? {
        let lower = line.lowercased()
        guard lower.hasPrefix("week ") else { return nil }
        let suffix = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty, let week = Int(digits), week > 0 else { return nil }
        return week
    }

    private func groupedWeekIndexes(_ draft: RunAssistantAIService.PlanDraft) -> [Int] {
        Array(Set(draft.sessions.map { $0.weekIndex })).sorted()
    }

    private func sessionsForWeek(_ draft: RunAssistantAIService.PlanDraft, week: Int) -> [RunPlanSessionBlueprint] {
        draft.sessions
            .filter { $0.weekIndex == week }
            .sorted {
                if $0.scheduledWeekday == $1.scheduledWeekday {
                    return $0.dayIndex < $1.dayIndex
                }
                return $0.scheduledWeekday < $1.scheduledWeekday
            }
    }

    private func detailText(_ session: RunPlanSessionBlueprint) -> String {
        if session.sessionType == "rest" {
            return session.notes ?? "Rest day"
        }

        let miles = (session.targetDistanceMeters ?? 0) / 1609.34
        let minutes = (session.targetDurationSeconds ?? 0) / 60
        let pace = session.targetPaceMinPerMile.map { " @ \(formatPaceMinSec($0))/mi" } ?? ""
        let notes = session.notes.map { " • \($0)" } ?? ""
        let parts = [
            miles > 0.01 ? String(format: "%.2f mi", miles) : nil,
            minutes >= 1 ? String(format: "%.0f min", minutes) : nil
        ].compactMap { $0 }

        if parts.isEmpty {
            let notes = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = (notes?.isEmpty == false ? notes : nil) ?? "Planned training session"
            return fallback + pace
        }
        return parts.joined(separator: " • ") + pace + notes
    }

    private func formatPaceMinSec(_ minPerMile: Double) -> String {
        guard minPerMile.isFinite, minPerMile > 0 else { return "--:--" }
        let totalSeconds = Int((minPerMile * 60.0).rounded())
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "Day"
        }
    }
}

private extension RunPlanSessionBlueprint {
    var _rowKey: String {
        "\(weekIndex)-\(dayIndex)-\(scheduledWeekday)-\(sessionType)-\(targetDistanceMeters ?? 0)-\(targetDurationSeconds ?? 0)"
    }
}
