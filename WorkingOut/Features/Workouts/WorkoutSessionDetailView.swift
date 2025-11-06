// MARK: - WorkoutSessionDetailView

import SwiftData
import SwiftUI

// MARK: - View

struct WorkoutSessionDetailView: View {
    // MARK: Properties
    
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession
    @State private var notes: String
    @State private var titleText: String
    @State private var notesBuffer: String
    @State private var editingLog: ExerciseLog? = nil
    @State private var editingLogIsNew: Bool = false
    @State private var saveWorkItem: DispatchWorkItem? = nil
    @State private var showingAddExercise: Bool = false
    @FocusState private var notesFocused: Bool
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    // Avoid storing/staging ExerciseDefinition references for UI
    
    init(session: WorkoutSession) {
        self.session = session
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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Workout Title", text: $titleText)
                            .padding(10)
                            .background(AppTheme.secondaryBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(AppTheme.textColor)
                            .tint(AppTheme.accentColor)
                            .onChange(of: titleText) { _, newValue in
                                saveWorkItem?.cancel()
                                let work = DispatchWorkItem { [session, modelContext] in
                                    if session.title != newValue {
                                        session.title = newValue
                                        try? modelContext.save()
                                    }
                                }
                                saveWorkItem = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
                            }
                    }
                    Text("Date: \(session.date.formatted())")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $notesBuffer)
                            .focused($notesFocused)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(AppTheme.secondaryBackgroundColor)
                            .foregroundColor(AppTheme.textColor)
                            .tint(AppTheme.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .floatingTile()

                // Exercises Tile
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Exercises")
                            .font(.headline)
                        Spacer()
                        Button {
                            showingAddExercise = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    // Group logs by exercise name to show one exercise with multiple sets
                    let logs = session.exerciseLogs ?? []
                    let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Exercise" }
                    
                    // Sort by exerciseOrder first, then by name
                    let sortedNames = groups.keys.sorted { name1, name2 in
                        // Get the minimum exerciseOrder for each name
                        let order1 = groups[name1]?.map { $0.exerciseOrder }.min() ?? Int.max
                        let order2 = groups[name2]?.map { $0.exerciseOrder }.min() ?? Int.max
                        
                        if order1 != order2 {
                            return order1 < order2
                        } else {
                            // If orders are equal, sort alphabetically
                            return name1 < name2
                        }
                    }

                    if (session.exerciseLogs?.isEmpty ?? true) {
                        Text("No exercises yet. Tap Add Exercise to begin.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(sortedNames, id: \.self) { name in
                                let logs = (groups[name] ?? []).sorted { $0.setNumber < $1.setNumber }
                                VStack(alignment: .leading, spacing: 10) {
                                    // Header row: Exercise title + Add Set
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(name)
                                            .font(.headline)
                                        Spacer()
                                        Button {
                                            if let base = logs.last ?? groups[name]?.first {
                                                let next = ExerciseLog(
                                                    reps: base.reps,
                                                    weight: base.weight,
                                                    weightUnit: base.weightUnit,
                                                    setNumber: (logs.map { $0.setNumber }.max() ?? 0) + 1,
                                                    exerciseName: base.exerciseName,
                                                    exerciseOrder: base.exerciseOrder
                                                )
                                                next.exerciseDefinition = base.exerciseDefinition
                                                next.workoutSession = session
                                                if var arr = session.exerciseLogs { arr.append(next); session.exerciseLogs = arr } else { session.exerciseLogs = [next] }
                                                try? modelContext.save()
                                                editingLog = next
                                                editingLogIsNew = true
                                            }
                                        } label: {
                                            Label("Add Set", systemImage: "plus")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.blue)
                                    }

                                    // Set rows
                                    LazyVStack(spacing: 6) {
                                        ForEach(logs) { log in
                                            HStack {
                                                Button {
                                                    editingLog = log
                                                    editingLogIsNew = false
                                                } label: {
                                            HStack {
                                                Text("Set \(log.setNumber)")
                                                    .foregroundColor(AppTheme.textColor)
                                                Spacer()
                                                if log.isCardio {
                                                    // Show cardio metrics
                                                    HStack(spacing: 8) {
                                                        if let duration = log.formattedDuration {
                                                            Text(duration)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        if let distance = log.distance, let unit = log.distanceUnit {
                                                            Text("• \(String(format: "%.2f", distance)) \(unit)")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        if let pace = log.calculatedPace {
                                                            Text("• \(pace)")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    }
                                                } else {
                                                    // Show strength metrics
                                                    Text("\(log.reps) reps @ \(String(format: "%.1f", log.weight)) \(log.weightUnit)")
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.vertical, 6)
                                                }
                                                .buttonStyle(.plain)
                                                Button(role: .destructive) {
                                                    deleteExerciseLog(log)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteExerciseLog(log)
                                                } label: { Label("Delete Set", systemImage: "trash") }
                                                Button {
                                                    duplicateExerciseLog(log)
                                                } label: { Label("Add Set", systemImage: "plus.square.on.square") }
                                                .tint(.blue)
                                            }
                                            Divider().opacity(0.12)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(AppTheme.secondaryBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .floatingTile()
            }
            .padding(.horizontal, AppTheme.padding)
        }
        .onTapGesture { notesFocused = false; dismissKeyboard() }
        .appBackground(AppTheme.gradientWorkouts)
        .ignoresSafeArea(.keyboard) // Fill behind the keyboard to avoid dark gap
        .scrollDismissesKeyboard(.immediately)
        .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .scrollContentBackground(.hidden)
        .foregroundColor(AppTheme.textColor)
        .background {
            AppTheme.backgroundGradient
                .ignoresSafeArea(.keyboard) // Ensure gradient extends under keyboard
        }
        .navigationTitle(titleText.isEmpty ? "Workout Details" : titleText)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
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
            if session.title != titleText {
                session.title = titleText
            }
            try? modelContext.save()
            // Auto-submit leaderboards after saving
            GameCenterService.submitAllMetrics(context: modelContext, preferredUnit: weightUnit)
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
                Text("\(log.reps) reps @ \(String(format: "%.1f", log.weight)) \(log.weightUnit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(log) }
    }
}
