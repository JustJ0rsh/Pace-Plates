import SwiftUI
import SwiftData

struct RunAssistantContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onStartRun: () -> Void

    @AppStorage("didCompleteRunAssistantOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("runAssistantGoalFocus") private var goalFocus: String = "hybrid"
    @AppStorage("runAssistantTargetDistanceMiles") private var targetDistanceMiles: Double = 3
    @AppStorage("runAssistantAbilityLevel") private var abilityLevel: String = "run_walk"
    @AppStorage("runAssistantCurrentAveragePaceMinPerMile") private var currentAveragePaceMinPerMile: Double = 12.0
    @AppStorage("runAssistantPaceGoalMinPerMile") private var paceGoalMinPerMile: Double = 9.5
    @AppStorage("runAssistantDaysPerWeek") private var daysPerWeek: Int = 4
    @AppStorage("runAssistantLongRunWeekday") private var longRunWeekday: Int = 7
    @AppStorage("runAssistantReminderEnabled") private var reminderEnabled: Bool = false
    @AppStorage("runAssistantReminderHour") private var reminderHour: Int = 7
    @AppStorage("runAssistantReminderMinute") private var reminderMinute: Int = 0

    @State private var errorText: String?
    @State private var showProfileEditor: Bool = false

    private var profileBinding: Binding<RunAssistantProfile> {
        Binding<RunAssistantProfile>(
            get: {
                RunAssistantProfile(
                    goalFocus: goalFocus,
                    targetDistanceMiles: targetDistanceMiles,
                    abilityLevel: abilityLevel,
                    currentAveragePaceMinPerMile: currentAveragePaceMinPerMile,
                    paceGoalMinPerMile: paceGoalMinPerMile,
                    daysPerWeek: daysPerWeek,
                    longRunWeekday: longRunWeekday,
                    reminderEnabled: reminderEnabled,
                    reminderHour: reminderHour,
                    reminderMinute: reminderMinute
                )
            },
            set: { newValue in
                goalFocus = newValue.goalFocus
                targetDistanceMiles = newValue.targetDistanceMiles
                abilityLevel = newValue.abilityLevel
                currentAveragePaceMinPerMile = newValue.currentAveragePaceMinPerMile
                paceGoalMinPerMile = newValue.paceGoalMinPerMile
                daysPerWeek = newValue.daysPerWeek
                longRunWeekday = newValue.longRunWeekday
                reminderEnabled = newValue.reminderEnabled
                reminderHour = newValue.reminderHour
                reminderMinute = newValue.reminderMinute
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if didCompleteOnboarding {
                    RunAssistantDashboardView(
                        profile: profileBinding,
                        onStartRun: {
                            dismiss()
                            onStartRun()
                        },
                        onEditProfile: {
                            showProfileEditor = true
                        }
                    )
                } else {
                    RunAssistantOnboardingView(
                        profile: profileBinding,
                        onSelectTemplate: { template in
                            activateTemplate(template)
                        }
                    )
                }
            }
            .navigationTitle("Running Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Running Assistant", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
        .sheet(isPresented: $showProfileEditor) {
            RunAssistantProfileEditorView(
                profile: profileBinding,
                onSave: {
                    applyProfileEdits()
                }
            )
        }
        .appBackground(AppTheme.gradientRuns)
        .foregroundColor(AppTheme.textColor)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .tint(AppTheme.accentColor)
    }

    private func activateTemplate(_ template: RunPlanTemplateDescriptor) {
        let profile = profileBinding.wrappedValue
        let plan = RunAssistantService.shared.createPlan(
            from: template,
            profile: profile,
            startDate: Date(),
            context: modelContext
        )
        RunAssistantService.shared.setActivePlan(plan.id, context: modelContext)

        didCompleteOnboarding = true
    }

    private func applyProfileEdits() {
        guard let activePlan = RunAssistantService.shared.activePlan(context: modelContext) else { return }
        activePlan.profileSnapshotJSON = profileBinding.wrappedValue.asJSONString()
        activePlan.updatedAt = Date()
        try? modelContext.save()
        RunAssistantService.shared.setActivePlan(activePlan.id, context: modelContext)
    }
}
