import SwiftUI
import SwiftData

struct WorkoutDetailsTile: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession
    let allowDateEdit: Bool
    @Binding var titleText: String
    @Binding var notesBuffer: String
    @Binding var showingDatePicker: Bool
    var titleFocused: FocusState<Bool>.Binding
    var notesFocused: FocusState<Bool>.Binding
    let onSelectAllTitle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Details")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Save Template")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(
                        get: { session.shouldSaveAsTemplate },
                        set: { newValue in
                            session.shouldSaveAsTemplate = newValue
                            _ = PersistenceSave.commit(modelContext, action: "save changes")
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .green))
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Workout Title", text: $titleText)
                    .padding(14)
                    .background(AppTheme.secondaryBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundColor(AppTheme.textColor)
                    .tint(AppTheme.accentColor)
                    .focused(titleFocused)
                    .onTapGesture { onSelectAllTitle() }
                    .onChange(of: titleFocused.wrappedValue) { _, newValue in
                        if newValue {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onSelectAllTitle()
                            }
                        }
                    }
            }
            HStack(spacing: 8) {
                Text("Date: \(session.date.formatted())")
                if allowDateEdit {
                    Button {
                        showingDatePicker = true
                    } label: {
                        Image(systemName: "calendar")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change Date")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $notesBuffer)
                    .focused(notesFocused)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.secondaryBackgroundColor)
                    .foregroundColor(AppTheme.textColor)
                    .tint(AppTheme.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .floatingTile()
    }
}

/// Shows metrics attached from a linked wearable/Health workout.
struct WearableMetricsTile: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch")
                    .foregroundStyle(AppTheme.accentColor)
                Text(session.healthSourceName ?? "Apple Watch")
                    .font(.headline)
                Spacer()
                if let key = session.healthActivityType {
                    Text(WearableWorkoutInboxService.activityDisplayName(for: key))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentColor.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 0) {
                if let duration = session.healthDuration {
                    wearableMetric(icon: "clock", value: durationText(duration), label: "Duration")
                }
                if let calories = session.healthCalories {
                    wearableMetric(icon: "flame", value: "\(Int(calories.rounded()))", label: "kcal")
                }
                if let bpm = session.healthAvgHeartRate {
                    wearableMetric(icon: "heart", value: "\(Int(bpm.rounded()))", label: "Avg bpm")
                }
            }
        }
        .floatingTile()
    }

    private func wearableMetric(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.accentColor)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(totalMinutes, 1))m"
    }
}

struct WorkoutExercisesTile: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession
    @Binding var showingAddExercise: Bool
    @Binding var editingLog: ExerciseLog?
    @Binding var editingLogIsNew: Bool
    
    let onDeleteLog: (ExerciseLog) -> Void
    let onDuplicateLog: (ExerciseLog) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .foregroundStyle(AppTheme.accentColor)
                }
            }

            // Group logs by exercise name
            let logs = session.exerciseLogs ?? []
            let groups = Dictionary(grouping: logs) { $0.exerciseName ?? "Exercise" }
            
            // Sort by exerciseOrder (most recently added first), then by name
            let sortedNames = groups.keys.sorted { name1, name2 in
                let order1 = groups[name1]?.map { $0.exerciseOrder }.min() ?? Int.min
                let order2 = groups[name2]?.map { $0.exerciseOrder }.min() ?? Int.min
                
                if order1 != order2 {
                    return order1 > order2
                } else {
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
                                            exerciseOrder: base.exerciseOrder,
                                            exerciseType: base.exerciseType,
                                            durationSeconds: base.durationSeconds,
                                            distance: base.distance,
                                            distanceUnit: base.distanceUnit,
                                            caloriesBurned: base.caloriesBurned,
                                            avgHeartRate: base.avgHeartRate,
                                            notes: base.notes,
                                            isCompleted: false
                                        )
                                        next.exerciseDefinition = base.exerciseDefinition
                                        next.workoutSession = session
                                        next.isIsolated = base.isIsolated
                                        if var arr = session.exerciseLogs { arr.append(next); session.exerciseLogs = arr } else { session.exerciseLogs = [next] }
                                        _ = PersistenceSave.commit(modelContext, action: "save changes")
                                        editingLog = next
                                        editingLogIsNew = true
                                    }
                                } label: {
                                    Label("Add Set", systemImage: "plus")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppTheme.accentColor)
                            }

                            // Set rows
                            LazyVStack(spacing: 6) {
                                ForEach(logs) { log in
                                    WorkoutSessionExerciseRow(
                                        session: session,
                                        log: log,
                                        onEdit: {
                                            editingLog = log
                                            editingLogIsNew = false
                                        },
                                        onDelete: { onDeleteLog(log) },
                                        onDuplicate: { onDuplicateLog(log) }
                                    )
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
}

struct WorkoutSessionExerciseRow: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkoutSession
    let log: ExerciseLog
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if session.sourceTemplateID != nil {
                    Button {
                        log.isCompleted.toggle()
                        if PersistenceSave.commit(modelContext, action: "save changes") {
                            Haptics.playImpact(log.isCompleted ? .medium : .light)
                        }
                    } label: {
                        Image(systemName: log.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(log.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Set \(log.setNumber) complete")
                    .accessibilityValue(log.isCompleted ? "On" : "Off")
                    .accessibilityAddTraits(.isToggle)
                }
                
                Button {
                    onEdit()
                } label: {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Set \(log.setNumber)")
                                .foregroundColor(AppTheme.textColor)
                            if let notes = log.notes, !notes.isEmpty {
                                Image(systemName: "note.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if log.isCardio {
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
                            Text("\(log.displayRepsText) @ \(String(format: "%.1f", log.weight)) \(log.weightUnit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete set \(log.setNumber)")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDelete()
                } label: { Label("Delete Set", systemImage: "trash") }
                Button {
                    onDuplicate()
                } label: { Label("Add Set", systemImage: "plus.square.on.square") }
                .tint(AppTheme.accentColor)
            }
            
            Divider().opacity(0.12)
        }
    }
}
