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
    @State private var phase: CoachPhase?
    @Query private var phaseReviews: [CoachPhaseReview]

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
                    }
                    if let template {
                        sessionActions(template)
                        if template.kind != "rest", session.executionID == nil, ["pending", "skipped"].contains(session.status) {
                            Section {
                                Button(session.status == "skipped" ? "Undo Skip" : "Skip Session") { toggleSkip() }
                                    .accessibilityIdentifier("coach.session.skip")
                            }
                        }
                        prescriptionSections(template)
                        if let notes = session.notes ?? template.notes, !notes.isEmpty {
                            Section("Session notes") { Text(notes) }
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
                                        Text("\(result.state.rawValue.capitalized) · \(Int(result.activeDuration)) sec · \(result.distanceMeters.map { "\($0.rounded(.towardZero).formatted(.number.grouping(.never).precision(.fractionLength(0)))) m" } ?? "Distance unavailable")")
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
    private func sessionActions(_ value: CoachSessionTemplate) -> some View {
        if value.kind == "rest" {
            Text("Rest has no workout execution and is excluded from training completion.").foregroundStyle(.secondary)
        } else if ["pending", "in_progress"].contains(session.status) {
            Section {
                if session.executionID == nil, let plan = session.plan, plan.status != "active" {
                    Text(plan.status == "draft" ? "This session is saved in your draft plan." : "This plan is \(plan.status).")
                    Text("\(plan.status == "draft" ? "Start" : "Resume") the plan before starting or checking off this session.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink(plan.status == "draft" ? "Start Plan" : "Resume Plan") {
                        CoachProgramDetailView(plan: plan)
                    }
                    .accessibilityIdentifier("coach.session.review_plan")
                } else if session.executionID == nil, let phase, needsPhaseReview, let plan = session.plan {
                    Text("Review \(phase.title) before you start.").font(.headline)
                    Text("Confirm this phase’s sessions and guidance are right for you. Your planned session stays here while you review.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Review Phase") { CoachProgramDetailView(plan: plan) }
                        .accessibilityIdentifier("coach.session.review_phase")
                } else {
                    Button(startTitle(for: value), systemImage: value.kind == "recovery" ? "checkmark.circle" : "play.fill", action: start)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("coach.session.start")
                    if hasActiveRecording {
                        Text("Resume this activity to finish or cancel its recording.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if value.kind != "recovery" {
                        Button("Mark as Done", systemImage: "checkmark.circle") { showingAttestation = true }
                            .accessibilityIdentifier("coach.session.mark_done")
                        Text("Already completed it? Check it off with an explanation. Measurements stay blank.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var needsPhaseReview: Bool {
        guard phase?.advanceMode == .reviewRequired else { return false }
        return !phaseReviews.contains {
            $0.planID == session.plan?.id && $0.phaseID == session.phaseID &&
            $0.revisionID == session.revisionID && $0.statusRaw == "ready"
        }
    }

    private var hasActiveRecording: Bool {
        RunTracker.shared.hasRecoverableActivity && RunTracker.shared.plannedTarget?.canonicalOccurrenceID == session.id
    }

    private func startTitle(for value: CoachSessionTemplate) -> String {
        if value.kind == "recovery" { return "Mark as Done" }
        let action = session.status == "in_progress" ? "Resume" : "Start"
        switch value.kind {
        case "strength": return "\(action) Workout"
        case "running": return "\(action) Run"
        default: return "\(action) Activity"
        }
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
            phase = nil
            if let revisionID = session.revisionID,
               let revision = try context.fetch(FetchDescriptor<CoachPlanRevision>(predicate: #Predicate { $0.id == revisionID })).first {
                phase = try JSONDecoder().decode(CoachPlanDocument.self, from: revision.documentData).phases.first { $0.id == session.phaseID }
            }
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
            guard !hasActiveRecording else {
                error = "Resume this activity to finish or cancel its recording before checking it off."
                return
            }
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
