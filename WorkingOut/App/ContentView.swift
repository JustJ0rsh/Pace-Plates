import SwiftUI
import GameKit
import SwiftData
import CoreData

struct ContentView: View {
    let persistenceController = PersistenceController.shared // Need access to this
    private let launchConfiguration = AppLaunchConfiguration.current
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didShowTutorial") private var didShowTutorial: Bool = false
    @AppStorage("didCompleteProfileSetup") private var didCompleteProfileSetup: Bool = false
    @State private var showTutorial: Bool = false
    @State private var showRecoveredRun = false
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("heightUnit") private var heightUnit: String = "in"
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @State private var selectedTab = AppLaunchConfiguration.current.initialTabSelection
    @Binding var importedWorkout: SharedWorkoutSession?
    @Binding var importedCoachProgram: CoachImportRequest?
    @StateObject private var workoutSaveRecoveries = WorkoutSaveRecoveryStore.shared
    @State private var presentedWorkoutRecoveryID: UUID?
    @State private var showWorkoutRecoveries = false
    @State private var restoreError: String?
    
    // Error handling moved to App level
    // @State private var showImportError: Bool = false
    // @State private var importErrorMessage: String = ""

    var body: some View {
        Group {
            if persistenceController.isPreparingStorage {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(persistenceController.isContinuingLocally ? "Opening local history…" : "Checking requested iCloud recovery…")
                    Text("Your saved history stays on this device. You can skip the cloud check and continue locally.")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Button("Continue Without iCloud Check") { persistenceController.continueWithoutCloudCheck() }
                        .disabled(persistenceController.isContinuingLocally)
                        .accessibilityIdentifier("storage.skipCloudCheck")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.backgroundColor)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("storage.preparing")
            } else {
            #if DEBUG
            if launchConfiguration.usesIsolatedStore && launchConfiguration.fixtureName == "recovery_lifecycle" {
                RecoveryLifecycleAcceptanceView()
            } else if launchConfiguration.usesIsolatedStore && launchConfiguration.fixtureName == "profile_reinstall_checks" {
                profileReinstallProbe
            } else if launchConfiguration.isUITest && ["user_record_map_probe", "active_record_map_probe"].contains(launchConfiguration.fixtureName ?? "") {
                ActualHistoryCloudVerificationView()
            } else if ProcessInfo.processInfo.environment["PP_USER_CLOUD_VERIFY"] == "1", persistenceController.storageError == nil {
                ActualHistoryCloudVerificationView()
            } else if let runID = launchConfiguration.liveCloudRunID {
                LiveCloudSyncVerificationView(runID: runID, phase: launchConfiguration.liveCloudPhase)
            } else if launchConfiguration.isUITest && launchConfiguration.fixtureName == "user_history_restore_checks" {
                UserHistoryRestorationVerificationView()
            } else if launchConfiguration.usesIsolatedStore && ["storage_integration_checks", "icloud_restoration_checks"].contains(launchConfiguration.fixtureName ?? "") {
                StorageIntegrationAcceptanceView()
            } else if let error = persistenceController.storageError {
                storageRecovery(error)
            } else {
                mainContent
            }
            #else
            if let error = persistenceController.storageError {
                storageRecovery(error)
            } else {
                mainContent
            }
            #endif
            }
        }
        .task { await persistenceController.prepareStorageIfNeeded() }
    }

    #if DEBUG
    @ViewBuilder private var profileReinstallProbe: some View {
        #if targetEnvironment(simulator)
        UserProfileReinstallAcceptanceView()
        #else
        Text("Profile lifecycle verification is Simulator-only.")
        #endif
    }
    #endif

    private func storageRecovery(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
            Text("Some history is unavailable").font(.title.bold())
            Text("You can keep using Pace & Plates with new local history. Older entries will not appear in that history, but their original files will be kept. New entries will be saved on this device.")
            Button("Continue with New Local History") { persistenceController.continueWithNewLocalHistory() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("storage.continueLocal")
            DisclosureGroup("Recovery details") { Text(error).font(.caption) }
            Text("Keep the app installed to retain both histories. Export a backup before recovering or combining older records.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundColor)
        .preferredColorScheme(appTheme.preferredColorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storage.recovery")
    }

    // Do not construct normal views or start their import/recovery tasks while
    // storage is unavailable. A visual overlay does not fence background work.
    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            // Left side - Use Group to prevent unnecessary NavigationStack recreation
            // Nav bar buttons set their color explicitly via AppTheme.toolbarButtonColor
            // in each view's toolbar — inherited tints are dropped by NavigationStack
            // toolbars on tab revisits, which made button colors inconsistent.
            NavigationStack {
                HomeView()
                    .safeAreaInset(edge: .top) {
                        VStack(spacing: 0) {
                            if persistenceController.cloudHistoryStatus.isEnabled,
                               persistenceController.cloudHistoryStatus.phase != .importConfirmed {
                                CloudHistoryStatusBanner(controller: persistenceController)
                            }
                            if let restoreError {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading) {
                                        Text("A history restore needs attention").font(.subheadline.bold())
                                        Text(restoreError).font(.caption)
                                        Text("You can continue using your available history.").font(.caption)
                                    }
                                    Button("Dismiss") { self.restoreError = nil }
                                        .accessibilityIdentifier("history.restore.dismiss")
                                }
                                .padding(12).background(.regularMaterial)
                                .accessibilityIdentifier("history.restore.notice")
                            }
                        }
                    }
            }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { WorkoutLogView() }
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
                .tag(1)

            NavigationStack { CoachHomeView() }
                .tabItem { Label("Coach", systemImage: "sparkles.rectangle.stack.fill") }
                .tag(2)

            // Right side
            NavigationStack { RunLogView() }
                .tabItem { Label("Runs", systemImage: "figure.run") }
                .tag(3)

            NavigationStack { WeightLogView() }
                .tabItem { Label("Weight", systemImage: "scalemass.fill") }
                .tag(4)
        }
        #if DEBUG
        .overlay(alignment: .top) {
            if launchConfiguration.isUITest && launchConfiguration.fixtureName == "optimization_checks" {
                OptimizationRegressionChecksView()
            }
            if launchConfiguration.isUITest && launchConfiguration.fixtureName == "coach_checks" {
                CoachRegressionChecksView()
            }
            if launchConfiguration.isUITest && launchConfiguration.fixtureName == "coach_calendar_checks" {
                CoachCalendarRegressionChecksView()
            }
            #if targetEnvironment(simulator)
            if launchConfiguration.usesNaturalProfileForTesting {
                Text(UserProfileStore.shared.naturalProfileTestStatus)
                    .font(.caption2)
                    .accessibilityIdentifier("readiness.syntheticProfile")
                    .allowsHitTesting(false)
            }
            #endif
        }
        #endif
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .tint(AppTheme.accentColor)
        .preferredColorScheme(appTheme.preferredColorScheme)
        .toolbarBackground(AppTheme.backgroundColor, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .tabBar)
        .modelContainer(persistenceController.container)
        .id(persistenceController.storageGeneration)
        .onReceive(NotificationCenter.default.publisher(for: WorkoutSaveRecovery.notification)) { notification in
            if let recovery = notification.object as? WorkoutSaveRecovery {
                if !showWorkoutRecoveries { presentedWorkoutRecoveryID = recovery.id }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !workoutSaveRecoveries.pending.isEmpty {
                Button {
                    showWorkoutRecoveries = true
                } label: {
                    Label("Retry unsaved workouts (\(workoutSaveRecoveries.pending.count))", systemImage: "arrow.clockwise.circle")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                .background(.regularMaterial)
                .accessibilityIdentifier("workout.saveRecovery")
            }
        }
        .sheet(isPresented: $showWorkoutRecoveries) {
            NavigationStack {
                List(workoutSaveRecoveries.pending) { recovery in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recovery.title.isEmpty ? "Workout" : recovery.title).font(.headline)
                        Text(recovery.message).font(.caption)
                        Button("Retry Save") { workoutSaveRecoveries.retry(id: recovery.id) }
                    }
                }
                .navigationTitle("Unsaved Workouts")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showWorkoutRecoveries = false }
                    }
                }
            }
        }
        .alert("Workout Save Failed", isPresented: Binding(
            get: { presentedWorkoutRecoveryID != nil },
            set: { if !$0 { presentedWorkoutRecoveryID = nil } }
        )) {
            Button("Retry") {
                if let id = presentedWorkoutRecoveryID { workoutSaveRecoveries.retry(id: id) }
            }
            Button("Later", role: .cancel) { presentedWorkoutRecoveryID = nil }
        } message: {
            Text((workoutSaveRecoveries.recovery(id: presentedWorkoutRecoveryID)?.message ?? "") + " Your draft remains available under Retry unsaved workouts. Retry before closing the app.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)) { _ in
            persistenceController.reconcileExerciseLibraryIfNeeded()
        }
        .task {
            if persistenceController.isCoachLocal {
                do {
                    try CoachRepository(context: persistenceController.container.mainContext).recoverPhotoImports()
                    try await DataBackupService.resumePendingRestores(context: persistenceController.container.mainContext)
                }
                catch { restoreError = error.localizedDescription }
            }
            showRecoveredRun = await RunTracker.shared.restoreInterruptedRun(context: persistenceController.container.mainContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { RunTracker.shared.checkpointRun(force: true) }
        }
        .alert("Recovered unfinished activity", isPresented: $showRecoveredRun) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your activity was recovered and is paused. Resume or save it from Home or Runs. Time while the app was unavailable hasn't been counted.")
        }
        .onAppear {
            AppTheme.applyGlobalTheme()
            reconcileLiveActivities()
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                Task { @MainActor in
                    await HealthKitManager.shared.refreshAuthorizationState()
                }
                HealthKitManager.shared.startWorkoutChangeObservationIfNeeded()
                AIProviderManager.cleanUpLegacyOpenRouterArtifacts()
                DataBackupService.removeStaleExportFiles()
            }
            persistenceController.reconcileExerciseLibraryIfNeeded()
            TrainingPlanService.shared.syncRunningPlans(
                context: persistenceController.container.mainContext
            )
            // Ensure legacy arm exercises are reclassified to Biceps/Triceps
            // (idempotent)

            #if DEBUG
            DebugDataGenerator.hideLegacySampleMarkers(context: persistenceController.container.mainContext)
            if let fixtureName = launchConfiguration.fixtureName {
                DebugDataGenerator.generateUITestFixture(
                    named: fixtureName,
                    context: persistenceController.container.mainContext
                )
            }
            #endif
            
            
            // Seed built-in workout templates (idempotent)
            Task { @MainActor in
                do {
                    try await TemplateSeeder.shared.seedBuiltInTemplates(
                        context: persistenceController.container.mainContext
                    )
                } catch {
                    print("❌ Failed to seed built-in templates: \(error)")
                }
            }

            let userProfile = UserProfileStore.shared
            userProfile.retryLoadingIfUnavailable()
            userProfile.restoreUnitPreferences()
            // Check if user needs to see onboarding
            // Show onboarding if: 
            // 1. They haven't completed profile setup AND
            // 2. They haven't filled out basic profile info (age, height)
            if launchConfiguration.shouldShowOnboardingForTesting {
                didCompleteProfileSetup = false
                didShowTutorial = false
                showTutorial = true
            } else if launchConfiguration.shouldSkipAutomationSideEffects
                && !launchConfiguration.usesNaturalProfileForTesting {
                didCompleteProfileSetup = true
                didShowTutorial = true
                showTutorial = false
            } else {
                let hasProfileData = userProfile.hasBasicProfile
                if !userProfile.isAvailable {
                    showTutorial = false
                } else if !didCompleteProfileSetup && !hasProfileData {
                    showTutorial = true
                } else {
                    // If onboarding was completed or profile data exists, mark as complete
                    didCompleteProfileSetup = true
                    didShowTutorial = true

                }
            }
            
            // Schedule weekly reminders if enabled
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                ReminderService.scheduleIfEnabled()
            }

            // No banner; we'll prompt for HK when appropriate
            // Align unit preferences to the global measurement selection
            if userProfile.isAvailable {
                // Read the restored preference immediately; AppStorage may still
                // hold its registered fallback during this first render.
                let restoredSystem = UserDefaults.standard.string(forKey: "measurementSystem") ?? measurementSystem
                measurementSystem = restoredSystem
                if restoredSystem == "imperial" {
                    if weightUnit != "lbs" { weightUnit = "lbs" }
                    if distanceUnit != "mi" { distanceUnit = "mi" }
                    if heightUnit != "in" { heightUnit = "in" }
                } else {
                    if weightUnit != "kg" { weightUnit = "kg" }
                    if distanceUnit != "km" { distanceUnit = "km" }
                    if heightUnit != "cm" { heightUnit = "cm" }
                }
            }

            // Ensure the Game Center access point dot is hidden by default
            GKAccessPoint.shared.isActive = false
        }
        .onChange(of: appTheme) { _, _ in
            AppTheme.applyGlobalTheme()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            reconcileLiveActivities()
            TrainingPlanService.shared.reconcileTrackedRuns(
                context: persistenceController.container.mainContext
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            LiveActivityManager.shared.end()
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView(onFinish: {
                finishOnboarding()
            })
            .interactiveDismissDisabled()
        }

        .sheet(item: $importedWorkout) { session in
            WorkoutImportView(sharedSession: session)
        }
        .sheet(item: $importedCoachProgram) { request in
            NavigationStack {
                CoachPlanImportView(text: request.text)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { importedCoachProgram = nil } } }
            }
        }

    }
}

extension ContentView {
    private var hasRecoverableRun: Bool {
        let tracker = RunTracker.shared
        return tracker.isRunning || (tracker.duration > 0 && tracker.startDate != nil)
    }

    private func reconcileLiveActivities() {
        guard !launchConfiguration.shouldSkipAutomationSideEffects else { return }
        LiveActivityManager.shared.reconcileActivities(hasRecoverableRun: hasRecoverableRun)
    }

    @MainActor
    private func finishOnboarding() {
        didShowTutorial = true
        didCompleteProfileSetup = true
        showTutorial = false
    }

    // Removed debug-only sample run feature and top banner
}

#Preview {
    ContentView(importedWorkout: .constant(nil), importedCoachProgram: .constant(nil))
        // Provide a container specifically for the preview
        .modelContainer(PersistenceController.preview.container)
} 
