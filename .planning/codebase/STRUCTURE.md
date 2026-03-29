# Codebase Structure

**Analysis Date:** 2026-03-29

## Directory Layout

```text
Pace & Plates/
├── WorkingOut/                  # Main app target source, resources, and configuration
│   ├── App/                     # App entry and root composition
│   ├── Features/                # Feature-first SwiftUI screens grouped by domain
│   ├── Models/                  # SwiftData models and lightweight shared helpers
│   ├── Data/                    # Persistence controller and static catalogs/seeds
│   ├── Services/                # Integration services and shared workflows
│   ├── Components/              # Reusable UI pieces and wrappers
│   ├── Theme/                   # Global theme tokens and view modifiers
│   ├── Resources/               # Non-asset-catalog images for custom document icons
│   ├── Assets.xcassets/         # Main app colors, icons, and image assets
│   ├── Preview Content/         # SwiftUI preview assets
│   ├── Info.plist               # App capabilities, document types, permissions
│   └── WorkingOut.entitlements  # App entitlements
├── RunningWidget/               # Widget extension target for Live Activity rendering
├── WorkoutThumbnailExtension/   # Quick Look thumbnail extension for workout files
├── Pace & Plates.xcodeproj/     # Xcode project and target wiring
├── GameCenterResources.gamekit/ # Game Center resource definitions
├── AchievementImages/           # Achievement artwork source assets
├── LeaderboardImages/           # Leaderboard artwork source assets
├── Docs/                        # Design and cleanup notes
├── scripts/                     # Small Python maintenance/import utilities
├── .planning/codebase/          # Generated codebase reference docs
├── README.md                    # Project overview and developer orientation
└── *.md                         # Root-level implementation notes and plans
```

## Directory Purposes

**`WorkingOut/`:**
- Purpose: Main iOS app target root.
- Contains: All production Swift source for the app, plus target config and resources.
- Key files: `WorkingOut/Info.plist`, `WorkingOut/WorkingOut.entitlements`, `WorkingOut/gameCenterResources.json`
- Subdirectories: `App/`, `Features/`, `Models/`, `Data/`, `Services/`, `Components/`, `Theme/`, `Resources/`, `Assets.xcassets/`, `Preview Content/`

**`WorkingOut/App/`:**
- Purpose: App entry and root-level composition.
- Contains: App startup, root tab shell, and top-level environment setup.
- Key files: `WorkingOut/App/WorkingOutApp.swift`, `WorkingOut/App/ContentView.swift`, `WorkingOut/App/HealthAuthorizationBanner.swift`
- Subdirectories: None

**`WorkingOut/Features/`:**
- Purpose: User-facing feature code grouped by domain, not by technical layer.
- Contains: SwiftUI screens, sheets, dashboard flows, view-local helper types, and feature-scoped subviews.
- Key files: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/AI/AIPlannerView.swift`, `WorkingOut/Features/Settings/SettingsView.swift`
- Subdirectories: `AI/`, `Community/`, `Home/`, `Home/Vitals/`, `Onboarding/`, `Runs/`, `Settings/`, `Weight/`, `Workouts/`

**`WorkingOut/Features/Home/`:**
- Purpose: Dashboard, streak, weather, and vitals surfaces that aggregate data from other domains.
- Contains: `HomeView.swift`, `StreakCalendarView.swift`, `WeatherSummaryView.swift`, plus nested vitals files under `Vitals/`
- Key files: `WorkingOut/Features/Home/HomeView.swift`, `WorkingOut/Features/Home/Vitals/VitalsModel.swift`, `WorkingOut/Features/Home/Vitals/VitalsSnapshotView.swift`
- Subdirectories: `Vitals/`

**`WorkingOut/Features/Runs/`:**
- Purpose: Run history, live tracking, and run-assistant planning.
- Contains: The largest feature files in the repo, including tracking UI, HealthKit enrichment, assistant onboarding, assistant dashboard, and profile editing.
- Key files: `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Features/Runs/RunAssistantContainerView.swift`, `WorkingOut/Features/Runs/RunAssistantDashboardView.swift`
- Subdirectories: None

**`WorkingOut/Features/Workouts/`:**
- Purpose: Strength/cardio workout logging, templates, session details, and import flows.
- Contains: Workout list/detail/edit screens, template browser, and imported-workout handling.
- Key files: `WorkingOut/Features/Workouts/WorkoutLogView.swift`, `WorkingOut/Features/Workouts/WorkoutSessionDetailView.swift`, `WorkingOut/Features/Workouts/WorkoutTemplateListView.swift`, `WorkingOut/Features/Workouts/WorkoutImportView.swift`
- Subdirectories: None

**`WorkingOut/Features/AI/`:**
- Purpose: AI planning, AI chat, AI history, and structured plan presentation.
- Contains: Planner entry screens, streaming conversation sheets, history views, and supporting schema/presentation helpers.
- Key files: `WorkingOut/Features/AI/AIPlannerView.swift`, `WorkingOut/Features/AI/AIConversationSheet.swift`, `WorkingOut/Features/AI/AIChatSheet.swift`, `WorkingOut/Features/AI/AIHistoryView.swift`, `WorkingOut/Features/AI/PlanSchema.swift`
- Subdirectories: None

**`WorkingOut/Features/Settings/`:**
- Purpose: Preferences, profile data, health sync triggers, backup/import actions, and theme selection.
- Contains: Settings list screens and supporting views.
- Key files: `WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Settings/ThemePickerView.swift`, `WorkingOut/Features/Settings/PrivacyPolicyView.swift`, `WorkingOut/Features/Settings/PrivacyPolicyContent.swift`
- Subdirectories: None

**`WorkingOut/Features/Weight/`:**
- Purpose: Weight history and entry logging.
- Contains: Weight chart/list screens and the `LogWeightView` entry sheet.
- Key files: `WorkingOut/Features/Weight/WeightLogView.swift`, `WorkingOut/Features/Weight/LogWeightView.swift`
- Subdirectories: None

**`WorkingOut/Features/Onboarding/`:**
- Purpose: Initial profile setup and tutorial flow.
- Contains: A single multi-step onboarding screen.
- Key files: `WorkingOut/Features/Onboarding/TutorialView.swift`
- Subdirectories: None

**`WorkingOut/Features/Community/`:**
- Purpose: Community/Game Center entry point.
- Contains: `CommunityView.swift`
- Key files: `WorkingOut/Features/Community/CommunityView.swift`
- Subdirectories: None

**`WorkingOut/Models/`:**
- Purpose: Persistent model definitions and lightweight app-wide helper types.
- Contains: SwiftData `@Model` classes plus a small number of helper files such as `Haptics.swift` and `KeyboardHelpers.swift`.
- Key files: `WorkingOut/Models/WorkoutSession.swift`, `WorkingOut/Models/ExerciseLog.swift`, `WorkingOut/Models/RunningSession.swift`, `WorkingOut/Models/RunningPlan.swift`, `WorkingOut/Models/AIConversation.swift`, `WorkingOut/Models/WorkoutTemplate.swift`
- Subdirectories: None

**`WorkingOut/Data/`:**
- Purpose: Persistence bootstrapping and static catalog data that seed or describe the domain.
- Contains: `PersistenceController.swift`, exercise/template catalogs, and run plan catalogs.
- Key files: `WorkingOut/Data/PersistenceController.swift`, `WorkingOut/Data/ExerciseLibrary.swift`, `WorkingOut/Data/BuiltInTemplates.swift`, `WorkingOut/Data/RunPlanCatalog.swift`
- Subdirectories: None

**`WorkingOut/Services/`:**
- Purpose: Side effects, multi-step domain workflows, and integrations with Apple/system APIs.
- Contains: Service singletons and helper types for HealthKit, ActivityKit, Game Center, weather, AI generation, reminders, backup, sharing, template seeding, run planning, and unit conversion.
- Key files: `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Services/LiveActivityManager.swift`, `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantService.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, `WorkingOut/Services/WorkoutTemplateService.swift`, `WorkingOut/Services/WorkoutSharingService.swift`
- Subdirectories: None

**`WorkingOut/Components/`:**
- Purpose: Reusable UI utilities used across multiple features.
- Contains: View modifiers, UIKit bridge wrappers, and markdown/share helpers.
- Key files: `WorkingOut/Components/FloatingTile.swift`, `WorkingOut/Components/GlassBackground.swift`, `WorkingOut/Components/ShareSheet.swift`, `WorkingOut/Components/MarkdownView.swift`
- Subdirectories: None

**`WorkingOut/Theme/`:**
- Purpose: Global design tokens and background helpers.
- Contains: The `AppTheme` palette, theme enum, and shared background helpers.
- Key files: `WorkingOut/Theme/AppTheme.swift`
- Subdirectories: None

**`RunningWidget/`:**
- Purpose: Widget extension target that renders the running Live Activity.
- Contains: Widget bundle entry, widget UI, target plist, assets, and entitlements.
- Key files: `RunningWidget/RunningWidgetBundle.swift`, `RunningWidget/RunningLiveActivityWidget.swift`, `RunningWidget/Info.plist`, `RunningWidget/RunningWidgetExtension.entitlements`
- Subdirectories: `Assets.xcassets/`

**`WorkoutThumbnailExtension/`:**
- Purpose: Quick Look thumbnail extension for custom workout documents.
- Contains: Thumbnail provider implementation, target plist, and icon resources.
- Key files: `WorkoutThumbnailExtension/ThumbnailProvider.swift`, `WorkoutThumbnailExtension/Info.plist`
- Subdirectories: `Resources/`

**`Pace & Plates.xcodeproj/`:**
- Purpose: Xcode project definition for the three targets.
- Contains: Project file, workspace metadata, schemes, and storyboard.
- Key files: `Pace & Plates.xcodeproj/project.pbxproj`, `Pace & Plates.xcodeproj/LaunchScreen.storyboard`
- Subdirectories: `project.xcworkspace/`, `xcshareddata/`, `xcuserdata/`

**`GameCenterResources.gamekit/`:**
- Purpose: Game Center metadata used alongside `GameCenterService`.
- Contains: Localization/resources JSON for achievements and leaderboards.
- Key files: `GameCenterResources.gamekit/gameCenterResources.json`
- Subdirectories: `en-US/`

**`AchievementImages/` and `LeaderboardImages/`:**
- Purpose: Source image assets for Game Center achievements and leaderboards.
- Contains: Image folders grouped by achievement or board name.
- Key files: Representative folders such as `AchievementImages/30-Day Streak/` and `LeaderboardImages/Longest Run/`
- Subdirectories: One folder per asset family

**`Docs/`:**
- Purpose: Supporting internal notes and cleanup writeups.
- Contains: Markdown docs under `Docs/App Bundle Cleanup/`
- Key files: `Docs/App Bundle Cleanup/AI/AI_IMPROVEMENTS.md`, `Docs/App Bundle Cleanup/Legal/PRIVACY.md`
- Subdirectories: `App Bundle Cleanup/AI/`, `App Bundle Cleanup/Legal/`

**`scripts/`:**
- Purpose: Local maintenance utilities outside the shipped app.
- Contains: Python scripts for importing or syncing Game Center assets.
- Key files: `scripts/asc_sync_gamecenter_images.py`, `scripts/import_achievements.py`
- Subdirectories: `__pycache__/`

**`.planning/codebase/`:**
- Purpose: Generated architecture/stack/testing/reference docs for GSD workflows.
- Contains: Markdown documents such as this file.
- Key files: `.planning/codebase/ARCHITECTURE.md`, `.planning/codebase/STRUCTURE.md`
- Subdirectories: None

## Key File Locations

**Entry Points:**
- `WorkingOut/App/WorkingOutApp.swift`: Main app `@main` entry for the `Pace & Plates` target.
- `WorkingOut/App/ContentView.swift`: Root tab shell and top-level model container injection.
- `RunningWidget/RunningWidgetBundle.swift`: Widget extension `@main` entry.
- `WorkoutThumbnailExtension/ThumbnailProvider.swift`: Quick Look thumbnail extension entry implementation.

**Configuration:**
- `Pace & Plates.xcodeproj/project.pbxproj`: Target definitions, embed relationships, bundle IDs, entitlements, and filesystem-synchronized root groups.
- `WorkingOut/Info.plist`: Main app permissions, background modes, Live Activity support, and custom document type declarations.
- `WorkingOut/WorkingOut.entitlements`: Main app entitlements for HealthKit, CloudKit, Game Center, WeatherKit, push, and app groups.
- `RunningWidget/Info.plist`: Widget extension registration and Live Activity support.
- `RunningWidget/RunningWidgetExtension.entitlements`: Widget extension app-group entitlement.
- `WorkoutThumbnailExtension/Info.plist`: Quick Look thumbnail extension registration and supported content types.

**Core Logic:**
- `WorkingOut/Features/`: Feature-specific SwiftUI screens.
- `WorkingOut/Models/`: SwiftData model graph and shared helper types.
- `WorkingOut/Data/PersistenceController.swift`: Shared `ModelContainer` creation and persistence maintenance.
- `WorkingOut/Services/`: System integrations, AI, sharing, seeding, backup, reminders, and domain workflows.

**Testing:**
- Not detected. No `*Tests` or `*UITests` target directories are present in the repository root.

**Documentation:**
- `README.md`: High-level project overview and folder orientation.
- `PRIVACY.md`: Privacy-focused project document at the repository root.
- Root `*.md` planning files such as `LIVE_ACTIVITY_SETUP.md`, `WORKOUT_TEMPLATE_IMPLEMENTATION.md`, and `MYNETDIARY_INTEGRATION_PLAN.md`: implementation notes and historical planning artifacts.
- `Docs/`: Additional internal markdown notes.

## Naming Conventions

**Files:**
- `PascalCase.swift`: Default pattern for Swift types, SwiftUI views, services, models, and helpers. Examples: `WorkoutLogView.swift`, `HealthKitManager.swift`, `PersistenceController.swift`, `AppTheme.swift`.
- `*View.swift`: Root or reusable SwiftUI view files. Examples: `HomeView.swift`, `SettingsView.swift`, `ThemePickerView.swift`, `PrivacyPolicyView.swift`.
- `*Service.swift` or `*Manager.swift`: Integration and workflow classes. Examples: `WorkoutTemplateService.swift`, `GameCenterService.swift`, `HealthKitManager.swift`, `ReminderService.swift`.
- `*Bundle.swift` / `*App.swift`: Target entry files. Examples: `RunningWidgetBundle.swift`, `WorkingOutApp.swift`.

**Directories:**
- `PascalCase` or title-case target folders at the root: `WorkingOut/`, `RunningWidget/`, `WorkoutThumbnailExtension/`.
- `Features/<Domain>/`: Feature folders are grouped by user-facing domain and use plural or noun-based names. Examples: `Workouts/`, `Runs/`, `Weight/`, `Settings/`, `Home/`.
- Nested feature subfolders are only used when the feature has a real sub-area. Example: `WorkingOut/Features/Home/Vitals/`.

**Special Patterns:**
- Large screens often keep feature-scoped helper views in the same file or a sibling support file rather than creating many tiny files. Examples: `WorkingOut/Features/Runs/RunLogView.swift`, `WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`.
- Shared domain DTOs sometimes live beside the service that owns them. Example: `SharedWorkoutSession` in `WorkingOut/Services/WorkoutSharingService.swift`.
- The Xcode project uses filesystem-synchronized root groups for `WorkingOut/`, `RunningWidget/`, and `WorkoutThumbnailExtension/`, as shown in `Pace & Plates.xcodeproj/project.pbxproj`. Add new files in the correct folder on disk so Xcode picks them up with the target’s synced group.

## Where to Add New Code

**New Feature:**
- Primary code: `WorkingOut/Features/<FeatureName>/`
- Tests: Not currently established in-repo; if test targets are added later, place them in a sibling `*Tests` target rather than inside `WorkingOut/`
- Config if needed: Update `WorkingOut/Info.plist`, entitlements, or `Pace & Plates.xcodeproj/project.pbxproj` only when the feature adds a new capability or target-level setting

**New Screen Inside an Existing Domain:**
- Home/dashboard additions: `WorkingOut/Features/Home/`
- Workout logging/template additions: `WorkingOut/Features/Workouts/`
- Running/tracking/planning additions: `WorkingOut/Features/Runs/`
- Weight-specific additions: `WorkingOut/Features/Weight/`
- AI planner/chat/history additions: `WorkingOut/Features/AI/`
- Settings/profile/privacy additions: `WorkingOut/Features/Settings/`

**New Component / Module:**
- Shared reusable UI: `WorkingOut/Components/`
- Global theme or app-wide visual tokens: `WorkingOut/Theme/`
- New persisted entity or small cross-feature helper type: `WorkingOut/Models/`
- Seed/catalog/static content: `WorkingOut/Data/`

**New Integration or Workflow Service:**
- Implementation: `WorkingOut/Services/`
- Use `*Service.swift` or `*Manager.swift` naming to match existing files
- Keep DTOs or helper types beside the owning service when the types are not reused broadly outside that workflow

**New Extension / Widget Code:**
- Live Activity or widget rendering changes: `RunningWidget/`
- Quick Look document preview changes: `WorkoutThumbnailExtension/`
- Shared business logic should stay in `WorkingOut/`; extension targets currently stay thin and UI-specific

**Utilities:**
- Persistence helper or save wrapper: `WorkingOut/Services/`
- UI behavior helper or reusable modifier: `WorkingOut/Components/`
- Data normalization or static catalog: `WorkingOut/Data/`
- Small app-wide helper that is not a platform integration: follow the existing nearest fit in `WorkingOut/Models/` or `WorkingOut/Services/`

## Special Directories

**`WorkingOut/Assets.xcassets`:**
- Purpose: Main app asset catalog.
- Source: Maintained in Xcode / on disk as part of the app target.
- Committed: Yes

**`RunningWidget/Assets.xcassets`:**
- Purpose: Widget extension asset catalog.
- Source: Maintained in Xcode / on disk as part of the widget target.
- Committed: Yes

**`WorkingOut/Preview Content/`:**
- Purpose: SwiftUI preview support assets.
- Source: Maintained with app source.
- Committed: Yes

**`GameCenterResources.gamekit/`:**
- Purpose: Game Center authoring bundle.
- Source: Managed as a Game Center resource package.
- Committed: Yes

**`.planning/codebase/`:**
- Purpose: Generated GSD reference documentation.
- Source: Produced by mapping commands.
- Committed: Yes

**`.swift-module-cache/`:**
- Purpose: Local Swift module cache artifacts.
- Source: Generated by local builds/tooling.
- Committed: No

**`.tmp/`:**
- Purpose: Local temporary workspace for scripts/art generation.
- Source: Generated locally.
- Committed: No

**`.cursor/`:**
- Purpose: Local editor/tool metadata.
- Source: Generated by local tooling.
- Committed: No

---

*Structure analysis: 2026-03-29*
