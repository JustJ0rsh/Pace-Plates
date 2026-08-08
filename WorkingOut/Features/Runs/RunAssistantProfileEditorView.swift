import SwiftUI

struct RunAssistantProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var profile: RunAssistantProfile
    @State private var draft: RunAssistantProfile
    let onSave: () -> Void

    init(profile: Binding<RunAssistantProfile>, onSave: @escaping () -> Void) {
        _profile = profile
        _draft = State(initialValue: profile.wrappedValue)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Focus", selection: $draft.goalFocus) {
                        Text("Endurance").tag("endurance")
                        Text("Speed").tag("speed")
                        Text("Hybrid").tag("hybrid")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Target") {
                    Picker("Distance", selection: $draft.targetDistanceMiles) {
                        Text("1 Mile").tag(1.0)
                        Text("2 Miles").tag(2.0)
                        Text("3 Miles").tag(3.0)
                    }
                    .pickerStyle(.segmented)

                    Picker("Ability", selection: $draft.abilityLevel) {
                        Text("Brand New").tag("brand_new")
                        Text("Run/Walk").tag("run_walk")
                        Text("Continuous").tag("continuous")
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Running Days Per Week")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Running Days Per Week", selection: $draft.daysPerWeek) {
                            Text("3").tag(3)
                            Text("4").tag(4)
                            Text("5").tag(5)
                            Text("6").tag(6)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text("Current Average Pace")
                        Spacer()
                        Text(formatPace(draft.currentAveragePaceMinPerMile))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper(value: $draft.currentAveragePaceMinPerMile, in: 5.0...20.0, step: 0.1) {
                        Text("Adjust Current Average Pace")
                    }

                    HStack {
                        Text("Pace Goal")
                        Spacer()
                        Text(formatPace(draft.paceGoalMinPerMile))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Stepper(value: $draft.paceGoalMinPerMile, in: 5.0...20.0, step: 0.1) {
                        Text("Adjust Pace Goal")
                    }
                }

                Section("Schedule") {
                    Picker("Long Run Day", selection: $draft.longRunWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }

                    Toggle("Enable reminders", isOn: $draft.reminderEnabled)

                    if draft.reminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: Binding(
                                get: {
                                    Calendar.current.date(bySettingHour: draft.reminderHour, minute: draft.reminderMinute, second: 0, of: Date()) ?? Date()
                                },
                                set: { newValue in
                                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                    draft.reminderHour = comps.hour ?? 7
                                    draft.reminderMinute = comps.minute ?? 0
                                }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile = draft
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatPace(_ minPerMile: Double) -> String {
        let mins = Int(minPerMile)
        let secs = Int((minPerMile - Double(mins)) * 60)
        return String(format: "%d:%02d /mi", mins, secs)
    }
}
