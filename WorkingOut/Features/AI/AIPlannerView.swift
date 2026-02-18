import SwiftUI
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

struct AIPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("userEquipment") private var userEquipment: String = ""

    // Use Settings-backed goal directly
    // Lose | maintain | gain
    // This keeps the AI view in sync with Settings
    @State private var prompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var availability: WorkoutPlanGenerator.Availability = .unavailable
    @FocusState private var promptFocused: Bool
    @State private var showConversation: Bool = false
    @State private var showChat: Bool = false
    @State private var lastRequest: WorkoutPlanRequest? = nil
    @State private var mode: WorkoutPlanGenerator.Mode = .plan
    @State private var showResetConfirmation: Bool = false
    @State private var showResetSuccess: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Show availability-specific content
                if availability == .available {
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
            availability = WorkoutPlanGenerator.shared.availability()
            Task { await WorkoutPlanGenerator.shared.prewarmIfPossible() }
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

            GroupBox("Apple Intelligence (On‑device)") {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                        Text("On‑device model ready")
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
            Image(systemName: getUnavailableIcon())
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            // Title
            Text(getUnavailableTitle())
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Description
            Text(getUnavailableDescription())
                .font(.body)
                .foregroundStyle(AppTheme.secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Action button if applicable
            if shouldShowSettingsButton() {
                Button(action: openSettings) {
                    Label("Open Settings", systemImage: "gear")
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
    
    private func getUnavailableIcon() -> String {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .unavailable(.appleIntelligenceNotEnabled):
                return "sparkles.rectangle.stack"
            case .unavailable(.modelNotReady):
                return "arrow.down.circle"
            case .unavailable(.deviceNotEligible):
                return "exclamationmark.triangle"
            default:
                return "sparkles.rectangle.stack"
            }
            #endif
        }
        #endif
        return "exclamationmark.triangle"
    }
    
    private func getUnavailableTitle() -> String {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence Not Enabled"
            case .unavailable(.modelNotReady):
                return "AI Model Not Ready"
            case .unavailable(.deviceNotEligible):
                return "Device Not Supported"
            default:
                return "Apple Intelligence Unavailable"
            }
            #endif
        }
        #endif
        return "Apple Intelligence Unavailable"
    }
    
    private func getUnavailableDescription() -> String {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is not enabled on this device. To use AI-powered workout planning, please enable Apple Intelligence in Settings > Apple Intelligence & Siri."
            case .unavailable(.modelNotReady):
                return "The AI model is currently downloading or preparing. This may take a few minutes. Please check back shortly or restart the app once the download completes."
            case .unavailable(.deviceNotEligible):
                return "This device does not support Apple Intelligence. AI-powered features require a compatible device with Apple Intelligence capabilities."
            default:
                return "Apple Intelligence is currently unavailable. Please try again later."
            }
            #endif
        }
        #endif
        return "Apple Intelligence is not available on this device. This feature requires specific hardware and software support."
    }
    
    private func shouldShowSettingsButton() -> Bool {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            if case .unavailable(.appleIntelligenceNotEnabled) = model.availability {
                return true
            }
            #endif
        }
        #endif
        return false
    }
    
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

private extension WorkoutPlanGenerator.Availability {
    var description: String {
        switch self {
        case .available:
            return "On‑device model ready"
        case .unavailable:
            return "Using template fallback"
        case .unknown:
            return "Checking availability…"
        }
    }
}

#Preview {
    NavigationStack { AIPlannerView() }
        .modelContainer(PersistenceController.preview.container)
}
