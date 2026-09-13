# Coach execution validation

Run the independent execution checks from the repository root:

```sh
./scripts/test-coach-execution.sh
```

On September 13, 2026, this command passed **48 checks** using the installed Swift compiler. The script compiles the production document types, execution state, progression rules, and tagged scheduled-run target together with `scripts/coach_execution_tests.swift`. It creates only a temporary executable and removes it after the run. It does not open the app's database or access personal tracking data.

These checks exercise rest deadlines, pause/resume and clock changes; optional GPS and manual interval boundaries; interrupted interval recovery; partial/skipped outcomes; round-trip timer and interval snapshots; legacy versus canonical plan identity; and progression eligibility, actual baselines, effort scales, substitutions, missing pain feedback, phase readiness, changed working-set prescriptions, and evidence correction fingerprints.

## App integration checks

The DEBUG `coach_checks` app fixture invokes these asynchronous runners:

- `CoachExecutionRegressionChecks.run()` creates disposable on-disk SwiftData stores and verifies exact repeated Start/resume, one actual workout identity, blank prescriptions, optional actual fields, explicit partial outcomes, correcting actuals, legacy history behavior, and deliberate backup/restore.
- `CoachScheduleRegressionChecks.run()` verifies 26-week expansion, canceled and exact imports, unknown-exercise consent, reviewed draft replacement, active-plan and phase gates, missing readiness records, schedule preview conflicts, identity-preserving moves, repeat-week identities, selected future revisions/additions/removals, and fresh-context durable status.
- `CoachPersistenceRegressionChecks.run()` covers the shared persistence and backup graph. Its implementation and validation are maintained with the persistence work.

The XCTest entry point is `WorkingOutUITests/testCoachPersistenceAndExecutionRegressions`. Use an available simulator identifier, keep this run separate from other Xcode builds using the same derived-data directory, and run:

```sh
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme WorkingOut \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath .tmp/coach-execution-validation \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:WorkingOutUITests/WorkingOutUITests/testCoachPersistenceAndExecutionRegressions \
  test
```

The separate `testCoachImportReviewTrackingAndCheckIn` UI test exercises the paste/import, review, session logging, finish, and check-in journey. Its observed central result is recorded below and in [simulator-audit.md](simulator-audit.md); the 48 pure checks above are separate evidence.

## Simulator audit additions

The September 13 audit added guards and focused regressions for these failure paths:

- Invalid, duplicate, or foreign set actuals and mismatched interval revisions reject before altering activity history. Reopening a terminal execution after deleting its actual does not recreate a workout.
- Interval and recovery snapshots reject invalid clocks, duplicate steps, impossible result ordering, and incomplete canonical identities. Active-run backup retains the exact interval, optional distance, and activity identity; late checkpoints cannot overwrite a finished run.
- Progression requires the latest consecutive comparable completed occurrences. Skipped or overdue sessions invalidate older proposals. Assistance loads require manual review. Recovery holds use the observation's civil date and time zone, so editing old feedback today or entering future feedback does not create a current hold.
- Recorded GPS distance remains known after location permission changes, while queued callbacks without authorization cannot extend the route. This permission issue was identified in source review; its synthetic regression does not establish physical permission-revocation behavior.

`testCoachStrengthRestoresRecordedSetAfterProcessRelaunch` and `testCoachCanonicalRunRestoresPausedAndSavesPartial` use disposable disk stores with `UITEST_COACH_DISK=1`, terminate the app, and relaunch with `UITEST_RESET_STATE=0`. The run journey also uses `UITEST_RUN_RECOVERY=1` and compares the displayed paused duration across processes before saving the exact occurrence as partial.

## Remaining physical acceptance

Physical-device acceptance remains necessary for GPS quality, interruption/relaunch while backgrounded or locked, rest notification delivery, physical permission changes, HealthKit write/link behavior, and real-device protected-storage/CloudKit boundaries. Simulator process-termination checks do not establish those device outcomes. No physical installation, live-history migration, remote data changes, or publication was performed by these execution checks.

## Central integration status

The independent compiler checks remain **48 passed**. After the final-source rebuild, the central iPhone / iOS 26.5 run passed **128 on-disk assertions**, including the four final distance/permission checks. The canonical run journey passed actual app termination/relaunch with an exact comparison of paused duration, then saved Partial to the same occurrence. The unrecorded lifting journey also passed: cancel the finish confirmation, save Partial, and reopen without inventing actuals (`.tmp/coach-audit-phone-pass4.xcresult`).

The iOS 27 beta smoke run passed all five tests: import/log/finish, unknown daily values, invalid-JSON correction, prompt copy, and recorded lifting process relaunch (`.tmp/coach-audit-ios27-smoke.xcresult`). The legacy regression run passed seven tests, including active-run identity and interrupted-run recovery plus five backup flows (`.tmp/coach-audit-legacy-final.xcresult`). The unsigned generic-iOS Release build passed with the final production changes verified here (`.tmp/coach-audit-release-final.log`).

These are named test and build results, not a claim that every selected test in every retained run passed. See [simulator-audit.md](simulator-audit.md) for the full test matrix, artifact paths, failed-attempt explanations, and remaining physical boundaries. [implementation-status.md](implementation-status.md) records the delivery state.
