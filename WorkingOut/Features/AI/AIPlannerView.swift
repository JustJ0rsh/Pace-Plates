import SwiftUI
import SwiftData

struct AIPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("userEquipment") private var userEquipment: String = ""
    @AppStorage(AIProviderManager.providerPreferenceKey) private var aiProviderPreferenceRaw: String = AIProviderPreference.appleIntelligence.rawValue
    @AppStorage(AIProviderManager.openRouterKeyConfiguredKey) private var openRouterKeyConfigured: Bool = false
    @AppStorage(AIProviderManager.openRouterResolvedModelKey) private var openRouterResolvedModel: String = ""
    @AppStorage(AIUsageBudgetManager.openRouterDailyLimitPreferenceKey) private var openRouterDailyLimit: Int = AIUsageBudgetManager.openRouterFreeUserDailyRequestLimit

    // Use Settings-backed goal directly
    // Lose | maintain | gain
    // This keeps the AI view in sync with Settings
    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @FocusState private var promptFocused: Bool
    @State private var showConversation: Bool = false
    @State private var showChat: Bool = false
    @State private var lastRequest: WorkoutPlanRequest? = nil
    @State private var mode: WorkoutPlanGenerator.Mode = .plan
    @State private var showResetConfirmation: Bool = false
    @State private var showResetSuccess: Bool = false
    @State private var statusRefreshTick: Int = 0

    private var providerStatus: AIProviderStatus {
        _ = aiProviderPreferenceRaw
        _ = openRouterKeyConfigured
        _ = openRouterResolvedModel
        _ = statusRefreshTick
        return AIProviderManager.currentStatus()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Show availability-specific content
                if providerStatus.canGenerateNow {
                    // AI is ready - show normal UI
                    availableContent
                } else {
                    // AI not available - show appropriate message
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
        .navigationTitle("AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AIHistoryView()) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("AI History")
            }
        }
        .onAppear {
            AIProviderManager.bootstrapOpenRouterKeyIfAvailable()
            Task { await WorkoutPlanGenerator.shared.prewarmIfPossible() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            statusRefreshTick += 1
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
        if trimmed.isEmpty { return prompt }
        return "Available equipment: \(trimmed). " + prompt
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
    
    private var goalDisplayName: String {
        switch weightGoal {
        case "lose": return "Lose Weight"
        case "gain": return "Gain Muscle"
        default: return "Maintain Fitness"
        }
    }
    
    // MARK: - Available Content (AI Ready)
    
    private var availableContent: some View {
        VStack(spacing: 16) {
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
                            .fill(providerStatus.effectiveProvider == .appleIntelligence ? Color.green : AppTheme.accentColor)
                            .frame(width: 10, height: 10)
                        Text(providerStatus.providerReadyDescription)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Spacer()
                    }

                    if providerStatus.effectiveProvider == .appleIntelligence {
                        HStack {
                            Spacer()
                            Button(action: { showResetConfirmation = true }) {
                                Label("Reset Model Context", systemImage: "arrow.counterclockwise.circle")
                                    .font(.footnote)
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                    } else {
                        Text("Cloud requests are sent through OpenRouter only while this provider is selected.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(openRouterBudgetSummary)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Text(mode == .plan
                 ? "Output will open in a new window and stream live."
                 : "Open structured Ask mode, then choose a health, strength, or endurance prompt.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryTextColor)

            Button(action: generateTapped) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    }
                    Text(isGenerating ? "Generating…" : (mode == .plan ? "Generate Weekly Plan" : "Open Structured Ask"))
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
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            Image(systemName: unavailableIconName)
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title
            Text(providerStatus.unavailableTitle)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Description
            Text(providerStatus.unavailableDescription)
                .font(.body)
                .foregroundStyle(AppTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            NavigationLink(destination: SettingsView()) {
                Label(providerStatus.needsAppConfiguration ? "Configure OpenRouter" : "AI Provider Settings", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 32)

            if providerStatus.needsSystemSettings {
                Button(action: openSettings) {
                    Label("Open iPhone Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }
            
            Spacer()
            Spacer()
        }
    }
    
    // MARK: - Unavailable State Helpers

    private var unavailableIconName: String {
        switch providerStatus.effectiveProvider {
        case .appleIntelligence:
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
        case .openRouter:
            return providerStatus.hasOpenRouterKey ? "wifi.exclamationmark" : "key.slash"
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var openRouterBudgetSummary: String {
        _ = openRouterDailyLimit
        let budget = AIUsageBudgetManager.currentOpenRouterStatus()
        return "\(budget.dailyRemaining)/\(budget.dailyLimit) free-model requests left today, \(budget.minuteRemaining)/\(budget.minuteLimit) left this minute. One AI action may use up to \(AIUsageBudgetManager.maxModelAttemptsPerRequest) attempts if free providers are busy."
    }
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
