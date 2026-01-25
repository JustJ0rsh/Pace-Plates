// MARK: - WorkoutLogView

import Charts
import SwiftData
import SwiftUI

// MARK: - View

struct WorkoutLogView: View {
    // MARK: Properties

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @Query(sort: [SortDescriptor<WorkoutSession>(\.date, order: .reverse)]) private var workoutSessions: [WorkoutSession]
    @Query(sort: [SortDescriptor<ExerciseDefinition>(\.name)]) private var exerciseDefinitions: [ExerciseDefinition]
    @State private var newSessionToOpen: WorkoutSession? = nil
    @State private var pastSessionID: UUID? = nil
    @State private var newlyCreatedSessionID: UUID? = nil
    @State private var isEditing: Bool = false
    @State private var showTemplates: Bool = false
    @AppStorage("weightUnit") private var preferredWeightUnit = "lbs"
    
    // Filters
    private enum TimeRange: String, CaseIterable, Identifiable {
        case days7 = "7 Days"
        case month1 = "1 Month"
        case months6 = "6 Months"
        case year1 = "1 Year"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .days7: return 7
            case .month1: return 30
            case .months6: return 180
            case .year1: return 365
            }
        }
    }
    @State private var selectedCategory: String = "All"
    @State private var selectedRange: TimeRange = .days7
    @State private var selectedChartDate: Date? = nil
    @State private var lockedChartDate: Date? = nil // Keeps summary open until X is clicked
    @State private var pendingDeleteSession: WorkoutSession? = nil
    @State private var showDeleteConfirm: Bool = false
    
    // Dynamic chart domain
    private var last7DaysDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let days = max(1, selectedRange.days - 1)
        let start = cal.date(byAdding: .day, value: -days, to: todayStart) ?? todayStart
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return start...end
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                    // Empty-state tile similar to Weight tab
                    if workoutSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ContentUnavailableView(
                                "No workouts yet",
                                systemImage: "dumbbell.fill",
                                description: Text("Tap the + button to add your first workout.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                        }
                        .floatingTile()
                    }
                    // Total Weight Lifted per Day Chart Tile
                    if !workoutSessions.isEmpty {
                        let data = chartData
                        let dailyVolume = data.dailyVolume
                        let groupedVolume = data.groupedVolume

                        VStack(alignment: .leading, spacing: 8) {
                            // Filters above the chart
                            HStack(spacing: 8) {
                                Menu {
                                    Button("All") { selectedCategory = "All" }
                                    ForEach(availableCategories(), id: \.self) { cat in
                                        Button(cat) { selectedCategory = cat }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "line.3.horizontal.decrease.circle")
                                        Text(selectedCategory)
                                    }
                                    .padding(8)
                                    .background(AppTheme.secondaryBackgroundColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }

                                Menu {
                                    ForEach(TimeRange.allCases) { r in
                                        Button(r.rawValue) { selectedRange = r }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                        Text(selectedRange.rawValue)
                                    }
                                    .padding(8)
                                    .background(AppTheme.secondaryBackgroundColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            Text("Total Weight Lifted per Day")
                                .font(.headline)
                                .foregroundStyle(AppTheme.textColor)
                            WorkoutVolumeChartSection(
                                dailyVolume: dailyVolume,
                                groupedVolume: groupedVolume,
                                preferredWeightUnit: preferredWeightUnit,
                                xDomain: last7DaysDomain,
                                selectedChartDate: $selectedChartDate,
                                lockedChartDate: $lockedChartDate,
                                workoutSessions: workoutSessions
                            )
                        }
                        .floatingTile()
                    }

                    if !workoutSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .foregroundStyle(AppTheme.textColor)
                                Text("Workouts")
                                    .font(.headline)
                            }
                            List {
                                ForEach(workoutSessions) { session in
                                    NavigationLink {
                                        WorkoutSessionDetailView(session: session)
                                    } label: {
                                        WorkoutSessionRowContent(
                                            session: session,
                                            isEditing: isEditing,
                                            onDelete: {
                                                pendingDeleteSession = session
                                                showDeleteConfirm = true
                                            }
                                        )
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDeleteSession = session
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollDisabled(true)
                            .frame(height: CGFloat(workoutSessions.count) * 55)
                        }
                        .floatingTile()
                    }
                }
                .padding(.horizontal, AppTheme.padding)
        }
        .appBackground(AppTheme.gradientWorkouts)
            .foregroundColor(AppTheme.textColor)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showTemplates = true }) {
                            Label("Templates", systemImage: "doc.text.fill")
                        }
                        
                        Menu {
                            Button {
                                addWorkoutSession()
                            } label: {
                                Label("New Workout", systemImage: "plus")
                            }
                            Button {
                                addPastWorkoutSession()
                            } label: {
                                Label("Add Past Workout", systemImage: "calendar")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .imageScale(.large)
                                .accessibilityLabel("Add Workout")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                        .font(.headline)
                }
            }
            .sheet(isPresented: $showTemplates) {
                NavigationStack {
                    WorkoutTemplateListView()
                }
            }
            .navigationDestination(item: $newSessionToOpen) { session in
                WorkoutSessionDetailView(
                    session: session,
                    allowDateEdit: session.id == pastSessionID,
                    isNewSession: session.id == newlyCreatedSessionID
                )
            }
            .alert("Delete Workout?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { pendingDeleteSession = nil }
                Button("Delete", role: .destructive) {
                    if let session = pendingDeleteSession {
                        withAnimation {
                            modelContext.delete(session)
                            try? modelContext.save()
                        }
                    }
                    pendingDeleteSession = nil
                }
            } message: {
                if let session = pendingDeleteSession {
                    let title = session.title.isEmpty ? session.date.formatted(date: .abbreviated, time: .shortened) : session.title
                    Text("Delete \"\(title)\" and all its exercise logs?")
                }
            }
    }

    // MARK: Actions

    private func addWorkoutSession() {
        let newSession = WorkoutSession()
        modelContext.insert(newSession)
        try? modelContext.save()
        // Trigger navigation to the new session's detail view
        newlyCreatedSessionID = newSession.id
        pastSessionID = nil
        newSessionToOpen = newSession
    }

    private func addPastWorkoutSession() {
        let newSession = WorkoutSession()
        modelContext.insert(newSession)
        try? modelContext.save()
        newlyCreatedSessionID = newSession.id
        pastSessionID = newSession.id
        newSessionToOpen = newSession
    }

    private func deleteWorkoutSessions(offsets: IndexSet) {
        withAnimation {
            offsets.map { workoutSessions[$0] }.forEach(modelContext.delete)
            try? modelContext.save()
        }
    }

    // MARK: Helpers

    private func convertWeight(_ value: Double, from unit: String, to target: String) -> Double {
        if unit == target { return value }
        if unit == "kg" && target == "lbs" { return value * 2.20462 }
        if unit == "lbs" && target == "kg" { return value / 2.20462 }
        return value
    }

    private var chartData: (dailyVolume: [(date: Date, value: Double)], groupedVolume: [Date: Double]) {
        let calendar = Calendar.current
        let domain = last7DaysDomain
        let startOfWindow = domain.lowerBound
        
        // Optimize: Only process sessions within the window (plus a buffer if needed, but exact is fine for daily sum)
        // workoutSessions is sorted by date descending
        let relevantSessions = workoutSessions.prefix { $0.date >= startOfWindow }
        
        let perSession: [(date: Date, volume: Double)] = relevantSessions.map { session in
            let total = (session.exerciseLogs ?? []).reduce(0.0) { acc, log in
                if selectedCategory != "All" {
                    let group = (log.exerciseDefinition?.muscleGroup ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if group != selectedCategory { return acc }
                }
                let weightInPreferred = convertWeight(log.weight, from: log.weightUnit, to: preferredWeightUnit)
                return acc + (Double(log.effectiveReps) * weightInPreferred)
            }
            return (date: session.date, volume: total)
        }
        
        let groupedVolume: [Date: Double] = Dictionary(grouping: perSession, by: { item in
            calendar.startOfDay(for: item.date)
        }).mapValues { dayItems in
            dayItems.reduce(0.0) { $0 + $1.volume }
        }
        
        let dailyVolume: [(date: Date, value: Double)] = groupedVolume.keys.sorted().map { day in
            (date: day, value: groupedVolume[day] ?? 0)
        }
        
        return (dailyVolume, groupedVolume)
    }

    private func availableCategories() -> [String] {
        let groups = Set(exerciseDefinitions.map { $0.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines) })
        return groups.filter { !$0.isEmpty }.sorted()
    }
}

// MARK: - Optimized Workout Session Row Content
private struct WorkoutSessionRowContent: View {
    let session: WorkoutSession
    let isEditing: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? session.date.formatted(date: .abbreviated, time: .shortened) : session.title)
                    .font(.headline)
                if let notes = session.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .lineLimit(1)
                }
                Text("\(session.exerciseLogs?.count ?? 0) exercises")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .foregroundColor(AppTheme.textColor)
            Spacer(minLength: 8)
            if isEditing {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Extracted subview to lower type-checking complexity
private struct WorkoutVolumeChartSection: View {
    let dailyVolume: [(date: Date, value: Double)]
    let groupedVolume: [Date: Double]
    let preferredWeightUnit: String
    let xDomain: ClosedRange<Date>
    @Binding var selectedChartDate: Date?
    @Binding var lockedChartDate: Date?
    let workoutSessions: [WorkoutSession]

    var body: some View {
        let minV = dailyVolume.map { $0.value }.min() ?? 0
        let maxV = dailyVolume.map { $0.value }.max() ?? 0
        let spanV = max(1.0, maxV - minV)
        let padV = max(0.1, spanV * 0.15)
        let yLowerV = max(0, minV - padV)
        let yUpperV = maxV + padV
        let yDomain: ClosedRange<Double> = (yLowerV <= yUpperV) ? (yLowerV...yUpperV) : (0...1)
        let calendar = Calendar.current
        let labelUnit = "Total (\(preferredWeightUnit))"
        let points: [VolumePoint] = dailyVolume.map { .init(date: $0.date, value: $0.value) }

        VStack(alignment: .leading, spacing: 8) {
            VolumeChart(points: points, labelUnit: labelUnit, xDomain: xDomain, yDomain: yDomain, selectedChartDate: $selectedChartDate, lockedChartDate: $lockedChartDate)

            // Use locked date to keep summary open until X is clicked
            if let lockedDate = lockedChartDate,
               let selectedPoint = points.first(where: { calendar.isDate($0.date, inSameDayAs: lockedDate) }) {
                let sessionsOnDay = workoutSessions.filter { calendar.isDate($0.date, inSameDayAs: lockedDate) }
                let counts = countsForSessions(sessionsOnDay)

                SelectionSummary(
                    date: lockedDate,
                    valueText: String(format: "%.0f %@", selectedPoint.value, preferredWeightUnit),
                    sessionsOnDay: sessionsOnDay,
                    exerciseCount: counts.exercises,
                    setCount: counts.sets,
                    onClose: { withAnimation(.easeOut(duration: 0.2)) { lockedChartDate = nil; selectedChartDate = nil } }
                )
            }

            let today = calendar.startOfDay(for: Date())
            if let todayVolume = groupedVolume[today] {
                HStack(spacing: 8) {
                    Text(String(format: "%.0f", todayVolume))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(preferredWeightUnit)
                        .font(.headline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }

    // Precompute simple counts without nested reduces for better type-checking
    private func countsForSessions(_ sessions: [WorkoutSession]) -> (exercises: Int, sets: Int) {
        var exerciseCount = 0
        var setCount = 0
        for s in sessions {
            let logs = s.exerciseLogs ?? []
            exerciseCount += logs.count
            // Each ExerciseLog represents a single set
            setCount += logs.count
        }
        return (exerciseCount, setCount)
    }
}

// Lightweight model to reduce generic tuple complexity in Chart
private struct VolumePoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

// Minimal chart-only view to isolate Chart DSL generics
private struct VolumeChart: View {
    let points: [VolumePoint]
    let labelUnit: String
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    @Binding var selectedChartDate: Date?
    @Binding var lockedChartDate: Date?

    var body: some View {
        Chart(points) { item in
            LineMark(
                x: .value("Date", item.date),
                y: .value(labelUnit, item.value)
            )
            .interpolationMethod(.linear)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .foregroundStyle(AppTheme.accentColor)

            PointMark(
                x: .value("Date", item.date),
                y: .value(labelUnit, item.value)
            )
            .symbol(Circle())
            .symbolSize(40)
            .foregroundStyle(AppTheme.accentColor)

            // Use locked date for persistent highlight
            if let displayDate = lockedChartDate ?? selectedChartDate,
               Calendar.current.isDate(item.date, inSameDayAs: displayDate) {
                RuleMark(x: .value("Selected", item.date))
                    .foregroundStyle(AppTheme.accentColor.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                PointMark(
                    x: .value("Date", item.date),
                    y: .value(labelUnit, item.value)
                )
                .symbol(Circle())
                .symbolSize(100)
                .foregroundStyle(AppTheme.accentColor)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartXScale(domain: xDomain)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartPlotStyle { plot in plot.background(.clear) }
        .chartXSelection(value: $selectedChartDate)
        .onChange(of: selectedChartDate) { _, newDate in
            // When user taps a new point, lock it
            if let newDate = newDate {
                withAnimation(.easeOut(duration: 0.2)) {
                    lockedChartDate = newDate
                }
            }
        }
        .frame(height: 180)
        .foregroundColor(AppTheme.textColor)
    }
}

// Selection summary view to avoid large inline ViewBuilder
private struct SelectionSummary: View {
    let date: Date
    let valueText: String
    let sessionsOnDay: [WorkoutSession]
    let exerciseCount: Int
    let setCount: Int
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }

            Divider().opacity(0.3)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Volume")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    Text(valueText)
                        .font(.title3.bold())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Workouts")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    Text("\(sessionsOnDay.count)")
                        .font(.title3.bold())
                }
            }

            if !sessionsOnDay.isEmpty {
                Divider().opacity(0.3)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exercises")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text("\(exerciseCount)")
                            .font(.subheadline.bold())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Sets")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text("\(setCount)")
                            .font(.subheadline.bold())
                    }
                }

                ForEach(sessionsOnDay.prefix(2)) { session in
                    HStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentColor)
                        Text(session.title.isEmpty ? session.date.formatted(date: .omitted, time: .shortened) : session.title)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }

                if sessionsOnDay.count > 2 {
                    Text("+ \(sessionsOnDay.count - 2) more")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
        }
        .padding(12)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}
