import SwiftUI
import SwiftData

struct AddExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor<ExerciseDefinition>(\.name)]) private var exerciseDefinitions: [ExerciseDefinition] // Added sort descriptor

    let onAdd: ((ExerciseLog) -> Void)?
    
    let workoutSession: WorkoutSession
    @State private var searchText = ""
    @State private var showingAddCustomExercise = false
    @State private var newExerciseName = ""
    @State private var selectedMuscleGroup = "Chest"
    // Include Biceps/Triceps sub-groups so users can file arms more precisely
    private let muscleGroups = ["Chest", "Back", "Legs", "Shoulders", "Biceps", "Triceps", "Forearms", "Core", "Cardio"]
    @State private var historyExerciseName: String? = nil
    @State private var editingExercise: ExerciseDefinition? = nil
    @State private var editingExerciseName: String = ""
    @State private var editingExerciseMuscleGroup: String = ""
    @State private var expandedMuscleGroups: Set<String> = []

    init(workoutSession: WorkoutSession, onAdd: ((ExerciseLog) -> Void)? = nil) {
        self.workoutSession = workoutSession
        self.onAdd = onAdd
    }

    var filteredExercises: [ExerciseDefinition] {
        let sortedDefinitions = exerciseDefinitions // Use the already sorted query result

        if searchText.isEmpty {
            return sortedDefinitions
        }
        return sortedDefinitions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // Group exercises by muscle group for the list
    var groupedExercises: [String: [ExerciseDefinition]] {
        Dictionary(grouping: filteredExercises, by: { $0.muscleGroup })
    }

    // Get sorted muscle group keys
    var sortedMuscleGroups: [String] {
        groupedExercises.keys.sorted()
    }

    private func expansionBinding(for group: String) -> Binding<Bool> {
        Binding(
            get: {
                if !searchText.isEmpty { return true }
                return expandedMuscleGroups.contains(group)
            },
            set: { isExpanded in
                if isExpanded {
                    expandedMuscleGroups.insert(group)
                } else {
                    expandedMuscleGroups.remove(group)
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // Iterate over sorted muscle groups
                ForEach(sortedMuscleGroups, id: \.self) { group in
                    DisclosureGroup(isExpanded: expansionBinding(for: group)) {
                        // Iterate over exercises within the group
                        ForEach(groupedExercises[group] ?? []) { exercise in
                            Button {
                                addExercise(exercise)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(exercise.name)
                                            .font(.headline)
                                        Text(exercise.muscleGroup)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(AppTheme.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    historyExerciseName = exercise.name
                                } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                                .tint(AppTheme.accentColor)
                                // Allow editing category for all exercises to prevent data loss
                                Button {
                                    editingExercise = exercise
                                    editingExerciseName = exercise.name
                                    editingExerciseMuscleGroup = exercise.muscleGroup
                                } label: { Label("Edit Category", systemImage: "pencil") }
                                .tint(AppTheme.accentColor)
                                if exercise.isUserDefined {
                                    Button(role: .destructive) {
                                        deleteExerciseDefinition(exercise)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    } label: {
                        Text(group)
                            .font(.headline)
                            .foregroundColor(AppTheme.textColor)
                    }
                    .listRowBackground(AppTheme.secondaryBackgroundColor)
                }
            }
            .listStyle(.plain)
            .appBackground(AppTheme.gradientWorkouts)
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddCustomExercise = true
                    } label: {
                        Label("Add Custom", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCustomExercise) {
                // Sheet for adding custom exercise
                NavigationStack {
                    Form {
                        TextField("Exercise Name", text: $newExerciseName)

                        Picker("Muscle Group", selection: $selectedMuscleGroup) {
                            ForEach(muscleGroups, id: \.self) { group in
                                Text(group).tag(group)
                            }
                        }
                    }
                    .appBackground(AppTheme.gradientWorkouts)
                    .scrollContentBackground(.hidden)
                    .navigationTitle("New Custom Exercise")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddCustomExercise = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addCustomExercise()
                            }
                            .disabled(newExerciseName.isEmpty)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { historyExerciseName != nil }, set: { if !$0 { historyExerciseName = nil } })) {
            if let name = historyExerciseName {
                ZStack {
                    AppTheme.gradientWorkouts.ignoresSafeArea()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Workouts for \(name)")
                            .font(.headline)
                            .padding(.top, 16)
                        
                        let recent = lastThreeWorkouts(forExerciseName: name)
                        if recent.isEmpty {
                            ContentUnavailableView(
                                "No History",
                                systemImage: "clock.arrow.circlepath",
                                description: Text("You haven't logged this exercise yet.")
                            )
                        } else {
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(Array(recent.enumerated()), id: \.offset) { _, item in
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            
                                            ForEach(item.sets, id: \.id) { set in
                                                HStack {
                                                    Text("Set \(set.setNumber)")
                                                        .fontWeight(.medium)
                                                    Spacer()
                                                Text("\(set.displayRepsText)")
                                                    Text("@")
                                                        .foregroundStyle(.secondary)
                                                    Text("\(String(format: "%.1f", set.weight)) \(set.weightUnit)")
                                                }
                                                .font(.callout)
                                                .padding(.vertical, 2)
                                            }
                                        }
                                        .padding()
                                        .background(AppTheme.secondaryBackgroundColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                                .padding(.bottom, 16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .presentationDetents([.fraction(0.45), .medium, .large])
                .presentationDragIndicator(.visible)
                .foregroundColor(AppTheme.textColor)
            }
        }
        .sheet(isPresented: Binding(get: { editingExercise != nil }, set: { if !$0 { editingExercise = nil } })) {
            // Sheet for editing exercise category
            NavigationStack {
                Form {
                    Section("Exercise Name") {
                        Text(editingExerciseName)
                            .foregroundColor(AppTheme.textColor)
                    }
                    
                    Section("Category") {
                        Picker("Muscle Group", selection: $editingExerciseMuscleGroup) {
                            ForEach(muscleGroups, id: \.self) { group in
                                Text(group).tag(group)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    if editingExercise != nil {
                        Section {
                            Text("Changing the category will update this exercise for all past and future workouts. No data will be lost.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .appBackground(AppTheme.gradientWorkouts)
                .scrollContentBackground(.hidden)
                .navigationTitle("Edit Category")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            editingExercise = nil
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveExerciseEdit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Delete + History helpers

    private func saveExerciseEdit() {
        guard let exercise = editingExercise else { return }
        
        // Update the exercise definition's muscle group
        // This automatically updates all logs that reference this exercise
        exercise.muscleGroup = editingExerciseMuscleGroup
        
        _ = PersistenceSave.commit(modelContext, action: "save changes")
        
        // Close the sheet
        editingExercise = nil
    }

    private func deleteExerciseDefinition(_ exercise: ExerciseDefinition) {
        // If currently showing history for this exercise, close it first
        if historyExerciseName == exercise.name { historyExerciseName = nil }

        // Detach all logs that reference this exercise to avoid accessing
        // an invalidated ExerciseDefinition instance in other views
        if let exerciseId = exercise.id as UUID? {
            let predicate = #Predicate<ExerciseLog> { $0.exerciseDefinition?.id == exerciseId }
            let descriptor = FetchDescriptor<ExerciseLog>(predicate: predicate)
            if let logs = try? modelContext.fetch(descriptor) {
                for log in logs { log.exerciseDefinition = nil; log.exerciseName = log.exerciseName ?? exercise.name }
            }
        }

        modelContext.delete(exercise)
        _ = PersistenceSave.commit(modelContext, action: "save changes")
    }

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

    private func addExercise(_ exercise: ExerciseDefinition) {
        let allLogs = workoutSession.exerciseLogs ?? []
        
        // Find the next set number for this specific exercise within the session
        let nextSetNumber = (allLogs
                                .filter { ($0.exerciseName ?? "") == exercise.name }
                                .map { $0.setNumber }
                                .max() ?? 0) + 1
        
        // Find the next exercise order (max order + 1, or use the exercise's current order if it already exists)
        let exerciseOrder: Int
        if let existingLog = allLogs.first(where: { ($0.exerciseName ?? "") == exercise.name }) {
            // Exercise already exists in this workout, use its existing order
            exerciseOrder = existingLog.exerciseOrder
        } else {
            // New exercise, assign next available order
            exerciseOrder = (allLogs.map { $0.exerciseOrder }.max() ?? -1) + 1
        }

        var defaultWeight: Double = 0
        if isCalisthenics(exercise.name), let bw = latestBodyWeight(preferredUnit: preferredWeightUnit) {
            defaultWeight = bw
        }

        let log = ExerciseLog(
            reps: 0, // Default values, user edits later
            weight: defaultWeight,
            weightUnit: preferredWeightUnit,
            setNumber: nextSetNumber,
            exerciseName: exercise.name,
            exerciseOrder: exerciseOrder
        )
        log.exerciseDefinition = exercise
        log.workoutSession = workoutSession // Establish the inverse relationship
        if var arr = workoutSession.exerciseLogs { arr.append(log); workoutSession.exerciseLogs = arr } else { workoutSession.exerciseLogs = [log] }

        // No need to insert log separately if relationship is set up correctly
        // modelContext.insert(log)
        
        // Saving the context might be better done when the user confirms the session is complete,
        // but saving here ensures the log is persisted immediately after adding.
        _ = PersistenceSave.commit(modelContext, action: "save changes")
        
        if let onAdd { onAdd(log) }
        
        // Consider not dismissing automatically, allowing user to add multiple exercises?
        // For now, keeping the original dismiss logic.
        dismiss()
    }

    private func addCustomExercise() {
        let newExercise = ExerciseDefinition(
            name: newExerciseName,
            muscleGroup: selectedMuscleGroup,
            isUserDefined: true
        )
        modelContext.insert(newExercise)
        // It's generally better to save changes together if possible
        // _ = PersistenceSave.commit(modelContext, action: "save changes") // Save potentially here or defer

        // Add the newly created exercise to the workout
        // Wait for save to complete or handle potential errors?
        // For simplicity, adding immediately.
        addExercise(newExercise) 
        
        // Reset sheet state
        newExerciseName = ""
        selectedMuscleGroup = "Chest"
        // showingAddCustomExercise = false // Dismissal is handled by addExercise()
    }
} 
