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
        let example = String(decoding: try data("example-coach-plan", extension: "json"), as: UTF8.self)
        return """
        Create an executable training program for the Pace & Plates Coach importer.
        The app turns your JSON into dated planned strength workouts and runs. During training it presents every prescribed set and run interval for recording actual performance and completion. A narrative weekly plan cannot be imported.

        Return exactly ONE complete JSON object using format "pace-and-plates.coach-program" and integer schemaVersion 1. No introduction, Markdown fences, tables, comments, ellipses, or text after the object. The complete schema and a format-only example are included below; you do not need an API, link, or local file.

        MY CHOSEN REQUIREMENTS
        \(requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No personal requirements supplied. Produce a clearly labeled generic format demonstration without personalized load, pace, or nutrition claims." : requirements)
        \(personalContext.map { "\nPERSONAL CONTEXT I CHOSE TO INCLUDE\n" + $0 } ?? "")

        MAKE THE TRAINING EXECUTABLE
        1. Strength: use kind "strength" templates with ordered exercise rows. Each row must include an exercise key/name/equipment, prescriptionBasis, loadBasis, and a separate object for EVERY set. For 3 sets of 8–12 reps, write three sets, each with its own id, role "working", and target {"kind":"reps","min":8,"max":12}. Timed sets use {"kind":"duration","seconds":30}. Preserve warmup/backoff/drop roles where appropriate. Put restAfterSeconds and RIR/RPE effort on the set itself. Do not encode sets, reps, rest, or effort only in notes.
        2. Running: use kind "running" templates with ordered warmup/main/cooldown arrays. A steady run still needs a main segment. Every segment has kind "segment", a unique id, activity "walk", "jog", or "run", and exactly one structured duration or distance target. Use a repeat block with count and segments for intervals; never nest repeat blocks. A 3 × (2-minute run, 1-minute walk) main block has count 3 and two segments with targets of 120 and 60 seconds. Optional intensity.rpe, intensity.pace, and intensity.cue remain structured. Pace minSeconds is the faster bound; maxSeconds is the slower bound. General cycling/rowing/etc. uses kind "cardio", not "running".
        3. Schedule: sessionTemplates alone do not schedule anything. Reference each intended workout/run from weekPatterns.slots using sessionTemplateId and dayOffset 0–6. Reference those patterns from EVERY explicit entry in weeks. A requested 12-week plan needs 12 ordered week entries, even when patterns repeat. Reuse templates when prescriptions are identical; create alternate templates/patterns when they change. Put two sessions on one day in two slots in their intended order. Day 0 means the user's chosen program start day, not necessarily Monday. Do not include a start date in JSON; the user chooses it in the app.
        4. Use kind "recovery" for instructed recovery sessions and kind "rest" for explicit rest. Missing days remain unscheduled. Never put rest alongside another slot on the same day. Label optional sessions with optional true; they do not count toward required-session adherence.

        REQUIRED VALIDATION RULES
        - Required root keys: format, schemaVersion, programId, revision, title, goal, preferredUnits, phases, sessionTemplates, weekPatterns, weeks. revision is a positive author revision number. For an update, keep source IDs for unchanged identities and increment revision. For a new plan, choose a new stable programId.
        - Use only schema-defined properties and enum values, real JSON numbers/booleans, explicit units, and valid ASCII IDs. No unknown fields, duplicate object keys, null placeholders, numeric strings, or invented catalogExerciseId values. Omit unavailable optional targets, including unspecified load/pace/nutrition. A missing value is not zero. Individual value units take precedence over preferredUnits.
        - All references must resolve. IDs are unique within each root collection; slot IDs within a pattern; exercise-row IDs within a strength template; set IDs within a row. Segment AND repeat-block IDs are unique across the whole running/cardio template, including all three sections and nested segments. An exercise key always has the same name, equipment, and catalog ID throughout the document, including substitutions.
        - Use every declared phase in declaration order, in contiguous week ranges. advanceMode "reviewRequired" requires explicit readiness review in the app; "scheduled" follows the schedule. A phase nutritionTargets or recoveryTargets block replaces that entire program-level block, not individual fields.
        - All min/max ranges must satisfy min <= max. If supplied, nutritionTargets needs at least one numeric target; recoveryTargets needs at least one property; intensity needs RPE, pace, or cue. Check calorie/macro consistency when all four numeric nutrition targets are supplied. Keep unknown personal targets absent.
        - All progression rules require reviewRequired true. doubleProgression must reference a strength exercise row with working rep sets that ALL prescribe RIR, and a strictly positive load increment suitable for its load basis. Otherwise use manualReview guidance with template references. Do not invent automatic rules or claim progression has already occurred.
        - Respect every schema bound plus these aggregate limits: 2 MiB JSON; 104 weeks; 56 slots per pattern and 8 per day; 5,824 scheduled occurrences; 200 sets per strength session; 2,000 expanded segments per running/cardio session; 200,000 total expanded steps across the program; 86,400 total explicitly prescribed duration seconds per session. Count repeat iterations and repeated weeks. These are technical limits, not recommended training amounts.
        - Include only prescriptions. No completed workouts, actual set results, logged food, measurements, recovery check-ins, photo data, Health IDs, calendar events, credentials, URLs to fetch, or executable code. The app reviews exercise matches, readiness, and replacement of an active plan before activation. It never silently completes a workout from this JSON.

        BEFORE YOU RETURN THE JSON
        Check every requested week is represented and every intended strength workout/run is reachable through weeks → weekPatterns → slots → sessionTemplates. Check every strength set and run interval is structured and every reference, ID, unit, range, and progression target follows the schema. Return the entire JSON object; never shorten it with "repeat this week" or placeholders. The example below demonstrates format only. Do not copy its exercise, load, run, or nutrition choices as personal recommendations.

        COMPLETE JSON SCHEMA
        \(schema)

        FORMAT-ONLY EXAMPLE
        \(example)
        """
    }
    static func readFile(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2 * 1_024 * 1_024 + 1) ?? Data()
        guard data.count <= 2 * 1_024 * 1_024 else { throw CoachValidationError(issues: [.init(path: "$", message: "This file exceeds 2 MiB. Ask for a complete program that uses reusable templates and week patterns within the import limit.")]) }
        guard let text = String(data: data, encoding: .utf8) else { throw CoachValidationError(issues: [.init(path: "$", message: "Save the program as UTF-8 JSON, then choose the file again.")]) }
        return text
    }
}

enum CoachProgramImportSource: String, CaseIterable {
    case paste, file
}

struct CoachAddPlanView: View {
    var body: some View {
        List {
            Section {
                Text("Add a plan to schedule workouts and runs, then check them off as you go.")
                    .foregroundStyle(.secondary)
            }
            Section {
                NavigationLink { CoachPlanImportView() } label: {
                    Label("Paste Program JSON", systemImage: "document.on.clipboard")
                }.accessibilityIdentifier("coach.add_plan.paste")
                NavigationLink { CoachPlanImportView(source: .file) } label: {
                    Label("Import JSON File", systemImage: "folder")
                }.accessibilityIdentifier("coach.add_plan.file")
            } header: { Text("Have program JSON?") } footer: {
                Text("You will review the dated schedule and exercise matches before saving or starting.")
            }
            Section {
                NavigationLink { CoachPromptView() } label: {
                    Label("Copy ChatGPT Prompt", systemImage: "text.bubble")
                }.accessibilityIdentifier("coach.add_plan.prompt")
                NavigationLink { CoachPlanBuilderView() } label: { Label("Build Manually", systemImage: "square.and.pencil") }
                NavigationLink { AIPlannerView() } label: { Label("Create with On-Device AI", systemImage: "sparkles") }
            } header: { Text("Need a program first?") } footer: {
                Text("The ChatGPT prompt requests the exact import format. Manual plans and JSON import work offline; on-device AI availability varies.")
            }
        }
        .navigationTitle("Add Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CoachPromptView: View {
    @State private var requirements = ""
    @State private var includePersonalContext = false
    @State private var personalContext = ""
    @State private var preview: String?
    @State private var copied = false
    @State private var error: String?
    @FocusState private var editingRequirements: Bool
    var body: some View {
        Form {
            Section("How this works") {
                Label("1. Describe the program you want below.", systemImage: "square.and.pencil")
                Label("2. Preview and copy the prompt into ChatGPT.", systemImage: "document.on.clipboard")
                Label("3. Copy its complete JSON reply, then paste it here to review your schedule.", systemImage: "calendar")
                Text("The prompt includes the full Coach v1 format so ChatGPT can prescribe individual strength sets and timed or distance-based run intervals.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                TextField("Goal, number of weeks, equipment, and schedule", text: $requirements, axis: .vertical)
                    .lineLimit(4...10).focused($editingRequirements)
                    .accessibilityIdentifier("coach.prompt.requirements")
            } header: { Text("Your requirements") } footer: {
                Text("Include how many days you want to lift and run, your current experience, and available equipment. With no requirements, the prompt asks for a generic format demonstration.")
            }
            Section {
                Toggle("Include personal context I enter", isOn: $includePersonalContext)
                if includePersonalContext {
                    TextField("Optional personal context", text: $personalContext, axis: .vertical)
                        .lineLimit(3...10).focused($editingRequirements)
                }
            } footer: {
                Text("No saved measurements, check-ins, photos, or health history are included automatically. You choose what to copy. If you paste it into ChatGPT, that service handles the text under its own terms.")
            }
            Section {
                Button("Preview Prompt") {
                    editingRequirements = false; error = nil
                    do {
                        preview = try CoachProgramResources.prompt(requirements: requirements, personalContext: includePersonalContext ? personalContext : nil)
                        copied = false
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("coach.prompt.preview")
            }
            if let preview {
                Section("Exact text to copy") {
                    Text("This includes your chosen text, the complete schema, and an example. Copy the whole prompt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ScrollView {
                        Text(preview).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("coach.prompt.content")
                    }.frame(height: 260)
                }
            }
            if copied {
                Section("Prompt copied") {
                    Text("Paste the prompt into ChatGPT. When its complete JSON reply is ready, return here.")
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("ChatGPT Prompt")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if let preview {
                VStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = preview; copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy Prompt for ChatGPT", systemImage: copied ? "checkmark" : "document.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityLabel(copied ? "Copied" : "Copy ChatGPT Prompt")
                    .accessibilityIdentifier("coach.prompt.copy")
                    if copied {
                        NavigationLink("Paste ChatGPT JSON Reply") { CoachPlanImportView() }
                            .accessibilityIdentifier("coach.prompt.paste_reply")
                    }
                }
                .padding().background(.bar)
            }
        }
        .onChange(of: requirements) { _, _ in invalidatePreview() }
        .onChange(of: personalContext) { _, _ in invalidatePreview() }
        .onChange(of: includePersonalContext) { _, _ in invalidatePreview() }
    }
    private func invalidatePreview() { preview = nil; copied = false; error = nil }
}

struct CoachPlanImportView: View {
    @Environment(\.modelContext) private var context
    @State private var text: String
    @State private var source: CoachProgramImportSource
    @State private var importingFile = false
    @State private var operation: ImportOperation?
    @State private var operationID = UUID()
    @State private var validated: CoachValidatedProgram?
    @State private var error: String?
    @State private var issues: [CoachValidationIssue] = []
    @State private var sourceFileName: String?
    @State private var validationTask: Task<Void, Never>?
    @State private var validationInput: String?
    @FocusState private var editingJSON: Bool
    @State private var showingReview = false
    private enum ImportOperation { case readingFile, validating }

    init(text: String = "", source: CoachProgramImportSource = .paste) {
        _text = State(initialValue: text); _source = State(initialValue: source)
    }

    var body: some View {
        Group {
            if !CoachPersistence.isLocal(context) { CoachHomeView() }
            else {
                Form {
                    Section {
                        Text("JSON → reviewed schedule → training").font(.headline)
                        Text("Coach creates planned workouts and runs from the program. Review the dates and prescriptions, then choose Start Plan or Save Draft.")
                            .foregroundStyle(.secondary)
                    }
                    if source == .file {
                        Section {
                            Button { editingJSON = false; importingFile = true } label: {
                                Label(sourceFileName == nil ? "Choose JSON File" : "Choose Another File", systemImage: "folder")
                            }.accessibilityIdentifier("coach.import.choose_file").disabled(operation != nil)
                            if let sourceFileName {
                                Label(sourceFileName, systemImage: "doc.text")
                                    .accessibilityIdentifier("coach.import.source_file")
                            }
                            Button("Paste JSON Instead") { source = .paste }.disabled(operation != nil)
                        } header: { Text("Import from Files") } footer: {
                            Text("Choose a complete Coach v1 JSON file, up to 2 MiB. The file is checked locally and opens for review before anything is saved.")
                        }
                    }
                    if source == .paste || !text.isEmpty {
                        Section {
                            TextEditor(text: $text).font(.body.monospaced()).frame(height: 280)
                                .focused($editingJSON)
                                .autocorrectionDisabled().textInputAutocapitalization(.never)
                                .accessibilityLabel("Program JSON").accessibilityIdentifier("coach.import.paste")
                                .disabled(operation == .readingFile)
                            if source == .paste {
                                Button("Choose a JSON File Instead") { source = .file; editingJSON = false; importingFile = true }.disabled(operation != nil)
                            }
                        } header: { Text(source == .paste ? "Paste the complete JSON reply" : "File contents") } footer: {
                            Text("Use the Coach ChatGPT prompt to generate this format. A prose plan or a different workout JSON format needs to be regenerated. Your text stays here if it needs correction.")
                        }
                    }
                    if let error {
                        Section("Needs correction") {
                            Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("coach.import.error")
                            ForEach(issues) { issue in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(issue.message)
                                    Text(issue.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }.textSelection(.enabled)
                            }
                            if !issues.isEmpty {
                                Button("Copy Errors for ChatGPT") {
                                    UIPasteboard.general.string = "Please correct the complete Coach v1 program JSON using these validation errors. Preserve the requested schedule and return one complete JSON object.\n" + issues.map { $0.path + ": " + $0.message }.joined(separator: "\n")
                                }.accessibilityIdentifier("coach.import.copy_errors")
                            }
                        }
                    }
                    if let operation { ProgressView(operation == .readingFile ? "Reading program file…" : "Checking schedule, sets, and intervals…") }
                    if let validated {
                        NavigationLink { CoachPlanReviewView(validated: validated) } label: {
                            Label("Review \(validated.document.title)", systemImage: "checkmark.circle")
                        }.accessibilityIdentifier("coach.import.open_review")
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(source == .paste ? "Paste Program JSON" : "Import JSON File")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingReview) {
            if let validated { CoachPlanReviewView(validated: validated) }
        }
        .safeAreaInset(edge: .bottom) {
            if CoachPersistence.isLocal(context), source == .paste || !text.isEmpty {
                Button { editingJSON = false; validate() } label: {
                    Label("Review Schedule", systemImage: "calendar.badge.checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(operation != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("coach.import.review")
                .padding().background(.bar)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Hide Keyboard") { editingJSON = false }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.coachProgram, .json, .plainText]) { result in
            switch result {
            case .success(let url): loadFile(url)
            case .failure(let failure): showError(failure)
            }
        }
        .onChange(of: text) { _, value in
            // File reading supplies this same input immediately before validation starts.
            // Its deferred change notification must not erase a fast validation result.
            guard validationInput != value else { return }
            validated = nil; error = nil; issues = []
            if operation == .validating { cancelOperation() }
        }
        .onDisappear { cancelOperation() }
    }
    private func cancelOperation() {
        validationTask?.cancel(); operationID = UUID(); operation = nil; validationInput = nil
    }
    private func loadFile(_ url: URL) {
        cancelOperation(); error = nil; issues = []; validated = nil
        operation = .readingFile
        let token = operationID
        validationTask = Task { @MainActor in
            do {
                let contents = try await Task.detached(priority: .userInitiated) { try CoachProgramResources.readFile(url) }.value
                try Task.checkCancellation()
                guard token == operationID else { return }
                text = contents; sourceFileName = url.lastPathComponent
                operation = nil
                validate()
            } catch is CancellationError { }
            catch {
                guard token == operationID else { return }
                operation = nil; showError(error)
            }
        }
    }
    private func validate() {
        cancelOperation(); error = nil; issues = []; validated = nil
        operation = .validating
        let input = text, token = operationID
        validationInput = input
        validationTask = Task { @MainActor in
            do {
                let value = try await Task.detached(priority: .userInitiated) { try CoachPlanValidator().validate(input) }.value
                try Task.checkCancellation()
                guard token == operationID, text == input else { return }
                operation = nil; validated = value; showingReview = true
            } catch is CancellationError { }
            catch {
                guard token == operationID, text == input else { return }
                operation = nil; showError(error)
            }
        }
    }
    private func showError(_ failure: Error) {
        if let validation = failure as? CoachValidationError {
            issues = validation.issues
            error = "The program could not be imported. Correct the items below, then review it again. Nothing has been saved."
        } else {
            issues = []; error = failure.localizedDescription
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
    @State private var mappingsLoaded = false
    @State private var selectedMappings: [String: UUID] = [:]
    @State private var allowCustomExercises = false
    @State private var readyFirstPhase = false
    @State private var acknowledgePause = false
    @State private var chosenDraftID: UUID?
    @State private var expectedDraftRevisionID: UUID?
    @State private var expectedDraftUpdatedAt: Date?
    @State private var separateCopy = false
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var resultID: UUID?
    @State private var error: String?
    private var document: CoachPlanDocument { validated.document }
    private var savedPlan: TrainingPlan? { resultID.flatMap { id in plans.first(where: { $0.id == id }) } }
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
        Group {
            if resultID != nil { savedProgram }
            else { review }
        }
        .navigationTitle(resultID == nil ? "Review Program" : "Program Saved")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !mappingsLoaded else { return }
            do {
                mappings = try CoachRepository(context: context).exerciseMappings(for: document)
                mappingsLoaded = true
            } catch { self.error = error.localizedDescription }
        }
        .onDisappear { saveTask?.cancel() }
        .onChange(of: active?.id) { _, _ in acknowledgePause = false }
        .onChange(of: chosenDraftID) { _, id in
            let draft = plans.first(where: { $0.id == id })
            expectedDraftRevisionID = draft?.currentRevisionID
            expectedDraftUpdatedAt = draft?.updatedAt
            if id != nil { separateCopy = false }
        }
        .onChange(of: separateCopy) { _, selected in if selected { chosenDraftID = nil } }
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
    private var review: some View {
        List {
            if let exact {
                Section("Already imported") {
                    Text("This exact program is already saved as \(exact.status). Open it to view its schedule\(exact.status == "draft" ? " and start it when ready" : ""). Importing it again is unnecessary.")
                    NavigationLink("Open \(exact.title)") { CoachProgramDetailView(plan: exact) }
                        .accessibilityIdentifier("coach.plan.open_existing")
                    Toggle("Create a separate copy", isOn: $separateCopy)
                }
            }
            Section {
                Text(document.title).font(.title2.bold())
                Text(document.goal)
                Text("\(document.weeks.count) \(document.weeks.count == 1 ? "week" : "weeks")").foregroundStyle(.secondary)
                CoachImportedScheduleSummary(document: document)
                if let overview = document.overview {
                    DisclosureGroup("About this plan") { Text(overview) }
                }
                DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    .environment(\.timeZone, timeZone).environment(\.calendar, scheduleCalendar)
                    .disabled(saving).accessibilityIdentifier("coach.plan.start_date")
                Picker("Schedule time zone", selection: $timeZoneIdentifier) {
                    ForEach(timeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                }.pickerStyle(.navigationLink).disabled(saving).accessibilityIdentifier("coach.plan.time_zone")
                Text("Plan dates stay in this time zone when you travel.").font(.caption).foregroundStyle(.secondary)
            }
            if !mappingsLoaded { Section { ProgressView("Checking exercise matches…") } }
            if !validated.issues.isEmpty {
                Section("Review notes") { ForEach(Array(validated.issues.enumerated()), id: \.offset) { _, issue in Text(issue.path + ": " + issue.message) } }
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
            if exact == nil && !matching.isEmpty {
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
            Section("Every week") { CoachProgramPreview(document: document, startDate: startDate, timeZone: timeZone) }
            if let targets = document.nutritionTargets { Section("Program nutrition targets") { CoachNutritionTargetValues(targets: targets) } }
            if let targets = document.recoveryTargets {
                Section("Program recovery guidance") {
                    if let sleep = targets.sleepHours { Text("Sleep: \(sleep.min.formatted())–\(sleep.max.formatted()) hours") }
                    if let notes = targets.notes { Text(notes) }
                }
            }
        }
        .disabled(saving)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("coach.import.save_error") }
                if saving { ProgressView("Saving schedule…") }
                else if let nextReviewStep {
                    Text(nextReviewStep).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("coach.plan.next_step")
                }
                Button { save(activate: true) } label: {
                    Label("Start Plan", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!canStart).accessibilityIdentifier("coach.plan.activate")
                Button("Save Draft") { save(activate: false) }
                    .disabled(!canSave || saving).accessibilityIdentifier("coach.plan.save_draft")
            }
            .padding().frame(maxWidth: .infinity).background(.bar)
        }
    }
    private var savedProgram: some View {
        List {
            if let savedPlan {
                Section {
                    Label(savedPlan.status == "active" ? "Your program is ready to follow" : "Your draft schedule is saved", systemImage: "checkmark.circle.fill")
                        .font(.title2.bold()).foregroundStyle(.green)
                        .accessibilityIdentifier("coach.plan.saved_status")
                    Text(document.title).font(.headline)
                    CoachImportedScheduleSummary(document: document)
                    Text(savedPlan.status == "active"
                         ? "Open Program to see your dated schedule. Choose a strength workout or run to follow its prescriptions and record your results. Your active schedule is also available from Coach."
                         : "Open Program to review your dated schedule, then choose Start Plan when you are ready to train.")
                    NavigationLink { CoachProgramDetailView(plan: savedPlan) } label: {
                        Label("Open Program", systemImage: "calendar").font(.headline)
                    }.accessibilityIdentifier("coach.plan.open_saved")
                }
                Section {
                    Text("Your sessions begin as planned. Record completed sets and intervals during training; importing does not create completed activity or add Calendar events.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Label("Program unavailable", systemImage: "calendar.badge.exclamationmark").font(.headline)
                        .accessibilityIdentifier("coach.plan.saved_unavailable")
                    Text("This saved program is no longer available. Return to Coach to see your remaining plans.")
                }
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.import.save_error") }
        }
    }
    private var canSave: Bool { mappingsLoaded && resultID == nil && !unresolved && (matching.isEmpty || separateCopy || chosenDraftID != nil) }
    private var canStart: Bool {
        canSave && !saving && (active == nil || acknowledgePause) && (document.phases.first?.advanceMode != .reviewRequired || readyFirstPhase)
    }
    private var nextReviewStep: String? {
        if !mappingsLoaded { return "Wait for exercise matches to finish before saving." }
        if unresolved { return "In Exercise mappings, choose each match and confirm any new custom exercises." }
        if !canSave { return "Open the existing program above, or review a separate copy or draft replacement." }
        if document.phases.first?.advanceMode == .reviewRequired && !readyFirstPhase { return "Confirm first-phase readiness to start, or save a draft." }
        if active != nil && !acknowledgePause { return "Review the active-plan pause to start, or save a draft." }
        return "Starting saves the complete schedule and makes this your active program."
    }
    private func save(activate: Bool) {
        let activationReview = activate ? CoachActivationReview(activePlanID: active?.id) : nil
        saving = true; error = nil
        saveTask = Task { @MainActor in
            defer { saving = false }
            do {
                let repository = CoachRepository(context: context)
                resultID = try await repository.importPlan(document: document, startDate: startDate, activate: activate,
                    exerciseMappings: selectedMappings, allowCreatingExercises: allowCustomExercises,
                    replacingDraftID: chosenDraftID, expectedRevisionID: expectedDraftRevisionID,
                    expectedDraftUpdatedAt: expectedDraftUpdatedAt,
                    saveAsNewPlan: separateCopy, firstPhaseReady: readyFirstPhase, timeZone: timeZone,
                    activationReview: activationReview)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// Count scheduled occurrences, including repeated weeks, rather than unused template definitions.
struct CoachImportedScheduleSummary: View {
    let document: CoachPlanDocument
    private var counts: [String: Int] {
        let templates = Dictionary(document.sessionTemplates.map { ($0.id, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let patterns = Dictionary(document.weekPatterns.map { ($0.id, $0.slots) }, uniquingKeysWith: { first, _ in first })
        return document.weeks.reduce(into: [:]) { result, week in
            for slot in patterns[week.weekPatternId] ?? [] {
                if let kind = templates[slot.sessionTemplateId] { result[kind, default: 0] += 1 }
                if slot.optional { result["optional", default: 0] += 1 }
            }
        }
    }
    var body: some View {
        let counts = counts
        VStack(alignment: .leading, spacing: 8) {
            if let number = counts["strength"] { Label("\(number) planned strength \(number == 1 ? "workout" : "workouts")", systemImage: "dumbbell") }
            if let number = counts["running"] { Label("\(number) planned \(number == 1 ? "run" : "runs")", systemImage: "figure.run") }
            if let number = counts["cardio"] { Label("\(number) planned cardio \(number == 1 ? "session" : "sessions")", systemImage: "heart") }
            if let number = counts["recovery"] { Label("\(number) recovery \(number == 1 ? "session" : "sessions")", systemImage: "leaf") }
            if let number = counts["rest"] { Label("\(number) rest \(number == 1 ? "day" : "days")", systemImage: "moon") }
            if let number = counts["optional"] { Text("Includes \(number) optional \(number == 1 ? "session" : "sessions").").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("coach.plan.schedule_summary")
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
