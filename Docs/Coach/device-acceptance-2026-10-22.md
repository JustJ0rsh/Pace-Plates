# Coach device acceptance continuation — 22 October 2026

## Outcome and scope

Continued the reviewed `9fdee8f` / `e9c61a2` fixes without reimplementing them. Physical acceptance remains **pending device availability**. Independent synthetic verification now includes the public saved-archive pipeline and native local Files export/recovery. No real Health, CloudKit, workout, Photos, Calendar or account records were read, sent, deleted or overwritten. No physical installation, account setup, signing/provisioning operation, push, PR, merge or deployment was performed.

The implementation target remains `/tmp/pace-coach-release-safety` on `codex/coach-release-safety-20261022`. The original dirty checkout's tracked diff still has SHA-256 `065c133f2441635de8ed4787973b96d2a40e34b7a5fce1a9a857ace670ceefb1`; unrelated work was preserved.

## Physical devices and the smallest missing action

Read-only `devicectl list devices` succeeded. The paired **Eagle 1**, an iPhone 16 Pro Max, and **Eagle 2 (2)**, an 11-inch iPad Pro (4th generation), both report an unavailable connection. Their cached OS versions are 27.0 and 26.6.1 respectively; neither was queried for app or personal data. Another cached iPad entry is also unavailable. The final inventory under Xcode 27.1 still shows no reachable physical iOS device; the two named devices no longer appear in that cache. A paired Apple Watch is listed, but this project has no watchOS target.

**First missing action:** connect and unlock Eagle 1 or Eagle 2 on this Mac and make it available to Xcode, accepting Trust on the device if requested. No Health or iCloud access is needed for the synthetic test suite. Developer Mode and existing development signing can be checked once the device is reachable; neither was changed or assumed here.

The prepared **Pace Synthetic QA** candidate uses `com.justjorshin.paceplates.acceptance20261022`, distinct extension IDs, and empty Health/iCloud/app-group entitlement dictionaries. Its dedicated Debug entry point forces an isolated on-disk test store and exposes only synthetic regression checks. Normal app navigation, incoming document handling and real Health/Calendar/location controls are inaccessible. Non-acceptance and Release builds fail closed. This avoids replacing the owner's production app or relying on launch arguments to keep it isolated.

The unsigned arm64 iOS 26+ candidate built with Xcode 27.1 (27A9275). It includes the 184-assertion suite but has **not** run on a physical device. Its source variant and unsigned app are `/tmp/pace-device-acceptance-20261022` and `/tmp/pace-device-acceptance-xcode271-derived/Build/Products/Debug-iphoneos/Pace & Plates.app`. Durable reproduction patch, identity/hash manifest and independent safety review are in `.tmp/device-acceptance-20261022/`.

## New simulator evidence

All runs used the existing disposable `PacePlates-ReleaseReview-20261022` iPhone 17e / iOS 26.5 simulator, ID `7372980A-77C0-4D68-9D24-C4CDC03C93B3`. Debug test mode selects temporary/in-memory `.none` CloudKit stores and suppresses normal side effects. No personal account was introduced.

| Check | Result and evidence |
| --- | --- |
| Combined production-model regression | **184 assertions passed**: 167 prior checks plus 17 new saved-backup checks. Individual `testCoachPersistenceAndExecutionRegressions` passed in `acceptance-initial.xcresult`; that exploratory bundle also contains a separate failed native share-sheet selector. |
| Saved archive to fresh store | The actual `DataBackupService.exportAll` creates the archive, a separate saved copy survives removal of the transient export, and `DataBackupService.import` restores into an empty disk store. Complete snapshot digest, canonical occurrence/execution IDs, actuals, targets, daily logs, weight, waist, photo metadata and exact JPEG bytes match. Disk reopen and repeat import retain the same graph. Corruption is rejected without changing history, photo bytes or saved original. |
| Native Files export → cleared store → restore | **Passed**, `testBackupSavedInFilesRestoresAfterRelaunch`, `files-fourth.xcresult`. Saved through the system share sheet to local On My iPhone storage, checked successful synthetic deletion and empty workouts/runs/weight after process relaunch, selected the saved `.pacebackup` through the native importer, received `Import complete`, then relaunched again and verified fixture workouts/runs/weight. This check does not stand in for exact Coach graph equality; the separate public-pipeline test provides that. |
| Native Coach JSON file selection and retained draft | **Passed**, `testCoachNativeJSONAcceptance`, `native-json-clean.xcresult`, 1 test / 0 failures and xcodebuild exit 0. Selected `Pace Acceptance/Synthetic Coach Program.json`, waited for its exact source ID, reviewed it, saved a draft, relaunched and verified exactly one retained title. |
| Isolated physical candidate compile | **Passed**, unsigned arm64 generic iOS build; `device-build-xcode271.log`, `build-verification.json`, `isolation-review.md`. Compile and source-isolation evidence only. |

The native Files fixture uses only the disposable simulator's `group.com.apple.FileProvider.LocalStorage` directory. A synthetic JSON and generated backups were staged there. The successful native saved archive is copied to `native-files-recovery.pacebackup` (SHA-256 `321496a15072a00cdbdd837f88dd23cf665294da87d963ee50cfca26eddaf31c`) and the JSON fixture to `synthetic-coach-program.json` (SHA-256 `4618cbaf9ffe6d79085d0bc5645bba934b31692e11b1f699e278b587ce957b3d`) in the evidence directory.

Exploratory UI assertions were corrected for the system share action being a cell, an initially empty Recents view, the newly saved review layout and the program row's combined accessibility label. One test process was interrupted when CoreSimulator's installed framework changed from version 1168 to 1174.9.2; its exit was 143 and it is not counted as a passed run. Subsequent native runs explicitly used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and separate derived data, without changing the global Xcode selection. The stopped process was checked before retrying. A later stale test-runner execution was resolved by rebuilding only the generated test target and reinstalling only the disposable simulator test runner; the final log confirms the updated predicate and selectors executed.

The native Files tests are preserved as a QA-only patch rather than added to the default suite, because they require deliberate staging in a disposable simulator's local provider. The new saved-backup production-model fixture is integrated into the normal Debug Coach regression runner. No production behavior was changed by this continuation.

## Remaining gates and delivery

Physical storage protection across lock/reboot, locked/background interval guidance, notification delivery, device performance/VoiceOver, real disk-full and forced termination during commit remain unverified. Real Health permission/source corrections and multi-device CloudKit behavior require a separately authorized account/data test; these synthetic results do not claim them.

The earlier denied `GET /repos/JustJ0rsh/Pace-Plates/hooks` request requiring `admin:repo_hook` was **not retried**, bypassed or replaced with broader credentials. Publication remains blocked under that prior decision. No remote changes or CI result are claimed.

Evidence and machine-readable handoff: `.tmp/device-acceptance-20261022/`. See also [the original release review](release-readiness-2026-10-22.md) and [the integrity follow-up](data-integrity-followup-2026-10-22.md).
