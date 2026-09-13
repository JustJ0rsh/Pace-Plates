//
//  WorkingOutApp.swift
//  WorkingOut
//
//  Created by Joshua Jackson on 4/2/25.
//

import SwiftUI
import SwiftData

@main
struct WorkingOutXApp: App {
    // Persistence controller might not be directly needed here anymore,
    // but ContentView might need it passed in or accessed via Environment.
    // Let's keep it for now, ContentView accesses it via static shared instance.
    let persistenceController = PersistenceController.shared

    init() {
        AppLaunchConfiguration.current.prepareUserDefaults(bundleIdentifier: Bundle.main.bundleIdentifier)
        // Apply the global theme settings on app initialization
        AppTheme.applyGlobalTheme()
    }
    
    @State private var importedWorkout: SharedWorkoutSession?
    @State private var importedCoachProgram: CoachImportRequest?
    @State private var showImportError: Bool = false
    @State private var importErrorMessage: String = ""

    var body: some Scene {
        WindowGroup {
            ContentView(importedWorkout: $importedWorkout, importedCoachProgram: $importedCoachProgram)
                .onOpenURL { url in
                    handleIncomingWorkout(url)
                }
                .alert("Import Failed", isPresented: $showImportError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(importErrorMessage)
                }
        }
    }

    /// Workout documents keep their existing routes; Coach also accepts its
    /// registered program type and JSON. The app registers no custom URL
    /// scheme, so any non-file URL is ignored rather than parsed.
    private func handleIncomingWorkout(_ url: URL) {
        guard url.isFileURL else { return }
        if ["coachplan", "json"].contains(url.pathExtension.lowercased()) {
            Task { @MainActor in
                do {
                    let text = try await Task.detached { try CoachProgramResources.readFile(url) }.value
                    importedCoachProgram = CoachImportRequest(text: text)
                } catch { presentImportError(error.localizedDescription) }
            }
            return
        }
        do {
            importedWorkout = try WorkoutSharingService.shared.parseWorkoutFile(url: url)
        } catch let limitError as SharedWorkoutImportError {
            presentImportError(limitError.localizedDescription)
        } catch {
            presentImportError("Could not open the workout file. It might be corrupted or incompatible.")
        }
    }

    private func presentImportError(_ message: String) {
        importErrorMessage = message
        showImportError = true
    }
}
