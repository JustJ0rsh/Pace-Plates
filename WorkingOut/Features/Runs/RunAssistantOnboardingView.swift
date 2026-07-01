import SwiftUI

struct RunAssistantOnboardingView: View {
    @Binding var profile: RunAssistantProfile
    let onSelectTemplate: (RunPlanTemplateDescriptor) -> Void

    @State private var step: Int = 0
    @State private var showAllPlans: Bool = false

    private let totalSteps = 6

    private var recommended: [RunPlanTemplateDescriptor] {
        RunAssistantService.shared.recommendedTemplates(for: profile)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))

                Text(stepTitle)
                    .font(.title3.bold())

                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryTextColor)

                Group {
                    switch step {
                    case 0: goalStep
                    case 1: targetStep
                    case 2: abilityStep
                    case 3: daysStep
                    case 4: scheduleStep
                    default: recommendationStep
                    }
                }

                if step < totalSteps - 1 {
                    HStack {
                        if step > 0 {
                            Button("Back") { step -= 1 }
                                .buttonStyle(.bordered)
                        }
                        Spacer()
                        Button("Next") { step += 1 }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "What do you want to improve?"
        case 1: return "What distance are you targeting?"
        case 2: return "What is your current running ability?"
        case 3: return "How many running days per week?"
        case 4: return "Pick your long-run day and reminders"
        default: return "Choose your recommended plan"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case 0: return "Choose endurance, speed, or a balanced mix."
        case 1: return "We will adapt the plan around this target."
        case 2: return "This tunes your starting volume and pace."
        case 3: return "We will map sessions to this weekly availability."
        case 4: return "Optional reminders can keep you consistent."
        default: return "Top picks first. You can expand to all 15 built-in plans."
        }
    }

    private var goalStep: some View {
        optionGrid(
            options: [
                ("endurance", "Build Endurance"),
                ("speed", "Get Faster"),
                ("hybrid", "Both")
            ],
            selection: profile.goalFocus,
            select: { profile.goalFocus = $0 }
        )
    }

    private var targetStep: some View {
        optionGrid(
            options: [
                ("1", "1 Mile"),
                ("2", "2 Miles"),
                ("3", "3 Miles")
            ],
            selection: String(Int(profile.targetDistanceMiles)),
            select: { value in
                profile.targetDistanceMiles = Double(value) ?? 1
            }
        )
    }

    private var abilityStep: some View {
        optionGrid(
            options: [
                ("brand_new", "Brand New"),
                ("run_walk", "Run/Walk"),
                ("continuous", "Continuous Runner")
            ],
            selection: profile.abilityLevel,
            select: { profile.abilityLevel = $0 }
        )
    }

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick how many days you can run each week.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)

            optionGrid(
                options: [
                    ("3", "3 Days"),
                    ("4", "4 Days"),
                    ("5", "5 Days"),
                    ("6", "6 Days")
                ],
                selection: String(profile.daysPerWeek),
                select: { profile.daysPerWeek = Int($0) ?? 4 }
            )
        }
    }

    private var scheduleStep: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Average Pace")
                    .font(.subheadline.bold())
                HStack {
                    Text("Current Baseline")
                    Spacer()
                    Text(formatPace(profile.currentAveragePaceMinPerMile))
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .monospacedDigit()
                }

                Stepper(value: $profile.currentAveragePaceMinPerMile, in: 5.0...20.0, step: 0.1) {
                    Text("Used as your plan starting pace")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pace Goal")
                    .font(.subheadline.bold())
                HStack {
                    Text("Target Pace")
                    Spacer()
                    Text(formatPace(profile.paceGoalMinPerMile))
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .monospacedDigit()
                }

                Stepper(value: $profile.paceGoalMinPerMile, in: 5.0...20.0, step: 0.1) {
                    Text("Adjust by 0.1 min/mi")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
            .padding(.bottom, 4)

            Picker("Long run day", selection: $profile.longRunWeekday) {
                Text("Sunday").tag(1)
                Text("Monday").tag(2)
                Text("Tuesday").tag(3)
                Text("Wednesday").tag(4)
                Text("Thursday").tag(5)
                Text("Friday").tag(6)
                Text("Saturday").tag(7)
            }
            .pickerStyle(.menu)

            Toggle("Enable plan reminders", isOn: $profile.reminderEnabled)

            if profile.reminderEnabled {
                HStack {
                    Text("Reminder Time")
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                Calendar.current.date(bySettingHour: profile.reminderHour, minute: profile.reminderMinute, second: 0, of: Date()) ?? Date()
                            },
                            set: { newValue in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                profile.reminderHour = comps.hour ?? 7
                                profile.reminderMinute = comps.minute ?? 0
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }
        }
        .padding()
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recommendationStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(showAllPlans ? recommended : Array(recommended.prefix(3))) { template in
                Button {
                    onSelectTemplate(template)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                        Text("\(template.durationWeeks) weeks • \(template.primaryGoal.capitalized)")
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

            Button(showAllPlans ? "Show Top 3" : "View All Plans") {
                showAllPlans.toggle()
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)
        }
    }

    private func optionGrid(
        options: [(String, String)],
        selection: String,
        select: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.0) { option in
                Button {
                    select(option.0)
                } label: {
                    HStack {
                        Text(option.1)
                        Spacer()
                        if selection == option.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accentColor)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.secondaryBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func formatPace(_ minPerMile: Double) -> String {
        let mins = Int(minPerMile)
        let secs = Int((minPerMile - Double(mins)) * 60)
        return String(format: "%d:%02d /mi", mins, secs)
    }
}
