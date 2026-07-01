# Technology Stack

**Analysis Date:** 2026-03-29

## Languages

**Primary:**
- Swift 5 toolchain setting (`SWIFT_VERSION = 5.0`) for all app, widget, and extension code in `WorkingOut/`, `RunningWidget/`, and `WorkoutThumbnailExtension/`

**Secondary:**
- XML property lists and scheme metadata for Apple platform configuration in `WorkingOut/Info.plist`, `WorkingOut/WorkingOut.entitlements`, `RunningWidget/Info.plist`, `RunningWidget/RunningWidgetExtension.entitlements`, `WorkoutThumbnailExtension/Info.plist`, and `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`
- JSON for bundled resources and app-owned interchange formats in `WorkingOut/gameCenterResources.json` and the custom workout file types declared in `WorkingOut/Info.plist`

## Runtime

**Environment:**
- Native iOS/iPadOS app runtime via `iphoneos` SDK, with `TARGETED_DEVICE_FAMILY = "1,2"` and `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `Pace & Plates.xcodeproj/project.pbxproj`
- Main executable target: `Pace & Plates.app` from `Pace & Plates.xcodeproj/project.pbxproj`
- Embedded runtime targets: `RunningWidgetExtension.appex` and `WorkoutThumbnailExtension.appex` from `Pace & Plates.xcodeproj/project.pbxproj`
- Apple Intelligence features are compiled behind `OTHER_SWIFT_FLAGS = "-DAI_FOUNDATION_AVAILABLE"` in `Pace & Plates.xcodeproj/project.pbxproj` and then gated again at runtime in `WorkingOut/App/ContentView.swift` and `WorkingOut/Services/WorkoutPlanGenerator.swift`

**Package Manager:**
- Xcode project-managed Apple SDK dependencies only via `Pace & Plates.xcodeproj/project.pbxproj`
- Lockfile: missing; no `Package.swift`, `Package.resolved`, `Podfile`, or `Cartfile` detected in the repository root

## Frameworks

**Core:**
- SwiftUI - primary UI framework for the app shell and feature views in `WorkingOut/App/ContentView.swift`, `WorkingOut/App/WorkingOutApp.swift`, and `WorkingOut/Features/**`
- SwiftData - primary persistence layer and model runtime in `WorkingOut/Data/PersistenceController.swift` and `WorkingOut/Models/**`
- UIKit - bridge layer for share sheets, Game Center presentation, haptics, and theme integration in `WorkingOut/Components/ShareSheet.swift`, `WorkingOut/Services/GameCenterService.swift`, and `WorkingOut/Theme/AppTheme.swift`
- FoundationModels / AppleIntelligence - on-device plan generation and coaching in `WorkingOut/Services/WorkoutPlanGenerator.swift`, `WorkingOut/Services/RunAssistantAIService.swift`, and `WorkingOut/Services/WorkoutTemplateService.swift`

**Testing:**
- XCTest / XCUITest targets are referenced by `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`
- No test source directories or `.xctestplan` files were detected in the current repository snapshot

**Build/Dev:**
- Xcode 26-era project metadata in `Pace & Plates.xcodeproj/project.pbxproj` with `CreatedOnToolsVersion = 26.0.1`, `LastSwiftUpdateCheck = 2600`, and `LastUpgradeVersion = 2600`
- Shared Xcode scheme for build, archive, profile, and test orchestration in `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`
- Asset catalogs and generated symbol support from `WorkingOut/Assets.xcassets`, `RunningWidget/Assets.xcassets`, and `ASSETCATALOG_*` settings in `Pace & Plates.xcodeproj/project.pbxproj`
- Launch and bundle metadata via `Pace & Plates.xcodeproj/LaunchScreen.storyboard` and the target `Info.plist` files under `WorkingOut/`, `RunningWidget/`, and `WorkoutThumbnailExtension/`

## Key Dependencies

**Critical:**
- SwiftUI - all primary screens, navigation, and widget UI in `WorkingOut/App/ContentView.swift`, `WorkingOut/Features/**`, and `RunningWidget/RunningLiveActivityWidget.swift`
- SwiftData + CloudKit-backed `ModelContainer` - persistence backbone with local fallback in `WorkingOut/Data/PersistenceController.swift`
- HealthKit - workout ingestion, route storage, vitals, and body metrics in `WorkingOut/Services/HealthKitManager.swift`, `WorkingOut/Features/Home/Vitals/VitalsModel.swift`, and `WorkingOut/Features/Runs/RunLogView.swift`
- FoundationModels / SystemLanguageModel - on-device AI planning and run-assistant generation in `WorkingOut/Services/WorkoutPlanGenerator.swift` and `WorkingOut/Services/RunAssistantAIService.swift`
- MapKit + CoreLocation + WeatherKit - outdoor run tracking, reverse search, map rendering, and weather summaries in `WorkingOut/Features/Runs/RunTrackingView.swift`, `WorkingOut/Services/MapSearchService.swift`, and `WorkingOut/Services/WeatherService.swift`

**Infrastructure:**
- ActivityKit + WidgetKit - Live Activities and Dynamic Island rendering in `WorkingOut/Services/LiveActivityManager.swift` and `RunningWidget/RunningLiveActivityWidget.swift`
- EventKit + UserNotifications - calendar scheduling and local reminders in `WorkingOut/Services/WorkoutCalendarService.swift` and `WorkingOut/Services/ReminderService.swift`
- GameKit - authentication, leaderboards, and achievements in `WorkingOut/Services/GameCenterService.swift` with metadata in `WorkingOut/gameCenterResources.json`
- CoreTransferable + UniformTypeIdentifiers + QuickLookThumbnailing - workout file export/import and thumbnail generation in `WorkingOut/Services/WorkoutSharingService.swift` and `WorkoutThumbnailExtension/ThumbnailProvider.swift`

## Configuration

**Environment:**
- No `.env` files or runtime environment-variable configuration were detected
- Capability and entitlement configuration lives in `WorkingOut/WorkingOut.entitlements`, `RunningWidget/RunningWidgetExtension.entitlements`, and `Pace & Plates.xcodeproj/project.pbxproj`
- User-facing runtime preferences are persisted with `@AppStorage` and `UserDefaults` in `WorkingOut/App/ContentView.swift`, `WorkingOut/Services/ReminderService.swift`, and `WorkingOut/Services/MapSearchService.swift`
- AI availability is controlled by the compile-time flag in `Pace & Plates.xcodeproj/project.pbxproj` and runtime checks in `WorkingOut/App/ContentView.swift`

**Build:**
- `Pace & Plates.xcodeproj/project.pbxproj` - targets, deployment targets, signing, build flags, and entitlements
- `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme` - shared build/test/archive scheme
- `WorkingOut/Info.plist` - app permissions, background modes, document types, Live Activities, and category
- `RunningWidget/Info.plist` - widget extension declaration and Live Activity flags
- `WorkoutThumbnailExtension/Info.plist` - Quick Look thumbnail extension registration

## Platform Requirements

**Development:**
- macOS with a modern Xcode matching the project metadata in `Pace & Plates.xcodeproj/project.pbxproj` and `Pace & Plates.xcodeproj/xcshareddata/xcschemes/WorkingOut.xcscheme`
- iOS 26 SDK and Apple Development signing for bundle IDs `Jorsh.WorkingOut`, `Jorsh.WorkingOut.RunningWidget`, and `Jorsh.WorkingOut.PPWorkoutThumbnail` in `Pace & Plates.xcodeproj/project.pbxproj`
- Real-device testing is required to fully exercise HealthKit, WeatherKit, Game Center, CloudKit, notifications, Live Activities, and Apple Intelligence paths declared in `WorkingOut/WorkingOut.entitlements` and used by `WorkingOut/Services/**`
- Apple Intelligence development requires an Apple Intelligence-capable iOS 26 device because the runtime availability checks in `WorkingOut/App/ContentView.swift` and `WorkingOut/Services/WorkoutPlanGenerator.swift` hide or degrade AI features when unavailable

**Production:**
- Signed iPhone/iPad app distributed as `Pace & Plates.app` with embedded `RunningWidgetExtension.appex` and `WorkoutThumbnailExtension.appex` from `Pace & Plates.xcodeproj/project.pbxproj`
- Apple platform capabilities are part of the shipped runtime contract: HealthKit, WeatherKit, Game Center, CloudKit, push entitlement, application groups, background location, and Live Activities from `WorkingOut/WorkingOut.entitlements` and `WorkingOut/Info.plist`
- No separate backend or server deployment target is detected; the production runtime is the native client plus Apple-managed platform services referenced by `WorkingOut/Data/PersistenceController.swift` and `WorkingOut/Services/**`

---

*Stack analysis: 2026-03-29*
*Update after major dependency changes*
