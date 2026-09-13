import SwiftUI
import SwiftData
import Charts

enum CoachProgressRange: String, CaseIterable {
    case week = "7 days", month = "30 days", quarter = "90 days", year = "1 year", all = "All"
    func start(relativeTo date: Date = Date(), timeZone: TimeZone = .current) -> Date? {
        let days: Int
        switch self { case .week: days = 6; case .month: days = 29; case .quarter: days = 89; case .year: days = 364; case .all: return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: date))
    }
}

struct CoachProgressRangePicker: View {
    @Binding var selection: String
    var body: some View {
        Picker("Date range", selection: $selection) {
            ForEach(CoachProgressRange.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
        }.accessibilityIdentifier("coach.progress.range")
    }
}

struct CoachChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    var detail: String = ""
}

struct CoachValueChart: View {
    let title: String
    let unit: String
    let points: [CoachChartPoint]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if points.isEmpty {
                Text("No recorded \(title.lowercased()) in this range.").foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    PointMark(x: .value("Date", point.date), y: .value(title, point.value))
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue("\(CoachEntryNumber.text(point.value)) \(unit). \(point.detail)")
                }
                .chartYAxisLabel(unit).frame(height: 180)
                Text("\(points.count) recorded values. Gaps are not filled with zero or connected as measurements.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Values · \(title)") {
                    ForEach(points.sorted { $0.date > $1.date }) { point in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(point.date, format: .dateTime.month().day().year())
                                Spacer()
                                Text("\(CoachEntryNumber.text(point.value)) \(unit)")
                            }
                            if !point.detail.isEmpty { Text(point.detail).font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

struct CoachProgressView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("coach.progress.range") private var rangeRaw = CoachProgressRange.month.rawValue
    @State private var plans: [TrainingPlan] = []
    @State private var sessions: [PlannedSession] = []
    @State private var executions: [CoachSessionExecution] = []
    @State private var runs: [RunningSession] = []
    @State private var nutrition: [CoachNutritionLog] = []
    @State private var recovery: [CoachRecoveryCheckIn] = []
    @State private var suggestions: [CoachProgressionSuggestion] = []
    @State private var selectedPlanID: UUID?
    @State private var liftFilter = ""
    @State private var liftPoints: [String: [CoachChartPoint]] = [:]
    @State private var liftLabels: [String: String] = [:]
    @State private var liftMetric = "Load"
    @State private var checkIn: CoachCheckInDestination?
    @State private var loading = true
    @State private var error: String?
    private var range: CoachProgressRange { CoachProgressRange(rawValue: rangeRaw) ?? .month }
    private var start: Date? { range.start() }
    private func includes(_ date: Date) -> Bool { (start == nil || date >= start!) && CoachDate.civil(date) <= CoachDate.civil(Date()) }
    private var selectedPlan: TrainingPlan? { plans.first { $0.id == selectedPlanID } }
    private var programSessions: [PlannedSession] { sessions.filter { $0.plan?.id == selectedPlanID && $0.activityType != "rest" && $0.completionProvenance != "removed_by_reviewed_revision" } }
    private var filteredSessions: [PlannedSession] {
        let zone = selectedPlan.map(CoachRepository.timeZone) ?? .current
        let today = CoachDate.civil(Date(), timeZone: zone)
        let lower = range.start(timeZone: zone).map { CoachDate.civil($0, timeZone: zone) }
        return programSessions.filter {
            let day = $0.currentCivilDate ?? CoachDate.civil($0.scheduledDate, timeZone: zone)
            return day <= today && (lower == nil || day >= lower!)
        }
    }
    private var filteredNutrition: [CoachNutritionLog] { nutrition.filter { includes(CoachDate.date($0.civilDate)) } }
    private var filteredRecovery: [CoachRecoveryCheckIn] { recovery.filter { includes(CoachDate.date($0.civilDate)) } }
    private var filteredRuns: [RunningSession] { runs.filter { includes($0.date) && ["completed", "partial", "legacy_recorded"].contains($0.executionStatusRaw) } }

    var body: some View {
        List {
            Section { CoachProgressRangePicker(selection: $rangeRaw) }
            if loading { ProgressView("Loading progress…") }
            if let error { Section { Text(error).foregroundStyle(.red); Button("Retry", action: load) } }
            if !loading {
                programSection
                liftingSection
                runningSection
                progressionSection
                Section("Body") {
                    NavigationLink { CoachBodyProgressView() } label: { Label("Weight, waist and photo comparisons", systemImage: "figure.stand") }
                    Text("Uses the same weight records as the Weight tab and the same selected date range.").font(.caption).foregroundStyle(.secondary)
                }
                nutritionSection
                recoverySection
            }
        }
        .listStyle(.insetGrouped)
        .task { load() }
        .onChange(of: rangeRaw) { _, _ in load() }
        .onChange(of: selectedPlanID) { _, _ in loadProgramSessions() }
        .onChange(of: liftMetric) { _, _ in rebuildLifting() }
        .sheet(item: $checkIn, onDismiss: load) { CoachCheckInView(destination: $0) }
        .refreshable { load() }
    }

    private var programSection: some View {
        Section("Program adherence") {
            if plans.isEmpty { Text("Add a program to see prescribed sessions and adherence.").foregroundStyle(.secondary) }
            else {
                Picker("Program", selection: $selectedPlanID) {
                    ForEach(plans) { Text($0.title).tag(Optional($0.id)) }
                }
                let required = filteredSessions.filter { !$0.isOptional }
                let completed = required.filter { $0.status == "completed" }.count
                LabeledContent("Adherence through today · Selected range", value: "\(completed) / \(required.count)")
                if !required.isEmpty {
                    ProgressView(value: Double(completed), total: Double(required.count))
                        .accessibilityLabel("Required sessions completed through today in selected range")
                        .accessibilityValue("\(completed) of \(required.count)")
                } else { Text("No required sessions due in this range.").foregroundStyle(.secondary) }
                ForEach(["partial", "skipped", "pending", "in_progress"], id: \.self) { status in
                    LabeledContent(status.replacingOccurrences(of: "_", with: " ").capitalized, value: "\(required.filter { $0.status == status }.count)")
                }
                LabeledContent("Optional sessions completed", value: "\(filteredSessions.filter { $0.isOptional && $0.status == "completed" }.count)")
                Text("Rest, optional sessions, and occurrences removed by a reviewed revision are excluded from the required-session denominator. Future days are excluded until due.").font(.caption).foregroundStyle(.secondary)
                let wholeRequired = programSessions.filter { !$0.isOptional }
                let wholeCompleted = wholeRequired.filter { $0.status == "completed" }.count
                if wholeRequired.isEmpty { Text("Whole program: No required sessions.").foregroundStyle(.secondary) }
                else {
                    LabeledContent("Whole-program completion", value: "\(wholeCompleted) / \(wholeRequired.count)")
                    Text("All scheduled required sessions, including future dates. Independent of the selected history range.").font(.caption).foregroundStyle(.secondary)
                }
                if let selectedPlan { NavigationLink("Open Program") { CoachProgramDetailView(plan: selectedPlan) } }
            }
        }
    }
    private var liftingSection: some View {
        Section("Lifting") {
            Picker("Recorded measurement", selection: $liftMetric) {
                ForEach(["Load", "Reps", "Time"], id: \.self) { Text($0).tag($0) }
            }
            if liftPoints.isEmpty { Text("No completed sets with recorded \(liftMetric.lowercased()) in this range.").foregroundStyle(.secondary) }
            else {
                Picker("Movement and setup", selection: $liftFilter) {
                    ForEach(liftPoints.keys.sorted(), id: \.self) { Text(liftLabels[$0] ?? "Movement").tag($0) }
                }
                CoachValueChart(title: "Actual \(liftMetric.lowercased())", unit: liftMetric == "Load" ? "kg" : liftMetric == "Time" ? "seconds" : "reps", points: liftPoints[liftFilter] ?? [])
                Text("Only recorded completed sets are shown. Exercise, equipment, load basis, and per-side interpretation stay separate; lb loads convert for display.").font(.caption).foregroundStyle(.secondary)
            }
            NavigationLink("Open Workout History") { WorkoutLogView() }
        }
    }
    private var runningSection: some View {
        Section("Running") {
            CoachValueChart(title: "Run distance", unit: "km", points: filteredRuns.compactMap { run in
                guard run.activityType == "running", run.hasMeasuredDistance,
                      let km = CoachMeasurementUnits.kilometers(run.distance, unit: run.distanceUnit), km > 0 else { return nil }
                return CoachChartPoint(id: run.id.uuidString, date: run.date, value: km, detail: "\(CoachEntryNumber.text(run.duration / 60)) minutes · \(run.duration > 0 ? CoachEntryNumber.text(run.duration / 60 / km) + " min/km" : "Pace unavailable")")
            })
            Text("Pace and distance are shown only when measured distance has a supported unit; missing distance is never filled in.").font(.caption).foregroundStyle(.secondary)
            LabeledContent("Recorded run time", value: "\(CoachEntryNumber.text(filteredRuns.filter { $0.activityType == "running" }.reduce(0) { $0 + $1.duration } / 60)) min")
            DisclosureGroup("Interval outcomes and original targets") {
                ForEach(executions.filter { includes($0.startedAt) && $0.snapshotData != nil }) { execution in
                    if let snapshot = decodeSnapshot(execution), let intervals = snapshot.intervalState {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(execution.startedAt, format: .dateTime.month().day()).font(.headline)
                            ForEach(intervals.results) { result in
                                let step = intervals.steps.first { $0.id == result.stepID }
                                Text("\(step?.label ?? result.stepID): \(CoachEntryNumber.text(result.activeDuration)) s\(result.distanceMeters.map { ", " + CoachEntryNumber.text($0) + " m" } ?? "") · \(result.state.rawValue)")
                                if let step { Text("Target: \(step.targetSeconds.map { CoachEntryNumber.text($0) + " s" } ?? step.targetMeters.map { CoachEntryNumber.text($0) + " m" } ?? "Unspecified") · \(result.completionMethod.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
    }
    private var progressionSection: some View {
        Section("Progression") {
            let rows = suggestions.filter { $0.planID == selectedPlanID && includes($0.createdAt) }
            ForEach(["pending", "accepted", "edited", "dismissed", "stale"], id: \.self) { status in
                LabeledContent(status.capitalized, value: "\(rows.filter { $0.statusRaw == status }.count)")
            }
            if let selectedPlan { NavigationLink("Review Progression and Evidence") { CoachProgressionReviewView(plan: selectedPlan) } }
            Text("Suggestions require a deliberate review. A calendar date or missing pain entry cannot clear readiness.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var nutritionSection: some View {
        Section("Nutrition") {
            CoachValueChart(title: "Calories", unit: "kcal", points: filteredNutrition.compactMap { row in
                row.calories.map { .init(id: row.id.uuidString, date: CoachDate.date(row.civilDate), value: $0, detail: row.statusRaw.capitalized) }
            })
            let lastWeek = nutrition.filter { CoachDate.date($0.civilDate) >= CoachProgressRange.week.start()! && $0.civilDate <= CoachDate.civil(Date()) }
            ForEach(["Calories", "Protein", "Carbohydrate", "Fat"], id: \.self) { field in
                let values = lastWeek.compactMap { row -> Double? in
                    switch field { case "Calories": row.calories; case "Protein": row.protein; case "Carbohydrate": row.carbs; default: row.fat }
                }
                LabeledContent("7-day average \(field.lowercased())", value: values.isEmpty ? "Not available" : "\(CoachEntryNumber.text(values.reduce(0, +) / Double(values.count))) · \(values.count) logged days")
            }
            Text("Averages include only known values; \(lastWeek.filter { $0.statusRaw == "draft" }.count) days remain drafts. Missing days do not count as zero.").font(.caption).foregroundStyle(.secondary)
            Button("Log Today's Nutrition") { checkIn = .nutrition(Date()) }
            DisclosureGroup("Nutrition history") {
                ForEach(filteredNutrition) { row in
                    Button { checkIn = .nutrition(CoachDate.date(row.civilDate)) } label: {
                        VStack(alignment: .leading) {
                            Text("\(row.civilDate) · \(row.statusRaw.capitalized)")
                            Text("\(row.calories.map { CoachEntryNumber.text($0) + " kcal" } ?? "Calories unknown") · P \(row.protein.map { CoachEntryNumber.text($0) } ?? "unknown") / C \(row.carbs.map { CoachEntryNumber.text($0) } ?? "unknown") / F \(row.fat.map { CoachEntryNumber.text($0) } ?? "unknown") g").font(.caption)
                        }
                    }
                }
            }
        }
    }
    private var recoverySection: some View {
        Section("Recovery") {
            CoachValueChart(title: "Sleep", unit: "hours", points: filteredRecovery.compactMap { row in
                row.displayedSleepHours.map { .init(id: row.id.uuidString, date: CoachDate.date(row.civilDate), value: $0, detail: row.displayedSleepSource) }
            })
            CoachValueChart(title: "Soreness", unit: "0–10", points: filteredRecovery.compactMap { row in
                row.soreness.map { .init(id: row.id.uuidString, date: CoachDate.date(row.civilDate), value: Double($0)) }
            })
            LabeledContent("Check-in days", value: "\(filteredRecovery.count)")
            Button("Log Today's Recovery") { checkIn = .recovery(Date()) }
            DisclosureGroup("Recovery history") {
                ForEach(filteredRecovery) { row in
                    Button { checkIn = .recovery(CoachDate.date(row.civilDate)) } label: {
                        VStack(alignment: .leading) {
                            Text(row.civilDate)
                            Text("Energy \(row.energy.map(String.init) ?? "unreported") · Pain \(row.painScore.map(String.init) ?? "unreported")").font(.caption)
                        }
                    }
                }
            }
        }
    }
    private func decodeSnapshot(_ execution: CoachSessionExecution) -> CoachExecutionSnapshot? {
        execution.snapshotData.flatMap { try? JSONDecoder().decode(CoachExecutionSnapshot.self, from: $0) }
    }
    private func rebuildLifting() {
        var series: [String: [CoachChartPoint]] = [:]
        var labels: [String: String] = [:]
        for execution in executions where includes(execution.startedAt) && ["completed", "partial"].contains(execution.statusRaw) {
            guard let snapshot = decodeSnapshot(execution) else { continue }
            for result in snapshot.setResults where result.state == .completed {
                let measured: Double?
                switch liftMetric {
                case "Reps": measured = result.reps.map(Double.init)
                case "Time": measured = result.durationSeconds
                default:
                    if let load = result.load, let unit = CoachMeasurementUnits.canonicalWeight(result.loadUnit ?? "") { measured = unit == "kg" ? load : load * 0.45359237 }
                    else { measured = nil }
                }
                guard let measured, measured.isFinite, measured >= 0 else { continue }
                let setup = "\(result.equipment ?? "Equipment unspecified") · \(result.loadBasis ?? "Basis unspecified") · \(result.repCounting ?? "Count unspecified")"
                let key = result.performedExerciseID + ":" + setup
                labels[key] = result.performedExerciseName + " · " + setup
                series[key, default: []].append(.init(id: execution.id.uuidString + ":" + result.id, date: execution.startedAt, value: measured,
                                                     detail: "\(result.reps.map { "\($0) reps" } ?? result.durationSeconds.map { CoachEntryNumber.text($0) + " s" } ?? "Result unreported")\(result.effort.map { " · " + (result.effortScale ?? "Effort") + " " + CoachEntryNumber.text($0) } ?? "")"))
            }
        }
        liftPoints = series
        liftLabels = labels
        if series[liftFilter] == nil { liftFilter = series.keys.sorted().first ?? "" }
    }
    private func load() {
        loading = true
        do {
            let fresh = ModelContext(context.container)
            let lower = start ?? Date.distantPast
            let upper = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            let lowerDay = CoachDate.civil(lower), upperDay = CoachDate.civil(upper)
            let nutritionLower = CoachDate.civil(min(lower, CoachProgressRange.week.start()!))
            plans = try fresh.fetch(FetchDescriptor<TrainingPlan>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            executions = try fresh.fetch(FetchDescriptor<CoachSessionExecution>(predicate: #Predicate { $0.startedAt >= lower && $0.startedAt < upper }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
            runs = try fresh.fetch(FetchDescriptor<RunningSession>(predicate: #Predicate { $0.date >= lower && $0.date < upper }, sortBy: [SortDescriptor(\.date, order: .reverse)]))
            nutrition = try fresh.fetch(FetchDescriptor<CoachNutritionLog>(predicate: #Predicate { $0.civilDate >= nutritionLower && $0.civilDate < upperDay }, sortBy: [SortDescriptor(\.civilDate, order: .reverse)]))
            recovery = try fresh.fetch(FetchDescriptor<CoachRecoveryCheckIn>(predicate: #Predicate { $0.civilDate >= lowerDay && $0.civilDate < upperDay }, sortBy: [SortDescriptor(\.civilDate, order: .reverse)]))
            suggestions = try fresh.fetch(FetchDescriptor<CoachProgressionSuggestion>(predicate: #Predicate { $0.createdAt >= lower && $0.createdAt < upper }))
            if !plans.contains(where: { $0.id == selectedPlanID }) { selectedPlanID = plans.first(where: { $0.status == "active" })?.id ?? plans.first?.id }
            try fetchProgramSessions()
            let unreadable = executions.filter { $0.snapshotData != nil && decodeSnapshot($0) == nil }.count
            error = unreadable > 0 ? "\(unreadable) saved execution snapshots could not be read and are excluded from charts. Other history remains available." : nil
            rebuildLifting()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
    private func fetchProgramSessions() throws {
        guard let selectedPlanID else { sessions = []; return }
        sessions = try ModelContext(context.container).fetch(FetchDescriptor<PlannedSession>(predicate: #Predicate { $0.plan?.id == selectedPlanID }))
    }
    private func loadProgramSessions() {
        do { try fetchProgramSessions() }
        catch { self.error = error.localizedDescription }
    }
}
