// MARK: - WorkoutSessionDetailView

import SwiftData
import SwiftUI

// MARK: - View

struct WorkoutSessionDetailView: View {
    // MARK: Properties
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: WorkoutSession
    let allowDateEdit: Bool
    let isNewSession: Bool
    @State private var notes: String
    @State private var titleText: String
    @State private var notesBuffer: String
    @State private var editingLog: ExerciseLog? = nil
    @State private var editingLogIsNew: Bool = false
    @State private var saveWorkItem: DispatchWorkItem? = nil
    @State private var showingAddExercise: Bool = false
    @State private var showingDatePicker: Bool = false
    @FocusState private var notesFocused: Bool
    @FocusState private var titleFocused: Bool
    @State private var didEditTitle: Bool = false
    // Removed local saveAsTemplate state in favor of session property
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    // Avoid storing/staging ExerciseDefinition references for UI
    
    init(session: WorkoutSession, allowDateEdit: Bool = false, isNewSession: Bool = false) {
        self.session = session
        self.allowDateEdit = allowDateEdit
        self.isNewSession = isNewSession
        let initialNotes = session.notes ?? ""
        _notes = State(initialValue: initialNotes)
        _notesBuffer = State(initialValue: initialNotes)
        // Default title falls back to formatted date when empty
        let titleFallback: String = {
            if !session.title.isEmpty { return session.title }
            return "Gym Session"
        }()
        _titleText = State(initialValue: titleFallback)
    }
    
    // MARK: Body
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Details Tile
                WorkoutDetailsTile(
                    session: session,
                    allowDateEdit: allowDateEdit,
                    titleText: $titleText,
                    notesBuffer: $notesBuffer,
                    showingDatePicker: $showingDatePicker,
                    titleFocused: $titleFocused,
                    notesFocused: $notesFocused,
                    onSelectAllTitle: selectAllText
                )

                // Exercises Tile
                WorkoutExercisesTile(
                    session: session,
                    showingAddExercise: $showingAddExercise,
                    editingLog: $editingLog,
                    editingLogIsNew: $editingLogIsNew,
                    onDeleteLog: deleteExerciseLog,
                    onDuplicateLog: duplicateExerciseLog
                )
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.horizontal, AppTheme.padding)
        }
        .onChange(of: titleText) { _, _ in
            didEditTitle = true
        }
        .onTapGesture { notesFocused = false; dismissKeyboard() }
        .sheet(isPresented: $showingDatePicker) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Select Workout Date").font(.headline)
                DatePicker("Date", selection: Binding(get: { session.date }, set: { newValue in
                    session.date = newValue
                    try? modelContext.save()
                }), displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .tint(AppTheme.accentColor)
                HStack {
                    Spacer()
                    Button("Done") { showingDatePicker = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .presentationDetents([.medium])
            .presentationBackground(AppTheme.backgroundColor)
        }

        .background {
            AppTheme.gradientWorkouts
                .ignoresSafeArea()
        }
        // Removed .ignoresSafeArea(.keyboard) to allow view to resize
        .scrollDismissesKeyboard(.immediately)
        .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .foregroundColor(AppTheme.textColor)
        .navigationTitle(titleText.isEmpty ? "Workout Details" : titleText)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    shareMenu
                    
                    Button("Done") {
                        dismissKeyboard()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseView(workoutSession: session, onAdd: { log in
                editingLog = log
            })
        }
        .sheet(item: $editingLog) { log in
            EditExerciseLogView(log: log, isNew: editingLogIsNew)
        }
        .onAppear {
            if editingLog == nil || !((session.exerciseLogs ?? []).contains { $0.id == editingLog?.id }) {
                editingLog = nil
            }
            // Clean up any empty sets that may have slipped through
            cleanupEmptySets()
        }
        .onChange(of: notesBuffer) {
            saveWorkItem?.cancel()
            let work = DispatchWorkItem { [session, modelContext] in
                if session.notes != notesBuffer {
                    session.notes = notesBuffer
                    try? modelContext.save()
                }
            }
            saveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
        .onDisappear {
            // Flush any pending notes save work and persist the session when leaving this screen
            saveWorkItem?.cancel()
            if session.notes != notesBuffer {
                session.notes = notesBuffer
            }
            // Only persist title if user actually edited it; avoid writing fallback "Gym Session" for brand-new sessions
            if didEditTitle, session.title != titleText {
                session.title = titleText
            }
            try? modelContext.save()

            // Report Game Center leaderboards for strength PRs and session volume
            GameCenterService.shared.reportStrengthForSession(
                exerciseLogs: session.exerciseLogs,
                preferredWeightUnit: weightUnit
            )

            // Update streak achievements (daily and weekly)
            StreakService.refreshAndReport(using: modelContext)

            // If this was just created and contains no meaningful data, delete it instead of leaving an empty session behind
            if isNewSession {
                let hasExercises = !((session.exerciseLogs ?? []).isEmpty)
                let hasNotes = !(notesBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                let titleTrim = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Consider title meaningful only if user edited it and it's non-empty
                let hasTitle = didEditTitle && !titleTrim.isEmpty
                if !(hasExercises || hasNotes || hasTitle) {
                    modelContext.delete(session)
                    try? modelContext.save()
                }
            }
            
            // Save as template if requested and session is valid
            if session.shouldSaveAsTemplate && !session.isDeleted {
                let hasExercises = !((session.exerciseLogs ?? []).isEmpty)
                if hasExercises {
                    if let existingTemplate = session.generatedTemplate {
                        // Update existing template
                        WorkoutTemplateService.shared.updateTemplate(template: existingTemplate, from: session, context: modelContext)
                    } else {
                        // Create new template and link it
                        let newTemplate = WorkoutTemplateService.shared.createTemplateFromWorkout(session: session, context: modelContext)
                        session.generatedTemplate = newTemplate
                        try? modelContext.save()
                    }
                }
            }
        }
    }
    
    // MARK: Actions
    
    private func deleteExerciseLogs(offsets: IndexSet) {
        guard var logs = session.exerciseLogs else { return }
        for index in offsets { modelContext.delete(logs[index]) }
        logs.remove(atOffsets: offsets)
        session.exerciseLogs = logs
        try? modelContext.save()
    }
    
    private func deleteExerciseLog(_ log: ExerciseLog) {
        let name = log.exerciseName
        modelContext.delete(log)
        renumberSets(for: name)
        try? modelContext.save()
    }
    
    private func duplicateExerciseLog(_ log: ExerciseLog) {
        let copy = ExerciseLog(
            reps: log.reps,
            weight: log.weight,
            weightUnit: log.weightUnit,
            setNumber: log.setNumber + 1,
            exerciseName: log.exerciseName,
            exerciseOrder: log.exerciseOrder
        )
        copy.exerciseDefinition = log.exerciseDefinition
        copy.workoutSession = session
        copy.isIsolated = log.isIsolated
        if var arr = session.exerciseLogs { arr.append(copy); session.exerciseLogs = arr } else { session.exerciseLogs = [copy] }
        try? modelContext.save()
    }

    // Renumber setNumber for an exercise so they stay 1..N in order
    private func renumberSets(for exerciseName: String?) {
        guard let exerciseName else { return }
        var group = (session.exerciseLogs ?? []).filter { ($0.exerciseName ?? "") == exerciseName }
        group.sort { $0.setNumber < $1.setNumber }
        for (idx, item) in group.enumerated() { item.setNumber = idx + 1 }
    }
    
    private func saveNotes(_ newValue: String) {
        if session.notes != newValue {
            session.notes = newValue
            try? modelContext.save()
        }
    }
    
    private func deleteExerciseByName(_ name: String) {
        let toDelete = (session.exerciseLogs ?? []).filter { ($0.exerciseName ?? "") == name }
        for item in toDelete { modelContext.delete(item) }
        if var arr = session.exerciseLogs { arr.removeAll { ($0.exerciseName ?? "") == name }; session.exerciseLogs = arr }
        try? modelContext.save()
    }
    
    /// Removes any empty sets (0 reps for strength, 0 duration for cardio)
    private func cleanupEmptySets() {
        guard let logs = session.exerciseLogs else { return }
        
        var needsSave = false
        for log in logs {
            let isEmpty: Bool
            
            // Check if it's a cardio exercise
            let isCardio = log.exerciseType == "cardio" || 
                          log.exerciseDefinition?.muscleGroup.lowercased() == "cardio"
            
            if isCardio {
                // Cardio set is empty if duration is 0
                isEmpty = (log.durationSeconds ?? 0) == 0
            } else {
                // Strength set is empty if reps is 0
                isEmpty = log.reps == 0
            }
            
            if isEmpty {
                modelContext.delete(log)
                needsSave = true
            }
        }
        
        if needsSave {
            // Update the session's exerciseLogs array
            if var arr = session.exerciseLogs {
                arr.removeAll { log in
                    let isCardio = log.exerciseType == "cardio" || 
                                  log.exerciseDefinition?.muscleGroup.lowercased() == "cardio"
                    if isCardio {
                        return (log.durationSeconds ?? 0) == 0
                    } else {
                        return log.reps == 0
                    }
                }
                session.exerciseLogs = arr
            }
            try? modelContext.save()
        }
    }

    private func generateShareText(includeData: Bool) -> String {
        var text = ""
        
        // Header
        let title = session.title.isEmpty ? "Gym Session" : session.title
        text += "\(title)\n"
        text += "\(session.date.formatted(date: .long, time: .shortened))\n"
        
        if let notes = session.notes, !notes.isEmpty {
            text += "\nNotes: \(notes)\n"
        }
        
        text += "\n"
        
        // Exercises
        let logs = session.exerciseLogs ?? []
        let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Exercise" }
        
        // Sort by exerciseOrder
        let sortedNames = groups.keys.sorted { name1, name2 in
            let order1 = groups[name1]?.map { $0.exerciseOrder }.min() ?? Int.min
            let order2 = groups[name2]?.map { $0.exerciseOrder }.min() ?? Int.min
            // Same sort logic as view: higher order first (reversed in view logic? wait, let's check view logic)
            // View logic: return order1 > order2. So higher order is first.
            if order1 != order2 {
                return order1 > order2
            } else {
                return name1 < name2
            }
        }
        
        for name in sortedNames {
            text += "• \(name)\n"
            let exerciseLogs = (groups[name] ?? []).sorted { $0.setNumber < $1.setNumber }
            
            for log in exerciseLogs {
                text += "  Set \(log.setNumber): "
                
                if includeData {
                    if log.isCardio {
                        var parts: [String] = []
                        if let duration = log.formattedDuration { parts.append(duration) }
                        if let distance = log.distance, let unit = log.distanceUnit {
                            parts.append("\(String(format: "%.2f", distance)) \(unit)")
                        }
                        text += parts.joined(separator: " | ")
                    } else {
                        let repsText = "\(log.displayRepsText) @ \(String(format: "%.1f", log.weight)) \(log.weightUnit)"
                        text += log.isIsolated ? "\(repsText)" : repsText
                    }
                } else {
                    // Structure only
                    text += "____"
                }
                text += "\n"
            }
            text += "\n"
        }
        
        return text
        }
    
    private func selectAllText() {
        #if os(iOS)
        DispatchQueue.main.async {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
        #endif
    }
    
    private var shareMenu: some View {
        Menu {
            let sharedSession = WorkoutSharingService.shared.convertToShared(session)
            ShareLink(item: sharedSession, preview: SharePreview(session.title.isEmpty ? "Workout" : session.title)) {
                Label("Share Workout File", systemImage: "square.and.arrow.up")
            }
            
            ShareLink(item: generateShareText(includeData: true)) {
                Label("Share Text Summary", systemImage: "doc.text")
            }
            
            ShareLink(item: generateShareText(includeData: false)) {
                Label("Share Structure Only", systemImage: "list.bullet")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
    }
}

// MARK: - Subviews

struct ExerciseLogRow: View {
    @Environment(\.modelContext) private var modelContext
    let log: ExerciseLog
    let onEdit: (ExerciseLog) -> Void
    
    init(log: ExerciseLog, onEdit: @escaping (ExerciseLog) -> Void) {
        self.log = log
        self.onEdit = onEdit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(log.exerciseName ?? "Exercise")
                    .font(.headline)
                Spacer()
                Button {
                    onEdit(log)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            
            if log.isCardio {
                HStack(spacing: 8) {
                    if let duration = log.formattedDuration {
                        Text(duration)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let distance = log.distance, let unit = log.distanceUnit {
                        Text("• \(String(format: "%.2f", distance)) \(unit)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("\(log.displayRepsText) @ \(String(format: "%.1f", log.weight)) \(log.weightUnit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Display notes if present
            if let notes = log.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(log) }
    }
}
