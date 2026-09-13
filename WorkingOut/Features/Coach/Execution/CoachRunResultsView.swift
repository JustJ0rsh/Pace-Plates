import SwiftUI
import SwiftData

struct CoachRunResultsView: View {
    let state: CoachRunIntervalState
    let onSave: (CoachRunIntervalResult) throws -> Void
    @State private var edited: CoachRunIntervalResult?
    @State private var replacements: [String: CoachRunIntervalResult] = [:]
    var body: some View {
        List {
            ForEach(state.results) { original in
                let result = replacements[original.id] ?? original
                Button { edited = result } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.steps.first(where: { $0.id == result.stepID })?.label ?? "Interval").font(.headline)
                        Text("\(result.state.rawValue.capitalized) · \(Int(result.activeDuration)) active sec")
                        Text(result.distanceMeters.map { "\($0.formatted()) meters · \(result.measurementSource)" } ?? "Distance unavailable")
                        if let pace = result.paceSecondsPerKilometer { Text("\(Int(pace)) sec/km").font(.caption) }
                        if let effort = result.effort { Text("\(result.effortScale?.uppercased() ?? "Effort") \(effort.formatted())").font(.caption) }
                    }.foregroundStyle(.primary)
                }
            }
            if state.results.isEmpty { Text("Complete an interval to review its actual measurements.") }
            Text("Editing a measurement preserves the original interval target and completion method.").font(.caption).foregroundStyle(.secondary)
        }
        .navigationTitle("Interval Results")
        .sheet(item: $edited) { result in
            NavigationStack {
                CoachIntervalResultEditor(result: result) { updated in
                    try onSave(updated)
                    replacements[updated.id] = updated
                }
            }
        }
    }
}

struct CoachSavedRunResultsView: View {
    @Environment(\.modelContext) private var context
    let session: RunningSession
    @State private var state: CoachRunIntervalState?
    @State private var error: String?
    var body: some View {
        Group {
            if let state { CoachRunResultsView(state: state, onSave: save) }
            else { ContentUnavailableView("Interval Results", systemImage: "figure.run", description: Text(error ?? "No structured interval results were recorded for this activity.")) }
        }.task {
            do { if let data = session.intervalResultsData { state = try JSONDecoder().decode(CoachRunIntervalState.self, from: data) } }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(_ result: CoachRunIntervalResult) throws {
        try CoachRepository(context: context).requireLocal()
        guard let data = session.intervalResultsData else { throw CoachRepositoryError.missingRecord }
        var current = try JSONDecoder().decode(CoachRunIntervalState.self, from: data)
        guard let index = current.results.firstIndex(where: { $0.id == result.id }) else { throw CoachRepositoryError.missingRecord }
        current.results[index] = result
        guard current.isValid else { throw CoachRepositoryError.invalidValue("interval measurement") }
        session.intervalResultsData = try JSONEncoder().encode(current)
        if let id = session.coachExecutionID,
           let execution = try context.fetch(FetchDescriptor<CoachSessionExecution>(predicate: #Predicate { $0.id == id })).first {
            var snapshot = try CoachExecutionCoordinator.snapshot(execution)
            snapshot.intervalState = current
            try CoachExecutionCoordinator.save(snapshot, execution: execution, context: context)
        } else { try context.save() }
        state = current
    }
}

private struct CoachIntervalResultEditor: View {
    @Environment(\.dismiss) private var dismiss
    let result: CoachRunIntervalResult
    let onSave: (CoachRunIntervalResult) throws -> Void
    @State private var distance: Double?
    @State private var effort: Double?
    @State private var scale = "rpe"
    @State private var error: String?
    var body: some View {
        Form {
            LabeledContent("Recorded active time", value: "\(Int(result.activeDuration)) sec")
            TextField("Actual distance, meters (optional)", value: $distance, format: .number).keyboardType(.decimalPad)
            Picker("Effort scale", selection: Binding(get: { scale }, set: { value in
                if scale != value { effort = nil }; scale = value
            })) { Text("RPE").tag("rpe"); Text("RIR").tag("rir") }
            TextField("Actual \(scale.uppercased()) (optional)", value: $effort, format: .number).keyboardType(.decimalPad)
            Button("Save Actual Measurements") {
                do {
                    guard distance.map({ $0.isFinite && $0 >= 0 }) ?? true, effort.map({ $0.isFinite && (0...10).contains($0) }) ?? true else { throw CoachRepositoryError.invalidValue("nonnegative distance and effort from 0 to 10") }
                    var updated = result
                    if distance != result.distanceMeters { updated.measurementSource = distance == nil ? "active_clock" : "manual" }
                    updated.distanceMeters = distance; updated.effort = effort; updated.effortScale = effort == nil ? nil : scale
                    try onSave(updated); dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }
        .navigationTitle("Interval Actuals")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { distance = result.distanceMeters; scale = result.effortScale ?? "rpe"; effort = result.effort }
        .alert("Unable to Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
