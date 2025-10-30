import SwiftUI
import CoreLocation
import SwiftData

struct ContentView: View {
    let persistenceController = PersistenceController.shared // Need access to this
    @AppStorage("didShowTutorial") private var didShowTutorial: Bool = false
    @State private var showTutorial: Bool = false
    @State private var healthAuthError: String? = nil
    @AppStorage("measurementSystem") private var measurementSystem: String = "metric"
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("heightUnit") private var heightUnit: String = "cm"

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                // Left side
                NavigationStack { HomeView() }
                    .tabItem { Label("Home", systemImage: "house.fill") }
                NavigationStack { WorkoutLogView() }
                    .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
                
                // Middle tab: AI
                NavigationStack { AIPlannerView() }
                    .tabItem { Label("AI", systemImage: "sparkles") }
                
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
        .task {
            // Defer HealthKit prompt until after tutorial is completed
            if didShowTutorial {
                do {
                    // Slight delay to ensure window is on screen before presenting HK sheet
                    try await Task.sleep(nanoseconds: 400_000_000)
                    try await HealthKitManager.shared.requestAuthorization()
                    // After asking for Health access, request Location so weather/routes work
                    await requestLocationAuthorizationIfNeeded()
                } catch {
                    healthAuthError = error.localizedDescription
                }
            }
        }
        .onAppear {
            // Seed + cleanup the exercise library safely (idempotent)
            ExerciseLibrary.populateInitialExercises(context: persistenceController.container.mainContext)
            persistenceController.deduplicateExerciseDefinitions()
            persistenceController.ensureDefaultExercisesPresent()
            
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
            
            if !didShowTutorial {
                showTutorial = true
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
        .sheet(isPresented: $showTutorial, onDismiss: { didShowTutorial = true }) {
            TutorialView(onFinish: {
                didShowTutorial = true
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
    // Removed debug-only sample run feature and top banner
}

#Preview {
    ContentView()
        // Provide a container specifically for the preview
        .modelContainer(PersistenceController.preview.container)
} 
