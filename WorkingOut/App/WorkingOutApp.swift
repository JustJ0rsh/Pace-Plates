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
    @State private var showImportError: Bool = false
    @State private var importErrorMessage: String = ""

    var body: some Scene {
        WindowGroup {
            ContentView(importedWorkout: $importedWorkout)
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

    private func handleIncomingWorkout(_ url: URL) {
        do {
            if url.isFileURL {
                importedWorkout = try WorkoutSharingService.shared.parseWorkoutFile(url: url)
            } else if let session = try WorkoutSharingService.shared.parseShareURL(url) {
                importedWorkout = session
            } else {
                presentImportError("Invalid workout link.")
            }
        } catch let limitError as SharedWorkoutImportError {
            presentImportError(limitError.localizedDescription)
        } catch {
            presentImportError(
                url.isFileURL
                    ? "Could not open the workout file. It might be corrupted or incompatible."
                    : "Invalid workout link."
            )
        }
    }

    private func presentImportError(_ message: String) {
        importErrorMessage = message
        showImportError = true
    }
}
