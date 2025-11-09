import SwiftUI
import SwiftData

struct WorkoutTemplateListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor<WorkoutTemplate>(\.createdDate, order: .reverse)]) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var createdSession: WorkoutSession?
    @State private var selectedExperienceLevel: String? = nil
    @State private var selectedGoal: String? = nil
    
    // Separate templates
    private var builtInTemplates: [WorkoutTemplate] {
        templates.filter { $0.isBuiltIn }
    }
    
    private var aiGeneratedTemplates: [WorkoutTemplate] {
        templates.filter { !$0.isBuiltIn }
    }
    
    // Filter built-in templates
    private var filteredBuiltInTemplates: [WorkoutTemplate] {
        var filtered = builtInTemplates
        
        if let level = selectedExperienceLevel {
            filtered = filtered.filter { $0.experienceLevel == level }
        }
        
        if let goal = selectedGoal {
            filtered = filtered.filter { $0.goal == goal }
        }
        
        return filtered
    }
    
    // Unique experience levels and goals
    private var experienceLevels: [String] {
        Array(Set(builtInTemplates.compactMap { $0.experienceLevel })).sorted()
    }
    
    private var availableGoals: [String] {
        let templates = selectedExperienceLevel != nil ? 
            builtInTemplates.filter { $0.experienceLevel == selectedExperienceLevel } : 
            builtInTemplates
        return Array(Set(templates.compactMap { $0.goal })).sorted()
    }
    
    var body: some View {
        Group {
            if templates.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No Templates Yet",
                        systemImage: "doc.text.fill",
                        description: Text("Built-in templates will appear here. Create custom templates from AI workout plans in the AI History.")
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        
                        let aiFirst = (WorkoutPlanGenerator.shared.availability() == .available)

                        // MARK: - AI Generated Templates (if available and preferred first)
                        if aiFirst && !aiGeneratedTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("AI Generated")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.padding)

                                VStack(spacing: 12) {
                                    ForEach(aiGeneratedTemplates) { template in
                                        TemplateCard(template: template) {
                                            selectedTemplate = template
                                        }
                                    }
                                }
                                .padding(.horizontal, AppTheme.padding)
                            }
                        }

                        // MARK: - Built-In Templates Section
                        if !builtInTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "books.vertical.fill")
                                        .foregroundColor(.orange)
                                    Text("Built-In Programs")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.padding)
                                
                                // Filters
                                VStack(spacing: 8) {
                                    // Experience Level Filter
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            FilterChip(
                                                title: "All Levels",
                                                isSelected: selectedExperienceLevel == nil
                                            ) {
                                                selectedExperienceLevel = nil
                                                selectedGoal = nil
                                            }
                                            
                                            ForEach(experienceLevels, id: \.self) { level in
                                                FilterChip(
                                                    title: level.capitalized,
                                                    isSelected: selectedExperienceLevel == level
                                                ) {
                                                    selectedExperienceLevel = level
                                                    selectedGoal = nil
                                                }
                                            }
                                        }
                                        .padding(.horizontal, AppTheme.padding)
                                    }
                                    
                                    // Goal Filter (if level selected)
                                    if selectedExperienceLevel != nil && !availableGoals.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                FilterChip(
                                                    title: "All Goals",
                                                    isSelected: selectedGoal == nil
                                                ) {
                                                    selectedGoal = nil
                                                }
                                                
                                                ForEach(availableGoals, id: \.self) { goal in
                                                    FilterChip(
                                                        title: goal.replacingOccurrences(of: "_", with: " ").capitalized,
                                                        isSelected: selectedGoal == goal
                                                    ) {
                                                        selectedGoal = goal
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, AppTheme.padding)
                                        }
                                    }
                                }
                                
                                // Template List
                                VStack(spacing: 12) {
                                    ForEach(filteredBuiltInTemplates) { template in
                                        BuiltInTemplateCard(template: template) {
                                            selectedTemplate = template
                                        }
                                    }
                                }
                                .padding(.horizontal, AppTheme.padding)
                            }
                        }
                        
                        // MARK: - AI Generated Templates Section (fallback when not first)
                        if !aiFirst && !aiGeneratedTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("AI Generated")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.padding)
                                
                                VStack(spacing: 12) {
                                    ForEach(aiGeneratedTemplates) { template in
                                        TemplateCard(template: template) {
                                            selectedTemplate = template
                                        }
                                    }
                                }
                                .padding(.horizontal, AppTheme.padding)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Workout Templates")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground(AppTheme.gradientWorkouts)
        .foregroundColor(AppTheme.textColor)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedTemplate) { template in
            NavigationStack {
                TemplateDetailView(template: template) { session in
                    createdSession = session
                    selectedTemplate = nil
                }
            }
        }
        .onChange(of: createdSession) { oldValue, newValue in
            if newValue != nil {
                // Navigate to the created workout session
                dismiss()
                // The navigation will be handled by the parent view
            }
        }
    }
}

// MARK: - Filter Chip Component
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? AppTheme.accentColor : AppTheme.secondaryBackgroundColor)
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Built-In Template Card
struct BuiltInTemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(.headline)
                            .foregroundColor(AppTheme.textColor)
                        
                        HStack(spacing: 8) {
                            if let duration = template.estimatedDuration {
                                Label("\(duration) min", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // Difficulty label instead of stars
                            if let difficulty = template.difficulty {
                                let label = difficultyLabel(for: difficulty)
                                Text(label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(difficultyColor(for: difficulty).opacity(0.2))
                                    .foregroundColor(difficultyColor(for: difficulty))
                                    .clipShape(Capsule())
                            }
                            
                            Text("\(template.exercises?.count ?? 0) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let equipment = template.equipment, !equipment.isEmpty {
                            Text(equipment.prefix(3).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let description = template.templateDescription, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(AppTheme.secondaryBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func difficultyLabel(for value: Int) -> String {
        switch value {
        case ..<3: return "Easy"
        case 3: return "Medium"
        default: return "Hard"
        }
    }

    private func difficultyColor(for value: Int) -> Color {
        switch value {
        case ..<3: return .green
        case 3: return .orange
        default: return .red
        }
    }
}

// MARK: - AI Template Card
struct TemplateCard: View {
    let template: WorkoutTemplate
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(.headline)
                            .foregroundColor(AppTheme.textColor)
                        
                        Text("\(template.exercises?.count ?? 0) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Created \(template.createdDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let notes = template.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(AppTheme.secondaryBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let template: WorkoutTemplate
    let onStartWorkout: (WorkoutSession) -> Void
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Template Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Details")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Created \(template.createdDate.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let notes = template.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                .floatingTile()
                
                // Exercise List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Exercises")
                        .font(.headline)
                    
                    if let exercises = template.exercises?.sorted(by: { $0.order < $1.order }), !exercises.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(exercises) { exercise in
                                ExerciseTemplateRow(exercise: exercise)
                            }
                        }
                    } else {
                        Text("No exercises in this template")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                }
                .floatingTile()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        let session = WorkoutTemplateService.shared.createWorkoutFromTemplate(
                            template: template,
                            context: modelContext
                        )
                        Haptics.notify(.success)
                        onStartWorkout(session)
                        dismiss()
                    } label: {
                        Label("Start Workout", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Template", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, AppTheme.padding)
        }
        .navigationTitle("Template")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground(AppTheme.gradientWorkouts)
        .foregroundColor(AppTheme.textColor)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .alert("Delete Template?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                modelContext.delete(template)
                try? modelContext.save()
                Haptics.notify(.warning)
                dismiss()
            }
        } message: {
            Text("This will permanently delete the template '\(template.title)'. This action cannot be undone.")
        }
    }
}

struct ExerciseTemplateRow: View {
    let exercise: TemplateExercise
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Order indicator
            Text("\(exercise.order + 1)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(AppTheme.accentColor))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(exercise.sets)×\(exercise.reps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let weight = exercise.suggestedWeight {
                        Text("@ \(String(format: "%.1f", weight)) \(exercise.weightUnit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
            
            Spacer()
        }
        .padding(10)
        .background(AppTheme.secondaryBackgroundColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        WorkoutTemplateListView()
    }
    .modelContainer(PersistenceController.preview.container)
}
