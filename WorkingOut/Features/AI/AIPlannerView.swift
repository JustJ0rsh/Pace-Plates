import SwiftUI
import SwiftData

struct AIPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

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
                GroupBox("Training Details") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Mode", selection: $mode) {
                            Text("Plan").tag(WorkoutPlanGenerator.Mode.plan)
                            Text("Ask").tag(WorkoutPlanGenerator.Mode.ask)
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Using goal: **\(goalDisplayName)** (change in Settings)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

            GroupBox(availability == .available ? "Apple Intelligence (On‑device)" : "Fallback Plan (Template)") {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(availability == .available ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(availability.description)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    if availability == .available {
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
            }

                Text("Output will open in a new window and stream live.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: generateTapped) {
                    HStack {
                        if isGenerating { ProgressView().tint(.white) }
                        Text(isGenerating ? "Generating…" : (mode == .plan ? "Generate Weekly Plan" : "Ask AI"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
        .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
        .navigationTitle("AI Planner")
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
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
    }

    private func generateTapped() {
        dismissKeyboard()
        isGenerating = true
        let req = WorkoutPlanRequest(
            goal: weightGoal,
            extraContext: prompt,
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
