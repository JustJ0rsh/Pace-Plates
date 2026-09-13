import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import HealthKit
import CoreLocation
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    private let launchConfiguration = AppLaunchConfiguration.current
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial" // "metric" or "imperial"
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit = "mi"
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("heightUnit") private var heightUnit: String = "in" // or "cm"
    // Age, sex, height, and goal weight are personal data and live in the
    // Keychain-backed profile store rather than UserDefaults.
    @Bindable private var profile = UserProfileStore.shared
    private var heightValue: Double {
        get { profile.heightValue }
        nonmutating set { profile.heightValue = newValue }
    }
    private var targetWeight: Double {
        get { profile.targetWeight }
        nonmutating set { profile.targetWeight = newValue }
    }
    private var age: Int {
        get { profile.age }
        nonmutating set { profile.age = newValue }
    }
    private var sex: String {
        get { profile.sex }
        nonmutating set { profile.sex = newValue }
    }
    /// The segmented picker has no "not set" state, so an unset sex displays as
    /// Male (the previous UserDefaults default) without writing anything back.
    private var sexSelection: Binding<String> {
        Binding(
            get: { profile.sex.isEmpty ? "male" : profile.sex },
            set: { profile.sex = $0 }
        )
    }
    @AppStorage("experienceLevel") private var experienceLevel: String = "beginner" // "beginner" or "experienced"
    @AppStorage("useStructuredPlanView") private var useStructuredPlanView: Bool = false
    @AppStorage("enableWeeklyWeightReminder") private var enableWeeklyWeightReminder: Bool = false
    @AppStorage("showVitalsOnHome") private var showVitalsOnHome: Bool = true
    @AppStorage(WearableDevicePreference.storageKey) private var preferredWearableRaw = WearableDevicePreference.none.rawValue
    @AppStorage("enableBackgroundRunTracking") private var enableBackgroundRunTracking: Bool = true
    @AppStorage("runsLastHealthImportAt") private var runsLastHealthImportAt: Double = 0
    @AppStorage("weightLastHealthImportAt") private var weightLastHealthImportAt: Double = 0
    @State private var showHeightPicker: Bool = false
    @State private var showGoalWeightPicker: Bool = false
    // Reminder prefs
    @AppStorage("reminderWeekday") private var reminderWeekday: Int = 2
    @AppStorage("reminderHour") private var reminderHour: Int = 9
    @AppStorage("reminderMinute") private var reminderMinute: Int = 0
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var confirmExport: Bool = false
    @State private var isProcessingBackup = false
    @State private var confirmImport: Bool = false
    @State private var confirmDedup: Bool = false
    @State private var isRefreshingHealthData: Bool = false
    @State private var showHealthSyncResult: Bool = false
    @State private var healthSyncResultMessage: String = ""
    @State private var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private let locationManager = CLLocationManager()
    #if DEBUG
    @State private var confirmAddSampleData: Bool = false
    @State private var confirmRemoveSampleData: Bool = false
    #endif

    var body: some View {
        settingsList
        .accessibilityIdentifier("settings.ready")
        // Force the insetGrouped table to rebuild when the theme changes.
        // This prevents the "Theme" row from briefly showing stale system row colors during transitions.
        .id(appTheme)
        .transaction { tx in
            tx.animation = nil
        }
        .listStyle(.insetGrouped)
        .appBackground(AppTheme.gradientSettings)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .onAppear {
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                loadProfileFromHealthKit()
                refreshLocationAuthorizationStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                refreshLocationAuthorizationStatus()
            }
        }
    }

    private var settingsList: some View {
        List {
            unitsSection
            appearanceSection
            profileSection
            goalsSection
            homeScreenSection
            remindersSection
            advancedSection
            aboutSection
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Measurement System", selection: $measurementSystem) {
                Text("Metric").tag("metric")
                Text("Imperial").tag("imperial")
            }
            .pickerStyle(.segmented)
            .onChange(of: measurementSystem) { _, newValue in
                updateMeasurementSystem(to: newValue)
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            NavigationLink {
                ThemePickerView(appTheme: $appTheme)
            } label: {
                HStack {
                    Text("Theme")
                    Spacer()
                    Text(appTheme.displayName)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
            }
        }
    }

    private var profileSection: some View {
        Section("Profile") {
            Picker("Sex", selection: sexSelection) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            .pickerStyle(.segmented)

            Picker("Experience Level", selection: $experienceLevel) {
                Text("New to Working Out").tag("beginner")
                Text("Experienced").tag("experienced")
            }
            .pickerStyle(.segmented)

            ageRow
            heightRow
            goalWeightRow
        }
    }

    private var ageRow: some View {
        Picker("Age", selection: $profile.age) {
            Text("Not Set").tag(0)
            ForEach(13...120, id: \.self) { value in
                Text("\(value)").tag(value)
            }
        }
        .pickerStyle(.menu)
    }

    private var heightRow: some View {
        Button {
            showHeightPicker = true
        } label: {
            HStack {
                Text("Height")
                Spacer()
                Text(heightDisplayValue)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showHeightPicker) {
            HeightPickerSheet(heightUnit: $heightUnit, heightValue: $profile.heightValue)
                .presentationDetents([.height(340), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var goalWeightRow: some View {
        Button {
            showGoalWeightPicker = true
        } label: {
            HStack {
                Text("Goal Weight")
                Spacer()
                Text(goalWeightDisplayValue)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGoalWeightPicker) {
            GoalWeightPickerSheet(
                weightUnit: weightUnit,
                targetWeight: $profile.targetWeight
            )
            .presentationDetents([.height(340), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var goalsSection: some View {
        Section("Goals") {
            Picker("Weight Goal", selection: $weightGoal) {
                Text("Lose").tag("lose")
                Text("Maintain").tag("maintain")
                Text("Gain").tag("gain")
            }
            .pickerStyle(.segmented)
        }
    }

    private var homeScreenSection: some View {
        Section("Home Screen") {
            Toggle(isOn: $showVitalsOnHome) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Vitals Section")
                    Text("Display health vitals like heart rate, steps, and sleep on the home screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Wearable", selection: preferredWearableBinding) {
                ForEach(WearableDevicePreference.allCases) { wearable in
                    Text(wearable.displayName).tag(wearable)
                }
            }
            .pickerStyle(.menu)
            .accessibilityHint("Changes which Apple Health vitals appear on the Home screen")

            Text(wearableVitalsDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var preferredWearableBinding: Binding<WearableDevicePreference> {
        Binding(
            get: { WearableDevicePreference(rawValue: preferredWearableRaw) ?? .none },
            set: { preferredWearableRaw = $0.rawValue }
        )
    }

    private var wearableVitalsDescription: String {
        switch preferredWearableBinding.wrappedValue {
        case .none:
            return "Shows general activity and sleep data available in Apple Health."
        case .appleWatch:
            return "Prioritizes heart rate, HRV, respiratory rate, blood oxygen, temperature, sleep, steps, and VO2 Max when your Watch provides them."
        case .ouraRing:
            return "Prioritizes Oura-synced heart rate, respiratory rate, sleep, steps, and active energy. Sleep Score is estimated from Apple Health sleep data."
        case .fitbit:
            return "Shows Fitbit-attributed activity, heart, sleep, oxygen, and respiratory data when Fitbit or a compatible sync app writes it to Apple Health."
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            Toggle(isOn: $enableWeeklyWeightReminder) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Weight Reminder")
                    Text("Reminds you to log your weight weekly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: enableWeeklyWeightReminder) { _, newValue in
                updateWeeklyWeightReminder(isEnabled: newValue)
            }

            if enableWeeklyWeightReminder {
                reminderScheduleControls
            }
        }
    }

    private var reminderScheduleControls: some View {
        Group {
            Picker("Day", selection: $reminderWeekday) {
                Text("Sun").tag(1)
                Text("Mon").tag(2)
                Text("Tue").tag(3)
                Text("Wed").tag(4)
                Text("Thu").tag(5)
                Text("Fri").tag(6)
                Text("Sat").tag(7)
            }
            .onChange(of: reminderWeekday) { _, _ in
                scheduleWeeklyWeightReminder()
            }

            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .onChange(of: reminderTime) { _, newTime in
                    updateReminderTime(to: newTime)
                }
                .onAppear(perform: initializeReminderTimePicker)
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            NavigationLink {
                LazySettingsDestination {
                    healthSyncSettingsPage
                }
            } label: {
                Label("Health & Sync", systemImage: "heart.text.square")
            }

            Toggle(isOn: $useStructuredPlanView) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Structured Plan View")
                    Text("Display saved AI plans as interactive cards when structured data is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                LazySettingsDestination {
                    backupDataSettingsPage
                }
            } label: {
                Label("Backup & Data", systemImage: "externaldrive")
            }

            #if DEBUG
            NavigationLink {
                LazySettingsDestination {
                    developerSettingsPage
                }
            } label: {
                Label("Developer", systemImage: "hammer")
            }
            #endif
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                .foregroundColor(AppTheme.textColor)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateMeasurementSystem(to newValue: String) {
        if newValue == "imperial" {
            weightUnit = "lbs"
            distanceUnit = "mi"
            heightUnit = "in"
        } else {
            weightUnit = "kg"
            distanceUnit = "km"
            heightUnit = "cm"
        }

        applyMeasurementSystemChange(newValue)
    }

    private func updateWeeklyWeightReminder(isEnabled: Bool) {
        if isEnabled {
            ReminderService.scheduleIfEnabled()
        } else {
            ReminderService.cancelWeeklyWeightReminder()
        }
    }

    private func scheduleWeeklyWeightReminder() {
        ReminderService.scheduleWeeklyWeightReminder(
            weekday: reminderWeekday,
            hour: reminderHour,
            minute: reminderMinute
        )
    }

    private func updateReminderTime(to newTime: Date) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
        reminderHour = comps.hour ?? 9
        reminderMinute = comps.minute ?? 0
        scheduleWeeklyWeightReminder()
    }

    private func initializeReminderTimePicker() {
        guard let date = Calendar.current.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: Date()
        ) else {
            return
        }

        reminderTime = date
    }

    private func settingsSubpage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()

            Color.clear
                .frame(height: 72)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .id(appTheme)
        .transaction { tx in
            tx.animation = nil
        }
        .listStyle(.insetGrouped)
        .appBackground(AppTheme.gradientSettings)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
    }

    private var healthSyncSettingsPage: some View {
        settingsSubpage(title: "Health & Sync") {
            Section("Tracking") {
                Toggle(isOn: $enableBackgroundRunTracking) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Background Run Tracking")
                        Text("Keep tracking active when Pace & Plates is in the background for better locked-screen cardio accuracy. Requires \"Always\" location access.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: enableBackgroundRunTracking) { _, isEnabled in
                    if isEnabled {
                        requestAlwaysLocationIfNeeded()
                    }
                }

                if enableBackgroundRunTracking && locationAuthorizationStatus != .authorizedAlways {
                    Button("Enable \"Always\" Location Access") {
                        requestAlwaysLocationIfNeeded()
                    }
                    .foregroundStyle(AppTheme.accentColor)
                }

                if enableBackgroundRunTracking {
                    Text(backgroundLocationStatusDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Apple Health") {
                Button {
                    refreshHealthDataNow()
                } label: {
                    HStack(spacing: 10) {
                        if isRefreshingHealthData {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isRefreshingHealthData ? "Refreshing Health Data..." : "Refresh Health Data Now")
                    }
                }
                .disabled(isRefreshingHealthData)

                Text("Imports recent runs and weight entries from Apple Health.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Health Sync", isPresented: $showHealthSyncResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(healthSyncResultMessage)
        }
    }

    private var backupDataSettingsPage: some View {
        settingsSubpage(title: "Backup & Data") {
            Section("Backup") {
                if isProcessingBackup { ProgressView("Processing backup…") }
                Button {
                    confirmExport = true
                } label: {
                    Label("Export Data", systemImage: "square.and.arrow.up")
                }
                .disabled(isProcessingBackup)

                Button {
                    confirmImport = true
                } label: {
                    Label("Import Data", systemImage: "square.and.arrow.down")
                }
                .disabled(isProcessingBackup)
            }

            Section("Data") {
                Button {
                    confirmDedup = true
                } label: {
                    Label("Remove All Duplicates", systemImage: "sparkles")
                        .foregroundStyle(AppTheme.accentColor)
                }

                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    Label("Delete All Data", systemImage: "trash.slash")
                }
            }
            .disabled(isProcessingBackup)

            Section("Privacy") {
                Link(destination: URL(string: "https://paceandplates.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "doc.text")
                }
            }
        }
        // Present from the visible destination, since the Settings root is offscreen.
        .sheet(item: $exportURL, onDismiss: {
            exportURL = nil
            // The share sheet has finished handing the file off; remove the
            // plaintext copy from tmp instead of waiting for the system to purge it.
            if let url = lastExportedBackupURL {
                try? FileManager.default.removeItem(at: url)
                lastExportedBackupURL = nil
            }
        }) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Backup & Data", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Export Data?", isPresented: $confirmExport) {
            Button("Cancel", role: .cancel) {}
            Button("Export") { exportTapped() }
        } message: {
            Text("This creates an unencrypted backup file containing your workouts, runs with GPS routes, body weight history, and AI coach conversations. Only share or store it somewhere you trust.")
        }
        .alert("Import Data?", isPresented: $confirmImport) {
            Button("Cancel", role: .cancel) {}
            Button("Import") { showImporter = true }
        } message: {
            Text("Records from the backup are added to this device. Items that already exist here are kept and not overwritten.")
        }
        .alert("Remove Duplicates?", isPresented: $confirmDedup) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { deduplicateAllData() }
        } message: {
            Text("We will scan workouts, runs, and templates to drop duplicates.")
        }
        .alert("Delete All Data?", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteAllAppData() }
        } message: {
            let cloud = PersistenceController.shared.isCloudBacked
            Text(
                cloud
                    ? "This removes Pace & Plates data from this device and the app's iCloud store. It does not delete workouts or measurements from Apple Health. This action cannot be undone."
                    : "This removes Pace & Plates data from this device. It does not delete workouts or measurements from Apple Health. This action cannot be undone."
            )
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importFrom(url: url)
            case .failure(let err):
                alertMessage = "Import failed: \(err.localizedDescription)"
                showAlert = true
            }
        }
    }

    #if DEBUG
    private var developerSettingsPage: some View {
        settingsSubpage(title: "Developer") {
            Section("Debug") {
                Button {
                    confirmAddSampleData = true
                } label: {
                    Label("Add Sample Data (1 Month)", systemImage: "plus.rectangle.on.folder")
                }

                Button(role: .destructive) {
                    confirmRemoveSampleData = true
                } label: {
                    Label("Remove Sample Data", systemImage: "trash")
                }
            }
        }
        .modifier(DebugSampleDataAlerts(
            confirmAddSampleData: $confirmAddSampleData,
            confirmRemoveSampleData: $confirmRemoveSampleData,
            modelContext: modelContext
        ))
    }
    #endif

    private var heightDisplayValue: String {
        if heightUnit == "in" {
            let totalInches = Int(round(heightValue))
            let feet = max(0, totalInches / 12)
            let inches = max(0, min(11, totalInches % 12))
            return "\(feet)′ \(inches)″"
        }

        return String(format: "%.1f cm", heightValue)
    }

    private var goalWeightDisplayValue: String {
        guard targetWeight > 0 else { return "Not set" }
        let value = targetWeight.formatted(
            .number.precision(.fractionLength(0...1))
        )
        return "\(value) \(weightUnit)"
    }

    // MARK: - Backup actions
    @State private var showImporter: Bool = false
    private struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
    // Bind the share sheet to its file so the first presentation has content.
    @State private var exportURL: IdentifiableURL? = nil
    @State private var lastExportedBackupURL: URL? = nil
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var confirmDeleteAll: Bool = false
    
    private var backgroundLocationStatusDescription: String {
        switch locationAuthorizationStatus {
        case .authorizedAlways:
            return "Location access: Always (ready for background tracking)."
        case .authorizedWhenInUse:
            return "Location access: While Using App. Switch to Always for background runs."
        case .denied:
            return "Location access denied. Enable Location permissions in Settings."
        case .restricted:
            return "Location access restricted by system policy."
        case .notDetermined:
            return "Location access not requested yet."
        @unknown default:
            return "Location access state is unknown."
        }
    }
    
    private func refreshLocationAuthorizationStatus() {
        locationAuthorizationStatus = locationManager.authorizationStatus
    }
    
    private func requestAlwaysLocationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
        refreshLocationAuthorizationStatus()
    }
    
    // MARK: - HealthKit Profile Loading
    private func loadProfileFromHealthKit() {
        Task { @MainActor in
            // Only load if values are not already set
            if age == 0 {
                if let healthAge = try? HealthKitManager.shared.getAge() {
                    age = healthAge
                }
            }
            
            if sex.isEmpty {
                if let healthSex = try? HealthKitManager.shared.getBiologicalSex() {
                    sex = healthSex
                }
            }
            
            if heightValue == 0 {
                if let healthHeight = try? await HealthKitManager.shared.getHeight() {
                    // healthHeight is in inches
                    if heightUnit == "cm" {
                        // Convert inches to cm
                        heightValue = healthHeight * 2.54
                    } else {
                        // Keep as inches
                        heightValue = healthHeight
                    }
                }
            }
        }
    }

    private func refreshHealthDataNow() {
        guard !isRefreshingHealthData else { return }
        isRefreshingHealthData = true
        let expectedPurgeGeneration =
            WearableWorkoutInboxService.localDataPurgeGeneration

        Task { @MainActor in
            do {
                try await HealthKitManager.shared.requestAuthorization()
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)

                let cardioResult = await CardioWorkoutInboxService.sync(
                    context: modelContext,
                    pageLimit: 100
                )
                if let errorMessage = cardioResult.errorMessage {
                    throw NSError(
                        domain: "CardioWorkoutInbox",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: errorMessage]
                    )
                }
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                let weightsInserted = try await importWeightsFromHealth(
                    expectedPurgeGeneration: expectedPurgeGeneration
                )
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)

                let now = Date().timeIntervalSince1970
                runsLastHealthImportAt = now
                weightLastHealthImportAt = now

                healthSyncResultMessage = "Cardio inbox: +\(cardioResult.inserted) ready to review. Weights: +\(weightsInserted) imported."
            } catch is CancellationError {
                isRefreshingHealthData = false
                return
            } catch {
                healthSyncResultMessage = "Health refresh failed: \(error.localizedDescription)"
            }

            isRefreshingHealthData = false
            showHealthSyncResult = true
        }
    }

    @MainActor
    private func ensureHealthImportIsCurrent(_ generation: Int) throws {
        guard WearableWorkoutInboxService
            .isCurrentLocalDataPurgeGeneration(generation) else {
            throw CancellationError()
        }
    }

    @MainActor
    private func importRunsFromHealth(
        limit: Int = 100,
        expectedPurgeGeneration: Int
    ) async throws -> (
        inserted: Int,
        linked: Int,
        skipped: Int,
        unlinked: Int
    ) {
        let changes = try await HealthKitManager.shared.fetchCardioWorkoutChanges(resetAnchor: false, limit: limit)
        try ensureHealthImportIsCurrent(expectedPurgeGeneration)
        let workouts = changes.added
        var allRuns = try modelContext.fetch(FetchDescriptor<RunningSession>())
        var existingUUIDs = Set(allRuns.compactMap(\.healthWorkoutUUID).filter { !$0.isEmpty })

        let unit = distanceUnit
        var inserted = 0
        var linked = 0
        var skipped = 0
        var unlinked = 0

        let replacements = SameBatchCardioReplacementReconciler.matches(
            changes: changes,
            addedWorkouts: workouts,
            existingSessions: allRuns.compactMap {
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

        let deletedSet = Set(changes.deletedUUIDs)
            .subtracting(replacedDeletedUUIDs)
        if !deletedSet.isEmpty {
            for run in allRuns where (run.healthWorkoutUUID.map { deletedSet.contains($0) } ?? false) {
                // Preserve the app-local activity and its notes/route. Health
                // deletion only removes the link; it never deletes app data.
                run.healthWorkoutUUID = nil
                unlinked += 1
            }
            existingUUIDs = Set(allRuns.compactMap(\.healthWorkoutUUID).filter { !$0.isEmpty })
        }

        for workout in workouts {
            let uuidStr = workout.uuid.uuidString
            if existingUUIDs.contains(uuidStr) {
                skipped += 1
                continue
            }

            guard let activityType = activityKey(for: workout.workoutActivityType) else {
                skipped += 1
                continue
            }

            let meters = HealthKitManager.recordedDistanceMeters(for: workout)
            let distanceValue: Double = (unit == "mi") ? (meters / 1609.34) : (meters / 1000.0)
            let endDate = workout.endDate
            let duration = workout.duration
            let calories = try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout)
            try ensureHealthImportIsCurrent(expectedPurgeGeneration)

            if let replacement = replacementByAddedUUID[uuidStr],
               let existing = allRuns.first(where: {
                   $0.id == replacement.sessionID
               }) {
                existing.healthWorkoutUUID = uuidStr
                existing.date = endDate
                existing.distance = distanceValue
                existing.distanceUnit = unit
                existing.duration = duration
                existing.activityType = activityType
                if let calories, calories > 0 {
                    existing.calories = calories
                }

                // A Health replacement is authoritative. Refresh corrected
                // metrics while retaining old values when Health omits one.
                let averageHeartRate = try? await HealthKitManager.shared
                    .averageHeartRate(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averageHeartRate {
                    existing.avgHeartRate = value
                }
                let maxHeartRate = try? await HealthKitManager.shared
                    .maxHeartRate(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = maxHeartRate {
                    existing.maxHeartRate = value
                }
                let minHeartRate = try? await HealthKitManager.shared
                    .minHeartRate(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = minHeartRate {
                    existing.minHeartRate = value
                }
                let averageCadence = try? await HealthKitManager.shared
                    .averageCadence(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averageCadence {
                    existing.avgCadence = value
                }
                let maxCadence = try? await HealthKitManager.shared
                    .maxCadence(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = maxCadence {
                    existing.maxCadence = value
                }
                let averageStrideLength = try? await HealthKitManager.shared
                    .averageStrideLength(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averageStrideLength {
                    existing.avgStrideLength = value
                }
                let averageVerticalOscillation = try? await HealthKitManager
                    .shared.averageVerticalOscillation(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averageVerticalOscillation {
                    existing.verticalOscillation = value
                }
                let averageGroundContactTime = try? await HealthKitManager
                    .shared.averageGroundContactTime(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averageGroundContactTime {
                    existing.groundContactTime = value
                }
                let averagePower = try? await HealthKitManager.shared
                    .averagePower(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = averagePower {
                    existing.avgPower = value
                }
                let maxPower = try? await HealthKitManager.shared
                    .maxPower(for: workout)
                try ensureHealthImportIsCurrent(expectedPurgeGeneration)
                if let value = maxPower {
                    existing.maxPower = value
                }
                linked += 1
            } else if let similar = findSimilarRun(
                in: allRuns,
                endDate: endDate,
                duration: duration,
                distance: distanceValue,
                unit: unit
            ) {
                similar.healthWorkoutUUID = uuidStr
                similar.activityType = activityType
                if let calories, calories > 0 {
                    similar.calories = calories
                }
                linked += 1
            } else {
                let run = RunningSession(
                    date: endDate,
                    distance: distanceValue,
                    distanceUnit: unit,
                    duration: duration,
                    calories: (calories ?? 0) > 0 ? calories : nil,
                    notes: nil,
                    locations: nil,
                    healthWorkoutUUID: uuidStr,
                    activityType: activityType
                )
                modelContext.insert(run)
                allRuns.append(run)
                inserted += 1
            }

            existingUUIDs.insert(uuidStr)
        }

        try ensureHealthImportIsCurrent(expectedPurgeGeneration)
        if inserted > 0 || linked > 0 || unlinked > 0 {
            try modelContext.save()
        }

        try ensureHealthImportIsCurrent(expectedPurgeGeneration)
        HealthKitManager.shared.persistCardioWorkoutAnchor(changes.newAnchor)

        return (inserted, linked, skipped, unlinked)
    }

    @MainActor
    private func importWeightsFromHealth(
        expectedPurgeGeneration: Int
    ) async throws -> Int {
        let history = try await HealthKitManager.shared.getWeightHistory()
        try ensureHealthImportIsCurrent(expectedPurgeGeneration)
        let existing = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        var existingDays = Set(existing.map { Calendar.current.startOfDay(for: $0.date) })

        // Keep only the LATEST sample per day within the imported batch so an
        // evening correction wins over a morning weigh-in (getWeightHistory is oldest-first).
        let purgeCutoff =
            WearableWorkoutInboxService.localDataPurgeCutoffDate
        let latestPerDay = HealthKitManager.latestWeightSamplesPerDay(
            history.filter { item in
                purgeCutoff.map { item.date > $0 } ?? true
            }
        )

        var inserted = 0
        for item in latestPerDay {
            let day = Calendar.current.startOfDay(for: item.date)
            if existingDays.contains(day) { continue }

            let value: Double
            let unit: String
            if weightUnit == "kg" {
                value = item.weightInPounds / 2.20462
                unit = "kg"
            } else {
                value = item.weightInPounds
                unit = "lbs"
            }

            modelContext.insert(WeightEntry(date: item.date, weight: value, weightUnit: unit))
            existingDays.insert(day)
            inserted += 1
        }

        try ensureHealthImportIsCurrent(expectedPurgeGeneration)
        if inserted > 0 {
            try modelContext.save()
        }

        return inserted
    }

    private func findSimilarRun(
        in runs: [RunningSession],
        endDate: Date,
        duration: TimeInterval,
        distance: Double,
        unit: String
    ) -> RunningSession? {
        return runs.first {
            HealthKitManager.runsAreSimilar(
                aDate: $0.date, aDuration: $0.duration, aDistance: $0.distance, aUnit: $0.distanceUnit,
                bDate: endDate, bDuration: duration, bDistance: distance, bUnit: unit
            )
        }
    }

    private func activityKey(for type: HKWorkoutActivityType) -> String? {
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
    
    private func exportTapped() {
        guard !isProcessingBackup else { return }
        isProcessingBackup = true
        Task { @MainActor in
            defer { isProcessingBackup = false }
            do {
                let url = try await DataBackupService.exportAll(context: modelContext)
                lastExportedBackupURL = url
                exportURL = IdentifiableURL(url: url)
            } catch {
                alertMessage = "Export failed: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func importFrom(url: URL) {
        guard !isProcessingBackup else { return }
        isProcessingBackup = true
        Task { @MainActor in
            defer { isProcessingBackup = false }
            do {
                try await DataBackupService.import(from: url, context: modelContext)
                PersistenceController.shared.reconcileExerciseLibraryIfNeeded(force: true)
                alertMessage = "Import complete"
                Haptics.playImpact(.light)
            } catch {
                alertMessage = "Import failed: \(error.localizedDescription)"
            }
            showAlert = true
        }
    }

    private func deduplicateAllData() {
        do {
            var totalRemoved = 0
            
            // Deduplicate runs
            let allRuns = try modelContext.fetch(FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\.date, order: .forward)]))
            var runsToKeep: [RunningSession] = []
            var duplicateRuns: [RunningSession] = []
            
            for run in allRuns {
                let isDuplicate = runsToKeep.contains { existing in
                    DataBackupService.areRunningSessionsDefiniteDuplicates(existing, run)
                }
                
                if isDuplicate {
                    duplicateRuns.append(run)
                } else {
                    runsToKeep.append(run)
                }
            }
            duplicateRuns.forEach { modelContext.delete($0) }
            totalRemoved += duplicateRuns.count
            
            // Deduplicate weight entries
            let allWeights = try modelContext.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .forward)]))
            var weightsToKeep: [WeightEntry] = []
            var duplicateWeights: [WeightEntry] = []
            
            for weight in allWeights {
                let isDuplicate = weightsToKeep.contains { existing in
                    DataBackupService.areWeightEntriesDefiniteDuplicates(existing, weight)
                }
                
                if isDuplicate {
                    duplicateWeights.append(weight)
                } else {
                    weightsToKeep.append(weight)
                }
            }
            duplicateWeights.forEach { modelContext.delete($0) }
            totalRemoved += duplicateWeights.count
            
            // Deduplicate workout sessions
            let allSessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .forward)]))
            var sessionsToKeep: [WorkoutSession] = []
            var duplicateSessions: [WorkoutSession] = []
            
            for session in allSessions {
                let isDuplicate = sessionsToKeep.contains { existing in
                    DataBackupService.areWorkoutSessionsDefiniteDuplicates(existing, session)
                }
                
                if isDuplicate {
                    duplicateSessions.append(session)
                } else {
                    sessionsToKeep.append(session)
                }
            }
            duplicateSessions.forEach { modelContext.delete($0) }
            totalRemoved += duplicateSessions.count
            
            // Deduplicate exercises
            let removedExercises = PersistenceController.shared.deduplicateExerciseDefinitions()
            totalRemoved += removedExercises
            
            try modelContext.save()
            
            if totalRemoved == 0 {
                alertMessage = "No duplicates found"
            } else {
                alertMessage = "Removed \(totalRemoved) duplicate(s): \(duplicateRuns.count) runs, \(duplicateWeights.count) weights, \(duplicateSessions.count) workouts, \(removedExercises) exercises"
            }
            showAlert = true
        } catch {
            alertMessage = "Failed to remove duplicates: \(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Data deletion
    private func deleteAllLocal() {
        do {
            try deleteAllEntities()
            alertMessage = "All Pace & Plates data has been removed. Apple Health data was not changed."
            showAlert = true
        } catch {
            alertMessage = "Delete failed: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func deleteAllAppData() {
        // With Cloud Sync enabled, deleting from the context propagates to iCloud.
        deleteAllLocal()
    }

    private func deleteAllEntities() throws {
        // Prevent a Health query that is currently suspended on metric reads
        // from repopulating SwiftData after this app-local purge completes.
        WearableWorkoutInboxService.prepareForLocalDataPurge()

        // Delete children first, then parents
        let logItems = try modelContext.fetch(FetchDescriptor<ExerciseLog>())
        logItems.forEach { modelContext.delete($0) }
        let runPlanSessions = try modelContext.fetch(FetchDescriptor<RunningPlanSession>())
        runPlanSessions.forEach { modelContext.delete($0) }
        let templateExercises = try modelContext.fetch(FetchDescriptor<TemplateExercise>())
        templateExercises.forEach { modelContext.delete($0) }
        let inboxItems = try modelContext.fetch(FetchDescriptor<HealthWorkoutInboxItem>())
        inboxItems.forEach { modelContext.delete($0) }
        let cardioInboxItems = try modelContext.fetch(FetchDescriptor<CardioWorkoutInboxItem>())
        cardioInboxItems.forEach { modelContext.delete($0) }

        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        sessions.forEach { modelContext.delete($0) }
        let templates = try modelContext.fetch(FetchDescriptor<WorkoutTemplate>())
        templates.forEach { modelContext.delete($0) }
        let runPlans = try modelContext.fetch(FetchDescriptor<RunningPlan>())
        runPlans.forEach { modelContext.delete($0) }
        let conversations = try modelContext.fetch(FetchDescriptor<AIConversation>())
        conversations.forEach { modelContext.delete($0) }

        // Keep preloaded library exercises; only delete user-defined
        let defs = try modelContext.fetch(FetchDescriptor<ExerciseDefinition>())
        defs.filter { $0.isUserDefined }.forEach { modelContext.delete($0) }
        let runs = try modelContext.fetch(FetchDescriptor<RunningSession>())
        runs.forEach { modelContext.delete($0) }
        let weights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        weights.forEach { modelContext.delete($0) }
        try modelContext.save()
        WearableWorkoutInboxService.completeLocalDataPurge()
        RunTracker.shared.pauseRun()
        RunTracker.shared.clearCurrentRun(resetActivityType: true)
        LiveActivityManager.shared.end()
        // The reverse-geocode cache is derived from run start points; drop it too.
        Task { await MapSearchService.shared.clearAll() }
    }
}

#if DEBUG
private struct DebugSampleDataAlerts: ViewModifier {
    @Binding var confirmAddSampleData: Bool
    @Binding var confirmRemoveSampleData: Bool
    let modelContext: ModelContext

    func body(content: Content) -> some View {
        content
            .alert("Add Sample Data?", isPresented: $confirmAddSampleData) {
                Button("Cancel", role: .cancel) {}
                Button("Add Data") {
                    DebugDataGenerator.generateSampleData(context: modelContext)
                }
            } message: {
                Text("This will add 1 month of realistic sample data including workouts and cardio sessions (no weight entries).")
            }
            .alert("Remove Sample Data?", isPresented: $confirmRemoveSampleData) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    DebugDataGenerator.removeSampleData(context: modelContext)
                }
            } message: {
                Text("This will remove only the sample data that was added via 'Add Sample Data'. Your real data will not be affected.")
            }
    }
}
#endif

private struct LazySettingsDestination<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}

// MARK: - Unit conversion helpers
extension SettingsView {
    private func applyMeasurementSystemChange(_ system: String) {
        // Convert stored data so measurements remain the same in the new unit system
        // ExerciseLog weights
        if let logs: [ExerciseLog] = try? modelContext.fetch(FetchDescriptor<ExerciseLog>()) {
            for log in logs {
                if system == "imperial", log.weightUnit == "kg" {
                    log.weight = log.weight * 2.20462
                    log.weightUnit = "lbs"
                } else if system == "metric", log.weightUnit == "lbs" {
                    log.weight = log.weight / 2.20462
                    log.weightUnit = "kg"
                }
            }
        }
        // WeightEntry entries
        if let weights: [WeightEntry] = try? modelContext.fetch(FetchDescriptor<WeightEntry>()) {
            for entry in weights {
                if system == "imperial", entry.weightUnit == "kg" {
                    entry.weight = entry.weight * 2.20462
                    entry.weightUnit = "lbs"
                } else if system == "metric", entry.weightUnit == "lbs" {
                    entry.weight = entry.weight / 2.20462
                    entry.weightUnit = "kg"
                }
            }
        }
        // RunningSession distances
        if let runs: [RunningSession] = try? modelContext.fetch(FetchDescriptor<RunningSession>()) {
            for run in runs {
                if system == "imperial", run.distanceUnit == "km" {
                    run.distance = run.distance / 1.60934 // km -> mi
                    run.distanceUnit = "mi"
                } else if system == "metric", run.distanceUnit == "mi" {
                    run.distance = run.distance * 1.60934 // mi -> km
                    run.distanceUnit = "km"
                }
            }
        }
        // Profile height value stored in AppStorage
        if system == "imperial" {
            heightValue = (heightValue / 2.54).rounded() // cm -> in, nearest inch
            heightUnit = "in"
            // Convert goal weight kg -> lbs (1 dec)
            targetWeight = ((targetWeight * 2.20462) * 10).rounded() / 10.0
        } else {
            heightValue = ((heightValue * 2.54) * 10).rounded() / 10.0 // in -> cm, 1 dec
            heightUnit = "cm"
            // Convert goal weight lbs -> kg (1 dec)
            targetWeight = ((targetWeight / 2.20462) * 10).rounded() / 10.0
        }
        _ = PersistenceSave.commit(modelContext, action: "save changes")
    }

    // MARK: - Height Picker
    private struct GoalWeightPickerSheet: View {
        let weightUnit: String
        @Binding var targetWeight: Double
        @Environment(\.dismiss) private var dismiss
        @State private var wholeValue: Int = 180
        @State private var decimalValue: Int = 0

        private var allowedWholeValues: ClosedRange<Int> {
            weightUnit == "kg" ? 25...320 : 55...700
        }

        var body: some View {
            NavigationStack {
                HStack(spacing: 0) {
                    Picker("Weight", selection: $wholeValue) {
                        ForEach(allowedWholeValues, id: \.self) { value in
                            Text("\(value) \(weightUnit)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("Decimal", selection: $decimalValue) {
                        ForEach(0...9, id: \.self) { value in
                            Text(".\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 220)
                .onAppear(perform: loadValue)
                .onChange(of: wholeValue) { _, _ in applyValue() }
                .onChange(of: decimalValue) { _, _ in applyValue() }
                .navigationTitle("Goal Weight")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        private func loadValue() {
            let fallback = weightUnit == "kg" ? 82.0 : 180.0
            let rawValue = targetWeight > 0 ? targetWeight : fallback
            let lower = Double(allowedWholeValues.lowerBound)
            let upper = Double(allowedWholeValues.upperBound) + 0.9
            let clamped = min(max(rawValue, lower), upper)
            let rounded = (clamped * 10).rounded() / 10
            let wholePart = Int(floor(rounded))
            wholeValue = min(
                max(wholePart, allowedWholeValues.lowerBound),
                allowedWholeValues.upperBound
            )
            decimalValue = min(
                max(
                    Int(
                        ((rounded - Double(wholeValue)) * 10)
                            .rounded()
                    ),
                    0
                ),
                9
            )
            applyValue()
        }

        private func applyValue() {
            targetWeight =
                Double(wholeValue) + (Double(decimalValue) / 10)
        }
    }

    private struct HeightPickerSheet: View {
        @Binding var heightUnit: String
        @Binding var heightValue: Double
        @Environment(\.dismiss) private var dismiss
        @State private var feet: Int = 5
        @State private var inches: Int = 9
        @State private var cmInt: Int = 175
        @State private var cmDec: Int = 0
        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    if heightUnit == "in" {
                        HStack(spacing: 0) {
                            Picker("Feet", selection: $feet) { ForEach(3...8, id: \.self) { Text("\($0) ft") } }
                                .pickerStyle(.wheel)
                            Picker("Inches", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in") } }
                                .pickerStyle(.wheel)
                        }
                        .frame(height: 200)
                        .onChange(of: feet) { _,_ in applyImperial() }
                        .onChange(of: inches) { _,_ in applyImperial() }
                        .onAppear { loadImperial() }
                    } else {
                        HStack(spacing: 0) {
                            Picker("Centimeters", selection: $cmInt) { ForEach(120...230, id: \.self) { Text("\($0)") } }
                                .pickerStyle(.wheel)
                            Picker("Decimal", selection: $cmDec) { ForEach(0...9, id: \.self) { Text(".\($0)") } }
                                .pickerStyle(.wheel)
                        }
                        .frame(height: 200)
                        .onChange(of: cmInt) { _,_ in applyMetric() }
                        .onChange(of: cmDec) { _,_ in applyMetric() }
                        .onAppear { loadMetric() }
                    }
                    Spacer(minLength: 0)
                }
                .navigationTitle("Height")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        private func loadImperial() {
            let storedHeight = heightValue > 0 ? heightValue : 68.0
            let f = Int(floor(storedHeight / 12.0))
            let i = Int(round(storedHeight - Double(f) * 12.0))
            feet = max(3, min(8, f)); inches = max(0, min(11, i))
        }
        private func applyImperial() { heightValue = Double(max(0, feet)) * 12.0 + Double(max(0, min(11, inches))) }
        private func loadMetric() {
            let v = heightValue > 0 ? heightValue : 175.0
            cmInt = Int(floor(v)); cmDec = min(9, max(0, Int(round((v - floor(v)) * 10))))
        }
        private func applyMetric() { heightValue = Double(cmInt) + Double(cmDec) / 10.0 }
    }
}
