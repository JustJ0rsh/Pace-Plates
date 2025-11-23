import SwiftUI
import GameKit
import CoreLocation
import SwiftData
import HealthKit

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ContentView: View {
    let persistenceController = PersistenceController.shared // Need access to this
    @AppStorage("didShowTutorial") private var didShowTutorial: Bool = false
    @AppStorage("didCompleteProfileSetup") private var didCompleteProfileSetup: Bool = false
    @AppStorage("age") private var age: Int = 0
    @AppStorage("heightValue") private var heightValue: Double = 0
    @State private var showTutorial: Bool = false
    @State private var healthAuthError: String? = nil
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "mi"
    @AppStorage("heightUnit") private var heightUnit: String = "in"
    @State private var aiAvailability: WorkoutPlanGenerator.Availability = .unknown
    @Binding var importedWorkout: SharedWorkoutSession?
    
    // Error handling moved to App level
    // @State private var showImportError: Bool = false
    // @State private var importErrorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                // Left side
                NavigationStack { HomeView() }
                    .tabItem { Label("Home", systemImage: "house.fill") }
                NavigationStack { WorkoutLogView() }
                    .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
                
                // Middle tab: AI (show if supported, hide if device is not eligible)
                if shouldShowAITab() {
                    NavigationStack { AIPlannerView() }
                        .tabItem { Label("AI", systemImage: "sparkles") }
                }
                
                // Right side
                NavigationStack { RunLogView() }
                    .tabItem { Label("Runs", systemImage: "figure.run") }
                NavigationStack { WeightLogView() }
                    .tabItem { Label("Weight", systemImage: "scalemass.fill") }
            }
            .background(AppTheme.backgroundColor.ignoresSafeArea())
            .tint(AppTheme.accentColor)
            .preferredColorScheme(.dark)
            .modelContainer(persistenceController.container)
            
        }
        .onAppear {
            // Check Apple Intelligence availability
            aiAvailability = WorkoutPlanGenerator.shared.availability()
            // Seed + cleanup the exercise library safely (idempotent)
            ExerciseLibrary.populateInitialExercises(context: persistenceController.container.mainContext)
            persistenceController.deduplicateExerciseDefinitions()
            persistenceController.ensureDefaultExercisesPresent()
            // Unify synonymous exercise names without losing user history
            persistenceController.unifySynonymousExerciseDefinitions()
            // Ensure legacy arm exercises are reclassified to Biceps/Triceps
            // (idempotent)
            
            
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
            
            // Schedule weekly reminders if enabled
            ReminderService.scheduleIfEnabled()

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

            // Authenticate Game Center (presents system sign-in if needed), then refresh streak achievements once.
            GameCenterService.shared.authenticate { _ in
                StreakService.refreshAndReport(using: persistenceController.container.mainContext)
            }
            // Ensure the Game Center access point dot is hidden by default
            GKAccessPoint.shared.isActive = false
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
                didShowTutorial = true
                didCompleteProfileSetup = true
                showTutorial = false
                Task { @MainActor in
                    do {
                        // Give time for the tutorial sheet to fully dismiss before presenting HK sheet
                        try await Task.sleep(nanoseconds: 500_000_000)
                        try await HealthKitManager.shared.requestAuthorization()
                        // After Health, ask for Location so you're ready to run
                        await requestLocationAuthorizationIfNeeded()
                    } catch {
                        healthAuthError = error.localizedDescription
                    }
                }
            })
        }

        .sheet(item: $importedWorkout) { session in
            WorkoutImportView(sharedSession: session)
        }

    }
}

extension ContentView {
    @MainActor
    private func requestLocationAuthorizationIfNeeded() async {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
    
    /// Checks if Health authorization is needed and requests it
    /// This ensures users get prompted after reinstalling the app
    @MainActor
    private func checkAndRequestHealthAuthorizationIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        // Check if we have any authorization status
        let healthStore = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        let status = healthStore.authorizationStatus(for: workoutType)
        
        // If not determined or sharing denied, request authorization
        // Note: HealthKit doesn't allow checking read authorization status,
        // so we also request if the user hasn't granted sharing yet
        if status == .notDetermined {
            do {
                try await Task.sleep(nanoseconds: 500_000_000) // Small delay for smooth UX
                try await HealthKitManager.shared.requestAuthorization()
                await requestLocationAuthorizationIfNeeded()
            } catch {
                healthAuthError = error.localizedDescription
            }
        }
    }
    
    /// Determines if the AI tab should be shown
    /// Returns true if device supports Apple Intelligence (even if not enabled)
    /// Returns false if device doesn't support it at all
    private func shouldShowAITab() -> Bool {
        #if AI_FOUNDATION_AVAILABLE
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            
            switch model.availability {
            case .available:
                // AI is ready - show tab
                return true
            case .unavailable(.appleIntelligenceNotEnabled):
                // Device supports it but user hasn't enabled - show tab with message
                return true
            case .unavailable(.modelNotReady):
                // Model is downloading - show tab with waiting message
                return true
            case .unavailable(.deviceNotEligible):
                // Device doesn't support Apple Intelligence - hide tab completely
                return false
            case .unavailable:
                // Other unavailable reason - hide tab
                return false
            @unknown default:
                return false
            }
            #else
            // FoundationModels couldn't be imported - hide tab
            return false
            #endif
        } else {
            // iOS too old - hide tab
            return false
        }
        #else
        // Build flag not set - hide tab
        return false
        #endif
    }
    
    // Removed debug-only sample run feature and top banner
}

#Preview {
    ContentView(importedWorkout: .constant(nil))
        // Provide a container specifically for the preview
        .modelContainer(PersistenceController.preview.container)
} 
