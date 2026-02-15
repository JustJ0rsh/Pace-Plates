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
    @State private var showQuickRunTracking: Bool = false
    @State private var showQuickWeightLog: Bool = false
    @State private var saveErrorMessage: String? = nil

    private enum ChartTab: Hashable { case volume, runs, weight }
    
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
        // Start from today if active today, otherwise from the most recent activity day
        let startAnchor: Date = {
            let today = calendar.startOfDay(for: Date())
            if activityDays.contains(today) { return today }
            return activityDays.max() ?? today
        }()
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
        // Start from this week if active, else from most recent week with activity
        let thisWeek = calendar.startOfWeek(for: Date())
        let startAnchor: Date = weeksWithActivity.contains(thisWeek) ? thisWeek : (weeksWithActivity.max() ?? thisWeek)
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
                HStack(spacing: 10) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(AppTheme.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Workout")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text(lastWorkout.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                }
            } else {
                Text("No workouts logged yet")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }

            if let lastRun = runningSessions.first {
                Divider().opacity(0.2)
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .foregroundColor(AppTheme.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Run")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text(lastRun.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                    }
                }
            } else {
                // Placeholder to maintain consistent height
                Divider().hidden()
                HStack(spacing: 10) {
                    Image(systemName: "figure.run")
                        .hidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last Run")
                            .font(.caption)
                            .hidden()
                        Text("Placeholder")
                            .font(.subheadline)
                            .hidden()
                    }
                }
            }
        }
        .floatingTile()
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

            Button {
                Haptics.playImpact(.light)
                showQuickRunTracking = true
            } label: {
                Label("Start Run", systemImage: "figure.run")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)

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
    
    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                
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
                }
                .accessibilityLabel("Community")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gear")
                }
                .accessibilityLabel("Settings")
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
                RunTrackingProView(activityType: "running")
                    .navigationTitle("Tracking Run")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            }
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .tint(AppTheme.accentColor)
        }
        .sheet(isPresented: $showQuickWeightLog) {
            LogWeightView()
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
