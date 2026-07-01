# Oura Wearable Vitals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Settings preference for `No Extra Device`, `Apple Watch`, or `Oura Ring`, then make the Home vitals snapshot render the metric set that best matches that wearable.

**Architecture:** Keep the first release HealthKit-first because the app already reads Apple Health and Oura can sync many basics into Apple Health. Model the wearable choice as a small persisted enum, make the Home vitals model produce source-aware card descriptors instead of hardcoded cards, then add a second-phase Oura API client for Oura-only scores that HealthKit cannot provide reliably.

**Tech Stack:** SwiftUI, SwiftData, HealthKit, UserDefaults via `@AppStorage`, Xcode UI tests, Oura API V2 OAuth in phase 2.

---

## Source Facts

- Current repo already has Home vitals in `WorkingOut/Features/Home/Vitals/VitalsModel.swift` and `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`.
- Current Settings already has `Health & Sync` and Home toggles in `WorkingOut/Features/Settings/SettingsView.swift`.
- Current HealthKit access is centralized in `WorkingOut/Services/HealthKitManager.swift`.
- Oura Apple Health sync can export basics such as active energy, heart rate, respiratory rate, sleep duration/stages, steps, weight, workouts, workout calories, and workout distance.
- Oura API V2 exposes OAuth/Bearer auth plus daily sleep, readiness, activity, SpO2, stress, resilience, detailed sleep, workout, and heart-rate endpoints. Oura-only fields such as readiness score, activity score, stress summary, resilience level, SpO2 daily average, temperature deviation, detailed sleep HRV, and sleep score should be treated as API-backed phase 2 data.

## File Structure

- Create `WorkingOut/Models/WearableDevicePreference.swift`: persisted enum and user-facing labels.
- Create `WorkingOut/Features/Home/Vitals/VitalMetric.swift`: small display model for a Home vitals card.
- Modify `WorkingOut/Services/HealthKitManager.swift`: add respiratory rate to read permissions and add source-aware helpers for latest samples and daily sums.
- Modify `WorkingOut/Features/Home/Vitals/VitalsModel.swift`: convert fixed string properties into `[VitalMetric]` based on selected wearable.
- Modify `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`: render dynamic cards and source labels.
- Modify `WorkingOut/Features/Settings/SettingsView.swift`: add the wearable picker under Health & Sync.
- Modify `WorkingOut/App/AppLaunchConfiguration.swift`: seed `preferredWearableDevice` for UI tests.
- Modify `WorkingOutUITests/WorkingOutUITests.swift`: cover Settings options and Home vitals labels with fixture state.
- Create in Task 6: `WorkingOut/Services/Oura/OuraAPIClient.swift`, `WorkingOut/Services/Oura/OuraTokenStore.swift`, and `WorkingOut/Services/Oura/OuraVitalsProvider.swift` for direct API support.

### Task 1: Add Wearable Preference Model

**Files:**
- Create: `WorkingOut/Models/WearableDevicePreference.swift`
- Modify: `WorkingOut/App/AppLaunchConfiguration.swift`

- [ ] **Step 1: Add the enum**

```swift
import Foundation

enum WearableDevicePreference: String, CaseIterable, Identifiable {
    static let storageKey = "preferredWearableDevice"

    case none
    case appleWatch
    case ouraRing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Extra Device"
        case .appleWatch: return "Apple Watch"
        case .ouraRing: return "Oura Ring"
        }
    }

    var shortSourceName: String {
        switch self {
        case .none: return "Health"
        case .appleWatch: return "Apple Watch"
        case .ouraRing: return "Oura"
        }
    }

    var healthSourceNameHints: [String] {
        switch self {
        case .none:
            return []
        case .appleWatch:
            return ["Apple Watch", "Watch"]
        case .ouraRing:
            return ["Oura", "Oura Ring"]
        }
    }
}
```

- [ ] **Step 2: Seed UI-test default**

Add this default inside `AppLaunchConfiguration.prepareUserDefaults`:

```swift
WearableDevicePreference.storageKey: WearableDevicePreference.none.rawValue,
```

- [ ] **Step 3: Build-check**

Run:

```bash
xcodebuild -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: build succeeds, or fails only because the local simulator/runtime destination is unavailable.

### Task 2: Add Settings Picker

**Files:**
- Modify: `WorkingOut/Features/Settings/SettingsView.swift`
- Test: `WorkingOutUITests/WorkingOutUITests.swift`

- [ ] **Step 1: Add AppStorage state**

Near the other Settings `@AppStorage` values:

```swift
@AppStorage(WearableDevicePreference.storageKey) private var preferredWearableDeviceRaw: String = WearableDevicePreference.none.rawValue
```

- [ ] **Step 2: Add a binding**

Add this helper near other Settings computed bindings:

```swift
private var preferredWearableBinding: Binding<WearableDevicePreference> {
    Binding(
        get: {
            WearableDevicePreference(rawValue: preferredWearableDeviceRaw) ?? .none
        },
        set: { newValue in
            preferredWearableDeviceRaw = newValue.rawValue
        }
    )
}
```

- [ ] **Step 3: Add the UI in `healthSyncSettingsPage`**

Place this section above `Section("Apple Health")`:

```swift
Section("Wearable Data") {
    Picker("Vitals Source", selection: preferredWearableBinding) {
        ForEach(WearableDevicePreference.allCases) { preference in
            Text(preference.displayName).tag(preference)
        }
    }
    .pickerStyle(.segmented)
    .accessibilityIdentifier("settings.vitalsSource.picker")

    Text(wearableVitalsDescription)
        .font(.footnote)
        .foregroundStyle(.secondary)
}
```

Add:

```swift
private var wearableVitalsDescription: String {
    switch preferredWearableBinding.wrappedValue {
    case .none:
        return "Home shows basic Apple Health metrics and hides wearable-only recovery cards."
    case .appleWatch:
        return "Home prioritizes Apple Watch-style Health metrics like heart rate, HRV, SpO2, temperature, sleep, and VO2 Max when available."
    case .ouraRing:
        return "Home prioritizes Oura-synced Health data now. Direct Oura scores require connecting Oura in the phase 2 API step."
    }
}
```

- [ ] **Step 4: Add UI test assertions**

In the existing Settings UI test that opens `Health & Sync`, assert:

```swift
XCTAssertTrue(app.segmentedControls["settings.vitalsSource.picker"].exists)
XCTAssertTrue(app.buttons["No Extra Device"].exists)
XCTAssertTrue(app.buttons["Apple Watch"].exists)
XCTAssertTrue(app.buttons["Oura Ring"].exists)
```

- [ ] **Step 5: Run focused UI test**

Run:

```bash
UITEST_MODE=1 UITEST_FIXTURE=core_tabs UITEST_RESET_STATE=1 UITEST_START_TAB=home xcodebuild test -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WorkingOutUITests/WorkingOutUITests/testSettingsHealthSync
```

Expected: test passes and the picker is visible in Health & Sync.

### Task 3: Make Home Vitals Dynamic

**Files:**
- Create: `WorkingOut/Features/Home/Vitals/VitalMetric.swift`
- Modify: `WorkingOut/Features/Home/Vitals/VitalsModel.swift`
- Modify: `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`

- [ ] **Step 1: Add display metric type**

```swift
import Foundation

struct VitalMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let systemName: String
    let value: String
    let source: String?
}
```

- [ ] **Step 2: Replace hardcoded card properties**

In `VitalsModel`, keep `@Published var metrics: [VitalMetric] = []` and `@Published var wearablePreference: WearableDevicePreference = .none`.

Load preference at the start of `loadVitals()`:

```swift
let preference = WearableDevicePreference(
    rawValue: UserDefaults.standard.string(forKey: WearableDevicePreference.storageKey) ?? ""
) ?? .none
wearablePreference = preference
```

- [ ] **Step 3: Build metric sets by source**

Implement these three builders:

```swift
private func noExtraDeviceMetrics(values: LoadedVitals) -> [VitalMetric] {
    [
        VitalMetric(id: "steps", title: "Steps", systemName: "figure.walk", value: values.stepsToday, source: "Health"),
        VitalMetric(id: "activeEnergy", title: "Active Energy", systemName: "flame.fill", value: values.activeEnergy, source: "Health"),
        VitalMetric(id: "sleep", title: "Sleep", systemName: "bed.double.fill", value: values.sleepDuration, source: "Health"),
        VitalMetric(id: "sleepScore", title: "Sleep Score", systemName: "zzz", value: values.sleepScoreDisplay, source: "Estimated")
    ]
}

private func appleWatchMetrics(values: LoadedVitals) -> [VitalMetric] {
    [
        VitalMetric(id: "restingHeartRate", title: "Resting HR", systemName: "heart.fill", value: values.restingHeartRateOrHeartRate, source: "Watch"),
        VitalMetric(id: "hrv", title: "HRV", systemName: "waveform.path.ecg", value: values.hrv, source: "Watch"),
        VitalMetric(id: "spo2", title: "SpO2", systemName: "lungs.fill", value: values.spo2, source: "Watch"),
        VitalMetric(id: "bodyTemp", title: "Temp", systemName: "thermometer.medium", value: values.bodyTemp, source: "Watch"),
        VitalMetric(id: "sleep", title: "Sleep", systemName: "bed.double.fill", value: values.sleepDuration, source: "Watch"),
        VitalMetric(id: "vo2Max", title: "VO2 Max", systemName: "figure.run", value: values.vo2Max, source: "Health")
    ]
}

private func ouraHealthMetrics(values: LoadedVitals) -> [VitalMetric] {
    [
        VitalMetric(id: "sleep", title: "Sleep", systemName: "bed.double.fill", value: values.sleepDuration, source: "Oura"),
        VitalMetric(id: "sleepScore", title: "Sleep Score", systemName: "zzz", value: values.sleepScoreDisplay, source: "Estimated"),
        VitalMetric(id: "restingHeartRate", title: "Resting HR", systemName: "heart.fill", value: values.restingHeartRateOrHeartRate, source: "Oura"),
        VitalMetric(id: "respiratoryRate", title: "Resp. Rate", systemName: "lungs.fill", value: values.respiratoryRate, source: "Oura"),
        VitalMetric(id: "steps", title: "Steps", systemName: "figure.walk", value: values.stepsToday, source: "Oura"),
        VitalMetric(id: "activeEnergy", title: "Active Energy", systemName: "flame.fill", value: values.activeEnergy, source: "Oura")
    ]
}
```

`LoadedVitals` is a private struct in `VitalsModel` that stores formatted strings. Missing values must stay `"—"` so cards never crash.

- [ ] **Step 4: Render dynamic cards**

In `VitalsSnapshotView`, replace the hardcoded `VitalCard(...)` calls with:

```swift
ForEach(model.metrics) { metric in
    VitalCard(
        title: metric.title,
        systemName: metric.systemName,
        value: metric.value,
        source: metric.source
    )
}
```

Update `VitalCard` to include optional source text under the value:

```swift
if let source = source {
    Text(source)
        .font(.caption2)
        .foregroundStyle(AppTheme.secondaryTextColor)
}
```

- [ ] **Step 5: Add empty state**

If `model.metrics.isEmpty`, show:

```swift
Text("No vitals available yet")
    .font(.subheadline)
    .foregroundStyle(AppTheme.secondaryTextColor)
```

- [ ] **Step 6: Build-check**

Run the same `xcodebuild build` command from Task 1.

Expected: build succeeds.

### Task 4: Extend HealthKit Reads

**Files:**
- Modify: `WorkingOut/Services/HealthKitManager.swift`
- Modify: `WorkingOut/Features/Home/Vitals/VitalsModel.swift`

- [ ] **Step 1: Add respiratory rate permission**

Add this in `readTypes`:

```swift
if let t = HKObjectType.quantityType(forIdentifier: .respiratoryRate) { set.insert(t) }
```

- [ ] **Step 2: Add source-aware latest sample helper**

Add:

```swift
func latestQuantitySample(
    for id: HKQuantityTypeIdentifier,
    matchingSourceHints sourceHints: [String]
) async throws -> HKQuantitySample? {
    guard !sourceHints.isEmpty else {
        return try await latestQuantitySample(for: id)
    }

    guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
    let predicate = HKQuery.predicateForSamples(withStart: .distantPast, end: Date(), options: [])

    return try await withCheckedThrowingContinuation { cont in
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 25, sortDescriptors: [sort]) { _, samples, error in
            if let error {
                cont.resume(throwing: error)
                return
            }

            let typedSamples = (samples as? [HKQuantitySample]) ?? []
            let matched = typedSamples.first { sample in
                let name = sample.sourceRevision.source.name.lowercased()
                return sourceHints.contains { name.contains($0.lowercased()) }
            }

            cont.resume(returning: matched ?? typedSamples.first)
        }
        self.healthStore.execute(query)
    }
}
```

- [ ] **Step 3: Use source hints from `VitalsModel`**

When preference is `.appleWatch` or `.ouraRing`, call the source-aware helper for RHR, HRV, SpO2, temperature, respiratory rate, and VO2 Max. For steps and active energy, keep current HealthKit cumulative totals first because HealthKit already reconciles overlapping sources; show the selected wearable as the source label only when samples exist from that source.

- [ ] **Step 4: Build-check**

Run:

```bash
xcodebuild -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: build succeeds.

### Task 5: Add Fixture Coverage for Home Vitals

**Files:**
- Modify: `WorkingOut/App/AppLaunchConfiguration.swift`
- Modify: `WorkingOut/Features/Home/Vitals/VitalsModel.swift`
- Modify: `WorkingOutUITests/WorkingOutUITests.swift`

- [ ] **Step 1: Add a UI-test vitals fixture flag**

Add to `AppLaunchConfiguration`:

```swift
var usesVitalsFixture: Bool {
    fixtureName == "vitals"
}
```

- [ ] **Step 2: Return deterministic vitals in UI test mode**

At the start of `VitalsModel.loadVitals()`:

```swift
if AppLaunchConfiguration.current.usesVitalsFixture {
    let preference = WearableDevicePreference(
        rawValue: UserDefaults.standard.string(forKey: WearableDevicePreference.storageKey) ?? ""
    ) ?? .none
    wearablePreference = preference
    metrics = fixtureMetrics(for: preference)
    return
}
```

Fixture values:

```swift
private func fixtureMetrics(for preference: WearableDevicePreference) -> [VitalMetric] {
    switch preference {
    case .none:
        return [
            VitalMetric(id: "steps", title: "Steps", systemName: "figure.walk", value: "4,200", source: "Health"),
            VitalMetric(id: "activeEnergy", title: "Active Energy", systemName: "flame.fill", value: "320 kcal", source: "Health")
        ]
    case .appleWatch:
        return [
            VitalMetric(id: "restingHeartRate", title: "Resting HR", systemName: "heart.fill", value: "58 bpm", source: "Watch"),
            VitalMetric(id: "hrv", title: "HRV", systemName: "waveform.path.ecg", value: "62 ms", source: "Watch"),
            VitalMetric(id: "vo2Max", title: "VO2 Max", systemName: "figure.run", value: "47.2", source: "Health")
        ]
    case .ouraRing:
        return [
            VitalMetric(id: "sleep", title: "Sleep", systemName: "bed.double.fill", value: "7.6 h", source: "Oura"),
            VitalMetric(id: "respiratoryRate", title: "Resp. Rate", systemName: "lungs.fill", value: "14 br/min", source: "Oura"),
            VitalMetric(id: "restingHeartRate", title: "Resting HR", systemName: "heart.fill", value: "54 bpm", source: "Oura")
        ]
    }
}
```

- [ ] **Step 3: Add UI tests**

Add tests that launch with:

```swift
app.launchEnvironment["UITEST_MODE"] = "1"
app.launchEnvironment["UITEST_FIXTURE"] = "vitals"
app.launchEnvironment["UITEST_RESET_STATE"] = "1"
app.launchEnvironment["UITEST_START_TAB"] = "home"
app.launchEnvironment[WearableDevicePreference.storageKey] = WearableDevicePreference.ouraRing.rawValue
```

Assert:

```swift
XCTAssertTrue(app.staticTexts["Sleep"].exists)
XCTAssertTrue(app.staticTexts["Resp. Rate"].exists)
XCTAssertTrue(app.staticTexts["Oura"].exists)
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
UITEST_MODE=1 UITEST_FIXTURE=vitals UITEST_RESET_STATE=1 UITEST_START_TAB=home xcodebuild test -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WorkingOutUITests/WorkingOutUITests/testHomeVitalsUseOuraPreference
```

Expected: test passes.

### Task 6: Phase 2 Direct Oura API

**Files:**
- Create: `WorkingOut/Services/Oura/OuraAPIClient.swift`
- Create: `WorkingOut/Services/Oura/OuraTokenStore.swift`
- Create: `WorkingOut/Services/Oura/OuraVitalsProvider.swift`
- Modify: `WorkingOut/Features/Settings/SettingsView.swift`
- Modify: `WorkingOut/Features/Home/Vitals/VitalsModel.swift`
- Modify: `WorkingOut/Features/Settings/PrivacyPolicyContent.swift`

- [ ] **Step 1: Add connect/disconnect UI, but hide it behind Oura selection**

In Health & Sync, show `Connect Oura` and `Disconnect Oura` only when `preferredWearableBinding.wrappedValue == .ouraRing`.

- [ ] **Step 2: Use OAuth, not a personal access token**

Implement OAuth authorization code flow through `ASWebAuthenticationSession`. Store access and refresh tokens in Keychain via `OuraTokenStore`. Do not store tokens in `UserDefaults`, SwiftData, `.env`, or app logs.

- [ ] **Step 3: Fetch Oura-only cards**

Use these API fields:

```text
daily_readiness: score, temperature_deviation, temperature_trend_deviation
daily_sleep: score
daily_activity: score, steps, active_calories, total_calories
daily_spo2: spo2_percentage, breathing_disturbance_index
daily_stress: day_summary, stress_high, recovery_high
daily_resilience: level
sleep: average_heart_rate, lowest_heart_rate, average_hrv, average_breath, total_sleep_duration
heartrate: latest=true
```

- [ ] **Step 4: Merge API and HealthKit values**

Precedence for `.ouraRing`:

```text
Oura API value -> Oura-sourced HealthKit value -> general HealthKit fallback -> "—"
```

- [ ] **Step 5: Update privacy text**

Privacy policy must state that selecting direct Oura connects to Oura API, stores tokens in Keychain, and fetches only vitals/recovery metrics needed for Home.

- [ ] **Step 6: Add tests for token absence and fallback**

When selected device is Oura but no token exists, Home must still render the HealthKit-first Oura card set and Settings must show a non-blocking `Connect Oura` option.

### Task 7: Verification

**Files:**
- All files above.

- [ ] **Step 1: Run build**

```bash
xcodebuild -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- [ ] **Step 2: Run UI tests**

```bash
UITEST_MODE=1 UITEST_FIXTURE=core_tabs UITEST_RESET_STATE=1 xcodebuild test -project "Pace & Plates.xcodeproj" -scheme WorkingOut -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WorkingOutUITests
```

- [ ] **Step 3: Manual smoke on simulator or device**

Check:

```text
Settings -> Health & Sync -> Vitals Source shows all three options.
No Extra Device shows basic Health vitals only.
Apple Watch shows HR/HRV/SpO2/temp/sleep/VO2-style cards.
Oura Ring shows sleep/respiratory/resting-HR/steps/energy cards from HealthKit-first path.
Refresh button reloads without layout jump.
Turning off Show Vitals on Home still hides the entire vitals tile.
```

- [ ] **Step 4: Physical-device Oura validation**

On a real iPhone with Oura installed:

```text
Enable Oura -> Apple Health in the Oura app.
Grant Pace & Plates Health permissions.
Pick Oura Ring in Pace & Plates Settings.
Confirm Home shows Oura-synced sleep, HR, respiratory rate, steps, energy, and workouts where Health contains those samples.
Confirm API-only cards stay absent until direct Oura connection exists.
```

## Recommended COA

1. Ship Tasks 1-5 first. This gives users the three-choice Settings control and makes Home vitals correlate to the selected source without introducing OAuth risk.
2. Validate on your iPhone with the ring synced to Apple Health. This proves the real Oura-to-Health data surface before adding network auth.
3. Ship Task 6 after the MVP is stable. This is the right time to add readiness, sleep score, activity score, resilience/stress, SpO2, and temperature deviation from Oura API V2.
