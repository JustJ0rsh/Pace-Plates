# Codebase Concerns

**Analysis Date:** 2026-03-29

## Tech Debt

**Duplicate prevention is implemented as scattered cleanup code instead of schema guarantees:**
- Files: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Services/TemplateSeeder.swift`, `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Models/ExerciseDefinition.swift`, `WorkingOut/Models/RunningSession.swift`, `WorkingOut/Models/WorkoutSession.swift`, `WorkingOut/Models/WorkoutTemplate.swift`
- Issue: duplicate repair and fuzzy matching are spread across multiple import, seeding, and settings flows, while the SwiftData models do not declare unique attributes.
- Why: new data sources were added incrementally, so each flow added its own "similar item" heuristic or post-hoc dedupe pass.
- Impact: different entry points can insert, merge, or delete the same logical record differently; fixes must be repeated in several places; users can lose distinct sessions during cleanup.
- Fix approach: introduce canonical identifiers where available (`healthWorkoutUUID`, stable template/source IDs), add shared dedupe/import services, and move uniqueness policy into the model layer instead of per-screen heuristics.

**Health import logic is duplicated across feature surfaces:**
- Files: `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Services/HealthKitManager.swift`
- Issue: the app has two separate HealthKit cardio import flows with overlapping matching rules, deletion handling, and persistence behavior.
- Why: one path serves automatic Runs-tab import, while another path serves manual Settings import.
- Impact: behavior can drift between "automatic" and "manual" import, especially around linking similar runs, deletion propagation, and save semantics.
- Fix approach: move run import/link/delete logic into a single service with one matching policy and one persistence path.

**Core feature files are monoliths with mixed UI, persistence, integration, and transformation logic:**
- Files: `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Runs/RunAssistantDashboardView.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`
- Issue: several files exceed 1,000 lines, and `WorkingOut/Features/Runs/RunLogView.swift` is nearly 3,000 lines.
- Why: features were expanded in place instead of being split into service, view-model, parser, and renderer layers.
- Impact: small changes have broad regression risk, reasoning about ownership is slow, and targeted testing becomes impractical.
- Fix approach: extract import/enrichment logic, route processing, chart helpers, AI orchestration, and destructive settings actions into smaller units with explicit boundaries.

## Known Bugs

**Fuzzy dedupe can merge legitimate records that happen close together:**
- Files: `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Symptoms: distinct workouts, runs, or weight entries can be linked, skipped, or deleted as "duplicates."
- Trigger: importing backups or HealthKit data after two similar activities occur within the hard-coded time/distance windows, or after multiple same-day weight logs exist.
- Workaround: export data before running cleanup/import flows; avoid relying on dedupe for closely-spaced activities.
- Root cause: the app uses time-based and distance-based similarity windows because most entities lack stable uniqueness constraints.

**Calendar scheduling is not idempotent and ignores stored plan dates:**
- Files: `WorkingOut/Services/WorkoutCalendarService.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`
- Symptoms: scheduling the same generated plan more than once creates duplicate calendar events, and events always start from tomorrow rather than a persisted plan start date.
- Trigger: using the "schedule to calendar" flow repeatedly for the same AI conversation.
- Workaround: manually delete duplicate events in Calendar before scheduling again.
- Root cause: `WorkoutCalendarService.scheduleWorkoutPlan` creates fresh events every run, starts from `Date() + 1 day`, and does not check for previously-created events.

**Changing measurement system rewrites history in place and compounds rounding loss:**
- Files: `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Symptoms: switching between imperial and metric mutates stored workout, run, and body-weight values; repeated toggles can drift rounded values and change later matching behavior.
- Trigger: changing the measurement system after real history exists in the database.
- Workaround: treat the measurement-system setting as mostly one-time; restore from backup or HealthKit if historical drift becomes visible.
- Root cause: `applyMeasurementSystemChange` converts persisted values instead of storing canonical base units and formatting at read time.

## Security Considerations

**Backups and imports move sensitive health, location, and AI data through plaintext temp files:**
- Files: `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Models/AIConversation.swift`, `WorkingOut/Models/RunningSession.swift`
- Risk: exported JSON contains route payloads, workout history, body weight, AI prompts, and AI responses; import copies files into the app temp directory and does not remove the copied file after success.
- Current mitigation: export/import is user-initiated and limited to the app sandbox.
- Recommendations: encrypt and sign backup files, delete temporary copies after use, minimize exported route precision when possible, and present an explicit sensitivity warning before export/share.

**Location and prompt data are stored or logged without privacy boundaries:**
- Files: `WorkingOut/Services/MapSearchService.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Features/Workouts/WorkoutImportView.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Risk: `MapSearchService` persists rounded coordinates in `UserDefaults`; AI prompt prefixes and workout/template details are written with `print`, which can expose fitness history and free-form user input in device logs.
- Current mitigation: none beyond default sandboxing.
- Recommendations: replace `print` with `Logger` using privacy redaction, stop logging prompt content, and avoid storing readable coordinate caches unless the UX gain justifies the privacy cost.

**Legacy share URLs embed raw workout JSON in the URL itself:**
- Files: `WorkingOut/Services/WorkoutSharingService.swift`
- Risk: the custom URL scheme path base64-encodes the full workout payload into a query string, which can leak through logs, previews, and URL length limits.
- Current mitigation: file-based `Transferable` sharing exists as a safer alternative.
- Recommendations: retire the URL-based fallback, or replace it with a signed opaque token and an import lookup flow.

## Performance Bottlenecks

**AI prompt generation scans the full local dataset on each request:**
- Files: `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/ExerciseRecommendationService.swift`, `WorkingOut/Services/AIPromptBuilder.swift`
- Problem: every AI request fetches all workouts, runs, exercise definitions, weights, and exercise logs before filtering in memory.
- Measurement: `collectRecentStats` fetches unbounded tables, and `ExerciseRecommendationService.baselines` reads every `ExerciseLog` row each time.
- Cause: aggregation is computed at request time instead of from precomputed summaries or query-level filters.
- Improvement path: fetch only recent rows, cache exercise baselines, and precompute summary tables used by AI prompts.

**Run detail rendering recomputes route caches on demand from opaque JSON blobs:**
- Files: `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Models/RunningSession.swift`
- Problem: saved routes are decoded, simplified, segmented, and charted when the detail UI loads.
- Measurement: the code includes explicit decode/render timing logs, persists up to 1,400 points per run, and trims map rendering to 700 points.
- Cause: routes are stored as JSON blobs with derived map/elevation artifacts recalculated inside the detail view layer.
- Improvement path: cache derived route summaries at save/enrichment time and move map/profile preprocessing out of the view.

**Location enrichment throughput is intentionally low and becomes backlogged on large histories:**
- Files: `WorkingOut/Services/MapSearchService.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Problem: route name enrichment and HealthKit detail enrichment are throttled hard enough that backfills can take many app sessions.
- Measurement: `MapSearchService` enforces a 4-second minimum delay, `RunLogView` only prefetches 3 locations concurrently, imports 10 workouts by default (8 on forced import), and processes only 2 enrichments per pass.
- Cause: rate-limit protection and view-owned work scheduling were added without a durable background queue.
- Improvement path: persist a background worklist, batch enrichment outside the view lifecycle, and add explicit UI for pending enrichment progress.

## Fragile Areas

**Run tracking, import, enrichment, and analytics are tightly coupled across one feature stack:**
- Files: `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Services/MapSearchService.swift`
- Why fragile: tracking, HealthKit writes, diff import, route enrichment, geocoding, map rendering, splits, deletion, and charts all interact across a small set of files.
- Common failures: duplicate runs, missing route/elevation metrics, delayed enrichment, or slow detail rendering after a change in one area.
- Safe modification: change this stack through extracted services with fixtures for imported/local runs, and validate both local-only and HealthKit-linked paths.
- Test coverage: no committed test files exercise this path.

**Settings is a destructive control surface with too many unrelated responsibilities:**
- Files: `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Data/PersistenceController.swift`
- Why fragile: unit conversion, backup import/export, HealthKit import, dedupe, full-data deletion, reminder settings, and theme/profile changes all live together.
- Common failures: destructive cleanup side effects, incorrect unit rewrites, leftover temp files, and hard-to-reproduce data repair bugs.
- Safe modification: move import/export, dedupe, and destructive data operations into dedicated services with dry-run or preview support before execution.
- Test coverage: no automation covers these flows.

**Live Activity state is duplicated across targets instead of shared:**
- Files: `WorkingOut/Services/LiveActivityManager.swift`, `RunningWidget/RunningLiveActivityWidget.swift`
- Why fragile: both targets define `RunningActivityAttributes` separately, so every schema change must be kept in sync manually.
- Common failures: build breaks or runtime mismatches when one side adds/removes fields and the other side lags behind.
- Safe modification: move the activity attributes into a shared source file included by both the app and widget targets.
- Test coverage: no widget or activity contract tests are present.

**AI feature availability and fallback behavior are spread across many files:**
- Files: `WorkingOut/App/ContentView.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/Runs/RunAssistantDashboardView.swift`, `WorkingOut/Features/AI/PlanSchema.swift`
- Why fragile: compile flags, iOS 26 availability checks, prompt truncation, guided-generation parsing, and persistence rules are distributed across UI and service layers.
- Common failures: hidden AI tabs, degraded fallback output, broken structured-plan parsing, and inconsistent saved AI state after provider changes.
- Safe modification: introduce a single AI provider boundary with deterministic fixtures for schema parsing and fallback cases.
- Test coverage: no automated AI parsing or persistence tests are committed.

## Scaling Limits

**Health import and enrichment throughput is capped by small hard-coded windows:**
- Files: `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Services/HealthKitManager.swift`
- Current capacity: default import reads 10 workouts, forced import reads 8, auto enrichment queues 3 UUIDs, and only 2 enrichments are processed per pass.
- Limit: large backfills or multi-device HealthKit histories will take repeated launches or long idle time to fully populate local detail fields.
- Symptoms at limit: newly imported runs appear without routes, elevation, cadence, or HR metrics for an extended time.
- Scaling path: move import/enrichment to a persisted background queue with resumable checkpoints and progress visibility.

**On-device AI scales linearly with database size and context complexity:**
- Files: `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/ExerciseRecommendationService.swift`, `WorkingOut/Services/RunAssistantAIService.swift`
- Current capacity: each request loads whole tables and then clamps prompt size to 3,500 characters (or 900 characters for Ask mode).
- Limit: as logs and history grow, latency rises and context-overflow fallback becomes more frequent.
- Symptoms at limit: slower first token, more fallback plans, and more prompt-compaction behavior.
- Scaling path: precompute summaries, query windows directly, and persist AI-ready aggregates instead of rebuilding them from raw history every time.

**Route fidelity is bounded by storage and rendering caps:**
- Files: `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Current capacity: the tracker stores up to 1,400 route points, and the detail map reduces that to 700 points for rendering.
- Limit: long or dense GPS sessions lose detail, while still carrying enough data to make rendering expensive.
- Symptoms at limit: simplified maps/elevation profiles and slower route detail loads.
- Scaling path: use polyline compression plus precomputed summaries instead of raw JSON point arrays as the primary persisted form.

## Dependencies at Risk

**FoundationModels / Apple Intelligence is a cross-cutting dependency with broad fallback behavior:**
- Files: `Pace & Plates.xcodeproj/project.pbxproj`, `WorkingOut/App/ContentView.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`
- Risk: AI features depend on `-DAI_FOUNDATION_AVAILABLE`, iOS 26 availability, and device eligibility; any SDK/API shift affects multiple screens and services at once.
- Impact: AI tabs can disappear, generation can fall back unexpectedly, and maintenance cost spans much of the app.
- Migration plan: hide the Apple Intelligence dependency behind one provider protocol and keep the non-AI/template path production-ready.

**CloudKit-backed SwiftData silently falls back to local storage:**
- Files: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/WorkingOut.entitlements`
- Risk: when CloudKit container creation fails, the app drops to a local-only store without surfacing that state to the user.
- Impact: users can believe they are synced while operating on an unsynced local database.
- Migration plan: add explicit sync-state reporting, user-visible recovery guidance, and telemetry for CloudKit fallback events.

**MapKit search-rate limits directly affect run-location labeling:**
- Files: `WorkingOut/Services/MapSearchService.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Risk: the current place lookup strategy is intentionally throttled to avoid Apple limits, so the integration is operationally fragile under larger histories.
- Impact: location labels remain blank or delayed even when route data exists.
- Migration plan: move location resolution to a dedicated background queue and reassess whether `MKLocalSearch` is the right API for nearest-address labeling.

## Missing Critical Features

**Automated regression coverage for persistence and integration flows:**
- Files: `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`, `Pace & Plates.xcodeproj/project.pbxproj`, `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`
- Problem: the shared scheme still references `Pace & PlatesTests` and `Pace & PlatesUITests`, but the project only lists app/extension targets and no test source tree is committed.
- Current workaround: manual in-app verification.
- Blocks: safe refactors of import, sync, conversion, deletion, and AI parsing behavior.
- Implementation complexity: medium initial setup, then low-to-medium ongoing cost.

**Secure, auditable backup handling:**
- Files: `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Features/Settings/SettingsView.swift`
- Problem: backup/export is plaintext, unsigned, temp-file based, and not cleaned up after every path.
- Current workaround: users must manually treat exported files as sensitive.
- Blocks: a privacy-safe backup and restore story for real user data.
- Implementation complexity: medium.

**User-visible sync/import health diagnostics:**
- Files: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`
- Problem: there is no UI for CloudKit fallback state, HealthKit import backlog, or pending enrichment work.
- Current workaround: rely on console logs and manual repair actions in Settings.
- Blocks: debugging "missing runs," "missing sync," and "why is this run incomplete?" support issues.
- Implementation complexity: medium.

## Test Coverage Gaps

**Persistence, migration, and cleanup flows:**
- Files: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Services/DataBackupService.swift`, `WorkingOut/Services/TemplateSeeder.swift`, `WorkingOut/Features/Settings/SettingsView.swift`
- What's not tested: CloudKit fallback, import/export round-trips, dedupe heuristics, built-in template seeding, destructive cleanup, and measurement-system conversion.
- Risk: silent data loss, irreversible merges, or unsynced local-only behavior can ship unnoticed.
- Priority: High
- Difficulty to test: Medium

**HealthKit import/writeback and run enrichment:**
- Files: `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Services/MapSearchService.swift`
- What's not tested: saving local runs to HealthKit, importing added/deleted workouts, linking similar runs, route enrichment, and location throttling behavior.
- Risk: duplicate or missing runs, incomplete metrics, and delayed geocoding regressions.
- Priority: High
- Difficulty to test: High

**AI generation, persistence, and template conversion:**
- Files: `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, `WorkingOut/Features/AI/PlanSchema.swift`
- What's not tested: structured-plan parsing, prompt overflow fallback, conversation persistence, and AI-to-template conversion.
- Risk: malformed plans can be saved to the database or rendered incorrectly without early detection.
- Priority: High
- Difficulty to test: Medium

**Widget and Live Activity contract parity:**
- Files: `WorkingOut/Services/LiveActivityManager.swift`, `RunningWidget/RunningLiveActivityWidget.swift`
- What's not tested: schema compatibility between app and widget targets, update lifecycle behavior, and end-state cleanup.
- Risk: one side can change the activity shape and break the other side at build time or runtime.
- Priority: Medium
- Difficulty to test: Medium

---

*Concerns audit: 2026-03-29*
*Update as issues are fixed or new ones discovered*
