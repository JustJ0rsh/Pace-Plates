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
    private let muscleGroups = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Cardio"]
    @State private var historyExerciseName: String? = nil

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


    var body: some View {
        NavigationStack {
            List {
                // Iterate over sorted muscle groups
                ForEach(sortedMuscleGroups, id: \.self) { group in
                    Section(header: Text(group).foregroundColor(AppTheme.textColor)) {
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
                                        .foregroundStyle(.blue)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.secondaryBackgroundColor)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    historyExerciseName = exercise.name
                                } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                                .tint(.teal)
                                if exercise.isUserDefined {
                                    Button(role: .destructive) {
                                        deleteExerciseDefinition(exercise)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .appBackground(AppTheme.gradientWorkouts)
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Workouts for \(name)")
                        .font(.headline)
                    let recent = lastThreeWorkouts(forExerciseName: name)
                    if recent.isEmpty {
                        Text("No history yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                ForEach(item.sets, id: \.id) { set in
                                    Text("Set \(set.setNumber): \(set.reps) reps @ \(String(format: "%.1f", set.weight)) \(set.weightUnit)")
                                }
                            }
                            .padding(10)
                            .background(AppTheme.secondaryBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .presentationDetents([.fraction(0.35), .medium])
                .appBackground(AppTheme.gradientWorkouts)
                .foregroundColor(AppTheme.textColor)
            }
        }
    }

    // MARK: - Delete + History helpers

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
        try? modelContext.save()
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

        let log = ExerciseLog(
            reps: 0, // Default values, user edits later
            weight: 0,
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
        try? modelContext.save()
        
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
        // try? modelContext.save() // Save potentially here or defer

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
