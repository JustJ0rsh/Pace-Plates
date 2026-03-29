# Architecture

**Analysis Date:** 2026-03-29

## Pattern Overview

**Overall:** Multi-target SwiftUI app with feature-first UI folders, a shared SwiftData model layer, singleton integration services, and embedded extension targets.

**Key Characteristics:**
- The main application target lives under `WorkingOut/` and composes the UI from feature folders such as `WorkingOut/Features/Home/`, `WorkingOut/Features/Workouts/`, `WorkingOut/Features/Runs/`, `WorkingOut/Features/Weight/`, `WorkingOut/Features/AI/`, and `WorkingOut/Features/Settings/`.
- Persistence is centralized in `WorkingOut/Data/PersistenceController.swift`, which creates one `ModelContainer` for the app’s SwiftData schema and attempts CloudKit-backed storage first, then falls back to a local store.
- Views read persisted data with `@Query`, mutate through `@Environment(\.modelContext)`, keep user preferences in `@AppStorage`, and call singleton services in `WorkingOut/Services/` for system APIs and cross-feature workflows.
- Two embedded extensions sit beside the app target: `RunningWidget/` renders the run Live Activity UI, and `WorkoutThumbnailExtension/` renders Quick Look thumbnails for exported workout files.

## Layers

**App Composition Layer:**
- Purpose: Boot the app target, install shared environment state, and route top-level events.
- Location: `WorkingOut/App/`
- Contains: `WorkingOut/App/WorkingOutApp.swift`, `WorkingOut/App/ContentView.swift`, `WorkingOut/App/HealthAuthorizationBanner.swift`
- Depends on: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Theme/AppTheme.swift`, service singletons such as `HealthKitManager`, `WorkoutSharingService`, `ReminderService`, and `TemplateSeeder`
- Used by: The `Pace & Plates` app target defined in `Pace & Plates.xcodeproj/project.pbxproj`

**Feature / Presentation Layer:**
- Purpose: Render screens, navigation stacks, sheets, toolbars, charts, and local interaction state for each user-facing domain.
- Location: `WorkingOut/Features/`
- Contains: Root screens such as `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/AI/AIPlannerView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`
- Depends on: SwiftData models, `@AppStorage` preferences, reusable UI in `WorkingOut/Components/`, theme tokens in `WorkingOut/Theme/AppTheme.swift`, and service classes in `WorkingOut/Services/`
- Used by: `WorkingOut/App/ContentView.swift` tab navigation, feature-to-feature navigation links, and modal sheets

**Shared UI Layer:**
- Purpose: Hold reusable visual building blocks and presentation helpers that multiple features use without creating a separate UI framework.
- Location: `WorkingOut/Components/` and `WorkingOut/Theme/`
- Contains: Reusable modifiers and wrappers such as `WorkingOut/Components/FloatingTile.swift`, `WorkingOut/Components/GlassBackground.swift`, `WorkingOut/Components/ShareSheet.swift`, `WorkingOut/Components/MarkdownView.swift`, and palette/style tokens in `WorkingOut/Theme/AppTheme.swift`
- Depends on: SwiftUI and UIKit bridges
- Used by: Most feature views, especially `HomeView`, `RunLogView`, `WorkoutLogView`, `WeightLogView`, AI screens, and settings screens

**Persistence / Domain Layer:**
- Purpose: Define the stored entities and static seed/catalog data that represent workouts, runs, weight logs, AI history, and templates.
- Location: `WorkingOut/Models/` and `WorkingOut/Data/`
- Contains: SwiftData `@Model` types such as `WorkoutSession`, `ExerciseLog`, `ExerciseDefinition`, `RunningSession`, `WeightEntry`, `RunningPlan`, `RunningPlanSession`, `AIConversation`, `WorkoutTemplate`, and `TemplateExercise`; data catalogs such as `WorkingOut/Data/ExerciseLibrary.swift`, `WorkingOut/Data/BuiltInTemplates.swift`, and `WorkingOut/Data/RunPlanCatalog.swift`
- Depends on: Foundation, SwiftData, and framework types needed by stored properties such as Core Location data encoding in `WorkingOut/Models/RunningSession.swift`
- Used by: Feature views through `@Query`, services through `ModelContext`, and backup/import/export workflows

**Service / Integration Layer:**
- Purpose: Encapsulate side effects, system framework access, and multi-step business workflows that should not live directly inside views.
- Location: `WorkingOut/Services/`
- Contains: Persistence helpers (`PersistenceSave.swift`), HealthKit integration (`HealthKitManager.swift`), Live Activity control (`LiveActivityManager.swift`), reminders (`ReminderService.swift`), weather (`WeatherService.swift`), Game Center (`GameCenterService.swift`), workout sharing/import-export (`WorkoutSharingService.swift`), template management (`WorkoutTemplateService.swift`, `TemplateSeeder.swift`), AI plan generation (`WorkoutPlanGenerator.swift`, `RunAssistantAIService.swift`, `AIPromptBuilder.swift`), run planning (`RunAssistantService.swift`), streaks (`StreakService.swift`), backup (`DataBackupService.swift`), and utility helpers like `UnitConverter.swift`
- Depends on: SwiftData models, platform frameworks, and sometimes `UserDefaults`
- Used by: Feature views, the app composition layer, and post-save/post-import maintenance flows

**Extension Target Layer:**
- Purpose: Render system-owned surfaces outside the main app process and package target-specific code separately.
- Location: `RunningWidget/` and `WorkoutThumbnailExtension/`
- Contains: `RunningWidget/RunningWidgetBundle.swift`, `RunningWidget/RunningLiveActivityWidget.swift`, `WorkoutThumbnailExtension/ThumbnailProvider.swift`
- Depends on: ActivityKit / WidgetKit or QuickLookThumbnailing, plus app-defined file type identifiers from `WorkingOut/Info.plist`
- Used by: The system when a Live Activity is active or when the Finder / share sheet needs a thumbnail for `.paceplate` or `.ppworkout` files

## Data Flow

**App Launch and Root Composition:**

1. The process enters at `WorkingOut/App/WorkingOutApp.swift`.
2. `WorkingOutXApp` applies the global theme through `AppTheme.applyGlobalTheme()`.
3. The root `WindowGroup` builds `WorkingOut/App/ContentView.swift`.
4. `ContentView` injects `PersistenceController.shared.container` with `.modelContainer(...)`.
5. `ContentView` seeds and heals persistent catalog data by calling `ExerciseLibrary.populateInitialExercises(...)`, `PersistenceController` maintenance methods, and `TemplateSeeder.shared.seedBuiltInTemplates(...)`.
6. `ContentView` decides whether to present onboarding, whether the AI tab is available, and whether an imported workout sheet should open.
7. Each tab mounts its own `NavigationStack` and then feature views fetch from SwiftData with `@Query`.

**Workout Logging and Template Generation:**

1. `WorkingOut/Features/Workouts/WorkoutLogView.swift` creates a new `WorkoutSession` or opens an existing one.
2. `WorkingOut/Features/Workouts/WorkoutSessionDetailView.swift` edits the session and its related `ExerciseLog` records through the feature’s `modelContext`.
3. Saves go through `PersistenceSave.commit(...)` in `WorkingOut/Services/PersistenceSave.swift`.
4. On dismiss, `WorkoutSessionDetailView` optionally updates `session.generatedTemplate` by calling `WorkoutTemplateService.shared.createTemplateFromWorkout(...)` or `updateTemplate(...)`.
5. The same post-dismiss path reports Game Center scores via `GameCenterService.shared.reportStrengthForSession(...)` and refreshes streak achievements through `StreakService.refreshAndReport(...)`.

**Run Tracking, Health Sync, and Live Activity:**

1. `WorkingOut/Features/Runs/RunLogView.swift` presents `WorkingOut/Features/Runs/RunTrackingView.swift`.
2. `RunTrackingView` uses the shared `RunTracker` observable singleton defined in the same file to manage `CLLocationManager`, elapsed time, route accumulation, and in-memory active-run state.
3. `RunTracker.startRun()` starts location updates and calls `LiveActivityManager.shared.start(...)`.
4. `WorkingOut/Services/LiveActivityManager.swift` issues `Activity.request(...)` with `RunningActivityAttributes`.
5. The system renders that Live Activity with the widget target entry points in `RunningWidget/RunningWidgetBundle.swift` and `RunningWidget/RunningLiveActivityWidget.swift`.
6. When the user saves the run, `RunTrackingView.saveRun()` converts the in-memory tracker state into a persisted `RunningSession`, inserts it into SwiftData, and asynchronously mirrors the workout to Apple Health through `HealthKitManager.shared.saveRunWorkout(...)`.
7. `RunLogView` also imports, enriches, and reconciles HealthKit cardio data via `HealthKitManager`, then matches imported runs against active run plans through `RunAssistantService.shared.reconcileCompletions(...)`.

**AI Planning and Template Materialization:**

1. `WorkingOut/Features/AI/AIPlannerView.swift` builds a `WorkoutPlanRequest` from `@AppStorage` profile settings, prompt text, and the current `ModelContext`.
2. `WorkoutPlanGenerator.shared` decides between on-device Foundation Models generation and fallback/template generation in `WorkingOut/Services/WorkoutPlanGenerator.swift`.
3. Generated output is streamed into AI-specific views such as `WorkingOut/Features/AI/AIConversationSheet.swift` and `WorkingOut/Features/AI/AIChatSheet.swift`.
4. Conversations are persisted as `AIConversation` models, and structured plan JSON is stored on the conversation record when available.
5. `WorkoutTemplateService.shared` converts those saved conversations into `WorkoutTemplate` and `TemplateExercise` records, which then surface in `WorkingOut/Features/Workouts/WorkoutTemplateListView.swift`.

**Workout Import / Export and Extension Relationship:**

1. `WorkoutSharingService` in `WorkingOut/Services/WorkoutSharingService.swift` converts `WorkoutSession` into `SharedWorkoutSession` DTOs and exports JSON-backed `.paceplate` or legacy `.ppworkout` files.
2. `WorkingOut/Features/Workouts/WorkoutSessionDetailView.swift` shares those DTOs through `ShareLink`.
3. `WorkingOut/App/WorkingOutApp.swift` handles incoming file URLs and custom share URLs through `.onOpenURL`.
4. Parsed imports become `SharedWorkoutSession` values, which drive the `WorkoutImportView` sheet in `WorkingOut/Features/Workouts/WorkoutImportView.swift`.
5. `WorkoutImportView` writes imported content back into SwiftData as `WorkoutTemplate` records.
6. The Quick Look target in `WorkoutThumbnailExtension/ThumbnailProvider.swift` provides thumbnails for the same custom file types declared in `WorkingOut/Info.plist` and supported in `WorkoutThumbnailExtension/Info.plist`.

**State Management:**
- Persistent domain state lives in one SwiftData container created by `WorkingOut/Data/PersistenceController.swift`.
- Query-driven read state is declared directly in feature views with `@Query`, for example in `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, and `WorkingOut/Features/Weight/WeightLogView.swift`.
- View-local UI state stays in `@State` inside feature files.
- Preference and lightweight profile state live in `@AppStorage` keys shared across screens, especially in `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/AI/AIPlannerView.swift`, and `WorkingOut/Features/Runs/RunAssistantContainerView.swift`.
- Long-lived in-memory operational state exists in singleton objects such as `RunTracker.shared`, `HealthKitManager.shared`, and `LiveActivityManager.shared`.
- Backup/export flows serialize the model graph into DTOs in `WorkingOut/Services/DataBackupService.swift` and `WorkingOut/Services/WorkoutSharingService.swift`.

## Key Abstractions

**SwiftData Model Graph:**
- Purpose: Represent all persisted fitness, planning, and AI records.
- Examples: `WorkingOut/Models/WorkoutSession.swift`, `WorkingOut/Models/ExerciseLog.swift`, `WorkingOut/Models/RunningSession.swift`, `WorkingOut/Models/WeightEntry.swift`, `WorkingOut/Models/RunningPlan.swift`, `WorkingOut/Models/AIConversation.swift`, `WorkingOut/Models/WorkoutTemplate.swift`
- Pattern: SwiftData `@Model` classes with `@Relationship` links and simple computed helpers

**Feature Root Views:**
- Purpose: Own each domain screen’s queries, filters, navigation, and modal state.
- Examples: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/AI/AIPlannerView.swift`
- Pattern: Large SwiftUI view files that mix top-level screen composition with nested helper views and feature-specific actions

**Singleton Service Managers:**
- Purpose: Centralize side effects and shared workflows instead of passing dependencies through many views.
- Examples: `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantService.swift`, `WorkingOut/Services/GameCenterService.swift`, `WorkingOut/Services/WorkoutSharingService.swift`
- Pattern: Mostly `static let shared` singletons, often `@MainActor`, called directly from views

**Catalog / Seed Sources:**
- Purpose: Provide static app-owned content that must exist in the persistent store.
- Examples: `WorkingOut/Data/ExerciseLibrary.swift`, `WorkingOut/Data/BuiltInTemplates.swift`, `WorkingOut/Data/RunPlanCatalog.swift`
- Pattern: In-memory library structs or arrays plus idempotent seeding and backfill services

**Transfer DTOs and Custom File Types:**
- Purpose: Move workout content across share sheets, imported files, and external document previews without exposing the SwiftData graph directly.
- Examples: `SharedWorkoutSession`, `SharedExercise`, and `SharedExerciseSet` in `WorkingOut/Services/WorkoutSharingService.swift`; UTType declarations there and in `WorkingOut/Info.plist`
- Pattern: Codable DTOs plus `Transferable` representations and file-based import/export

**Live Activity Contract:**
- Purpose: Define the state shape shared conceptually between the app’s run tracker and the widget extension.
- Examples: `RunningActivityAttributes` in `WorkingOut/Services/LiveActivityManager.swift` and `RunningWidget/RunningLiveActivityWidget.swift`
- Pattern: ActivityKit attributes mirrored in app and extension targets so the app can publish state while the widget renders UI

## Entry Points

**Main App Entry:**
- Location: `WorkingOut/App/WorkingOutApp.swift`
- Triggers: iOS launching the main `Pace & Plates` application target
- Responsibilities: Apply theme, host `ContentView`, process incoming workout files / deep links, and surface import errors

**Root Shell / Tab Entry:**
- Location: `WorkingOut/App/ContentView.swift`
- Triggers: App window creation
- Responsibilities: Mount `TabView`, inject the model container, perform first-run/on-appear seeding and cleanup, gate onboarding, and choose whether the AI tab appears

**Live Activity Widget Entry:**
- Location: `RunningWidget/RunningWidgetBundle.swift`
- Triggers: ActivityKit when an activity of type `RunningActivityAttributes` is active
- Responsibilities: Register the widget bundle and expose `RunningLiveActivity`

**Quick Look Thumbnail Entry:**
- Location: `WorkoutThumbnailExtension/ThumbnailProvider.swift`
- Triggers: The system requesting a thumbnail for `.paceplate` or `.ppworkout` documents
- Responsibilities: Draw a preview icon for exported workout files

**Target Wiring Entry:**
- Location: `Pace & Plates.xcodeproj/project.pbxproj`
- Triggers: Xcode builds the project
- Responsibilities: Define the `Pace & Plates`, `RunningWidgetExtension`, and `WorkoutThumbnailExtension` targets; connect filesystem-synchronized root groups; embed the widget extension into the app

## Error Handling

**Strategy:** Keep errors close to the feature that triggered them, use lightweight helpers for persistence failures, and degrade to local or reduced functionality instead of building a centralized error pipeline.

**Patterns:**
- SwiftData writes usually call `PersistenceSave.commit(...)` from `WorkingOut/Services/PersistenceSave.swift`, which logs through `os.Logger` and lets the caller present a user-facing message.
- Many integration failures use local `@State` alert strings inside the active screen, for example in `WorkingOut/App/WorkingOutApp.swift`, `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, and `WorkingOut/Features/Settings/SettingsView.swift`.
- `PersistenceController` falls back from CloudKit-enabled configuration to a local SwiftData store if container creation fails in `WorkingOut/Data/PersistenceController.swift`.
- Service-layer errors often log with `print(...)` and continue when the feature can still partially succeed, such as template seeding, import deduplication, HealthKit sync, and Live Activity start/update failures.

## Cross-Cutting Concerns

**Logging:** Minimal centralized logging exists in `WorkingOut/Services/PersistenceSave.swift` via `os.Logger`. Most other diagnostics are inline `print(...)` statements in services and feature files such as `TemplateSeeder.swift`, `WorkoutTemplateService.swift`, `LiveActivityManager.swift`, and `WorkoutImportView.swift`.

**Validation:** Validation is mostly inline and pragmatic. Examples include duplicate checks in `WorkingOut/Services/TemplateSeeder.swift` and `WorkingOut/Features/Workouts/WorkoutImportView.swift`, AI prompt clamping in `WorkingOut/Services/WorkoutPlanGenerator.swift`, and file/share URL validation in `WorkingOut/Services/WorkoutSharingService.swift`.

**Authentication / Permissions:** Permission flows are handled per framework rather than through a shared auth layer. `HealthKitManager` owns Health permissions, `RunTracker` and `SettingsView` manage location permission escalation, `GameCenterService` handles Game Center authentication, and the AI tab gates itself through Foundation Models availability checks in `WorkingOut/Services/WorkoutPlanGenerator.swift` and `WorkingOut/App/ContentView.swift`.

**Theming:** `WorkingOut/Theme/AppTheme.swift` is a global design token source read through static accessors and `@AppStorage(AppTheme.storageKey)` across screens. Reusable tile/background modifiers in `WorkingOut/Components/` apply the theme consistently.

**Extension Boundaries:** The app target owns all business logic and most state. `RunningWidget/` only renders Live Activity UI, and `WorkoutThumbnailExtension/` only renders thumbnails. Neither extension contains its own persistence layer.

---

*Architecture analysis: 2026-03-29*
