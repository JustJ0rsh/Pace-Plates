import SwiftUI
import CoreLocation
import MapKit
import SwiftData

// Simple Codable wrapper for CLLocationCoordinate2D with altitude and timestamp
struct Coordinate: Codable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var altitude: Double? = nil // meters above sea level
    var timestamp: Date? = nil // When this coordinate was recorded

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case altitude
        case timestamp
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// Observable class to manage location updates and run state
@Observable
class RunTracker: NSObject, CLLocationManagerDelegate {
    static let shared = RunTracker()
    
    private let manager = CLLocationManager()
    var authorizationStatus: CLAuthorizationStatus
    
    var location: CLLocation? // Last known location
    var route: [CLLocation] = [] // Array to store route points
    var distance: Double = 0.0 // Meters
    var duration: TimeInterval = 0.0
    var startDate: Date? = nil
    private var pausedAt: Date? = nil
    private var pausedDuration: TimeInterval = 0.0
    private var shouldSkipNextDistanceSample = false
    // UI refresh timer; duration is computed from dates
    var timer: Timer? = nil
    var isRunning: Bool = false
    var pendingStartAfterAuth: Bool = false
    
    // Activity type: "running", "walking", or "hiking"
    var activityType: String = "running"
    
    // Throttle for map follow updates
    var lastFollowUpdate: Date? = nil

    // Smoothed pace support (rolling window of recent samples)
    var recentSamples: [(time: Date, distanceMeters: Double)] = []
    var smoothedPaceSecondsPerUnit: Double? = nil // seconds per km or per mile based on distanceUnit
    private let smoothingWindowSeconds: TimeInterval = 20
    private let smoothingMinDistance: Double = 25 // meters
    private var lastLiveActivityUpdateAt: Date? = nil
    private var lastLiveActivityDistanceMeters: Double = 0
    private var lastLiveActivityPace: Double? = nil
    private let liveActivityMinUpdateInterval: TimeInterval = 1
    private let liveActivityDistanceDeltaMeters: Double = 20
    private let liveActivityPaceDeltaSeconds: Double = 8
    private let routeAccuracyThresholdMeters: Double = 65
    private let routeMinDistanceMeters: Double = 8
    private let routeMinTimeInterval: TimeInterval = 2.0
    private let routePersistMinDistanceMeters: Double = 5
    private let routePersistMaxPoints: Int = 1400
    private let maxDistanceStepMeters: Double = 250
    private var lastDistanceLocation: CLLocation? = nil
    
    @ObservationIgnored @AppStorage("distanceUnit") var distanceUnit = "mi"
    @ObservationIgnored @AppStorage("enableBackgroundRunTracking") var enableBackgroundRunTracking = true
    
    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        
        manager.allowsBackgroundLocationUpdates = false
        // Keep updates continuous during active cardio sessions, including when locked.
        manager.pausesLocationUpdatesAutomatically = false
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            #if os(iOS)
            // manager.showsBackgroundLocationIndicator = true // Enable if you want the blue banner in background
            #endif
        }
    }
    
    func requestAuthorization(startAfterAuth: Bool = false) {
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStartAfterAuth = startAfterAuth
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if enableBackgroundRunTracking {
                manager.requestAlwaysAuthorization()
            }
        default:
            break
        }
    }
    
    func requestCurrentLocation() {
        // One-time location request to populate last known location without continuous updates
        manager.requestLocation()
    }

    func clearCurrentRun(resetActivityType: Bool = false) {
        route.removeAll()
        distance = 0.0
        duration = 0.0
        startDate = nil
        pausedAt = nil
        pausedDuration = 0.0
        shouldSkipNextDistanceSample = false
        lastDistanceLocation = nil
        location = nil
        isRunning = false
        smoothedPaceSecondsPerUnit = nil
        recentSamples.removeAll()
        lastLiveActivityUpdateAt = nil
        lastLiveActivityDistanceMeters = 0
        lastLiveActivityPace = nil

        if resetActivityType {
            activityType = "running"
        }
    }

    func startRun() {
        clearCurrentRun()
        startDate = Date()
        maybeRequestAlwaysAuthorizationUpgradeIfNeeded()
        updateBackgroundLocationMode(isActiveRun: true)
        manager.startUpdatingLocation()
        startTimer()
        isRunning = true
        // Start Live Activity (if available)
        LiveActivityManager.shared.start(startDate: startDate ?? Date(),
                                         distanceMeters: 0,
                                         paceSecondsPerUnit: nil,
                                         distanceUnit: distanceUnit,
                                         activityType: activityType)
    }
    
    func pauseRun() {

        if isRunning {
            pausedAt = Date()
        }
        updateBackgroundLocationMode(isActiveRun: false)
        manager.stopUpdatingLocation()
        stopTimer()
        isRunning = false

        // Push immediate update so the widget freezes the timer
        if let s = startDate {
            let currentDuration = max(0, Date().timeIntervalSince(s) - pausedDuration)
            lastLiveActivityUpdateAt = nil
            LiveActivityManager.shared.update(startDate: s,
                                              duration: currentDuration,
                                              distanceMeters: distance,
                                              paceSecondsPerUnit: smoothedPaceSecondsPerUnit,
                                              distanceUnit: distanceUnit,
                                              isPaused: true)
        }
    }
    
    func resumeRun() {

        if let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        shouldSkipNextDistanceSample = true
        lastDistanceLocation = nil
        if startDate == nil {
            startDate = Date()
        }
        maybeRequestAlwaysAuthorizationUpgradeIfNeeded()
        updateBackgroundLocationMode(isActiveRun: true)
        manager.startUpdatingLocation()
        startTimer()
        isRunning = true

        // Push immediate update so the widget resumes the live timer
        if let s = startDate {
            lastLiveActivityUpdateAt = nil
            LiveActivityManager.shared.update(startDate: s,
                                              duration: duration,
                                              distanceMeters: distance,
                                              paceSecondsPerUnit: smoothedPaceSecondsPerUnit,
                                              distanceUnit: distanceUnit,
                                              isPaused: false)
        }
    }
    
    func stopRun() -> RunningSession? {
        if let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        updateBackgroundLocationMode(isActiveRun: false)
        manager.stopUpdatingLocation()
        stopTimer()
        isRunning = false
        
        if let s = startDate {
            let activeDuration = max(0, Date().timeIntervalSince(s) - pausedDuration)
            duration = max(duration, activeDuration)
        }
        startDate = nil
        
        // Downsample route for persisted payload size while preserving start/end.
        let persistedRoute = downsampleRouteForStorage(
            route,
            maxPoints: routePersistMaxPoints,
            minDistance: routePersistMinDistanceMeters
        )
        // Encode route data with altitude and timestamp
        let coordinates = persistedRoute.map {
            Coordinate(latitude: $0.coordinate.latitude, 
                      longitude: $0.coordinate.longitude,
                      altitude: $0.altitude,
                      timestamp: $0.timestamp) 
        }
        let encoder = JSONEncoder()
        guard let locationsData = try? encoder.encode(coordinates) else {
            return nil
        }
        
        // Calculate elevation metrics from route
        let elevationMetrics = calculateElevationMetrics(from: route)
        
        // Create RunningSession object (but don't save it here)
        return RunningSession(distance: distance / (distanceUnit == "km" ? 1000 : 1609.34), // Convert meters to selected unit
                              distanceUnit: distanceUnit,
                              duration: duration,
                              locations: locationsData,
                              activityType: activityType,
                              totalAscent: elevationMetrics?.ascent,
                              totalDescent: elevationMetrics?.descent,
                              minElevation: elevationMetrics?.min,
                              maxElevation: elevationMetrics?.max)
    }

    private func downsampleRouteForStorage(_ route: [CLLocation], maxPoints: Int, minDistance: Double) -> [CLLocation] {
        guard route.count > 2 else { return route }

        var filtered: [CLLocation] = []
        filtered.reserveCapacity(min(route.count, maxPoints))
        filtered.append(route[0])

        var lastKept = route[0]
        for loc in route.dropFirst().dropLast() {
            if loc.distance(from: lastKept) >= minDistance {
                filtered.append(loc)
                lastKept = loc
            }
        }

        let finalPoint = route[route.count - 1]
        if filtered.last?.timestamp != finalPoint.timestamp {
            filtered.append(finalPoint)
        }

        guard filtered.count > maxPoints, maxPoints > 2 else { return filtered }

        let first = filtered[0]
        let last = filtered[filtered.count - 1]
        let interiorLimit = maxPoints - 2
        let interiorCount = filtered.count - 2
        if interiorCount <= interiorLimit { return filtered }

        var downsampled: [CLLocation] = [first]
        downsampled.reserveCapacity(maxPoints)
        let step = Double(interiorCount) / Double(interiorLimit)
        var lastIndex = 0

        for i in 1...interiorLimit {
            let raw = Int((Double(i) * step).rounded(.down))
            let index = min(max(1, raw), filtered.count - 2)
            if index == lastIndex { continue }
            downsampled.append(filtered[index])
            lastIndex = index
        }
        downsampled.append(last)
        return downsampled
    }
    
    private func calculateElevationMetrics(from locations: [CLLocation]) -> (ascent: Double, descent: Double, min: Double, max: Double)? {
        let altitudes = locations.map { $0.altitude }
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
    
    private func startTimer() {
        stopTimer() // Ensure no duplicate timers
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isRunning, let s = self.startDate {
                self.duration = max(0, Date().timeIntervalSince(s) - self.pausedDuration)
                if self.shouldUpdateLiveActivity(now: Date()) {
                    LiveActivityManager.shared.update(startDate: s,
                                                      duration: self.duration,
                                                      distanceMeters: self.distance,
                                                      paceSecondsPerUnit: self.smoothedPaceSecondsPerUnit,
                                                      distanceUnit: self.distanceUnit)
                }
            }
        }
    }

    private func shouldUpdateLiveActivity(now: Date) -> Bool {
        guard LiveActivityManager.shared.isActive else { return false }

        let intervalReached: Bool
        if let last = lastLiveActivityUpdateAt {
            intervalReached = now.timeIntervalSince(last) >= liveActivityMinUpdateInterval
        } else {
            intervalReached = true
        }

        let distanceDelta = abs(distance - lastLiveActivityDistanceMeters)
        let paceDelta: Double = {
            guard let currentPace = smoothedPaceSecondsPerUnit, let lastPace = lastLiveActivityPace else { return 0 }
            return abs(currentPace - lastPace)
        }()
        let significantChange = distanceDelta >= liveActivityDistanceDeltaMeters || paceDelta >= liveActivityPaceDeltaSeconds

        guard intervalReached || significantChange else { return false }

        lastLiveActivityUpdateAt = now
        lastLiveActivityDistanceMeters = distance
        lastLiveActivityPace = smoothedPaceSecondsPerUnit
        return true
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func maybeRequestAlwaysAuthorizationUpgradeIfNeeded() {
        guard enableBackgroundRunTracking else { return }
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    private func updateBackgroundLocationMode(isActiveRun: Bool) {
        let hasAlways = manager.authorizationStatus == .authorizedAlways
        manager.allowsBackgroundLocationUpdates = isActiveRun && enableBackgroundRunTracking && hasAlways
    }
    
    // CLLocationManagerDelegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }

        let runStart = startDate
        let validLocations = locations.filter { point in
            guard point.horizontalAccuracy >= 0 && point.horizontalAccuracy <= routeAccuracyThresholdMeters else { return false }
            if let runStart {
                return point.timestamp >= runStart.addingTimeInterval(-5)
            }
            return true
        }
        guard let latestLocation = validLocations.last else { return }

        // Always update last known location so the UI can center even when not running
        self.location = latestLocation
        
        // Removed clock drift bug: do not mutate startDate from location timestamps
        /*
        if isRunning && startDate == nil {
            startDate = newLocation.timestamp
        }
        */
        
        // Only track distance/route while running
        guard isRunning else { return }

        // Balanced sampling: use only the latest valid point per callback to avoid burst over-capture.
        let newLocation = latestLocation

        if shouldSkipNextDistanceSample {
            route.append(newLocation)
            lastDistanceLocation = newLocation
            shouldSkipNextDistanceSample = false
            return
        }

        if let lastDistanceLocation {
            let segmentDistance = newLocation.distance(from: lastDistanceLocation)
            if segmentDistance.isFinite, segmentDistance >= 0, segmentDistance <= maxDistanceStepMeters {
                distance += segmentDistance
            }
        }
        lastDistanceLocation = newLocation

        if shouldAcceptForRoute(newLocation) {
            route.append(newLocation)
        }

        // Update smoothing samples
        let now = Date()
        recentSamples.append((time: now, distanceMeters: distance))
        // Drop samples older than window
        recentSamples.removeAll { now.timeIntervalSince($0.time) > smoothingWindowSeconds }
        // Compute delta over window
        if let first = recentSamples.first, let last = recentSamples.last {
            let dt = last.time.timeIntervalSince(first.time)
            let dd = last.distanceMeters - first.distanceMeters
            if dt > 0 && dd >= smoothingMinDistance {
                // Convert to seconds per selected unit
                let metersPerUnit: Double = (distanceUnit == "km") ? 1000 : 1609.34
                let secPerUnit = (dt / dd) * metersPerUnit
                smoothedPaceSecondsPerUnit = secPerUnit
            }
        }
    }

    private func shouldAcceptForRoute(_ location: CLLocation) -> Bool {
        guard let last = route.last else { return true }
        let distanceDelta = location.distance(from: last)
        let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
        return distanceDelta >= routeMinDistanceMeters || timeDelta >= routeMinTimeInterval
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        // Handle error appropriately (e.g., show alert to user)
        if let clError = error as? CLError, clError.code == .denied {
             pauseRun() // Stop run if permissions denied
             // Maybe show an alert directing user to settings?
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        updateBackgroundLocationMode(isActiveRun: isRunning)
        maybeRequestAlwaysAuthorizationUpgradeIfNeeded()
        
        // Handle authorization changes if needed (e.g., start run if granted)
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
            if pendingStartAfterAuth && !isRunning {
                pendingStartAfterAuth = false
                startRun()
            }
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            // Stop any attempt to auto-start
            pendingStartAfterAuth = false
        }
    }
}

struct RunTrackingProView: View {
    let activityType: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var runTracker = RunTracker.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSettingsPrompt = false
    @State private var showingDiscardConfirmation = false
    
    @State private var isSavingRun: Bool = false
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    
    // NEW: Map camera / region state
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var shouldFollowUser: Bool = true // When true, recenter on user updates
    @State private var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                                                   span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    
    // Throttle interval to reduce choppy re-centering
    private let followThrottle: TimeInterval = 1.0
    
    // Formatter for distance
    private var distanceFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }
    
    // Formatter for duration
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: duration) ?? "00:00"
    }
    
    // Calculate pace (time per unit distance)
    private var pace: String {
        guard runTracker.distance > 0, runTracker.duration > 0 else { return "--:--" }

        // Prefer smoothed pace when available while active metrics are non-zero.
        if let smoothed = runTracker.smoothedPaceSecondsPerUnit, smoothed.isFinite {
            return formatDuration(smoothed)
        }
        let distanceInUnit = runTracker.distance / (runTracker.distanceUnit == "km" ? 1000 : 1609.34)
        let paceSeconds = runTracker.duration / max(distanceInUnit, 0.0001)
        return formatDuration(paceSeconds)
    }
    
    // Build a MKPolyline from route points
    private var routePolyline: MKPolyline? {
        guard !runTracker.route.isEmpty else { return nil }
        let coords = runTracker.route.map { $0.coordinate }
        return MKPolyline(coordinates: coords, count: coords.count)
    }
    
    // Helper to recenter on current location if available or request location if missing
    private func recenterOnUser() {
        if let loc = runTracker.location?.coordinate {
            withAnimation {
                let newRegion = MKCoordinateRegion(center: loc,
                                                   span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                region = newRegion
                cameraPosition = .region(newRegion)
            }
        } else {
            // Request a one-time location, then when it arrives, auto-center via onChange
            runTracker.requestCurrentLocation()
        }
    }

    private var activityDisplayName: String {
        switch activityType.lowercased() {
        case "run", "running":
            return "Run"
        case "walk", "walking":
            return "Walk"
        case "hike", "hiking":
            return "Hike"
        case "cycle", "cycling", "bike", "biking":
            return "Ride"
        case "swim", "swimming":
            return "Swim"
        default:
            return activityType
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Permission status banner
            if runTracker.authorizationStatus == .notDetermined {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.yellow)
                    Text("We need your location to track this \(activityDisplayName.lowercased()).")
                        .font(.callout)
                    Spacer()
                    Button("Allow") {
                        runTracker.requestAuthorization()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding([.horizontal, .top])
            } else if runTracker.authorizationStatus == .denied || runTracker.authorizationStatus == .restricted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Location access is off. Enable it in Settings to start this \(activityDisplayName.lowercased()).")
                        .font(.callout)
                    Spacer()
                    Button("Open Settings") {
                        #if os(iOS)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding([.horizontal, .top])
            }
            
            // Interactive Map
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, interactionModes: .all) {
                    UserAnnotation()
                }
                .onMapCameraChange { context in
                    region = context.region
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .frame(height: 280)
                .gesture(DragGesture().onEnded { _ in
                    shouldFollowUser = false
                })
                .onChange(of: runTracker.location) { _, newLoc in
                    guard shouldFollowUser, let newLoc = newLoc else { return }
                    // Throttle updates to at most once per followThrottle seconds
                    let now = Date()
                    if let last = runTracker.lastFollowUpdate, now.timeIntervalSince(last) < followThrottle {
                        return
                    }
                    // Only recenter if we've moved a meaningful distance (~15m)
                    let shouldRecentre: Bool
                    if let center = region.center as CLLocationCoordinate2D? {
                        let prev = CLLocation(latitude: center.latitude, longitude: center.longitude)
                        let dist = newLoc.distance(from: prev)
                        shouldRecentre = dist > 15
                    } else {
                        shouldRecentre = true
                    }
                    if shouldRecentre {
                        let newRegion = MKCoordinateRegion(center: newLoc.coordinate,
                                                           span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                        withAnimation(.easeInOut(duration: 0.25)) {
                            cameraPosition = .region(newRegion)
                        }
                        runTracker.lastFollowUpdate = now
                    }
                }
                .task {
                    // Ensure we prompt on first appearance if needed and fetch a location
                    runTracker.requestAuthorization(startAfterAuth: false)
                    runTracker.requestCurrentLocation()
                }
                .onAppear {
                    // Set the activity type from the parameter
                    runTracker.activityType = activityType
                    
                    // Initial center if we already have a location
                    if let coord = runTracker.location?.coordinate {
                        let initialRegion = MKCoordinateRegion(center: coord,
                                                               span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                        cameraPosition = .region(initialRegion)
                    } else {
                        // Request a one-time location to allow initial centering
                        runTracker.requestCurrentLocation()
                    }
                }
            }
            
            // Stats Display
            HStack(spacing: 20) {
                VStack {
                    Text(formatDuration(runTracker.duration))
                        .font(.largeTitle)
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    let distanceInUnit = runTracker.distance / (runTracker.distanceUnit == "km" ? 1000 : 1609.34)
                    Text(distanceFormatter.string(from: NSNumber(value: distanceInUnit)) ?? "0.00")
                        .font(.largeTitle)
                    Text("Distance (\(runTracker.distanceUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack {
                    Text(pace)
                        .font(.largeTitle)
                    Text("Pace (/\(runTracker.distanceUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            Spacer()
            
            // Control Buttons
            HStack(spacing: 12) {
                if !runTracker.isRunning {
                    Button {
                        #if os(iOS)
                        switch runTracker.authorizationStatus {
                        case .authorizedAlways, .authorizedWhenInUse:
                            if runTracker.duration == 0 { runTracker.startRun() } else { runTracker.resumeRun() }
                            shouldFollowUser = true
                            recenterOnUser()
                            runTracker.lastFollowUpdate = nil
                        case .notDetermined:
                            runTracker.requestAuthorization(startAfterAuth: true)
                        case .denied, .restricted:
                            alertMessage = "Location access is required to start this \(activityDisplayName.lowercased()). Please enable it in Settings > Privacy > Location Services."
                            showingAlert = true
                        @unknown default:
                            runTracker.requestAuthorization(startAfterAuth: false)
                        }
                        #else
                        if runTracker.duration == 0 { runTracker.startRun() } else { runTracker.resumeRun() }
                        shouldFollowUser = true
                        recenterOnUser()
                        runTracker.lastFollowUpdate = nil
                        #endif
                    } label: {
                        Label(runTracker.duration == 0 ? "Start" : "Resume", systemImage: runTracker.duration == 0 ? "play.fill" : "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)

                    if runTracker.duration > 0 {
                        Button {
                            saveRun()
                        } label: {
                            ZStack {
                                Label("Stop & Save", systemImage: "stop.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(Rectangle())
                                if isSavingRun {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
                        .disabled(isSavingRun)
                        .opacity(isSavingRun ? 0.7 : 1)
                    } else {
                        // Maintain symmetry with a disabled placeholder button
                        Button(action: {}) {
                            Label("Stop & Save", systemImage: "stop.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red.opacity(0.5))
                        .clipShape(Capsule())
                        .disabled(true)
                        .opacity(0.6)
                    }
                } else {
                    Button {
                        runTracker.pauseRun()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)

                    Button {
                        saveRun()
                    } label: {
                        ZStack {
                            Label("Stop & Save", systemImage: "stop.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .contentShape(Rectangle())
                            if isSavingRun {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
                    .disabled(isSavingRun)
                    .opacity(isSavingRun ? 0.7 : 1)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Tracking \(activityDisplayName)")
        // Hide the system back button while actively running (tracking persists
        // in the background) and while paused with unsaved data (so leaving is
        // routed through the discard confirmation instead of silently dismissing).
        .navigationBarBackButtonHidden(runTracker.isRunning || runTracker.duration > 0)
        // Block interactive sheet swipe-down for the same states — it would bypass
        // handleDone() and leave an orphaned Live Activity on a paused run.
        .interactiveDismissDisabled(runTracker.isRunning || runTracker.duration > 0)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !runTracker.isRunning && runTracker.duration > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        handleDone()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        shouldFollowUser = true
                        recenterOnUser()
                        runTracker.lastFollowUpdate = nil
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .disabled(runTracker.authorizationStatus == .denied || runTracker.authorizationStatus == .restricted)
                    .help("Center on current location")

                    Button("Done") {
                        handleDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        shouldFollowUser = true
                        recenterOnUser()
                        runTracker.lastFollowUpdate = nil
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .disabled(runTracker.authorizationStatus == .denied || runTracker.authorizationStatus == .restricted)
                    .help("Center on current location")
                    
                    Button("Done") {
                        handleDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #endif
        .interactiveDismissDisabled(false)
        .onDisappear {
            // Intentionally do not stop tracking on dismiss; tracking persists via shared RunTracker
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Discard \(activityDisplayName)?", isPresented: $showingDiscardConfirmation) {
            Button("Discard", role: .destructive) { discardRun() }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("This \(activityDisplayName.lowercased()) is paused and hasn't been saved. Leaving now will discard it.")
        }
    }

    // Handle the "Done" toolbar button.
    // - Active run: keep tracking (background run support) and just dismiss.
    // - Paused run with elapsed data: prompt so it isn't abandoned with a stale
    //   Live Activity.
    // - Fresh/zero-data session: tear down any Live Activity, clear the tracker,
    //   and dismiss cleanly without prompting.
    private func handleDone() {
        if runTracker.isRunning {
            // Actively running: preserve tracking and the Live Activity.
            dismiss()
        } else if runTracker.duration > 0 {
            showingDiscardConfirmation = true
        } else {
            // Never started or zero-duration: nothing to save.
            LiveActivityManager.shared.end()
            runTracker.clearCurrentRun(resetActivityType: true)
            dismiss()
        }
    }

    // Fully abandon a paused run: stop tracking, reset RunTracker state, and end
    // the Live Activity so it can't persist or be adopted on the next launch.
    private func discardRun() {
        _ = runTracker.stopRun()
        LiveActivityManager.shared.end()
        runTracker.clearCurrentRun(resetActivityType: true)
        shouldFollowUser = false
        dismiss()
    }
    
    private func saveRun() {
        guard !isSavingRun else { return }
        isSavingRun = true
        

        // Capture end timestamp and route snapshot for HealthKit before any resets
        let endTime = Date()
        let routeSnapshot: [CLLocation] = runTracker.route
        let distanceMeters: Double = runTracker.distance

        guard let session = runTracker.stopRun() else {
            
            alertMessage = "Failed to prepare run data for saving."
            showingAlert = true
            isSavingRun = false
            return
        }

        // Persist end time onto the session date
        session.date = endTime

        modelContext.insert(session)
        do {
            try modelContext.save()


            // Fire-and-forget: write to HealthKit (if authorized). We derive start from end - duration.
            let startTime = endTime.addingTimeInterval(-session.duration)
            let activityType = session.activityType
            Task { @MainActor in
                do {
                    let workout = try await HealthKitManager.shared.saveRunWorkout(
                        start: startTime,
                        end: endTime,
                        distanceMeters: distanceMeters,
                        energyBurned: nil,
                        activityType: activityType
                    )
                    session.healthWorkoutUUID = workout.uuid.uuidString
                    if !PersistenceSave.commit(modelContext, action: "link saved run with Health workout UUID") {
                        alertMessage = "Run saved locally, but the Apple Health link could not be persisted. The run may import again later as a duplicate."
                        showingAlert = true
                        return
                    }

                    do {
                        try await HealthKitManager.shared.saveRunRoute(routeSnapshot, for: workout)
                    } catch {
                        alertMessage = "Run saved and linked to Apple Health, but route sync failed: \(error.localizedDescription)"
                        showingAlert = true
                    }
                } catch {
                    alertMessage = "Run saved locally, but sync to Apple Health failed: \(error.localizedDescription)"
                    showingAlert = true
                }
            }

            // Report Game Center leaderboards (Longest Run, Fastest Run)
            GameCenterService.shared.reportRunStats(
                distance: session.distance,
                distanceUnit: session.distanceUnit,
                duration: session.duration
            )

            // Update streak achievements (daily and weekly)
            StreakService.refreshAndReport(using: modelContext)

            // End Live Activity (if any)
            LiveActivityManager.shared.end()

            // Reset tracker so the next start is a brand-new run (not resume)
            runTracker.clearCurrentRun(resetActivityType: true)

            shouldFollowUser = false
            isSavingRun = false
            dismiss()
        } catch {
            
            alertMessage = "Failed to save run to database: \(error.localizedDescription)"
            showingAlert = true
            isSavingRun = false
        }
    }
}
