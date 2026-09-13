import SwiftUI
import HealthKit
import SwiftData
import MapKit
import CoreLocation
import Charts
import Combine
import CoreData

struct RunLogView: View {
    private static let pendingForcedEnrichmentDefaultsKey =
        "healthKit.pendingForcedRunEnrichmentUUIDs"

    private struct RunTrackingRequest: Identifiable {
        let id = UUID()
        let activityType: String
        let plannedTarget: ScheduledRunTarget?
    }

    private enum EnrichmentOutcome {
        case completed
        case noLongerNeeded
        case retryLater
    }

    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("distanceUnit") private var preferredDistanceUnit: String = "mi"
    @AppStorage("runsLastHealthImportAt") private var runsLastHealthImportAt: Double = 0
    private let launchConfiguration = AppLaunchConfiguration.current
    // Helper type for chart points
    private struct DailyPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var chartSessions: [RunningSession]
    @State private var historyPage: [RunningSession] = []
    @State private var historyResultCount = 0
    @State private var totalRunCount = 0

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? .distantPast
        _chartSessions = Query(filter: #Predicate<RunningSession> { $0.date >= cutoff },
                               sort: [SortDescriptor(\.date, order: .reverse)])
    }

    // Full history is fetched only by reconciliation/import operations, never
    // by the view's render path. Visible rows use RunHistoryStore's fetch limit.
    private var runningSessions: [RunningSession] {
        (try? modelContext.fetch(FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }
    @Query(filter: #Predicate<CardioWorkoutInboxItem> {
        $0.statusRaw == "pending" && $0.healthDeletionObservedAt == nil
    })
    private var pendingCardioInboxItems: [CardioWorkoutInboxItem]
    
    @State private var isEditing: Bool = false
    @State private var locationCache: [UUID: String] = [:]
    @State private var pendingLocationTasks: Set<UUID> = [] // Track active location fetch tasks
    @State private var hasPrefetchedLocations = false // Prevent duplicate prefetching
    @State private var runTrackingRequest: RunTrackingRequest? = nil
    @State private var stepsToday: Int? = nil
    @State private var hasScheduledInitialImport = false
    @State private var pendingEnrichmentUUIDs: Set<String> = []
    @State private var pendingForcedEnrichmentUUIDs: Set<String> = []
    @State private var activeForcedEnrichmentUUIDs: Set<String> = []
    @State private var enrichmentTask: Task<Void, Never>? = nil
    private let healthStore = HKHealthStore()
    @State private var pendingDeleteSession: RunningSession? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var loadingSessionId: UUID? = nil
    @State private var navigationSessionId: UUID? = nil
    @State private var selectedChartDate: Date? = nil
    @State private var pendingSwipeDeleteSession: RunningSession? = nil
    @State private var showSwipeDeleteConfirm: Bool = false
    @State private var lockedChartDate: Date? = nil // Keeps summary open until X is clicked
    @State private var showRunActions: Bool = false
    @State private var showPastRunLog: Bool = false
    @State private var saveErrorMessage: String? = nil
    @State private var visibleRunCount: Int = 30
    @State private var hasInitializedRunPagination: Bool = false
    @State private var healthChangeDebounceTask: Task<Void, Never>? = nil
    @State private var quickViewSession: RunningSession? = nil
    @State private var historySearchText: String = ""
    @State private var historyRange: HistoryRange = .all
    @State private var historyActivityType: String? = nil
    private let runPageSize: Int = 30
    private let defaultHealthImportLimit: Int = 10
    private let forcedHealthImportLimit: Int = 8
    private let autoEnrichmentLimit: Int = 3
    
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
    @State private var runSelectedRange: TimeRange = .days7
    @State private var runActivityFilter: String = "All"
    
    
    
    // Dynamic domain based on selected range
    private var last7DaysDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let days = max(1, runSelectedRange.days - 1)
        let start = calendar.date(byAdding: .day, value: -days, to: todayStart) ?? todayStart
        // Upper bound is start of tomorrow to make the X-axis inclusive of today
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return start...endExclusive
    }

    private var historyActivityOptions: [HistoryFilterOption] {
        activityFilterOptions().map { label in
            HistoryFilterOption(id: keyForActivity(label), title: label)
        }
    }

    var body: some View {
        let visibleHistoryRuns = historyPage
        let canLoadMoreHistoryRuns = historyResultCount > visibleHistoryRuns.count

        ScrollView {
            VStack(spacing: 16) {
                
                ActiveRunBanner(activityName: activityName, activityIcon: activityIcon) { type in
                    presentRunTracking(for: type)
                }

                // Unified Runs tile (header + chart or placeholder)
                let calendar = Calendar.current
                let domain = last7DaysDomain
                // Apply activity and date range filters before grouping
                let filteredSessions: [RunningSession] = chartSessions.filter { s in
                    if runActivityFilter != "All", s.activityType != keyForActivity(runActivityFilter) {
                        return false
                    }
                    return s.date >= domain.lowerBound && s.date < domain.upperBound
                }
                let grouped: [Date: Double] = Dictionary(grouping: filteredSessions, by: { session in
                    calendar.startOfDay(for: session.date)
                }).mapValues { sessions in
                    sessions.reduce(0) {
                        $0 + UnitConverter.distance($1.distance, from: $1.distanceUnit, to: preferredDistanceUnit)
                    }
                }
                let daily: [DailyPoint] = grouped.keys.sorted().map { day in
                    DailyPoint(date: day, value: grouped[day] ?? 0)
                }
                let minV: Double = daily.map { $0.value }.min() ?? 0
                let maxV: Double = daily.map { $0.value }.max() ?? 0
                let span: Double = max(1.0, maxV - minV)
                let pad: Double = max(0.1, span * 0.15)
                let yLower: Double = max(0, minV - pad)
                let yUpper: Double = maxV + pad
                let unitLabel = UnitConverter.canonicalDistanceUnit(preferredDistanceUnit)

                // Always show the Runs tile header; render chart or placeholder
                VStack(alignment: .leading, spacing: 8) {
                        // Filters
                        HStack(spacing: 8) {
                            Menu {
                                Button("All") { runActivityFilter = "All" }
                                ForEach(activityFilterOptions(), id: \.self) { label in
                                    Button(label) { runActivityFilter = label }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "line.3.horizontal.decrease.circle")
                                    Text(runActivityFilter)
                                }
                                .padding(8)
                                .background(AppTheme.secondaryBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Menu {
                                ForEach(TimeRange.allCases) { r in
                                    Button(r.rawValue) { runSelectedRange = r }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "calendar")
                                    Text(runSelectedRange.rawValue)
                                }
                                .padding(8)
                                .background(AppTheme.secondaryBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        // Header row with steps count on the right
                        HStack(spacing: 8) {
                            Text("Total Distance Per Day")
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 6) {
                                Image(systemName: "figure.walk")
                                Text("Steps Today \(stepsToday.map { String($0) } ?? "—")")
                                    .monospacedDigit()
                            }
                            .foregroundStyle(AppTheme.textColor)
                        }

                        Text(runDistanceSummary(filteredSessions: filteredSessions, unitLabel: unitLabel))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryTextColor)

                        if daily.isEmpty {
                            VStack(spacing: 10) {
                                ContentUnavailableView(
                                    "No Runs Logged",
                                    systemImage: "figure.run",
                                    description: Text("Start tracking now, log a past activity, or import from Apple Health.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 150)

                                Button {
                                    presentRunTracking(for: "running")
                                } label: {
                                    Label("Start First Run", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    showPastRunLog = true
                                } label: {
                                    Label("Log Past Run", systemImage: "calendar")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    importHealthRuns(limit: forcedHealthImportLimit, force: true)
                                } label: {
                                    Label("Check Health Inbox", systemImage: "tray.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else {
                            Chart(daily, id: \.id) { item in
                                LineMark(
                                    x: .value("Date", item.date),
                                    y: .value("Distance (\(unitLabel))", item.value)
                                )
                                .interpolationMethod(.linear)
                                .lineStyle(.init(lineWidth: 2))
                                .foregroundStyle(AppTheme.accentColor)

                                PointMark(
                                    x: .value("Date", item.date),
                                    y: .value("Distance (\(unitLabel))", item.value)
                                )
                                .symbol(Circle())
                                .symbolSize(40)
                                .foregroundStyle(AppTheme.accentColor)
                                
                                // Selection indicator (use locked date for persistent highlight)
                                if let displayDate = lockedChartDate ?? selectedChartDate,
                                   Calendar.current.isDate(item.date, inSameDayAs: displayDate) {
                                    RuleMark(x: .value("Selected", item.date))
                                        .foregroundStyle(AppTheme.accentColor.opacity(0.3))
                                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                                    
                                    PointMark(
                                        x: .value("Date", item.date),
                                        y: .value("Distance (\(unitLabel))", item.value)
                                    )
                                    .symbol(Circle())
                                    .symbolSize(100)
                                    .foregroundStyle(AppTheme.accentColor)
                                }
                            }
                            .chartYScale(domain: (yLower <= yUpper ? yLower...yUpper : 0...1))
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                                    AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month().day())
                                }
                            }
                            .chartXScale(domain: last7DaysDomain)
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
                            .frame(height: 200)
                            .foregroundColor(AppTheme.textColor)
                            
                            // Data summary popup when a point is locked (stays until X is clicked)
                            if let lockedDate = lockedChartDate,
                               let selectedPoint = daily.first(where: { Calendar.current.isDate($0.date, inSameDayAs: lockedDate) }) {
                                let selectedDate = lockedDate
                                let sessionsOnDay = filteredSessions.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                            .font(.headline)
                                        Spacer()
                                        Button {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                lockedChartDate = nil
                                                selectedChartDate = nil
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(AppTheme.secondaryTextColor)
                                        }
                                    }
                                    
                                    Divider().opacity(0.3)
                                    
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Total Distance")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryTextColor)
                                            Text(String(format: "%.2f %@", selectedPoint.value, unitLabel))
                                                .font(.title3.bold())
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Activities")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryTextColor)
                                            Text("\(sessionsOnDay.count)")
                                                .font(.title3.bold())
                                        }
                                    }
                                    
                                    if !sessionsOnDay.isEmpty {
                                        Divider().opacity(0.3)
                                        
                                        ForEach(sessionsOnDay.prefix(3)) { session in
                                            let convertedDistance = UnitConverter.distance(session.distance, from: session.distanceUnit, to: unitLabel)
                                            HStack(spacing: 8) {
                                                Image(systemName: activityIcon(for: session.activityType))
                                                    .font(.caption)
                                                    .foregroundStyle(AppTheme.accentColor)
                                                Text(session.hasMeasuredDistance ? "\(String(format: "%.2f", convertedDistance)) \(unitLabel)" : "Distance unavailable")
                                                    .font(.subheadline)
                                                Text("•")
                                                    .foregroundStyle(AppTheme.secondaryTextColor)
                                                Text(formatDuration(session.duration))
                                                    .font(.subheadline)
                                                    .foregroundStyle(AppTheme.secondaryTextColor)
                                            }
                                        }
                                        
                                        if sessionsOnDay.count > 3 {
                                            Text("+ \(sessionsOnDay.count - 3) more")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.secondaryTextColor)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(AppTheme.secondaryBackgroundColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .motionAwareTransition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                    }
                    .floatingTile()

                    if totalRunCount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.run")
                                    .foregroundStyle(AppTheme.textColor)
                                Text("Activity History")
                                    .font(.headline)
                            }

                            HistoryFilterBar(
                                searchText: $historySearchText,
                                selectedRange: $historyRange,
                                selectedCategory: $historyActivityType,
                                resultCount: historyResultCount,
                                searchPrompt: "Search activities or notes",
                                accessibilityIdentifier: "runs.history.filters",
                                categories: historyActivityOptions
                            )

                            if historyPage.isEmpty {
                                HistoryNoResultsView(
                                    title: "No Matching Activities",
                                    message: "Try another activity, note, or date range.",
                                    accessibilityIdentifier: "runs.history.no_results",
                                    clearFilters: clearRunHistoryFilters
                                )
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(visibleHistoryRuns) { session in
                                        Group {
                                            if isEditing {
                                                RunSessionRowContent(
                                                    session: session,
                                                    preferredDistanceUnit: preferredDistanceUnit,
                                                    locationName: locationCache[session.id],
                                                    isEditing: true,
                                                    onDelete: {
                                                        pendingDeleteSession = session
                                                        showDeleteConfirm = true
                                                    }
                                                )
                                            } else {
                                                Button {
                                                    loadingSessionId = session.id
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                        navigationSessionId = session.id
                                                    }
                                                } label: {
                                                    RunSessionRowContent(
                                                        session: session,
                                                        preferredDistanceUnit: preferredDistanceUnit,
                                                        locationName: locationCache[session.id],
                                                        isEditing: false,
                                                        onDelete: {
                                                            pendingDeleteSession = session
                                                            showDeleteConfirm = true
                                                        }
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityHint("Opens activity details")
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onLongPressGesture {
                                            guard !isEditing else { return }
                                            Haptics.playImpact(.light)
                                            quickViewSession = session
                                        }
                                        .padding(.vertical, 8)
                                        .contextMenu {
                                            Button {
                                                quickViewSession = session
                                            } label: {
                                                Label("Quick View", systemImage: "eye")
                                            }

                                            Button(role: .destructive) {
                                                pendingDeleteSession = session
                                                showDeleteConfirm = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                pendingSwipeDeleteSession = session
                                                showSwipeDeleteConfirm = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                    }
                                }

                                if canLoadMoreHistoryRuns {
                                    Divider().padding(.top, 6).opacity(0.25)

                                    HStack(spacing: 10) {
                                        Text("Showing \(visibleHistoryRuns.count) of \(historyResultCount) activities")
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.secondaryTextColor)

                                        Spacer()

                                        Button("Load 30 More") {
                                            visibleRunCount = min(
                                                visibleRunCount + runPageSize,
                                                historyResultCount
                                            )
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .frame(minHeight: 44)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        }
                        .floatingTile()
                        .onAppear {
                            prefetchLocationNames()
                        }
                        .onChange(of: totalRunCount) {
                            hasPrefetchedLocations = false
                            prefetchLocationNames()
                        }
                    }

                    
                }
                .padding(.horizontal, AppTheme.padding)
                .padding(.top)
            }
            .alert("Delete Run?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { pendingDeleteSession = nil }
                Button("Delete on Device", role: .destructive) {
                    if let session = pendingDeleteSession {
                        deleteRunningSession(session, action: "delete run session")
                    }
                    pendingDeleteSession = nil
                }
                Button("Delete on Device + Health", role: .destructive) {
                    Task { @MainActor in
                        if let session = pendingDeleteSession {
                            do {
                                try await HealthKitManager.shared.deleteRun(uuidString: session.healthWorkoutUUID)
                                deleteRunningSession(session, action: "delete run + health")
                            } catch {
                                saveErrorMessage = "Nothing was deleted. \(error.localizedDescription)"
                            }
                        }
                        pendingDeleteSession = nil
                    }
                }
            } message: {
                Text("Also remove this workout from the Health app?")
            }
            .alert("Delete Run?", isPresented: $showSwipeDeleteConfirm) {
                Button("Cancel", role: .cancel) { pendingSwipeDeleteSession = nil }
                Button("Delete on Device", role: .destructive) {
                    if let session = pendingSwipeDeleteSession {
                        deleteRunningSession(session, action: "delete run (swipe)")
                    }
                    pendingSwipeDeleteSession = nil
                }
                Button("Delete on Device + Health", role: .destructive) {
                    Task { @MainActor in
                        if let session = pendingSwipeDeleteSession {
                            do {
                                try await HealthKitManager.shared.deleteRun(uuidString: session.healthWorkoutUUID)
                                deleteRunningSession(session, action: "delete run + health (swipe)")
                            } catch {
                                saveErrorMessage = "Nothing was deleted. \(error.localizedDescription)"
                            }
                        }
                        pendingSwipeDeleteSession = nil
                    }
                }
            } message: {
                Text("Also remove this workout from the Health app?")
            }
            .overlay {
                if loadingSessionId != nil {
                    ZStack {
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.8)
                                .tint(.white)
                            Text("Loading Run...")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                    }
                    .motionAwareTransition(.opacity.combined(with: .scale(scale: 0.9)))
                    .animation(.easeInOut(duration: 0.2), value: loadingSessionId)
                }
            }
            .accessibilityIdentifier("runs.ready")
            .navigationDestination(item: $navigationSessionId) { sessionId in
                if let session = sessionForNavigation(id: sessionId) {
                    RunSessionDetailView(session: session)
                        .onAppear {
                            loadingSessionId = nil
                        }
                        .onDisappear {
                            navigationSessionId = nil
                        }
                }
            }
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .navigationTitle("Runs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
            .tint(AppTheme.accentColor)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.headline)
                            .foregroundStyle(AppTheme.toolbarButtonColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink {
                            CardioInboxView()
                        } label: {
                            Image(systemName: "tray.fill")
                                .foregroundStyle(AppTheme.toolbarButtonColor)
                                .overlay(alignment: .topTrailing) {
                                    if !pendingCardioInboxItems.isEmpty {
                                        Text("\(min(pendingCardioInboxItems.count, 99))")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(3)
                                            .frame(minWidth: 15)
                                            .background(Color.red)
                                            .clipShape(Capsule())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                                .accessibilityLabel(
                                    pendingCardioInboxItems.isEmpty
                                        ? "Cardio Inbox"
                                        : "Cardio Inbox, \(pendingCardioInboxItems.count) pending"
                                )
                        }
                        .accessibilityIdentifier("runs.cardioInbox")

                        Button {
                            showRunActions = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.toolbarButtonColor)
                                .accessibilityLabel("Track Activity")
                        }
                    }
                }

                
            }
            .onAppear {
                reloadHistory()
                if !hasInitializedRunPagination {
                    hasInitializedRunPagination = true
                    visibleRunCount = min(runPageSize, totalRunCount)
                }
                if !launchConfiguration.shouldSkipAutomationSideEffects {
                    HealthKitManager.shared.startWorkoutChangeObservationIfNeeded()
                    restorePersistedForcedEnrichment()
                    if UserDefaults.standard.bool(forKey: "runsPendingHealthImport") {
                        UserDefaults.standard.set(false, forKey: "runsPendingHealthImport")
                        importHealthRuns(limit: forcedHealthImportLimit, force: true)
                    }
                    // Permissions are requested in the tracking/import flows
                    // that need them, rather than when browsing run history.
                    fetchTodaySteps()
                    scheduleInitialHealthImportIfNeeded()
                    reconcileAssistantPlanCompletions()
                }
            }
            .onChange(of: totalRunCount) { oldCount, newCount in
                if oldCount == 0 && visibleRunCount == 0 && newCount > 0 {
                    visibleRunCount = min(runPageSize, newCount)
                } else {
                    visibleRunCount = min(visibleRunCount, newCount)
                }
                reconcileAssistantPlanCompletions()
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in reloadHistory() }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in reloadHistory() }
            .onChange(of: visibleRunCount) { reloadHistory() }
            .onChange(of: historySearchText) {
                resetRunHistoryPagination()
            }
            .onChange(of: historyRange) {
                resetRunHistoryPagination()
            }
            .onChange(of: historyActivityType) {
                resetRunHistoryPagination()
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitWorkoutsDidChange)) { _ in
                scheduleImportForHealthWorkoutUpdate()
            }
            .onDisappear {
                healthChangeDebounceTask?.cancel()
                healthChangeDebounceTask = nil
            }
            .sheet(item: $runTrackingRequest) { request in
                NavigationStack {
                    RunTrackingProView(
                        activityType: request.activityType,
                        plannedTarget: request.plannedTarget
                    )
                        .navigationTitle(activityTitle(for: request.activityType))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
                }
                .id(request.id)
                .appBackground(AppTheme.gradientRuns)
                .foregroundColor(AppTheme.textColor)
                .tint(AppTheme.accentColor)
            }
            .sheet(isPresented: $showPastRunLog) {
                PastRunLogView()
            }
            .sheet(isPresented: $showRunActions) {
                QuickActionSheet(
                    title: "Activity Actions",
                    actions: [
                        QuickActionSheetAction(
                            id: "run.start-now",
                            title: "Start now",
                            subtitle: "Track a run with GPS.",
                            systemImage: "play.fill",
                            accessibilityIdentifier: "runs.action.start_now",
                            handler: { presentRunTracking(for: "running") }
                        ),
                        QuickActionSheetAction(
                            id: "run.log-past",
                            title: "Log past activity",
                            subtitle: "Enter distance, duration, and date manually.",
                            systemImage: "calendar",
                            accessibilityIdentifier: "runs.action.log_past",
                            handler: { showPastRunLog = true }
                        ),
                        QuickActionSheetAction(
                            id: "run.import-health",
                            title: "Check Cardio Inbox",
                            subtitle: "Review and link cardio workouts from Apple Health.",
                            systemImage: "tray.and.arrow.down",
                            accessibilityIdentifier: "runs.action.import_health",
                            handler: { importHealthRuns(limit: forcedHealthImportLimit, force: true) }
                        )
                    ]
                )
            }
            .sheet(item: $quickViewSession) { session in
                RunQuickViewSheet(
                    session: session,
                    preferredDistanceUnit: preferredDistanceUnit,
                    locationName: locationCache[session.id]
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .background {
                Color.clear.alert("Save Failed", isPresented: Binding(
                    get: { saveErrorMessage != nil },
                    set: { if !$0 { saveErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { saveErrorMessage = nil }
                } message: {
                    Text(saveErrorMessage ?? "Couldn’t save your changes. Please try again.")
                }
            }
            .id(appTheme) // Force rebuild when theme changes
    }

    private func clearRunHistoryFilters() {
        historySearchText = ""
        historyRange = .all
        historyActivityType = nil
        resetRunHistoryPagination()
    }

    private func resetRunHistoryPagination() {
        visibleRunCount = runPageSize
        reloadHistory()
    }

    private func reloadHistory() {
        do {
            let page = try RunHistoryStore.fetch(context: modelContext, search: historySearchText,
                range: historyRange, activity: historyActivityType, limit: visibleRunCount)
            historyPage = page.sessions
            historyResultCount = page.matchingCount
            totalRunCount = page.totalCount
        } catch {
            saveErrorMessage = "Activity history couldn't be loaded. Please try again."
        }
    }

    private func sessionForNavigation(id: UUID) -> RunningSession? {
        var descriptor = FetchDescriptor<RunningSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func sessionForHealthUUID(_ uuid: String) -> RunningSession? {
        var descriptor = FetchDescriptor<RunningSession>(predicate: #Predicate { $0.healthWorkoutUUID == uuid })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func matchesHistoryActivity(_ sessionType: String, selectedType: String) -> Bool {
        if selectedType == "stairClimbing" {
            return sessionType == "stairClimbing" || sessionType == "stairStepper"
        }
        return sessionType == selectedType
    }
    
    private func activityTitle(for type: String) -> String {
        switch type {
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
        case "stairStepper", "stairClimbing":
            return "Tracking Stair Climbing"
        default:
            return "Tracking Run"
        }
    }
    
    private func activityFilterOptions() -> [String] {
        ["Running", "Walking", "Hiking", "Cycling", "Rowing", "Elliptical", "Stair Climbing"]
    }

    private func presentRunTracking(
        for activityType: String,
        plannedTarget: ScheduledRunTarget? = nil
    ) {
        runTrackingRequest = RunTrackingRequest(
            activityType: activityType,
            plannedTarget: plannedTarget
        )
    }

    private func runDistanceSummary(filteredSessions: [RunningSession], unitLabel: String) -> String {
        guard !filteredSessions.isEmpty else {
            return "Start a run or import from Health to see your distance trend."
        }

        let longest = filteredSessions
            .map { UnitConverter.distance($0.distance, from: $0.distanceUnit, to: unitLabel) }
            .max() ?? 0

        guard longest > 0 else {
            return "Activities logged, but no distance recorded yet."
        }

        let formatted = longest.formatted(.number.precision(.fractionLength(1)))
        return "Longest activity: \(formatted) \(unitLabel)."
    }

    private func keyForActivity(_ label: String) -> String {
        switch label.lowercased() {
        case "running": return "running"
        case "walking": return "walking"
        case "hiking": return "hiking"
        case "cycling": return "cycling"
        case "rowing": return "rowing"
        case "elliptical": return "elliptical"
        case "stair climbing": return "stairClimbing"
        default: return "running"
        }
    }

    private func activityIcon(for type: String) -> String {
        switch type {
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
    
    private func activityName(for type: String) -> String {
        switch type {
        case "walking":
            return "Walk"
        case "hiking":
            return "Hike"
        case "cycling":
            return "Cycle"
        case "rowing":
            return "Row"
        case "elliptical":
            return "Elliptical"
        case "stairStepper":
            return "Stair Stepper"
        case "stairClimbing":
            return "Stair Climbing"
        default:
            return "Run"
        }
    }
    
    private func deleteRunningSession(_ session: RunningSession, action: String) {
        withAnimation {
            do { try CoachDeletionService.detachActual(runID: session.id, context: modelContext) }
            catch { saveErrorMessage = error.localizedDescription; return }
            if let inboxItems = try? modelContext.fetch(
                FetchDescriptor<CardioWorkoutInboxItem>()
            ) {
                for item in inboxItems where
                    item.linkedRunningSessionID == session.id {
                    item.status = .pending
                    item.linkedRunningSessionID = nil
                    item.suggestedRunningSessionID = nil
                }
            }
            modelContext.delete(session)
            _ = PersistenceSave.commit(
                modelContext,
                action: action,
                onFailure: { message in saveErrorMessage = message }
            )
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func formatPace(distance: Double, duration: TimeInterval, unit: String) -> String {
        guard distance > 0, duration > 0 else { return "—" }
        let minutesPerUnit = (duration / 60.0) / distance
        let mins = Int(minutesPerUnit)
        let secs = Int((minutesPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d/%@", mins, secs, unit)
    }

    private func reconcileAssistantPlanCompletions() {
        guard let activePlan = RunAssistantService.shared.activePlan(context: modelContext) else { return }
        RunAssistantService.shared.reconcileCompletions(activePlan: activePlan, runs: runningSessions, context: modelContext)
    }

    // MARK: - Steps and Calories helpers
    private func fetchTodaySteps() {
        Task { @MainActor in
            do {
                let value = try await HealthKitManager.shared.todayStepCount()
                stepsToday = value
            } catch {
                stepsToday = nil
            }
        }
    }

    private func latestWeightKg() -> Double? {
        // Fetch latest weight entry from SwiftData; convert to kg
        var fd = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 1
        if let entry = try? modelContext.fetch(fd).first {
            if entry.weightUnit == "kg" { return entry.weight }
            return entry.weight / 2.20462
        }
        return nil
    }

    private func estimatedCalories(for session: RunningSession) -> Double {
        // Estimate calories using MET based on modality & speed with simple heuristics.
        let hours = max(session.duration / 3600.0, 0.0001)
        let miles = (session.distanceUnit == "mi") ? session.distance : session.distance / 1.60934
        let mph = miles / hours
        let met: Double = {
            switch session.activityType {
            case "cycling":
                switch mph {
                case ..<10: return 4.0
                case 10..<12: return 6.0
                case 12..<14: return 8.0
                case 14..<16: return 10.0
                case 16..<19: return 12.0
                default: return 16.0
                }
            case "rowing":
                switch mph { // mph proxy for intensity; rowing usually slower speeds
                case ..<3: return 4.0
                case 3..<4.5: return 7.0
                default: return 10.0
                }
            case "elliptical":
                return 5.5 // moderate effort constant when distance may be 0
            case "stairStepper", "stairClimbing":
                return 8.0 // vigorous effort constant when distance may be 0
            default: // running/walking/hiking
                switch mph {
                case ..<2.5: return 2.5
                case 2.5..<3.0: return 3.3
                case 3.0..<3.5: return 3.8
                case 3.5..<4.0: return 4.3
                case 4.0..<5.0: return 5.0
                case 5.0..<5.5: return 8.3
                case 5.5..<6.0: return 9.0
                case 6.0..<7.0: return 9.8
                case 7.0..<8.0: return 11.0
                case 8.0..<9.0: return 11.8
                case 9.0..<10.0: return 12.8
                default: return 14.5
                }
            }
        }()
        let kg = latestWeightKg() ?? 70.0
        let minutes = session.duration / 60.0
        return max(met * 3.5 * kg / 200.0 * minutes, 0)
    }
    
    private func caloriesFor(_ session: RunningSession) -> Double {
        if let c = session.calories, c > 0 { return c }
        return estimatedCalories(for: session)
    }

    // MARK: - HealthKit import
    private func importHealthRuns(limit: Int? = nil, force: Bool = false) {
        guard shouldImportHealthRuns(force: force) else { return }
        let effectiveLimit = max(1, limit ?? defaultHealthImportLimit)

        Task { @MainActor in
            let result = await CardioWorkoutInboxService.sync(
                context: modelContext,
                pageLimit: effectiveLimit,
                requestAuthorization: force
            )
            if let errorMessage = result.errorMessage {
                saveErrorMessage = "Cardio inbox refresh failed: \(errorMessage)"
            } else {
                runsLastHealthImportAt = Date().timeIntervalSince1970
            }
        }
    }

    /// Kept temporarily for migration reference while older app stores move to
    /// the explicit cardio inbox. New Health changes are handled above.
    private func legacyImportHealthRuns(limit: Int? = nil, force: Bool = false) {
        guard shouldImportHealthRuns(force: force) else { return }
        let effectiveLimit = max(1, limit ?? defaultHealthImportLimit)
        let expectedPurgeGeneration =
            WearableWorkoutInboxService.localDataPurgeGeneration

        Task(priority: .utility) {
            do {
                let changes = try await HealthKitManager.shared.fetchCardioWorkoutChanges(resetAnchor: false, limit: effectiveLimit)
                let existingRuns = await MainActor.run {
                    () -> [ExistingRunSnapshot]? in
                    guard WearableWorkoutInboxService
                        .isCurrentLocalDataPurgeGeneration(
                            expectedPurgeGeneration
                        ) else {
                        return nil
                    }
                    return runningSessions.map {
                        ExistingRunSnapshot(
                            id: $0.id,
                            date: $0.date,
                            distance: $0.distance,
                            distanceUnit: $0.distanceUnit,
                            duration: $0.duration,
                            healthWorkoutUUID: $0.healthWorkoutUUID,
                            activityType: $0.activityType
                        )
                    }
                }
                guard let existingRuns else { return }

                let workouts = changes.added
                var existingUUIDs = Set(existingRuns.compactMap(\.healthWorkoutUUID))
                let runLookup = existingRuns
                var actions: [RunImportAction] = []
                var uuidsToEnrich: [String] = []
                var uuidsToForceEnrich: [String] = []

                let replacements = SameBatchCardioReplacementReconciler.matches(
                    changes: changes,
                    addedWorkouts: workouts,
                    existingSessions: existingRuns.compactMap {
                        run -> CardioReplacementSessionSnapshot? in
                        guard let healthWorkoutUUID = run.healthWorkoutUUID,
                              !healthWorkoutUUID.isEmpty else { return nil }
                        return CardioReplacementSessionSnapshot(
                            healthWorkoutUUID: healthWorkoutUUID,
                            sessionID: run.id,
                            date: run.date,
                            distance: run.distance,
                            distanceUnit: run.distanceUnit,
                            duration: run.duration,
                            activityType: run.activityType
                        )
                    }
                )
                let replacementByAddedUUID = Dictionary(
                    uniqueKeysWithValues: replacements.map {
                        ($0.addedWorkoutUUID, $0)
                    }
                )
                let replacedDeletedUUIDs = Set(replacements.map(\.deletedUUID))

                for deletedUUID in changes.deletedUUIDs
                where !replacedDeletedUUIDs.contains(deletedUUID) {
                    actions.append(.unlink(healthWorkoutUUID: deletedUUID))
                }

                for w in workouts {
                    // Map HK activity to our string type
                    let activityType: String
                    switch w.workoutActivityType {
                    case .running: activityType = "running"
                    case .walking: activityType = "walking"
                    case .hiking: activityType = "hiking"
                    case .cycling: activityType = "cycling"
                    case .rowing: activityType = "rowing"
                    case .elliptical: activityType = "elliptical"
                    case .stairClimbing: activityType = "stairClimbing"
                    default: continue
                    }
                    let end = w.endDate
                    let duration = w.duration
                    let meters = HealthKitManager.recordedDistanceMeters(for: w)
                    let unit = preferredDistanceUnit // from @AppStorage
                    let value: Double = (unit == "mi") ? (meters / 1609.34) : (meters / 1000.0)
                    let uuidStr = w.uuid.uuidString
                    if existingUUIDs.contains(uuidStr) { continue }

                    existingUUIDs.insert(uuidStr)

                    if let replacement = replacementByAddedUUID[uuidStr] {
                        actions.append(.update(
                            sessionID: replacement.sessionID,
                            healthWorkoutUUID: uuidStr,
                            activityType: activityType,
                            date: end,
                            distance: value,
                            distanceUnit: unit,
                            duration: duration,
                            calories: nil,
                            locations: nil
                        ))
                        uuidsToEnrich.append(uuidStr)
                        uuidsToForceEnrich.append(uuidStr)
                        continue
                    }

                    // Attempt to match a similar local run (e.g., tracked via phone) and attach the UUID
                    if let similarId = findSimilarRunID(
                        in: runLookup,
                        endDate: end,
                        duration: duration,
                        distance: value,
                        unit: unit
                    ) {
                        let kcal: Double? = nil
                        actions.append(.update(
                            sessionID: similarId,
                            healthWorkoutUUID: uuidStr,
                            activityType: activityType,
                            date: nil,
                            distance: nil,
                            distanceUnit: nil,
                            duration: nil,
                            calories: kcal,
                            locations: nil
                        ))
                        uuidsToEnrich.append(uuidStr)
                    } else {
                        let kcal: Double? = nil
                        actions.append(.insert(
                            NewRunPayload(
                                date: end,
                                distance: value,
                                distanceUnit: unit,
                                duration: duration,
                                calories: (kcal ?? 0) > 0 ? kcal : nil,
                                locations: nil,
                                healthWorkoutUUID: uuidStr,
                                activityType: activityType,
                                avgHeartRate: nil,
                                maxHeartRate: nil,
                                minHeartRate: nil,
                                avgCadence: nil,
                                maxCadence: nil,
                                totalAscent: nil,
                                totalDescent: nil,
                                minElevation: nil,
                                maxElevation: nil,
                                avgPower: nil,
                                maxPower: nil
                            )
                        ))
                        uuidsToEnrich.append(uuidStr)
                    }
                }

                await MainActor.run {
                    guard WearableWorkoutInboxService
                        .isCurrentLocalDataPurgeGeneration(
                            expectedPurgeGeneration
                        ) else {
                        return
                    }
                    let didCommit = applyImportActions(actions)
                    guard didCommit else { return }

                    var forcedSeen = Set<String>()
                    let forcedUUIDs = uuidsToForceEnrich.filter {
                        forcedSeen.insert($0).inserted
                    }
                    enqueuePersistedForcedEnrichmentUUIDs(forcedUUIDs)

                    HealthKitManager.shared.persistCardioWorkoutAnchor(changes.newAnchor)
                    runsLastHealthImportAt = Date().timeIntervalSince1970

                    var ordinarySeen = Set(forcedUUIDs)
                    let ordinaryUUIDs = uuidsToEnrich.filter {
                        ordinarySeen.insert($0).inserted
                    }
                    let scheduledUUIDs =
                        forcedUUIDs +
                        Array(ordinaryUUIDs.prefix(autoEnrichmentLimit))
                    scheduleDeferredEnrichment(
                        for: scheduledUUIDs,
                        forcing: Set(forcedUUIDs)
                    )
                }
            } catch {
                // Ignore errors silently; user may not have granted permission yet
            }
        }
    }
    
    // Reduce number of points to speed map rendering/storage. Keep up to ~1200 points and at least 5 m apart
    private func downsampleLocations(_ locs: [CLLocation], maxPoints: Int = 1200, minDistance: Double = 5.0) -> [CLLocation] {
        if locs.count <= maxPoints { return locs }
        var reduced: [CLLocation] = []
        var last: CLLocation? = nil
        for l in locs {
            if let last, l.distance(from: last) < minDistance { continue }
            reduced.append(l)
            last = l
            if reduced.count >= maxPoints { break }
        }
        return reduced
    }

    private func scheduleInitialHealthImportIfNeeded() {
        guard !hasScheduledInitialImport else { return }
        hasScheduledInitialImport = true

        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            importHealthRuns()
        }
    }

    private func scheduleImportForHealthWorkoutUpdate() {
        healthChangeDebounceTask?.cancel()
        healthChangeDebounceTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                UserDefaults.standard.set(false, forKey: "runsPendingHealthImport")
                importHealthRuns(limit: forcedHealthImportLimit, force: true)
            }
        }
    }

    private func shouldImportHealthRuns(force: Bool) -> Bool {
        if force { return true }

        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval = 60 * 60 // 1 hour
        return now - runsLastHealthImportAt >= minInterval
    }

    @MainActor
    private func applyImportActions(_ actions: [RunImportAction]) -> Bool {
        guard !actions.isEmpty else { return true }

        let sessionsById = Dictionary(uniqueKeysWithValues: runningSessions.map { ($0.id, $0) })

        for action in actions {
            switch action {
            case let .update(
                sessionID,
                uuid,
                activityType,
                date,
                distance,
                distanceUnit,
                duration,
                calories,
                locations
            ):
                guard let similar = sessionsById[sessionID] else { continue }
                similar.healthWorkoutUUID = uuid
                similar.activityType = activityType
                if let date { similar.date = date }
                if let distance { similar.distance = distance }
                if let distanceUnit { similar.distanceUnit = distanceUnit }
                if let duration { similar.duration = duration }
                if let calories, calories > 0 { similar.calories = calories }
                if similar.locations.isEmpty, let locations, !locations.isEmpty {
                    similar.locations = locations
                }

            case let .unlink(healthWorkoutUUID):
                guard let session = sessionsById.values.first(where: { $0.healthWorkoutUUID == healthWorkoutUUID }) else { continue }
                // Health records and app logs are separate. Preserve the local
                // run (including notes/routes) when Health reports a deletion;
                // a later replacement can relink it by similarity.
                session.healthWorkoutUUID = nil

            case let .insert(payload):
                let model = RunningSession(
                    date: payload.date,
                    distance: payload.distance,
                    distanceUnit: payload.distanceUnit,
                    duration: payload.duration,
                    calories: payload.calories,
                    notes: nil,
                    locations: payload.locations,
                    healthWorkoutUUID: payload.healthWorkoutUUID,
                    activityType: payload.activityType,
                    avgHeartRate: payload.avgHeartRate,
                    maxHeartRate: payload.maxHeartRate,
                    minHeartRate: payload.minHeartRate,
                    avgCadence: payload.avgCadence,
                    maxCadence: payload.maxCadence,
                    totalAscent: payload.totalAscent,
                    totalDescent: payload.totalDescent,
                    minElevation: payload.minElevation,
                    maxElevation: payload.maxElevation,
                    avgPower: payload.avgPower,
                    maxPower: payload.maxPower
                )
                modelContext.insert(model)
            }
        }

        return PersistenceSave.commit(
            modelContext,
            action: "import Health runs",
            onFailure: { message in saveErrorMessage = message }
        )
    }

    private func findSimilarRunID(
        in runs: [ExistingRunSnapshot],
        endDate: Date,
        duration: TimeInterval,
        distance: Double,
        unit: String
    ) -> UUID? {
        return runs.first {
            HealthKitManager.runsAreSimilar(
                aDate: $0.date, aDuration: $0.duration, aDistance: $0.distance, aUnit: $0.distanceUnit,
                bDate: endDate, bDuration: duration, bDistance: distance, bUnit: unit
            )
        }?.id
    }

    @MainActor
    private func restorePersistedForcedEnrichment() {
        let persisted = persistedForcedEnrichmentUUIDs()
        guard !persisted.isEmpty else { return }

        let linkedUUIDs = Set(
            runningSessions
                .compactMap(\.healthWorkoutUUID)
                .filter { !$0.isEmpty }
        )
        let noLongerNeeded = persisted.subtracting(linkedUUIDs)
        if !noLongerNeeded.isEmpty {
            updatePersistedForcedEnrichmentUUIDs(
                persisted.subtracting(noLongerNeeded)
            )
        }

        let retryUUIDs = persisted
            .intersection(linkedUUIDs)
            .subtracting(activeForcedEnrichmentUUIDs)
        guard !retryUUIDs.isEmpty else { return }

        scheduleDeferredEnrichment(
            for: Array(retryUUIDs),
            forcing: retryUUIDs
        )
    }

    @MainActor
    private func enqueuePersistedForcedEnrichmentUUIDs(_ uuids: [String]) {
        let cleaned = Set(uuids.filter { !$0.isEmpty })
        guard !cleaned.isEmpty else { return }
        updatePersistedForcedEnrichmentUUIDs(
            persistedForcedEnrichmentUUIDs().union(cleaned)
        )
    }

    @MainActor
    private func removePersistedForcedEnrichmentUUID(_ uuid: String) {
        var persisted = persistedForcedEnrichmentUUIDs()
        guard persisted.remove(uuid) != nil else { return }
        updatePersistedForcedEnrichmentUUIDs(persisted)
    }

    private func persistedForcedEnrichmentUUIDs() -> Set<String> {
        Set(
            UserDefaults.standard
                .stringArray(
                    forKey: Self.pendingForcedEnrichmentDefaultsKey
                ) ?? []
        ).filter { !$0.isEmpty }
    }

    private func updatePersistedForcedEnrichmentUUIDs(
        _ uuids: Set<String>
    ) {
        let defaults = UserDefaults.standard
        if uuids.isEmpty {
            defaults.removeObject(
                forKey: Self.pendingForcedEnrichmentDefaultsKey
            )
        } else {
            defaults.set(
                uuids.sorted(),
                forKey: Self.pendingForcedEnrichmentDefaultsKey
            )
        }
    }

    @MainActor
    private func scheduleDeferredEnrichment(
        for uuids: [String],
        forcing forcedUUIDs: Set<String> = []
    ) {
        let schedulableForcedUUIDs = forcedUUIDs
            .subtracting(activeForcedEnrichmentUUIDs)
        for uuid in uuids where
            !uuid.isEmpty &&
            (!forcedUUIDs.contains(uuid) ||
                schedulableForcedUUIDs.contains(uuid)) {
            pendingEnrichmentUUIDs.insert(uuid)
        }
        pendingForcedEnrichmentUUIDs.formUnion(schedulableForcedUUIDs)

        guard enrichmentTask == nil else { return }

        enrichmentTask = Task(priority: .utility) {
            // Let first render/nav settle before detail fetch work starts.
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let maxPerPass = 2
            var processed = 0

            while processed < maxPerPass {
                if Task.isCancelled { break }

                let next = await MainActor.run { () -> (String, Bool)? in
                    guard let uuid = pendingEnrichmentUUIDs.first else {
                        return nil
                    }
                    _ = pendingEnrichmentUUIDs.remove(uuid)
                    let forceRefresh =
                        pendingForcedEnrichmentUUIDs.remove(uuid) != nil
                    if forceRefresh {
                        activeForcedEnrichmentUUIDs.insert(uuid)
                    }
                    return (uuid, forceRefresh)
                }
                guard let (nextUUID, forceRefresh) = next else { break }

                let outcome = await enrichRunDetails(
                    forWorkoutUUID: nextUUID,
                    forceHealthMetrics: forceRefresh
                )
                if forceRefresh {
                    await MainActor.run {
                        activeForcedEnrichmentUUIDs.remove(nextUUID)
                        switch outcome {
                        case .completed, .noLongerNeeded:
                            removePersistedForcedEnrichmentUUID(nextUUID)
                            // A view activation may have restored the UUID while
                            // this attempt was in flight.
                            pendingEnrichmentUUIDs.remove(nextUUID)
                            pendingForcedEnrichmentUUIDs.remove(nextUUID)
                        case .retryLater:
                            // Leave the durable entry for a later view activation.
                            break
                        }
                    }
                }
                processed += 1
            }

            await MainActor.run {
                enrichmentTask = nil
                if !pendingEnrichmentUUIDs.isEmpty {
                    scheduleDeferredEnrichment(for: [])
                }
            }
        }
    }

    private func enrichRunDetails(
        forWorkoutUUID uuid: String,
        forceHealthMetrics: Bool
    ) async -> EnrichmentOutcome {
        let needs = await MainActor.run {
            enrichmentNeeds(
                forWorkoutUUID: uuid,
                forceHealthMetrics: forceHealthMetrics
            )
        }
        guard let needs else { return .noLongerNeeded }
        guard needs.requiresAnyFetch else { return .completed }

        let workout: HKWorkout
        do {
            guard let fetchedWorkout = try await HealthKitManager.shared
                .workoutForUUID(uuid) else {
                return .noLongerNeeded
            }
            workout = fetchedWorkout
        } catch {
            return .retryLater
        }

        var routeData: Data? = nil
        var elevationMetrics: (ascent: Double, descent: Double, min: Double, max: Double)? = nil

        if needs.needsRoute || needs.needsElevation {
            if let locs = try? await HealthKitManager.shared
                .routeLocations(for: workout), !locs.isEmpty {
                let reduced = downsampleLocations(locs)
                let coords = reduced.map {
                    RunCoordinate(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude,
                        altitude: $0.altitude,
                        timestamp: $0.timestamp
                    )
                }
                routeData = try? JSONEncoder().encode(coords)
                elevationMetrics = ElevationCalculator.calculateElevationMetrics(from: coords)
            }
        }

        let calories: Double?
        let avgHeartRate: Double?
        let maxHeartRate: Double?
        let minHeartRate: Double?
        let avgCadence: Double?
        let maxCadence: Double?
        let avgStrideLength: Double?
        let verticalOscillation: Double?
        let groundContactTime: Double?
        let avgPower: Double?
        let maxPower: Double?

        if forceHealthMetrics {
            do {
                calories = try await HealthKitManager.shared
                    .activeEnergyKilocalories(for: workout)
                avgHeartRate = try await HealthKitManager.shared
                    .averageHeartRate(for: workout)
                maxHeartRate = try await HealthKitManager.shared
                    .maxHeartRate(for: workout)
                minHeartRate = try await HealthKitManager.shared
                    .minHeartRate(for: workout)
                avgCadence = try await HealthKitManager.shared
                    .averageCadence(for: workout)
                maxCadence = try await HealthKitManager.shared
                    .maxCadence(for: workout)
                avgStrideLength = try await HealthKitManager.shared
                    .averageStrideLength(for: workout)
                verticalOscillation = try await HealthKitManager.shared
                    .averageVerticalOscillation(for: workout)
                groundContactTime = try await HealthKitManager.shared
                    .averageGroundContactTime(for: workout)
                avgPower = try await HealthKitManager.shared
                    .averagePower(for: workout)
                maxPower = try await HealthKitManager.shared
                    .maxPower(for: workout)
            } catch {
                return .retryLater
            }
        } else {
            calories = needs.needsCalories
                ? (try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout))
                : nil
            avgHeartRate = needs.needsHeartRate
                ? (try? await HealthKitManager.shared.averageHeartRate(for: workout))
                : nil
            maxHeartRate = needs.needsHeartRate
                ? (try? await HealthKitManager.shared.maxHeartRate(for: workout))
                : nil
            minHeartRate = needs.needsHeartRate
                ? (try? await HealthKitManager.shared.minHeartRate(for: workout))
                : nil
            avgCadence = needs.needsCadence
                ? (try? await HealthKitManager.shared.averageCadence(for: workout))
                : nil
            maxCadence = needs.needsCadence
                ? (try? await HealthKitManager.shared.maxCadence(for: workout))
                : nil
            avgStrideLength = needs.needsStrideLength
                ? (try? await HealthKitManager.shared.averageStrideLength(for: workout))
                : nil
            verticalOscillation = needs.needsVerticalOscillation
                ? (try? await HealthKitManager.shared.averageVerticalOscillation(for: workout))
                : nil
            groundContactTime = needs.needsGroundContactTime
                ? (try? await HealthKitManager.shared.averageGroundContactTime(for: workout))
                : nil
            avgPower = needs.needsPower
                ? (try? await HealthKitManager.shared.averagePower(for: workout))
                : nil
            maxPower = needs.needsPower
                ? (try? await HealthKitManager.shared.maxPower(for: workout))
                : nil
        }

        let didCommit: Bool? = await MainActor.run {
            guard let session = sessionForHealthUUID(uuid) else {
                return nil
            }

            if let calories, calories > 0 { session.calories = calories }

            if needs.needsRoute,
               session.locations.isEmpty,
               let routeData,
               !routeData.isEmpty {
                session.locations = routeData
            }

            if needs.needsHeartRate {
                if let avgHeartRate,
                   forceHealthMetrics || session.avgHeartRate == nil {
                    session.avgHeartRate = avgHeartRate
                }
                if let maxHeartRate,
                   forceHealthMetrics || session.maxHeartRate == nil {
                    session.maxHeartRate = maxHeartRate
                }
                if let minHeartRate,
                   forceHealthMetrics || session.minHeartRate == nil {
                    session.minHeartRate = minHeartRate
                }
            }

            if needs.needsCadence {
                if let avgCadence,
                   forceHealthMetrics || session.avgCadence == nil {
                    session.avgCadence = avgCadence
                }
                if let maxCadence,
                   forceHealthMetrics || session.maxCadence == nil {
                    session.maxCadence = maxCadence
                }
            }
            if needs.needsStrideLength,
               let avgStrideLength,
               forceHealthMetrics || session.avgStrideLength == nil {
                session.avgStrideLength = avgStrideLength
            }
            if needs.needsVerticalOscillation,
               let verticalOscillation,
               forceHealthMetrics || session.verticalOscillation == nil {
                session.verticalOscillation = verticalOscillation
            }
            if needs.needsGroundContactTime,
               let groundContactTime,
               forceHealthMetrics || session.groundContactTime == nil {
                session.groundContactTime = groundContactTime
            }

            if needs.needsPower {
                if let avgPower,
                   forceHealthMetrics || session.avgPower == nil {
                    session.avgPower = avgPower
                }
                if let maxPower,
                   forceHealthMetrics || session.maxPower == nil {
                    session.maxPower = maxPower
                }
            }

            if needs.needsElevation, let elevationMetrics {
                if session.totalAscent == nil { session.totalAscent = elevationMetrics.ascent }
                if session.totalDescent == nil { session.totalDescent = elevationMetrics.descent }
                if session.minElevation == nil { session.minElevation = elevationMetrics.min }
                if session.maxElevation == nil { session.maxElevation = elevationMetrics.max }
            }

            return PersistenceSave.commit(
                modelContext,
                action: "enrich run details"
            )
        }
        guard let didCommit else { return .noLongerNeeded }
        return didCommit ? .completed : .retryLater
    }

    @MainActor
    private func enrichmentNeeds(
        forWorkoutUUID uuid: String,
        forceHealthMetrics: Bool
    ) -> RunEnrichmentNeeds? {
        guard let session = sessionForHealthUUID(uuid) else { return nil }
        return RunEnrichmentNeeds(
            needsCalories: forceHealthMetrics || (session.calories ?? 0) <= 0,
            needsRoute: session.locations.isEmpty,
            needsHeartRate: forceHealthMetrics || session.avgHeartRate == nil || session.maxHeartRate == nil || session.minHeartRate == nil,
            needsCadence: forceHealthMetrics || session.avgCadence == nil || session.maxCadence == nil,
            needsStrideLength: forceHealthMetrics || session.avgStrideLength == nil,
            needsVerticalOscillation: forceHealthMetrics || session.verticalOscillation == nil,
            needsGroundContactTime: forceHealthMetrics || session.groundContactTime == nil,
            needsPower: forceHealthMetrics || session.avgPower == nil || session.maxPower == nil,
            needsElevation: session.totalAscent == nil || session.totalDescent == nil || session.minElevation == nil || session.maxElevation == nil
        )
    }
    
    private func prefetchLocationNames() {
        // Prevent duplicate prefetching on the same set of sessions
        guard !hasPrefetchedLocations || historyPage.count != locationCache.count else { return }

        // Only prefetch for sessions that don't already have cached names and aren't currently being fetched
        let sessionsToFetch = historyPage.filter { session in
            locationCache[session.id] == nil && !pendingLocationTasks.contains(session.id)
        }

        // Limit concurrent requests to prevent overwhelming the service
        let maxConcurrent = 3
        let fetchCount = min(sessionsToFetch.count, maxConcurrent - pendingLocationTasks.count)

        guard fetchCount > 0 else {
            hasPrefetchedLocations = true
            return
        }

        for session in sessionsToFetch.prefix(fetchCount) {
            guard !session.locations.isEmpty,
                  let coords = try? JSONDecoder().decode([RunCoordinate].self, from: session.locations),
                  let first = coords.first?.cl else { continue }

            pendingLocationTasks.insert(session.id)
            let coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)

            Task {
                // Throttled global search to avoid PlaceRequest throttling
                if let name = await MapSearchService.shared.reverseAddressName(near: coordinate) {
                    _ = await MainActor.run {
                        locationCache[session.id] = name
                        pendingLocationTasks.remove(session.id)
                    }
                } else {
                    _ = await MainActor.run {
                        pendingLocationTasks.remove(session.id)
                    }
                }
            }
        }

        // Mark as prefetched if we've started fetching all available sessions
        if sessionsToFetch.count <= fetchCount {
            hasPrefetchedLocations = true
        }
    }
}

struct SameBatchCardioReplacement {
    let deletedUUID: String
    let addedWorkoutUUID: String
    let sessionID: UUID
}

struct CardioReplacementSessionSnapshot {
    let healthWorkoutUUID: String
    let sessionID: UUID
    let date: Date
    let distance: Double
    let distanceUnit: String
    let duration: TimeInterval
    let activityType: String
}

enum SameBatchCardioReplacementReconciler {
    static func matches(
        changes: HealthKitManager.CardioWorkoutChanges,
        addedWorkouts: [HKWorkout],
        existingSessions: [CardioReplacementSessionSnapshot]
    ) -> [SameBatchCardioReplacement] {
        let sessionsByHealthUUID = Dictionary(
            grouping: existingSessions,
            by: { $0.healthWorkoutUUID }
        )

        var addedBySyncIdentifier: [String: [HKWorkout]] = [:]
        for workout in addedWorkouts {
            guard let syncIdentifier = syncIdentifier(
                in: workout.metadata
            ) else { continue }
            addedBySyncIdentifier[syncIdentifier, default: []].append(workout)
        }

        var deletedBySyncIdentifier:
            [String: [HealthKitManager.CardioWorkoutChanges.DeletedWorkout]] = [:]
        for deleted in changes.deleted {
            guard let syncIdentifier = normalized(deleted.syncIdentifier) else {
                continue
            }
            deletedBySyncIdentifier[syncIdentifier, default: []].append(deleted)
        }

        var matches: [SameBatchCardioReplacement] = []
        for syncIdentifier in deletedBySyncIdentifier.keys.sorted() {
            guard let deletedObjects = deletedBySyncIdentifier[syncIdentifier],
                  let addedCandidates = addedBySyncIdentifier[syncIdentifier]
            else { continue }

            let linkedDeletedObjects = deletedObjects.compactMap { deleted -> (
                deleted: HealthKitManager.CardioWorkoutChanges.DeletedWorkout,
                session: CardioReplacementSessionSnapshot
            )? in
                guard let sessions = sessionsByHealthUUID[deleted.uuid],
                      sessions.count == 1,
                      let session = sessions.first else { return nil }
                return (deleted, session)
            }
            guard linkedDeletedObjects.count == 1,
                  let linkedDeletion = linkedDeletedObjects.first else {
                continue
            }

            let availableCandidates = addedCandidates.filter {
                sessionsByHealthUUID[$0.uuid.uuidString] == nil &&
                    semanticallyMatches(
                        $0,
                        session: linkedDeletion.session
                    )
            }
            guard let replacement = preferredCandidate(
                from: availableCandidates
            ) else { continue }

            matches.append(
                SameBatchCardioReplacement(
                    deletedUUID: linkedDeletion.deleted.uuid,
                    addedWorkoutUUID: replacement.uuid.uuidString,
                    sessionID: linkedDeletion.session.sessionID
                )
            )
        }
        return matches
    }

    private static func semanticallyMatches(
        _ workout: HKWorkout,
        session: CardioReplacementSessionSnapshot
    ) -> Bool {
        guard let activityType = activityKey(for: workout.workoutActivityType),
              activityType == session.activityType ||
                (activityType == "stairClimbing" &&
                    session.activityType == "stairStepper") else {
            return false
        }

        let candidateMeters = HealthKitManager.recordedDistanceMeters(
            for: workout
        )
        let sessionMeters = session.distanceUnit == "mi"
            ? session.distance * 1609.34
            : session.distance * 1000
        return abs(session.date.timeIntervalSince(workout.endDate)) <= 120 &&
            abs(session.duration - workout.duration) <= 120 &&
            abs(sessionMeters - candidateMeters) <= 100
    }

    private static func activityKey(
        for type: HKWorkoutActivityType
    ) -> String? {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairClimbing"
        default: return nil
        }
    }

    private static func preferredCandidate(
        from candidates: [HKWorkout]
    ) -> HKWorkout? {
        guard !candidates.isEmpty else { return nil }

        // Deleted HealthKit objects do not retain their source. Do not guess if
        // two source apps happen to reuse the same source-scoped sync identifier.
        let candidatesBySource = Dictionary(
            grouping: candidates,
            by: { $0.sourceRevision.source.bundleIdentifier.lowercased() }
        )
        guard candidatesBySource.count == 1,
              let sameSourceCandidates = candidatesBySource.values.first else {
            return nil
        }
        if sameSourceCandidates.count == 1 {
            return sameSourceCandidates[0]
        }

        let versionedCandidates = sameSourceCandidates.compactMap { workout -> (
            workout: HKWorkout,
            version: Int
        )? in
            guard let version = syncVersion(in: workout.metadata) else {
                return nil
            }
            return (workout, version)
        }
        guard let highestVersion = versionedCandidates.map(\.version).max() else {
            return nil
        }
        let newestCandidates = versionedCandidates.filter {
            $0.version == highestVersion
        }
        guard newestCandidates.count == 1 else { return nil }
        return newestCandidates[0].workout
    }

    private static func syncIdentifier(
        in metadata: [String: Any]?
    ) -> String? {
        normalized(metadata?[HKMetadataKeySyncIdentifier] as? String)
    }

    private static func syncVersion(
        in metadata: [String: Any]?
    ) -> Int? {
        if let number = metadata?[HKMetadataKeySyncVersion] as? NSNumber {
            return number.intValue
        }
        return metadata?[HKMetadataKeySyncVersion] as? Int
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ExistingRunSnapshot {
    let id: UUID
    let date: Date
    let distance: Double
    let distanceUnit: String
    let duration: TimeInterval
    let healthWorkoutUUID: String?
    let activityType: String
}

private struct RunEnrichmentNeeds {
    let needsCalories: Bool
    let needsRoute: Bool
    let needsHeartRate: Bool
    let needsCadence: Bool
    let needsStrideLength: Bool
    let needsVerticalOscillation: Bool
    let needsGroundContactTime: Bool
    let needsPower: Bool
    let needsElevation: Bool

    var requiresAnyFetch: Bool {
        needsCalories || needsRoute || needsHeartRate || needsCadence || needsStrideLength || needsVerticalOscillation || needsGroundContactTime || needsPower || needsElevation
    }
}

private struct NewRunPayload {
    let date: Date
    let distance: Double
    let distanceUnit: String
    let duration: TimeInterval
    let calories: Double?
    let locations: Data?
    let healthWorkoutUUID: String
    let activityType: String
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let minHeartRate: Double?
    let avgCadence: Double?
    let maxCadence: Double?
    let totalAscent: Double?
    let totalDescent: Double?
    let minElevation: Double?
    let maxElevation: Double?
    let avgPower: Double?
    let maxPower: Double?
}

private enum RunImportAction {
    case update(
        sessionID: UUID,
        healthWorkoutUUID: String,
        activityType: String,
        date: Date?,
        distance: Double?,
        distanceUnit: String?,
        duration: TimeInterval?,
        calories: Double?,
        locations: Data?
    )
    case unlink(healthWorkoutUUID: String)
    case insert(NewRunPayload)
}

// MARK: - Optimized Run Session Row Content
private struct RunSessionRowContent: View {
    let session: RunningSession
    let preferredDistanceUnit: String
    let locationName: String?
    let isEditing: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activityIcon(for: session.activityType))
                .font(.title2)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text("\(String(format: "%.1f", displayDistance)) \(preferredDistanceUnit) • \(String(format: "%.0f", estimatedCalories)) kcal")
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(formattedDuration)
                    Text("•")
                    Text(formattedPace)
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryTextColor)
                if let place = locationName, !place.isEmpty {
                    Text(place)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
            .foregroundColor(AppTheme.textColor)
            Spacer(minLength: 8)
            if isEditing {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
        }
    }
    
    private var formattedDuration: String {
        let hours = Int(session.duration) / 3600
        let minutes = Int(session.duration) / 60 % 60
        let seconds = Int(session.duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var formattedPace: String {
        guard displayDistance > 0, session.duration > 0 else { return "—" }
        let minutesPerUnit = (session.duration / 60.0) / displayDistance
        let mins = Int(minutesPerUnit)
        let secs = Int((minutesPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d/%@", mins, secs, preferredDistanceUnit)
    }

    private var displayDistance: Double {
        UnitConverter.distance(session.distance, from: session.distanceUnit, to: preferredDistanceUnit)
    }
    
    private var estimatedCalories: Double {
        if let c = session.calories, c > 0 { return c }
        let hours = max(session.duration / 3600.0, 0.0001)
        let miles = (session.distanceUnit == "mi") ? session.distance : session.distance / 1.60934
        let mph = miles / hours
        let met: Double = {
            switch session.activityType {
            case "cycling":
                switch mph {
                case ..<10: return 4.0
                case 10..<12: return 6.0
                case 12..<14: return 8.0
                case 14..<16: return 10.0
                case 16..<19: return 12.0
                default: return 16.0
                }
            case "rowing":
                switch mph {
                case ..<3: return 4.0
                case 3..<4.5: return 7.0
                default: return 10.0
                }
            case "elliptical": return 5.5
            case "stairStepper", "stairClimbing": return 8.0
            default:
                switch mph {
                case ..<2.5: return 2.5
                case 2.5..<3.0: return 3.3
                case 3.0..<3.5: return 3.8
                case 3.5..<4.0: return 4.3
                case 4.0..<5.0: return 5.0
                case 5.0..<5.5: return 8.3
                case 5.5..<6.0: return 9.0
                case 6.0..<7.0: return 9.8
                case 7.0..<8.0: return 11.0
                case 8.0..<9.0: return 11.8
                case 9.0..<10.0: return 12.8
                default: return 14.5
                }
            }
        }()
        let minutes = session.duration / 60.0
        return max(met * 3.5 * 70.0 / 200.0 * minutes, 0)
    }
    
    private func activityIcon(for type: String) -> String {
        switch type {
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "bicycle"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.core.training"
        case "stairStepper", "stairClimbing": return "figure.stairs"
        default: return "figure.run"
        }
    }
}

private struct RunQuickViewSheet: View {
    let session: RunningSession
    let preferredDistanceUnit: String
    let locationName: String?

    private var displayDistance: Double {
        UnitConverter.distance(session.distance, from: session.distanceUnit, to: preferredDistanceUnit)
    }

    private var estimatedCalories: Double {
        if let calories = session.calories, calories > 0 {
            return calories
        }

        let hours = max(session.duration / 3600.0, 0.0001)
        let miles = (session.distanceUnit == "mi") ? session.distance : session.distance / 1.60934
        let mph = miles / hours
        let met: Double = {
            switch session.activityType {
            case "cycling":
                switch mph {
                case ..<10: return 4.0
                case 10..<12: return 6.0
                case 12..<14: return 8.0
                case 14..<16: return 10.0
                case 16..<19: return 12.0
                default: return 16.0
                }
            case "rowing":
                switch mph {
                case ..<3: return 4.0
                case 3..<4.5: return 7.0
                default: return 10.0
                }
            case "elliptical": return 5.5
            case "stairStepper", "stairClimbing": return 8.0
            default:
                switch mph {
                case ..<2.5: return 2.5
                case 2.5..<3.0: return 3.3
                case 3.0..<3.5: return 3.8
                case 3.5..<4.0: return 4.3
                case 4.0..<5.0: return 5.0
                case 5.0..<5.5: return 8.3
                case 5.5..<6.0: return 9.0
                case 6.0..<7.0: return 9.8
                case 7.0..<8.0: return 11.0
                case 8.0..<9.0: return 11.8
                case 9.0..<10.0: return 12.8
                default: return 14.5
                }
            }
        }()

        let minutes = session.duration / 60.0
        return max(met * 3.5 * 70.0 / 200.0 * minutes, 0)
    }

    private var formattedDuration: String {
        let hours = Int(session.duration) / 3600
        let minutes = Int(session.duration) / 60 % 60
        let seconds = Int(session.duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedPace: String {
        guard displayDistance > 0, session.duration > 0 else { return "—" }
        let minutesPerUnit = (session.duration / 60.0) / displayDistance
        let mins = Int(minutesPerUnit)
        let secs = Int((minutesPerUnit - Double(mins)) * 60)
        return String(format: "%d:%02d/%@", mins, secs, preferredDistanceUnit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: activityIcon(for: session.activityType))
                        .font(.title2)
                        .foregroundStyle(AppTheme.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(activityTitle(for: session.activityType))
                            .font(.title3.weight(.semibold))
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }
                }

                HStack(spacing: 12) {
                    quickMetric(title: "Distance", value: session.hasMeasuredDistance ? String(format: "%.2f %@", displayDistance, preferredDistanceUnit) : "Not available")
                    quickMetric(title: "Time", value: formattedDuration)
                }

                HStack(spacing: 12) {
                    quickMetric(title: "Pace", value: formattedPace)
                    quickMetric(title: "Calories", value: "\(Int(estimatedCalories.rounded())) kcal")
                }

                if let locationName, !locationName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Location")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text(locationName)
                    }
                }

                if let notes = session.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Text(notes)
                    }
                }
            }
            .padding(AppTheme.padding)
        }
        .appBackground(AppTheme.gradientRuns)
        .foregroundStyle(AppTheme.textColor)
    }

    @ViewBuilder
    private func quickMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func activityIcon(for type: String) -> String {
        switch type {
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "bicycle"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.core.training"
        case "stairStepper", "stairClimbing": return "figure.stairs"
        default: return "figure.run"
        }
    }

    private func activityTitle(for type: String) -> String {
        switch type {
        case "walking": return "Walk"
        case "hiking": return "Hike"
        case "cycling": return "Ride"
        case "rowing": return "Row"
        case "elliptical": return "Elliptical"
        case "stairStepper", "stairClimbing": return "Stair Climb"
        default: return "Run"
        }
    }
}

// MARK: - Elevation Calculator
struct ElevationCalculator {
    static func calculateElevationMetrics(from coordinates: [RunCoordinate]) -> (ascent: Double, descent: Double, min: Double, max: Double)? {
        let altitudes = coordinates.compactMap { $0.altitude }
        guard altitudes.count >= 2 else { return nil }
        
        var totalAscent: Double = 0
        var totalDescent: Double = 0
        var minAlt = altitudes.first!
        var maxAlt = altitudes.first!
        
        // Calculate ascent/descent with smoothing to avoid GPS noise
        let smoothingThreshold: Double = 1.0 // Only count changes > 1m
        
        for i in 1..<altitudes.count {
            let diff = altitudes[i] - altitudes[i-1]
            
            if diff > smoothingThreshold {
                totalAscent += diff
            } else if diff < -smoothingThreshold {
                totalDescent += abs(diff)
            }
            
            minAlt = min(minAlt, altitudes[i])
            maxAlt = max(maxAlt, altitudes[i])
        }
        
        return (ascent: totalAscent, descent: totalDescent, min: minAlt, max: maxAlt)
    }
}

struct RunSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let session: RunningSession
    @State private var selectedTab: Int = 0

    private var hasActual: Bool { (session.calories ?? 0) > 0 }
    private let routeDecodePrefix = "⏱️ Run detail"

    // Build map region around the route
    @State private var camera: MapCameraPosition = .automatic

    // Segment representation
    private struct Segment: Identifiable {
        let id = UUID()
        let points: [CLLocationCoordinate2D]
        let color: Color
    }
    
    @State private var decodedCoordinates: [RunCoordinate] = []
    @State private var cachedSegments: [Segment] = []
    // True from the moment a route needs decoding until the background
    // preparation lands, so the tile shows a spinner instead of flashing the
    // "No Route Recorded" empty state.
    @State private var isPreparingRoute: Bool
    @State private var routePreparationTask: Task<Void, Never>? = nil
    @State private var showMap: Bool = false
    @State private var heartRateSamples: [(timestamp: Date, bpm: Double)] = []
    @State private var isLoadingHeartRate: Bool = false
    @State private var detailAppearStart: Date? = nil
    @State private var hasLoggedFirstMapRender = false

    init(session: RunningSession) {
        self.session = session
        _isPreparingRoute = State(initialValue: !session.locations.isEmpty)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        decodedCoordinates.map(\.cl)
    }

    private var fullCoordinates: [RunCoordinate] {
        decodedCoordinates
    }

    private static func color(for pace: RoutePaceClass) -> Color {
        switch pace {
        case .unknown: return .gray
        case .walk: return .blue
        case .jog: return .orange
        case .run: return .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control in glass container
            Picker("View", selection: $selectedTab.animation(.easeInOut(duration: 0.3))) {
                Text("Overview").tag(0)
                Text("Stats").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppTheme.padding)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider()
                    .opacity(0.3)
            }
            
            // Content view with animation
            Group {
                if selectedTab == 0 {
                // Overview Tab
                ScrollView {
                    VStack(spacing: 24) {
                        if session.intervalResultsData != nil {
                            NavigationLink("Review structured interval results") { CoachSavedRunResultsView(session: session) }
                        }
                        // Prominent Time & Distance Display
                        HStack(spacing: 40) {
                            VStack(spacing: 4) {
                                Text(formatDuration(session.duration))
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.textColor)
                                Text("Time")
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.textColor.opacity(0.7))
                            }
                            
                            VStack(spacing: 4) {
                                Text(session.hasMeasuredDistance ? String(format: "%.2f", session.distance) : "Not available")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.textColor)
                                Text(session.distanceUnit.uppercased())
                                    .font(.subheadline)
                                    .foregroundColor(AppTheme.textColor.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.top, 8)
                        
                        // Details Tile
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.headline)
                        Text("Date: \(session.date.formatted())")
                        if hasActual {
                            Text("Calories: \(String(format: "%.0f", session.calories ?? 0)) kcal")
                        } else {
                            Text("Calories (est.): \(String(format: "%.0f", estimatedCalories()) ) kcal")
                            Text("Estimated calories are based on speed and your latest weight. Actual burn varies.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryTextColor)
                        }
                        if let source = session.healthMetricSourceName,
                           !source.isEmpty {
                            Label("Heart-rate data from \(source)", systemImage: "heart.text.square.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.accentColor)
                        }
                        if let notes = session.notes { Text("Notes: \(notes)") }

                    }
                    .floatingTile()

                    // Route Tile (unconditional, with empty state)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Route")
                            .font(.headline)
                        if isPreparingRoute {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                        } else if !coordinates.isEmpty {
                            if showMap {
                                Map(position: $camera) {
                                    ForEach(cachedSegments) { seg in
                                        MapPolyline(coordinates: seg.points, contourStyle: .geodesic)
                                            .stroke(seg.color, lineWidth: 4)
                                    }
                                    if let start = coordinates.first {
                                        Annotation("Start", coordinate: start) { Circle().fill(Color.green).frame(width: 10, height: 10) }
                                    }
                                    if let end = coordinates.last {
                                        Annotation("End", coordinate: end) { Circle().fill(Color.red).frame(width: 10, height: 10) }
                                    }
                                }
                                .frame(height: 260)
                                .overlay(alignment: .bottomLeading) {
                                    // Pace color legend
                                    HStack(spacing: 8) {
                                        paceLegendItem(color: .blue, label: "Walk")
                                        paceLegendItem(color: .orange, label: "Jog")
                                        paceLegendItem(color: .red, label: "Run")
                                    }
                                    .font(.caption2)
                                    .padding(8)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .padding(8)
                                }
                                .onAppear {
                                    zoomToRoute()
                                    logFirstMapRenderIfNeeded()
                                }
                            } else {
                                ProgressView().frame(height: 260)
                            }
                        } else {
                            ContentUnavailableView("No Route Recorded", systemImage: "map", description: Text("This run doesn't include route data."))
                                .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                    .floatingTile()
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, AppTheme.padding)
                }
            } else {
                // Stats Tab
                RunStatsView(
                    session: session,
                    coordinates: coordinates,
                    fullCoordinates: fullCoordinates,
                    heartRateSamples: heartRateSamples,
                    isLoadingHeartRate: isLoadingHeartRate
                )
            }
        }
        .transition(.opacity)
        }
        .appBackground(AppTheme.gradientRuns)
        .foregroundColor(AppTheme.textColor)
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .onAppear {
            detailAppearStart = Date()
            hasLoggedFirstMapRender = false
            refreshDecodedRouteCaches()
            DispatchQueue.main.async { showMap = true }
            // If we have a Health UUID but no stored route yet, fetch on-demand
            if (session.locations.isEmpty), let uuid = session.healthWorkoutUUID, !uuid.isEmpty {
                Task { @MainActor in
                    if let locs = try? await HealthKitManager.shared.routeLocationsForUUID(uuid), !locs.isEmpty {
                        let reduced = downsampleLocations(locs)
                        let coords = reduced.map { RunCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                        if let data = try? JSONEncoder().encode(coords) {
                            session.locations = data
                            _ = PersistenceSave.commit(modelContext, action: "cache run route from Health")
                            refreshDecodedRouteCaches()
                        }
                    }
                }
            }
            
            // Fetch heart rate samples if this is from HealthKit
            if let uuid = session.preferredMetricWorkoutUUID,
               !uuid.isEmpty,
               heartRateSamples.isEmpty {
                isLoadingHeartRate = true
                Task { @MainActor in
                    do {
                        // Get the HKWorkout from the UUID
                        if let workout = try await HealthKitManager.shared.workoutForUUID(uuid) {
                            let samples = try await HealthKitManager.shared.heartRateSamples(for: workout)
                            heartRateSamples = samples
                        }
                    } catch {
                        print("Failed to fetch heart rate samples: \(error)")
                    }
                    isLoadingHeartRate = false
                }
            }
        }
        .onChange(of: session.locations) { _, _ in
            refreshDecodedRouteCaches()
        }
        .onDisappear {
            routePreparationTask?.cancel()
        }
    }

    // Reduce number of points to speed map rendering/storage. Keep up to ~1200 points and at least 5 m apart
    private func downsampleLocations(_ locs: [CLLocation], maxPoints: Int = 1200, minDistance: Double = 5.0) -> [CLLocation] {
        if locs.count <= maxPoints { return locs }
        var reduced: [CLLocation] = []
        var last: CLLocation? = nil
        for l in locs {
            if let last, l.distance(from: last) < minDistance { continue }
            reduced.append(l)
            last = l
            if reduced.count >= maxPoints { break }
        }
        return reduced
    }

    /// Decodes and simplifies the stored route on a background task, then applies
    /// the result on the main actor. Model access happens up front so the
    /// SwiftData object never crosses actors; a newer request cancels any
    /// in-flight one so a stale route cannot overwrite a fresh one.
    private func refreshDecodedRouteCaches() {
        routePreparationTask?.cancel()

        let locations = session.locations
        let duration = session.duration
        guard !locations.isEmpty else {
            decodedCoordinates = []
            cachedSegments = []
            isPreparingRoute = false
            return
        }

        isPreparingRoute = true
        let startedAt = Date()
        routePreparationTask = Task { @MainActor in
            let prepared = await Task.detached(priority: .userInitiated) {
                RouteRenderPreparation.make(from: locations, duration: duration)
            }.value
            guard !Task.isCancelled else { return }

            decodedCoordinates = prepared.decoded
            cachedSegments = prepared.segments.map { Segment(points: $0.points, color: Self.color(for: $0.pace)) }
            isPreparingRoute = false

            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("\(routeDecodePrefix) decode/cache prep: \(elapsedMs)ms (\(prepared.decoded.count) route pts -> \(prepared.simplified.count) map pts)")
        }
    }

    private func logFirstMapRenderIfNeeded() {
        guard !hasLoggedFirstMapRender else { return }
        hasLoggedFirstMapRender = true
        if let detailAppearStart {
            let elapsedMs = Int(Date().timeIntervalSince(detailAppearStart) * 1000)
            print("\(routeDecodePrefix) first map render: \(elapsedMs)ms")
        }
    }
    
    private func zoomToRoute() {
        guard !coordinates.isEmpty else { return }
        var minLat = coordinates.first!.latitude
        var maxLat = minLat
        var minLon = coordinates.first!.longitude
        var maxLon = minLon
        for c in coordinates.dropFirst() {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        let span = MKCoordinateSpan(latitudeDelta: max(0.002, (maxLat - minLat) * 1.4),
                                     longitudeDelta: max(0.002, (maxLon - minLon) * 1.4))
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2.0,
                                            longitude: (minLon + maxLon) / 2.0)
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    @ViewBuilder
    private func paceLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(AppTheme.secondaryTextColor)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        else { return String(format: "%02d:%02d", minutes, seconds) }
    }

    // MARK: - Calories estimate (detail view helpers)
    private func latestWeightKgDetail() -> Double? {
        var fd = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 1
        if let entry = try? modelContext.fetch(fd).first {
            return entry.weightUnit == "kg" ? entry.weight : (entry.weight / 2.20462)
        }
        return nil
    }

    private func estimatedCalories() -> Double {
        let hours = max(session.duration / 3600.0, 0.0001)
        let miles = (session.distanceUnit == "mi") ? session.distance : session.distance / 1.60934
        let mph = miles / hours
        let met: Double = {
            switch mph {
            case ..<2.5: return 2.5
            case 2.5..<3.0: return 3.3
            case 3.0..<3.5: return 3.8
            case 3.5..<4.0: return 4.3
            case 4.0..<5.0: return 5.0
            case 5.0..<5.5: return 8.3
            case 5.5..<6.0: return 9.0
            case 6.0..<7.0: return 9.8
            case 7.0..<8.0: return 11.0
            case 8.0..<9.0: return 11.8
            case 9.0..<10.0: return 12.8
            default: return 14.5
            }
        }()
        let kg = latestWeightKgDetail() ?? 70.0
        let minutes = session.duration / 60.0
        return max(met * 3.5 * kg / 200.0 * minutes, 0)
    }
}

// MARK: - Run Stats View
struct RunStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"
    let session: RunningSession
    let coordinates: [CLLocationCoordinate2D]
    let fullCoordinates: [RunCoordinate]
    let heartRateSamples: [(timestamp: Date, bpm: Double)]
    let isLoadingHeartRate: Bool
    
    @State private var loadError: String? = nil
    
    private var usesImperial: Bool { measurementSystem == "imperial" }
    
    // Calculate splits per mile/km based on actual GPS data
    // Returns: (distance in units, display text, elevation in meters above sea level)
    private var splits: [(distance: Double, pace: String, elevation: Double?)] {
        // Validate basic session data first
        guard session.distance > 0,
              session.duration > 0,
              !session.distance.isNaN,
              !session.duration.isNaN,
              session.distance.isFinite,
              session.duration.isFinite else {
            print("⚠️ Invalid session data - distance: \(session.distance), duration: \(session.duration)")
            return []
        }
        
        // For very short runs (< 30 seconds), just use fallback
        guard session.duration >= 30 else {
            print("⏱️ Run too short (<30s), using fallback splits")
            return fallbackSplits()
        }
        
        // Check if we have location data
        guard !fullCoordinates.isEmpty else {
            print("📍 No location data, using fallback splits")
            return fallbackSplits()
        }
        print("✅ Decoded \(fullCoordinates.count) coordinates for \(session.distance) \(session.distanceUnit)")
        
        // Calculate splits from actual route with timestamps
        return calculateSplitsFromRoute(fullCoordinates)
    }
    
    // Fallback to average pace if no GPS data available
    private func fallbackSplits() -> [(distance: Double, pace: String, elevation: Double?)] {
        let totalUnits = Int(session.distance)
        guard totalUnits > 0, session.distance > 0, session.duration > 0 else { return [] }
        
        let timePerUnit = session.duration / session.distance
        var result: [(Double, String, Double?)] = []
        
        for i in 1...totalUnits {
            let splitTime = timePerUnit
            let pace = formatPaceTime(splitTime)
            result.append((Double(i), pace, nil))
        }
        
        return result
    }
    
    // Calculate splits from route coordinates with timestamps
    private func calculateSplitsFromRoute(_ coords: [RunCoordinate]) -> [(distance: Double, pace: String, elevation: Double?)] {
        guard coords.count >= 2,
              session.distance > 0,
              session.duration > 0 else {
            print("⚠️ Not enough coords or invalid session data")
            return fallbackSplits() 
        }
        
        let metersPerUnit = session.distanceUnit == "mi" ? 1609.34 : 1000.0
        let completeUnits = Int(session.distance) // Number of complete miles/km
        
        // Validate we have at least one complete unit to display
        guard completeUnits > 0 else {
            print("⚠️ No complete units to display")
            return fallbackSplits()
        }
        
        let hasPartial = session.distance - Double(completeUnits) >= 0.05 // Show if at least 0.05 units remain
        
        var result: [(Double, String, Double?)] = []
        
        // Check if we have valid timestamps
        guard let firstTimestamp = coords.first?.timestamp,
              let lastTimestamp = coords.last?.timestamp,
              lastTimestamp > firstTimestamp else {
            print("⚠️ Missing or invalid timestamps, using fallback")
            return fallbackSplits()
        }
        
        print("✅ Valid timestamps found, calculating splits for \(completeUnits) complete units")
        
        // Build cumulative distance array
        var cumulativeDistances: [(coord: RunCoordinate, distance: Double)] = [(coords[0], 0.0)]
        var totalDistance = 0.0
        
        for i in 1..<coords.count {
            let prevCoord = coords[i-1]
            let currCoord = coords[i]
            
            // Validate coordinates
            guard prevCoord.latitude.isFinite, prevCoord.longitude.isFinite,
                  currCoord.latitude.isFinite, currCoord.longitude.isFinite,
                  abs(prevCoord.latitude) <= 90, abs(prevCoord.longitude) <= 180,
                  abs(currCoord.latitude) <= 90, abs(currCoord.longitude) <= 180 else {
                print("⚠️ Invalid coordinates at index \(i), skipping")
                continue
            }
            
            let prev = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
            let curr = CLLocation(latitude: currCoord.latitude, longitude: currCoord.longitude)
            let segmentDistance = curr.distance(from: prev)
            
            // Validate segment distance is reasonable
            guard segmentDistance.isFinite, segmentDistance >= 0, segmentDistance < 10000 else {
                print("⚠️ Invalid segment distance: \(segmentDistance)m, skipping")
                continue
            }
            
            totalDistance += segmentDistance
            cumulativeDistances.append((currCoord, totalDistance))
        }
        
        // Make sure we have enough data points
        guard cumulativeDistances.count >= 2 else {
            print("⚠️ Not enough valid coordinates after filtering")
            return fallbackSplits()
        }
        
        // Find split points at each COMPLETE mile/km marker
        var lastSplitTime: Date? = firstTimestamp
        var lastSplitDistance = 0.0
        
        for splitNum in 1...completeUnits {
            let targetDistance = Double(splitNum) * metersPerUnit
            
            // Find the first point that reaches or exceeds this distance marker
            guard let splitIndex = cumulativeDistances.firstIndex(where: { $0.distance >= targetDistance }) else {
                // If we can't find this split point, use average pace
                let timePerUnit = session.duration / session.distance
                result.append((Double(splitNum), formatPaceTime(timePerUnit), nil))
                continue
            }
            
            let splitCoord = cumulativeDistances[splitIndex].coord
            let splitDistance = cumulativeDistances[splitIndex].distance
            
            // Calculate time for this split using timestamps
            if let splitTime = splitCoord.timestamp, let lastTime = lastSplitTime, splitTime > lastTime {
                let splitDuration = splitTime.timeIntervalSince(lastTime)
                let splitDistanceMeters = splitDistance - lastSplitDistance
                let splitDistanceUnits = splitDistanceMeters / metersPerUnit
                
                // Validate the split data
                guard splitDuration > 0, 
                      splitDuration < session.duration * 2, // Sanity check
                      splitDistanceUnits > 0,
                      splitDistanceUnits < 2, // Should be close to 1 mile/km
                      splitDuration.isFinite,
                      splitDistanceUnits.isFinite else {
                    print("⚠️ Invalid split \(splitNum): duration=\(splitDuration)s, distance=\(splitDistanceUnits)u")
                    // Use average for this split
                    let timePerUnit = session.duration / session.distance
                    result.append((Double(splitNum), formatPaceTime(timePerUnit), splitCoord.altitude))
                    continue
                }
                
                // Calculate pace per unit for this split
                let pacePerUnit = splitDuration / splitDistanceUnits
                result.append((Double(splitNum), formatPaceTime(pacePerUnit), splitCoord.altitude))
                
                lastSplitTime = splitTime
                lastSplitDistance = splitDistance
            } else {
                // No timestamp data for this point, use average
                let timePerUnit = session.duration / session.distance
                result.append((Double(splitNum), formatPaceTime(timePerUnit), nil))
            }
        }
        
        // Add partial mile/km at the end if it exists
        if hasPartial, let lastTime = lastSplitTime, let endTime = coords.last?.timestamp, endTime > lastTime {
            let partialDuration = endTime.timeIntervalSince(lastTime)
            guard partialDuration > 0 && partialDuration < session.duration else {
                // Invalid partial duration, skip it
                return result.isEmpty ? fallbackSplits() : result
            }
            let partialTimeStr = formatSplitDuration(partialDuration) // Show actual time, not pace
            
            // Distance marker for partial (e.g., 11.13 for the partial after mile 11)
            result.append((session.distance, partialTimeStr, coords.last?.altitude))
        }
        
        // If we didn't get any valid splits, fall back to average
        return result.isEmpty ? fallbackSplits() : result
    }
    
    private func formatPaceTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatSplitDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        else { return String(format: "%d:%02d", minutes, seconds) }
    }

    private func formatElevation(_ meters: Double) -> String {
        if usesImperial {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }

    private var strideUnitLabel: String {
        usesImperial ? "ft" : "m"
    }

    private func formatStrideValue(_ meters: Double) -> String {
        if usesImperial {
            return String(format: "%.2f", meters * 3.28084)
        }
        return String(format: "%.2f", meters)
    }

    private var verticalOscillationUnitLabel: String {
        usesImperial ? "in" : "cm"
    }

    private func formatVerticalOscillationValue(_ centimeters: Double) -> String {
        if usesImperial {
            return String(format: "%.2f", centimeters / 2.54)
        }
        return String(format: "%.1f", centimeters)
    }
    
    // Average pace
    private var averagePace: String {
        guard session.hasMeasuredDistance, session.distance > 0 else { return "N/A" }
        let timePerUnit = session.duration / session.distance
        return formatPaceTime(timePerUnit)
    }
    
    // Average speed
    private var averageSpeed: String {
        guard session.duration > 0 else { return "N/A" }
        let speedMPS = (session.distance * (session.distanceUnit == "mi" ? 1609.34 : 1000)) / session.duration
        let speedMPH = speedMPS * 2.23694 // Convert m/s to mph
        return String(format: "%.1f mph", speedMPH)
    }
    
    // Calories per mile/km
    private var caloriesPerUnit: String {
        guard session.hasMeasuredDistance, session.distance > 0 else { return "N/A" }
        let calories = session.calories ?? estimatedCalories()
        let perUnit = calories / session.distance
        return String(format: "%.0f kcal/%@", perUnit, session.distanceUnit)
    }
    
    // Estimated elevation (placeholder - can be enhanced with actual altitude data)
    private var totalElevation: String {
        // TODO: Calculate from altitude in coordinates if available
        return "N/A"
    }
    
    // Get latest weight for calorie calculation
    private func latestWeightKg() -> Double? {
        var fd = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 1
        if let entry = try? modelContext.fetch(fd).first {
            return entry.weightUnit == "kg" ? entry.weight : (entry.weight / 2.20462)
        }
        return nil
    }
    
    private func estimatedCalories() -> Double {
        let hours = max(session.duration / 3600.0, 0.0001)
        let miles = (session.distanceUnit == "mi") ? session.distance : session.distance / 1.60934
        let mph = miles / hours
        let met: Double = {
            switch mph {
            case ..<2.5: return 2.5
            case 2.5..<3.0: return 3.3
            case 3.0..<3.5: return 3.8
            case 3.5..<4.0: return 4.3
            case 4.0..<5.0: return 5.0
            case 5.0..<5.5: return 8.3
            case 5.5..<6.0: return 9.0
            case 6.0..<6.5: return 9.8
            case 6.5..<7.0: return 10.5
            case 7.0..<7.5: return 11.0
            case 7.5..<8.0: return 11.5
            case 8.0..<9.0: return 11.8
            case 9.0..<10.0: return 12.3
            case 10.0..<11.0: return 12.8
            default: return 14.5
            }
        }()
        let kg = latestWeightKg() ?? 70.0
        let minutes = session.duration / 60.0
        return max(met * 3.5 * kg / 200.0 * minutes, 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Timing & Distance Summary
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(AppTheme.accentColor)
                        Text("Time & Distance")
                            .font(.headline)
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 150)),
                        GridItem(.flexible(minimum: 150))
                    ], spacing: 12) {
                        StatCard(title: "Duration", value: formatDuration(session.duration), subtitle: "")
                        StatCard(title: "Distance", value: String(format: "%.2f", session.distance), subtitle: session.distanceUnit)
                        StatCard(title: "Activity", value: session.activityType.capitalized, subtitle: "")
                        StatCard(title: "Date", value: session.date.formatted(date: .abbreviated, time: .omitted), subtitle: "")
                    }
                }
                .floatingTile()
                .padding(.top, 8)
                
                // Performance Metrics
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .foregroundStyle(AppTheme.accentColor)
                        Text("Performance")
                            .font(.headline)
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(minimum: 150)),
                        GridItem(.flexible(minimum: 150))
                    ], spacing: 12) {
                        StatCard(title: "Avg Pace", value: averagePace, subtitle: "per \(session.distanceUnit)")
                        StatCard(title: "Avg Speed", value: averageSpeed, subtitle: "")
                        StatCard(title: "Calories/Unit", value: caloriesPerUnit, subtitle: "")
                        StatCard(title: "Total Calories", value: String(format: "%.0f kcal", session.calories ?? estimatedCalories()), subtitle: "")
                    }
                }
                .floatingTile()
                
                // Power (for running power meters) - only show if data exists
                if session.avgPower != nil || session.maxPower != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.yellow)
                            Text("Power")
                                .font(.headline)
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(minimum: 150)),
                            GridItem(.flexible(minimum: 150))
                        ], spacing: 12) {
                            StatCard(title: "Avg Power", 
                                   value: session.avgPower.map { String(format: "%.0f", $0) } ?? "N/A", 
                                   subtitle: "W")
                            StatCard(title: "Max Power", 
                                   value: session.maxPower.map { String(format: "%.0f", $0) } ?? "N/A", 
                                   subtitle: "W")
                        }
                        
                        Text("Power data from compatible meters (Stryd, Garmin, etc.)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .padding(.top, 4)
                    }
                    .floatingTile()
                }
                
                // Heart Rate - only show if data exists
                if session.avgHeartRate != nil || session.maxHeartRate != nil || session.minHeartRate != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Heart Rate")
                                .font(.headline)
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(minimum: 150)),
                            GridItem(.flexible(minimum: 150))
                        ], spacing: 12) {
                            StatCard(title: "Avg HR", 
                                   value: session.avgHeartRate.map { String(format: "%.0f", $0) } ?? "N/A", 
                                   subtitle: "bpm")
                            StatCard(title: "Max HR", 
                                   value: session.maxHeartRate.map { String(format: "%.0f", $0) } ?? "N/A", 
                                   subtitle: "bpm")
                            StatCard(title: "Min HR", 
                                   value: session.minHeartRate.map { String(format: "%.0f", $0) } ?? "N/A", 
                                   subtitle: "bpm")
                            StatCard(title: "HR Range", 
                                   value: session.maxHeartRate != nil && session.minHeartRate != nil ? 
                                   String(format: "%.0f", session.maxHeartRate! - session.minHeartRate!) : "N/A", 
                                   subtitle: "bpm")
                        }
                        
                        Text("Heart rate from Apple Watch or compatible chest strap")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .padding(.top, 4)
                    }
                    .floatingTile()
                }
                
                // Elevation - only show if meaningful data exists (not just zeros)
                if (session.totalAscent ?? 0) > 0 || (session.totalDescent ?? 0) > 0 || 
                   (session.minElevation ?? 0) != 0 || (session.maxElevation ?? 0) != 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "mountain.2.fill")
                                .foregroundStyle(AppTheme.accentColor)
                            Text("Elevation")
                                .font(.headline)
                        }
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible(minimum: 150)),
                            GridItem(.flexible(minimum: 150))
                        ], spacing: 12) {
                            StatCard(title: "Total Ascent", 
                                   value: session.totalAscent.map { formatElevation($0) } ?? "N/A", 
                                   subtitle: "")
                            StatCard(title: "Total Descent", 
                                   value: session.totalDescent.map { formatElevation($0) } ?? "N/A", 
                                   subtitle: "")
                            StatCard(title: "Min Elevation", 
                                   value: session.minElevation.map { formatElevation($0) } ?? "N/A", 
                                   subtitle: "")
                            StatCard(title: "Max Elevation", 
                                   value: session.maxElevation.map { formatElevation($0) } ?? "N/A", 
                                   subtitle: "")
                        }
                        
                        Text("Elevation calculated from GPS altitude data (requires physical device with GPS)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .padding(.top, 4)
                    }
                    .floatingTile()
                }
                
                // Running Dynamics - only show if data exists
                if session.avgCadence != nil || session.avgStrideLength != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.run")
                                .foregroundStyle(AppTheme.accentColor)
                            Text("Running Dynamics")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            if let avgCadence = session.avgCadence {
                                DynamicRow(label: "Avg Cadence", value: String(format: "%.0f", avgCadence), unit: "spm")
                                Divider().opacity(0.2)
                            }
                            if let maxCadence = session.maxCadence {
                                DynamicRow(label: "Max Cadence", value: String(format: "%.0f", maxCadence), unit: "spm")
                                Divider().opacity(0.2)
                            }
                            if let avgStride = session.avgStrideLength {
                                DynamicRow(label: "Avg Stride Length", value: formatStrideValue(avgStride), unit: strideUnitLabel)
                                Divider().opacity(0.2)
                            }
                            if let vertOsc = session.verticalOscillation {
                                DynamicRow(label: "Vertical Oscillation", value: formatVerticalOscillationValue(vertOsc), unit: verticalOscillationUnitLabel)
                                Divider().opacity(0.2)
                            }
                            if let gct = session.groundContactTime {
                                DynamicRow(label: "Ground Contact Time", value: String(format: "%.0f", gct), unit: "ms")
                            }
                        }
                        
                        Text("Running dynamics from Apple Watch Series 6+ or compatible devices")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .padding(.top, 4)
                    }
                    .floatingTile()
                }
                
                // Elevation Chart
                if !fullCoordinates.isEmpty, fullCoordinates.contains(where: { $0.altitude != nil && $0.timestamp != nil }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "mountain.2.fill")
                                .foregroundStyle(.green)
                            Text("Elevation Profile")
                                .font(.headline)
                        }
                        
                        Chart {
                            ForEach(fullCoordinates.filter { $0.altitude != nil && $0.timestamp != nil }) { coord in
                                LineMark(
                                    x: .value("Time", coord.timestamp!),
                                    y: .value("Elevation", coord.altitude!)
                                )
                                .foregroundStyle(.green.gradient)
                                .interpolationMethod(.catmullRom)
                            }
                            
                            AreaMark(
                                x: .value("Time", fullCoordinates.first(where: { $0.timestamp != nil })?.timestamp ?? Date()),
                                yStart: .value("Min", fullCoordinates.compactMap { $0.altitude }.min() ?? 0),
                                yEnd: .value("Max", fullCoordinates.compactMap { $0.altitude }.max() ?? 0)
                            )
                            .foregroundStyle(.green.opacity(0.1))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let elevation = value.as(Double.self) {
                                        Text("\(Int(elevation))m")
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine()
                            }
                        }
                        .frame(height: 180)
                    }
                    .floatingTile()
                }
                
                // Heart Rate Chart
                if !heartRateSamples.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Heart Rate Profile")
                                .font(.headline)
                            Spacer()
                            if let avg = session.avgHeartRate {
                                Text("Avg: \(Int(avg)) bpm")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Chart {
                            ForEach(Array(heartRateSamples.enumerated()), id: \.offset) { _, sample in
                                LineMark(
                                    x: .value("Time", sample.timestamp),
                                    y: .value("BPM", sample.bpm)
                                )
                                .foregroundStyle(.red.gradient)
                                .interpolationMethod(.catmullRom)
                            }
                            
                            if let minBPM = heartRateSamples.map({ $0.bpm }).min(),
                               let maxBPM = heartRateSamples.map({ $0.bpm }).max() {
                                AreaMark(
                                    x: .value("Time", heartRateSamples.first?.timestamp ?? Date()),
                                    yStart: .value("Min", minBPM),
                                    yEnd: .value("Max", maxBPM)
                                )
                                .foregroundStyle(.red.opacity(0.1))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let bpm = value.as(Double.self) {
                                        Text("\(Int(bpm))")
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisGridLine()
                            }
                        }
                        .frame(height: 180)
                    }
                    .floatingTile()
                } else if isLoadingHeartRate {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("Heart Rate Profile")
                                .font(.headline)
                        }
                        ProgressView()
                            .frame(height: 180)
                    }
                    .floatingTile()
                }
                
                // Split Times
                if !splits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "list.number")
                                .foregroundStyle(AppTheme.accentColor)
                            Text("Splits")
                                .font(.headline)
                        }
                        
                        ForEach(Array(splits.enumerated()), id: \.offset) { index, split in
                            SplitRow(
                                distance: split.distance,
                                timeOrPace: split.pace,
                                elevation: split.elevation,
                                distanceUnit: session.distanceUnit,
                                isSlower: isSplitSlowerThanAverage(split.pace),
                                totalDistance: session.distance
                            )
                            
                            if index < splits.count - 1 {
                                Divider().opacity(0.2)
                            }
                        }
                    }
                    .floatingTile()
                    .padding(.bottom, 80) // Extra padding to avoid tab bar overlap
                }
            }
            .padding(.horizontal, AppTheme.padding)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        else { return String(format: "%02d:%02d", minutes, seconds) }
    }
    
    // Compare a split pace with the average pace
    private func isSplitSlowerThanAverage(_ paceString: String) -> Bool? {
        // Convert pace strings "MM:SS" to seconds
        let components = paceString.split(separator: ":")
        guard components.count == 2,
              let mins = Int(components[0]),
              let secs = Int(components[1]) else {
            return nil
        }
        let splitSeconds = Double(mins * 60 + secs)
        
        // Get average pace in seconds
        guard session.distance > 0 else { return nil }
        let avgPaceSeconds = session.duration / session.distance
        
        // Return true if split is slower (more seconds per unit)
        return splitSeconds > avgPaceSeconds
    }
}

// MARK: - Supporting Views
private struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            // Always show subtitle space to maintain consistent height
            Group {
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .foregroundStyle(.clear)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryBackgroundColor.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryTextColor)
        }
    }
}

private struct DynamicRow: View {
    let label: String
    let value: String
    let unit: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
        }
    }
}

private struct SplitRow: View {
    let distance: Double // Actual distance value (e.g., 1.0, 2.0, or 11.13)
    let timeOrPace: String // Either pace (MM:SS/unit) or actual time for partials
    let elevation: Double? // Altitude in meters above sea level
    let distanceUnit: String
    let isSlower: Bool?
    let totalDistance: Double
    
    // Check if this is a partial segment (last segment with fractional distance)
    private var isPartial: Bool {
        guard distance.isFinite, totalDistance.isFinite, distance > 0, totalDistance > 0 else {
            return false
        }
        let wholePart = floor(distance)
        let fractionalPart = distance - wholePart
        return fractionalPart >= 0.05 && distance >= totalDistance - 0.01
    }
    
    private var splitNumber: Int {
        guard distance.isFinite, distance > 0 else { return 0 }
        return Int(distance)
    }
    
    private var partialDistance: Double {
        guard distance.isFinite, distance > 0 else { return 0 }
        return distance - floor(distance)
    }
    
    var body: some View {
        // Validate data before rendering
        guard distance > 0, distance.isFinite, !timeOrPace.isEmpty else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
        HStack(alignment: .center, spacing: 12) {
            // Split number badge or partial indicator
            ZStack {
                Circle()
                    .fill(isPartial ? .orange.opacity(0.2) : AppTheme.accentColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                if isPartial {
                    Text("+")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(max(1, splitNumber))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if isPartial {
                    // Show partial distance (e.g., "0.13 mi")
                    Text(String(format: "%.2f %@", partialDistance, distanceUnit))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.orange)
                } else {
                    // Show full mile/km (e.g., "Mile 1")
                    Text("\(distanceUnit == "mi" ? "Mile" : "Km") \(splitNumber)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                if let elevation = elevation {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                        Text(String(format: "%.0f m", elevation))
                            .font(.caption)
                    }
                    .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
            
            Spacer()
            
            // Pace with indicator (or actual time for partials)
            HStack(spacing: 6) {
                if isPartial {
                    // Show actual time for partial segment
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timeOrPace)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text("time")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }
                } else {
                    // Show pace for full segments
                    Text(timeOrPace)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    // Indicator if faster or slower than average
                    if let isSlower = isSlower {
                        Image(systemName: isSlower ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(isSlower ? .red.opacity(0.7) : .green.opacity(0.7))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        )
    }
}
