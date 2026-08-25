import SwiftUI
import SwiftData

struct AIPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<TrainingPlan>(\.updatedAt, order: .reverse)])
    private var trainingPlans: [TrainingPlan]
    @Query(sort: [SortDescriptor<WorkoutTemplate>(\.createdDate, order: .reverse)])
    private var workoutTemplates: [WorkoutTemplate]
    @Query private var runningPlanSessions: [RunningPlanSession]
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("userEquipment") private var userEquipment: String = ""

    // Use Settings-backed goal directly
    // Lose | maintain | gain
    // This keeps the AI view in sync with Settings
    @State private var isGenerating: Bool = false
    @State private var showConversation: Bool = false
    @State private var showChat: Bool = false
    @State private var lastRequest: WorkoutPlanRequest? = nil
    @State private var mode: WorkoutPlanGenerator.Mode = .plan
    @State private var showResetConfirmation: Bool = false
    @State private var showResetSuccess: Bool = false
    @State private var statusRefreshTick: Int = 0
    @State private var showRunningPlans: Bool = false
    @State private var startedWorkout: WorkoutSession? = nil
    @State private var runTrackingRequest: CoachRunTrackingRequest? = nil
    @State private var planActionMessage: String? = nil

    private var providerStatus: AIProviderStatus {
        _ = statusRefreshTick
        return AIProviderManager.currentStatus()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                coachPlanContent
                runningPlansCard

                if providerStatus.canGenerateNow {
                    availableContent
                } else {
                    unavailableContent
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
        .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AIHistoryView()) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(AppTheme.toolbarButtonColor)
                }
                .accessibilityLabel("Coach history")
            }
        }
        .onAppear {
            Task { await WorkoutPlanGenerator.shared.prewarmIfPossible() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            statusRefreshTick += 1
        }
        .onChange(of: showRunningPlans) { _, isPresented in
            if !isPresented {
                TrainingPlanService.shared.syncRunningPlans(context: modelContext)
            }
        }
        .sheet(isPresented: $showConversation, onDismiss: { isGenerating = false }) {
            if let req = lastRequest {
                AIConversationSheet(mode: mode == .plan ? .plan : .ask, request: req)
            }
        }
        .sheet(isPresented: $showChat, onDismiss: { isGenerating = false }) {
            if let req = lastRequest {
                NavigationStack { AIChatSheet(requestBase: req) }
                    .modelContainer(PersistenceController.shared.container)
            }
        }
        .sheet(isPresented: $showRunningPlans) {
            RunAssistantContainerView { target in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    runTrackingRequest = CoachRunTrackingRequest(target: target)
                }
            }
            .presentationSizing(.page)
        }
        .sheet(item: $startedWorkout) { session in
            NavigationStack {
                WorkoutSessionDetailView(session: session, isNewSession: true)
            }
        }
        .sheet(item: $runTrackingRequest) { request in
            NavigationStack {
                RunTrackingProView(activityType: "running", plannedTarget: request.target)
                    .navigationTitle("Planned Run")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .tint(AppTheme.accentColor)
        }
        .appBackground(AppTheme.gradientAI)
        .foregroundColor(AppTheme.textColor)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .tint(AppTheme.accentColor)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("Reset Model Context?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                Task { @MainActor in
                    WorkoutPlanGenerator.shared.resetModelContext()
                    showResetSuccess = true
                    Haptics.notify(.success)
                }
            }
        } message: {
            Text("This will clear the AI model's memory and free up resources. Your conversation history will be preserved but the model will start fresh.")
        }
        .alert("Context Reset", isPresented: $showResetSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Model context has been successfully reset and offloaded.")
        }
        .alert("Coach", isPresented: Binding(
            get: { planActionMessage != nil },
            set: { if !$0 { planActionMessage = nil } }
        )) {
            Button("OK", role: .cancel) { planActionMessage = nil }
        } message: {
            Text(planActionMessage ?? "")
        }
        .task {
            TrainingPlanService.shared.syncRunningPlans(context: modelContext)
        }
        .id(appTheme) // Force rebuild when theme changes
    }

    private func generateTapped() {
        dismissKeyboard()
        isGenerating = true
        let req = WorkoutPlanRequest(
            goal: weightGoal,
            extraContext: buildExtraContext(),
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            modelContext: modelContext,
            mode: mode
        )
        lastRequest = req
        if mode == .ask {
            showChat = true
        } else {
            showConversation = true
        }
    }
    
    private func buildExtraContext() -> String {
        let trimmed = userEquipment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return "Available equipment: \(trimmed)."
    }
    
    private var goalDisplayName: String {
        switch weightGoal {
        case "lose": return "Lose Weight"
        case "gain": return "Gain Muscle"
        default: return "Maintain Fitness"
        }
    }

    private var activePlan: TrainingPlan? {
        trainingPlans.first { $0.status == "active" }
    }

    private var upcomingSession: PlannedSession? {
        guard let plan = activePlan else { return nil }
        return (plan.sessions ?? [])
            .filter { $0.status == "pending" }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
    }

    @ViewBuilder
    private var coachPlanContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your Training")
                    .font(.title3.bold())
                Spacer()
                if let plan = activePlan {
                    Text(plan.source == "running_assistant" ? "RUNNING PLAN" : "COACH PLAN")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityLabel(plan.source == "running_assistant" ? "Running plan" : "Coach plan")
                }
            }

            if let plan = activePlan {
                let sessions = plan.sessions ?? []
                let completedCount = sessions.filter { $0.status == "completed" }.count

                VStack(alignment: .leading, spacing: 12) {
                    Text(plan.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    if !sessions.isEmpty {
                        ProgressView(value: Double(completedCount), total: Double(sessions.count))
                            .tint(AppTheme.accentColor)
                        Text("\(completedCount) of \(sessions.count) sessions complete")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }

                    Divider().opacity(0.35)

                    if let session = upcomingSession {
                        plannedSessionContent(session)
                    } else {
                        Label("Plan complete", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                }
                .floatingTile()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No active plan", systemImage: "calendar.badge.plus")
                        .font(.headline)
                    Text("Build a running plan or generate a mixed training plan below. Coach will keep the next session ready here.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .floatingTile()
            }
        }
    }

    @ViewBuilder
    private func plannedSessionContent(_ session: PlannedSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: session.activityType))
                .font(.title3)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.scheduledDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryTextColor)
                Text(session.title)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = targetSummary(for: session) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }

        VStack(spacing: 8) {
            Button {
                start(session)
            } label: {
                Label(primaryActionTitle(for: session), systemImage: primaryActionIcon(for: session))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 8) {
                Button("Tomorrow") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    TrainingPlanService.shared.move(session, to: tomorrow, context: modelContext)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Skip") {
                    TrainingPlanService.shared.mark(session, status: "skipped", context: modelContext)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Complete") {
                    TrainingPlanService.shared.mark(session, status: "completed", context: modelContext)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .contain)
    }

    private var runningPlansCard: some View {
        Button {
            showRunningPlans = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Running Plans")
                        .font(.headline)
                        .foregroundStyle(AppTheme.textColor)
                    Text("Build, adapt, and manage a target-based running plan.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .floatingTile()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.runningPlans")
        .accessibilityHint("Opens running plan setup and schedule")
    }

    private func start(_ session: PlannedSession) {
        switch session.activityType {
        case "run":
            if let sourceID = session.runningPlanSessionID,
               let source = runningPlanSessions.first(where: { $0.id == sourceID }) {
                runTrackingRequest = CoachRunTrackingRequest(target: ScheduledRunTarget(session: source))
            } else {
                runTrackingRequest = CoachRunTrackingRequest(
                    target: ScheduledRunTarget(
                        sessionID: session.id,
                        sessionType: "planned",
                        targetDistanceMeters: session.targetDistanceMeters,
                        targetDurationSeconds: session.targetDurationSeconds,
                        targetPaceMinPerMile: session.targetPaceMinPerMile,
                        intensityLevel: session.intensityLevel ?? "moderate",
                        notes: session.notes
                    )
                )
            }
        case "rest", "recovery":
            TrainingPlanService.shared.mark(session, status: "completed", context: modelContext)
        default:
            guard let templateID = session.workoutTemplateID,
                  let template = workoutTemplates.first(where: { $0.id == templateID }) else {
                planActionMessage = "This session doesn’t have an executable workout yet. Generate the plan again to rebuild it."
                return
            }
            startedWorkout = WorkoutTemplateService.shared.createWorkoutFromTemplate(
                template: template,
                context: modelContext
            )
        }
    }

    private func icon(for activityType: String) -> String {
        switch activityType {
        case "run": return "figure.run"
        case "strength": return "dumbbell.fill"
        case "rest": return "bed.double.fill"
        case "recovery": return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }

    private func primaryActionTitle(for session: PlannedSession) -> String {
        switch session.activityType {
        case "run": return "Start Planned Run"
        case "rest", "recovery": return "Finish Recovery"
        default: return "Start Workout"
        }
    }

    private func primaryActionIcon(for session: PlannedSession) -> String {
        switch session.activityType {
        case "rest", "recovery": return "checkmark"
        default: return "play.fill"
        }
    }

    private func targetSummary(for session: PlannedSession) -> String? {
        var parts: [String] = []
        if let meters = session.targetDistanceMeters {
            let value = distanceUnit == "km" ? meters / 1_000 : meters / 1_609.344
            parts.append("\(value.formatted(.number.precision(.fractionLength(1)))) \(distanceUnit)")
        }
        if let duration = session.targetDurationSeconds {
            parts.append("\(Int(duration / 60)) min")
        }
        if let pace = session.targetPaceMinPerMile {
            let displayed = distanceUnit == "km" ? pace / 1.609344 : pace
            let minutes = Int(displayed)
            let seconds = Int((displayed - Double(minutes)) * 60)
            parts.append(String(format: "%d:%02d /%@", minutes, seconds, distanceUnit))
        }
        if let intensity = session.intensityLevel, !intensity.isEmpty {
            parts.append(intensity.capitalized)
        }
        return parts.isEmpty ? session.notes : parts.joined(separator: " • ")
    }
    
    // MARK: - Available Content (AI Ready)
    
    private var availableContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create with AI")
                .font(.title3.bold())

            GroupBox("Training Details") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $mode) {
                        Text("Plan").tag(WorkoutPlanGenerator.Mode.plan)
                        Text("Ask").tag(WorkoutPlanGenerator.Mode.ask)
                    }
                    .pickerStyle(.segmented)
                    
                    Text("Using goal: **\(goalDisplayName)** (change in Settings)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }

            // Equipment input between goal and model status
            GroupBox("Equipment") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available equipment (optional)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    TextField("e.g., dumbbells, barbell, bench, bike", text: $userEquipment)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .padding(10)
                        .background(AppTheme.secondaryBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            GroupBox(providerStatus.providerGroupTitle) {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text(providerStatus.providerReadyDescription)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Spacer()
                    }

                    HStack {
                        Spacer()
                        Button(action: { showResetConfirmation = true }) {
                            Label("Reset Model Context", systemImage: "arrow.counterclockwise.circle")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }
            }

            Text(mode == .plan
                 ? "Output will open in a new window and stream live."
                 : "Choose a suggestion or type your own training question.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryTextColor)

            Button(action: generateTapped) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    }
                    Text(isGenerating ? "Generating…" : (mode == .plan ? "Generate Weekly Plan" : "Ask AI"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)

            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Unavailable Content (AI Not Ready)
    
    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create with AI")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: unavailableIconName)
                    .font(.title2)
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(providerStatus.unavailableTitle)
                        .font(.headline)
                    Text(providerStatus.unavailableDescription)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if providerStatus.needsSystemSettings {
                Button(action: openSettings) {
                    Label("Open iPhone Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .floatingTile()
    }
    
    // MARK: - Unavailable State Helpers

    private var unavailableIconName: String {
        switch providerStatus.appleIntelligenceStatus {
        case .notEnabled:
            return "sparkles.rectangle.stack"
        case .modelNotReady:
            return "arrow.down.circle"
        case .unsupported, .unavailable:
            return "exclamationmark.triangle"
        case .available:
            return "checkmark.circle"
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private struct CoachRunTrackingRequest: Identifiable {
    let id = UUID()
    let target: ScheduledRunTarget
}

private extension WorkoutPlanGenerator.Availability {
    var description: String {
        switch self {
        case .available:
            return "AI ready"
        case .unavailable:
            return "AI unavailable"
        case .unknown:
            return "Checking availability…"
        }
    }
}

#Preview {
    NavigationStack { AIPlannerView() }
        .modelContainer(PersistenceController.preview.container)
}
