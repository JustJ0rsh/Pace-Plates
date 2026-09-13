import SwiftUI
import SwiftData

struct CoachSessionDetailView: View {
    @Environment(\.modelContext) private var context
    let session: PlannedSession
    @State private var execution: CoachSessionExecution?
    @State private var template: CoachSessionTemplate?
    @State private var runTarget: ScheduledRunTarget?
    @State private var showingRun = false
    @State private var error: String?
    @State private var explanation = ""
    @State private var showingAttestation = false

    var body: some View {
        Group {
            if let execution, case let .strength(strength) = template {
                CoachStrengthExecutionView(execution: execution, prescription: strength, guidanceNotes: session.notes)
            } else {
                List {
                    Section {
                        Text(session.title).font(.title2.bold())
                        Text(session.currentCivilDate ?? session.scheduledDate.formatted(date: .abbreviated, time: .omitted))
                        Text(session.status.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
                        if let notes = session.notes ?? template?.notes, !notes.isEmpty { Text(notes) }
                    }
                    if let template {
                        prescriptionSections(template)
                        if template.kind != "rest", ["pending", "in_progress"].contains(session.status) {
                            Section {
                                Button(session.status == "in_progress" ? "Resume Session" : "Start Session", systemImage: "play.fill", action: start)
                                    .accessibilityIdentifier("coach.session.start")
                                Button("Record completion without logs") { showingAttestation = true }
                            }
                        } else if template.kind == "rest" {
                            Text("Rest has no workout execution and is excluded from training completion.").foregroundStyle(.secondary)
                        }
                        if template.kind != "rest", session.executionID == nil, ["pending", "skipped"].contains(session.status) {
                            Section {
                                Button(session.status == "skipped" ? "Undo Skip" : "Skip Session") { toggleSkip() }
                                    .accessibilityIdentifier("coach.session.skip")
                            }
                        }
                        if let execution, let data = execution.snapshotData,
                           let snapshot = try? JSONDecoder().decode(CoachExecutionSnapshot.self, from: data),
                           let intervals = snapshot.intervalState {
                            Section("Recorded intervals") {
                                if let runID = execution.runSessionID, let run = try? context.fetch(FetchDescriptor<RunningSession>(predicate: #Predicate { $0.id == runID })).first {
                                    NavigationLink("Review or edit actual interval measurements") { CoachSavedRunResultsView(session: run) }
                                }
                                ForEach(intervals.results) { result in
                                    VStack(alignment: .leading) {
                                        Text(intervals.steps.first(where: { $0.id == result.stepID })?.label ?? "Interval")
                                        Text("\(result.state.rawValue.capitalized) · \(Int(result.activeDuration)) sec · \(result.distanceMeters.map { "\(Int($0)) m" } ?? "Distance unavailable")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("This older plan uses the original workout or running screen. Its saved history is preserved.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(isPresented: $showingRun, onDismiss: load) {
            if let runTarget {
                NavigationStack { RunTrackingProView(activityType: trackerActivityType, plannedTarget: runTarget) }
            }
        }
        .alert("Record Completion", isPresented: $showingAttestation) {
            TextField("What did you complete?", text: $explanation)
            Button("Cancel", role: .cancel) {}
            Button("Record") { attest() }.disabled(explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { Text("This records your explanation without inventing any reps, load, distance, or calories.") }
        .alert("Coach", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    @ViewBuilder
    private func prescriptionSections(_ value: CoachSessionTemplate) -> some View {
        switch value {
        case let .strength(strength):
            ForEach(strength.exercises) { exercise in
                Section(exercise.exercise.name) {
                    if let notes = exercise.notes { Text(notes) }
                    ForEach(exercise.sets) { set in Text(CoachStrengthFormatting.prescription(set, exercise: exercise)) }
                }
            }
        case .running, .cardio:
            if let steps = try? CoachExecutionCoordinator.runSteps(value) {
                Section("Intervals") {
                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.label).font(.headline)
                            Text(step.targetSeconds.map { "\(Int($0)) sec" } ?? step.targetMeters.map { "\(Int($0)) m" } ?? "Manual")
                            if let guidance = step.guidance { Text(guidance).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        case let .recovery(recovery):
            Section("Recovery") {
                Text(recovery.instructions)
                if let seconds = recovery.durationSeconds { Text("\(seconds / 60) minutes suggested") }
            }
        case .rest: EmptyView()
        }
    }

    private var trackerActivityType: String {
        if template?.kind == "running" { return "running" }
        guard let template, let steps = try? CoachSchedule.steps(for: template) else { return "other" }
        let activities = steps.filter { $0.section == "main" }.compactMap { item -> CoachActivity? in
            if case let .segment(segment) = item.payload { return segment.activity }; return nil
        }
        guard Set(activities.map(\.rawValue)).count == 1 else { return "other" }
        switch activities.first {
        case .walk: return "walking"
        case .run, .jog: return "running"
        case .cycle: return "cycling"
        case .row: return "rowing"
        case .swim: return "swimming"
        case .elliptical: return "elliptical"
        default: return "other"
        }
    }
    private func load() {
        do {
            if let data = session.prescriptionData { template = try JSONDecoder().decode(CoachSessionTemplate.self, from: data) }
            if let executionID = session.executionID {
                execution = try context.fetch(FetchDescriptor<CoachSessionExecution>(predicate: #Predicate { $0.id == executionID })).first
                if let data = execution?.prescriptionData { template = try JSONDecoder().decode(CoachSessionTemplate.self, from: data) }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func start() {
        do {
            guard let template else { return }
            switch template {
            case .strength: execution = try CoachExecutionCoordinator.startStrength(session, context: context)
            case .running, .cardio:
                let tracker = RunTracker.shared
                guard !tracker.hasRecoverableActivity || tracker.plannedTarget?.canonicalOccurrenceID == session.id else {
                    error = "Another activity is in progress. Resume or finish that activity first."
                    return
                }
                execution = try CoachRepository(context: context).beginExecution(occurrenceID: session.id)
                if let execution { runTarget = try CoachExecutionCoordinator.runTarget(session, execution: execution); showingRun = true }
            case .recovery: showingAttestation = true
            case .rest: break
            }
        } catch { self.error = error.localizedDescription }
    }
    private func attest() {
        do {
            let record = try CoachRepository(context: context).beginExecution(occurrenceID: session.id)
            try CoachRepository(context: context).finishExecution(executionID: record.id, status: .completed,
                notes: explanation, provenance: "manual_attestation")
            execution = record
        } catch { self.error = error.localizedDescription }
    }
    private func toggleSkip() {
        do {
            try CoachRepository(context: context).markSession(id: session.id, status: session.status == "skipped" ? .pending : .skipped)
            load()
        } catch { self.error = error.localizedDescription }
    }
}

enum CoachStrengthFormatting {
    static func prescription(_ set: CoachStrengthSet, exercise: CoachStrengthExercise) -> String {
        let target: String
        switch set.target { case let .reps(minimum, maximum): target = minimum == maximum ? "\(minimum) reps" : "\(minimum)–\(maximum) reps"
        case let .duration(seconds): target = "\(seconds) sec" }
        var parts = [set.role.rawValue.capitalized, target]
        if exercise.prescriptionBasis == .perSide { parts.append("per side") }
        if let load = set.load { parts.append("\(load.value.formatted()) \(load.unit.rawValue) · \(exercise.loadBasis.rawValue)") }
        else { parts.append("Load unspecified") }
        if let effort = set.effort { parts.append("\(effort.scale.rawValue.uppercased()) \(effort.min.formatted())–\(effort.max.formatted())") }
        if let rest = set.restAfterSeconds { parts.append("Rest \(rest) sec") }
        return parts.joined(separator: " · ")
    }
    static func actual(_ result: CoachSetResult) -> String {
        var parts: [String] = []
        if let reps = result.reps { parts.append("\(reps) reps") }
        if let load = result.load { parts.append("\(load.formatted()) \(result.loadUnit ?? "")") }
        if let duration = result.durationSeconds { parts.append("\(duration.formatted()) sec") }
        if let effort = result.effort { parts.append("\(result.effortScale?.uppercased() ?? "Effort") \(effort.formatted())") }
        if parts.isEmpty { parts.append("No measurements entered") }
        return parts.joined(separator: " · ")
    }
}
