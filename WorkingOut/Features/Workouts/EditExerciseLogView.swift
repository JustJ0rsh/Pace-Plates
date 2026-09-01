import SwiftUI
import SwiftData

struct EditExerciseLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let log: ExerciseLog
    let isNew: Bool

    // Strength fields
    @State private var repsText: String
    @State private var weightText: String
    @State private var weightUnit: String
    
    // Cardio fields
    @State private var durationMinutes: Int
    @State private var durationSeconds: Int
    @State private var distanceText: String
    @State private var distanceUnit: String
    @State private var caloriesText: String
    @State private var heartRateText: String
    
    // Notes field
    @State private var notesText: String
    // Isolation toggle for unilateral work
    @State private var isIsolated: Bool
    
    @State private var historyExerciseName: String? = nil

    @FocusState private var repsFocused: Bool
    @FocusState private var weightFocused: Bool
    @FocusState private var durationFocused: Bool
    @FocusState private var distanceFocused: Bool
    @FocusState private var notesFocused: Bool

    init(log: ExerciseLog, isNew: Bool = false) {
        self.log = log
        self.isNew = isNew
        
        // Initialize strength fields
        _repsText = State(initialValue: String(log.reps))
        _weightText = State(initialValue: String(format: "%.1f", log.weight))
        _weightUnit = State(initialValue: log.weightUnit)
        
        // Initialize cardio fields
        let totalSeconds = log.durationSeconds ?? 0
        _durationMinutes = State(initialValue: totalSeconds / 60)
        _durationSeconds = State(initialValue: totalSeconds % 60)
        _distanceText = State(initialValue: log.distance != nil ? String(format: "%.2f", log.distance!) : "")
        _distanceUnit = State(initialValue: log.distanceUnit ?? "mi")
        _caloriesText = State(initialValue: log.caloriesBurned != nil ? String(log.caloriesBurned!) : "")
        _heartRateText = State(initialValue: log.avgHeartRate != nil ? String(log.avgHeartRate!) : "")
        
        // Initialize notes field
        _notesText = State(initialValue: log.notes ?? "")
        _isIsolated = State(initialValue: log.isIsolated)
    }
    
    @AppStorage("weightUnit") private var preferredWeightUnit = "lbs"
    
    private func latestBodyWeight(preferredUnit: String) -> Double? {
        var fd = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 1
        if let entry = try? modelContext.fetch(fd).first {
            let kg = entry.weightUnit == "kg" ? entry.weight : (entry.weight / 2.20462)
            return preferredUnit == "kg" ? kg : kg * 2.20462
        }
        return nil
    }
    
    private func isCalisthenics(_ name: String) -> Bool {
        let lower = name.lowercased()
        let keywords = ["push-up", "push ups", "push-ups", "pull-up", "pull ups", "pull-ups", "chin-up", "chin ups", "dips", "plank", "bodyweight", "sit-up", "crunch", "burpee", "mountain climber", "pushups", "pullups"]
        if keywords.contains(where: { lower.contains($0) }) { return true }
        let direct = Set(["Push-Ups", "Knee Push-Ups", "Wall Push-Ups", "Assisted Pull-Ups", "Pull-Ups", "Plank", "Bodyweight Squats"]) 
        return direct.contains(name)
    }
    
    // Helper to detect if this is a cardio exercise
    // Now properly checks the exercise definition's muscle group = "Cardio"
    private var isCardioExercise: Bool {
        // First check if the exercise definition's muscle group is "Cardio"
        if let muscleGroup = log.exerciseDefinition?.muscleGroup, muscleGroup.lowercased() == "cardio" {
            return true
        }
        
        // If explicit type is set, respect that
        if log.exerciseType == "cardio" { return true }
        
        // Fallback to name-based detection only if no definition
        guard let raw = log.exerciseName, !raw.isEmpty, log.exerciseDefinition == nil else { 
            return log.exerciseType == "cardio" 
        }
        
        let name = raw.lowercased()
        // Broad cardio indicators
        let cardioTokens = ["run", "jog", "bike", "cycle", "swim", "elliptical", "cardio", "treadmill", "stair", "rowing", "rower", "erg", "ergometer", "concept2", "assault bike", "airdyne", "spin"]
        let looksCardio = cardioTokens.contains(where: { name.contains($0) })
        // Common strength "row" exercises that should NOT be treated as cardio
        let strengthRowTokens = [" row", "rows", "barbell row", "bent over row", "bent-over row", "pendlay row", "t-bar row", "dumbbell row", "one-arm row", "one arm row", "seated row", "cable row", "inverted row"]
        let isStrengthRow = strengthRowTokens.contains(where: { name.contains($0) }) && !name.contains("rowing") && !name.contains("rower")
        
        return looksCardio && !isStrengthRow
    }

    private var shouldShowIsolationControl: Bool {
        !isCardioExercise
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise Details") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.exerciseName ?? "Exercise")
                                .foregroundColor(AppTheme.textColor)
                            Text(isCardioExercise ? "Cardio" : "Strength")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let name = log.exerciseName, !name.isEmpty {
                            Button {
                                showHistoryForExercise(name: name)
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("History")
                        }
                    }
                }

                if isCardioExercise {
                    // Cardio fields
                    Section("Duration") {
                        HStack {
                            Text("Minutes")
                            Spacer()
                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(0..<120, id: \.self) { min in
                                    Text("\(min)").tag(min)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        HStack {
                            Text("Seconds")
                            Spacer()
                            Picker("Seconds", selection: $durationSeconds) {
                                ForEach(0..<60, id: \.self) { sec in
                                    Text("\(sec)").tag(sec)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    Section("Distance (Optional)") {
                        HStack {
                            Text("Distance")
                            Spacer()
                            TextField("0.00", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($distanceFocused)
                        }
                        
                        Picker("Unit", selection: $distanceUnit) {
                            Text("miles").tag("mi")
                            Text("km").tag("km")
                        }
                    }
                    
                    Section("Additional (Optional)") {
                        HStack {
                            Text("Calories")
                            Spacer()
                            TextField("0", text: $caloriesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("Avg Heart Rate")
                            Spacer()
                            TextField("0", text: $heartRateText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } else {
                    // Strength fields
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

                        if shouldShowIsolationControl {
                            Button {
                                isIsolated.toggle()
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: isIsolated ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isIsolated ? .green : .secondary)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(isIsolated ? "Double reps active (x2)" : "Double reps (x2)")
                                            .foregroundColor(AppTheme.textColor)
                                        Text("Use this for unilateral or alternating movements so each rep counts both sides (example: 10 reps logs as 20 total).")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if isIsolated {
                                        Text("x2")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppTheme.secondaryBackgroundColor.opacity(0.8))
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Notes section (shared for both cardio and strength)
                Section("Notes (Optional)") {
                    TextEditor(text: $notesText)
                        .frame(minHeight: 80)
                        .focused($notesFocused)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .background {
                AppTheme.gradientWorkouts
                    .ignoresSafeArea()
            }
            // Removed .ignoresSafeArea(.keyboard) to allow view to resize
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
            // Reps/weight/distance use number pads, which have no return key.
            .keyboardToolbar {
                repsFocused = false
                weightFocused = false
                durationFocused = false
                distanceFocused = false
                notesFocused = false
                dismissKeyboard()
            }
            .onAppear {
                if isCardioExercise {
                    // Focus on duration for cardio
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        durationFocused = false  // Don't auto-focus for picker-based fields
                    }
                } else {
                    repsFocused = true
                }
                // Auto-fill bodyweight for calisthenics sets with empty weight
                if !isCardioExercise, (Double(weightText) ?? 0) <= 0, let name = log.exerciseName, isCalisthenics(name) {
                    if let bw = latestBodyWeight(preferredUnit: preferredWeightUnit) {
                        weightText = String(format: "%.1f", bw)
                        weightUnit = preferredWeightUnit
                    }
                }
            }
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
                                                HStack(spacing: 8) {
                                                    Text("Set \(set.setNumber)")
                                                        .foregroundColor(AppTheme.textColor)
                                                    Spacer()
                                                    Text("\(set.displayRepsText) @ \(weightString) \(set.weightUnit)")
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
                durationFocused = false
                distanceFocused = false
                notesFocused = false
                dismissKeyboard()
                if didCancelExplicitly {
                    // Draft fields are local state. Explicit cancellation of an
                    // existing set must leave the persisted model untouched.
                    // A newly inserted set still needs to be removed.
                    if isNew {
                        modelContext.delete(log)
                        _ = PersistenceSave.commit(modelContext, action: "cancel new set")
                    }
                } else if isNew && !didSaveExplicitly {
                    // User canceled; remove the newly created set
                    modelContext.delete(log)
                    _ = PersistenceSave.commit(modelContext, action: "save changes")
                } else if !didSaveExplicitly {
                    // Persist current edits when dismissed without tapping Done
                    if isCardioExercise {
                        log.exerciseType = "cardio"
                        log.durationSeconds = (durationMinutes * 60) + durationSeconds
                        log.distance = Double(distanceText)
                        log.distanceUnit = distanceUnit
                        log.caloriesBurned = Int(caloriesText)
                        log.avgHeartRate = Int(heartRateText)
                        log.reps = 1
                        log.weight = 0
                        
                        // Delete empty cardio sets
                        if log.durationSeconds ?? 0 == 0 {
                            modelContext.delete(log)
                        }
                    } else {
                        log.exerciseType = "strength"
                        let reps = Int(repsText) ?? log.reps
                        let weight = Double(weightText) ?? log.weight
                        log.reps = reps
                        log.weight = weight
                        log.weightUnit = weightUnit
                        
                        // Delete empty strength sets
                        if reps == 0 {
                            modelContext.delete(log)
                        }
                    }
                    
                    // Persist isolation choice only for strength work
                    log.isIsolated = isCardioExercise ? false : isIsolated
                    
                    // Save notes
                    log.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText
                    
                    _ = PersistenceSave.commit(modelContext, action: "save changes")
                }
            }
        }
    }

    private func saveAndDismiss() {
        didSaveExplicitly = true
        
        if isCardioExercise {
            // Save cardio data
            log.exerciseType = "cardio"
            log.durationSeconds = (durationMinutes * 60) + durationSeconds
            log.distance = Double(distanceText)
            log.distanceUnit = distanceUnit
            log.caloriesBurned = Int(caloriesText)
            log.avgHeartRate = Int(heartRateText)
            // Set default values for strength fields
            log.reps = 1
            log.weight = 0
            
            // Delete empty cardio sets (no duration = meaningless)
            if log.durationSeconds ?? 0 == 0 {
                modelContext.delete(log)
                _ = PersistenceSave.commit(modelContext, action: "save changes")
                repsFocused = false
                weightFocused = false
                durationFocused = false
                distanceFocused = false
                notesFocused = false
                dismissKeyboard()
                dismiss()
                return
            }
        } else {
            // Save strength data
            log.exerciseType = "strength"
            let reps = Int(repsText) ?? log.reps
            let weight = Double(weightText) ?? log.weight
            log.reps = reps
            log.weight = weight
            log.weightUnit = weightUnit
            
            // Delete empty strength sets (no reps = meaningless)
            if reps == 0 {
                modelContext.delete(log)
                _ = PersistenceSave.commit(modelContext, action: "save changes")
                repsFocused = false
                weightFocused = false
                durationFocused = false
                distanceFocused = false
                notesFocused = false
                dismissKeyboard()
                dismiss()
                return
            }
        }
        
        // Save notes (store nil if empty to save space)
        log.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText
        log.isIsolated = isCardioExercise ? false : isIsolated
        
        _ = PersistenceSave.commit(modelContext, action: "save changes")
        repsFocused = false
        weightFocused = false
        durationFocused = false
        distanceFocused = false
        notesFocused = false
        dismissKeyboard()
        dismiss()
    }

    @State private var didSaveExplicitly: Bool = false
    @State private var didCancelExplicitly: Bool = false

    private func cancelAndDismiss() {
        didCancelExplicitly = true
        repsFocused = false
        weightFocused = false
        durationFocused = false
        distanceFocused = false
        notesFocused = false
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
