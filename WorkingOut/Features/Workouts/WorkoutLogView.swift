// MARK: - WorkoutLogView

import Charts
import SwiftData
import SwiftUI

// MARK: - View

struct WorkoutLogView: View {
    // MARK: Properties

    @Environment(\.modelContext) private var modelContext
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
        NavigationStack {
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
                        let calendar = Calendar.current
                        
                        let minV = dailyVolume.map { $0.value }.min() ?? 0
                        let maxV = dailyVolume.map { $0.value }.max() ?? 0
                        let spanV = max(1.0, maxV - minV)
                        let padV = max(0.1, spanV * 0.15)
                        let yLowerV = max(0, minV - padV)
                        let yUpperV = maxV + padV

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

                            Chart(dailyVolume, id: \.date) { item in
                                LineMark(
                                    x: .value("Date", item.date),
                                    y: .value("Total (\(preferredWeightUnit))", item.value)
                                )
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(AppTheme.accentColor)

                                PointMark(
                                    x: .value("Date", item.date),
                                    y: .value("Total (\(preferredWeightUnit))", item.value)
                                )
                                .symbol(Circle())
                                .symbolSize(40)
                                .foregroundStyle(AppTheme.accentColor)
                            }
                            .chartYScale(domain: (yLowerV <= yUpperV ? yLowerV...yUpperV : 0...1))
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month().day())
                                }
                            }
                            .chartXScale(domain: last7DaysDomain)
                            .chartYAxis { AxisMarks(position: .leading) }
                            .chartPlotStyle { plot in plot.background(.clear) }
                            .frame(height: 180)
                            .foregroundColor(AppTheme.textColor)

                            let today = calendar.startOfDay(for: Date())
                            if let todayVolume = groupedVolume[today] {
                                HStack(spacing: 8) {
                                    Text(String(format: "%.0f", todayVolume))
                                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Text(preferredWeightUnit)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 4)
                            }
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
                            LazyVStack(spacing: 12) {
                                ForEach(workoutSessions) { session in
                                    NavigationLink {
                                        WorkoutSessionDetailView(session: session)
                                    } label: {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(session.title.isEmpty ? session.date.formatted(date: .abbreviated, time: .shortened) : session.title)
                                                    .font(.headline)
                                                if let notes = session.notes, !notes.isEmpty {
                                                    Text(notes)
                                                        .font(.subheadline)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
                                                Text("\(session.exerciseLogs?.count ?? 0) exercises")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .foregroundColor(AppTheme.textColor)
                                            Spacer(minLength: 8)
                                            if isEditing {
                                                Button(role: .destructive) {
                                                    if let idx = workoutSessions.firstIndex(where: { $0.id == session.id }) {
                                                        deleteWorkoutSessions(offsets: IndexSet(integer: idx))
                                                    }
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            modelContext.delete(session)
                                            try? modelContext.save()
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    Divider().opacity(0.2)
                                }
                                .onDelete(perform: deleteWorkoutSessions)
                            }
                        }
                        .floatingTile()
                    }
                }
                .padding(.horizontal, AppTheme.padding)
            }
            .appBackground(AppTheme.gradientWorkouts)
            .foregroundColor(AppTheme.textColor)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(
                LinearGradient(
                    gradient: Gradient(colors: [AppTheme.backgroundColor.opacity(0.98), AppTheme.backgroundColor.opacity(0.9)]),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
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

    private static func backgroundGradient() -> some View {
        let base = AppTheme.backgroundColor
        let ui = UIColor(base)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let factor: CGFloat = 0.85 // lower = darker; tweak to taste
        let darker = Color(red: Double(r * factor), green: Double(g * factor), blue: Double(b * factor), opacity: 1.0)

        let gradient = LinearGradient(
            colors: [
                Color(red: Double(r), green: Double(g), blue: Double(b), opacity: 1.0),
                darker
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return gradient.ignoresSafeArea(.container, edges: .all)
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
                return acc + (Double(log.reps) * weightInPreferred)
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
