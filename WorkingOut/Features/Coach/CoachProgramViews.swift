import SwiftUI
import SwiftData

struct CoachProgramLibraryView: View {
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var plans: [TrainingPlan]
    var body: some View {
        List {
            NavigationLink { CoachAddPlanView() } label: { Label("Add Plan", systemImage: "plus.circle.fill") }
                .accessibilityIdentifier("coach.add_plan")
            ForEach(CoachPlanStatus.allCases, id: \.self) { status in
                let matching = plans.filter { $0.status == status.rawValue }
                if !matching.isEmpty {
                    Section(status.rawValue.capitalized) {
                        ForEach(matching) { plan in
                            NavigationLink { CoachProgramDetailView(plan: plan) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.title).font(.headline)
                                    Text(plan.goal).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    if plan.durationWeeks > 0 { Text("\(plan.durationWeeks) weeks").font(.caption) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CoachProgramDetailView: View {
    let plan: TrainingPlan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allSessions: [PlannedSession]
    @Query private var allPlans: [TrainingPlan]
    @Query private var gates: [CoachPhaseReview]
    @State private var document: CoachPlanDocument?
    @State private var selectedWeek = 0
    @State private var error: String?
    @State private var confirmActivate = false
    @State private var exportDocument: CoachProgramFile?
    @State private var exporting = false
    @State private var reviewExport = false
    @State private var startDate = Date()
    @State private var confirmingDelete = false
    @State private var deleting = false
    @Query private var calendarMappings: [CoachCalendarMapping]
    private var rows: [PlannedSession] { allSessions.filter { $0.plan?.id == plan.id }.sorted { ($0.scheduledDate, $0.intraDayOrder) < ($1.scheduledDate, $1.intraDayOrder) } }
    private var weeks: [Int] { Array(Set(rows.map(\.weekIndex)).union(0..<max(0, plan.durationWeeks))).sorted() }
    var body: some View {
        List {
            Section {
                Text(plan.title).font(.title2.bold())
                Text(plan.goal)
                Text(plan.status.capitalized + " · " + (plan.startCivilDate ?? CoachDate.civil(plan.startDate))).foregroundStyle(.secondary)
                if let overview = plan.overview { Text(overview) }
                if plan.timeZoneIdentifier != TimeZone.current.identifier, !plan.timeZoneIdentifier.isEmpty {
                    Text("This program keeps its dates in \(plan.timeZoneIdentifier). Your device is now in \(TimeZone.current.identifier). Review future dates and reminders before changing the schedule.").font(.caption)
                }
            }
            Section("Program actions") {
                if plan.status != "active" {
                    Button("Review Start or Resume") { confirmActivate = true }
                } else { Button("Pause Program") { perform { try $0.setPlanStatus(planID: plan.id, status: .paused) } } }
                NavigationLink("Move, swap or repeat sessions") { CoachScheduleEditorView(plan: plan) }
                NavigationLink("Review progression") { CoachProgressionReviewView(plan: plan) }
                NavigationLink("Calendar and reminders") { CoachCalendarReviewView(plan: plan) }
                if let document {
                    NavigationLink("Edit a new revision") {
                        CoachPlanBuilderView(document: revised(document))
                    }
                    Button("Review Program Export") { reviewExport = true }
                }
                Button("Mark Program Finished") { perform { try $0.setPlanStatus(planID: plan.id, status: .finished) } }
                Button(plan.status == "archived" ? "Return to Draft" : "Archive Program") {
                    perform { try $0.setPlanStatus(planID: plan.id, status: plan.status == "archived" ? .draft : .archived) }
                }
                if plan.currentRevisionID != nil { Button("Delete Program", role: .destructive) { confirmingDelete = true }.disabled(deleting) }
            }
            Section("Phase readiness") {
                ForEach(gates.filter { gate in gate.planID == plan.id && (gate.revisionID == plan.currentRevisionID || rows.contains { $0.revisionID == gate.revisionID && $0.phaseID == gate.phaseID && $0.status == "pending" }) }) { gate in
                    VStack(alignment: .leading, spacing: 8) {
                        let phase = phase(for: gate)
                        Text(phase?.title ?? gate.phaseID).font(.headline)
                        if let overview = phase?.overview { Text(overview) }
                        if let targets = phase?.recoveryTargets {
                            if let sleep = targets.sleepHours { Text("Sleep guidance: \(sleep.min.formatted())–\(sleep.max.formatted()) hours") }
                            if let fields = targets.checkInFields { Text("Suggested check-ins: " + fields.map(\.rawValue).joined(separator: ", ")) }
                            if let notes = targets.notes { Text(notes) }
                        }
                        DisclosureGroup("Review this phase’s sessions") {
                            ForEach(rows.filter { $0.revisionID == gate.revisionID && $0.phaseID == gate.phaseID }) { CoachSessionRow(session: $0, showDate: true) }
                        }
                        Text(gate.statusRaw == "ready" ? "Readiness confirmed" : "Awaiting your review").foregroundStyle(.secondary)
                        if gate.revisionID != plan.currentRevisionID { Text("Retained earlier prescription").font(.caption) }
                        if gate.statusRaw != "ready" {
                            Button("I reviewed this phase and am ready") { perform { try $0.reviewPhase(planID: plan.id, phaseID: gate.phaseID, ready: true, revisionID: gate.revisionID) } }
                        }
                    }
                }
            }
            Section("Weeks") {
                Picker("Selected week", selection: $selectedWeek) { ForEach(weeks, id: \.self) { Text("Week \($0 + 1)").tag($0) } }
                    .accessibilityIdentifier("coach.program.week")
                ForEach(rows.filter { $0.weekIndex == selectedWeek }) { CoachSessionRow(session: $0, showDate: true) }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Program")
        .task(id: plan.currentRevisionID) { do { document = try CoachRepository(context: context).document(for: plan); startDate = plan.startDate; selectedWeek = weeks.first ?? 0 } catch { self.error = error.localizedDescription } }
        .confirmationDialog("Delete this program?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            if calendarMappings.contains(where: { mapping in rows.contains { $0.id == mapping.plannedSessionID } }) {
                Button("Remove App Calendar Events and Delete", role: .destructive) { deleteProgram(keepCalendarEvents: false) }
                Button("Keep Calendar Events and Delete", role: .destructive) { deleteProgram(keepCalendarEvents: true) }
            } else {
                Button("Delete Program", role: .destructive) { deleteProgram(keepCalendarEvents: false) }
            }
        } message: {
            Text("Completed workouts, measurements and daily check-ins are preserved. Finish any activity in progress first. Program reminders are canceled.")
        }
        .confirmationDialog("Start \(plan.title)?", isPresented: $confirmActivate, titleVisibility: .visible) {
            Button("Keep Existing Dates") { perform { try $0.activate(planID: plan.id) } }
        } message: {
            Text((allPlans.first(where: { $0.id != plan.id && $0.status == "active" }).map { "This pauses “\($0.title)” and preserves its history. " } ?? "") + "Session dates stay fixed. To shift remaining work, open Move, swap or repeat sessions and review every affected date before applying.")
        }
        .sheet(isPresented: $reviewExport) {
            NavigationStack {
                List {
                    Text("This export includes prescriptions, guidance, and notes. Review notes for personal information before sharing. Actual logs and schedule dates are kept in your history backup.")
                    if let document { CoachProgramPreview(document: document, startDate: plan.startDate, timeZone: CoachRepository.timeZone(plan)) }
                    Button("Export Reviewed Program") {
                        do {
                            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            exportDocument = CoachProgramFile(data: try encoder.encode(document)); reviewExport = false; exporting = true
                        } catch { self.error = error.localizedDescription }
                    }
                }.navigationTitle("Review Export").toolbar { Button("Close") { reviewExport = false } }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .coachProgram, defaultFilename: "Coach Program") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }
    private func revised(_ value: CoachPlanDocument) -> CoachPlanDocument { var copy = value; copy.revision += 1; return copy }
    private func phase(for gate: CoachPhaseReview) -> CoachPhase? {
        let source: CoachPlanDocument?
        if gate.revisionID == plan.currentRevisionID { source = document }
        else {
            guard let revisionID = gate.revisionID,
                  let revision = try? context.fetch(FetchDescriptor<CoachPlanRevision>(predicate: #Predicate { $0.id == revisionID })).first else { return nil }
            source = try? JSONDecoder().decode(CoachPlanDocument.self, from: revision.documentData)
        }
        guard var phase = source?.phases.first(where: { $0.id == gate.phaseID }) else { return nil }
        phase.recoveryTargets = phase.recoveryTargets ?? source?.recoveryTargets
        return phase
    }
    private func perform(_ action: (CoachRepository) throws -> Void) { do { try action(CoachRepository(context: context)) } catch { self.error = error.localizedDescription } }
    private func deleteProgram(keepCalendarEvents: Bool) {
        guard !deleting else { return }
        guard !rows.contains(where: { $0.status == "in_progress" }) else { error = "Finish the activity in progress before deleting this program."; return }
        deleting = true
        Task { @MainActor in
            defer { deleting = false }
            do {
                if !keepCalendarEvents { try await CoachCalendarProjection(context: context).removeMappedEvents(rows) }
                try CoachRepository(context: context).deletePlan(id: plan.id, keepingCalendarEvents: keepCalendarEvents)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CoachScheduleEditorView: View {
    let plan: TrainingPlan
    @Environment(\.modelContext) private var context
    @Query private var allSessions: [PlannedSession]
    @State private var selected: Set<UUID> = []
    @State private var offset = 1
    @State private var preview: [CoachScheduleChange] = []
    @State private var expectedUpdatedAt: Date?
    @State private var repeatDate = Date()
    @State private var repeatWeekID = ""
    @State private var confirmingRepeat = false
    @State private var error: String?
    @State private var success: String?
    private var rows: [PlannedSession] { allSessions.filter { $0.plan?.id == plan.id }.sorted { ($0.scheduledDate, $0.intraDayOrder) < ($1.scheduledDate, $1.intraDayOrder) } }
    var body: some View {
        List {
            Section("Choose unstarted sessions") {
                ForEach(rows.filter { $0.status == "pending" && $0.executionID == nil }) { row in
                    Toggle(isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) }; preview = [] })) {
                        Text(row.title + " · " + (row.currentCivilDate ?? ""))
                    }
                }
            }
            Section("Move selected dates") {
                Stepper("\(offset) calendar days", value: $offset, in: -730...730).onChange(of: offset) { _, _ in preview = [] }
                Button("Preview Move") {
                    do { preview = try CoachRepository(context: context).schedulePreview(planID: plan.id, selected: selected, dayOffset: offset); expectedUpdatedAt = plan.updatedAt }
                    catch { self.error = error.localizedDescription }
                }.disabled(selected.isEmpty)
                Button("Preview Swap Two Sessions") {
                    let pair = rows.filter { selected.contains($0.id) }
                    guard pair.count == 2 else { return }
                    preview = [.init(id: pair[0].id, title: pair[0].title, from: pair[0].currentCivilDate ?? "", to: pair[1].currentCivilDate ?? "", order: pair[1].intraDayOrder),
                               .init(id: pair[1].id, title: pair[1].title, from: pair[1].currentCivilDate ?? "", to: pair[0].currentCivilDate ?? "", order: pair[0].intraDayOrder)]
                    expectedUpdatedAt = plan.updatedAt
                }.disabled(selected.count != 2)
            }
            if !preview.isEmpty {
                Section("Review affected dates") {
                    ForEach(preview) { Text($0.title + "\n" + $0.from + " → " + $0.to) }
                    Button("Apply Reviewed Dates") {
                        do { try CoachRepository(context: context).applySchedule(preview, planID: plan.id, expectedUpdatedAt: expectedUpdatedAt ?? plan.updatedAt); preview = []; success = "Schedule updated. Previous reminders for changed sessions were canceled. Review Calendar and reminders to update exported dates and schedule reminders again." }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            Section("Repeat a week") {
                Picker("Source week", selection: $repeatWeekID) {
                    Text("Select a week").tag("")
                    ForEach(Array(Set(rows.compactMap(\.sourceWeekID))).sorted(), id: \.self) { id in
                        Text("Week \((rows.first(where: { $0.sourceWeekID == id })?.weekIndex ?? 0) + 1)").tag(id)
                    }
                }
                DatePicker("New week begins", selection: $repeatDate, displayedComponents: .date)
                    .environment(\.timeZone, CoachRepository.timeZone(plan))
                if !repeatWeekID.isEmpty {
                    ForEach(rows.filter { $0.sourceWeekID == repeatWeekID }) { row in
                        let date = repeatPreviewDate(row)
                        LabeledContent(row.title, value: CoachDate.civil(date, timeZone: CoachRepository.timeZone(plan)))
                    }
                }
                Button("Create Reviewed Repeat") {
                    do { try CoachRepository(context: context).repeatWeek(planID: plan.id, sourceWeekID: repeatWeekID, startDate: repeatDate, expectedUpdatedAt: plan.updatedAt); success = "Week repeated with new session identities." }
                    catch { self.error = error.localizedDescription }
                }.disabled(repeatWeekID.isEmpty)
            }
            if let success { Text(success).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Edit Schedule")
    }
    private func repeatPreviewDate(_ row: PlannedSession) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = CoachRepository.timeZone(plan)
        return calendar.date(byAdding: .day, value: row.dayIndex - 1, to: repeatDate) ?? repeatDate
    }
}

struct CoachRevisionReviewView: View {
    let plan: TrainingPlan
    let incoming: CoachValidatedProgram
    @Environment(\.modelContext) private var context
    @State private var previous: CoachPlanDocument?
    @State private var rows: [PlannedSession] = []
    @State private var selected: Set<UUID> = []
    @State private var expanded: [CoachScheduledOccurrence] = []
    @State private var selectedAdditions: Set<String> = []
    @State private var exerciseMappings: [CoachExerciseMapping] = []
    @State private var exerciseSelections: [String: UUID] = [:]
    @State private var allowCustomExercises = false
    @State private var expectedUpdatedAt: Date?
    @State private var expectedRevision: UUID?
    @State private var error: String?
    @State private var saved = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false
    @State private var applyNutritionTargets = false
    @State private var targetsEffectiveDate = Date()
    var body: some View {
        List {
            Section("Program changes") {
                Text("Revision \(plan.sourceRevision) → \(incoming.document.revision)")
                LabeledContent("Title", value: plan.title + " → " + incoming.document.title)
                Text("Goal: " + plan.goal + " → " + incoming.document.goal)
                Text("Weeks: \(previous?.weeks.count ?? plan.durationWeeks) → \(incoming.document.weeks.count)")
                Text("Started, finished, skipped, moved, and locally edited occurrences are retained. Select only the future prescriptions you want to update.")
            }
            Section("Review the full program") {
                if let previous { DisclosureGroup("Previous program") { CoachProgramPreview(document: previous, startDate: plan.startDate, timeZone: CoachRepository.timeZone(plan)) } }
                DisclosureGroup("Proposed program") { CoachProgramPreview(document: incoming.document, startDate: plan.startDate, timeZone: CoachRepository.timeZone(plan)) }
            }
            Section("Nutrition targets") {
                Text("Saved daily target snapshots stay unchanged. Keep existing target periods, or explicitly apply the proposed weekly targets from a reviewed date.")
                if incoming.document.nutritionTargets != nil || incoming.document.phases.contains(where: { $0.nutritionTargets != nil }) {
                    Toggle("Apply proposed nutrition targets", isOn: $applyNutritionTargets)
                    if applyNutritionTargets {
                        DatePicker("Effective from", selection: $targetsEffectiveDate, in: Date()..., displayedComponents: .date)
                            .environment(\.timeZone, CoachRepository.timeZone(plan))
                        Text("Uses the proposed phase and weekly targets from this date in \(plan.timeZoneIdentifier), through the end of the program. Existing target periods after this date are replaced.").font(.caption)
                    }
                }
            }
            ForEach(incoming.document.sessionTemplates, id: \.id) { template in
                if previous?.sessionTemplates.first(where: { $0.id == template.id }) != template {
                    Section("Changed: \(template.title)") {
                        if let old = previous?.sessionTemplates.first(where: { $0.id == template.id }) { DisclosureGroup("Previous prescription") { CoachPrescriptionPreview(template: old) } }
                        DisclosureGroup("Proposed prescription") { CoachPrescriptionPreview(template: template) }
                    }
                }
            }
            Section("Selected future occurrences") {
                ForEach(rows.filter { $0.status == "pending" && $0.executionID == nil && !$0.localScheduleOverride && ($0.currentCivilDate ?? "") >= CoachDate.civil(Date(), timeZone: CoachRepository.timeZone(plan)) }) { row in
                    Toggle(changeLabel(row), isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } }))
                }
            }
            Section("Added future occurrences") {
                ForEach(expanded.filter { source in
                    source.civilDate >= CoachDate.civil(Date(), timeZone: CoachRepository.timeZone(plan)) && !rows.contains { $0.sourceWeekID == source.weekId && $0.sourceSlotID == source.slotId }
                }, id: \.sourceKey) { source in
                    Toggle(source.template.title + " · " + source.civilDate, isOn: Binding(get: { selectedAdditions.contains(source.sourceKey) }, set: { if $0 { selectedAdditions.insert(source.sourceKey) } else { selectedAdditions.remove(source.sourceKey) } }))
                }
            }
            Section("Review exercise mappings") {
                ForEach(exerciseMappings) { mapping in
                    if mapping.requiresSelection {
                        Picker(mapping.choice.name, selection: Binding(get: { exerciseSelections[mapping.id] }, set: { exerciseSelections[mapping.id] = $0 })) {
                            Text("Choose a match").tag(Optional<UUID>.none)
                            ForEach(mapping.candidates) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } else { Text(mapping.choice.name + (mapping.candidates.isEmpty ? " · New custom exercise" : " · Library match")) }
                }
                if exerciseMappings.contains(where: { $0.candidates.isEmpty }) { Toggle("Create reviewed custom exercises", isOn: $allowCustomExercises) }
            }
            if incoming.document.revision <= plan.sourceRevision { Text("Changed content requires a higher author revision, or a separate copy.").foregroundStyle(.red) }
            Button(saving ? "Saving…" : "Save Reviewed Revision") {
                saving = true
                saveTask = Task { @MainActor in
                    defer { saving = false }
                    do {
                        try await CoachRepository(context: context).applyRevision(incoming, planID: plan.id, selected: selected, addSourceKeys: selectedAdditions, expectedRevisionID: expectedRevision, expectedUpdatedAt: expectedUpdatedAt ?? plan.updatedAt, exerciseSelections: exerciseSelections, allowCustomExercises: allowCustomExercises, applyNutritionTargetsFrom: applyNutritionTargets ? targetsEffectiveDate : nil)
                        saved = true
                    } catch { self.error = error.localizedDescription }
                }
            }.disabled(incoming.document.revision <= plan.sourceRevision || saved || saving || expectedUpdatedAt == nil)
            if saved { Text("Reviewed revision saved. Previous results were preserved.") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Review Revision")
        .onDisappear { saveTask?.cancel() }
        .task {
            do {
                let repository = CoachRepository(context: context)
                previous = try repository.document(for: plan); rows = try repository.occurrences(planID: plan.id)
                expectedUpdatedAt = plan.updatedAt; expectedRevision = plan.currentRevisionID
                exerciseMappings = try repository.exerciseMappings(for: incoming.document)
                let start = plan.startDate, zone = CoachRepository.timeZone(plan)
                expanded = try await Task.detached { try CoachSchedule.expand(incoming, startDate: start, timeZone: zone) }.value
            } catch { self.error = error.localizedDescription }
        }
    }
    private func changeLabel(_ row: PlannedSession) -> String {
        guard let source = expanded.first(where: { $0.weekId == row.sourceWeekID && $0.slotId == row.sourceSlotID }) else {
            return "Remove future prescription: " + row.title + " · " + (row.currentCivilDate ?? "")
        }
        return row.title + " → " + source.template.title + " · " + (row.currentCivilDate ?? "") + " → " + source.civilDate
    }
}
