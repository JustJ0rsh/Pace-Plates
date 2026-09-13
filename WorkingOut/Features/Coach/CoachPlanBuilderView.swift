import SwiftUI
import SwiftData

struct CoachPlanBuilderView: View {
    @State private var document: CoachPlanDocument
    @State private var validated: CoachValidatedProgram?
    @State private var error: String?
    @State private var validating = false
    @State private var validationTask: Task<Void, Never>?
    @FocusState private var focusedField: String?

    init(document: CoachPlanDocument? = nil) {
        let phase = CoachPhase(title: "Phase 1", advanceMode: .scheduled)
        let pattern = CoachWeekPattern(title: "Week pattern 1")
        _document = State(initialValue: document ?? CoachPlanDocument(title: "", goal: "",
            phases: [phase], weekPatterns: [pattern], weeks: [.init(phaseId: phase.id, weekPatternId: pattern.id)]))
    }

    var body: some View {
        Form {
            Section("Program") {
                TextField("Title", text: $document.title).focused($focusedField, equals: "title").accessibilityIdentifier("coach.builder.title")
                TextField("Goal", text: $document.goal, axis: .vertical).focused($focusedField, equals: "goal").accessibilityIdentifier("coach.builder.goal")
                TextField("Overview (optional)", text: optional($document.overview), axis: .vertical).focused($focusedField, equals: "overview")
                Picker("Weight units", selection: $document.preferredUnits.weight) { ForEach(CoachWeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Distance units", selection: $document.preferredUnits.distance) { ForEach(CoachPreferredDistanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Section("Session templates") {
                ForEach(document.sessionTemplates.indices, id: \.self) { index in
                    NavigationLink(document.sessionTemplates[index].title) {
                        CoachTemplateEditor(template: $document.sessionTemplates[index])
                    }.accessibilityIdentifier("coach.builder.template.\(document.sessionTemplates[index].id)")
                    Button("Duplicate \(document.sessionTemplates[index].title)") { duplicateTemplate(at: index) }.font(.caption)
                }
                .onDelete { document.sessionTemplates.remove(atOffsets: $0) }
                .onMove { document.sessionTemplates.move(fromOffsets: $0, toOffset: $1) }
                Menu("Add Session Template") {
                    Button("Strength") { document.sessionTemplates.append(.strength(.init(title: "Strength workout"))) }
                    Button("Running") { document.sessionTemplates.append(.running(.init(kind: "running", title: "Run", main: [.segment(.init(activity: .run, target: .duration(seconds: 60)))]))) }
                    Button("Cardio") { document.sessionTemplates.append(.cardio(.init(title: "Cardio", main: [.segment(.init(activity: .cycle, target: .duration(seconds: 60)))]))) }
                    Button("Recovery") { document.sessionTemplates.append(.recovery(.init(title: "Recovery", instructions: ""))) }
                    Button("Rest") { document.sessionTemplates.append(.rest(.init(title: "Rest"))) }
                }
                .accessibilityIdentifier("coach.builder.add_template")
                NavigationLink("Copy an Existing Workout Template") { CoachWorkoutLibraryPicker(document: $document) }
            }
            Section("Week patterns") {
                ForEach(document.weekPatterns.indices, id: \.self) { index in
                    NavigationLink(document.weekPatterns[index].title) {
                        CoachPatternEditor(pattern: $document.weekPatterns[index], templates: document.sessionTemplates)
                    }
                    Button("Duplicate \(document.weekPatterns[index].title)") {
                        var copy = document.weekPatterns[index]; copy.id = UUID().uuidString; copy.title += " copy"
                        document.weekPatterns.append(copy)
                    }.font(.caption)
                }
                .onDelete { document.weekPatterns.remove(atOffsets: $0) }
                .onMove { document.weekPatterns.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Week Pattern") { document.weekPatterns.append(.init(title: "Week pattern \(document.weekPatterns.count + 1)")) }
            }
            Section("Phases") {
                ForEach(document.phases.indices, id: \.self) { index in
                    NavigationLink(document.phases[index].title) { CoachPhaseEditor(phase: $document.phases[index]) }
                    Button("Duplicate Phase and Its Weeks") { duplicatePhase(at: index) }.font(.caption).accessibilityIdentifier("coach.builder.duplicate_phase.\(document.phases[index].id)")
                }
                .onDelete { document.phases.remove(atOffsets: $0) }
                .onMove { document.phases.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Phase") { document.phases.append(.init(title: "Phase \(document.phases.count + 1)", advanceMode: .reviewRequired)) }
            }
            Section {
                ForEach(document.weeks.indices, id: \.self) { index in
                    DisclosureGroup("Week \(index + 1)") {
                        TextField("Label", text: optional($document.weeks[index].label))
                        Picker("Phase", selection: $document.weeks[index].phaseId) { ForEach(document.phases) { Text($0.title).tag($0.id) } }
                        Picker("Pattern", selection: $document.weeks[index].weekPatternId) { ForEach(document.weekPatterns) { Text($0.title).tag($0.id) } }
                        Button("Duplicate Week") {
                            var week = document.weeks[index]; week.id = UUID().uuidString
                            document.weeks.insert(week, at: index + 1)
                        }
                    }
                }
                .onDelete { document.weeks.remove(atOffsets: $0) }
                .onMove { document.weeks.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Week") {
                    if let phase = document.phases.last, let pattern = document.weekPatterns.first {
                        document.weeks.append(.init(phaseId: phase.id, weekPatternId: pattern.id))
                    }
                }
            } header: { Text("All \(document.weeks.count) weeks, in order") } footer: {
                Text("List each week explicitly. Reuse a pattern when the prescription repeats. Keep each phase in one consecutive block.")
            }
            Section("Targets and guidance") {
                NavigationLink("Nutrition targets") { CoachAuthoredNutritionEditor(targets: $document.nutritionTargets) }
                NavigationLink("Recovery targets") { CoachAuthoredRecoveryEditor(targets: $document.recoveryTargets) }
                NavigationLink("Reviewed progression rules") { CoachAuthoredProgressionEditor(rules: $document.progressionRules, templates: document.sessionTemplates) }
                TextField("Program guidance", text: optional($document.guidance), axis: .vertical).focused($focusedField, equals: "guidance")
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.builder.error") }
            Button("Review Program") { validate() }.disabled(validating).accessibilityIdentifier("coach.builder.review")
            if validating { ProgressView("Validating…") }
            if let validated { NavigationLink("Open Review") { CoachPlanReviewView(validated: validated) }.accessibilityIdentifier("coach.builder.open_review") }
        }
        .scrollDismissesKeyboard(.interactively).navigationTitle("Build Program")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Button("Review") { validate() }.disabled(validating).accessibilityIdentifier("coach.builder.review_toolbar")
            }
        }
        .onChange(of: document) { _, _ in validated = nil; validationTask?.cancel() }
        .onDisappear { validationTask?.cancel() }
    }
    private func duplicateTemplate(at index: Int) {
        let id = UUID().uuidString
        var copy = document.sessionTemplates[index]
        switch copy {
        case .strength(var value): value.id = id; value.title += " copy"; copy = .strength(value)
        case .running(var value): value.id = id; value.title += " copy"; copy = .running(value)
        case .cardio(var value): value.id = id; value.title += " copy"; copy = .cardio(value)
        case .recovery(var value): value.id = id; value.title += " copy"; copy = .recovery(value)
        case .rest(var value): value.id = id; value.title += " copy"; copy = .rest(value)
        }
        document.sessionTemplates.insert(copy, at: index + 1)
    }
    private func duplicatePhase(at index: Int) {
        let originalID = document.phases[index].id
        var phase = document.phases[index]
        phase.id = UUID().uuidString; phase.title += " copy"
        let weeks = document.weeks.filter { $0.phaseId == originalID }.map { source in
            var copy = source; copy.id = UUID().uuidString; copy.phaseId = phase.id; return copy
        }
        let destination = document.weeks.lastIndex(where: { $0.phaseId == originalID }).map { $0 + 1 } ?? document.weeks.count
        document.phases.insert(phase, at: index + 1)
        document.weeks.insert(contentsOf: weeks, at: destination)
    }
    private func validate() {
        focusedField = nil
        validating = true; error = nil
        let draft = document
        validationTask = Task { @MainActor in
            defer { validating = false }
            do {
                let result = try await Task.detached { try CoachPlanValidator().validate(JSONEncoder().encode(draft)) }.value
                try Task.checkCancellation()
                if document == draft { validated = result }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

private func optional(_ binding: Binding<String?>) -> Binding<String> {
    Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
}

struct CoachPatternEditor: View {
    @Binding var pattern: CoachWeekPattern
    let templates: [CoachSessionTemplate]
    var body: some View {
        Form {
            TextField("Pattern title", text: $pattern.title)
            ForEach(0..<7) { day in
                Section("Day \(day + 1)") {
                    ForEach(pattern.slots.indices.filter { pattern.slots[$0].dayOffset == day }, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Picker("Session", selection: $pattern.slots[index].sessionTemplateId) { ForEach(templates, id: \.id) { Text($0.title).tag($0.id) } }
                            Toggle("Optional", isOn: $pattern.slots[index].optional)
                            TextField("Slot label (optional)", text: optional($pattern.slots[index].label))
                            Button("Move Earlier on This Day") {
                                let peers = pattern.slots.indices.filter { pattern.slots[$0].dayOffset == day }
                                if let position = peers.firstIndex(of: index), position > 0 { pattern.slots.swapAt(index, peers[position - 1]) }
                            }.font(.caption)
                            TextField("Notes", text: optional($pattern.slots[index].notes), axis: .vertical)
                            Button("Remove Session", role: .destructive) { pattern.slots.remove(at: index) }
                        }
                    }
                    Button("Add Session") {
                        if let template = templates.first { pattern.slots.append(.init(dayOffset: day, sessionTemplateId: template.id)) }
                    }.disabled(templates.isEmpty || pattern.slots.filter { $0.dayOffset == day }.count >= 8).accessibilityIdentifier("coach.builder.day.\(day).add_session")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively).navigationTitle("Weekly Schedule")
    }
}

struct CoachPhaseEditor: View {
    @Binding var phase: CoachPhase
    var body: some View {
        Form {
            TextField("Phase title", text: $phase.title)
            TextField("Guidance", text: optional($phase.overview), axis: .vertical)
            Picker("Advance", selection: $phase.advanceMode) {
                Text("By schedule").tag(CoachAdvanceMode.scheduled)
                Text("Readiness review required").tag(CoachAdvanceMode.reviewRequired)
            }
            NavigationLink("Phase nutrition targets") { CoachAuthoredNutritionEditor(targets: $phase.nutritionTargets) }
            NavigationLink("Phase recovery targets") { CoachAuthoredRecoveryEditor(targets: $phase.recoveryTargets) }
            Text("A phase target replaces its entire program-level block; omitted values remain unset.").font(.caption)
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Edit Phase")
    }
}

struct CoachAuthoredNutritionEditor: View {
    @Binding var targets: CoachNutritionTargets?
    var body: some View {
        Form {
            Toggle("Set nutrition targets", isOn: Binding(get: { targets != nil }, set: { targets = $0 ? .init() : nil }))
            if targets != nil {
                TextField("Calories (kcal)", value: Binding(get: { targets?.caloriesKcal }, set: { targets?.caloriesKcal = $0 }), format: .number).keyboardType(.numberPad)
                TextField("Protein (g)", value: Binding(get: { targets?.proteinGrams }, set: { targets?.proteinGrams = $0 }), format: .number).keyboardType(.decimalPad)
                TextField("Carbohydrate (g)", value: Binding(get: { targets?.carbohydrateGrams }, set: { targets?.carbohydrateGrams = $0 }), format: .number).keyboardType(.decimalPad)
                TextField("Fat (g)", value: Binding(get: { targets?.fatGrams }, set: { targets?.fatGrams = $0 }), format: .number).keyboardType(.decimalPad)
                TextField("Notes", text: Binding(get: { targets?.notes ?? "" }, set: { targets?.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Nutrition Targets")
    }
}

struct CoachTemplateEditor: View {
    @Binding var template: CoachSessionTemplate
    var body: some View {
        Group {
            switch template {
            case .strength(let value): CoachStrengthTemplateEditor(value: Binding(get: { if case .strength(let value) = template { return value }; return value }, set: { template = .strength($0) }))
            case .running(let value): CoachCardioTemplateEditor(value: Binding(get: { if case .running(let value) = template { return value }; return value }, set: { template = .running($0) }))
            case .cardio(let value): CoachCardioTemplateEditor(value: Binding(get: { if case .cardio(let value) = template { return value }; return value }, set: { template = .cardio($0) }))
            case .recovery:
                Form {
                    TextField("Title", text: Binding(get: { template.title }, set: { if case .recovery(var copy) = template { copy.title = $0; template = .recovery(copy) } }))
                    TextField("Instructions", text: Binding(get: { if case .recovery(let current) = template { return current.instructions }; return "" }, set: { if case .recovery(var copy) = template { copy.instructions = $0; template = .recovery(copy) } }), axis: .vertical)
                    TextField("Duration seconds (optional)", value: Binding(get: { if case .recovery(let current) = template { return current.durationSeconds }; return nil }, set: { if case .recovery(var copy) = template { copy.durationSeconds = $0; template = .recovery(copy) } }), format: .number).keyboardType(.numberPad)
                }
            case .rest:
                Form {
                    TextField("Title", text: Binding(get: { template.title }, set: { if case .rest(var copy) = template { copy.title = $0; template = .rest(copy) } }))
                    TextField("Notes", text: Binding(get: { template.notes ?? "" }, set: { if case .rest(var copy) = template { copy.notes = $0.isEmpty ? nil : $0; template = .rest(copy) } }), axis: .vertical)
                }
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Edit Session")
    }
}

struct CoachStrengthTemplateEditor: View {
    @Binding var value: CoachStrengthSession
    @Query(sort: \ExerciseDefinition.name) private var exercises: [ExerciseDefinition]
    @State private var selectedExercise: UUID?
    @State private var customName = ""
    var body: some View {
        Form {
            TextField("Title", text: $value.title)
            TextField("Notes", text: optional($value.notes), axis: .vertical)
            Section("Exercises") {
                ForEach(value.exercises.indices, id: \.self) { index in
                    NavigationLink(value.exercises[index].exercise.name) { CoachExercisePrescriptionEditor(value: $value.exercises[index]) }
                }
                .onDelete { value.exercises.remove(atOffsets: $0) }
                .onMove { value.exercises.move(fromOffsets: $0, toOffset: $1) }
            }
            Section("Add from your exercise library") {
                Picker("Exercise", selection: $selectedExercise) {
                    Text("Choose exercise").tag(Optional<UUID>.none)
                    ForEach(exercises) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("Add Exercise") {
                    if let definition = exercises.first(where: { $0.id == selectedExercise }) {
                        add(.init(key: definition.id.uuidString, name: definition.name, catalogExerciseId: definition.id.uuidString))
                    }
                }.disabled(selectedExercise == nil)
            }
            Section("Custom exercise") {
                TextField("Exercise name", text: $customName)
                Button("Add Custom Exercise") { add(.init(key: UUID().uuidString, name: customName)); customName = "" }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.scrollDismissesKeyboard(.interactively).toolbar { EditButton() }
    }
    private func add(_ choice: CoachExerciseChoice) {
        value.exercises.append(.init(exercise: choice, prescriptionBasis: .total, loadBasis: .totalExternal,
            sets: [.init(role: .working, target: .reps(min: 8, max: 12))]))
    }
}

struct CoachExercisePrescriptionEditor: View {
    @Binding var value: CoachStrengthExercise
    @State private var equipment = ""
    @State private var alternative = ""
    var body: some View {
        Form {
            TextField("Name", text: $value.exercise.name)
            DisclosureGroup("Movement identity") {
                Text(value.exercise.key).font(.caption.monospaced())
                Text("Keep this identity for the same authored movement. If you change to an incompatible movement or equipment, create a new identity.").font(.caption)
                Button("Use a New Custom Movement Identity") { value.exercise.key = UUID().uuidString; value.exercise.catalogExerciseId = nil }
            }
            TextField("Equipment (comma separated)", text: $equipment).onChange(of: equipment) { _, text in value.exercise.equipment = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            Picker("Rep/time basis", selection: $value.prescriptionBasis) { Text("Total").tag(CoachPrescriptionBasis.total); Text("Per side").tag(CoachPrescriptionBasis.perSide) }
            Picker("Load basis", selection: $value.loadBasis) { ForEach(CoachLoadBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Technique notes", text: optional($value.notes), axis: .vertical)
            Section("Per-set targets") {
                ForEach(value.sets.indices, id: \.self) { index in
                    NavigationLink("Set \(index + 1): \(CoachPresentation.set(value.sets[index]))") { CoachSetPrescriptionEditor(value: $value.sets[index]) }
                }.onDelete { value.sets.remove(atOffsets: $0) }.onMove { value.sets.move(fromOffsets: $0, toOffset: $1) }
                Button("Add Set") { value.sets.append(.init(role: .working, target: .reps(min: 8, max: 12))) }
            }
            Section("Equipment alternatives") {
                ForEach((value.substitutions ?? []).indices, id: \.self) { index in
                    NavigationLink(value.substitutions?[index].name ?? "Alternative") {
                        CoachMovementChoiceEditor(choice: Binding(get: { value.substitutions![index] }, set: { value.substitutions?[index] = $0 }))
                    }
                }.onDelete { value.substitutions?.remove(atOffsets: $0) }
                Text("Selecting an alternative preserves targets until review, clears suggested loads, and requires confirmation of the load basis in the workout.").font(.caption).foregroundStyle(.secondary)
                TextField("Alternative exercise", text: $alternative)
                Button("Add Alternative") { var choices = value.substitutions ?? []; choices.append(.init(key: UUID().uuidString, name: alternative)); value.substitutions = choices; alternative = "" }.disabled(alternative.isEmpty)
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Exercise Prescription").toolbar { EditButton() }.onAppear { equipment = value.exercise.equipment.joined(separator: ", ") }
    }
}

struct CoachSetPrescriptionEditor: View {
    @Binding var value: CoachStrengthSet
    var body: some View {
        Form {
            Picker("Set role", selection: $value.role) { ForEach(CoachSetRole.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            Picker("Target", selection: Binding(get: { if case .reps = value.target { return "reps" }; return "duration" }, set: { value.target = $0 == "reps" ? .reps(min: 8, max: 12) : .duration(seconds: 30) })) { Text("Rep range").tag("reps"); Text("Time").tag("duration") }
            switch value.target {
            case .reps(let min, let max):
                TextField("Minimum reps", value: Binding(get: { if case .reps(let min, _) = value.target { return min }; return min }, set: { if case .reps(_, let currentMax) = value.target { value.target = .reps(min: $0, max: currentMax) } }), format: .number).keyboardType(.numberPad)
                TextField("Maximum reps", value: Binding(get: { if case .reps(_, let max) = value.target { return max }; return max }, set: { if case .reps(let currentMin, _) = value.target { value.target = .reps(min: currentMin, max: $0) } }), format: .number).keyboardType(.numberPad)
            case .duration(let seconds): TextField("Seconds", value: Binding(get: { if case .duration(let seconds) = value.target { return seconds }; return seconds }, set: { value.target = .duration(seconds: $0) }), format: .number).keyboardType(.numberPad)
            }
            Toggle("Prescribe load", isOn: Binding(get: { value.load != nil }, set: { value.load = $0 ? .init(value: 0, unit: .kg) : nil }))
            if value.load != nil {
                TextField("Load", value: Binding(get: { value.load?.value ?? 0 }, set: { value.load?.value = $0 }), format: .number).keyboardType(.decimalPad)
                Picker("Load unit", selection: Binding(get: { value.load?.unit ?? .kg }, set: { value.load?.unit = $0 })) { ForEach(CoachWeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Toggle("Prescribe effort", isOn: Binding(get: { value.effort != nil }, set: { value.effort = $0 ? .init(scale: .rir, min: 2, max: 3) : nil }))
            if value.effort != nil {
                Picker("Effort scale", selection: Binding(get: { value.effort?.scale ?? .rir }, set: { value.effort?.scale = $0 })) { Text("RIR").tag(CoachEffortScale.rir); Text("RPE").tag(CoachEffortScale.rpe) }
                TextField("Minimum effort", value: Binding(get: { value.effort?.min }, set: { if let new = $0 { value.effort?.min = new } }), format: .number).keyboardType(.decimalPad)
                TextField("Maximum effort", value: Binding(get: { value.effort?.max }, set: { if let new = $0 { value.effort?.max = new } }), format: .number).keyboardType(.decimalPad)
            }
            TextField("Rest after set (seconds)", value: $value.restAfterSeconds, format: .number).keyboardType(.numberPad)
            TextField("Notes", text: optional($value.notes), axis: .vertical)
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Set Target")
    }
}

struct CoachCardioTemplateEditor: View {
    @Binding var value: CoachCardioSession
    var body: some View {
        Form {
            TextField("Title", text: $value.title)
            CoachBlockListEditor(title: "Warm-up", blocks: $value.warmup, running: value.kind == "running")
            CoachBlockListEditor(title: "Main session", blocks: $value.main, running: value.kind == "running")
            CoachBlockListEditor(title: "Cool-down", blocks: $value.cooldown, running: value.kind == "running")
            TextField("Notes", text: optional($value.notes), axis: .vertical)
        }.scrollDismissesKeyboard(.interactively).toolbar { EditButton() }
    }
}

struct CoachBlockListEditor: View {
    let title: String
    @Binding var blocks: [CoachIntervalBlock]
    let running: Bool
    var body: some View {
        Section(title) {
            ForEach(blocks.indices, id: \.self) { index in
                NavigationLink(CoachPresentation.block(blocks[index])) { CoachBlockEditor(block: $blocks[index], running: running) }
            }.onDelete { blocks.remove(atOffsets: $0) }.onMove { blocks.move(fromOffsets: $0, toOffset: $1) }
            Button("Add Segment") { blocks.append(.segment(.init(activity: running ? .run : .cycle, target: .duration(seconds: 60)))) }
            Button("Add Repeated Intervals") { blocks.append(.repeatBlock(.init(count: 2, segments: [.init(activity: running ? .run : .cycle, target: .duration(seconds: 60)), .init(activity: .walk, target: .duration(seconds: 60))]))) }
        }
    }
}

struct CoachBlockEditor: View {
    @Binding var block: CoachIntervalBlock
    let running: Bool
    var body: some View {
        Form {
            switch block {
            case .segment(let value): CoachSegmentEditor(segment: Binding(get: { if case .segment(let current) = block { return current }; return value }, set: { block = .segment($0) }), running: running)
            case .repeatBlock(let value):
                Stepper("Repeat \(value.count) times", value: Binding(get: { if case .repeatBlock(let current) = block { return current.count }; return value.count }, set: { if case .repeatBlock(var copy) = block { copy.count = $0; block = .repeatBlock(copy) } }), in: 2...100)
                TextField("Repeat notes", text: Binding(get: { if case .repeatBlock(let current) = block { return current.notes ?? "" }; return "" }, set: { text in if case .repeatBlock(var copy) = block { copy.notes = text.isEmpty ? nil : text; block = .repeatBlock(copy) } }), axis: .vertical)
                ForEach(value.segments.indices, id: \.self) { index in
                    DisclosureGroup("Segment \(index + 1)") {
                        CoachSegmentEditor(segment: Binding(get: { if case .repeatBlock(let current) = block { return current.segments[index] }; return value.segments[index] }, set: { new in if case .repeatBlock(var copy) = block { copy.segments[index] = new; block = .repeatBlock(copy) } }), running: running)
                    }
                }
                .onDelete { offsets in if case .repeatBlock(var copy) = block { copy.segments.remove(atOffsets: offsets); block = .repeatBlock(copy) } }
                .onMove { offsets, destination in if case .repeatBlock(var copy) = block { copy.segments.move(fromOffsets: offsets, toOffset: destination); block = .repeatBlock(copy) } }
                Button("Add Segment to Repeat") { if case .repeatBlock(var copy) = block { copy.segments.append(.init(activity: .walk, target: .duration(seconds: 60))); block = .repeatBlock(copy) } }
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Interval Target").toolbar { EditButton() }
    }
}

struct CoachSegmentEditor: View {
    @Binding var segment: CoachSegment
    let running: Bool
    var body: some View {
        TextField("Segment title (optional)", text: optional($segment.title))
        Picker("Activity", selection: $segment.activity) { ForEach(running ? [.walk, .jog, .run] : CoachActivity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
        Picker("Goal", selection: Binding(get: { if case .duration = segment.target { return "time" }; return "distance" }, set: { segment.target = $0 == "time" ? .duration(seconds: 60) : .distance(.init(value: 100, unit: .m)) })) { Text("Time").tag("time"); Text("Distance").tag("distance") }
        switch segment.target {
        case .duration(let seconds): TextField("Seconds", value: Binding(get: { if case .duration(let current) = segment.target { return current }; return seconds }, set: { segment.target = .duration(seconds: $0) }), format: .number).keyboardType(.numberPad)
        case .distance(let distance):
            TextField("Distance", value: Binding(get: { if case .distance(let current) = segment.target { return current.value }; return distance.value }, set: { if case .distance(var current) = segment.target { current.value = $0; segment.target = .distance(current) } }), format: .number).keyboardType(.decimalPad)
            Picker("Unit", selection: Binding(get: { if case .distance(let current) = segment.target { return current.unit }; return distance.unit }, set: { if case .distance(var current) = segment.target { current.unit = $0; segment.target = .distance(current) } })) { ForEach(CoachDistanceUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        }
        CoachSegmentIntensityEditor(intensity: $segment.intensity)
        TextField("Intensity cue", text: Binding(get: { segment.intensity?.cue ?? "" }, set: { text in
            if text.isEmpty { segment.intensity?.cue = nil; if segment.intensity?.rpe == nil && segment.intensity?.pace == nil { segment.intensity = nil } }
            else { if segment.intensity == nil { segment.intensity = .init() }; segment.intensity?.cue = text }
        }), axis: .vertical)
        TextField("Notes", text: optional($segment.notes), axis: .vertical)
    }
}

private struct CoachAuthoredRecoveryEditor: View {
    @Binding var targets: CoachRecoveryTargets?
    var body: some View {
        Form {
            Toggle("Set recovery guidance", isOn: Binding(get: { targets != nil }, set: { targets = $0 ? .init() : nil }))
            if targets != nil {
                Toggle("Sleep range", isOn: Binding(get: { targets?.sleepHours != nil }, set: { targets?.sleepHours = $0 ? .init(min: 0, max: 0) : nil }))
                if targets?.sleepHours != nil {
                    TextField("Minimum hours", value: Binding(get: { targets?.sleepHours?.min }, set: { if let value = $0 { targets?.sleepHours?.min = value } }), format: .number).keyboardType(.decimalPad)
                    TextField("Maximum hours", value: Binding(get: { targets?.sleepHours?.max }, set: { if let value = $0 { targets?.sleepHours?.max = value } }), format: .number).keyboardType(.decimalPad)
                }
                Section("Suggested check-in fields") {
                    ForEach(CoachCheckInField.allCases, id: \.self) { field in
                        Toggle(field.rawValue.capitalized, isOn: Binding(get: { targets?.checkInFields?.contains(field) == true }, set: { selected in
                            var fields = targets?.checkInFields ?? []
                            if selected && !fields.contains(field) { fields.append(field) }
                            else if !selected { fields.removeAll { $0 == field } }
                            targets?.checkInFields = fields.isEmpty ? nil : fields
                        }))
                    }
                }
                TextField("Recovery notes", text: Binding(get: { targets?.notes ?? "" }, set: { targets?.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                Text("Include at least one range, check-in field, or note. Targets are guidance, not actual check-in values.").font(.caption).foregroundStyle(.secondary)
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Recovery Targets")
    }
}

private struct CoachSegmentIntensityEditor: View {
    @Binding var intensity: CoachSegmentIntensity?
    var body: some View {
        Toggle("Structured RPE range", isOn: Binding(get: { intensity?.rpe != nil }, set: { enabled in
            if enabled { ensureIntensity(); intensity?.rpe = .init(scale: .rpe, min: 1, max: 1) }
            else { intensity?.rpe = nil; removeEmptyIntensity() }
        }))
        if intensity?.rpe != nil {
            TextField("Minimum RPE", value: Binding(get: { intensity?.rpe?.min }, set: { if let value = $0 { intensity?.rpe?.min = value } }), format: .number).keyboardType(.decimalPad)
            TextField("Maximum RPE", value: Binding(get: { intensity?.rpe?.max }, set: { if let value = $0 { intensity?.rpe?.max = value } }), format: .number).keyboardType(.decimalPad)
        }
        Toggle("Structured pace range", isOn: Binding(get: { intensity?.pace != nil }, set: { enabled in
            if enabled { ensureIntensity(); intensity?.pace = .init(minSeconds: 300, maxSeconds: 360, per: .km) }
            else { intensity?.pace = nil; removeEmptyIntensity() }
        }))
        if intensity?.pace != nil {
            TextField("Faster pace (seconds)", value: Binding(get: { intensity?.pace?.minSeconds }, set: { if let value = $0 { intensity?.pace?.minSeconds = value } }), format: .number).keyboardType(.numberPad)
            TextField("Slower pace (seconds)", value: Binding(get: { intensity?.pace?.maxSeconds }, set: { if let value = $0 { intensity?.pace?.maxSeconds = value } }), format: .number).keyboardType(.numberPad)
            Picker("Pace distance", selection: Binding(get: { intensity?.pace?.per ?? .km }, set: { intensity?.pace?.per = $0 })) {
                ForEach(CoachPreferredDistanceUnit.allCases, id: \.self) { Text("per \($0.rawValue)").tag($0) }
            }
            Text("Pace stays numeric. The faster bound must not exceed the slower bound.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func ensureIntensity() { if intensity == nil { intensity = .init() } }
    private func removeEmptyIntensity() { if intensity?.rpe == nil && intensity?.pace == nil && intensity?.cue == nil { intensity = nil } }
}

private struct CoachMovementChoiceEditor: View {
    @Binding var choice: CoachExerciseChoice
    @Query(sort: \ExerciseDefinition.name) private var catalog: [ExerciseDefinition]
    @State private var equipment = ""
    var body: some View {
        Form {
            TextField("Movement name", text: $choice.name)
            TextField("Equipment (comma separated)", text: $equipment)
                .onChange(of: equipment) { _, value in choice.equipment = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            Picker("Catalog identity", selection: $choice.catalogExerciseId) {
                Text("Custom / unresolved").tag(Optional<String>.none)
                ForEach(catalog) { Text($0.name).tag(Optional($0.id.uuidString)) }
            }
            .onChange(of: choice.catalogExerciseId) { _, id in
                if let entry = catalog.first(where: { $0.id.uuidString == id }) { choice.name = entry.name }
            }
            Text("Authored movement key: \(choice.key)").font(.caption.monospaced())
            Text("The same key must retain a compatible name, equipment, and catalog identity throughout the program.").font(.caption).foregroundStyle(.secondary)
            Button("Use a New Movement Identity") { choice.key = UUID().uuidString }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Movement Choice")
            .onAppear { equipment = choice.equipment.joined(separator: ", ") }
    }
}

private struct CoachAuthoredProgressionEditor: View {
    @Binding var rules: [CoachProgressionRule]?
    let templates: [CoachSessionTemplate]
    var body: some View {
        List {
            Section {
                Text("Every rule proposes a review. Nothing automatically changes future load, pace, nutrition, or health records.").font(.subheadline)
            }
            ForEach((rules ?? []).indices, id: \.self) { index in
                NavigationLink(rules?[index].title ?? "Rule") {
                    CoachProgressionRuleEditor(rule: Binding(get: { rules![index] }, set: { rules?[index] = $0 }), templates: templates)
                }
            }.onDelete { rules?.remove(atOffsets: $0) }.onMove { rules?.move(fromOffsets: $0, toOffset: $1) }
            Button("Add Double Progression Review") {
                let strength = templates.first { if case .strength = $0 { true } else { false } }
                let exerciseID: String
                if case let .strength(session) = strength { exerciseID = session.exercises.first?.id ?? "choose-exercise" }
                else { exerciseID = "choose-exercise" }
                var values = rules ?? []
                values.append(.doubleProgression(.init(title: "Review load progression", sessionTemplateId: strength?.id ?? "choose-template", exerciseId: exerciseID,
                                                       requiredSuccessfulOccurrences: 2, minimumRIR: 2, increment: .init(value: 1, unit: .kg))))
                rules = values
            }
            Button("Add Manual Progression Review") {
                var values = rules ?? []
                values.append(.manualReview(.init(title: "Review progression", sessionTemplateIds: templates.first.map { [$0.id] } ?? [], instructions: "")))
                rules = values
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Progression Rules").toolbar { EditButton() }
    }
}

private struct CoachProgressionRuleEditor: View {
    @Binding var rule: CoachProgressionRule
    let templates: [CoachSessionTemplate]
    var body: some View {
        Group {
            switch rule {
            case let .doubleProgression(value):
                CoachDoubleProgressionEditor(value: Binding(get: { if case let .doubleProgression(current) = rule { return current }; return value }, set: { rule = .doubleProgression($0) }), templates: templates)
            case let .manualReview(value):
                CoachManualProgressionEditor(value: Binding(get: { if case let .manualReview(current) = rule { return current }; return value }, set: { rule = .manualReview($0) }), templates: templates)
            }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Review Rule")
    }
}

private struct CoachDoubleProgressionEditor: View {
    @Binding var value: CoachDoubleProgressionRule
    let templates: [CoachSessionTemplate]
    private var strength: [CoachStrengthSession] { templates.compactMap { if case let .strength(session) = $0 { session } else { nil } } }
    private var rows: [CoachStrengthExercise] { strength.first { $0.id == value.sessionTemplateId }?.exercises ?? [] }
    var body: some View {
        Form {
            TextField("Title", text: $value.title)
            Picker("Strength template", selection: $value.sessionTemplateId) { ForEach(strength) { Text($0.title).tag($0.id) } }
                .onChange(of: value.sessionTemplateId) { _, _ in value.exerciseId = rows.first?.id ?? "choose-exercise" }
            Picker("Exercise row", selection: $value.exerciseId) { ForEach(rows) { Text($0.exercise.name).tag($0.id) } }
            Stepper("Consecutive successful sessions: \(value.requiredSuccessfulOccurrences)", value: $value.requiredSuccessfulOccurrences, in: 1...10)
            TextField("Minimum actual RIR", value: $value.minimumRIR, format: .number).keyboardType(.decimalPad)
            TextField("Equipment load increment", value: $value.increment.value, format: .number).keyboardType(.decimalPad)
            Picker("Increment unit", selection: $value.increment.unit) { ForEach(CoachWeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            TextField("Notes", text: optional($value.notes), axis: .vertical)
            Text("The increment refers to this exercise's load basis. Every working set must prescribe reps and RIR; the final review checks these requirements. Actual performance, documented readiness, and explicit acceptance are required before any change.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CoachManualProgressionEditor: View {
    @Binding var value: CoachManualReviewRule
    let templates: [CoachSessionTemplate]
    var body: some View {
        Form {
            TextField("Title", text: $value.title)
            Section("Referenced templates") {
                ForEach(templates) { template in
                    Toggle(template.title, isOn: Binding(get: { value.sessionTemplateIds.contains(template.id) }, set: { selected in
                        if selected && !value.sessionTemplateIds.contains(template.id) { value.sessionTemplateIds.append(template.id) }
                        else if !selected { value.sessionTemplateIds.removeAll { $0 == template.id } }
                    }))
                }
            }
            TextField("Instructions to review", text: $value.instructions, axis: .vertical).lineLimit(5...12)
            Text("These instructions are displayed for review. They are never interpreted as formulas or executable actions.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct CoachWorkoutLibraryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var document: CoachPlanDocument
    @Query(sort: \WorkoutTemplate.title) private var templates: [WorkoutTemplate]
    @Query(sort: \ExerciseDefinition.name) private var catalog: [ExerciseDefinition]
    @State private var error: String?
    @State private var loadBases: [UUID: CoachLoadBasis] = [:]
    @State private var repBases: [UUID: CoachPrescriptionBasis] = [:]
    @State private var keepSuggestedLoads = false
    var body: some View {
        List {
            Section {
                Text("Copy a library workout into this program, then review its sets and movement details. Later library edits do not alter this program's copy.")
                Text("Legacy templates do not record load basis, structured rest or effort. Those values require review; they are not recovered from notes.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Toggle("Retain suggested loads after reviewing their basis", isOn: $keepSuggestedLoads)
            ForEach(templates) { template in
                DisclosureGroup(template.title) {
                    ForEach((template.exercises ?? []).sorted { $0.order < $1.order }) { row in
                        VStack(alignment: .leading) {
                            Text(row.name).font(.headline)
                            Text("\(row.sets) sets × \(row.reps) reps").font(.caption)
                            Picker("Load basis", selection: Binding(get: { loadBases[row.id] }, set: { loadBases[row.id] = $0 })) {
                                Text("Choose reviewed basis").tag(Optional<CoachLoadBasis>.none)
                                ForEach(CoachLoadBasis.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                            }
                            Picker("Rep / time basis", selection: Binding(get: { repBases[row.id] }, set: { repBases[row.id] = $0 })) {
                                Text("Choose reviewed basis").tag(Optional<CoachPrescriptionBasis>.none)
                                ForEach(CoachPrescriptionBasis.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                            }
                            if let load = row.suggestedWeight { Text("Legacy suggested load: \(load.formatted()) \(row.weightUnit)").font(.caption) }
                        }
                    }
                    Button("Copy Reviewed Template") { copy(template) }
                        .disabled((template.exercises ?? []).contains { loadBases[$0.id] == nil || repBases[$0.id] == nil })
                }
            }
            if templates.isEmpty { Text("No saved workout templates yet.").foregroundStyle(.secondary) }
        }.scrollDismissesKeyboard(.interactively).navigationTitle("Workout Library")
    }
    private func copy(_ template: WorkoutTemplate) {
        do {
            let sourceRows = (template.exercises ?? []).sorted { $0.order < $1.order }
            guard !sourceRows.isEmpty else { throw CoachRepositoryError.invalidValue("library template containing exercise rows") }
            var authoredChoices = document.sessionTemplates.flatMap { template -> [CoachExerciseChoice] in
                guard case let .strength(session) = template else { return [] }
                return session.exercises.flatMap { [$0.exercise] + ($0.substitutions ?? []) }
            }
            let rows = try sourceRows.map { source -> CoachStrengthExercise in
                guard (0...20).contains(source.sets), (0...200).contains(source.reps) else {
                    throw CoachRepositoryError.invalidValue("legacy set/rep counts within the supported resource limits for \(source.name); nothing was truncated")
                }
                let exact = catalog.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == source.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                let catalogID = exact.count == 1 ? exact.first?.id.uuidString : nil
                let choice = authoredChoices.first { $0.catalogExerciseId == catalogID && catalogID != nil }
                    ?? authoredChoices.first { $0.name == source.name && $0.equipment.isEmpty && $0.catalogExerciseId == catalogID }
                    ?? CoachExerciseChoice(key: catalogID ?? UUID().uuidString, name: source.name, catalogExerciseId: catalogID)
                authoredChoices.append(choice)
                guard let loadBasis = loadBases[source.id], let repBasis = repBases[source.id] else { throw CoachRepositoryError.invalidValue("reviewed load and repetition basis for \(source.name)") }
                var reviewedLoad: CoachWeight?
                if keepSuggestedLoads, let load = source.suggestedWeight {
                    guard ["kg", "lb", "lbs"].contains(source.weightUnit), load.isFinite, (0...1000).contains(load) else { throw CoachRepositoryError.invalidValue("supported suggested load and unit for \(source.name)") }
                    reviewedLoad = .init(value: load, unit: source.weightUnit == "kg" ? .kg : .lb)
                }
                let sets = (0..<source.sets).map { _ in CoachStrengthSet(role: .working, target: .reps(min: source.reps, max: source.reps), load: reviewedLoad, notes: "Review legacy target; rest and effort were not recorded.") }
                var review = "Review load basis, per-side interpretation, and equipment before activation."
                if source.sets == 0 || source.reps == 0 { review += " Essential legacy set or rep targets were absent. This row stays invalid until you add or correct its targets in the Coach editor; timed prescriptions must be entered explicitly." }
                if let load = source.suggestedWeight { review += " Legacy suggested load: \(load) \(source.weightUnit); it is not applied until its basis is reviewed." }
                if let notes = source.notes { review += "\n" + notes }
                return CoachStrengthExercise(exercise: choice, prescriptionBasis: repBasis, loadBasis: loadBasis, sets: sets, notes: review)
            }
            document.sessionTemplates.append(.strength(.init(title: template.title, exercises: rows, notes: template.notes)))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
