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
                    // Handle file import
                    if url.isFileURL {
                        if let session = WorkoutSharingService.shared.parseWorkoutFile(url: url) {
                            importedWorkout = session
                        } else {
                            importErrorMessage = "Could not open the workout file. It might be corrupted or incompatible."
                            showImportError = true
                        }
                    } else {
                        // Handle deep link
                        if let session = WorkoutSharingService.shared.parseShareURL(url) {
                            importedWorkout = session
                        } else {
                            importErrorMessage = "Invalid workout link."
                            showImportError = true
                        }
                    }
                }
                .alert("Import Failed", isPresented: $showImportError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(importErrorMessage)
                }
        }
    }
}
