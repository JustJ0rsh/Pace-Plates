import SwiftUI
import CoreLocation
import MapKit
import SwiftData

// Simple Codable wrapper for CLLocationCoordinate2D
struct Coordinate: Codable, Identifiable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    
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
    
    @ObservationIgnored @AppStorage("distanceUnit") var distanceUnit = "mi"
    
    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10 // Update every 10 meters
        
        manager.allowsBackgroundLocationUpdates = true
        // Allow the system to pause updates to conserve battery when appropriate
        manager.pausesLocationUpdatesAutomatically = true
        
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            #if os(iOS)
            // manager.showsBackgroundLocationIndicator = true // Enable if you want the blue banner in background
            #endif
        }
    }
    
    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            pendingStartAfterAuth = true
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }
    
    func requestCurrentLocation() {
        // One-time location request to populate last known location without continuous updates
        manager.requestLocation()
    }
    
    func startRun() {
        
        route.removeAll()
        distance = 0.0
        duration = 0.0
        location = nil
        startDate = Date()
        smoothedPaceSecondsPerUnit = nil
        recentSamples.removeAll()
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
        
        manager.stopUpdatingLocation()
        stopTimer()
        isRunning = false
    }
    
    func resumeRun() {
        
        if startDate == nil {
            startDate = Date().addingTimeInterval(-duration)
        }
        manager.startUpdatingLocation()
        startTimer()
        isRunning = true
    }
    
    func stopRun() -> RunningSession? {
        manager.stopUpdatingLocation()
        stopTimer()
        isRunning = false
        
        if let s = startDate {
            duration = max(duration, Date().timeIntervalSince(s))
        }
        startDate = nil
        
        // Encode route data
        let coordinates = route.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let encoder = JSONEncoder()
        guard let locationsData = try? encoder.encode(coordinates) else {
            
            return nil
        }
        
        // Create RunningSession object (but don't save it here)
        return RunningSession(distance: distance / (distanceUnit == "km" ? 1000 : 1609.34), // Convert meters to selected unit
                              distanceUnit: distanceUnit,
                              duration: duration,
                              locations: locationsData,
                              activityType: activityType)
    }
    
    private func startTimer() {
        stopTimer() // Ensure no duplicate timers
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.isRunning, let s = self.startDate {
                self.duration = Date().timeIntervalSince(s)
                // Update Live Activity with current stats
                LiveActivityManager.shared.update(startDate: s,
                                                  duration: self.duration,
                                                  distanceMeters: self.distance,
                                                  paceSecondsPerUnit: self.smoothedPaceSecondsPerUnit,
                                                  distanceUnit: self.distanceUnit)
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // CLLocationManagerDelegate Methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Ignore inaccurate points
        guard newLocation.horizontalAccuracy >= 0 && newLocation.horizontalAccuracy <= 50 else { return }
        
        // Always update last known location so the UI can center even when not running
        self.location = newLocation
        
        // Removed clock drift bug: do not mutate startDate from location timestamps
        /*
        if isRunning && startDate == nil {
            startDate = newLocation.timestamp
        }
        */
        
        // Only track distance/route while running
        guard isRunning else { return }
        
        if let lastLocation = route.last {
            distance += newLocation.distance(from: lastLocation)
        }
        
        route.append(newLocation)

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
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        
        // Handle error appropriately (e.g., show alert to user)
        if let clError = error as? CLError, clError.code == .denied {
             pauseRun() // Stop run if permissions denied
             // Maybe show an alert directing user to settings?
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.allowsBackgroundLocationUpdates = true
        }
        
        
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
        // Prefer smoothed pace when available; otherwise fall back to overall average
        if let smoothed = runTracker.smoothedPaceSecondsPerUnit, smoothed.isFinite {
            return formatDuration(smoothed)
        }
        guard runTracker.distance > 0, runTracker.duration > 0 else { return "--:--" }
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Permission status banner
            if runTracker.authorizationStatus == .notDetermined {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.yellow)
                    Text("We need your location to track runs.")
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
                    Text("Location access is off. Enable it in Settings to start a run.")
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
                    runTracker.requestAuthorization()
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
                            runTracker.pendingStartAfterAuth = true
                            runTracker.requestAuthorization()
                        case .denied, .restricted:
                            alertMessage = "Location access is required to start a run. Please enable it in Settings > Privacy > Location Services."
                            showingAlert = true
                        @unknown default:
                            runTracker.requestAuthorization()
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
        .navigationTitle("Tracking Run")
        .navigationBarBackButtonHidden(runTracker.isRunning)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shouldFollowUser = true
                    recenterOnUser()
                    runTracker.lastFollowUpdate = nil
                } label: {
                    Image(systemName: "location.fill")
                }
                .disabled(runTracker.authorizationStatus == .denied || runTracker.authorizationStatus == .restricted)
                .help("Center on current location")
            }
        }
        #else
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shouldFollowUser = true
                    recenterOnUser()
                    runTracker.lastFollowUpdate = nil
                } label: {
                    Image(systemName: "location.fill")
                }
                .disabled(runTracker.authorizationStatus == .denied || runTracker.authorizationStatus == .restricted)
                .help("Center on current location")
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
                    try await HealthKitManager.shared.saveRunWorkout(
                        start: startTime,
                        end: endTime,
                        distanceMeters: distanceMeters,
                        energyBurned: nil,
                        route: routeSnapshot,
                        activityType: activityType
                    )
                    
                } catch {
                    
                }
            }

            // End Live Activity (if any)
            LiveActivityManager.shared.end()

            // Reset tracker so the next start is a brand-new run (not resume)
            runTracker.route.removeAll()
            runTracker.distance = 0
            runTracker.duration = 0
            runTracker.location = nil
            runTracker.startDate = nil
            runTracker.isRunning = false
            runTracker.activityType = "running" // Reset to default

            shouldFollowUser = false
            isSavingRun = false
            // Auto-submit leaderboards after saving
            GameCenterService.submitAllMetrics(context: modelContext, preferredUnit: weightUnit)
            dismiss()
        } catch {
            
            alertMessage = "Failed to save run to database: \(error.localizedDescription)"
            showingAlert = true
            isSavingRun = false
        }
    }
}
