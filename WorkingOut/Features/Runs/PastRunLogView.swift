import SwiftData
import SwiftUI

struct PastRunLogView: View {
    private enum Activity: String, CaseIterable, Identifiable {
        case running
        case walking
        case hiking
        case cycling
        case rowing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .running: return "Run"
            case .walking: return "Walk"
            case .hiking: return "Hike"
            case .cycling: return "Cycle"
            case .rowing: return "Row"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("distanceUnit") private var preferredDistanceUnit: String = "mi"

    @State private var activity: Activity = .running
    @State private var date: Date = Date()
    @State private var distance: Double?
    @State private var distanceUnit: String = "mi"
    @State private var hours: Int = 0
    @State private var minutes: Int = 30
    @State private var calories: Double?
    @State private var notes: String = ""
    @State private var saveErrorMessage: String? = nil
    @FocusState private var distanceFocused: Bool

    private var duration: TimeInterval {
        TimeInterval((hours * 60 + minutes) * 60)
    }

    private var isInputValid: Bool {
        (distance ?? 0) > 0 && duration > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $activity) {
                        ForEach(Activity.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0.0", value: $distance, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($distanceFocused)
                        Picker("Unit", selection: $distanceUnit) {
                            Text("mi").tag("mi")
                            Text("km").tag("km")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }

                    Stepper("Hours: \(hours)", value: $hours, in: 0...24)
                    Stepper("Minutes: \(minutes)", value: $minutes, in: 0...59)
                }

                Section("Optional") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("kcal", value: $calories, format: .number.precision(.fractionLength(0...0)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .appBackground(AppTheme.gradientRuns)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // Distance and calories use the decimal pad, which has no return key.
            .keyboardToolbar {
                distanceFocused = false
                dismissKeyboard()
            }
            .navigationTitle("Log Past Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRun()
                    }
                    .disabled(!isInputValid)
                }
            }
            .onAppear {
                distanceUnit = UnitConverter.canonicalDistanceUnit(preferredDistanceUnit)
                distanceFocused = true
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    saveErrorMessage = nil
                }
            } message: {
                Text(saveErrorMessage ?? "Couldn’t save your run. Please try again.")
            }
        }
    }

    private func saveRun() {
        guard let distance, isInputValid else { return }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = RunningSession(
            date: date,
            distance: distance,
            distanceUnit: distanceUnit,
            duration: duration,
            calories: (calories ?? 0) > 0 ? calories : nil,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            locations: nil,
            healthWorkoutUUID: nil,
            activityType: activity.rawValue
        )
        modelContext.insert(session)

        if PersistenceSave.commit(
            modelContext,
            action: "log past run",
            onFailure: { message in saveErrorMessage = message }
        ) {
            Haptics.notify(.success)
            dismiss()
        } else {
            Haptics.notify(.error)
            modelContext.delete(session)
        }
    }
}
