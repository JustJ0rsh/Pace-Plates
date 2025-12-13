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
            ZStack {
                AppTheme.backgroundColor.ignoresSafeArea()
                
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
                                        .foregroundStyle(AppTheme.textColor)
                                    
                                    ForEach(exercise.sets) { set in
                                        HStack(spacing: 6) {
                                            Text("Set \(set.setNumber)")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 50, alignment: .leading)
                                            
                                            if exercise.type == "cardio" {
                                                if let duration = set.durationSeconds {
                                                    Text("\(duration / 60):\(String(format: "%02d", duration % 60))")
                                                        .foregroundStyle(AppTheme.textColor)
                                                }
                                                if let distance = set.distance, let unit = set.distanceUnit {
                                                    Text("\(String(format: "%.2f", distance)) \(unit)")
                                                        .foregroundStyle(AppTheme.textColor)
                                                }
                                            } else {
                                                Text("\(set.displayRepsText) @ \(String(format: "%.1f", set.weight)) \(set.weightUnit)")
                                                    .foregroundStyle(AppTheme.textColor)
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        
        Task { @MainActor in
            do {
                // CRITICAL: Use the shared persistence controller's context
                let persistentContext = PersistenceController.shared.container.mainContext
                
                // Verify we have the correct database by checking built-in templates
                let builtInCheck = try persistentContext.fetch(FetchDescriptor<WorkoutTemplate>(
                    predicate: #Predicate { $0.isBuiltIn == true }
                ))
                print("🔍 Database verification: Found \(builtInCheck.count) built-in templates")
                
                if builtInCheck.isEmpty {
                    print("⚠️  WARNING: Database appears empty. This context might not be connected properly.")
                }
                
                // Keep the original name but add (Imported) suffix
                let uniqueTitle = "\(sharedSession.title) (Imported)"
                
                print("📝 Creating imported template: '\(uniqueTitle)'")
                print("   Source has \(sharedSession.exercises.count) exercises:")
                for (idx, ex) in sharedSession.exercises.enumerated() {
                    print("   [\(idx)] \(ex.name) - order: \(ex.order), sets: \(ex.sets.count)")
                }
                
                // Create a new WorkoutTemplate with explicit UUID and properties
                let templateID = UUID()
                let newTemplate = WorkoutTemplate(
                    id: templateID,
                    title: uniqueTitle,
                    notes: sharedSession.notes,
                    isBuiltIn: false, // CRITICAL: Must be false for imported templates
                    experienceLevel: "Imported",
                    goal: "Imported"
                )
                
                // Insert template first
                persistentContext.insert(newTemplate)
                
                // Add exercises to the template
                var exerciseCount = 0
                for sharedExercise in sharedSession.exercises {
                    // Skip if already processed (prevent duplicates)
                    if exerciseCount > 0 && sharedSession.exercises.filter({ $0.name == sharedExercise.name }).count > 1 {
                        // Check if we already added this exercise
                        let alreadyAdded = (0..<exerciseCount).contains { idx in
                            sharedSession.exercises[idx].name == sharedExercise.name && 
                            sharedSession.exercises[idx].order == sharedExercise.order
                        }
                        if alreadyAdded {
                            print("⚠️  Skipping duplicate exercise: \(sharedExercise.name)")
                            continue
                        }
                    }
                    
                    // Find or create ExerciseDefinition
                    _ = try findOrCreateExerciseDefinition(name: sharedExercise.name, type: sharedExercise.type, muscleGroup: sharedExercise.muscleGroup, context: persistentContext)
                    
                    // Calculate representative values from all sets
                    let allReps = sharedExercise.sets.map { $0.reps }
                    let allWeights = sharedExercise.sets.map { $0.weight }
                    
                    // Use the MEDIAN or FIRST set as representative (templates are meant to be simplified)
                    let representativeReps = allReps.first ?? 0
                    let representativeWeight = allWeights.first
                    
                    // Build detailed notes showing all sets
                    var detailedNotes: [String] = []
                    for (index, set) in sharedExercise.sets.enumerated() {
                        if sharedExercise.type == "cardio" {
                            var setInfo = "Set \(index + 1):"
                            if let duration = set.durationSeconds {
                                setInfo += " \(duration / 60):\(String(format: "%02d", duration % 60))"
                            }
                            if let distance = set.distance, let unit = set.distanceUnit {
                                setInfo += " \(String(format: "%.2f", distance)) \(unit)"
                            }
                            detailedNotes.append(setInfo)
                        } else {
                            let repsText = "\(set.displayRepsText) @ \(String(format: "%.1f", set.weight)) \(set.weightUnit)"
                            detailedNotes.append("Set \(index + 1): \(repsText)")
                        }
                        if let setNotes = set.notes, !setNotes.isEmpty {
                            detailedNotes.append("  Note: \(setNotes)")
                        }
                    }
                    let combinedNotes = detailedNotes.joined(separator: "\n")

                    let templateExercise = TemplateExercise(
                        name: sharedExercise.name,
                        order: sharedExercise.order,
                        sets: sharedExercise.sets.count,
                        reps: representativeReps,
                        suggestedWeight: representativeWeight,
                        weightUnit: sharedExercise.sets.first?.weightUnit ?? "lbs",
                        notes: combinedNotes
                    )
                    templateExercise.template = newTemplate
                    
                    persistentContext.insert(templateExercise)
                    exerciseCount += 1
                    print("   Added exercise \(exerciseCount): \(sharedExercise.name) (\(sharedExercise.sets.count) sets)")
                }
                
                // Explicitly save to catch any errors immediately
                print("💾 Saving template to database...")
                do {
                    try persistentContext.save()
                    print("✅ Save completed successfully")
                } catch {
                    print("❌ Save failed with error: \(error)")
                    print("   Error details: \(error.localizedDescription)")
                    throw error
                }
                
                // Give CloudKit a moment to process
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                // Verify with ID-based fetch (more reliable than title)
                print("🔍 Verifying template with ID: \(templateID)")
                let verifyDescriptor = FetchDescriptor<WorkoutTemplate>(
                    predicate: #Predicate<WorkoutTemplate> { template in
                        template.id == templateID
                    }
                )
                let verified = try persistentContext.fetch(verifyDescriptor)
                print("   Found \(verified.count) templates with matching ID")
                
                // Also check by title as a fallback
                let allTemplates = try persistentContext.fetch(FetchDescriptor<WorkoutTemplate>())
                print("   Total templates in DB: \(allTemplates.count)")
                let byTitle = allTemplates.filter { $0.title == uniqueTitle }
                print("   Templates with title '\(uniqueTitle)': \(byTitle.count)")
                
                if let found = verified.first {
                    print("✅ Verified template in database:")
                    print("   - ID: \(found.id)")
                    print("   - Title: \(found.title)")
                    print("   - Experience Level: \(found.experienceLevel ?? "nil")")
                    print("   - Goal: \(found.goal ?? "nil")")
                    print("   - Is Built-in: \(found.isBuiltIn)")
                    print("   - Exercises: \(found.exercises?.count ?? 0)")
                    
                    // Success feedback
                    Haptics.notify(.success)
                    isSaving = false
                    dismiss()
                } else if let foundByTitle = byTitle.first {
                    print("⚠️  Found template by title but not by ID")
                    print("   - Actual ID: \(foundByTitle.id)")
                    print("   - Expected ID: \(templateID)")
                    print("   - This suggests the template was modified after save")
                    
                    // Still count as success since it exists
                    Haptics.notify(.success)
                    isSaving = false
                    dismiss()
                } else {
                    print("❌ Template not found by ID or title")
                    print("   Checking if ANY non-built-in templates exist...")
                    let imported = allTemplates.filter { !$0.isBuiltIn }
                    print("   Non-built-in templates: \(imported.count)")
                    for t in imported.prefix(5) {
                        print("      - \(t.title) (id: \(t.id))")
                    }
                    
                    throw NSError(domain: "WorkoutImport", code: -1, 
                                userInfo: [NSLocalizedDescriptionKey: "Template failed to persist. This may be a CloudKit sync issue. Try disabling iCloud sync in Settings > Apple ID > iCloud > Pace & Plates and try again."])
                }
            } catch {
                print("❌ Failed to save template: \(error)")
                isSaving = false
                saveError = "Failed to save template: \(error.localizedDescription)"
            }
        }
    }
    
    private func findOrCreateExerciseDefinition(name: String, type: String, muscleGroup: String?, context: ModelContext) throws -> ExerciseDefinition {
        // Normalize to avoid duplicates that differ only by case/spacing/punctuation
        func normalize(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            t = t.replacingOccurrences(of: "\u{2019}", with: "'")
            t = t.replacingOccurrences(of: "\u{2018}", with: "'")
            t = t.replacingOccurrences(of: "\u{2013}", with: "-")
            t = t.replacingOccurrences(of: "\u{2014}", with: "-")
            t = t.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }.reduce("") { $0 + String($1) }
            while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let target = normalize(name)
        // Fetch once and compare in-memory using normalization for reliability with SwiftData
        let all = try context.fetch(FetchDescriptor<ExerciseDefinition>())
        if let existing = all.first(where: { normalize($0.name) == target }) {
            return existing
        }
        
        // Create new if not found
        let newDefinition = ExerciseDefinition(
            name: name,
            muscleGroup: muscleGroup ?? "Other",
            isUserDefined: true
        )
        context.insert(newDefinition)
        return newDefinition
    }
}
