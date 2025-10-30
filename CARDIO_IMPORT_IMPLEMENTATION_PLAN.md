# Cardio Import - Complete Implementation Plan

## Overview
Transform the current "Runs" feature into a comprehensive "Cardio" tracker that automatically imports all cardio workouts from HealthKit (including those from MyNetDiary, Strava, etc.) while preserving their original activity types.

---

## Scope: Cardio Activity Types to Import

### Phase 1: Core Cardio Activities
- 🏃 Running
- 🚶 Walking
- 🥾 Hiking
- 🚴 Cycling
- 🏃‍♀️ Jogging (if different from running)

### Phase 2: Extended Cardio (Future)
- 🏊 Swimming
- ⛷️ Skiing/Snowboarding
- 🛼 Skating
- 🚣 Rowing
- 🧗 Climbing
- 🏄 Surfing

**Priority for Phase 1:** Walking, Running, Hiking, Cycling (most common for your mom's use case)

---

## Data Model Changes

### 1. Update `RunningSession.swift` → Rename to `CardioSession.swift`

**New Properties to Add:**
```swift
@Model
final class CardioSession {
    var id: UUID = UUID()
    var date: Date = Date()
    
    // NEW: Activity type tracking
    var activityType: String = "running" // HKWorkoutActivityType raw value
    var activityDisplayName: String = "Run" // User-friendly name
    var activityIcon: String = "figure.run" // SF Symbol name
    
    var distance: Double = 0
    var distanceUnit: String = "km"
    var duration: TimeInterval = 0
    var calories: Double? = nil
    var notes: String?
    var locations: Data = Data()
    
    // Source tracking
    var healthWorkoutUUID: String? = nil
    var sourceApp: String? = nil // "MyNetDiary", "Strava", "Pace & Plates", etc.
    var isImported: Bool = false // true if from HealthKit, false if tracked in P&P
    
    // NEW: Activity-specific metrics
    var elevationGain: Double? = nil // meters (for hiking/cycling)
    var averageSpeed: Double? = nil // m/s
    var averageHeartRate: Double? = nil // bpm
    var maxHeartRate: Double? = nil // bpm
}
```

**Migration Strategy:**
- Rename model from `RunningSession` to `CardioSession`
- Add migration to set `activityType = "running"` for all existing sessions
- Add migration to set `activityDisplayName = "Run"` for existing sessions
- Add migration to set `activityIcon = "figure.run"` for existing sessions
- Add migration to set `isImported = false` for existing sessions (since they were tracked in-app)

---

## Activity Type Mapping

### Create `CardioActivityType.swift` - New Enum/Helper

```swift
import HealthKit
import SwiftUI

enum CardioActivityType: String, CaseIterable, Codable {
    case running
    case walking
    case hiking
    case cycling
    case swimming
    case rowing
    case skating
    case skiing
    case snowboarding
    case climbing
    case elliptical
    case stairClimbing
    case other
    
    // Map from HKWorkoutActivityType
    init(from hkType: HKWorkoutActivityType) {
        switch hkType {
        case .running: self = .running
        case .walking: self = .walking
        case .hiking: self = .hiking
        case .cycling: self = .cycling
        case .swimming, .swimBikeRun: self = .swimming
        case .rowing: self = .rowing
        case .skating, .skatingSports: self = .skating
        case .skiing, .crossCountrySkiing, .downhillSkiing: self = .skiing
        case .snowboarding: self = .snowboarding
        case .climbing, .rockClimbing: self = .climbing
        case .elliptical: self = .elliptical
        case .stairClimbing: self = .stairClimbing
        default: self = .other
        }
    }
    
    // Display properties
    var displayName: String {
        switch self {
        case .running: return "Run"
        case .walking: return "Walk"
        case .hiking: return "Hike"
        case .cycling: return "Ride"
        case .swimming: return "Swim"
        case .rowing: return "Row"
        case .skating: return "Skate"
        case .skiing: return "Ski"
        case .snowboarding: return "Snowboard"
        case .climbing: return "Climb"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .other: return "Workout"
        }
    }
    
    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .rowing: return "figure.rowing"
        case .skating: return "figure.skating"
        case .skiing: return "figure.skiing.downhill"
        case .snowboarding: return "figure.snowboarding"
        case .climbing: return "figure.climbing"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stairs"
        case .other: return "figure.mixed.cardio"
        }
    }
    
    var color: Color {
        switch self {
        case .running: return .red
        case .walking: return .blue
        case .hiking: return .green
        case .cycling: return .orange
        case .swimming: return .cyan
        case .rowing: return .purple
        case .skating: return .pink
        case .skiing, .snowboarding: return .mint
        case .climbing: return .brown
        case .elliptical, .stairClimbing: return .indigo
        case .other: return .gray
        }
    }
    
    var verb: String {
        switch self {
        case .running: return "ran"
        case .walking: return "walked"
        case .hiking: return "hiked"
        case .cycling: return "rode"
        case .swimming: return "swam"
        case .rowing: return "rowed"
        case .skating: return "skated"
        case .skiing: return "skied"
        case .snowboarding: return "snowboarded"
        case .climbing: return "climbed"
        case .elliptical: return "did"
        case .stairClimbing: return "climbed"
        case .other: return "completed"
        }
    }
    
    // Does this activity typically have distance?
    var hasDistance: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .swimming, .rowing, .skiing, .snowboarding:
            return true
        case .skating, .climbing, .elliptical, .stairClimbing, .other:
            return false
        }
    }
    
    // Does this activity typically have route data?
    var hasRoute: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .skiing, .snowboarding:
            return true
        default:
            return false
        }
    }
}
```

---

## HealthKit Manager Changes

### Update `HealthKitManager.swift`

#### 1. Expand Read Types
```swift
private let readTypes: Set<HKObjectType> = {
    var set = Set<HKObjectType>()
    set.insert(HKObjectType.workoutType()) // All workout types
    set.insert(HKObjectType.quantityType(forIdentifier: .heartRate)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .distanceCycling)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .distanceSwimming)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .stepCount)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .vo2Max)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .runningPower)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .runningSpeed)!)
    set.insert(HKObjectType.quantityType(forIdentifier: .cyclingSpeed)!)
    // NEW: Elevation
    set.insert(HKQuantityType.quantityType(forIdentifier: .distanceDownhillSnowSports)!)
    set.insert(HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!)
    set.insert(HKSeriesType.workoutRoute())
    return set
}()
```

#### 2. New Method: Fetch All Cardio Workouts
```swift
func fetchRecentCardioWorkouts(
    activityTypes: [HKWorkoutActivityType],
    limit: Int = 50
) async throws -> [HKWorkout] {
    let predicates = activityTypes.map { 
        HKQuery.predicateForWorkouts(with: $0) 
    }
    let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: compoundPredicate,
            limit: limit,
            sortDescriptors: [sort]
        ) { _, samples, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            let workouts = (samples as? [HKWorkout]) ?? []
            continuation.resume(returning: workouts)
        }
        self.healthStore.execute(query)
    }
}
```

#### 3. New Method: Fetch Elevation Data
```swift
func elevationGain(for workout: HKWorkout) async throws -> Double? {
    // Try to get elevation from route data first
    let locations = try? await routeLocations(for: workout)
    if let locs = locations, locs.count > 1 {
        var gain: Double = 0
        for i in 1..<locs.count {
            let elevDiff = locs[i].altitude - locs[i-1].altitude
            if elevDiff > 0 { gain += elevDiff }
        }
        return gain > 0 ? gain : nil
    }
    return nil
}
```

#### 4. New Method: Fetch Heart Rate Data
```swift
func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
    let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    let predicate = HKQuery.predicateForSamples(
        withStart: workout.startDate,
        end: workout.endDate,
        options: .strictStartDate
    )
    
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: heartRateType,
            quantitySamplePredicate: predicate,
            options: .discreteAverage
        ) { _, stats, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }
            let avgHR = stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            continuation.resume(returning: avgHR)
        }
        self.healthStore.execute(query)
    }
}
```

#### 5. Update Save Methods to Support All Types
```swift
func saveCardioWorkout(
    activityType: HKWorkoutActivityType,
    start: Date,
    end: Date,
    distance: Double?, // in meters, optional for some activities
    distanceType: HKQuantityTypeIdentifier, // .distanceWalkingRunning, .distanceCycling, etc.
    energyBurned: Double? = nil,
    route: [CLLocation]? = nil
) async throws {
    // Similar to current saveRunWorkout but with activity type parameter
}
```

---

## UI Changes

### 1. Rename Files (Do Last When Ready)
- `RunLogView.swift` → `CardioLogView.swift`
- `RunTrackingView.swift` → `CardioTrackingView.swift`
- `RunningSession.swift` → `CardioSession.swift`

### 2. Update Navigation/Naming
- Screen title: "Runs" → "Cardio"
- Button text: "Track Run" → "Track Workout"
- Section header: "Recent Runs" → "Recent Workouts"

### 3. New UI Component: Activity Type Badge

**Create `ActivityTypeBadge.swift`:**
```swift
struct ActivityTypeBadge: View {
    let activityType: CardioActivityType
    let size: BadgeSize
    
    enum BadgeSize {
        case small, medium, large
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 16
            case .large: return 24
            }
        }
        
        var fontSize: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .body
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: activityType.icon)
                .font(.system(size: size.iconSize))
            Text(activityType.displayName)
                .font(size.fontSize)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(activityType.color.opacity(0.2))
        .foregroundColor(activityType.color)
        .clipShape(Capsule())
    }
}
```

### 4. New UI Component: Source App Badge

**Create `SourceAppBadge.swift`:**
```swift
struct SourceAppBadge: View {
    let sourceApp: String?
    let isImported: Bool
    
    var body: some View {
        if isImported, let source = sourceApp {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                Text("from \(source)")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
        }
    }
}
```

### 5. Update List Item Display

**In `CardioLogView.swift` (formerly RunLogView):**
```swift
ForEach(cardioSessions) { session in
    NavigationLink {
        CardioSessionDetailView(session: session)
    } label: {
        HStack(alignment: .top) {
            // Activity type icon/badge
            ActivityTypeBadge(
                activityType: CardioActivityType(rawValue: session.activityType) ?? .other,
                size: .medium
            )
            
            VStack(alignment: .leading, spacing: 4) {
                // Date/time
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                
                // Distance (if applicable)
                let activityType = CardioActivityType(rawValue: session.activityType) ?? .other
                if activityType.hasDistance && session.distance > 0 {
                    Text("\(String(format: "%.1f", session.distance)) \(session.distanceUnit)")
                        .font(.subheadline)
                }
                
                // Duration
                Text(formatDuration(session.duration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // Calories
                if let cal = session.calories, cal > 0 {
                    Text("\(String(format: "%.0f", cal)) kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Source app badge
                SourceAppBadge(sourceApp: session.sourceApp, isImported: session.isImported)
            }
            .foregroundColor(AppTheme.textColor)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

### 6. Update Chart Visualization

**Add Activity Type Filtering:**
```swift
@State private var selectedActivityTypes: Set<CardioActivityType> = [.running, .walking, .hiking, .cycling]

// Filter toggle buttons
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        ForEach(CardioActivityType.allCases, id: \.self) { type in
            Button {
                if selectedActivityTypes.contains(type) {
                    selectedActivityTypes.remove(type)
                } else {
                    selectedActivityTypes.insert(type)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: type.icon)
                    Text(type.displayName)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selectedActivityTypes.contains(type) 
                        ? type.color.opacity(0.3) 
                        : Color.gray.opacity(0.1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            selectedActivityTypes.contains(type) 
                                ? type.color 
                                : Color.clear,
                            lineWidth: 2
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
```

**Stacked Bar Chart by Activity Type:**
```swift
Chart {
    ForEach(dailyData) { day in
        ForEach(day.byActivityType, id: \.type) { typeData in
            BarMark(
                x: .value("Date", day.date),
                y: .value("Distance", typeData.distance)
            )
            .foregroundStyle(typeData.type.color)
            .position(by: .value("Activity", typeData.type.displayName))
        }
    }
}
.chartLegend(position: .bottom)
```

---

## Settings Panel

### New Settings Section: Cardio Import Settings

**In `SettingsView.swift`, add new section:**

```swift
Section {
    NavigationLink {
        CardioImportSettingsView()
    } label: {
        Label("Cardio Import", systemImage: "heart.circle")
    }
} header: {
    Text("Workouts")
}
```

**Create `CardioImportSettingsView.swift`:**
```swift
struct CardioImportSettingsView: View {
    @AppStorage("autoImportCardio") private var autoImport = true
    @AppStorage("importedActivityTypes") private var importedTypes = "running,walking,hiking,cycling"
    @AppStorage("showSourceApp") private var showSourceApp = true
    @AppStorage("lastCardioSync") private var lastSync: Double = 0
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-import from Health", isOn: $autoImport)
                Toggle("Show source app name", isOn: $showSourceApp)
            } header: {
                Text("Import Settings")
            } footer: {
                Text("Automatically import cardio workouts logged in other apps like MyNetDiary, Strava, etc.")
            }
            
            Section {
                ForEach(CardioActivityType.allCases, id: \.self) { type in
                    Toggle(isOn: binding(for: type)) {
                        Label {
                            Text(type.displayName)
                        } icon: {
                            Image(systemName: type.icon)
                                .foregroundColor(type.color)
                        }
                    }
                }
            } header: {
                Text("Activity Types to Import")
            }
            
            Section {
                HStack {
                    Text("Last synced")
                    Spacer()
                    if lastSync > 0 {
                        Text(Date(timeIntervalSince1970: lastSync), style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Button("Sync Now") {
                    Task {
                        // Trigger manual sync
                    }
                }
            } header: {
                Text("Sync Status")
            }
        }
        .navigationTitle("Cardio Import")
    }
    
    private func binding(for type: CardioActivityType) -> Binding<Bool> {
        Binding(
            get: { importedTypes.contains(type.rawValue) },
            set: { isEnabled in
                var types = importedTypes.components(separatedBy: ",")
                if isEnabled {
                    if !types.contains(type.rawValue) {
                        types.append(type.rawValue)
                    }
                } else {
                    types.removeAll { $0 == type.rawValue }
                }
                importedTypes = types.joined(separator: ",")
            }
        )
    }
}
```

---

## Import Logic Changes

### Update `CardioLogView.swift` Import Method

**Replace `importHealthRuns()` with `importHealthCardioWorkouts()`:**

```swift
private func importHealthCardioWorkouts(limit: Int = 50) {
    Task { @MainActor in
        do {
            // Check if auto-import is enabled
            @AppStorage("autoImportCardio") var autoImport = true
            @AppStorage("importedActivityTypes") var importedTypesString = "running,walking,hiking,cycling"
            
            guard autoImport else { return }
            guard HealthKitManager.shared.isAuthorized else { return }
            
            // Parse which activity types to import
            let typesToImport = importedTypesString
                .components(separatedBy: ",")
                .compactMap { CardioActivityType(rawValue: $0) }
            
            // Map to HKWorkoutActivityType
            let hkTypes: [HKWorkoutActivityType] = typesToImport.compactMap { type in
                switch type {
                case .running: return .running
                case .walking: return .walking
                case .hiking: return .hiking
                case .cycling: return .cycling
                case .swimming: return .swimming
                case .rowing: return .rowing
                case .skating: return .skating
                case .skiing: return .skiing
                case .snowboarding: return .snowboarding
                case .climbing: return .climbing
                case .elliptical: return .elliptical
                case .stairClimbing: return .stairClimbing
                case .other: return nil
                }
            }
            
            // Fetch workouts
            let workouts = try await HealthKitManager.shared.fetchRecentCardioWorkouts(
                activityTypes: hkTypes,
                limit: limit
            )
            
            for workout in workouts {
                let uuidStr = workout.uuid.uuidString
                
                // Skip if already imported
                var fd = FetchDescriptor<CardioSession>(
                    predicate: #Predicate { $0.healthWorkoutUUID == uuidStr }
                )
                fd.fetchLimit = 1
                if let existing = try? modelContext.fetch(fd), !existing.isEmpty {
                    continue
                }
                
                // Extract workout data
                let activityType = CardioActivityType(from: workout.workoutActivityType)
                let end = workout.endDate
                let duration = workout.duration
                
                // Distance (might be nil for some activities)
                var distance: Double = 0
                var distanceUnit = preferredDistanceUnit
                if let totalDist = workout.totalDistance {
                    let meters = totalDist.doubleValue(for: .meter())
                    distance = (distanceUnit == "mi") ? (meters / 1609.34) : (meters / 1000.0)
                }
                
                // Calories
                let calories = try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout)
                
                // Source app name
                let sourceApp = workout.sourceRevision.source.name
                
                // Route data (if available)
                var routeData: Data? = nil
                if activityType.hasRoute {
                    if let locs = try? await HealthKitManager.shared.routeLocations(for: workout), !locs.isEmpty {
                        let reduced = downsampleLocations(locs)
                        let coords = reduced.map { 
                            CardioCoordinate(
                                latitude: $0.coordinate.latitude,
                                longitude: $0.coordinate.longitude,
                                altitude: $0.altitude
                            )
                        }
                        routeData = try? JSONEncoder().encode(coords)
                    }
                }
                
                // Elevation (for hiking/cycling)
                var elevation: Double? = nil
                if activityType == .hiking || activityType == .cycling {
                    elevation = try? await HealthKitManager.shared.elevationGain(for: workout)
                }
                
                // Heart rate
                let avgHR = try? await HealthKitManager.shared.averageHeartRate(for: workout)
                
                // Create session
                let session = CardioSession(
                    date: end,
                    activityType: activityType.rawValue,
                    activityDisplayName: activityType.displayName,
                    activityIcon: activityType.icon,
                    distance: distance,
                    distanceUnit: distanceUnit,
                    duration: duration,
                    calories: calories,
                    locations: routeData,
                    healthWorkoutUUID: uuidStr,
                    sourceApp: sourceApp,
                    isImported: true,
                    elevationGain: elevation,
                    averageHeartRate: avgHR
                )
                
                modelContext.insert(session)
            }
            
            try? modelContext.save()
            
            // Update last sync time
            @AppStorage("lastCardioSync") var lastSync: Double = 0
            lastSync = Date().timeIntervalSince1970
            
        } catch {
            print("Failed to import cardio workouts: \(error)")
        }
    }
}
```

---

## Tracking In-App Workouts

### Update `CardioTrackingView.swift` (formerly RunTrackingView)

**Add Activity Type Selection at Start:**

```swift
struct CardioTrackingView: View {
    @State private var selectedActivityType: CardioActivityType = .running
    @State private var hasStarted = false
    
    var body: some View {
        if !hasStarted {
            // Activity type selection screen
            ActivityTypeSelectionView(
                selectedType: $selectedActivityType,
                onStart: {
                    hasStarted = true
                    startTracking()
                }
            )
        } else {
            // Current tracking UI
            TrackingInProgressView(activityType: selectedActivityType)
        }
    }
}

struct ActivityTypeSelectionView: View {
    @Binding var selectedType: CardioActivityType
    let onStart: () -> Void
    
    let quickAccessTypes: [CardioActivityType] = [.running, .walking, .hiking, .cycling]
    
    var body: some View {
        VStack(spacing: 24) {
            Text("What are you doing?")
                .font(.title2)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(quickAccessTypes, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: type.icon)
                                .font(.system(size: 40))
                                .foregroundColor(selectedType == type ? type.color : .secondary)
                            Text(type.displayName)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(selectedType == type ? type.color.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(selectedType == type ? type.color : Color.clear, lineWidth: 3)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                onStart()
            } label: {
                Label("Start \(selectedType.displayName)", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedType.color)
            .clipShape(Capsule())
        }
        .padding()
    }
}
```

**Update Save Logic to Include Activity Type:**
```swift
private func saveWorkout() {
    // ... existing logic ...
    
    let session = CardioSession(
        date: endTime,
        activityType: selectedActivityType.rawValue,
        activityDisplayName: selectedActivityType.displayName,
        activityIcon: selectedActivityType.icon,
        distance: distance,
        distanceUnit: distanceUnit,
        duration: duration,
        locations: routeData,
        healthWorkoutUUID: nil,
        sourceApp: "Pace & Plates",
        isImported: false // Tracked in-app
    )
    
    // Save to HealthKit with correct activity type
    let hkActivityType = selectedActivityType.toHKWorkoutActivityType()
    try await HealthKitManager.shared.saveCardioWorkout(
        activityType: hkActivityType,
        // ... other params
    )
}
```

---

## Detail View Updates

### Update `CardioSessionDetailView.swift` (formerly RunSessionDetailView)

**Show Activity-Specific Details:**

```swift
var body: some View {
    ScrollView {
        VStack(spacing: 16) {
            // Activity type header
            HStack {
                ActivityTypeBadge(
                    activityType: CardioActivityType(rawValue: session.activityType) ?? .other,
                    size: .large
                )
                Spacer()
                if session.isImported {
                    SourceAppBadge(sourceApp: session.sourceApp, isImported: true)
                }
            }
            
            // Stats tile
            VStack(alignment: .leading, spacing: 8) {
                Text("Stats")
                    .font(.headline)
                
                let activityType = CardioActivityType(rawValue: session.activityType) ?? .other
                
                // Date
                StatRow(label: "Date", value: session.date.formatted())
                
                // Distance (if applicable)
                if activityType.hasDistance && session.distance > 0 {
                    StatRow(
                        label: "Distance",
                        value: "\(String(format: "%.1f", session.distance)) \(session.distanceUnit)"
                    )
                }
                
                // Duration
                StatRow(label: "Duration", value: formatDuration(session.duration))
                
                // Elevation (for hiking/cycling)
                if let elevation = session.elevationGain, elevation > 0 {
                    StatRow(
                        label: "Elevation Gain",
                        value: "\(String(format: "%.0f", elevation)) m"
                    )
                }
                
                // Heart rate
                if let avgHR = session.averageHeartRate {
                    StatRow(
                        label: "Avg Heart Rate",
                        value: "\(String(format: "%.0f", avgHR)) bpm"
                    )
                }
                
                // Calories
                if let cal = session.calories {
                    StatRow(label: "Calories", value: "\(String(format: "%.0f", cal)) kcal")
                }
                
                // Pace (for distance activities)
                if activityType.hasDistance && session.distance > 0 && session.duration > 0 {
                    let pace = session.duration / (session.distance * 60) // min per unit
                    StatRow(
                        label: "Avg Pace",
                        value: String(format: "%d:%02d /%@", Int(pace), Int((pace.truncatingRemainder(dividingBy: 1)) * 60), session.distanceUnit)
                    )
                }
            }
            .floatingTile()
            
            // Route tile (if applicable)
            if activityType.hasRoute {
                // ... existing route map logic ...
            }
            
            // Notes tile
            // ... existing notes logic ...
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
```

---

## Manual Entry Feature

### Create `AddPastCardioView.swift`

```swift
struct AddPastCardioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var activityType: CardioActivityType = .walking
    @State private var date = Date()
    @State private var duration: TimeInterval = 1800 // 30 min default
    @State private var distance: Double = 5.0
    @State private var distanceUnit: String = "km"
    @State private var calories: String = ""
    @State private var notes: String = ""
    @State private var alsoSaveToHealth = true
    
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section {
                // Activity type picker
                Picker("Activity Type", selection: $activityType) {
                    ForEach(CardioActivityType.allCases, id: \.self) { type in
                        Label {
                            Text(type.displayName)
                        } icon: {
                            Image(systemName: type.icon)
                                .foregroundColor(type.color)
                        }
                        .tag(type)
                    }
                }
            } header: {
                Text("Activity")
            }
            
            Section {
                DatePicker("Date & Time", selection: $date)
                
                // Duration picker (hours and minutes)
                DurationPickerView(duration: $duration)
            } header: {
                Text("When")
            }
            
            if activityType.hasDistance {
                Section {
                    HStack {
                        TextField("Distance", value: $distance, format: .number)
                            .keyboardType(.decimalPad)
                        
                        Picker("Unit", selection: $distanceUnit) {
                            Text("km").tag("km")
                            Text("mi").tag("mi")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                } header: {
                    Text("Distance")
                } footer: {
                    Text("Enter the total distance covered")
                }
            }
            
            Section {
                TextField("Calories (optional)", text: $calories)
                    .keyboardType(.numberPad)
            } header: {
                Text("Calories")
            } footer: {
                Text("Leave blank to estimate based on activity")
            }
            
            Section {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Notes (Optional)")
            }
            
            Section {
                Toggle("Also save to Health app", isOn: $alsoSaveToHealth)
            } footer: {
                Text("Save this workout to Apple Health so other apps can see it")
            }
        }
        .navigationTitle("Add Past Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveWorkout()
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveWorkout() {
        // Validation
        guard duration > 0 else {
            errorMessage = "Duration must be greater than 0"
            showingError = true
            return
        }
        
        if activityType.hasDistance && distance <= 0 {
            errorMessage = "Distance must be greater than 0"
            showingError = true
            return
        }
        
        // Parse calories
        let caloriesValue = Double(calories)
        
        // Create session
        let session = CardioSession(
            date: date,
            activityType: activityType.rawValue,
            activityDisplayName: activityType.displayName,
            activityIcon: activityType.icon,
            distance: activityType.hasDistance ? distance : 0,
            distanceUnit: distanceUnit,
            duration: duration,
            calories: caloriesValue,
            notes: notes.isEmpty ? nil : notes,
            locations: Data(),
            healthWorkoutUUID: nil,
            sourceApp: "Pace & Plates",
            isImported: false
        )
        
        modelContext.insert(session)
        
        do {
            try modelContext.save()
            
            // Optionally save to HealthKit
            if alsoSaveToHealth {
                Task {
                    let startDate = date.addingTimeInterval(-duration)
                    try? await HealthKitManager.shared.saveCardioWorkout(
                        activityType: activityType.toHKWorkoutActivityType(),
                        start: startDate,
                        end: date,
                        distance: activityType.hasDistance ? (distance * (distanceUnit == "km" ? 1000 : 1609.34)) : nil,
                        distanceType: activityType.distanceTypeIdentifier(),
                        energyBurned: caloriesValue
                    )
                }
            }
            
            dismiss()
        } catch {
            errorMessage = "Failed to save workout: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct DurationPickerView: View {
    @Binding var duration: TimeInterval
    
    private var hours: Int {
        get { Int(duration) / 3600 }
        set { duration = TimeInterval(newValue * 3600 + minutes * 60 + seconds) }
    }
    
    private var minutes: Int {
        get { (Int(duration) % 3600) / 60 }
        set { duration = TimeInterval(hours * 3600 + newValue * 60 + seconds) }
    }
    
    private var seconds: Int {
        get { Int(duration) % 60 }
        set { duration = TimeInterval(hours * 3600 + minutes * 60 + newValue) }
    }
    
    var body: some View {
        HStack {
            Text("Duration")
            Spacer()
            Picker("Hours", selection: Binding(get: { hours }, set: { hours = $0 })) {
                ForEach(0..<24) { Text("\($0)h").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            
            Picker("Minutes", selection: Binding(get: { minutes }, set: { minutes = $0 })) {
                ForEach(0..<60) { Text("\($0)m").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
            
            Picker("Seconds", selection: Binding(get: { seconds }, set: { seconds = $0 })) {
                ForEach(0..<60) { Text("\($0)s").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(width: 70)
        }
    }
}
```

---

## SwiftData Migration

### Create Migration Script

**Since we're renaming `RunningSession` to `CardioSession` and adding fields:**

```swift
// In PersistenceController.swift or migration file

import SwiftData

enum SchemaV2 {
    static func migrate(from context: ModelContext) throws {
        // Fetch all existing RunningSession objects
        let descriptor = FetchDescriptor<RunningSession>()
        let existingSessions = try context.fetch(descriptor)
        
        // For each old session, create new CardioSession
        for oldSession in existingSessions {
            let newSession = CardioSession(
                id: oldSession.id,
                date: oldSession.date,
                activityType: "running", // Default for all existing
                activityDisplayName: "Run",
                activityIcon: "figure.run",
                distance: oldSession.distance,
                distanceUnit: oldSession.distanceUnit,
                duration: oldSession.duration,
                calories: oldSession.calories,
                notes: oldSession.notes,
                locations: oldSession.locations,
                healthWorkoutUUID: oldSession.healthWorkoutUUID,
                sourceApp: oldSession.healthWorkoutUUID != nil ? "Unknown App" : "Pace & Plates",
                isImported: oldSession.healthWorkoutUUID != nil
            )
            context.insert(newSession)
            context.delete(oldSession)
        }
        
        try context.save()
    }
}
```

---

## Testing Plan

### Phase 1 Testing
1. ✅ Import walking workout from MyNetDiary
2. ✅ Import running workout from P&P's own tracker
3. ✅ Import cycling workout from Strava (if available)
4. ✅ Verify duplicate detection works
5. ✅ Verify source app name displays correctly
6. ✅ Check that existing run data migrates properly

### Phase 2 Testing
1. ✅ Manually add a past walk
2. ✅ Manually add a past bike ride
3. ✅ Verify HealthKit write works
4. ✅ Verify manual entries don't get re-imported

### Phase 3 Testing
1. ✅ Settings toggles work correctly
2. ✅ Activity type filtering in charts works
3. ✅ Manual sync button works
4. ✅ Route maps display for all activity types

---

## Implementation Checklist

### Step 1: Data Model & Infrastructure
- [ ] Create `CardioActivityType.swift` enum
- [ ] Create `CardioCoordinate.swift` (with altitude)
- [ ] Rename `RunningSession` → `CardioSession`
- [ ] Add new properties to `CardioSession`
- [ ] Create migration script
- [ ] Test migration with sample data

### Step 2: HealthKit Enhancements
- [ ] Update `HealthKitManager` read types
- [ ] Add `fetchRecentCardioWorkouts()` method
- [ ] Add `elevationGain()` method
- [ ] Add `averageHeartRate()` method
- [ ] Update `saveCardioWorkout()` to support all types
- [ ] Test HealthKit queries with sample data

### Step 3: Import Logic
- [ ] Create `importHealthCardioWorkouts()` method
- [ ] Add activity type filtering based on settings
- [ ] Add source app name extraction
- [ ] Add elevation/HR data import
- [ ] Test import with multiple activity types

### Step 4: UI Components
- [ ] Create `ActivityTypeBadge.swift`
- [ ] Create `SourceAppBadge.swift`
- [ ] Update list item display
- [ ] Update detail view display
- [ ] Test UI with various activity types

### Step 5: Settings
- [ ] Create `CardioImportSettingsView.swift`
- [ ] Add activity type toggles
- [ ] Add auto-import toggle
- [ ] Add manual sync button
- [ ] Test settings persistence

### Step 6: Manual Entry
- [ ] Create `AddPastCardioView.swift`
- [ ] Create `DurationPickerView`
- [ ] Add "Add Past Workout" button to toolbar
- [ ] Test manual entry flow
- [ ] Test HealthKit write from manual entry

### Step 7: Charts & Visualizations
- [ ] Add activity type filter chips
- [ ] Update chart to show stacked/grouped data
- [ ] Add legend for activity types
- [ ] Test chart with mixed activity types

### Step 8: Tracking Updates
- [ ] Add activity type selection to start screen
- [ ] Update tracking UI with activity-specific labels
- [ ] Update save logic to include activity type
- [ ] Test in-app tracking for each activity type

### Step 9: Renaming (FINAL STEP)
- [ ] Rename `RunLogView` → `CardioLogView`
- [ ] Rename `RunTrackingView` → `CardioTrackingView`
- [ ] Update all navigation titles
- [ ] Update all button labels
- [ ] Update tab bar / home screen references
- [ ] Search codebase for "run" references and update
- [ ] Test full app flow

### Step 10: Polish & QA
- [ ] Add empty states for each activity type
- [ ] Add helpful tips/banners
- [ ] Test with no HealthKit permission
- [ ] Test with partial HealthKit permission
- [ ] Performance test with 100+ workouts
- [ ] Test on iPhone and iPad
- [ ] Update tutorial/onboarding

---

## File Structure Summary

### New Files to Create
```
WorkingOut/
├── Models/
│   ├── CardioSession.swift (renamed from RunningSession)
│   └── CardioActivityType.swift (NEW)
├── Features/
│   └── Cardio/ (renamed from Runs/)
│       ├── CardioLogView.swift (renamed from RunLogView)
│       ├── CardioTrackingView.swift (renamed from RunTrackingView)
│       ├── CardioSessionDetailView.swift (extracted from RunLogView)
│       └── AddPastCardioView.swift (NEW)
├── Components/
│   ├── ActivityTypeBadge.swift (NEW)
│   └── SourceAppBadge.swift (NEW)
└── Settings/
    └── CardioImportSettingsView.swift (NEW)
```

---

## Estimated Timeline

| Phase | Description | Time Estimate |
|-------|-------------|---------------|
| 1 | Data model changes & migration | 2-3 hours |
| 2 | HealthKit enhancements | 3-4 hours |
| 3 | Import logic updates | 2-3 hours |
| 4 | UI components | 2-3 hours |
| 5 | Settings panel | 1-2 hours |
| 6 | Manual entry feature | 3-4 hours |
| 7 | Charts & visualizations | 2-3 hours |
| 8 | Tracking updates | 2-3 hours |
| 9 | Renaming & refactoring | 1-2 hours |
| 10 | Testing & polish | 3-4 hours |
| **TOTAL** | | **21-31 hours** |

---

## Risk & Considerations

### Data Loss Prevention
- ✅ Keep old `RunningSession` data during migration
- ✅ Test migration on copy of database first
- ✅ Add rollback capability

### Performance
- ⚠️ Fetching 50+ workouts with routes could be slow
- ✅ Solution: Lazy loading, pagination, route caching

### HealthKit Permissions
- ⚠️ Users might not grant all workout type permissions
- ✅ Solution: Graceful degradation, clear error messages

### Duplicate Detection
- ⚠️ Some apps might not provide workout UUIDs
- ✅ Solution: Fuzzy matching by time/distance/duration

---

## Success Metrics

After implementation, verify:
1. ✅ MyNetDiary walks import automatically within 2 minutes
2. ✅ All activity types display with correct icons/colors
3. ✅ Source app badges show correctly
4. ✅ Manual entry works for all activity types
5. ✅ No data loss from migration
6. ✅ Charts display mixed activity types clearly
7. ✅ Settings persist and affect import behavior

---

*Implementation Plan for Pace & Plates - Cardio Import Feature*
*Date: October 29, 2025*
*Status: Ready for implementation - awaiting approval*

