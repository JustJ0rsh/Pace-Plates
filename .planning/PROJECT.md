# Pace & Plates

## What This Is

Pace & Plates is a native iOS fitness app for logging strength workouts, tracking outdoor cardio sessions, recording body weight, and generating AI-assisted training guidance. This brownfield planning milestone is focused on run-tracking resilience so active sessions and Live Activities stay trustworthy when the app is backgrounded, force-quit, or relaunched mid-workout.

## Core Value

Users can trust Pace & Plates to capture and preserve real workout progress without losing an in-flight session.

## Requirements

### Validated

- ✓ User can log strength workouts with exercise history and template flows — existing
- ✓ User can start cardio tracking, capture route/distance/duration, and review saved runs — existing
- ✓ User can log body weight and review trend/history surfaces — existing
- ✓ User can use AI-assisted workout and running-plan flows — existing
- ✓ User can see active run stats in a Live Activity while a run is in progress — existing

### Active

- [ ] In-progress run state survives app termination or accidental dismissal until the user resumes, saves, or discards it.
- [ ] Live Activity lifecycle stays synchronized with persisted run state and never lingers after the underlying run is ended or discarded.
- [ ] After relaunch, the user can recover an interrupted run with its elapsed time, distance, activity type, and captured route data.
- [ ] Local run save remains authoritative even if HealthKit write-back or route sync fails afterward.
- [ ] Run-tracking lifecycle regressions are covered by automated checks and a device validation checklist.

### Out of Scope

- New cardio modes or coaching features unrelated to run recovery — this milestone is reliability-focused, not feature expansion.
- A full rewrite of the Runs feature architecture — too large for the current bug-fix scope; extract only what is needed for resilience.
- Cosmetic redesign of the Live Activity UI — behavior correctness comes before presentation changes.
- Cross-device sync of in-progress runs — current recovery scope is on-device only.

## Context

- The app is a brownfield SwiftUI + SwiftData iOS app with ActivityKit/WidgetKit support via `LiveActivityManager` and `RunningWidget`.
- Active run state currently lives only in the in-memory `RunTracker.shared` singleton, and the active-run banner in `RunLogView` is derived from that singleton state.
- Live Activity ownership currently lives only in a process-local `activity` reference inside `LiveActivityManager`, so the app cannot reconcile or end orphaned activities after relaunch.
- `RunTrackingView.saveRun()` saves locally, then performs HealthKit write-back asynchronously; the milestone must preserve local data even when Apple Health operations fail.
- Live Activities require physical-device validation, not simulator-only testing.

## Constraints

- **Tech stack**: SwiftUI, SwiftData, ActivityKit, WidgetKit, HealthKit, CoreLocation — fixes should fit the existing app architecture and targets.
- **Reliability**: Local persistence must be the source of truth for interrupted runs — users cannot lose session progress because of process death or sync failures.
- **Compatibility**: App and widget must share the same activity attributes contract — divergence between targets is a regression risk.
- **Testing**: Live Activity behavior needs manual device validation in addition to automated coverage — simulator support is incomplete for this surface.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Treat this as a brownfield reliability milestone, not a net-new feature initiative | The reported issue is a broken trust path in an existing core workflow | - Pending |
| Persist active-run draft state outside the `RunTracker` singleton | Recovery after force-quit is impossible while state is memory-only | - Pending |
| Reconcile orphaned Live Activities from durable state on launch and foreground entry | Process-local `activity` references cannot clean up activities after the app restarts | - Pending |
| Prefer local-first save and explicit post-save sync reporting | HealthKit failures should not destroy or hide successfully saved local runs | - Pending |
| Add both automated lifecycle coverage and a manual device checklist | ActivityKit and app lifecycle bugs are high-risk and not fully testable in simulator | - Pending |

---
*Last updated: 2026-04-14 after initialization*
