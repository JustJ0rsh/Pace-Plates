// MARK: - HomeView

import Charts
import SwiftData
import SwiftUI

// MARK: - View

struct HomeView: View {
    // MARK: Properties

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @Query(sort: [SortDescriptor<WeightEntry>(\.date, order: .reverse)]) private var weightEntries: [WeightEntry]
    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)]) private var runningSessions: [RunningSession]
    @Query(sort: [SortDescriptor<WorkoutSession>(\.date, order: .reverse)]) private var workoutSessions: [WorkoutSession]
    @AppStorage("weightUnit") private var preferredWeightUnit = "lbs"
    @AppStorage("streakMode") private var streakMode: String = "daily"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("showVitalsOnHome") private var showVitalsOnHome: Bool = true
    
    @State private var selectedChartTab: ChartTab = .volume
    @State private var quickWorkoutSession: WorkoutSession? = nil
    @State private var showWorkoutTemplates: Bool = false
    @State private var showQuickRunTracking: Bool = false
    @State private var quickCardioActivityType: String = "running"
    @State private var quickPlannedRunTarget: ScheduledRunTarget? = nil
    @State private var showQuickWeightLog: Bool = false
    @State private var saveErrorMessage: String? = nil
    @State private var runTracker = RunTracker.shared

    private enum ChartTab: Hashable { case volume, runs, weight }
    
    private let quickCardioOptions: [(title: String, activityType: String, icon: String)] = [
        ("Run", "running", "figure.run"),
        ("Walk", "walking", "figure.walk"),
        ("Hike", "hiking", "figure.hiking"),
        ("Cycle", "cycling", "bicycle"),
        ("Row", "rowing", "figure.rower")
    ]
    
    // Last 7 days window (inclusive of today). X domain ends at start of tomorrow.
    private var last7DaysDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return start...end
    }
    
    // MARK: Derived Data

    // Sample computed properties for chart data (replace with actual logic)
    // Optimized: Only process runs from the last 7 days
    private var dailyRunTotalsLast7: [(date: Date, distance: Double)] {
        let calendar = Calendar.current
        let startOfWindow = last7DaysDomain.lowerBound
        
        // Since runningSessions is sorted by date descending, we can stop once we go past the window
        let relevantSessions = runningSessions.prefix { $0.date >= startOfWindow }
        
        let grouped = Dictionary(grouping: relevantSessions) { session in
            calendar.startOfDay(for: session.date)
        }
        
        let summed: [(date: Date, distance: Double)] = grouped.map { (key: Date, value: [RunningSession]) in
            let totalDistance = value.reduce(0.0) { partial, session in
                partial + UnitConverter.distance(session.distance, from: session.distanceUnit, to: distanceUnit)
            }
            return (date: key, distance: totalDistance)
        }
        
        return summed.sorted { $0.date < $1.date }
    }

    // Build a sorted series for the chart in the preferred unit
    // Optimized: Only process weights from the last 7 days
    private var weightDailySeriesLast7: [(date: Date, weight: Double)] {
        let calendar = Calendar.current
        let startOfWindow = last7DaysDomain.lowerBound
        
        // weightEntries is sorted by date descending
        let relevantEntries = weightEntries.prefix { $0.date >= startOfWindow }
        
        let grouped = Dictionary(grouping: relevantEntries) { item in
            calendar.startOfDay(for: item.date)
        }
        
        let perDayLatest: [(date: Date, weight: Double)] = grouped.compactMap { day, items in
            // Items are already sorted descending, so the first one is the latest for that day
            guard let latest = items.first else { return nil }
            let converted = UnitConverter.weight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)
            return (date: day, weight: converted)
        }.sorted { $0.date < $1.date }
        
        return perDayLatest
    }
    
    // Auto-centered Y range for body weight chart with padding
    private var weightYDomain: ClosedRange<Double>? {
        guard let minVal = weightDailySeriesLast7.map(\.weight).min(),
              let maxVal = weightDailySeriesLast7.map(\.weight).max(),
              minVal.isFinite, maxVal.isFinite, minVal != maxVal else {
            // Fallback to nil so Charts chooses automatically
            return nil
        }
        let span = max(5.0, (maxVal - minVal))
        let padding = max(2.0, span * 0.15)
        return (minVal - padding)...(maxVal + padding)
    }
    
    // Total lifted volume per day (sum of reps * weight per set), grouped by day
    // Optimized: Only process workouts from the last 7 days
    private var workoutVolumePerDayLast7: [(date: Date, volume: Double)] {
        let calendar = Calendar.current
        let startOfWindow = last7DaysDomain.lowerBound
        
        // workoutSessions is sorted by date descending
        let relevantSessions = workoutSessions.prefix { $0.date >= startOfWindow }
        
        let perSession: [(date: Date, volume: Double)] = relevantSessions.map { session in
            let total = (session.exerciseLogs ?? []).reduce(0.0) { acc, log in
                let weightInPreferred = UnitConverter.weight(log.weight, from: log.weightUnit, to: preferredWeightUnit)
                return acc + (Double(log.effectiveReps) * weightInPreferred)
            }
            return (date: session.date, volume: total)
        }
        
        let grouped = Dictionary(grouping: perSession) { item in
            calendar.startOfDay(for: item.date)
        }
        
        let summed: [(date: Date, volume: Double)] = grouped.map { (day, items) in
            (date: day, volume: items.reduce(0) { $0 + $1.volume })
        }
        
        return summed.sorted { $0.date < $1.date }
    }

    // MARK: Formatting & Utilities

    // Formatter for week
    private func formatWeek(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formattedWholeNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }

    private func formattedOneDecimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private var selectedChartSummary: String {
        switch selectedChartTab {
        case .volume:
            let total = workoutVolumePerDayLast7.reduce(0) { $0 + $1.volume }
            guard total > 0 else { return "Log a workout to see your volume trend." }
            return "You lifted \(formattedWholeNumber(total)) \(preferredWeightUnit) this week."
        case .runs:
            let startOfWindow = last7DaysDomain.lowerBound
            let recentActivities = runningSessions.prefix { $0.date >= startOfWindow }
            let longest = recentActivities
                .map { UnitConverter.distance($0.distance, from: $0.distanceUnit, to: distanceUnit) }
                .max() ?? 0
            guard longest > 0 else { return "Start a run to see your distance trend." }
            return "Longest activity: \(formattedOneDecimal(longest)) \(distanceUnit)."
        case .weight:
            let data = weightDailySeriesLast7
            guard let latest = data.last else { return "Log a weight to see your trend." }
            guard let oldest = data.first, data.count >= 2 else {
                return "Latest: \(formattedOneDecimal(latest.weight)) \(preferredWeightUnit)."
            }
            let delta = latest.weight - oldest.weight
            guard abs(delta) >= 0.05 else { return "No change over 7 days." }
            let direction = delta < 0 ? "Down" : "Up"
            return "\(direction) \(formattedOneDecimal(abs(delta))) \(preferredWeightUnit) over 7 days."
        }
    }
    
    // MARK: Chart Builders

    @ViewBuilder
    private func placeholderChart(text: String) -> some View {
        ZStack {
            Color.clear
            Text(text)
                .foregroundColor(AppTheme.textColor.opacity(0.6))
                .font(.subheadline)
        }
        .frame(height: 200)
    }
    
    @ViewBuilder
    private func volumeChartView(data: [(date: Date, volume: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Weight Lifted per Day")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textColor)
                Chart(data, id: \.date) { dataPoint in
                    BarMark(
                        x: .value("Date", dataPoint.date, unit: .day),
                        y: .value("Total (\(preferredWeightUnit))", dataPoint.volume)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accentColor.opacity(0.9), AppTheme.accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartPlotStyle { plot in plot.background(.clear) }
                .chartXScale(domain: last7DaysDomain)
                .frame(height: 200)
            }
        } else {
            placeholderChart(text: "No workout data yet")
        }
    }
    
    @ViewBuilder
    private func runsChartView(data: [(date: Date, distance: Double)]) -> some View {
        if !data.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Distance per Day")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textColor)
                Chart(data, id: \.date) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Total (\(distanceUnit))", point.distance)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(LinearGradient(colors: [AppTheme.accentColor.opacity(0.9), AppTheme.accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartPlotStyle { plot in plot.background(.clear) }
                .chartXScale(domain: last7DaysDomain)
                .frame(height: 200)
            }
        } else {
            placeholderChart(text: "No running data yet")
        }
    }
    
    @ViewBuilder
    private func weightChartView(data: [(date: Date, weight: Double)]) -> some View {
        if !data.isEmpty {
            HStack {
                Text("Body Weight")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textColor)
                Spacer()
            }

            Group {
                Chart(data, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight (\(preferredWeightUnit))", point.weight)
                    )
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(AppTheme.accentColor.opacity(0.9))

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Weight (\(preferredWeightUnit))", point.weight)
                    )
                    .symbol(Circle())
                    .symbolSize(70)
                    .foregroundStyle(AppTheme.accentColor)
                }
                .modifier(ChartYScaleWrapper(domain: weightYDomain))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartPlotStyle { plot in plot.background(.clear) }
                .chartXScale(domain: last7DaysDomain)
                .frame(height: 200)
            }
            .id(data.map(\.date))
        } else {
            placeholderChart(text: "No weight data yet")
        }
    }
    
    private struct ChartYScaleWrapper: ViewModifier {
        let domain: ClosedRange<Double>?
        func body(content: Content) -> some View {
            if let domain {
                content.chartYScale(domain: domain)
            } else {
                content.chartYScale(domain: .automatic(includesZero: false))
            }
        }
    }
    
    // MARK: Streak Logic

    // Activity streaks
    private var activityDailyStreakDays: Int {
        let calendar = Calendar.current
        let runDays = runningSessions.map { calendar.startOfDay(for: $0.date) }
        let workoutDays = workoutSessions.map { calendar.startOfDay(for: $0.date) }
        let activityDays = Set(runDays + workoutDays)
        guard !activityDays.isEmpty else { return 0 }
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        // A daily streak remains current through the day after the last
        // activity, but older streaks have expired.
        let startAnchor: Date
        if activityDays.contains(today) {
            startAnchor = today
        } else if activityDays.contains(yesterday) {
            startAnchor = yesterday
        } else {
            return 0
        }
        var streak = 0
        var day = startAnchor
        while activityDays.contains(day) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private var activityWeeklyStreakWeeks: Int {
        let calendar = Calendar.current
        let allDates = runningSessions.map { $0.date } + workoutSessions.map { $0.date }
        guard !allDates.isEmpty else { return 0 }
        let weeksWithActivity: Set<Date> = Set(allDates.map { calendar.startOfWeek(for: $0) })
        let thisWeek = calendar.startOfWeek(for: Date())
        let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek) ?? thisWeek
        // As with daily streaks, the immediately previous period can still be
        // extended; a gap longer than that expires the current streak.
        let startAnchor: Date
        if weeksWithActivity.contains(thisWeek) {
            startAnchor = thisWeek
        } else if weeksWithActivity.contains(previousWeek) {
            startAnchor = previousWeek
        } else {
            return 0
        }
        var streak = 0
        var week = startAnchor
        while weeksWithActivity.contains(week) {
            streak += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = prev
        }
        return streak
    }

    private var streakDisplayText: String {
        let isWeekly: Bool = (streakMode == "weekly")
        let count: Int = isWeekly ? activityWeeklyStreakWeeks : activityDailyStreakDays
        // Always use singular word per requirement
        if isWeekly { return "\(count) Week Streak" }
        return "\(count) Day Streak"
    }
    
    // MARK: Helpers to reduce type-check complexity in body

    @State private var showStreakCalendar: Bool = false
    
    @ViewBuilder
    private var streakCard: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Current Streak")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
                Text(streakDisplayText)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: { showStreakCalendar = true }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentColor.opacity(0.2))
                        .foregroundColor(AppTheme.accentColor)
                        .clipShape(Capsule())
                        .accessibilityLabel("Calendar")
                }
                .buttonStyle(.plain)

                Button(action: { streakMode = (streakMode == "weekly") ? "daily" : "weekly" }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentColor.opacity(0.2))
                        .foregroundColor(AppTheme.accentColor)
                        .clipShape(Capsule())
                        .accessibilityLabel(streakMode == "weekly" ? "Switch to day streak" : "Switch to week streak")
                }
                .buttonStyle(.plain)
            }
        }
        .floatingTile()
        .sheet(isPresented: $showStreakCalendar) {
            NavigationStack { StreakCalendarView() }
        }
    }
    
    @ViewBuilder
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(AppTheme.textColor)

            if let lastWorkout = workoutSessions.first {
                NavigationLink {
                    WorkoutSessionDetailView(session: lastWorkout)
                } label: {
                    HomeRecentActivityRow(
                        icon: "figure.strengthtraining.traditional",
                        title: lastWorkout.title.isEmpty ? "Workout" : lastWorkout.title,
                        subtitle: recentWorkoutSubtitle(lastWorkout)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens workout details.")
                .accessibilityIdentifier("home.recentActivity.workout")
            }

            if let lastRun = runningSessions.first {
                if workoutSessions.first != nil {
                    Divider().opacity(0.2)
                }

                NavigationLink {
                    RunSessionDetailView(session: lastRun)
                } label: {
                    HomeRecentActivityRow(
                        icon: activityIcon(for: lastRun.activityType),
                        title: activityDisplayName(for: lastRun.activityType),
                        subtitle: recentRunSubtitle(lastRun)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens activity details.")
                .accessibilityIdentifier("home.recentActivity.run")
            }

            if let lastWeight = weightEntries.first {
                if workoutSessions.first != nil || runningSessions.first != nil {
                    Divider().opacity(0.2)
                }

                NavigationLink {
                    HomeWeightEntryDetailView(
                        entry: lastWeight,
                        comparisonEntry: weightEntries.dropFirst().first,
                        preferredWeightUnit: preferredWeightUnit
                    )
                } label: {
                    HomeRecentActivityRow(
                        icon: "scalemass",
                        title: "Weight",
                        subtitle: recentWeightSubtitle(lastWeight)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens weight entry details.")
                .accessibilityIdentifier("home.recentActivity.weight")
            }

            if workoutSessions.isEmpty && runningSessions.isEmpty && weightEntries.isEmpty {
                Text("Your latest workout, cardio, and weight entries will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
        .floatingTile()
    }

    private func recentWorkoutSubtitle(_ session: WorkoutSession) -> String {
        let exerciseCount = Set((session.exerciseLogs ?? []).compactMap(\.exerciseName)).count
        let exerciseText = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        return "\(exerciseText) • \(session.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func recentRunSubtitle(_ session: RunningSession) -> String {
        let convertedDistance = UnitConverter.distance(
            session.distance,
            from: session.distanceUnit,
            to: distanceUnit
        )
        let distance = convertedDistance.formatted(.number.precision(.fractionLength(2)))
        return "\(distance) \(distanceUnit) • \(formatActivityDuration(session.duration)) • \(session.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func recentWeightSubtitle(_ entry: WeightEntry) -> String {
        let convertedWeight = UnitConverter.weight(
            entry.weight,
            from: entry.weightUnit,
            to: preferredWeightUnit
        )
        let weight = convertedWeight.formatted(.number.precision(.fractionLength(1)))
        return "\(weight) \(preferredWeightUnit) • \(entry.date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func activityDisplayName(for activityType: String) -> String {
        switch activityType {
        case "walking":
            return "Walk"
        case "hiking":
            return "Hike"
        case "cycling":
            return "Ride"
        case "rowing":
            return "Row"
        case "elliptical":
            return "Elliptical"
        case "stairStepper", "stairClimbing":
            return "Stair Climb"
        default:
            return "Run"
        }
    }

    private func activityIcon(for activityType: String) -> String {
        switch activityType {
        case "walking":
            return "figure.walk"
        case "hiking":
            return "figure.hiking"
        case "cycling":
            return "bicycle"
        case "rowing":
            return "figure.rower"
        case "elliptical":
            return "figure.core.training"
        case "stairStepper", "stairClimbing":
            return "figure.stairs"
        default:
            return "figure.run"
        }
    }

    private func formatActivityDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Log")
                .font(.headline)
                .foregroundStyle(AppTheme.textColor)

            Button {
                Haptics.playImpact(.light)
                startQuickWorkout()
            } label: {
                Label("Start Workout", systemImage: "figure.strengthtraining.traditional")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.quickActions.startWorkout")
            .id("home.quickActions.startWorkout")
            .contextMenu {
                Button {
                    Haptics.playImpact(.light)
                    startQuickWorkout()
                } label: {
                    Label("Start Workout", systemImage: "play.fill")
                }

                Button {
                    Haptics.playImpact(.light)
                    showWorkoutTemplates = true
                } label: {
                    Label("Choose Template", systemImage: "doc.text")
                }
            }

            if !runTracker.hasRecoverableActivity {
                Button {
                    startQuickCardio(activityType: "running")
                } label: {
                    Label("Start Run", systemImage: "figure.run")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("home.quickActions.startRun")
                .id("home.quickActions.startRun")
                .contextMenu {
                    ForEach(quickCardioOptions, id: \.activityType) { option in
                        Button {
                            startQuickCardio(activityType: option.activityType)
                        } label: {
                            Label(option.title, systemImage: option.icon)
                        }
                    }
                }
            }

            Button {
                Haptics.playImpact(.light)
                showQuickWeightLog = true
            } label: {
                Label("Log Weight", systemImage: "scalemass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
        }
        .floatingTile()
    }

    private func startQuickWorkout() {
        let session = WorkoutSession()
        modelContext.insert(session)
        guard PersistenceSave.commit(
            modelContext,
            action: "quick log workout",
            onFailure: { message in saveErrorMessage = message }
        ) else {
            modelContext.delete(session)
            return
        }
        quickWorkoutSession = session
    }
    
    private func startQuickCardio(
        activityType: String,
        plannedTarget: ScheduledRunTarget? = nil
    ) {
        Haptics.playImpact(.light)
        let tracker = RunTracker.shared
        // Re-enter an existing active/paused activity instead of presenting it
        // under the type of the newly tapped shortcut.
        quickCardioActivityType = tracker.hasRecoverableActivity
            ? tracker.activityType
            : activityType
        quickPlannedRunTarget = tracker.hasRecoverableActivity
            ? tracker.plannedTarget
            : plannedTarget
        showQuickRunTracking = true
    }
    
    private func quickCardioTrackingTitle(for activityType: String) -> String {
        switch activityType {
        case "walking":
            return "Tracking Walk"
        case "hiking":
            return "Tracking Hike"
        case "cycling":
            return "Tracking Ride"
        case "rowing":
            return "Tracking Row"
        case "elliptical":
            return "Tracking Elliptical"
        case "stairClimbing":
            return "Tracking Stair Climbing"
        default:
            return "Tracking Run"
        }
    }
    
    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomeTodayCard(
                    workoutSessions: workoutSessions,
                    weightEntries: weightEntries,
                    preferredWeightUnit: preferredWeightUnit,
                    distanceUnit: distanceUnit,
                    runTracker: runTracker,
                    onStartCardio: { activityType, plannedTarget in
                        startQuickCardio(
                            activityType: activityType,
                            plannedTarget: plannedTarget
                        )
                    },
                    onOpenWorkout: { session in
                        quickWorkoutSession = session
                    },
                    onLogWeight: {
                        showQuickWeightLog = true
                    },
                    onSaveError: { message in
                        saveErrorMessage = message
                    }
                )

                // Weather summary tile
                WeatherSummaryView()

                streakCard

                quickActionsCard

                recentActivityCard

                if showVitalsOnHome {
                    VitalsSnapshotView()
                }

                // Floating Charts Card with Tabs
                VStack(spacing: 12) {
                    // Segmented control to switch charts
                    Picker("Chart", selection: $selectedChartTab) {
                        Text("Volume").tag(ChartTab.volume)
                        Text("Runs").tag(ChartTab.runs)
                        Text("Weight").tag(ChartTab.weight)
                    }
                    .pickerStyle(.segmented)

                    Text(selectedChartSummary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Chart content swaps based on selected tab
                    Group {
                        switch selectedChartTab {
                        case .volume:
                            let data = workoutVolumePerDayLast7
                            volumeChartView(data: data)
                        case .runs:
                            let data = dailyRunTotalsLast7
                            runsChartView(data: data)
                        case .weight:
                            let data = weightDailySeriesLast7
                            weightChartView(data: data)
                        }
                    }
                }
                .floatingTile()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.padding)
            .padding(.top)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(destination: CommunityView()) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(AppTheme.toolbarButtonColor)
                }
                .accessibilityLabel("Community")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                        .foregroundStyle(AppTheme.toolbarButtonColor)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("home.settings.button")
            }
        }
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
        .tint(AppTheme.accentColor)
        .navigationDestination(item: $quickWorkoutSession) { session in
            WorkoutSessionDetailView(session: session, isNewSession: true)
        }
        .sheet(isPresented: $showQuickRunTracking) {
            NavigationStack {
                RunTrackingProView(
                    activityType: quickCardioActivityType,
                    plannedTarget: quickPlannedRunTarget
                )
                    .navigationTitle(quickCardioTrackingTitle(for: quickCardioActivityType))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            }
            .id(quickCardioActivityType)
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .tint(AppTheme.accentColor)
        }
        .onChange(of: showQuickRunTracking) { _, isPresented in
            if !isPresented {
                quickPlannedRunTarget = nil
            }
        }
        .sheet(isPresented: $showQuickWeightLog) {
            LogWeightView()
        }
        .sheet(isPresented: $showWorkoutTemplates) {
            NavigationStack {
                WorkoutTemplateListView { session in
                    quickWorkoutSession = session
                }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Couldn’t save your changes. Please try again.")
        }
        .id(appTheme) // Force rebuild when theme changes
    }
}

private struct HomeRecentActivityRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 36, height: 36)
                .background(AppTheme.accentColor.opacity(0.14))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryTextColor)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct HomeWeightEntryDetailView: View {
    let entry: WeightEntry
    let comparisonEntry: WeightEntry?
    let preferredWeightUnit: String

    @AppStorage("weightGoal") private var weightGoal: String = "lose"

    private var convertedWeight: Double {
        UnitConverter.weight(
            entry.weight,
            from: entry.weightUnit,
            to: preferredWeightUnit
        )
    }

    private var weightChange: Double? {
        guard let comparisonEntry else { return nil }
        let previousWeight = UnitConverter.weight(
            comparisonEntry.weight,
            from: comparisonEntry.weightUnit,
            to: preferredWeightUnit
        )
        return convertedWeight - previousWeight
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date.formatted(date: .long, time: .shortened))
                        .font(.headline)
                    Text("Recorded measurement")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .floatingTile()

                detailMetric(
                    title: "Weight",
                    value: "\(convertedWeight.formatted(.number.precision(.fractionLength(1)))) \(preferredWeightUnit)"
                )

                if let weightChange {
                    let isUp = weightChange >= 0
                    let isTowardGoal = weightGoal == "gain" ? isUp : !isUp

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Change From Previous Entry")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)

                        Label {
                            Text("\(abs(weightChange).formatted(.number.precision(.fractionLength(1)))) \(preferredWeightUnit)")
                                .font(.headline)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        }
                        .foregroundStyle(isTowardGoal ? .green : .orange)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingTile()
                }

                NavigationLink {
                    WeightLogView()
                } label: {
                    Label("View Weight History", systemImage: "chart.line.uptrend.xyaxis")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, AppTheme.padding)
            .padding(.top)
        }
        .navigationTitle("Weight Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .appBackground(AppTheme.gradientWeight)
        .foregroundStyle(AppTheme.textColor)
        .tint(AppTheme.accentColor)
    }

    private func detailMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingTile()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Extensions

// Helper extension for Calendar start of week
extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = self.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Preview

#Preview {
    NavigationStack { HomeView() }
        .modelContainer(PersistenceController.preview.container)
}
