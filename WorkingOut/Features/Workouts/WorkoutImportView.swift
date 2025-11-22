import SwiftUI
import SwiftData

struct WorkoutImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let sharedSession: SharedWorkoutSession
    
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Import Workout")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(sharedSession.title)
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                        
                        if let notes = sharedSession.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    .padding(.top)
                    
                    // Exercises Preview
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(sharedSession.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(exercise.name)
                                    .font(.headline)
                                
                                ForEach(exercise.sets) { set in
                                    HStack {
                                        Text("Set \(set.setNumber)")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 50, alignment: .leading)
                                        
                                        if exercise.type == "cardio" {
                                            if let duration = set.durationSeconds {
                                                Text("\(duration / 60):\(String(format: "%02d", duration % 60))")
                                            }
                                            if let distance = set.distance, let unit = set.distanceUnit {
                                                Text("\(String(format: "%.2f", distance)) \(unit)")
                                            }
                                        } else {
                                            Text("\(set.reps) reps @ \(String(format: "%.1f", set.weight)) \(set.weightUnit)")
                                        }
                                    }
                                    .font(.subheadline)
                                }
                            }
                            .padding()
                            .background(AppTheme.secondaryBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                    
                    Spacer()
                        .frame(height: 40)
                }
            }
            .background(AppTheme.backgroundColor.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAsTemplate()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save as Template")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error Saving", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveError ?? "Unknown error")
            }
        }
    }
    
    private func saveAsTemplate() {
        isSaving = true
        
        Task {
            do {
                // Create a new WorkoutTemplate from the shared session
                let newTemplate = WorkoutTemplate(
                    title: sharedSession.title,
                    notes: sharedSession.notes
                )
                
                modelContext.insert(newTemplate)
                
                // Add exercises to the template
                for sharedExercise in sharedSession.exercises {
                    // Find or create ExerciseDefinition
                    // Ideally we try to match by name, or create a new one if it doesn't exist
                    _ = try await findOrCreateExerciseDefinition(name: sharedExercise.name, type: sharedExercise.type, muscleGroup: sharedExercise.muscleGroup)
                    
                    // Prepare notes, potentially adding cardio info
                    var notes = sharedExercise.sets.first?.notes
                    if sharedExercise.type == "cardio", let firstSet = sharedExercise.sets.first {
                        var cardioInfo: [String] = []
                        if let duration = firstSet.durationSeconds {
                            cardioInfo.append("Duration: \(duration / 60)m")
                        }
                        if let distance = firstSet.distance, let unit = firstSet.distanceUnit {
                            cardioInfo.append("Distance: \(distance) \(unit)")
                        }
                        if !cardioInfo.isEmpty {
                            let info = cardioInfo.joined(separator: ", ")
                            notes = notes == nil ? info : "\(notes!) (\(info))"
                        }
                    }

                    let templateExercise = TemplateExercise(
                        name: sharedExercise.name,
                        order: sharedExercise.order,
                        sets: sharedExercise.sets.count,
                        reps: sharedExercise.sets.first?.reps ?? 0,
                        suggestedWeight: sharedExercise.sets.first?.weight,
                        weightUnit: sharedExercise.sets.first?.weightUnit ?? "lbs",
                        notes: notes
                    )
                    // templateExercise.exerciseDefinition = definition // Not supported in TemplateExercise model
                    templateExercise.template = newTemplate
                    
                    modelContext.insert(templateExercise)
                }
                
                try modelContext.save()
                
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }
    
    private func findOrCreateExerciseDefinition(name: String, type: String, muscleGroup: String?) async throws -> ExerciseDefinition {
        // Try to find existing definition by name (case insensitive)
        let fetchDescriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate<ExerciseDefinition> { $0.name.localizedStandardContains(name) }
        )
        
        if let existing = try modelContext.fetch(fetchDescriptor).first {
            return existing
        }
        
        // Create new if not found
        let newDefinition = ExerciseDefinition(
            name: name,
            muscleGroup: muscleGroup ?? "Other"
        )
        modelContext.insert(newDefinition)
        return newDefinition
    }
}
