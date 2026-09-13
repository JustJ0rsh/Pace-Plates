import SwiftUI
import SwiftData

struct CoachProgressionReviewView: View {
    @Environment(\.modelContext) private var context
    var execution: CoachSessionExecution? = nil
    var plan: TrainingPlan? = nil
    @State private var suggestions: [CoachProgressionSuggestion] = []
    @State private var holds: [String] = []
    @State private var selected: CoachProgressionSuggestion?
    @State private var resolvedPlan: TrainingPlan?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("Progression is reviewed before it changes a future prescription. Past targets and actual results stay saved.").font(.subheadline)
            }
            if suggestions.isEmpty { ContentUnavailableView("No load change ready", systemImage: "chart.line.uptrend.xyaxis", description: Text("Record comparable sessions and actual effort, then return here.")) }
            ForEach(suggestions) { suggestion in
                Button {
                    if suggestion.statusRaw == "pending" { selected = suggestion }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(suggestion.reason).foregroundStyle(.primary)
                        Text(suggestion.statusRaw.capitalized).font(.caption).foregroundStyle(.secondary)
                        if let proposal = try? JSONDecoder().decode(CoachProgressionProposal.self, from: suggestion.proposedPrescriptionData) {
                            ForEach(proposal.newLoads.keys.sorted(), id: \.self) { setID in
                                if let load = proposal.newLoads[setID] { Text("Set \(setID): \(load.value.formatted()) \(load.unit.rawValue)").font(.caption) }
                            }
                            Text("Evidence: \(proposal.evidenceIDs.count) completed sessions").font(.caption)
                        }
                    }
                }.disabled(suggestion.statusRaw != "pending")
            }
            if !holds.isEmpty {
                Section("Review notes") { ForEach(holds, id: \.self) { Text($0).font(.subheadline) } }
            }
        }
        .navigationTitle("Review Progression")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise", action: refresh) }
        .task { refresh() }
        .sheet(item: $selected, onDismiss: refresh) { suggestion in
            NavigationStack { CoachProgressionDecisionView(suggestion: suggestion, plan: resolvedPlan) }
        }
        .alert("Progression", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private func refresh() {
        do {
            if let plan { resolvedPlan = plan }
            else if let occurrenceID = execution?.plannedSessionID {
                resolvedPlan = try context.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == occurrenceID })?.plan
            }
            guard let resolvedPlan else { holds = ["The original plan is unavailable. Actual workout history remains saved."]; return }
            let result = try CoachProgressionEvaluator.generate(plan: resolvedPlan, context: context)
            suggestions = result.suggestions; holds = result.holds
        } catch { self.error = error.localizedDescription }
    }
}

private struct CoachProgressionDecisionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let suggestion: CoachProgressionSuggestion
    let plan: TrainingPlan?
    @State private var proposal: CoachProgressionProposal?
    @State private var future: [PlannedSession] = []
    @State private var evidence: [CoachProgressionEvidence] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var increment: Double = 0
    @State private var confirmedPerImplement = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Reason") { Text(suggestion.reason) }
            Section("Evidence") {
                ForEach(evidence, id: \.executionID) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.endedAt, format: .dateTime.month().day().year())
                        Text("Pain feedback: \(item.painScore.map { String($0) } ?? "Unknown") · Phase readiness: \(item.readinessReviewed == true ? "Reviewed" : "Needs review")").font(.caption)
                        ForEach(item.results.filter { $0.exerciseID == proposal?.exerciseID }) { result in
                            Text(CoachStrengthFormatting.actual(result)).font(.caption)
                        }
                    }
                }
            }
            if let proposal {
                Section("Available equipment") {
                    TextField("Load increment (\(proposal.increment.unit.rawValue))", value: $increment, format: .number).keyboardType(.decimalPad)
                    if proposal.loadBasis == .perImplement { Toggle("This load and increment are per implement (per hand for dumbbells)", isOn: $confirmedPerImplement) }
                }
            }
            Section("Select future sessions") {
                if future.isEmpty { Text("No matching unstarted future sessions remain.") }
                ForEach(future) { occurrence in
                    Toggle(isOn: Binding(get: { selectedIDs.contains(occurrence.id) }, set: { value in
                        if value { selectedIDs.insert(occurrence.id) } else { selectedIDs.remove(occurrence.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(occurrence.title)
                            Text(occurrence.currentCivilDate ?? occurrence.scheduledDate.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                        }
                    }
                }
            }
            Section {
                Button("Accept for \(selectedIDs.count) selected sessions") {
                    do {
                        try CoachProgressionEvaluator.accept(suggestionID: suggestion.id, selectedIDs: selectedIDs,
                            increment: increment, confirmedPerImplement: confirmedPerImplement, context: context)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.disabled(selectedIDs.isEmpty || increment <= 0).accessibilityIdentifier("coach.progression.accept")
                Button("Dismiss Suggestion", role: .destructive) {
                    do {
                        try CoachRepository(context: context).transaction { isolated in
                            let id = suggestion.id
                            guard let row = try isolated.fetch(FetchDescriptor<CoachProgressionSuggestion>(predicate: #Predicate { $0.id == id })).first else { throw CoachRepositoryError.missingRecord }
                            row.statusRaw = "dismissed"; row.decidedAt = Date()
                        }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
        .navigationTitle("Review Change")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task {
            do {
                proposal = try JSONDecoder().decode(CoachProgressionProposal.self, from: suggestion.proposedPrescriptionData)
                increment = proposal?.increment.value ?? 0
                evidence = try CoachProgressionEvaluator.evidence(context: context, planID: suggestion.planID).filter { proposal?.evidenceIDs.contains($0.executionID) == true }
                let zone = plan.map(CoachRepository.timeZone) ?? .current
                let today = CoachSchedule.civilDate(Date(), timeZone: zone)
                future = try context.fetch(FetchDescriptor<PlannedSession>()).filter {
                    $0.plan?.id == suggestion.planID && $0.status == "pending" && $0.executionID == nil && !$0.localScheduleOverride && $0.sourceTemplateID == suggestion.sourceTemplateID && ($0.currentCivilDate ?? "") >= today
                }.sorted { $0.scheduledDate < $1.scheduledDate }
            } catch { self.error = error.localizedDescription }
        }
        .alert("Unable to Apply Change", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
