import SwiftUI
import GameKit
import SwiftData
import HealthKit

struct ContentView: View {
    let persistenceController = PersistenceController.shared // Need access to this
    private let launchConfiguration = AppLaunchConfiguration.current
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didShowTutorial") private var didShowTutorial: Bool = false
    @AppStorage("didCompleteProfileSetup") private var didCompleteProfileSetup: Bool = false
    @AppStorage("age") private var age: Int = 0
    @AppStorage("heightValue") private var heightValue: Double = 0
    @AppStorage("didShowHealthAccessIssueAlert") private var didShowHealthAccessIssueAlert: Bool = false
    @State private var showTutorial: Bool = false
    @State private var healthAuthError: String? = nil
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("heightUnit") private var heightUnit: String = "in"
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @State private var selectedTab = AppLaunchConfiguration.current.initialTabSelection
    @Binding var importedWorkout: SharedWorkoutSession?
    
    // Error handling moved to App level
    // @State private var showImportError: Bool = false
    // @State private var importErrorMessage: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            // Left side - Use Group to prevent unnecessary NavigationStack recreation
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            
            NavigationStack { WorkoutLogView() }
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
                .tag(1)
            
            NavigationStack { AIPlannerView() }
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(2)
            
            // Right side
            NavigationStack { RunLogView() }
                .tabItem { Label("Runs", systemImage: "figure.run") }
                .tag(3)
            
            NavigationStack { WeightLogView() }
                .tabItem { Label("Weight", systemImage: "scalemass.fill") }
                .tag(4)
        }
        .background(AppTheme.backgroundColor.ignoresSafeArea())
        .tint(AppTheme.accentColor)
        .preferredColorScheme(appTheme.preferredColorScheme)
        .toolbarBackground(AppTheme.backgroundColor, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .tabBar)
        .modelContainer(persistenceController.container)
        .onAppear {
            AppTheme.applyGlobalTheme()
            reconcileLiveActivities()
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                Task { @MainActor in
                    await HealthKitManager.shared.refreshAuthorizationState()
                }
                HealthKitManager.shared.startWorkoutChangeObservationIfNeeded()
                AIProviderManager.bootstrapOpenRouterKeyIfAvailable()
            }
            // Seed + cleanup the exercise library safely (idempotent)
            ExerciseLibrary.populateInitialExercises(context: persistenceController.container.mainContext)
            persistenceController.deduplicateExerciseDefinitions()
            persistenceController.ensureDefaultExercisesPresent()
            // Unify synonymous exercise names without losing user history
            persistenceController.unifySynonymousExerciseDefinitions()
            // Ensure legacy arm exercises are reclassified to Biceps/Triceps
            // (idempotent)

            #if DEBUG
            DebugDataGenerator.hideLegacySampleMarkers(context: persistenceController.container.mainContext)
            if launchConfiguration.usesCoreTabsFixture {
                DebugDataGenerator.generateUITestFixture(
                    named: "core_tabs",
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

            // Check if user needs to see onboarding
            // Show onboarding if: 
            // 1. They haven't completed profile setup AND
            // 2. They haven't filled out basic profile info (age, height)
            if launchConfiguration.shouldSkipAutomationSideEffects {
                didCompleteProfileSetup = true
                didShowTutorial = true
                showTutorial = false
            } else {
                let hasProfileData = age > 0 && heightValue > 0
                if !didCompleteProfileSetup && !hasProfileData {
                    showTutorial = true
                } else {
                    // If onboarding was completed or profile data exists, mark as complete
                    didCompleteProfileSetup = true
                    didShowTutorial = true

                    // Check health authorization and prompt if not granted
                    Task { @MainActor in
                        await checkAndRequestHealthAuthorizationIfNeeded()
                    }
                }
            }
            
            // Schedule weekly reminders if enabled
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                ReminderService.scheduleIfEnabled()
            }

            // No banner; we'll prompt for HK when appropriate
            // Align unit preferences to the global measurement selection
            if measurementSystem == "imperial" {
                if weightUnit != "lbs" { weightUnit = "lbs" }
                if distanceUnit != "mi" { distanceUnit = "mi" }
                if heightUnit != "in" { heightUnit = "in" }
            } else {
                if weightUnit != "kg" { weightUnit = "kg" }
                if distanceUnit != "km" { distanceUnit = "km" }
                if heightUnit != "cm" { heightUnit = "cm" }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            LiveActivityManager.shared.end()
        }
        .alert("Health Access Issue", isPresented: Binding(get: { healthAuthError != nil }, set: { if !$0 { healthAuthError = nil } })) {
            Button("OK", role: .cancel) { healthAuthError = nil }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(healthAuthError ?? "Health permissions may be limited. You can adjust them in Settings.")
        }
        .sheet(isPresented: $showTutorial, onDismiss: {
            didShowTutorial = true
            didCompleteProfileSetup = true
        }) {
            TutorialView(onFinish: {
                finishOnboarding()
            })
        }

        .sheet(item: $importedWorkout) { session in
            WorkoutImportView(sharedSession: session)
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

        guard !launchConfiguration.shouldSkipAutomationSideEffects else { return }

        Task { @MainActor in
            do {
                // Give time for the tutorial sheet to fully dismiss before presenting system permission sheets.
                try await Task.sleep(nanoseconds: 500_000_000)
                try await HealthKitManager.shared.requestAuthorization()
                if !HealthKitManager.shared.isAuthorized {
                    presentHealthAuthorizationIssue(incompleteHealthAuthorizationMessage)
                } else {
                    clearHealthAuthorizationIssue(resetSuppression: true)
                }
            } catch {
                presentHealthAuthorizationIssue(error.localizedDescription)
            }
        }
    }
    
    /// Checks if Health authorization is needed and requests it
    /// This ensures users get prompted after reinstalling the app
    @MainActor
    private func checkAndRequestHealthAuthorizationIfNeeded() async {
        guard !launchConfiguration.shouldSkipAutomationSideEffects else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        await HealthKitManager.shared.refreshAuthorizationState()
        if HealthKitManager.shared.isAuthorized {
            clearHealthAuthorizationIssue(resetSuppression: true)
            return
        }

        let shouldRequestAuthorization = await HealthKitManager.shared.authorizationRequiresRequest()
        if shouldRequestAuthorization {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // Small delay for smooth UX
                try await HealthKitManager.shared.requestAuthorization()
                if !HealthKitManager.shared.isAuthorized {
                    presentHealthAuthorizationIssue(incompleteHealthAuthorizationMessage)
                } else {
                    clearHealthAuthorizationIssue(resetSuppression: true)
                }
            } catch {
                presentHealthAuthorizationIssue(error.localizedDescription)
            }
        } else {
            presentHealthAuthorizationIssue(incompleteHealthAuthorizationMessage)
        }
    }

    @MainActor
    private func presentHealthAuthorizationIssue(_ message: String) {
        if message == incompleteHealthAuthorizationMessage {
            guard !didShowHealthAccessIssueAlert else { return }
            didShowHealthAccessIssueAlert = true
        }

        healthAuthError = message
    }

    @MainActor
    private func clearHealthAuthorizationIssue(resetSuppression: Bool = false) {
        healthAuthError = nil
        if resetSuppression {
            didShowHealthAccessIssueAlert = false
        }
    }

    private var incompleteHealthAuthorizationMessage: String {
        "Health permissions are incomplete. Enable workout, workout route, and distance write access in Settings > Health > Data Access & Devices."
    }

    // Removed debug-only sample run feature and top banner
}

#Preview {
    ContentView(importedWorkout: .constant(nil))
        // Provide a container specifically for the preview
        .modelContainer(PersistenceController.preview.container)
} 
