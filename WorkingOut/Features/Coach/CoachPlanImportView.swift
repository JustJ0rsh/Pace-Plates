import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let coachProgram = UTType(exportedAs: "com.justjorshin.paceandplates.coach-program", conformingTo: .json)
}

struct CoachProgramFile: FileDocument {
    static var readableContentTypes: [UTType] { [.coachProgram, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 2 * 1_024 * 1_024 else {
            throw CoachRepositoryError.invalidValue("program file smaller than 2 MiB")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CoachImportRequest: Identifiable { let id = UUID(); let text: String }

enum CoachProgramResources {
    static func data(_ name: String, extension ext: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Coach")
                ?? Bundle.main.url(forResource: name, withExtension: ext) else {
            throw CoachRepositoryError.invalidValue("bundled \(name) resource")
        }
        return try Data(contentsOf: url)
    }
    static func prompt(requirements: String, personalContext: String?) throws -> String {
        let schema = String(decoding: try data("coach-plan-v1.schema", extension: "json"), as: UTF8.self)
        let contract = String(decoding: try data("coach-json-contract", extension: "md"), as: UTF8.self)
        let example = String(decoding: try data("example-coach-plan", extension: "json"), as: UTF8.self)
        return """
        Create a Pace & Plates Coach program using format pace-and-plates.coach-program, schemaVersion 1.
        Return exactly one JSON object, no prose or Markdown fences. Follow the complete schema and semantic contract below. Use explicit ordered weeks, stable IDs, reusable templates and week patterns, structured sets and intervals, and reviewed progression only. Omit unavailable optional targets; never invent actual results. Include every requested week. Multiple sessions on a day use multiple slots. Different prescriptions use separate templates/patterns. The example is for format only, not a personal training prescription.

        MY CHOSEN REQUIREMENTS
        \(requirements)
        \(personalContext.map { "\nPERSONAL CONTEXT I CHOSE TO INCLUDE\n" + $0 } ?? "")

        SEMANTIC CONTRACT
        \(contract)

        COMPLETE JSON SCHEMA
        \(schema)

        FORMAT-ONLY EXAMPLE
        \(example)
        """
    }
    static func readFile(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw CoachRepositoryError.invalidValue("local program file") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2 * 1_024 * 1_024 + 1) ?? Data()
        guard data.count <= 2 * 1_024 * 1_024, let text = String(data: data, encoding: .utf8) else {
            throw CoachRepositoryError.invalidValue("UTF-8 program file no larger than 2 MiB")
        }
        return text
    }
}

struct CoachAddPlanView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { CoachPlanImportView() } label: { Label("Paste from ChatGPT or Import File", systemImage: "doc.badge.arrow.up") }
                NavigationLink { CoachPromptView() } label: { Label("Copy ChatGPT Prompt", systemImage: "document.on.clipboard") }
                NavigationLink { CoachPlanBuilderView() } label: { Label("Build Manually", systemImage: "square.and.pencil") }
            } footer: {
                Text("Programs contain prescriptions. Importing a plan does not record a workout, share personal history, or add calendar events.")
            }
            Section {
                NavigationLink { AIPlannerView() } label: { Label("Create with On-Device AI", systemImage: "sparkles") }
            } footer: {
                Text("AI availability depends on this device. Manual plans and JSON import work offline.")
            }
        }
        .navigationTitle("Add Plan")
    }
}

struct CoachPromptView: View {
    @State private var requirements = ""
    @State private var includePersonalContext = false
    @State private var personalContext = ""
    @State private var preview: String?
    @State private var copied = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Your requirements") {
                TextField("Goal, number of weeks, equipment, and schedule", text: $requirements, axis: .vertical).lineLimit(4...10)
            }
            Section {
                Toggle("Include personal context I enter", isOn: $includePersonalContext)
                if includePersonalContext { TextField("Optional personal context", text: $personalContext, axis: .vertical).lineLimit(3...10) }
            } footer: {
                Text("No saved measurements, check-ins, photos, or health history are included automatically. If you paste this prompt into ChatGPT, that service handles the text under its own terms.")
            }
            Button("Preview Prompt") {
                do { preview = try CoachProgramResources.prompt(requirements: requirements, personalContext: includePersonalContext ? personalContext : nil); copied = false }
                catch { self.error = error.localizedDescription }
            }
            if let preview {
                Section("Exact text to copy") {
                    ScrollView {
                        Text(preview).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 300)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("ChatGPT Prompt")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if let preview {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "Copied" : "Copy") { UIPasteboard.general.string = preview; copied = true }
                        .accessibilityLabel(copied ? "Copied" : "Copy ChatGPT Prompt")
                        .accessibilityIdentifier("coach.prompt.copy")
                }
            }
        }
        .onChange(of: requirements) { _, _ in preview = nil }
        .onChange(of: personalContext) { _, _ in preview = nil }
        .onChange(of: includePersonalContext) { _, _ in preview = nil }
    }
}

struct CoachPlanImportView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String
    @State private var importingFile = false
    @State private var validating = false
    @State private var validated: CoachValidatedProgram?
    @State private var error: String?
    @State private var validationTask: Task<Void, Never>?
    @FocusState private var editingJSON: Bool
    @State private var showingReview = false

    init(text: String = "") { _text = State(initialValue: text) }

    var body: some View {
        Group {
            if !CoachPersistence.isLocal(context) { CoachHomeView() }
            else {
                Form {
                    Section {
                        TextEditor(text: $text).font(.body.monospaced()).frame(height: 280)
                            .focused($editingJSON)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .accessibilityLabel("Program JSON").accessibilityIdentifier("coach.import.paste")
                        Button { importingFile = true } label: { Label("Import File", systemImage: "folder") }
                    } header: { Text("Paste program JSON") } footer: {
                        Text("Paste one complete Coach program. Your text stays here if validation finds an error.")
                    }
                    if let error { Section("Needs correction") { Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("coach.import.error") } }
                    if validating { ProgressView("Checking program…") }
                    if let validated {
                        NavigationLink { CoachPlanReviewView(validated: validated) } label: {
                            Label("Review \(validated.document.title)", systemImage: "checkmark.circle")
                        }
                        .accessibilityIdentifier("coach.import.open_review")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Import Program")
        .navigationDestination(isPresented: $showingReview) {
            if let validated { CoachPlanReviewView(validated: validated) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Review") { editingJSON = false; validate() }
                    .disabled(validating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("coach.import.review")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") { editingJSON = false }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.coachProgram, .json, .plainText]) { result in
            switch result {
            case .success(let url):
                validationTask?.cancel()
                validationTask = Task { @MainActor in
                    do {
                        let contents = try await Task.detached { try CoachProgramResources.readFile(url) }.value
                        try Task.checkCancellation(); text = contents; validated = nil
                    } catch { self.error = error.localizedDescription }
                }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        .onChange(of: text) { _, _ in validated = nil; error = nil }
        .onDisappear { validationTask?.cancel() }
    }
    private func validate() {
        error = nil; validated = nil; validating = true
        let input = text
        validationTask = Task { @MainActor in
            defer { validating = false }
            do {
                let value = try await Task.detached(priority: .userInitiated) { try CoachPlanValidator().validate(input) }.value
                try Task.checkCancellation()
                if text == input { validated = value; showingReview = true }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CoachPlanReviewView: View {
    let validated: CoachValidatedProgram
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var plans: [TrainingPlan]
    @State private var startDate = Date()
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var restoringTimeZone = false
    @State private var mappings: [CoachExerciseMapping] = []
    @State private var selectedMappings: [String: UUID] = [:]
    @State private var allowCustomExercises = false
    @State private var readyFirstPhase = false
    @State private var acknowledgePause = false
    @State private var chosenDraftID: UUID?
    @State private var expectedDraftRevisionID: UUID?
    @State private var separateCopy = false
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var resultID: UUID?
    @State private var error: String?
    private var document: CoachPlanDocument { validated.document }
    private var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
    private var scheduleCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone; return calendar
    }
    private var timeZoneIdentifiers: [String] { Array(Set(TimeZone.knownTimeZoneIdentifiers + [TimeZone.current.identifier])).sorted() }
    private var matching: [TrainingPlan] { plans.filter { $0.sourceProgramID == document.programId } }
    private var exact: TrainingPlan? { matching.first { $0.fingerprint == validated.fingerprint } }
    private var active: TrainingPlan? { plans.first { $0.status == "active" } }
    private var unresolved: Bool { mappings.contains { $0.requiresSelection && selectedMappings[$0.id] == nil } || (mappings.contains { $0.candidates.isEmpty } && !allowCustomExercises) }

    var body: some View {
        List {
            Section {
                Text(document.title).font(.title2.bold())
                Text(document.goal)
                if let overview = document.overview { Text(overview) }
                Text("\(document.weeks.count) weeks · \(document.phases.count) phases · \(document.sessionTemplates.count) templates").foregroundStyle(.secondary)
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .environment(\.timeZone, timeZone).environment(\.calendar, scheduleCalendar)
                    .disabled(saving).accessibilityIdentifier("coach.plan.start_date")
                Picker("Schedule time zone", selection: $timeZoneIdentifier) {
                    ForEach(timeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }.pickerStyle(.navigationLink).disabled(saving).accessibilityIdentifier("coach.plan.time_zone")
                Text("The selected start day stays the same when you choose a time zone. This zone anchors program dates and reminders when you travel.").font(.caption).foregroundStyle(.secondary)
            }
            if !validated.issues.isEmpty {
                Section("Review notes") { ForEach(Array(validated.issues.enumerated()), id: \.offset) { _, issue in Text(issue.path + ": " + issue.message) } }
            }
            Section("Every week") { CoachProgramPreview(document: document, startDate: startDate, timeZone: timeZone) }
            if let targets = document.nutritionTargets { Section("Program nutrition targets") { CoachNutritionTargetValues(targets: targets) } }
            if let targets = document.recoveryTargets {
                Section("Program recovery guidance") {
                    if let sleep = targets.sleepHours { Text("Sleep: \(sleep.min.formatted())–\(sleep.max.formatted()) hours") }
                    if let notes = targets.notes { Text(notes) }
                }
            }
            if !mappings.isEmpty {
                Section("Exercise mappings") {
                    ForEach(mappings) { mapping in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mapping.choice.name).font(.headline)
                            Text(mapping.choice.equipment.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            if mapping.candidates.isEmpty { Text("Create as a custom exercise after review").font(.subheadline) }
                            else if mapping.requiresSelection {
                                Picker("Match", selection: Binding(get: { selectedMappings[mapping.id] }, set: { selectedMappings[mapping.id] = $0 })) {
                                    Text("Choose a match").tag(Optional<UUID>.none)
                                    ForEach(mapping.candidates) { Text($0.name).tag(Optional($0.id)) }
                                }
                            } else { Text("Matches \(mapping.candidates[0].name)").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                    if mappings.contains(where: { $0.candidates.isEmpty }) { Toggle("Create the reviewed custom exercises", isOn: $allowCustomExercises) }
                }
            }
            if let exact {
                Section("Already imported") {
                    NavigationLink("Open \(exact.title)") { CoachProgramDetailView(plan: exact) }
                    Toggle("Create a separate copy", isOn: $separateCopy)
                }
            } else if !matching.isEmpty {
                Section("Changed program") {
                    Text("This source identity already exists. Review its changes and choose the copy to update, or explicitly save a separate plan.")
                    ForEach(matching) { plan in
                        NavigationLink("Compare with \(plan.title) · revision \(plan.sourceRevision)") {
                            CoachRevisionReviewView(plan: plan, incoming: validated)
                        }
                    }
                    Toggle("Save as a separate plan", isOn: $separateCopy)
                    Picker("Replace reviewed draft", selection: $chosenDraftID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(matching.filter { $0.status == "draft" && $0.sourceRevision < document.revision }) {
                            Text($0.title).tag(Optional($0.id))
                        }
                    }
                }
            }
            if document.phases.first?.advanceMode == .reviewRequired { Section { Toggle("I have reviewed the first phase and am ready to start it", isOn: $readyFirstPhase) } }
            if let active { Section { Toggle("Starting pauses “\(active.title)” and keeps its history", isOn: $acknowledgePause) } }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.import.save_error") }
            Section {
                Button("Save Draft") { save(activate: false) }.disabled(!canSave || saving)
                    .accessibilityIdentifier("coach.plan.save_draft")
                Button("Start Plan") { save(activate: true) }
                    .disabled(!canSave || saving || (active != nil && !acknowledgePause) || (document.phases.first?.advanceMode == .reviewRequired && !readyFirstPhase))
                    .accessibilityIdentifier("coach.plan.activate")
                if saving { ProgressView("Saving program…") }
                if let resultID, let plan = plans.first(where: { $0.id == resultID }) {
                    Text("Program saved.").foregroundStyle(.secondary)
                    NavigationLink("Open Program") { CoachProgramDetailView(plan: plan) }.accessibilityIdentifier("coach.plan.open_saved")
                }
            }
        }
        .navigationTitle("Review Program")
        .task {
            do { mappings = try CoachRepository(context: context).exerciseMappings(for: document) }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear { saveTask?.cancel() }
        .onChange(of: chosenDraftID) { _, id in expectedDraftRevisionID = plans.first(where: { $0.id == id })?.currentRevisionID }
        .onChange(of: timeZoneIdentifier) { previous, selected in
            if restoringTimeZone { restoringTimeZone = false; return }
            let civilDate = CoachSchedule.civilDate(startDate, timeZone: TimeZone(identifier: previous) ?? .current)
            if let selectedZone = TimeZone(identifier: selected), let adjusted = CoachSchedule.date(from: civilDate, timeZone: selectedZone) {
                startDate = adjusted
            } else {
                restoringTimeZone = true; timeZoneIdentifier = previous
                error = "The selected civil day does not exist in that time zone. Choose another start date or time zone."
            }
        }
    }
    private var canSave: Bool { !unresolved && (matching.isEmpty || separateCopy || chosenDraftID != nil) }
    private func save(activate: Bool) {
        saving = true; error = nil
        saveTask = Task { @MainActor in
            defer { saving = false }
            do {
                let repository = CoachRepository(context: context)
                resultID = try await repository.importPlan(document: document, startDate: startDate, activate: activate,
                    exerciseMappings: selectedMappings, allowCreatingExercises: allowCustomExercises,
                    replacingDraftID: chosenDraftID, expectedRevisionID: expectedDraftRevisionID,
                    saveAsNewPlan: separateCopy, firstPhaseReady: readyFirstPhase, timeZone: timeZone)
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CoachProgramPreview: View {
    let document: CoachPlanDocument
    let startDate: Date
    var timeZone: TimeZone = .current
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone; return calendar
    }
    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.weekday().month().day()
        format.timeZone = timeZone; format.calendar = calendar; return format
    }
    private func orderedSlots(for week: CoachWeek) -> [CoachSlot] {
        let slots = document.weekPatterns.first(where: { $0.id == week.weekPatternId })?.slots ?? []
        return slots.enumerated().sorted {
            $0.element.dayOffset == $1.element.dayOffset ? $0.offset < $1.offset : $0.element.dayOffset < $1.element.dayOffset
        }.map(\.element)
    }
    var body: some View {
        ForEach(Array(document.weeks.enumerated()), id: \.element.id) { index, week in
            DisclosureGroup("Week \(index + 1) · \(week.label ?? document.phases.first(where: { $0.id == week.phaseId })?.title ?? week.id)") {
                if let phase = document.phases.first(where: { $0.id == week.phaseId }) {
                    if let overview = phase.overview { Text(overview).font(.subheadline) }
                    if phase.advanceMode == .reviewRequired { Label("Readiness review required", systemImage: "hand.raised").font(.caption) }
                    if let targets = phase.nutritionTargets { CoachNutritionTargetValues(targets: targets) }
                }
                ForEach(orderedSlots(for: week)) { slot in
                    if let template = document.sessionTemplates.first(where: { $0.id == slot.sessionTemplateId }) {
                        let date = calendar.date(byAdding: .day, value: index * 7 + slot.dayOffset, to: calendar.startOfDay(for: startDate)) ?? startDate
                        DisclosureGroup {
                            CoachPrescriptionPreview(template: template)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(template.title)
                                Text(date, format: dateFormat).font(.caption)
                                if slot.optional { Text("Optional").font(.caption) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CoachPrescriptionPreview: View {
    let template: CoachSessionTemplate
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch template {
            case .strength(let strength):
                ForEach(strength.exercises) { exercise in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.exercise.name).font(.headline)
                        if !exercise.exercise.equipment.isEmpty { Text("Equipment: " + exercise.exercise.equipment.joined(separator: ", ")).font(.caption) }
                        Text("\(CoachPresentation.prescriptionBasis(exercise.prescriptionBasis)) · \(CoachPresentation.loadBasis(exercise.loadBasis))").font(.caption)
                        ForEach(exercise.sets) { set in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(CoachPresentation.set(set)).font(.subheadline)
                                if let notes = set.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        if let notes = exercise.notes { Text(notes).font(.caption) }
                        if let alternatives = exercise.substitutions, !alternatives.isEmpty {
                            Text("Alternative movements").font(.caption.bold())
                            ForEach(alternatives, id: \.key) { choice in
                                Text(choice.name + (choice.equipment.isEmpty ? "" : " · " + choice.equipment.joined(separator: ", "))).font(.caption)
                            }
                            Text("An alternative requires review of its load basis; suggested loads are cleared when it is selected.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.bottom, 4)
                }
            case .running(let cardio), .cardio(let cardio):
                CoachIntervalSectionPreview(title: "Warm-up", blocks: cardio.warmup)
                CoachIntervalSectionPreview(title: "Main session", blocks: cardio.main)
                CoachIntervalSectionPreview(title: "Cool-down", blocks: cardio.cooldown)
            case .recovery(let recovery):
                if let duration = recovery.durationSeconds { Text("Target duration: \(duration) seconds").font(.subheadline) }
                Text(recovery.instructions)
            case .rest: Text("Rest day. No workout is created.")
            }
            if template.kind != "recovery", let notes = template.notes { Text(notes).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoachIntervalSectionPreview: View {
    let title: String
    let blocks: [CoachIntervalBlock]
    var body: some View {
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                ForEach(blocks, id: \.id) { block in
                    switch block {
                    case let .segment(segment): CoachSegmentPrescriptionPreview(segment: segment)
                    case let .repeatBlock(repeated):
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Repeat \(repeated.count) times").font(.subheadline.bold())
                            ForEach(repeated.segments) { CoachSegmentPrescriptionPreview(segment: $0) }
                            if let notes = repeated.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.leading, 10)
                    }
                }
            }
        }
    }
}

private struct CoachSegmentPrescriptionPreview: View {
    let segment: CoachSegment
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(CoachPresentation.segment(segment)).font(.subheadline)
            if let notes = segment.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
            if case .distance = segment.target {
                Text("Distance needs a measured source or deliberate manual completion.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

enum CoachPresentation {
    static func prescriptionBasis(_ basis: CoachPrescriptionBasis) -> String {
        basis == .perSide ? "Reps / time per side" : "Reps / time total"
    }
    static func loadBasis(_ basis: CoachLoadBasis) -> String {
        switch basis {
        case .totalExternal: "Total external load"
        case .perImplement: "Load per implement"
        case .addedToBodyweight: "Load added to bodyweight"
        case .assistance: "Assistance load"
        }
    }
    static func set(_ set: CoachStrengthSet) -> String {
        var text = set.role.rawValue.capitalized + ": "
        switch set.target {
        case .reps(let min, let max): text += "\(min)–\(max) reps"
        case .duration(let seconds): text += "\(seconds) sec"
        }
        if let load = set.load { text += " · \(load.value.formatted()) \(load.unit.rawValue)" }
        if let effort = set.effort { text += " · \(effort.min.formatted())–\(effort.max.formatted()) \(effort.scale.rawValue.uppercased())" }
        if let rest = set.restAfterSeconds { text += " · Rest \(rest) sec" }
        return text
    }
    static func block(_ block: CoachIntervalBlock) -> String {
        switch block {
        case .segment(let segment): return self.segment(segment)
        case .repeatBlock(let repetition): return "\(repetition.count) × (" + repetition.segments.map(segment).joined(separator: " / ") + ")"
        }
    }
    static func segment(_ segment: CoachSegment) -> String {
        var text = segment.title.map { $0 + " · " } ?? ""
        text += segment.activity.rawValue.capitalized + " "
        switch segment.target {
        case .duration(let seconds): text += "\(seconds) sec"
        case .distance(let distance): text += "\(distance.value.formatted()) \(distance.unit.rawValue)"
        }
        if let rpe = segment.intensity?.rpe { text += " · RPE \(rpe.min.formatted())–\(rpe.max.formatted())" }
        if let pace = segment.intensity?.pace {
            func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
            text += " · \(clock(pace.minSeconds))–\(clock(pace.maxSeconds)) min/\(pace.per.rawValue)"
        }
        if let cue = segment.intensity?.cue { text += " · " + cue }
        return text
    }
}

struct CoachNutritionTargetValues: View {
    let targets: CoachNutritionTargets
    var body: some View {
        if let value = targets.caloriesKcal { LabeledContent("Calories", value: "\(value) kcal") }
        if let value = targets.proteinGrams { LabeledContent("Protein", value: "\(value.formatted()) g") }
        if let value = targets.carbohydrateGrams { LabeledContent("Carbohydrate", value: "\(value.formatted()) g") }
        if let value = targets.fatGrams { LabeledContent("Fat", value: "\(value.formatted()) g") }
        if let notes = targets.notes { Text(notes).font(.caption) }
    }
}
