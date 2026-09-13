import SwiftUI
import SwiftData

enum CoachCheckInDestination: Identifiable {
    case nutrition(Date), recovery(Date)
    var date: Date { switch self { case let .nutrition(date), let .recovery(date): date } }
    var isNutrition: Bool { if case .nutrition = self { return true }; return false }
    var id: String { (isNutrition ? "nutrition:" : "recovery:") + CoachDate.civil(date) }
}

struct CoachCheckInView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let destination: CoachCheckInDestination
    @State private var date: Date
    @State private var recordID: UUID?
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var sleep = ""
    @State private var soreness = ""
    @State private var energy = ""
    @State private var pain = ""
    @State private var painLocation = ""
    @State private var notes = ""
    @State private var target: CoachNutritionTargets?
    @State private var isFinal = false
    @State private var error: String?
    @State private var saved: String?
    @State private var showTargets = false
    @State private var showCorrection = false
    @State private var loadedFields: [String] = []
    @State private var pendingDate: Date?
    @State private var suppressDateChange = false
    @State private var confirmDateChange = false
    @State private var confirmClose = false
    @State private var loadingHealth = false
    @State private var healthOptions: [HealthKitManager.CoachSleepObservation] = []
    @State private var selectedHealthSource = ""
    @State private var savedHealthHours: Double?
    @State private var savedHealthSource: String?
    @State private var savedHealthCoverage: HealthKitManager.CoachSleepCoverage?

    init(destination: CoachCheckInDestination) {
        self.destination = destination
        _date = State(initialValue: destination.date)
    }
    private var repository: CoachRepository { CoachRepository(context: ModelContext(modelContext.container)) }
    private var fields: [String] { [calories, protein, carbs, fat, sleep, soreness, energy, pain, painLocation, notes] }
    private var hasUnsavedChanges: Bool { fields != loadedFields }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(destination.isNutrition ? "Day" : "Wake / check-in day", selection: $date, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("coach.checkin.date")
                    Text("Select a date to open that day's entry. Blank fields stay unknown; an entered zero stays zero.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if destination.isNutrition { nutritionFields } else { recoveryFields }
                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3...6) }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.checkin.error") } }
                if let saved { Section { Label(saved, systemImage: "checkmark.circle.fill").foregroundStyle(.green).accessibilityIdentifier("coach.checkin.saved") } }
                Section {
                    Button(destination.isNutrition ? "Save Draft" : "Save Check-in") { save(final: false) }
                        .accessibilityIdentifier(destination.isNutrition ? "coach.nutrition.save" : "coach.recovery.save")
                    if destination.isNutrition {
                        Button("Mark Day Finished") { save(final: true) }
                            .accessibilityIdentifier("coach.nutrition.finish")
                    }
                    if recordID != nil {
                        Button("Correct Saved Entry Date") { showCorrection = true }.disabled(hasUnsavedChanges)
                        if hasUnsavedChanges { Text("Save your edits before correcting the saved entry date.").font(.caption).foregroundStyle(.secondary) }
                        Button("Delete This Check-in", role: .destructive) { delete() }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle(destination.isNutrition ? "Nutrition" : "Recovery")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if hasUnsavedChanges { confirmClose = true } else { dismiss() } } } }
            .task { load() }
            .onChange(of: fields) { _, _ in if hasUnsavedChanges { saved = nil } }
            .onChange(of: date) { previous, selected in
                if suppressDateChange { suppressDateChange = false; return }
                if hasUnsavedChanges {
                    pendingDate = selected; suppressDateChange = true; date = previous; confirmDateChange = true
                } else { load() }
            }
            .confirmationDialog("Unsaved check-in changes", isPresented: $confirmDateChange, titleVisibility: .visible) {
                Button("Discard Edits and Open Selected Day", role: .destructive) {
                    loadedFields = fields
                    if let pendingDate { date = pendingDate }
                    pendingDate = nil
                }
                Button("Keep Editing", role: .cancel) { pendingDate = nil }
            } message: { Text("Your current edits have not been saved.") }
            .confirmationDialog("Unsaved check-in changes", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("Discard Edits and Close", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: { Text("Save the check-in to retain your edits before closing.") }
            .sheet(isPresented: $showTargets, onDismiss: refreshTarget) { CoachNutritionTargetEditor() }
            .sheet(isPresented: $showCorrection, onDismiss: { load() }) {
                if let recordID { CoachDailyDateCorrectionView(sourceID: recordID, isNutrition: destination.isNutrition, originalDate: date) }
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges)
    }

    private var nutritionFields: some View {
        Group {
            Section(isFinal ? "Daily totals · Finished" : "Daily totals · Draft") {
                CoachOptionalNumberField("Calories", unit: "kcal", text: $calories)
                CoachOptionalNumberField("Protein", unit: "g", text: $protein)
                CoachOptionalNumberField("Carbohydrate", unit: "g", text: $carbs)
                CoachOptionalNumberField("Fat", unit: "g", text: $fat)
                if let warning = macroWarning { Text(warning).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Targets for this day") {
                if let target {
                    targetRow("Calories", target: target.caloriesKcal.map(Double.init), actual: try? CoachEntryNumber.optional(calories), unit: "kcal")
                    targetRow("Protein", target: target.proteinGrams, actual: try? CoachEntryNumber.optional(protein), unit: "g")
                    targetRow("Carbohydrate", target: target.carbohydrateGrams, actual: try? CoachEntryNumber.optional(carbs), unit: "g")
                    targetRow("Fat", target: target.fatGrams, actual: try? CoachEntryNumber.optional(fat), unit: "g")
                    if let notes = target.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                    Text("Saved days keep the target that applied when first logged.").font(.caption).foregroundStyle(.secondary)
                } else { Text("No targets set for this day.").foregroundStyle(.secondary) }
                Button("Edit Targets from an Effective Date") { showTargets = true }
            }
        }
    }
    private func targetRow(_ title: String, target: Double?, actual: Double?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title); Spacer(); Text(target.map { "\(CoachEntryNumber.text($0)) \(unit)" } ?? "Not set").foregroundStyle(.secondary) }
            if let target, let actual {
                Text("Actual \(CoachEntryNumber.text(actual)) · Difference \(actual - target >= 0 ? "+" : "")\(CoachEntryNumber.text(actual - target)) \(unit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func refreshTarget() {
        do {
            if let row = try repository.nutritionLogs().first(where: { $0.civilDate == CoachDate.civil(date) }) {
                target = try row.targetSnapshotData.map { try JSONDecoder().decode(CoachNutritionTargets.self, from: $0) }
            } else if let period = try repository.nutritionTarget(on: date) {
                target = .init(caloriesKcal: period.calories.map { Int($0.rounded()) }, proteinGrams: period.protein, carbohydrateGrams: period.carbs, fatGrams: period.fat, notes: period.notes)
            } else { target = nil }
        } catch { self.error = error.localizedDescription }
    }
    private var recoveryFields: some View {
        Group {
            Section("Sleep") {
                CoachOptionalNumberField("Manual sleep", unit: "hours", text: $sleep)
                Text("Manual hours take precedence for this day. Health sleep stays separate and is never added to your entry.").font(.caption).foregroundStyle(.secondary)
                if let hours = savedHealthHours {
                    LabeledContent("Health sleep", value: "\(CoachEntryNumber.text(hours)) hours")
                    Text(savedHealthSource ?? "Health").font(.caption).foregroundStyle(.secondary)
                } else { Text("Health sleep: Not available").foregroundStyle(.secondary) }
                if let coverage = savedHealthCoverage {
                    Text("Main episode ended \(coverage.episodeEnd.formatted(date: .abbreviated, time: .shortened)); \(coverage.sampleCount) samples across \(coverage.intervalCount) non-overlapping intervals.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !coverage.additionalEpisodeHours.isEmpty {
                        Text("Other episodes / naps: \(coverage.additionalEpisodeHours.map { CoachEntryNumber.text($0) + " h" }.joined(separator: ", ")). These are not added to the main sleep duration.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if healthOptions.count > 1 {
                    Picker("Health source", selection: $selectedHealthSource) {
                        ForEach(healthOptions) { Text($0.sourceName).tag($0.id) }
                    }.onChange(of: selectedHealthSource) { _, _ in selectHealthSource() }
                }
                Button { Task { await refreshHealth() } } label: {
                    if loadingHealth { ProgressView("Reading this day's sleep…") }
                    else { Label("Refresh Sleep from Apple Health", systemImage: "heart.text.clipboard") }
                }.disabled(loadingHealth)
                Text("Sleep belongs to the day you woke, including daytime sleep. No readable data does not imply zero sleep or a denied permission.").font(.caption).foregroundStyle(.secondary)
            }
            Section("How you feel") {
                CoachOptionalNumberField("Soreness", unit: "0–10", text: $soreness, integer: true)
                CoachOptionalNumberField("Energy", unit: "1–5", text: $energy, integer: true)
                CoachOptionalNumberField("Pain", unit: "0–10", text: $pain, integer: true)
                TextField("Pain location (optional)", text: $painLocation)
                Text("An empty pain field means unreported. Enter 0 only when documenting no pain.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var macroWarning: String? {
        guard let c = try? CoachEntryNumber.optional(calories), let p = try? CoachEntryNumber.optional(protein),
              let carb = try? CoachEntryNumber.optional(carbs), let f = try? CoachEntryNumber.optional(fat),
              abs(c - (4 * p + 4 * carb + 9 * f)) > max(100, c * 0.1) else { return nil }
        return "Calories and macro-derived calories differ. Review your entry if useful; food-label differences are allowed and your values will be retained."
    }
    private func load() {
        saved = nil; error = nil; healthOptions = []; selectedHealthSource = ""
        do {
            let key = CoachDate.civil(date)
            if destination.isNutrition {
                let rows = try repository.nutritionLogs().filter { $0.civilDate == key }
                guard rows.count <= 1 else { throw CoachRepositoryError.dateCollision }
                let row = rows.first
                recordID = row?.id; calories = CoachEntryNumber.input(row?.calories); protein = CoachEntryNumber.input(row?.protein)
                carbs = CoachEntryNumber.input(row?.carbs); fat = CoachEntryNumber.input(row?.fat); notes = row?.notes ?? ""; isFinal = row?.statusRaw == "final"
                if let data = row?.targetSnapshotData { target = try JSONDecoder().decode(CoachNutritionTargets.self, from: data) }
                else if row != nil { target = nil }
                else if let period = try repository.nutritionTarget(on: date) {
                    target = .init(caloriesKcal: period.calories.map { Int($0.rounded()) }, proteinGrams: period.protein, carbohydrateGrams: period.carbs, fatGrams: period.fat, notes: period.notes)
                } else { target = nil }
            } else {
                let rows = try repository.recoveryLogs().filter { $0.civilDate == key }
                guard rows.count <= 1 else { throw CoachRepositoryError.dateCollision }
                let row = rows.first
                recordID = row?.id; sleep = CoachEntryNumber.input(row?.manualSleepHours); soreness = row?.soreness.map(String.init) ?? ""
                energy = row?.energy.map(String.init) ?? ""; pain = row?.painScore.map(String.init) ?? ""; painLocation = row?.painLocation ?? ""; notes = row?.notes ?? ""
                savedHealthHours = row?.healthSleepHours; savedHealthSource = row?.healthSleepSource
                savedHealthCoverage = try row?.healthSampleCoverageData.map { try JSONDecoder().decode(HealthKitManager.CoachSleepCoverage.self, from: $0) }
            }
            loadedFields = fields
        } catch { self.error = error.localizedDescription }
    }
    private func save(final: Bool) {
        do {
            if destination.isNutrition {
                recordID = try repository.saveNutrition(date: date, calories: CoachEntryNumber.optional(calories), protein: CoachEntryNumber.optional(protein), carbs: CoachEntryNumber.optional(carbs), fat: CoachEntryNumber.optional(fat), notes: CoachEntryNumber.note(notes), isFinal: final, id: recordID)
                isFinal = final
            } else {
                recordID = try repository.saveRecovery(date: date, manualSleepHours: CoachEntryNumber.optional(sleep), soreness: CoachEntryNumber.integer(soreness), energy: CoachEntryNumber.integer(energy), painScore: CoachEntryNumber.integer(pain), painLocation: CoachEntryNumber.note(painLocation), notes: CoachEntryNumber.note(notes), id: recordID)
            }
            loadedFields = fields
            error = nil; saved = "Saved for \(date.formatted(date: .abbreviated, time: .omitted))"
            if destination.isNutrition { refreshTarget() }
        } catch { self.error = error.localizedDescription; saved = nil }
    }
    private func delete() {
        guard let recordID else { return }
        do {
            if destination.isNutrition { try repository.deleteNutrition(id: recordID) }
            else { try repository.deleteRecovery(id: recordID) }
            load(); saved = "Check-in deleted"
        } catch { self.error = error.localizedDescription }
    }
    private func refreshHealth() async {
        let selectedDate = date
        let generation = WearableWorkoutInboxService.localDataPurgeGeneration
        loadingHealth = true
        defer { loadingHealth = false }
        do {
            let result = try await HealthKitManager.shared.coachSleep(on: selectedDate, requestAccess: true)
            guard !Task.isCancelled, CoachDate.civil(selectedDate) == CoachDate.civil(date), WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(generation) else { return }
            healthOptions = result
            selectedHealthSource = result.first(where: { $0.id == savedHealthCoverage?.sourceIdentifier })?.id ?? result.first?.id ?? ""
            if result.isEmpty {
                try repository.saveHealthSleep(date: date, hours: nil, source: nil, endDate: nil, coverageData: nil)
                savedHealthHours = nil; savedHealthSource = nil; savedHealthCoverage = nil
            } else { selectHealthSource() }
        } catch { self.error = "Sleep could not be refreshed. Your manual entry is preserved. \(error.localizedDescription)" }
    }
    private func selectHealthSource() {
        guard let option = healthOptions.first(where: { $0.id == selectedHealthSource }) else { return }
        do {
            try repository.saveHealthSleep(date: date, hours: option.hours, source: option.sourceName, endDate: option.endDate, coverageData: JSONEncoder().encode(option.coverage))
            savedHealthHours = option.hours; savedHealthSource = option.sourceName; savedHealthCoverage = option.coverage
        } catch { self.error = error.localizedDescription }
    }
}

struct CoachOptionalNumberField: View {
    let title: String
    let unit: String
    @Binding var text: String
    var integer = false
    init(_ title: String, unit: String, text: Binding<String>, integer: Bool = false) {
        self.title = title; self.unit = unit; self._text = text; self.integer = integer
    }
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("Not entered", text: $text).multilineTextAlignment(.trailing)
                .keyboardType(integer ? .numberPad : .decimalPad).frame(minWidth: 90, maxWidth: 160)
                .accessibilityLabel(title)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

enum CoachEntryNumber {
    static func optional(_ text: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.range(of: "^[0-9]+([.,][0-9]+)?([eE][+-]?[0-9]+)?$", options: .regularExpression) != nil,
              let result = Double(value.replacingOccurrences(of: ",", with: ".")), result.isFinite else { throw CoachRepositoryError.invalidValue("finite number using digits and an optional decimal separator") }
        if result == 0, value.split(whereSeparator: { $0 == "e" || $0 == "E" }).first?.contains(where: { "123456789".contains($0) }) == true {
            throw CoachRepositoryError.invalidValue("number large enough to represent without losing its value")
        }
        return result
    }
    static func integer(_ text: String) throws -> Int? {
        guard let number = try optional(text) else { return nil }
        guard number >= 0, number <= Double(Int.max / 2), number.rounded() == number else { throw CoachRepositoryError.invalidValue("whole number") }
        return Int(number)
    }
    static func input(_ value: Double?) -> String { value.map { String($0) } ?? "" }
    static func text(_ value: Double?) -> String {
        value.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) } ?? ""
    }
    static func note(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct CoachNutritionTargetEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective from", selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    Text("This replaces the complete target block from the selected day. Saved check-ins retain their original target snapshots.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Targets") {
                    CoachOptionalNumberField("Calories", unit: "kcal", text: $calories, integer: true)
                    CoachOptionalNumberField("Protein", unit: "g", text: $protein)
                    CoachOptionalNumberField("Carbohydrate", unit: "g", text: $carbs)
                    CoachOptionalNumberField("Fat", unit: "g", text: $fat)
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle("Nutrition Targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try CoachRepository(context: modelContext).saveNutritionTarget(date: date, calories: CoachEntryNumber.integer(calories).map(Double.init), protein: CoachEntryNumber.optional(protein), carbs: CoachEntryNumber.optional(carbs), fat: CoachEntryNumber.optional(fat), notes: CoachEntryNumber.note(notes))
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .task {
                do {
                    if let target = try CoachRepository(context: modelContext).nutritionTarget(on: date) {
                        calories = CoachEntryNumber.input(target.calories); protein = CoachEntryNumber.input(target.protein)
                        carbs = CoachEntryNumber.input(target.carbs); fat = CoachEntryNumber.input(target.fat); notes = target.notes ?? ""
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

private struct CoachDailyMergeField: Identifiable {
    let id: String
    let title: String
    let source: String
    let destination: String?
    var merged: String
    var reviewed: Bool
}

private struct CoachDailyDateCorrectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let sourceID: UUID
    let isNutrition: Bool
    let originalDate: Date
    @State private var date = Date()
    @State private var fields: [CoachDailyMergeField] = []
    @State private var expectedSourceUpdatedAt: Date?
    @State private var expectedDestinationID: UUID?
    @State private var expectedDestinationUpdatedAt: Date?
    @State private var target: CoachNutritionTargets?
    @State private var final = false
    @State private var prepared = false
    @State private var error: String?
    private var repository: CoachRepository { CoachRepository(context: ModelContext(context.container)) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Move the saved entry from \(CoachDate.civil(originalDate)).")
                    DatePicker("Corrected day", selection: $date, in: ...Date(), displayedComponents: .date)
                    Button("Preview Date Correction", action: preview).disabled(CoachDate.civil(date) == CoachDate.civil(originalDate))
                }
                if prepared {
                    Section(expectedDestinationID == nil ? "Review moved values" : "Merge with the existing day") {
                        Text(isNutrition ? "Review each final value. Totals are replaced, never added. The source entry is removed only after this correction saves successfully." : "Review each final manual value. Values are replaced, never added. Health sleep stays on its measured day; a source Health-only record remains when needed.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(fields.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(fields[index].title).font(.headline)
                                Text("Source: \(fields[index].source.isEmpty ? "Not entered" : fields[index].source)").font(.caption)
                                if let value = fields[index].destination { Text("Destination: \(value.isEmpty ? "Not entered" : value)").font(.caption) }
                                HStack {
                                    Button("Use Source") { fields[index].merged = fields[index].source; fields[index].reviewed = true }
                                    if let value = fields[index].destination { Button("Use Destination") { fields[index].merged = value; fields[index].reviewed = true } }
                                }.buttonStyle(.bordered).font(.caption)
                                TextField("Final value (blank stays unknown)", text: Binding(get: { fields[index].merged }, set: { fields[index].merged = $0; fields[index].reviewed = true }), axis: .vertical)
                                if !fields[index].reviewed { Text("Choose or enter a final value.").font(.caption).foregroundStyle(.orange) }
                            }.padding(.vertical, 4)
                        }
                        if isNutrition { Toggle("Day finished", isOn: $final) }
                    }
                    if isNutrition {
                        Section("Target after correction") {
                            if let target { CoachNutritionTargetValues(targets: target) }
                            else { Text("No target recorded for the corrected day.") }
                            Text(expectedDestinationID == nil ? "A move to an empty day uses that day's reviewed effective target." : "Merging preserves the destination day's original target snapshot.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else { Text("Manual sleep and the destination's Health provenance stay separate. Health samples are not added or changed.").font(.caption).foregroundStyle(.secondary) }
                    Button("Apply Reviewed Date Correction", action: apply).disabled(fields.contains { !$0.reviewed })
                        .accessibilityIdentifier("coach.checkin.correct_date.apply")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .scrollDismissesKeyboard(.interactively).navigationTitle("Correct Check-in Date")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: date) { _, _ in prepared = false; fields = []; error = nil }
        }
    }
    private func preview() {
        do {
            if isNutrition {
                let preview = try repository.nutritionMovePreview(id: sourceID, to: date)
                expectedSourceUpdatedAt = preview.source.updatedAt; expectedDestinationID = preview.destination?.id; expectedDestinationUpdatedAt = preview.destination?.updatedAt
                fields = [field("calories", "Calories (kcal)", preview.source.calories, preview.destination?.calories),
                          field("protein", "Protein (g)", preview.source.protein, preview.destination?.protein),
                          field("carbs", "Carbohydrate (g)", preview.source.carbs, preview.destination?.carbs),
                          field("fat", "Fat (g)", preview.source.fat, preview.destination?.fat),
                          textField("notes", "Notes", preview.source.notes, preview.destination?.notes)]
                final = preview.destination?.statusRaw == "final" || (preview.destination == nil && preview.source.statusRaw == "final")
                if let destination = preview.destination {
                    target = try destination.targetSnapshotData.map { try JSONDecoder().decode(CoachNutritionTargets.self, from: $0) }
                } else if let period = preview.target {
                    target = .init(caloriesKcal: period.calories.map { Int($0.rounded()) }, proteinGrams: period.protein, carbohydrateGrams: period.carbs, fatGrams: period.fat, notes: period.notes)
                } else { target = nil }
            } else {
                let preview = try repository.recoveryMovePreview(id: sourceID, to: date)
                expectedSourceUpdatedAt = preview.source.updatedAt; expectedDestinationID = preview.destination?.id; expectedDestinationUpdatedAt = preview.destination?.updatedAt
                fields = [field("sleep", "Manual sleep (hours)", preview.source.manualSleepHours, preview.destination?.manualSleepHours),
                          field("soreness", "Soreness (0–10)", preview.source.soreness.map(Double.init), preview.destination?.soreness.map(Double.init)),
                          field("energy", "Energy (1–5)", preview.source.energy.map(Double.init), preview.destination?.energy.map(Double.init)),
                          field("pain", "Pain (0–10)", preview.source.painScore.map(Double.init), preview.destination?.painScore.map(Double.init)),
                          textField("location", "Pain location", preview.source.painLocation, preview.destination?.painLocation),
                          textField("notes", "Notes", preview.source.notes, preview.destination?.notes)]
            }
            prepared = true; error = nil
        } catch { self.error = error.localizedDescription; prepared = false }
    }
    private func field(_ id: String, _ title: String, _ source: Double?, _ destination: Double?) -> CoachDailyMergeField {
        textField(id, title, CoachEntryNumber.input(source), CoachEntryNumber.input(destination))
    }
    private func textField(_ id: String, _ title: String, _ source: String?, _ destination: String?) -> CoachDailyMergeField {
        let source = source ?? "", destination = expectedDestinationID == nil ? nil : (destination ?? "")
        return .init(id: id, title: title, source: source, destination: destination, merged: source, reviewed: destination == nil || destination == source)
    }
    private func value(_ id: String) -> String { fields.first { $0.id == id }?.merged ?? "" }
    private func apply() {
        do {
            guard prepared, fields.allSatisfy(\.reviewed) else { return }
            if isNutrition {
                _ = try repository.moveNutrition(id: sourceID, to: date, mergedCalories: CoachEntryNumber.optional(value("calories")), mergedProtein: CoachEntryNumber.optional(value("protein")), mergedCarbs: CoachEntryNumber.optional(value("carbs")), mergedFat: CoachEntryNumber.optional(value("fat")), mergedNotes: CoachEntryNumber.note(value("notes")), isFinal: final, expectedDestinationID: expectedDestinationID, expectedSourceUpdatedAt: expectedSourceUpdatedAt, expectedDestinationUpdatedAt: expectedDestinationUpdatedAt)
            } else {
                _ = try repository.moveRecovery(id: sourceID, to: date, manualSleepHours: CoachEntryNumber.optional(value("sleep")), soreness: CoachEntryNumber.integer(value("soreness")), energy: CoachEntryNumber.integer(value("energy")), painScore: CoachEntryNumber.integer(value("pain")), painLocation: CoachEntryNumber.note(value("location")), notes: CoachEntryNumber.note(value("notes")), expectedDestinationID: expectedDestinationID, expectedSourceUpdatedAt: expectedSourceUpdatedAt, expectedDestinationUpdatedAt: expectedDestinationUpdatedAt)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
