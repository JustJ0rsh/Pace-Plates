import SwiftUI
import SwiftData
import UserNotifications

struct CoachStrengthExecutionView: View {
    @Environment(\.modelContext) private var context
    let execution: CoachSessionExecution
    let prescription: CoachStrengthSession
    var guidanceNotes: String? = nil
    @State private var snapshot = CoachExecutionSnapshot()
    @State private var editing: SetEditorRequest?
    @State private var error: String?
    @State private var showFinish = false
    @State private var showAttestation = false
    @State private var explanation = ""
    @State private var previous: [CoachSetResult] = []
    @AppStorage("coach.autoRest") private var autoRest = true
    private var isFinished: Bool { execution.statusRaw != "in_progress" }
    private var allPerformed: Bool {
        prescription.exercises.allSatisfy { exercise in
            exercise.sets.allSatisfy { set in result(exercise.id, set.id)?.state == .completed }
        }
    }

    var body: some View {
        List {
            Section {
                Text(prescription.title).font(.title2.bold())
                Text(execution.statusRaw.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
                if let notes = guidanceNotes ?? prescription.notes, !notes.isEmpty { Text(notes) }
                Text("Targets are suggestions. Actual fields stay blank until you record them.").font(.caption).foregroundStyle(.secondary)
            }
            if let timer = snapshot.restTimer, !isFinished {
                Section("Rest") {
                    CoachRestTimerView(timer: timer, onChange: updateTimer)

                }
            }
            if !isFinished {
                Section("Rest settings") {
                    Toggle("Start rest after a working set", isOn: $autoRest)
                    Button("Enable rest notifications") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                    }
                }
            }
            ForEach(prescription.exercises) { exercise in
                Section {
                    if let notes = exercise.notes { Text(notes).font(.subheadline).foregroundStyle(.secondary) }
                    let last = previous.filter { $0.performedExerciseID == exercise.exercise.key && $0.equipment == exercise.exercise.equipment.sorted().joined(separator: ",") && $0.repCounting == exercise.prescriptionBasis.rawValue && $0.loadBasis == exercise.loadBasis.rawValue && $0.state == .completed }
                    if !last.isEmpty {
                        Text("Previous comparable: " + last.map(CoachStrengthFormatting.actual).joined(separator: "; "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(exercise.sets) { set in
                        Button {
                            editing = SetEditorRequest(exercise: exercise, set: set, result: result(exercise.id, set.id))
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(CoachStrengthFormatting.prescription(set, exercise: exercise)).foregroundStyle(.primary)
                                    if let result = result(exercise.id, set.id) {
                                        if result.performedExerciseID != exercise.exercise.key { Text("Performed: \(result.performedExerciseName)").font(.caption) }
                                        Text("\(result.state.rawValue.capitalized): \(CoachStrengthFormatting.actual(result))").font(.caption).foregroundStyle(.secondary)
                                    } else { Text("Not recorded").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: result(exercise.id, set.id)?.state == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(result(exercise.id, set.id)?.state == .completed ? .green : .secondary)
                            }
                            .padding(.vertical, 5)
                        }
                        .accessibilityIdentifier("coach.set.\(exercise.id).\(set.id)")
                        if !isFinished, let seconds = set.restAfterSeconds, seconds > 0, result(exercise.id, set.id)?.state == .completed {
                            Button("Start \(seconds)-second rest") {
                                updateTimer(CoachRestTimerState(setResultID: exercise.id + "/" + set.id, seconds: Double(seconds)))
                            }
                        }
                    }
                } header: { Text(exercise.exercise.name) }
            }
            Section("Session notes") {
                TextField("Notes", text: Binding(get: { snapshot.notes }, set: { snapshot.notes = $0; save() }), axis: .vertical)
                Picker("Effort scale", selection: Binding(get: { snapshot.effortScale }, set: { value in
                    if snapshot.effortScale != value { snapshot.effort = nil }
                    snapshot.effortScale = value; save()
                })) {
                    Text("RPE").tag("rpe"); Text("RIR").tag("rir")
                }
                TextField("Optional actual \(snapshot.effortScale.uppercased())", value: Binding(get: { snapshot.effort }, set: { snapshot.effort = $0; save() }), format: .number)
                    .keyboardType(.decimalPad).onSubmit(save)
                Button("Save notes and effort", action: save)
            }
            if !isFinished {
                Section {
                    Button("Finish Workout", systemImage: "checkmark.circle") {
                        if allPerformed { finish(.completed) } else { showFinish = true }
                    }
                    .accessibilityIdentifier("coach.workout.finish")
                    Text("Closing saves your recorded sets and leaves this workout available to resume.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Saved \(execution.statusRaw). Correct a set to update your history and invalidate suggestions based on the older result.")
                    NavigationLink("Review progression") { CoachProgressionReviewView(execution: execution) }
                }
            }
        }
        .task { load() }
        .sheet(item: $editing) { request in
            NavigationStack {
                CoachSetEditor(request: request) { result in
                    if let index = snapshot.setResults.firstIndex(where: { $0.id == result.id }) { snapshot.setResults[index] = result }
                    else { snapshot.setResults.append(result) }
                    if !isFinished, autoRest, result.state == .completed, request.set.role == .working,
                       let seconds = request.set.restAfterSeconds, seconds > 0 {
                        if let timer = snapshot.restTimer { CoachRestNotifications.cancel(timer.notificationID) }
                        snapshot.restTimer = CoachRestTimerState(setResultID: result.id, seconds: Double(seconds))
                    }
                    try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context)
                    if !isFinished, let timer = snapshot.restTimer { CoachRestNotifications.schedule(timer) }
                }
            }
        }
        .confirmationDialog("Prescribed work is unfinished", isPresented: $showFinish, titleVisibility: .visible) {
            Button("Save Partial") { finish(.partial) }
            Button("Record completion with explanation") { showAttestation = true }
            Button("Continue", role: .cancel) {}
        } message: { Text("\(snapshot.setResults.filter { $0.state == .completed }.count) of \(prescription.exercises.reduce(0) { $0 + $1.sets.count }) prescribed sets recorded complete.") }
        .alert("Completion explanation", isPresented: $showAttestation) {
            TextField("Explain the completed work", text: $explanation)
            Button("Cancel", role: .cancel) {}
            Button("Record Completion") { finish(.completed, explanation: explanation) }
                .disabled(explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Unable to Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func result(_ exercise: String, _ set: String) -> CoachSetResult? { snapshot.setResults.first { $0.exerciseID == exercise && $0.setID == set } }
    private func load() {
        do {
            snapshot = try CoachExecutionCoordinator.snapshot(execution)
            var descriptor = FetchDescriptor<CoachSessionExecution>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            descriptor.predicate = #Predicate { $0.statusRaw == "completed" }
            let history = try context.fetch(descriptor).filter { $0.startedAt < execution.startedAt }
            let priorResults = try history.map { try CoachExecutionCoordinator.snapshot($0).setResults }
            previous = prescription.exercises.flatMap { exercise in
                priorResults.first(where: { results in results.contains { comparable($0, to: exercise) } })?
                    .filter { comparable($0, to: exercise) } ?? []
            }
        } catch { self.error = error.localizedDescription }
    }
    private func comparable(_ result: CoachSetResult, to exercise: CoachStrengthExercise) -> Bool {
        result.state == .completed && result.performedExerciseID == exercise.exercise.key
            && result.equipment == exercise.exercise.equipment.sorted().joined(separator: ",")
            && result.repCounting == exercise.prescriptionBasis.rawValue && result.loadBasis == exercise.loadBasis.rawValue
    }
    private func save() {
        do { try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context) }
        catch { self.error = error.localizedDescription }
    }
    private func updateTimer(_ value: CoachRestTimerState?) {
        if let old = snapshot.restTimer { CoachRestNotifications.cancel(old.notificationID) }
        snapshot.restTimer = value
        save()
        if let value { CoachRestNotifications.schedule(value) }
    }
    private func finish(_ status: CoachExecutionStatus, explanation: String? = nil) {
        do { try CoachExecutionCoordinator.finish(execution, snapshot: snapshot, status: status, explanation: explanation, context: context) }
        catch { self.error = error.localizedDescription }
    }
}

private struct SetEditorRequest: Identifiable {
    var id: String { exercise.id + "/" + set.id }
    let exercise: CoachStrengthExercise
    let set: CoachStrengthSet
    let result: CoachSetResult?
}

private struct CoachSetEditor: View {
    @Environment(\.dismiss) private var dismiss
    let request: SetEditorRequest
    let onSave: (CoachSetResult) throws -> Void
    @State private var reps = ""
    @State private var load = ""
    @State private var seconds = ""
    @State private var effort = ""
    @State private var effortScale = "rir"
    @State private var unit = "kg"
    @State private var performedKey = ""
    @State private var equivalent = false
    @State private var notes = ""
    @State private var error: String?
    private var choices: [CoachExerciseChoice] { [request.exercise.exercise] + (request.exercise.substitutions ?? []) }

    var body: some View {
        Form {
            Section("Prescription") {
                Text(CoachStrengthFormatting.prescription(request.set, exercise: request.exercise))
                if let notes = request.set.notes { Text(notes) }
            }
            Section("Performed exercise") {
                Picker("Exercise", selection: $performedKey) { ForEach(choices, id: \.key) { Text($0.name).tag($0.key) } }
                if performedKey != request.exercise.exercise.key {
                    Text("The original prescription stays saved. This choice applies to this actual set.").font(.caption)
                    Toggle("Treat as equivalent for progression", isOn: $equivalent)
                }
            }
            Section("Actual results") {
                TextField("Reps, optional", text: $reps).keyboardType(.numberPad)
                TextField("Load, optional", text: $load).keyboardType(.decimalPad)
                Picker("Load unit", selection: $unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
                Text(request.exercise.loadBasis == .perImplement ? "Record the load of one implement, such as one dumbbell." : "Load basis: \(request.exercise.loadBasis.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Active seconds, optional", text: $seconds).keyboardType(.decimalPad)
                Picker("Effort scale", selection: Binding(get: { effortScale }, set: { value in
                    if effortScale != value { effort = "" }; effortScale = value
                })) { Text("RIR").tag("rir"); Text("RPE").tag("rpe") }
                TextField("Actual \(effortScale.uppercased()), optional", text: $effort).keyboardType(.decimalPad)
                TextField("Set notes", text: $notes, axis: .vertical)
            }
            Section {
                Button("Record Completed Set") { save(.completed) }.accessibilityIdentifier("coach.set.save")
                Button("Skip Set") { save(.skipped) }
                if request.result != nil { Button("Mark Unrecorded") { save(.unlogged) } }
            }
        }
        .navigationTitle("Log Set")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            let result = request.result
            reps = result?.reps.map(String.init) ?? ""
            load = result?.load.map { $0.formatted(.number.grouping(.never)) } ?? ""
            seconds = result?.durationSeconds.map { $0.formatted(.number.grouping(.never)) } ?? ""
            effort = result?.effort.map { $0.formatted(.number.grouping(.never)) } ?? ""
            effortScale = result?.effortScale ?? request.set.effort?.scale.rawValue ?? "rir"
            unit = result?.loadUnit ?? request.set.load?.unit.rawValue ?? "kg"
            performedKey = result?.performedExerciseID ?? request.exercise.exercise.key
            notes = result?.notes ?? ""
            equivalent = result?.substitutionIsEquivalent ?? false
        }
        .alert("Check Actual Values", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func number(_ value: String) throws -> Double? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        let normalized = value.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let number = Double(normalized), number.isFinite, number >= 0 else {
            throw CoachExecutionCoordinator.ExecutionError.invalid("Enter a nonnegative number or leave the field blank.")
        }
        return number
    }
    private func save(_ state: CoachSetResult.State) {
        do {
            let actualReps: Int?
            if reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { actualReps = nil }
            else if let parsed = Int(reps), parsed >= 0, parsed <= 10_000 { actualReps = parsed }
            else { throw CoachExecutionCoordinator.ExecutionError.invalid("Reps must be a whole nonnegative number.") }
            let choice = choices.first { $0.key == performedKey } ?? request.exercise.exercise
            var result = CoachSetResult(id: request.id, exerciseID: request.exercise.id, setID: request.set.id,
                performedExerciseID: choice.key, performedExerciseName: choice.name, equipment: choice.equipment.sorted().joined(separator: ","),
                reps: actualReps, load: try number(load), loadUnit: unit, loadBasis: request.exercise.loadBasis.rawValue,
                repCounting: request.exercise.prescriptionBasis.rawValue, durationSeconds: try number(seconds),
                effortScale: effortScale, effort: try number(effort), notes: notes, state: state, substitutionIsEquivalent: equivalent)
            if state == .unlogged { result.reps = nil; result.load = nil; result.durationSeconds = nil; result.effort = nil }
            guard result.isValid else { throw CoachExecutionCoordinator.ExecutionError.invalid("Effort must be between 0 and 10.") }
            try onSave(result)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct CoachRestTimerView: View {
    let timer: CoachRestTimerState
    let onChange: (CoachRestTimerState?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = Int(ceil(timer.remaining(at: timeline.date)))
                Text(remaining == 0 ? "Rest finished" : String(format: "%d:%02d", remaining / 60, remaining % 60))
                    .font(.largeTitle.monospacedDigit()).accessibilityIdentifier("coach.rest.remaining")
            }
            HStack {
                Button(timer.pausedRemaining == nil ? "Pause" : "Resume") {
                    var updated = timer
                    if timer.pausedRemaining == nil { updated.pause() } else { updated.resume() }
                    onChange(updated)
                }
                Button("−15 sec") { var updated = timer; updated.adjust(by: -15); onChange(updated) }
                Button("+15 sec") { var updated = timer; updated.adjust(by: 15); onChange(updated) }
                Button("Skip") { onChange(nil) }
            }.buttonStyle(.bordered)
        }
    }
}
