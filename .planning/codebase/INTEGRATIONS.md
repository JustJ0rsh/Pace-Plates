# External Integrations

**Analysis Date:** 2026-03-29

## APIs & External Services

**Health & Fitness APIs:**
- HealthKit - reads workouts, routes, vitals, sleep, steps, and body metrics; writes cardio workouts and route data back to Apple Health
  - SDK/Client: `HealthKit` via `WorkingOut/Services/HealthKitManager.swift`, with Health-backed views in `WorkingOut/Features/Home/Vitals/VitalsModel.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, and `WorkingOut/Features/Weight/WeightLogView.swift`
  - Auth: system Health permissions declared in `WorkingOut/Info.plist` (`NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`) and requested in `WorkingOut/Services/HealthKitManager.swift`
  - Notes: background workout observation is enabled with `HKObserverQuery` and background delivery in `WorkingOut/Services/HealthKitManager.swift`

**Location, Maps, and Weather:**
- Core Location + MapKit - tracks outdoor runs, renders route maps, and reverse-resolves location names
  - Integration method: `CLLocationManager` in `WorkingOut/Features/Runs/RunTrackingView.swift`; map rendering in `WorkingOut/Features/Runs/RunLogView.swift`; `MKLocalSearch` reverse lookups in `WorkingOut/Services/MapSearchService.swift`
  - Auth: location usage strings and background location mode in `WorkingOut/Info.plist`
  - Rate limits: `WorkingOut/Services/MapSearchService.swift` serializes `MKLocalSearch` calls and enforces a 4-second minimum delay
- WeatherKit - fetches current weather for the user’s location
  - Integration method: `WeatherKit.WeatherService` in `WorkingOut/Services/WeatherService.swift`
  - Auth: `com.apple.developer.weatherkit` entitlement in `WorkingOut/WorkingOut.entitlements`
  - Attribution: legal attribution link is surfaced in `WorkingOut/Features/Home/WeatherSummaryView.swift`

**On-Device AI:**
- Apple Intelligence / Foundation Models - generates workout plans, structured plan JSON, Q&A responses, and running-plan drafts on device
  - SDK/Client: `FoundationModels` and optional `AppleIntelligence` in `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, and `WorkingOut/Features/AI/PlanSchema.swift`
  - Auth: no API keys or remote credentials; gated by `OTHER_SWIFT_FLAGS = "-DAI_FOUNDATION_AVAILABLE"` in `Pace & Plates.xcodeproj/project.pbxproj` plus runtime `SystemLanguageModel` availability checks in `WorkingOut/App/ContentView.swift`
  - Network: no external AI HTTP client or third-party model SDK is detected; `WorkingOut/Services/WorkoutPlanGenerator.swift` explicitly notes that web search/tool calls are disabled

**Calendar & Reminder Services:**
- EventKit - schedules AI-generated training plans onto user calendars
  - SDK/Client: `WorkingOut/Services/WorkoutCalendarService.swift`
  - Auth: calendar usage strings in `WorkingOut/Info.plist`; permission requests in `WorkingOut/Services/WorkoutCalendarService.swift`
- UserNotifications - creates weekly weight reminders and running-plan reminders
  - SDK/Client: `WorkingOut/Services/ReminderService.swift`
  - Auth: local notification permission via `UNUserNotificationCenter.current()` in `WorkingOut/Services/ReminderService.swift`

**Game Services:**
- Game Center - authenticates the local player and submits leaderboard scores and streak achievements
  - SDK/Client: `WorkingOut/Services/GameCenterService.swift`
  - Auth: `GKLocalPlayer` authentication and access point presentation in `WorkingOut/Services/GameCenterService.swift`
  - Resources: bundled configuration in `WorkingOut/gameCenterResources.json` and `GameCenterResources.gamekit/gameCenterResources.json`

**System Experience Extensions:**
- ActivityKit + WidgetKit - powers the active-run Live Activity, lock-screen layout, and Dynamic Island presentation
  - SDK/Client: `WorkingOut/Services/LiveActivityManager.swift`, `RunningWidget/RunningLiveActivityWidget.swift`, and `RunningWidget/RunningWidgetBundle.swift`
  - Auth: Live Activity flags in `WorkingOut/Info.plist` and `RunningWidget/Info.plist`
  - Push model: local-only updates; `Activity.request(..., pushType: nil)` in `WorkingOut/Services/LiveActivityManager.swift`
- Quick Look Thumbnailing - generates document thumbnails for custom workout files
  - SDK/Client: `WorkoutThumbnailExtension/ThumbnailProvider.swift`
  - Registration: `WorkoutThumbnailExtension/Info.plist`

**Sharing & Document Exchange:**
- CoreTransferable + UniformTypeIdentifiers + UIKit share sheet - exports and imports workout files as custom document types
  - Integration method: `WorkingOut/Services/WorkoutSharingService.swift`, `WorkingOut/Components/ShareSheet.swift`, and `WorkingOut/App/WorkingOutApp.swift`
  - Formats: custom UTTypes `com.justj0rsh.paceandplates.ppworkout` and `com.justj0rsh.paceandplates.paceplate` declared in `WorkingOut/Services/WorkoutSharingService.swift` and `WorkingOut/Info.plist`
  - Import paths: `onOpenURL` handling in `WorkingOut/App/WorkingOutApp.swift` and security-scoped file access in `WorkingOut/Services/WorkoutSharingService.swift` and `WorkingOut/Features/Settings/SettingsView.swift`

## Data Storage

**Databases:**
- SwiftData local store with optional CloudKit private-database sync
  - Connection: `ModelContainer` is created in `WorkingOut/Data/PersistenceController.swift`
  - Client: `SwiftData` `ModelContainer` and `ModelContext` throughout `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/App/ContentView.swift`, and `WorkingOut/Features/**`
  - Migrations: no separate migration tooling is detected; schema is declared directly in code in `WorkingOut/Data/PersistenceController.swift`
  - Sync behavior: `.automatic` CloudKit backing with `.none` fallback on failure in `WorkingOut/Data/PersistenceController.swift`

**File Storage:**
- Local filesystem only for exported backups and share files
  - Export/import: `WorkingOut/Services/DataBackupService.swift` writes JSON backups to `FileManager.default.temporaryDirectory`
  - Workout sharing: `WorkingOut/Services/WorkoutSharingService.swift` writes `.paceplate` and `.ppworkout` files to `FileManager.default.temporaryDirectory`
  - File import UI: `WorkingOut/Features/Settings/SettingsView.swift` copies imported files into the app sandbox before processing

**Caching:**
- UserDefaults / `@AppStorage` only
  - Location-name cache: `WorkingOut/Services/MapSearchService.swift`
  - User settings and feature flags: `WorkingOut/App/ContentView.swift`, `WorkingOut/Services/ReminderService.swift`, and other feature views under `WorkingOut/Features/**`
  - Shared container: `group.Jorsh.WorkingOut` is declared in `WorkingOut/WorkingOut.entitlements` and `RunningWidget/RunningWidgetExtension.entitlements`; no `UserDefaults(suiteName:)` usage is currently detected

## Authentication & Identity

**Auth Provider:**
- No custom account system or backend auth provider is detected
  - Implementation: app data is device-local or Apple-account-backed through platform APIs rather than app-managed sessions
  - Token storage: not applicable
  - Session management: not applicable

**Apple Identity Surfaces:**
- CloudKit private database identity comes from the signed-in Apple ID used by `WorkingOut/Data/PersistenceController.swift` and enabled by `WorkingOut/WorkingOut.entitlements`
- Game Center identity comes from `GKLocalPlayer` in `WorkingOut/Services/GameCenterService.swift`

**OAuth Integrations:**
- None detected

## Monitoring & Observability

**Error Tracking:**
- None detected; no Sentry, Crashlytics, or third-party error SDK is present

**Analytics:**
- None detected; `WorkingOut/Features/Settings/PrivacyPolicyContent.swift` explicitly states that no advertising or analytics SDKs are used

**Logs:**
- Local console logging via `print` across `WorkingOut/Services/**`
- Structured save-error logging via `os.Logger` in `WorkingOut/Services/PersistenceSave.swift`

## CI/CD & Deployment

**Hosting:**
- Native Apple platform distribution only
  - Deployment: `Pace & Plates.app` is produced from `Pace & Plates.xcodeproj/project.pbxproj`, with `RunningWidgetExtension.appex` and `WorkoutThumbnailExtension.appex` embedded in the app target
  - Environment vars: none detected

**CI Pipeline:**
- None detected
  - Workflows: no `.github/workflows` files were found in the repository
  - Secrets: no CI secret configuration files were found in the repository

## Environment Configuration

**Development:**
- Required env vars: none detected
- Secrets location: Apple Developer signing, provisioning, and capability setup external to the repo; entitlements are declared in `WorkingOut/WorkingOut.entitlements` and `RunningWidget/RunningWidgetExtension.entitlements`
- Mock/stub services: AI falls back to template-based generation when Foundation Models are unavailable in `WorkingOut/Services/WorkoutPlanGenerator.swift`; persistence falls back to local SwiftData when CloudKit setup fails in `WorkingOut/Data/PersistenceController.swift`

**Staging:**
- Not detected

**Production:**
- Secrets management: Apple-managed entitlements, provisioning, and user-granted system permissions rather than app-managed secret files
- Failover/redundancy: CloudKit-backed SwiftData falls back to local storage in `WorkingOut/Data/PersistenceController.swift`; user-initiated JSON backup/export is available through `WorkingOut/Services/DataBackupService.swift`

## Webhooks & Callbacks

**Incoming:**
- File open callbacks into `WorkingOut/App/WorkingOutApp.swift` for custom workout documents declared in `WorkingOut/Info.plist`
  - Verification: files are decoded as `SharedWorkoutSession` in `WorkingOut/Services/WorkoutSharingService.swift`
  - Supported types: `com.justj0rsh.paceandplates.ppworkout` and `com.justj0rsh.paceandplates.paceplate`
  - Incoming payloads are size-capped and sanitized by `SharedWorkoutSession.decodeUntrusted` before use
- No custom URL scheme is registered or parsed; the former `paceandplates://share/workout` deep-link code was removed
- Quick Look thumbnail callbacks are handled by `WorkoutThumbnailExtension/ThumbnailProvider.swift`

**Outgoing:**
- No network webhooks or server callbacks are detected
- Apple-system callbacks are produced through local SDK calls only:
  - HealthKit read/write and background delivery in `WorkingOut/Services/HealthKitManager.swift`
  - Calendar event creation in `WorkingOut/Services/WorkoutCalendarService.swift`
  - Game Center score and achievement submission in `WorkingOut/Services/GameCenterService.swift`
  - Weather requests in `WorkingOut/Services/WeatherService.swift`
  - Live Activity updates in `WorkingOut/Services/LiveActivityManager.swift`

---

*Integration audit: 2026-03-29*
*Update when adding/removing external services*
