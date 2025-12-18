import SwiftUI
import SwiftData

struct WorkoutTemplateListView: View {
    private enum LibraryTab: String {
        case programs
        case aiGenerated
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor<WorkoutTemplate>(\.createdDate, order: .reverse)]) private var templates: [WorkoutTemplate]
    @State private var selectedTemplate: WorkoutTemplate?
    @State private var createdSession: WorkoutSession?
    @State private var selectedExperienceLevel: String? = nil
    @State private var selectedGoal: String? = nil
    @State private var searchText: String = ""
    @State private var selectedLibraryTab: LibraryTab = .programs
    
    // Separate templates
    private var builtInTemplates: [WorkoutTemplate] {
        templates.filter { $0.isBuiltIn && $0.experienceLevel?.lowercased() != "advanced" }
    }
    
    private var importedTemplates: [WorkoutTemplate] {
        templates.filter { !$0.isBuiltIn && $0.experienceLevel == "Imported" }
    }
    
    private var aiGeneratedTemplates: [WorkoutTemplate] {
        templates.filter { !$0.isBuiltIn && $0.experienceLevel != "Imported" }
    }
    
    // Filter templates - includes both built-in and imported
    private var filteredTemplates: [WorkoutTemplate] {
        if selectedLibraryTab == .aiGenerated {
            var filtered = aiGeneratedTemplates
            if !searchText.isEmpty {
                filtered = filtered.filter { template in
                    template.title.localizedCaseInsensitiveContains(searchText) ||
                    (template.templateDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (template.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
                }
            }
            return filtered
        }

        if selectedExperienceLevel == "Imported" {
            // Show only imported templates
            return importedTemplates
        }
        
        if selectedExperienceLevel == "Custom" {
            // Show both built-in Custom AND imported templates
            let customBuiltIns = builtInTemplates.filter { $0.experienceLevel == "Custom" }
            return customBuiltIns + importedTemplates
        }
        
        // For other levels or "All", filter built-ins normally
        var filtered = builtInTemplates
        
        if let level = selectedExperienceLevel {
            filtered = filtered.filter { $0.experienceLevel == level }
        }
        
        if let goal = selectedGoal {
            filtered = filtered.filter { $0.goal == goal }
        }
        
        if !searchText.isEmpty {
            filtered = filtered.filter { template in
                template.title.localizedCaseInsensitiveContains(searchText) ||
                (template.templateDescription?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (template.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return filtered
    }
    
    // Unique experience levels and goals
    private var experienceLevels: [String] {
        let builtInLevels = Set(builtInTemplates.compactMap { $0.experienceLevel })
        let order = ["Custom", "Imported", "Beginner", "Intermediate"]
        
        return order.filter { level in
            if level == "Imported" { return !importedTemplates.isEmpty }
            return builtInLevels.contains(level)
        }
    }
    
    // Section Headers
    private var sectionTitle: String {
        if selectedExperienceLevel == "Imported" { return "Imported Templates" }
        if selectedExperienceLevel == "Custom" { return "Custom Programs" }
        return "Workout Programs"
    }
    
    private var sectionIcon: String {
        if selectedExperienceLevel == "Imported" { return "square.and.arrow.down.fill" }
        return "books.vertical.fill"
    }
    
    private var sectionColor: Color {
        if selectedExperienceLevel == "Imported" { return .blue }
        return .orange
    }
    
    private var availableGoals: [String] {
        if selectedLibraryTab == .aiGenerated { return [] }
        // Hide categories for Custom templates
        if selectedExperienceLevel == "Custom" { return [] }
        
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
                ZStack(alignment: .bottom) {
                    List {
                        // MARK: - Custom & Imported Templates Combined
                        if !builtInTemplates.isEmpty || !importedTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: sectionIcon)
                                        .foregroundColor(sectionColor)
                                    Text(sectionTitle)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Spacer()
                                }
                                .padding(.horizontal, AppTheme.padding)

                                // Filters
                                VStack(spacing: 8) {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            FilterChip(
                                                title: "All Templates",
                                                isSelected: selectedLibraryTab == .programs && selectedExperienceLevel == nil
                                            ) {
                                                selectedLibraryTab = .programs
                                                selectedExperienceLevel = nil
                                                selectedGoal = nil
                                            }

                                            if !aiGeneratedTemplates.isEmpty {
                                                FilterChip(
                                                    title: "AI Generated",
                                                    isSelected: selectedLibraryTab == .aiGenerated
                                                ) {
                                                    selectedLibraryTab = .aiGenerated
                                                    selectedExperienceLevel = nil
                                                    selectedGoal = nil
                                                }
                                            }

                                            ForEach(experienceLevels, id: \.self) { level in
                                                FilterChip(
                                                    title: level.capitalized,
                                                    isSelected: selectedLibraryTab == .programs && selectedExperienceLevel == level
                                                ) {
                                                    selectedLibraryTab = .programs
                                                    selectedExperienceLevel = level
                                                    selectedGoal = nil
                                                }
                                            }
                                        }
                                        .padding(.horizontal, AppTheme.padding)
                                    }

                                    if selectedLibraryTab == .programs &&
                                        selectedExperienceLevel != nil &&
                                        selectedExperienceLevel != "Imported" &&
                                        !availableGoals.isEmpty
                                    {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                FilterChip(
                                                    title: "All Categories",
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
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 4, trailing: 0))

                            ForEach(filteredTemplates) { template in
                                if selectedLibraryTab == .programs, template.isBuiltIn {
                                    BuiltInTemplateCard(template: template) {
                                        selectedTemplate = template
                                    }
                                    .padding(.horizontal, AppTheme.padding)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                } else {
                                    TemplateCard(template: template) {
                                        selectedTemplate = template
                                    }
                                    .padding(.horizontal, AppTheme.padding)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(template)
                                            try? modelContext.save()
                                            Haptics.notify(.warning)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }

                        // Space for floating search bar so the last row isn't obscured
                        Color.clear
                            .frame(height: 92)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    
                    // Floating Search Bar
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            NoToolbarTextField(
                                text: $searchText,
                                placeholder: "Search templates...",
                                returnKeyType: .search,
                                onCommit: { dismissKeyboard() }
                            )
                            .frame(height: 24) // Match standard text field height
                            
                            if !searchText.isEmpty {
                                Button(action: { 
                                    searchText = ""
                                    dismissKeyboard()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, AppTheme.padding)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .navigationTitle("Workout Templates")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.gradientWorkouts.ignoresSafeArea())
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
        .onAppear {
            // Smart default selection
            if selectedLibraryTab == .programs && selectedExperienceLevel == nil {
                let hasCustom = builtInTemplates.contains { $0.experienceLevel == "Custom" }
                let hasImported = !importedTemplates.isEmpty
                if hasImported {
                    // Default to Imported if we have imported templates
                    selectedLibraryTab = .programs
                    selectedExperienceLevel = "Imported"
                } else if hasCustom {
                    selectedLibraryTab = .programs
                    selectedExperienceLevel = "Custom"
                }
                // Otherwise leave as nil ("All Templates")
            }
        }
    }
}

// MARK: - No Toolbar Text Field
struct NoToolbarTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var returnKeyType: UIReturnKeyType = .default
    var onCommit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.returnKeyType = returnKeyType
        
        // This is the key line to remove the toolbar
        textField.inputAccessoryView = nil
        
        // Styling to match SwiftUI TextField
        textField.textColor = UIColor(AppTheme.textColor)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        textField.backgroundColor = .clear
        
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoToolbarTextField

        init(_ parent: NoToolbarTextField) {
            self.parent = parent
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit?()
            textField.resignFirstResponder()
            return true
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        // Handle text changes
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if let currentText = textField.text as NSString? {
                let updatedText = currentText.replacingCharacters(in: range, with: string)
                parent.text = updatedText
            }
            return true
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
                            
                            Text("\(template.exerciseCount) exercises")
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
                        
                        Text("\(template.exerciseCount) exercises")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Created \(template.createdDate, style: .date)")
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
