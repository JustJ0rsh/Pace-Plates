# WorkingOut

A comprehensive iOS app for tracking workouts, runs, and body weight, built with SwiftUI and SwiftData.

## Features

- **Workout Tracking**
  - Log exercises with sets, reps, and weights
  - Predefined exercise library with muscle group categorization
  - Custom exercise creation
  - Workout history and details

- **Run Tracking**
  - Track runs with distance and duration
  - Route mapping with MapKit
  - Run history and statistics

- **Weight Tracking**
  - Log body weight with timestamps
  - Weight trend visualization with charts
  - Weight history

- **Dashboard**
  - Overview of recent activity
  - Weight trend chart
  - Quick access to all features

## Technical Details

- Built with SwiftUI for modern iOS UI
- Uses SwiftData for persistence (iOS 17+)
- Integrates MapKit for run route visualization
- Uses Swift Charts for data visualization
- Supports both metric and imperial units

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

1. Clone the repository
2. Open `WorkingOut.xcodeproj` in Xcode
3. Build and run the project

## Development

The project uses a clear, feature-first folder structure to make files easy to find and maintain:

- `WorkingOut/App` — App entry and global composition
  - `WorkingOutApp.swift`, `ContentView.swift`
- `WorkingOut/Features` — User-facing features grouped by domain
  - `Home/` — `HomeView.swift`
  - `Workouts/` — `WorkoutLogView.swift`, `WorkoutSessionDetailView.swift`, `AddExerciseView.swift`, `EditExerciseLogView.swift`
  - `Runs/` — `RunLogView.swift`, `RunTrackingView.swift`
  - `Weight/` — `WeightLogView.swift`, `LogWeightView.swift`
  - `Settings/` — `SettingsView.swift`
- `WorkingOut/Components` — Reusable UI components and modifiers
  - `FloatingTile.swift`, `GlassBackground.swift`
- `WorkingOut/Services` — External integrations and system services
  - `HealthKitManager.swift`
- `WorkingOut/Data` — Persistence and data seeding
  - `PersistenceController.swift`, `ExerciseLibrary.swift`
- `WorkingOut/Models` — SwiftData models
  - `ExerciseDefinition.swift`, `ExerciseLog.swift`, `WorkoutSession.swift`, `RunningSession.swift`, `WeightEntry.swift`
- `WorkingOut/Theme` — App theming
  - `AppTheme.swift`
- `WorkingOut/Assets.xcassets` — Colors, app icon, images
- `WorkingOut/Preview Content` — Preview assets

Notes:
- The Xcode project is configured to mirror the filesystem, so adding/moving files under `WorkingOut/` automatically updates the project.
- No public APIs or UI were changed during refactor; only file organization and minor comment cleanup.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
