- Bugs & Issues Inventory

- WeightLogView: references non-existent WeightEntry.notes
  - Location: WorkingOut/Features/Weight/WeightLogView.swift (previously around the chart selection summary)
  - Type: Compile-time error (property does not exist)
  - Impact: Build failure
  - Fix: Remove notes usage or add a notes field to WeightEntry; current code removed the notes block.

- WorkoutLogView: extraneous closing brace at file end
  - Location: WorkingOut/Features/Workouts/WorkoutLogView.swift (end of file)
  - Type: Compile-time error ("Extraneous '}' at top level")
  - Impact: Build failure
  - Fix: Remove the stray brace; done.

- WorkoutLogView: used ExerciseLog.sets (property doesn’t exist)
  - Location: WorkingOut/Features/Workouts/WorkoutLogView.swift (selected-day summary set counting)
  - Type: Compile-time error / logic error
  - Impact: Build failure; wrong counting logic
  - Fix: Each ExerciseLog represents one set; use logs.count (per session) instead.

- Heavy SwiftUI Chart expressions cause type-check timeouts
  - Locations: WeightLogView and WorkoutLogView chart sections
  - Type: Compiler performance ("unable to type-check … in reasonable time")
  - Impact: Build failures and slow compiles
  - Fix: Extracted chart blocks into small subviews and precomputed values; consider the same for any remaining large ViewBuilders (e.g., RunLogView chart if it grows).

- WorkoutLogView: unused locals left after refactor
  - Location: WorkingOut/Features/Workouts/WorkoutLogView.swift (calendar, yLowerV, yUpperV)
  - Type: Warnings / dead code
  - Impact: Noise; potential confusion
  - Fix: Remove unused variables; done.

- RunLogView: distance aggregation ignores units
  - Location: WorkingOut/Features/Runs/RunLogView.swift (daily distance grouping)
  - Type: Logic bug
  - Impact: Distances in mi and km are summed raw, producing incorrect totals and charts if units vary between sessions
  - Fix: Convert each session.distance from its distanceUnit to preferredDistanceUnit (or a common base) before aggregation.

- WeightLogView: history list shows raw units, not preferred unit
  - Location: WorkingOut/Features/Weight/WeightLogView.swift (History tile rows)
  - Type: UX / inconsistency
  - Impact: Chart uses preferred unit but history displays stored unit, confusing users
  - Fix: Convert entry.weight to preferred unit before rendering.

- Workout list label likely misnamed: "X exercises" counts sets
  - Location: WorkingOut/Features/Workouts/WorkoutLogView.swift (WorkoutSessionRowContent)
  - Type: UX / correctness
  - Impact: Label says exercises but counts ExerciseLog (sets), misleading users
  - Fix: Either show unique exercises (by definition/name) or relabel as "X sets".

- List embedded inside ScrollView with fixed height
  - Locations: WeightLogView and WorkoutLogView
  - Type: UI/layout smell
  - Impact: Potential clipping, incorrect heights, accessibility issues as counts grow
  - Fix: Prefer LazyVStack inside ScrollView or a standalone List without fixed-height frames.

- Widespread silent error swallowing on saves
  - Locations: Many files (e.g., WorkoutLogView, WeightLogView, WorkoutSessionDetailView, AddExerciseView, SettingsView, RunLogView, etc.)
  - Type: Error handling bug
  - Impact: Data-save failures are ignored; users can lose data with no feedback
  - Fix: Replace try? with do/try/catch, surface user-friendly alerts, and log details.

- PersistenceController fatalError on container init fallback
  - Location: WorkingOut/Data/PersistenceController.swift
  - Type: Crash risk
  - Impact: App can crash on initialization if local container fails
  - Fix: Avoid fatalError in production; show an error UI and attempt recovery or safe mode.

- WorkoutVolume chart selection UX inconsistency across tabs
  - Locations: WorkoutLogView vs WeightLogView
  - Type: UX inconsistency
  - Impact: Workout chart locks selection until close (via locked date), Weight chart dismisses immediately on selection change
  - Fix: Align behavior across charts (either both lock until close or both follow live selection).

- Duplicate convertWeight implementations
  - Locations: WeightLogView and WorkoutLogView (and possibly others)
  - Type: Maintainability
  - Impact: Risk of drift if conversion changes are needed
  - Fix: Extract a shared helper (e.g., WeightConverter) or extension used project-wide.

- Dead/unreferenced code
  - Examples:
    - WeightLogView: deleteWeightEntries(offsets:) appears unused
    - WorkoutLogView: backgroundGradient() not used
  - Type: Maintainability
  - Impact: Adds noise and confusion
  - Fix: Remove or wire up, and add tests if intended to be used.

- Debug prints in services
  - Locations: Multiple (TemplateSeeder, ReminderService, GameCenterService, LiveActivityManager, WorkoutTemplateService, WorkoutSharingService, StreakService, WorkoutPlanGenerator, etc.)
  - Type: Logging hygiene
  - Impact: Verbose console output in production, potential PII leakage
  - Fix: Gate with a logging utility and build flags; prefer os_log with privacy settings.

- AIConversationSheet uses try! with NSRegularExpression
  - Location: WorkingOut/Features/AI/AIConversationSheet.swift
  - Type: Crash risk
  - Impact: App will crash if a pattern is ever invalid (now or via edits)
  - Fix: Replace try! with do/try/catch; precompile once and assert in debug only.

- RunLogView TODO for elevation remains unimplemented
  - Location: WorkingOut/Features/Runs/RunLogView.swift (totalElevation)
  - Type: Missing feature / placeholder
  - Impact: Users may see "N/A" without explanation
  - Fix: Either implement with altitude data or soften UI copy and hide when unavailable.

- Category filtering normalization may be inconsistent
  - Location: WorkoutLogView.availableCategories()
  - Type: Data normalization
  - Impact: "Chest" vs "chest" or leading/trailing spaces could create duplicates elsewhere
  - Fix: Normalize by lowercasing and trimming at definition time; store canonical forms.

