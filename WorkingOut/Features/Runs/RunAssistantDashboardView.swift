import SwiftUI
import SwiftData

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

    private var activePlan: RunningPlan? {
        plans.first(where: { $0.isActive && !$0.isArchived })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let plan = activePlan {
                    activePlanCard(plan)
                    todayCard(plan)
                    weekSessionsCard(plan)
                    restDayMoveCard(plan)
                } else {
                    ContentUnavailableView(
                        "No Active Plan",
                        systemImage: "figure.run",
                        description: Text("Select a saved plan or reopen onboarding to activate a plan.")
                    )
                    .frame(maxWidth: .infinity)
                }

                if RunAssistantAIService.shared.canGenerate() {
                    aiCard
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
        }
        .onChange(of: runs.count) { _, _ in
            reconcileIfPossible()
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

        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Session")
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
            } else {
                Text("No scheduled session today.")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func weekSessionsCard(_ plan: RunningPlan) -> some View {
        let week = RunAssistantService.shared.sessionsForCurrentWeek(plan: plan)

        VStack(alignment: .leading, spacing: 8) {
            Text("Current Week")
                .font(.headline)

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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func restDayMoveCard(_ plan: RunningPlan) -> some View {
        let weekIndex = currentWeekIndex(for: plan)
        let currentWeek = (plan.sessions ?? []).filter { $0.weekIndex == weekIndex }
        let restWeekdays = Array(Set(currentWeek.filter { $0.sessionType == "rest" }.map { weekdayNumber($0) })).sorted()
        let nonRestWeekdays = Array(Set(currentWeek.filter { $0.sessionType != "rest" }.map { weekdayNumber($0) })).sorted()

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
                Text("No movable rest day this week.")
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
        VStack(alignment: .leading, spacing: 10) {
            Text("More Plans (Apple Intelligence)")
                .font(.headline)
            Text("Generate personalized plans using your cardio and weight data.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)

            HStack {
                aiButton("Generate Faster Plan", style: "speed")
                aiButton("Generate Endurance Plan", style: "endurance")
                aiButton("Generate Balanced Plan", style: "hybrid")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func aiButton(_ title: String, style: String) -> some View {
        Button(title) {
            pendingAIStyle = style
            pendingAITitle = title
            showAIGenerationSheet = true
        }
        .buttonStyle(.bordered)
        .disabled(showAIGenerationSheet)
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

    private func currentWeekIndex(for plan: RunningPlan) -> Int {
        let calendar = Calendar.current
        return max(0, calendar.dateComponents([.weekOfYear], from: plan.startDate, to: Date()).weekOfYear ?? 0)
    }

    private func todaySession(for plan: RunningPlan) -> RunningPlanSession? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let nonRest = (plan.sessions ?? []).filter { $0.sessionType != "rest" }

        let todays = nonRest.filter { session in
            guard let scheduledDate = session.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: today)
        }

        if let exact = todays.sorted(by: { $0.dayIndex < $1.dayIndex }).first {
            return exact
        }

        let pending = nonRest.filter { $0.status == "pending" }
        return pending.sorted {
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
        return Calendar.current.component(.weekday, from: date)
    }

    @ViewBuilder
    private func sessionSummary(_ session: RunningPlanSession) -> some View {
        let miles = (session.targetDistanceMeters ?? 0) / 1609.34
        let minutes = (session.targetDurationSeconds ?? 0) / 60

        if session.sessionType == "rest" {
            Text("Rest day")
        } else {
            Text("\(String(format: "%.2f", miles)) mi • \(Int(minutes)) min")
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
                .background(.ultraThinMaterial)
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
    @State private var streamText: String = ""
    @State private var generationID: Int = 0

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ProgressView().scaleEffect(1.2)
                            Text("Streaming AI generation")
                                .foregroundStyle(AppTheme.secondaryTextColor)
                        }

                        Text("Live output")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.secondaryTextColor)

                        ScrollView {
                            Text(
                                streamText.isEmpty
                                ? "Preparing on-device model. You will see generation text here as it arrives."
                                : streamText
                            )
                                .font(.footnote.monospaced())
                                .foregroundStyle(AppTheme.secondaryTextColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                        .background(AppTheme.secondaryBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("\(streamText.count) characters streamed")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor.opacity(0.9))
                    }
                    .padding(16)
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
                        VStack(alignment: .leading, spacing: 12) {
                            Text(draft.name)
                                .font(.title3.bold())
                            Text("\(draft.durationWeeks) weeks • \(draft.primaryGoal.capitalized) • \(draft.daysPerWeek) days/week")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryTextColor)

                            Divider()

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
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.secondaryBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
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
            .safeAreaInset(edge: .bottom) {
                if draft != nil && !isLoading {
                    HStack(spacing: 10) {
                        Button("Approve Plan") {
                            savePlan(activate: false)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(isSaving)

                        Button("Approve & Start Plan") {
                            savePlan(activate: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .top) {
                        Divider()
                    }
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
        streamText = ""
        do {
            draft = try await RunAssistantAIService.shared.generateDraft(
                style: style,
                profile: profile,
                context: modelContext,
                onStreamChunk: { chunk in
                    streamText += chunk
                }
            )
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
        return String(format: "%.2f mi • %.0f min", miles, minutes) + pace + notes
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
