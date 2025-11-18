import SwiftUI
import HealthKit
import SwiftData
import MapKit
import CoreLocation
import Charts

struct RunLogView: View {
    @AppStorage("distanceUnit") private var preferredDistanceUnit: String = "mi"
    // Helper type for chart points
    private struct DailyPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)]) private var runningSessions: [RunningSession] // Added sort
    
    @State private var isEditing: Bool = false
    @State private var locationCache: [UUID: String] = [:]
    @State private var pendingLocationTasks: Set<UUID> = [] // Track active location fetch tasks
    @State private var hasPrefetchedLocations = false // Prevent duplicate prefetching
    @State private var showRunTracking: Bool = false
    @State private var selectedActivityType: String = "running"
    @State private var stepsToday: Int? = nil
    @State private var requestedLocationAuthOnce = false
    private let healthStore = HKHealthStore()
    @State private var pendingDeleteIndex: Int? = nil
    @State private var showDeleteConfirm: Bool = false
    
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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Active Run banner
                    if RunTracker.shared.isRunning || (RunTracker.shared.duration > 0 && RunTracker.shared.startDate != nil) {
                        Button {
                            selectedActivityType = RunTracker.shared.activityType
                            showRunTracking = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: activityIcon(for: RunTracker.shared.activityType))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active \(activityName(for: RunTracker.shared.activityType)) In Progress")
                                        .font(.headline)
                                    let dur = RunTracker.shared.duration
                                    let distMeters = RunTracker.shared.distance
                                    let unit = RunTracker.shared.distanceUnit
                                    let dist = distMeters / (unit == "km" ? 1000 : 1609.34)
                                    Text(String(format: "%@  •  %.2f %@", formatDuration(dur), dist, unit))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(AppTheme.secondaryBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                                        
                    // Unified Runs tile (header + chart or placeholder)
                    let calendar = Calendar.current
                    // Apply activity filter first if set
                    let filteredSessions: [RunningSession] = runningSessions.filter { s in
                        if runActivityFilter == "All" { return true }
                        return s.activityType == keyForActivity(runActivityFilter)
                    }
                    let grouped: [Date: Double] = Dictionary(grouping: filteredSessions, by: { session in
                        calendar.startOfDay(for: session.date)
                    }).mapValues { sessions in
                        sessions.reduce(0) { $0 + $1.distance }
                    }
                    let dailyAll: [DailyPoint] = grouped.keys.sorted().map { day in
                        DailyPoint(date: day, value: grouped[day] ?? 0)
                    }
                    let daily = dailyAll.filter { $0.date >= last7DaysDomain.lowerBound && $0.date < last7DaysDomain.upperBound }

                    let minV: Double = daily.map { $0.value }.min() ?? 0
                    let maxV: Double = daily.map { $0.value }.max() ?? 0
                    let span: Double = max(1.0, maxV - minV)
                    let pad: Double = max(0.1, span * 0.15)
                    let yLower: Double = max(0, minV - pad)
                    let yUpper: Double = maxV + pad
                    let unitLabel = runningSessions.first?.distanceUnit ?? preferredDistanceUnit

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

                        if daily.isEmpty {
                            ContentUnavailableView(
                                "No Runs Logged",
                                systemImage: "figure.run",
                                description: Text("Tap the + button to track your first run.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 160)
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
                            .frame(height: 200)
                            .foregroundColor(AppTheme.textColor)
                        }
                    }
                    .floatingTile()

                    if !runningSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            LazyVStack(spacing: 16) {
                            ForEach(runningSessions) { session in
                                NavigationLink {
                                    RunSessionDetailView(session: session)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        // Activity type icon
                                        Image(systemName: activityIcon(for: session.activityType))
                                            .font(.title2)
                                            .foregroundStyle(AppTheme.accentColor)
                                            .frame(width: 32)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.headline)
                                            Text("\(String(format: "%.1f", session.distance)) \(session.distanceUnit) • \(String(format: "%.0f", caloriesFor(session))) kcal")
                                                .font(.subheadline)
                                            HStack(spacing: 4) {
                                                Text(formatDuration(session.duration))
                                                Text("•")
                                                Text(formatPace(distance: session.distance, duration: session.duration, unit: session.distanceUnit))
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            if let place = locationCache[session.id], !place.isEmpty {
                                                Text(place)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .foregroundColor(AppTheme.textColor)
                                        Spacer(minLength: 8)
                                        if isEditing {
                                            Button(role: .destructive) {
                                                if let idx = runningSessions.firstIndex(where: { $0.id == session.id }) {
                                                    pendingDeleteIndex = idx
                                                    showDeleteConfirm = true
                                                }
                                            } label: { Image(systemName: "trash") }
                                        }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    if session.id != runningSessions.last?.id {
                                        Divider().opacity(0.2)
                                    }
                                }
                                .onDelete(perform: deleteRunningSessions)
                            }
                        }
                        .floatingTile()
                        .onAppear {
                            prefetchLocationNames()
                        }
                        .onChange(of: runningSessions) {
                            hasPrefetchedLocations = false
                            prefetchLocationNames()
                        }
                    }

                    
                }
                .padding(.horizontal, AppTheme.padding)
            }
            .alert("Delete Run?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { pendingDeleteIndex = nil }
                Button("Delete on Device", role: .destructive) {
                    if let idx = pendingDeleteIndex { deleteRunningSessions(offsets: IndexSet(integer: idx)) }
                    pendingDeleteIndex = nil
                }
                Button("Delete on Device + Health", role: .destructive) {
                    Task { @MainActor in
                        if let idx = pendingDeleteIndex {
                            let s = runningSessions[idx]
                            // Kick off Health deletion before removing locally
                            let meters: Double = (s.distanceUnit == "mi") ? (s.distance * 1609.34) : (s.distance * 1000.0)
                            try? await HealthKitManager.shared.deleteRun(uuidString: s.healthWorkoutUUID, endDate: s.date, duration: s.duration, distanceMeters: meters)
                            deleteRunningSessions(offsets: IndexSet(integer: idx))
                        }
                        pendingDeleteIndex = nil
                    }
                }
            } message: {
                Text("Also remove this workout from the Health app?")
            }
            .appBackground(AppTheme.gradientRuns)
            .foregroundColor(AppTheme.textColor)
            .navigationTitle("Runs")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppTheme.accentColor)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            selectedActivityType = "running"
                            showRunTracking = true
                        } label: {
                            Label("Run", systemImage: "figure.run")
                        }
                        
                        Button {
                            selectedActivityType = "walking"
                            showRunTracking = true
                        } label: {
                            Label("Walk", systemImage: "figure.walk")
                        }
                        
                        Button {
                            selectedActivityType = "hiking"
                            showRunTracking = true
                        } label: {
                            Label("Hike", systemImage: "figure.hiking")
                        }
                        
                        Button {
                            selectedActivityType = "cycling"
                            showRunTracking = true
                        } label: {
                            Label("Cycle", systemImage: "bicycle")
                        }
                        
                        Button {
                            selectedActivityType = "rowing"
                            showRunTracking = true
                        } label: {
                            Label("Row", systemImage: "figure.rower")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityLabel("Track Activity")
                    }
                }

                
            }
            .onAppear {
                // Request location permission only when entering Runs for the first time
                if !requestedLocationAuthOnce {
                    requestedLocationAuthOnce = true
                    let manager = CLLocationManager()
                    if manager.authorizationStatus == .notDetermined {
                        manager.requestWhenInUseAuthorization()
                    }
                }
                // Load data (HealthKit should already be authorized from tutorial)
                fetchTodaySteps()
                importHealthRuns()
            }
            .sheet(isPresented: $showRunTracking) {
                NavigationStack {
                    RunTrackingProView(activityType: selectedActivityType)
                        .navigationTitle(activityTitle(for: selectedActivityType))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                }
                .id(selectedActivityType) // Force refresh when activity type changes
                .appBackground(AppTheme.gradientRuns)
                .foregroundColor(AppTheme.textColor)
                .tint(AppTheme.accentColor)
            }
        }
    }
    
    private func activityTitle(for type: String) -> String {
        switch type {
        case "walking":
            return "Tracking Walk"
        case "hiking":
            return "Tracking Hike"
        default:
            return "Tracking Run"
        }
    }
    
    private func activityFilterOptions() -> [String] {
        ["Running", "Walking", "Hiking", "Cycling", "Rowing", "Elliptical", "Stair Climbing"]
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
    
    private func deleteRunningSessions(offsets: IndexSet) {
         withAnimation { // Added animation
            offsets.map { runningSessions[$0] }.forEach(modelContext.delete)
            try? modelContext.save() // Save after deleting
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
    private func importHealthRuns(limit: Int = 30) {
        Task { @MainActor in
            do {
                // Try to fetch recent workouts (will no-op if not authorized)
                let workouts = try await HealthKitManager.shared.fetchRecentRuns(limit: limit)
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
                    let meters = w.totalDistance?.doubleValue(for: .meter()) ?? 0
                    let unit = preferredDistanceUnit // from @AppStorage
                    let value: Double = (unit == "mi") ? (meters / 1609.34) : (meters / 1000.0)
                    let uuidStr = w.uuid.uuidString
                    // If we already have this workout, skip import
                    var fd = FetchDescriptor<RunningSession>(predicate: #Predicate { $0.healthWorkoutUUID == uuidStr })
                    fd.fetchLimit = 1
                    if let existing = try? modelContext.fetch(fd), existing.isEmpty == false {
                        continue
                    }
                    // Attempt to match a similar local run (e.g., tracked via phone) and attach the UUID
                    if let similar = findSimilarRun(endDate: end, duration: duration, distance: value, unit: unit) {
                        similar.healthWorkoutUUID = uuidStr
                        similar.activityType = activityType
                        if let kcal = try? await HealthKitManager.shared.activeEnergyKilocalories(for: w), kcal > 0 {
                            similar.calories = kcal
                        }
                        // Optionally attach route to similar item
                        if similar.locations.isEmpty, let locs = try? await HealthKitManager.shared.routeLocations(for: w), !locs.isEmpty {
                            let reduced = downsampleLocations(locs)
                            let coords = reduced.map { RunCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                            similar.locations = (try? JSONEncoder().encode(coords)) ?? Data()
                        }
                    } else {
                        // Create new item
                        var routeData: Data? = nil
                        let kcal = try? await HealthKitManager.shared.activeEnergyKilocalories(for: w)
                        if let locs = try? await HealthKitManager.shared.routeLocations(for: w), !locs.isEmpty {
                            let reduced = downsampleLocations(locs)
                            let coords = reduced.map { RunCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                            routeData = try? JSONEncoder().encode(coords)
                        }
                        let model = RunningSession(date: end, distance: value, distanceUnit: unit, duration: duration, calories: (kcal ?? 0) > 0 ? kcal : nil, notes: nil, locations: routeData, healthWorkoutUUID: uuidStr, activityType: activityType)
                        modelContext.insert(model)
                    }
                }
                try? modelContext.save()
            } catch {
                // Ignore errors silently; user may not have granted permission yet
            }
        }
    }

    private func findSimilarRun(endDate: Date, duration: TimeInterval, distance: Double, unit: String) -> RunningSession? {
        // Consider a run similar if end dates within 2 minutes and distance within ~0.07 units
        let window: TimeInterval = 120
        let tol: Double = 0.07
        let all: [RunningSession] = (try? modelContext.fetch(FetchDescriptor<RunningSession>())) ?? []
        return all.first { abs($0.date.timeIntervalSince(endDate)) < window && $0.distanceUnit == unit && abs($0.distance - distance) < tol }
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
    
    private func prefetchLocationNames() {
        // Prevent duplicate prefetching on the same set of sessions
        guard !hasPrefetchedLocations || runningSessions.count != locationCache.count else { return }

        // Only prefetch for sessions that don't already have cached names and aren't currently being fetched
        let sessionsToFetch = runningSessions.filter { session in
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

private struct RunCoordinate: Codable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

struct RunSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let session: RunningSession

    private var hasActual: Bool { (session.calories ?? 0) > 0 }

    // Decode stored coordinates
    private var coordinates: [CLLocationCoordinate2D] {
        guard !session.locations.isEmpty,
              let decoded = try? JSONDecoder().decode([RunCoordinate].self, from: session.locations) else { return [] }
        return decoded.map { $0.cl }
    }

    // Build map region around the route
    @State private var camera: MapCameraPosition = .automatic

    // Speed thresholds (m/s)
    private let walkMax: Double = 1.5   // ~3.4 mph
    private let jogMax: Double = 3.0    // ~6.7 mph; above this is running

    // Segment representation
    private struct Segment: Identifiable {
        let id = UUID()
        let points: [CLLocationCoordinate2D]
        let color: Color
    }
    
    @State private var cachedSegments: [Segment] = []
    @State private var showMap: Bool = false

    private var segments: [Segment] {
        guard coordinates.count > 1 else { return [] }
        // Approximate time between points using session duration evenly (fallback)
        let total = Double(coordinates.count - 1)
        let avgDt = max(session.duration / max(total, 1), 1)
        var segs: [Segment] = []
        var currentColor: Color? = nil
        var currentPoints: [CLLocationCoordinate2D] = []

        func colorForSpeed(_ v: Double) -> Color {
            if v <= walkMax { return .blue }
            if v <= jogMax { return .orange }
            return .red
        }

        for i in 0..<(coordinates.count - 1) {
            let a = coordinates[i]
            let b = coordinates[i+1]
            let da = MKMapPoint(a).distance(to: MKMapPoint(b)) // meters
            let v = da / max(avgDt, 1) // m/s
            let c = colorForSpeed(v)
            if currentColor == nil {
                currentColor = c
                currentPoints = [a, b]
            } else if c == currentColor {
                currentPoints.append(b)
            } else {
                if currentPoints.count >= 2, let cc = currentColor {
                    segs.append(Segment(points: currentPoints, color: cc))
                }
                currentColor = c
                currentPoints = [a, b]
            }
        }
        if currentPoints.count >= 2, let cc = currentColor {
            segs.append(Segment(points: currentPoints, color: cc))
        }
        return segs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Details Tile
                VStack(alignment: .leading, spacing: 8) {
                    Text("Details")
                        .font(.headline)
                    Text("Date: \(session.date.formatted())")
                    Text("Distance: \(String(format: "%.1f", session.distance)) \(session.distanceUnit)")
                    Text("Duration: \(formatDuration(session.duration))")
                    if hasActual {
                        Text("Calories: \(String(format: "%.0f", session.calories ?? 0)) kcal")
                    } else {
                        Text("Calories (est.): \(String(format: "%.0f", estimatedCalories()) ) kcal")
                        Text("Estimated calories are based on speed and your latest weight. Actual burn varies.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = session.notes { Text("Notes: \(notes)") }
                }
                .floatingTile()

                // Route Tile (unconditional, with empty state)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Route")
                        .font(.headline)
                    if !coordinates.isEmpty {
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
                            .onAppear { zoomToRoute() }
                        } else {
                            ProgressView().frame(height: 260)
                        }
                    } else {
                        ContentUnavailableView("No Route Recorded", systemImage: "map", description: Text("This run doesn’t include route data."))
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .floatingTile()
            }
            .padding(.horizontal, AppTheme.padding)
        }
        .appBackground(AppTheme.gradientRuns)
        .foregroundColor(AppTheme.textColor)
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .onAppear {
            if cachedSegments.isEmpty { cachedSegments = segments }
            DispatchQueue.main.async { showMap = true }
            // If we have a Health UUID but no stored route yet, fetch on-demand
            if (session.locations.isEmpty), let uuid = session.healthWorkoutUUID, !uuid.isEmpty {
                Task { @MainActor in
                    if let locs = try? await HealthKitManager.shared.routeLocationsForUUID(uuid), !locs.isEmpty {
                        let reduced = downsampleLocations(locs)
                        let coords = reduced.map { RunCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                        if let data = try? JSONEncoder().encode(coords) {
                            session.locations = data
                            try? modelContext.save()
                            cachedSegments = segments
                        }
                    }
                }
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
