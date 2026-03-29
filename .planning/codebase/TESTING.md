# Testing Patterns

**Analysis Date:** 2026-03-29

## Test Framework

**Runner:**
- No automated test runner is active in the checked-in repository. There are no `*Tests/` directories, no `XCTest` source files, and `xcodebuild -list -project 'Pace & Plates.xcodeproj'` reports only the app and extension targets from `Pace & Plates.xcodeproj`.
- The shared scheme `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme` still references `Pace & PlatesTests.xctest` and `Pace & PlatesUITests.xctest`, but those targets are not present in `Pace & Plates.xcodeproj/project.pbxproj` and do not appear in `xcodebuild -list`.

**Assertion Library:**
- Not detected. No `XCTest`, snapshot library, or third-party assertion framework is present in the repo.

**Run Commands:**
```bash
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme 'WorkingOut' build
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme 'WorkingOut' analyze
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme 'WorkingOut' test
```
- Use `build` as the current automated quality gate for compilation.
- Use `analyze` for Xcode static analysis when touching persistence, threading, or UIKit bridges.
- The `test` command is currently not usable until real test targets are restored to `Pace & Plates.xcodeproj`.

## Test File Organization

**Location:**
- Not detected. There are no checked-in unit-test or UI-test source directories.
- The app code lives under `WorkingOut/`, with extension code in `RunningWidget/` and `WorkoutThumbnailExtension/`.

**Naming:**
- Not applicable for automated tests because no test files are present.
- Manual verification documents use descriptive feature-focused markdown names at the repository root or under `Docs/`. Examples: `TESTING_GENERABLE.md`, `AI_GENERATION_FIX.md`, `MATERIAL_FADE_EFFECT.md`, `WORKOUT_TEMPLATE_IMPLEMENTATION.md`, `LIVE_ACTIVITY_QUICK_START.md`, `Docs/App Bundle Cleanup/AI/UI_IMPROVEMENTS.md`.

**Structure:**
```text
Pace & Plates/
  Pace & Plates.xcodeproj/
  WorkingOut/
  RunningWidget/
  WorkoutThumbnailExtension/
  TESTING_GENERABLE.md
  AI_GENERATION_FIX.md
  MATERIAL_FADE_EFFECT.md
  LIVE_ACTIVITY_QUICK_START.md
  WORKOUT_TEMPLATE_IMPLEMENTATION.md
  # No Pace & PlatesTests/ or Pace & PlatesUITests/ directories are checked in
```

## Test Structure

**Suite Organization:**
```text
Current quality loop:
1. Build or run the `WorkingOut` scheme from `Pace & Plates.xcodeproj`.
2. Exercise the feature manually in the app, preview, simulator, or physical device.
3. Capture acceptance steps in a markdown checklist such as `WORKOUT_TEMPLATE_IMPLEMENTATION.md` or `AI_GENERATION_FIX.md`.
4. Use alerts, visible UI state, and console output to confirm success or failure paths.
```

**Patterns:**
- UI previews are the lightest-weight visual check. Examples: `#Preview` blocks in `WorkingOut/App/ContentView.swift`, `WorkingOut/App/HealthAuthorizationBanner.swift`, `WorkingOut/Features/Settings/ThemePickerView.swift`.
- In-memory preview data acts as the closest existing fixture setup. See `PersistenceController.preview` in `WorkingOut/Data/PersistenceController.swift`.
- Feature validation often relies on user-visible alerts and result banners rather than assertions. Examples: save/import/export alerts in `WorkingOut/Features/Settings/SettingsView.swift`, error alerts in `WorkingOut/App/ContentView.swift`, save failure alerts in `WorkingOut/Features/Weight/WeightLogView.swift`.
- Manual validation is especially important for HealthKit, location, Live Activities, AI generation, and Game Center because those paths cross system APIs and device capabilities. Representative files: `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Features/Runs/RunTrackingView.swift`, `RunningWidget/RunningLiveActivityWidget.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Services/GameCenterService.swift`.

## Mocking

**Framework:**
- Not detected. No mocking library or XCTest-based test doubles are present.

**Patterns:**
```swift
// Existing repo pattern for manual/preview data instead of mocks:
let controller = PersistenceController(inMemory: true)
let context = controller.container.mainContext

context.insert(WeightEntry(date: Date(), weight: 185.0, weightUnit: "lbs"))
context.insert(RunningSession(date: Date().addingTimeInterval(-86400),
                              distance: 5.0,
                              distanceUnit: "km",
                              duration: 1800,
                              locations: Data()))
```
- The snippet above comes from `WorkingOut/Data/PersistenceController.swift` and is the current seed pattern for previews.

**What to Mock:**
- When reintroducing automated tests, mock or wrap system-service boundaries first: `HealthKitManager` in `WorkingOut/Services/HealthKitManager.swift`, `MapSearchService` in `WorkingOut/Services/MapSearchService.swift`, `WeatherService` in `WorkingOut/Services/WeatherService.swift`, `GameCenterService` in `WorkingOut/Services/GameCenterService.swift`, and AI services in `WorkingOut/Services/WorkoutPlanGenerator.swift` and `WorkingOut/Services/RunAssistantAIService.swift`.
- Mock time, authorization status, and environment-dependent APIs for run tracking and reminders. Relevant files: `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Services/ReminderService.swift`, `WorkingOut/App/ContentView.swift`.

**What NOT to Mock:**
- Do not mock pure conversion and formatting helpers. Prefer direct assertions around `WorkingOut/Services/UnitConverter.swift`, prompt-building helpers in `WorkingOut/Services/AIPromptBuilder.swift`, and parsing/derivation helpers that do not cross system boundaries.
- Prefer real in-memory SwiftData for model and persistence behavior instead of mocking `ModelContext` when testing `@Model` interactions.

## Fixtures and Factories

**Test Data:**
```swift
// Preview fixture pattern used by the repo today
static var preview: PersistenceController = {
    let controller = PersistenceController(inMemory: true)
    let context = controller.container.mainContext

    ExerciseLibrary.populateInitialExercises(context: context)
    context.insert(WeightEntry(date: Date(), weight: 185.0, weightUnit: "lbs"))
    context.insert(RunningSession(date: Date().addingTimeInterval(-86400),
                                  distance: 5.0,
                                  distanceUnit: "km",
                                  duration: 1800,
                                  locations: Data()))
    try? context.save()
    return controller
}()
```
- This pattern is defined in `WorkingOut/Data/PersistenceController.swift`.
- `DebugDataGenerator` in `WorkingOut/Services/DebugDataGenerator.swift` is the other important quality hook. It creates and removes realistic sample data for DEBUG builds and is exposed from `WorkingOut/Features/Settings/SettingsView.swift`.

**Location:**
- Preview fixture setup lives in `WorkingOut/Data/PersistenceController.swift`.
- DEBUG-only manual data generation lives in `WorkingOut/Services/DebugDataGenerator.swift` and is triggered from the Debug section in `WorkingOut/Features/Settings/SettingsView.swift`.
- Built-in seed data for exercise and template flows lives in `WorkingOut/Data/ExerciseLibrary.swift`, `WorkingOut/Data/BuiltInTemplates.swift`, and `WorkingOut/Services/TemplateSeeder.swift`.

## Coverage

**Requirements:**
- No automated coverage target is enforced.
- No CI or repository-level quality workflow is configured to block merges on coverage.

**Configuration:**
- Not detected. There is no `.xctestplan`, no coverage script, and no coverage report path checked into the repo.

**View Coverage:**
```bash
# Not applicable until XCTest targets are restored
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme 'WorkingOut' test
```

## Test Types

**Unit Tests:**
- Not present.
- The best current candidates for first unit coverage are pure logic and parsers in `WorkingOut/Services/UnitConverter.swift`, `WorkingOut/Services/AIPromptBuilder.swift`, `WorkingOut/Features/AI/StructuredPlanCards.swift`, and mapping helpers in `WorkingOut/Services/WorkoutTemplateService.swift`.

**Integration Tests:**
- Not present as automated tests.
- Manual integration coverage exists through feature flows that cross SwiftData and Apple services. Examples include backup/import in `WorkingOut/Features/Settings/SettingsView.swift`, template seeding in `WorkingOut/App/ContentView.swift` plus `WorkingOut/Services/TemplateSeeder.swift`, and AI plan save/schedule flows in `WorkingOut/Features/AI/AIConversationSheet.swift`.

**E2E Tests:**
- Not present.
- Real-device smoke testing is explicitly required for Live Activities according to `LIVE_ACTIVITY_QUICK_START.md` because the simulator is insufficient for that path.

## Common Patterns

**Async Testing:**
```text
Current pattern is manual verification of async UI:
- Start a Task-based flow from the view.
- Watch progress UI or loading state.
- Confirm success via alert, updated model data, or console logging.
```
- Representative async flows: `Task { @MainActor in ... }` in `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/Runs/RunLogView.swift`.

**Error Testing:**
```text
Current pattern is checklist-driven:
- Trigger the failure path manually.
- Confirm the UI leaves the loading state.
- Confirm a user-facing message appears.
- Inspect console output for subsystem detail when needed.
```
- This pattern is explicitly documented in `AI_GENERATION_FIX.md` and reflected in production error surfaces like `healthAuthError` in `WorkingOut/App/ContentView.swift`, `saveErrorMessage` in `WorkingOut/Features/Weight/WeightLogView.swift`, and `healthSyncResultMessage` in `WorkingOut/Features/Settings/SettingsView.swift`.

**Snapshot Testing:**
- Not used.
- Visual regressions are currently caught through `#Preview` blocks, simulator runs, and markdown checklists such as `MATERIAL_FADE_EFFECT.md` and `Docs/App Bundle Cleanup/AI/UI_IMPROVEMENTS.md`.

## Manual QA Documents

**Feature Checklists:**
- `TESTING_GENERABLE.md` documents a guided-generation experiment, expected console output, and explicit success criteria for `WorkingOut/Services/WorkoutPlanGenerator.swift` and `WorkingOut/Features/AI/PlanSchema.swift`.
- `AI_GENERATION_FIX.md` records failure modes and verification steps for `WorkingOut/Features/AI/AIConversationSheet.swift` and `WorkingOut/Services/WorkoutPlanGenerator.swift`.
- `WORKOUT_TEMPLATE_IMPLEMENTATION.md` contains a feature checklist covering template creation, list display, workout creation, and order preservation across `WorkingOut/Services/WorkoutTemplateService.swift` and related workout screens.
- `MATERIAL_FADE_EFFECT.md` and `Docs/App Bundle Cleanup/AI/UI_IMPROVEMENTS.md` act as UI QA notes with before/after expectations and visual checks.
- `LIVE_ACTIVITY_QUICK_START.md` is a device-oriented smoke-test checklist for `RunningWidget/RunningLiveActivityWidget.swift` and run tracking integration.

**Operational QA Hooks:**
- `WorkingOut/Features/Settings/SettingsView.swift` exposes export/import, deduplication, health refresh, and DEBUG sample-data actions that double as manual regression tools.
- `WorkingOut/Services/DebugDataGenerator.swift` exists specifically to generate realistic sample data for manual testing in DEBUG builds.
- `WorkingOut/Features/Runs/RunLogView.swift` and `WorkingOut/Features/Workouts/WorkoutImportView.swift` contain verbose console diagnostics used during manual validation.

## Quality Maintenance Today

**What Maintains Quality:**
- Compile success on the `WorkingOut` scheme from `Pace & Plates.xcodeproj`.
- Manual feature walkthroughs, often accompanied by markdown checklists committed to the repo.
- SwiftUI previews backed by `PersistenceController.preview`.
- In-app debug utilities and sample data generation in DEBUG builds.
- Static analysis via `xcodebuild analyze`.

**Current Gaps:**
- No active automated unit, integration, or UI tests.
- The shared scheme contains stale references to missing test bundles.
- No CI pipeline, lint gate, or coverage gate is checked in.

**Practical Guidance For New Work:**
- If you add new behavior in `WorkingOut/Services/` or non-trivial derived-data logic in `WorkingOut/Features/`, add XCTest coverage with restored test targets instead of extending the checklist-only pattern.
- If you touch HealthKit, location, widgets, or AI streaming, keep a manual QA checklist in the PR or a repo markdown note because those paths depend on system state and are only partially previewable.
- Reuse `PersistenceController.preview` and `DebugDataGenerator` as the starting point for any new test fixtures or preview factories.

---

*Testing analysis: 2026-03-29*
*Update when test patterns change*
