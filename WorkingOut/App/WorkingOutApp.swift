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
    
    var body: some Scene {
        WindowGroup {
            ContentView() // Simply present ContentView
            // .modelContainer and .onAppear are removed from here
        }
    }
}
