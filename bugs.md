# Bugs & Issues Inventory

Last verified against the codebase on 2026-08-28. Items are split into what is
still open and what has been confirmed fixed, so this file reflects the actual
release state instead of accumulating history.

## Open

- Duplicate `convertWeight` implementations
  - Locations: `WorkingOut/Services/ExerciseRecommendationService.swift`, `WorkingOut/Services/AIPromptBuilder.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift` (private static copies)
  - Type: Maintainability
  - Impact: Risk of drift if conversion rules change; `UnitConverter` already exists and is used by the UI layer
  - Fix: Replace the three private copies with `UnitConverter.weight(_:from:to:)`.

- Debug prints in services
  - Locations: ~50 `print(...)` calls across `WorkingOut/Services/` (WearableWorkoutInboxService, WorkoutTemplateService, WorkoutPlanGenerator, LiveActivityManager, WorkoutSharingService, TemplateSeeder, RunAssistantService, StreakService, ReminderService, GameCenterService, WorkoutCalendarService, RunAssistantAIService)
  - Type: Logging hygiene
  - Impact: Verbose console output in production, potential PII leakage
  - Fix: Migrate to `os.Logger` with privacy annotations (see `PersistenceSave` for the established pattern).

- Run detail elevation shows "N/A"
  - Location: `WorkingOut/Features/Runs/RunLogView.swift` (`totalElevation`)
  - Type: Missing feature / placeholder
  - Impact: Users see "N/A" with no explanation
  - Note: `RunningSession` now stores `totalAscent`/`totalDescent`/`minElevation`/`maxElevation` (computed at save time by `RunTracker.calculateElevationMetrics`), so the detail view can render real values for new sessions; older sessions lack the data.

- Category filtering normalization is case-sensitive
  - Location: `WorkoutLogView.availableCategories()`
  - Type: Data normalization
  - Impact: Whitespace is now trimmed, but "Chest" vs "chest" would still create duplicate filter entries
  - Fix: Normalize casing at definition time; store canonical forms.

## Resolved (verified)

- Run loss on process death — **fixed 2026-08-28.** `RunTracker` now persists a durable draft of the in-progress session (`WorkingOut/Models/RunDraft.swift`, stored via `WorkingOut/Services/CodableFileStore.swift`) on start/pause/resume and throttled during ticks/location updates. On relaunch the draft is restored in a paused state (dead time never counts toward the run), which plugs into the existing recovery UX (Home resume card, Runs banner, paused Resume/Save controls). Surviving Live Activities are adopted and frozen to the restored snapshot; stale drafts (>24h) are discarded and orphaned activities ended. Logic covered by `scripts/run_draft_logic_test_main.swift`.

- Home weather tile stuck on "—" during startup — **fixed 2026-08-28.** `WeatherViewModel` now caches the last successful summary (`WorkingOut/Services/WeatherSummaryCache.swift`) and renders it immediately on launch, shows an explicit "Updating weather…" loading state, keeps the previous value on refresh failures, and shows neutral copy instead of a bare dash when location isn't available. See `WEATHER_STARTUP_DELAY_FOLLOWUP.md`.

- `PersistenceController` fatalError on container init fallback — **fixed 2026-08-28.** When both the CloudKit-backed and local stores fail to open, the app now falls back to a temporary in-memory store (safe mode) and surfaces an alert (`startupSafeModeMessage` in `ContentView`) instead of crashing at launch. The remaining `fatalError` only triggers if the model schema itself cannot load (a programming error).

- WeightLogView referenced non-existent `WeightEntry.notes` — fixed; the notes block was removed.
- WorkoutLogView extraneous closing brace — fixed.
- WorkoutLogView used non-existent `ExerciseLog.sets` — fixed; rows now show unique exercise names (`exerciseCount`) and a separate `setCount`.
- Heavy SwiftUI chart expressions caused type-check timeouts — fixed by extracting chart blocks into subviews with precomputed values.
- WorkoutLogView unused locals after refactor — removed.
- RunLogView distance aggregation ignored units — fixed; sessions are converted via `UnitConverter.distance(_:from:to:)` before daily aggregation.
- WeightLogView history showed raw stored units — fixed; rows convert to the preferred unit via `UnitConverter.weight(_:from:to:)`.
- "X exercises" label counted sets — fixed; see `WorkoutSessionRowContent`.
- `List` embedded in `ScrollView` with fixed height — no longer present in WeightLogView/WorkoutLogView.
- Widespread silent error swallowing on saves — fixed; saves route through `PersistenceSave.commit(_:action:userMessage:onFailure:)`, which logs via `os.Logger` and surfaces user-facing alerts.
- Workout/Weight chart selection UX inconsistency — aligned; both charts keep the selection summary open until explicitly closed (`lockedChartDate`).
- Dead code (`deleteWeightEntries(offsets:)`, `backgroundGradient()`) — removed.
- `try!` with `NSRegularExpression` in AIConversationSheet — removed; no `try!` remains in app code.
