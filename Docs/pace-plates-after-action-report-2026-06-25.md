# Pace & Plates After Action Report

Date: 2026-06-25
Device: iPhone 17 Pro Simulator, iOS 26.5, UDID C8CE439A-A426-4124-8C8C-5BC457A2DBFA
Scheme: WorkingOut
Scope: Product design review, live simulator smoke, automated UI test run, and failure analysis.

## Executive Summary

The app is not release-ready from this pass. The primary app surfaces mostly render well under the UI-test fixture and 8 of 9 UI tests passed, including Home quick-action context menus, empty states, AI History navigation, toolbar action sheets, Running Assistant entry, and the core Home/Workouts/Runs/Weight screenshot checks.

The blocking issue is Settings entry reliability. `testSettingsScreenshot()` failed after 169.9 seconds with `Failed to get matching snapshots: Timed out while evaluating UI query.` A current-run screenshot taken during the stall showed the app still on Home with the Settings gear visually pressed, so the route did not reach `SettingsView` or did not expose `settings.ready` before XCTest timed out.

There is also a startup/rendering risk outside XCTest. Direct `simctl launch` initially showed a blank white app body for both normal and fixture launches. A delayed capture later rendered Home, which points to a slow or blocked startup path rather than a permanent blank screen. The log around that delayed render showed heavy CoreLocation/network activity and an extended launch metrics event after roughly 23 seconds.

## Evidence

Screenshots:

- `.tmp/pace-plates-aar/screenshots/01-home-normal-launch.png`: rejected, blank launch state.
- `.tmp/pace-plates-aar/screenshots/02-home-fixture.png`: rejected, blank fixture launch state.
- `.tmp/pace-plates-aar/screenshots/03-home-uitest.png`: accepted Home Fastlane/UI-test screenshot.
- `.tmp/pace-plates-aar/screenshots/04-workouts-uitest.png`: accepted Workouts Fastlane/UI-test screenshot.
- `.tmp/pace-plates-aar/screenshots/05-runs-uitest.png`: accepted Runs Fastlane/UI-test screenshot.
- `.tmp/pace-plates-aar/screenshots/06-weight-uitest.png`: accepted Weight Fastlane/UI-test screenshot.
- `.tmp/pace-plates-aar/screenshots/07-settings-fastlane-prior.png`: Settings visual reference from Fastlane output, not current-run proof.
- `.tmp/pace-plates-aar/screenshots/settings-test-stall.png`: current-run Settings failure state, Home still visible after Settings tap.
- `.tmp/pace-plates-aar/screenshots/08-delayed-fixture-launch.png`: accepted delayed Home fixture render.
- `.tmp/pace-plates-aar/screenshots/09-after-settings-click-attempt.png`: Home after blocked shell click attempt.

Test result bundle:

- `.tmp/pace-plates-aar/test-results/WorkingOutUITests.xcresult`

Automated result:

- 9 UI tests executed.
- 8 passed.
- 1 failed: `WorkingOutUITests.testSettingsScreenshot()`.

## Test Results

Passed:

- `testAISurfaceAndHistoryNavigation()` in 15.4s
- `testEmptyStatePrimaryActions()` in 22.6s
- `testHomeQuickActionContextMenusStayScopedToPressedButton()` in 15.7s
- `testHomeScreenshot()` in 10.0s
- `testRunsScreenshot()` in 10.0s
- `testToolbarActionSheetsAndRunAssistantPresent()` in 41.9s
- `testWeightScreenshot()` in 9.2s
- `testWorkoutsScreenshot()` in 10.1s

Failed:

- `testSettingsScreenshot()` in 169.9s
- Failure: `WorkingOutUITests.swift:176: Failed to get matching snapshots: Timed out while evaluating UI query.`
- Current screenshot evidence: Settings tap left the app on Home with the gear pressed.

Tooling notes:

- XcodeBuildMCP could not list simulators or schemes because it could not find `simctl`/`xcodebuild`.
- Shell Xcode tools worked with `/Applications/Xcode.app/Contents/Developer`.
- MCP UI snapshot also failed because its environment believed `xcode-select -p` was `/Library/Developer/CommandLineTools`.
- Shell `xcodebuild test` was the authoritative verification path for this pass.

## Product Review

### Home

Health: good visual hierarchy, blocked by bottom overlap and Settings route reliability.

Strengths:

- Primary actions are obvious: Start Workout, Start Run, Log Weight.
- Weather, streak, quick log, and recent activity read cleanly.
- The touch targets are large and visually distinct.

Risks:

- Bottom chart content is obscured by the floating tab bar. The segmented chart control and chart text sit under the tab surface in both current and UI-test Home evidence.
- The Settings icon is visually clear, but current testing shows it can fail to navigate or fail to become accessible to XCTest.
- The long-press hint appears in the Fastlane Home screenshot but not in the delayed current fixture screenshot, which suggests the reviewed UI state may vary across launch paths or stale screenshot sets.

### Workouts

Health: usable and coherent.

Strengths:

- The main weekly volume story is clear.
- Edit, import/document, and add actions are discoverable.
- Workout list rows are readable and scan well.

Risks:

- The chart dominates the first viewport. For a repeat-use logging app, recent workouts and add/log actions may deserve more first-screen weight than the chart.
- The top right combined action group uses icon-only controls. That can be fine, but it depends on strong accessibility labels and user familiarity.

### Runs

Health: mostly good.

Strengths:

- The run list has clear dates and useful metrics.
- Track Activity and Running Assistant entry points are prominent.
- The page visually matches the rest of the app.

Risks:

- `Steps Today -` reads like missing data without explanation. A short unavailable state would build more trust.
- The chart title and step summary compete horizontally, especially on smaller width or larger Dynamic Type.

### Weight

Health: good data readability, blocked by bottom overlap.

Strengths:

- The weight trend is easy to understand.
- The green delta is clear and reinforces progress.
- History rows are simple and scannable.

Risks:

- The floating tab bar clips the lower history rows.
- Dense numeric text should be checked under larger Dynamic Type, because the current layout relies on two-column alignment.

### Settings

Health: visually dense but coherent when it renders; current route is unreliable.

Strengths:

- Grouping into Units, Appearance, Profile, Goals, Home Screen, Reminders, Advanced, and About is sensible.
- Segmented controls are appropriate for binary/short option sets.
- The AI Provider, Health & Sync, Backup & Data, and Developer subpages are covered by the test plan.

Risks:

- Current UI test run could not enter Settings from Home.
- The visual Settings reference shows the bottom tab bar remains visible underneath Settings, with Home selected. That is potentially confusing because Settings is a pushed utility screen, not the Home tab itself.
- The bottom of the Settings list is also at risk of tab bar overlap.
- Settings has many controls on one long screen. That is acceptable for a utility screen, but the profile section is dense and should be tested with larger text.

## Accessibility Review

Confirmed from screenshots and code:

- Primary action targets are generally large.
- Home Settings and Community toolbar controls have accessibility labels in `HomeView.swift`.
- The Settings list has `settings.ready` as an accessibility identifier.
- The primary UI uses native controls, which is a good baseline for VoiceOver and Dynamic Type support.

Risks needing follow-up:

- Full VoiceOver order was not verified.
- Dynamic Type was not verified.
- Contrast was visually acceptable in the captured dark theme, but not measured.
- The floating tab bar overlapping content can harm readability and touch access at the bottom of scroll views.
- Icon-only toolbar controls need a full label audit across Workouts, Runs, Weight, and Settings subpages.

## Likely Root Causes And Follow-Up

1. Settings navigation/test hang

The Settings button is a `NavigationLink(destination: SettingsView())` in `HomeView.swift`, and `SettingsView` applies `.accessibilityIdentifier("settings.ready")` to `settingsList`. The failure screenshot shows Home still visible, so the first suspect is navigation/tap completion or a main-thread stall during transition, not a missing identifier alone.

Recommended next checks:

- Re-run only `testSettingsScreenshot()` with logging around the Settings tap.
- Add a focused UI test that taps `home.settings.button`, captures immediately, and asserts either the Settings navigation bar or the current screen title.
- Temporarily simplify `SettingsView.onAppear` side effects to isolate whether `bootstrapOpenRouterKeyIfAvailable()`, `loadProfileFromHealthKit()`, or `refreshLocationAuthorizationStatus()` contributes to the delay.
- Consider replacing the toolbar `NavigationLink` with explicit `NavigationStack` path/state for a more testable Settings transition.

2. Slow or blank direct launch

Direct `simctl launch` initially rendered a white body, then later showed Home after a delayed capture. The log showed CoreLocation churn and network activity before launch measurement completed.

Recommended next checks:

- Measure cold launch with non-UI-test normal state.
- Gate HealthKit, CoreLocation, weather, and provider bootstrap so first paint is not blocked by side effects.
- Add a smoke test that launches without `UITEST_MODE` after setting only the minimum onboarding defaults.

3. Bottom content overlap

Home and Weight clearly show scroll content under the floating tab bar. Runs and Workouts have more breathing room, but the same pattern can reappear with longer content or Dynamic Type.

Recommended next checks:

- Add consistent bottom padding or `safeAreaInset` handling for all root tab scroll views.
- Verify Home, Weight, and Settings at default and large text sizes.

## After Action

What went well:

- The existing UI test suite has meaningful coverage across the core product surfaces.
- The quick-action regression coverage is valuable and passed.
- Empty-state and action-sheet checks passed, which protects important first-use and logging workflows.

What did not go well:

- Settings entry failed in the current test run and consumed most of the suite time.
- Direct app launch was initially blank, delaying manual review.
- XcodeBuildMCP was unusable on this machine for simulator control because of environment/toolchain visibility problems.
- Manual shell-based Simulator tapping was blocked by System Events permission/error `-25204`.

Decision:

- Do not ship as-is.
- Treat Settings navigation reliability and launch first-paint delay as blockers.
- Treat bottom tab overlap as a high-priority design/accessibility bug.

Recommended next pass:

1. Fix or isolate Settings navigation stall.
2. Fix launch side effects so Home paints promptly outside XCTest.
3. Add bottom safe-area protection to Home, Weight, and Settings.
4. Re-run the 9-test UI suite.
5. Add a focused non-UI-test launch smoke if feasible.
6. Re-capture Home, Workouts, Runs, Weight, and Settings after fixes.
