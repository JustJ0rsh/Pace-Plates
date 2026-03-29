# Coding Conventions

**Analysis Date:** 2026-03-29

## Naming Patterns

**Files:**
- Use `PascalCase.swift` for app files whose primary type is a Swift type or SwiftUI view, matching the main symbol name. Examples: `WorkingOut/App/ContentView.swift`, `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Components/FloatingTile.swift`.
- Keep companion UI types in the same file when they are tightly coupled to one screen, or move them into a focused companion file with the same feature prefix. Examples: `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`, `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`.
- Organize features by domain folder under `WorkingOut/Features/` and keep folders in `PascalCase`. Examples: `WorkingOut/Features/Runs/`, `WorkingOut/Features/AI/`, `WorkingOut/Features/Settings/`.
- Keep extension-target files alongside the extension target folder. Examples: `RunningWidget/RunningLiveActivityWidget.swift`, `WorkoutThumbnailExtension/ThumbnailProvider.swift`.

**Functions:**
- Use lowerCamelCase for functions and methods. Examples: `finishOnboarding()` in `WorkingOut/App/ContentView.swift`, `loadVitals()` in `WorkingOut/Features/Home/Vitals/VitalsModel.swift`, `seedBuiltInTemplates(context:)` in `WorkingOut/Services/TemplateSeeder.swift`.
- Name UI event handlers as verbs or verb phrases instead of `handle...` by default. Examples: `generateTapped()` in `WorkingOut/Features/AI/AIPlannerView.swift`, `refreshHealthDataNow()` in `WorkingOut/Features/Settings/SettingsView.swift`, `requestAuthorization(startAfterAuth:)` in `WorkingOut/Features/Runs/RunTrackingView.swift`.
- Keep async and throwing behavior in the signature rather than the name. Examples: `currentWeather(at:) async throws` in `WorkingOut/Services/WeatherService.swift`, `fetchRecentRuns(limit:) async throws` in `WorkingOut/Services/HealthKitManager.swift`.
- Use helper names that describe derived data or formatting directly. Examples: `weightDailySeriesLast7` and `formatWeek(for:)` in `WorkingOut/Features/Home/HomeView.swift`.

**Variables:**
- Use lowerCamelCase for stored properties, locals, and bindings. Examples: `preferredWeightUnit`, `showDeleteConfirm`, `locationAuthorizationStatus`, `structuredPlanJSON`.
- Prefix booleans with `is`, `has`, `show`, `should`, `allow`, or `did` depending on meaning. Examples: `isStreaming` in `WorkingOut/Features/AI/AIConversationSheet.swift`, `hasScheduledInitialImport` in `WorkingOut/Features/Weight/WeightLogView.swift`, `showTutorial` in `WorkingOut/App/ContentView.swift`, `shouldSaveAsTemplate` in `WorkingOut/Models/WorkoutSession.swift`.
- Keep constants in lowerCamelCase, not `UPPER_SNAKE_CASE`. Examples: `runPageSize` in `WorkingOut/Features/Runs/RunLogView.swift`, `quickCardioOptions` in `WorkingOut/Features/Home/HomeView.swift`, `storageKey` in `WorkingOut/Theme/AppTheme.swift`.
- Use `shared` for global singleton access points. Examples: `PersistenceController.shared` in `WorkingOut/Data/PersistenceController.swift`, `TemplateSeeder.shared` in `WorkingOut/Services/TemplateSeeder.swift`, `RunTracker.shared` in `WorkingOut/Features/Runs/RunTrackingView.swift`.

**Types:**
- Use `PascalCase` for models, views, services, enums, nested helper structs, and modifiers. Examples: `RunningPlan` in `WorkingOut/Models/RunningPlan.swift`, `WorkoutDetailsTile` in `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`, `AppThemeOption` in `WorkingOut/Theme/AppTheme.swift`.
- Use noun-based type names for services and models, and screen-oriented names ending in `View`, `Sheet`, `Tile`, or `Section` for UI types. Examples: `WorkoutTemplateService` in `WorkingOut/Services/WorkoutTemplateService.swift`, `AIConversationSheet` in `WorkingOut/Features/AI/AIConversationSheet.swift`, `WeightChartSection` in `WorkingOut/Features/Weight/WeightLogView.swift`.
- Use nested private enums and structs for local view-only state domains. Examples: `private enum TimeRange` in `WorkingOut/Features/Weight/WeightLogView.swift`, `private struct DailyPoint` in `WorkingOut/Features/Runs/RunLogView.swift`.

## Code Style

**Formatting:**
- No repository-managed formatter config is detected. There is no `.swiftformat`, `swiftformat` config, or `.swiftlint.yml` at the project root.
- Follow Xcode-default Swift formatting: 4-space indentation, opening braces on the same line, one import per line, and trailing commas only where Swift style already uses them. Representative files: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Theme/AppTheme.swift`, `WorkingOut/Services/TemplateSeeder.swift`.
- Use `// MARK:` sections in larger files to create navigable structure. Examples: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Components/FloatingTile.swift`.
- Prefer explicit access control for internal implementation details when a file is large or view state is dense. Common patterns: `private var`, `private func`, `private enum`, `private struct`.
- Keep conditional compilation local and explicit. Examples: `#if canImport(FoundationModels)` in `WorkingOut/App/ContentView.swift`, `#if DEBUG` in `WorkingOut/App/ContentView.swift` and `WorkingOut/Features/Settings/SettingsView.swift`.

**Linting:**
- No dedicated lint framework is configured in the repo. There is no `SwiftLint`, `SwiftFormat`, `Danger`, `fastlane`, or CI workflow configuration at the root.
- Treat Xcode build diagnostics, analyzer output, and compiler type-check failures as the effective lint gate. The shared scheme is `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`.
- Keep compile-heavy view bodies split into subviews when Charts or large `ViewBuilder` expressions get hard to type-check. This is already reflected by extracted sections like `WorkoutVolumeChartSection` in `WorkingOut/Features/Workouts/WorkoutLogView.swift` and `WeightChartSection` in `WorkingOut/Features/Weight/WeightLogView.swift`.

## Import Organization

**Order:**
1. Apple frameworks and SDK modules used by the file. Examples: `SwiftUI`, `SwiftData`, `HealthKit`, `MapKit`, `Charts`, `ActivityKit`.
2. Conditional Apple-only modules behind feature gates. Example: `#if canImport(FoundationModels)` in `WorkingOut/App/ContentView.swift`.
3. No local module imports are used because app code lives in a single target namespace plus extension targets.

**Grouping:**
- Keep imports in one compact block at the top of the file with no blank lines between standard framework imports. Examples: `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`.
- Strict alphabetical ordering is not enforced. Match the local file's existing grouping instead of reordering unrelated imports just for style churn.

**Path Aliases:**
- Not applicable. Swift files refer to project symbols directly; there are no package-level path aliases or modular import wrappers.

## State Management

**SwiftUI View State:**
- Use `@State` for screen-local ephemeral UI state such as sheet toggles, selection, loading flags, and error text. Examples: `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`.
- Use `@Binding` to pass mutable state into sheets, detail subviews, and helper screens. Examples: `ContentView(importedWorkout:)` in `WorkingOut/App/ContentView.swift`, `ThemePickerView(appTheme:)` in `WorkingOut/Features/Settings/ThemePickerView.swift`, `WorkoutDetailsTile` in `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`.
- Use `@FocusState` for form navigation and keyboard management. Examples: `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Onboarding/TutorialView.swift`.

**Shared and Persisted State:**
- Use `@AppStorage` aggressively for user preferences and lightweight profile state. Examples span `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Runs/RunAssistantContainerView.swift`.
- Use `@Query` plus `@Environment(\.modelContext)` as the default SwiftData read/write path in screens. Examples: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/AI/AIHistoryView.swift`.
- Use `@Observable` for mutable shared controllers that should be directly observed by SwiftUI without `ObservableObject`. Examples: `PersistenceController` in `WorkingOut/Data/PersistenceController.swift`, `RunTracker` in `WorkingOut/Features/Runs/RunTrackingView.swift`.
- Keep `ObservableObject` plus `@Published` and `@StateObject` for class-based view models that still fit the older observation pattern. Examples: `VitalsModel` with `@StateObject` in `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`, `HealthKitManager` in `WorkingOut/Services/HealthKitManager.swift`, `WeatherViewModel` in `WorkingOut/Services/WeatherService.swift`.
- Favor singleton services for system integrations and cross-feature coordination. Examples: `HealthKitManager.shared`, `WorkoutPlanGenerator.shared`, `MapSearchService.shared`, `ReminderService`.

## Error Handling

**Patterns:**
- Let service boundaries throw when the caller can recover or surface UI. Examples: `requestAuthorization() async throws` in `WorkingOut/Services/HealthKitManager.swift`, `exportAll(context:) throws` in `WorkingOut/Services/DataBackupService.swift`, `generatePlan(...) async throws` in `WorkingOut/Services/RunAssistantAIService.swift`.
- Catch errors in views and convert them into alert state or inline error text. Examples: `healthAuthError` in `WorkingOut/App/ContentView.swift`, `saveErrorMessage` in `WorkingOut/Features/Weight/WeightLogView.swift`, `errorText` in `WorkingOut/Features/AI/AIConversationSheet.swift`.
- Use `PersistenceSave.commit` for user-facing SwiftData writes so logging and fallback messaging stay consistent. See `WorkingOut/Services/PersistenceSave.swift` and call sites in `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`.
- Use `try?` for best-effort fetches, caches, and non-critical migrations where silent fallback is acceptable in current code. Examples: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Services/TemplateSeeder.swift`, `WorkingOut/Features/Home/Vitals/VitalsModel.swift`.
- Handle cancellation separately when streaming AI tasks. Examples: `catch is CancellationError` in `WorkingOut/Features/AI/AIChatSheet.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/Runs/RunAssistantDashboardView.swift`.

**Error Types:**
- Custom error enums are uncommon; the codebase mainly uses thrown framework errors and user-facing strings.
- `fatalError` is reserved for unrecoverable app boot failures only. Current example: `WorkingOut/Data/PersistenceController.swift`. Do not introduce more crash-on-error paths unless initialization truly cannot continue.

## Logging

**Framework:**
- Persistence failures use `os.Logger` through `WorkingOut/Services/PersistenceSave.swift`.
- Most other logging uses direct `print(...)` statements, often with emoji prefixes for subsystem tracing. Examples: `WorkingOut/Services/TemplateSeeder.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/LiveActivityManager.swift`, `WorkingOut/Features/Workouts/WorkoutImportView.swift`.

**Patterns:**
- Keep logs close to external-service boundaries, persistence migrations, import/export flows, and AI streaming. Examples: `WorkingOut/Services/MapSearchService.swift`, `WorkingOut/Services/WorkoutSharingService.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`.
- If you are touching save paths, prefer `PersistenceSave.commit` over ad hoc `print` so failures get both a user message and a structured log entry.
- If you must add temporary console diagnostics, include concrete context values like IDs, counts, dates, or action names, following the existing style in `WorkingOut/Features/Workouts/WorkoutImportView.swift` and `WorkingOut/Features/Runs/RunLogView.swift`.

## Comments

**When to Comment:**
- Use `// MARK:` to segment screens, services, and helper blocks.
- Add comments for migration rationale, SwiftUI lifecycle edge cases, and platform constraints. Examples: CloudKit fallback comments in `WorkingOut/Data/PersistenceController.swift`, location throttling notes in `WorkingOut/Services/MapSearchService.swift`, onboarding permission timing in `WorkingOut/App/ContentView.swift`.
- Avoid repeating what the code already states unless the comment records intent that would otherwise be lost. Good examples: route persistence comments in `WorkingOut/Features/Runs/RunTrackingView.swift`, AI availability behavior in `WorkingOut/App/ContentView.swift`.

**JSDoc/TSDoc:**
- Swift doc comments are used sparingly, mainly on service entry points or migration helpers where the intent matters. Examples: `WorkingOut/Services/TemplateSeeder.swift`, `WorkingOut/Services/DebugDataGenerator.swift`.
- Do not add blanket doc comments to every view property; reserve them for public-ish helpers, non-obvious migration logic, or complex conversion code.

**TODO Comments:**
- TODO usage is rare and informal. Current example: altitude work in `WorkingOut/Features/Runs/RunLogView.swift`.
- If you add a TODO, include the missing behavior directly in the comment because there is no repo-wide ticket reference convention.

## Function Design

**Size:**
- Keep pure utilities small and static. Example: `WorkingOut/Services/UnitConverter.swift`.
- Larger SwiftUI screens commonly exceed small-function limits; control complexity by extracting subviews, helper types, computed properties, and extensions within the same feature file or a nearby companion file. Examples: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`.

**Parameters:**
- Pass `ModelContext` explicitly into services and migration helpers instead of hiding write access behind ambient globals. Examples: `seedBuiltInTemplates(context:)` in `WorkingOut/Services/TemplateSeeder.swift`, `exportAll(context:)` in `WorkingOut/Services/DataBackupService.swift`, `createTemplateFromAIPlan(..., context:)` in `WorkingOut/Services/WorkoutTemplateService.swift`.
- Prefer concise primitive parameters and tuples for screen-local helpers. Examples: `(inserted: Int, linked: Int, skipped: Int)` in `WorkingOut/Features/Settings/SettingsView.swift`, `WorkoutPlanRequest` passed into `WorkingOut/Features/AI/AIConversationSheet.swift`.

**Return Values:**
- Return optionals for best-effort lookups and cached system data. Examples: `reverseAddressName(near:) async -> String?` in `WorkingOut/Services/MapSearchService.swift`, `getAge() throws -> Int?` in `WorkingOut/Services/HealthKitManager.swift`.
- Return SwiftData model instances directly when the caller is expected to persist or present them. Examples: `stopRun() -> RunningSession?` in `WorkingOut/Features/Runs/RunTrackingView.swift`.
- Use tuples for multi-value workflow summaries instead of introducing one-off types. Examples: health import summaries in `WorkingOut/Features/Settings/SettingsView.swift`, route stats helpers in `WorkingOut/Services/HealthKitManager.swift`.

## Persistence and Data Mutation

**SwiftData:**
- Define persisted entities as `@Model final class` in `WorkingOut/Models/`. Examples: `WorkoutSession` in `WorkingOut/Models/WorkoutSession.swift`, `ExerciseDefinition` in `WorkingOut/Models/ExerciseDefinition.swift`, `AIConversation` in `WorkingOut/Models/AIConversation.swift`.
- Centralize schema registration in `WorkingOut/Data/PersistenceController.swift`. When adding a new model, update the schema there and consider `preview` data if the model affects previews.
- Keep preview data in `PersistenceController.preview` using an in-memory container and real model inserts. This is the repo's closest existing factory pattern.

**Mutation Style:**
- Mutate model objects directly in the view or service that owns the interaction, then persist immediately. Examples: toggles in `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`, import flows in `WorkingOut/Features/Settings/SettingsView.swift`, migration helpers in `WorkingOut/Data/PersistenceController.swift`.
- Use helper services for non-trivial migration, import/export, template creation, or deduplication. Examples: `TemplateSeeder`, `WorkoutTemplateService`, `DataBackupService`, `PersistenceController`.

## UI Composition Style

**Screen Composition:**
- Root app composition happens in `WorkingOut/App/ContentView.swift` using a `TabView` with a separate `NavigationStack` per tab.
- Feature screens live under `WorkingOut/Features/` and usually own their toolbar, sheets, alerts, and derived chart data in a single file. Examples: `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`.
- Reusable decoration and wrappers live under `WorkingOut/Components/` and `WorkingOut/Theme/`. Examples: `floatingTile()` in `WorkingOut/Components/FloatingTile.swift`, global tokens in `WorkingOut/Theme/AppTheme.swift`.

**Visual Patterns:**
- Apply section-specific gradient backgrounds via `.appBackground(AppTheme.gradient...)` or theme tokens. Examples: `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/Settings/ThemePickerView.swift`.
- Reuse tile styling through `.floatingTile()` for feature cards and summary panels. Examples: `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`.
- Prefer `ContentUnavailableView`, `Menu`, `sheet`, `alert`, and `safeAreaInset` over custom containers when platform controls fit the need. Examples: `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/Runs/RunLogView.swift`.

**Previews:**
- Use modern `#Preview` macros instead of legacy `PreviewProvider`. Examples: `WorkingOut/App/ContentView.swift`, `WorkingOut/App/HealthAuthorizationBanner.swift`, `WorkingOut/Features/Settings/ThemePickerView.swift`.
- When a screen depends on SwiftData, provide a preview container from `PersistenceController.preview`. Example: `WorkingOut/App/ContentView.swift`.

## Module Design

**Exports:**
- Default module visibility is implicit internal; there is no public API surface or barrel-file pattern.
- Keep view-local helper types `private` where possible. Examples: `private struct DailyPoint` in `WorkingOut/Features/Runs/RunLogView.swift`, `private struct VitalCard` in `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`.

**Barrel Files:**
- Not used. Add new files directly under the relevant feature, model, service, component, or data directory rather than creating re-export layers.

**Repo-Specific Practices:**
- The Xcode project mirrors the filesystem via file-system-synchronized groups in `Pace & Plates.xcodeproj/project.pbxproj`. Add new Swift files in the correct folder on disk; the project should pick them up automatically.
- Keep quality-of-life debug hooks behind `#if DEBUG`. Existing examples include sample data controls in `WorkingOut/Features/Settings/SettingsView.swift` and legacy sample cleanup in `WorkingOut/App/ContentView.swift`.
- When adding manual feature work that needs follow-up verification, mirror the existing habit of shipping a root-level or `Docs/` markdown note with the checklist. Examples: `TESTING_GENERABLE.md`, `AI_GENERATION_FIX.md`, `MATERIAL_FADE_EFFECT.md`, `LIVE_ACTIVITY_QUICK_START.md`.

---

*Convention analysis: 2026-03-29*
*Update when patterns change*
