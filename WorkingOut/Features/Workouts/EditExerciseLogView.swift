import SwiftUI
import SwiftData

struct EditExerciseLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let log: ExerciseLog
    let isNew: Bool

    @State private var repsText: String
    @State private var weightText: String
    @State private var weightUnit: String
    @State private var historyExerciseName: String? = nil

    @FocusState private var repsFocused: Bool
    @FocusState private var weightFocused: Bool

    init(log: ExerciseLog, isNew: Bool = false) {
        self.log = log
        self.isNew = isNew
        _repsText = State(initialValue: String(log.reps))
        _weightText = State(initialValue: String(format: "%.1f", log.weight))
        _weightUnit = State(initialValue: log.weightUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Details") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.exerciseName ?? "Exercise")
                                .foregroundColor(AppTheme.textColor)
                            Text("")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let name = log.exerciseName, !name.isEmpty {
                            Button {
                                // Present a lightweight history sheet for this exercise
                                showHistoryForExercise(name: name)
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("History")
                        }
                    }
                }

                Section("Set Details") {
                    HStack {
                        Text("Reps")
                        Spacer()
                        TextField("Reps", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($repsFocused)
                            .onChange(of: repsFocused) { oldValue, newValue in
                                if newValue { selectAllText() }
                            }
                            .onTapGesture { selectAllText() }
                    }

                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($weightFocused)
                            .onChange(of: weightFocused) { oldValue, newValue in
                                if newValue { selectAllText() }
                            }
                            .onTapGesture { selectAllText() }
                    }

                    Picker("Unit", selection: $weightUnit) {
                        Text("lbs").tag("lbs")
                        Text("kg").tag("kg")
                    }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelAndDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveAndDismiss() }
                }
            }
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .appBackground(AppTheme.gradientWorkouts)
            .ignoresSafeArea(.keyboard)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
            .onAppear { weightFocused = true }
            .sheet(isPresented: Binding(get: { historyExerciseName != nil }, set: { if !$0 { historyExerciseName = nil } })) {
                if let name = historyExerciseName {
                    VStack(spacing: 16) {
                        Text("History for \(name)")
                            .font(.title2)
                            .bold()
                            .foregroundColor(AppTheme.textColor)
                            .padding(.top)
                        ScrollView {
                            VStack(spacing: 12) {
                                let recent: [(date: Date, sets: [ExerciseLog])] = lastThreeWorkouts(forExerciseName: name)

                                if recent.isEmpty {
                                    ContentUnavailableView(
                                        "No History recorded yet",
                                        systemImage: "clock.arrow.circlepath",
                                        description: Text("Start logging sets to see history here.")
                                    )
                                    .padding(.top, 20)
                                } else {
                                    ForEach(Array(recent.enumerated()), id: \.offset) { _, workout in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(workout.date, style: .date)
                                                .font(.headline)
                                                .foregroundColor(AppTheme.textColor)
                                            ForEach(workout.sets, id: \.id) { set in
                                                let weightString = String(format: "%.1f", set.weight)
                                                HStack {
                                                    Text("Set \(set.setNumber)")
                                                        .foregroundColor(AppTheme.textColor)
                                                    Spacer()
                                                    Text("\(set.reps) reps @ \(weightString) \(set.weightUnit)")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .padding()
                                        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryBackgroundColor))
                                    }
                                }
                            }
                        }
                        Button("Close") { historyExerciseName = nil }
                        .padding(.bottom)
                        .foregroundColor(AppTheme.accentColor)
                    }
                    .appBackground(AppTheme.gradientWorkouts)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .onDisappear {
                // Clear focus and dismiss keyboard before saving edits
                repsFocused = false
                weightFocused = false
                dismissKeyboard()
                if isNew && !didSaveExplicitly {
                    // User canceled; remove the newly created set
                    modelContext.delete(log)
                    try? modelContext.save()
                } else if !didSaveExplicitly {
                    // Persist current edits when dismissed without tapping Done
                    let reps = Int(repsText) ?? log.reps
                    let weight = Double(weightText) ?? log.weight
                    log.reps = reps
                    log.weight = weight
                    log.weightUnit = weightUnit
                    try? modelContext.save()
                }
            }
        }
    }

    private func saveAndDismiss() {
        didSaveExplicitly = true
        let reps = Int(repsText) ?? log.reps
        let weight = Double(weightText) ?? log.weight
        log.reps = reps
        log.weight = weight
        log.weightUnit = weightUnit
        try? modelContext.save()
        repsFocused = false
        weightFocused = false
        dismissKeyboard()
        dismiss()
    }

    @State private var didSaveExplicitly: Bool = false

    private func cancelAndDismiss() {
        didSaveExplicitly = false
        repsFocused = false
        weightFocused = false
        dismissKeyboard()
        dismiss()
    }

    private func selectAllText() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        #endif
    }

    private func showHistoryForExercise(name: String) { historyExerciseName = name }

    private func lastThreeWorkouts(forExerciseName name: String) -> [(date: Date, sets: [ExerciseLog])] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        var result: [(Date, [ExerciseLog])] = []
        for s in sessions {
            // Filter sets for this exercise, excluding placeholder entries (0 reps and 0 weight)
            let sets = (s.exerciseLogs ?? [])
                .filter { ($0.exerciseName ?? "") == name }
                .filter { !($0.reps == 0 && $0.weight == 0) }
            if !sets.isEmpty {
                result.append((s.date, sets.sorted { $0.setNumber < $1.setNumber }))
            }
            if result.count >= 3 { break }
        }
        return result
    }
}

#Preview {
    EditExerciseLogView(log: ExerciseLog(reps: 10, weight: 100, setNumber: 1))
        .modelContainer(PersistenceController.preview.container)
}
