# Coach release readiness and data safety — 22 October 2026

## Decision and scope

**Follow-up status:** R1 and R2 were subsequently reproduced and fixed with production-model synthetic regressions. See the [data integrity follow-up](data-integrity-followup-2026-10-22.md) for the final patch and fresh QA. The findings and initial results below retain the original review boundary; the physical acceptance and recovery gates remain open.

Hold a paid pilot until the remaining acceptance checklist is completed. The repeatable value to protect is the existing loop: import a reviewed program, find its scheduled session, record actuals, reopen the same result after relaunch, and recover it from a deliberate backup. No paywall or additional feature is proposed.

The initial review examined the dirty `codex/simplify-coach-plans` checkout at base `a3a869f6232bbd970b45951a49f17d7245141120`, including the uncommitted usability follow-up. Existing edits and unrelated `LettersHome/` work were preserved. Only this review's isolated fixes were copied to `codex/coach-release-safety-20261022` in `/tmp/pace-coach-release-safety` for independent review and exact-branch QA.

No real Health, iCloud, workout, Photos, or account records were used. No physical installation, pairing, purchase, credentials change, paywall, merge, or deployment was performed. Review agents were explicitly requested as GPT 6.1 sol with ultra reasoning. The continuation/delegation APIs do not expose verifiable Fast routing; no routing change is claimed.

## Prioritized findings

### R1 — P1 release gate: a suspended importer can retain the legacy store after selection

`PersistenceController.adoptLocalOwnership()` verifies the source and copy before selecting Coach local storage (`WorkingOut/Data/PersistenceController.swift:192`). It then changes the container and `storageGeneration`, without invalidating suspended import operations. Existing unstructured sync tasks retain their original `modelContext` across awaits (`WorkingOut/Features/Settings/SettingsView.swift`, `WorkingOut/Features/Weight/WeightLogView.swift`). Their stale-operation guards use `WearableWorkoutInboxService.localDataPurgeGeneration`, which the storage switch does not change. The cardio importer can save that old context and advance the shared Health anchor (`WorkingOut/Services/CardioWorkoutInboxService.swift:299`).

**Impact inferred from the source:** a query begun before switching can finish afterward, write to retained legacy/CloudKit history, and advance an anchor without putting the new records into the selected Coach copy. Recreating views with `.id(storageGeneration)` does not cancel an unstructured `Task` already retaining a context.

**New evidence:** a disposable SwiftData probe using the production SQLite/auxiliary copiers passed 11 assertions, including a retained context saving after the copy was opened. The source then had two rows and the copied store one. This establishes the storage-divergence primitive, not an end-to-end Health timing reproduction. Actual Health and CloudKit services were not invoked.

**Gate:** suspend a synthetic importer immediately before its final mutation, complete local ownership selection, then resume it. It must neither write the retired context nor advance its anchor. Cover Health weight and both workout inbox paths. Use a storage-generation guard/rebinding strategy and verify every post-await mutation boundary before changing real store behavior. This was left outside the small isolated fixes.

### R2 — P2 release gate: stale draft replacement can discard a newer schedule move

Import review captures `draft.currentRevisionID` (`WorkingOut/Features/Coach/CoachPlanImportView.swift`). `CoachRepository.importPlan` compares that revision and pending status before deleting draft occurrences (`WorkingOut/Features/Coach/Data/CoachRepository.swift:181`). A schedule edit changes `updatedAt`, `scheduleRevision`, and `localScheduleOverride` without changing the prescription revision (`CoachRepository+Schedule.swift:26`). A reviewed replacement can therefore pass after another window moves a pending session and delete the newer move.

This is source-traced; no new runtime reproduction is claimed. It conflicts with the contract's promise to recheck draft revision and state. **Gate:** capture the reviewed draft state/version, atomically reject a replacement after a same-revision schedule edit, and assert that all dates, occurrence identities, and actual history remain unchanged on rejection. These files already contain substantial owner edits and were not changed by this review.

### F1 — P2 fixed locally: valid manual measurements could crash result displays

A valid 60-second interval with `0.000000000000001` meters produced approximately `6e19` sec/km. The result display converted that to `Int` and trapped. The production-domain reproduction accepted the state and the exact conversion terminated with signal 5. Derived pace now returns unavailable when nonfinite or outside the whole-second display range; the entered measurement is retained. Four regression assertions cover the tiny actual, overflowing derived pace, and ordinary 600 sec/km result.

Separately, `1e20` finite meters passed interval validation but `CoachSessionDetailView` converted its distance to `Int` and trapped. One rendering line now formats the rounded `Double` directly. A compiled rendering probe checked `100 → 100 m`, `123.9 → 123 m`, `1e20 → 100000000000000000000 m`, and `nil → Distance unavailable`. Normal truncation is preserved. Only that unchanged rendering line was touched within the otherwise dirty view.

### F2 — P2 fixed locally: Delete All overstated its scope after enabling Coach

Coach-local deletion clears the selected history and owned assets while intentionally retaining the pre-Coach store and existing legacy iCloud records. Confirmation and completion formerly said the device/all app data was removed. Both local-mode messages now disclose those retained copies. Deletion behavior was not expanded. The existing synthetic deletion journey checks the disclosure and that fixture workout/run/weight history disappears.

The first revised UI assertion hit XCTest's 128-character identifier-query limit. It was corrected to an explicit predicate; that failure is test automation evidence, not an app deletion failure.

## New verification and evidence boundaries

Artifacts are under the original checkout's ignored `.tmp/release-review-20261022/` directory. These are fresh 22 October checks, separate from September's reports.

| Check | New result |
| --- | --- |
| Foundation contract | 77 assertions passed; also passed from the isolated review checkout. |
| Execution/progression domain | 52 assertions passed after the fix (48 existing + 4 new); also passed from the isolated checkout. |
| Numeric entry and units | 14 + 8 assertions passed. |
| Archive/photo boundaries | 34 assertions passed with disposable files. |
| SQLite/WAL/external assets copy | 9 assertions passed with disposable SwiftData stores. |
| Retained-context writer probe | 11 assertions passed; this extends the copy probe and is not 11 additional independent migration checks. |
| Current dirty-checkout integration | Fresh iPhone 17e / iOS 26.5: XCTest logged 8 passed / 1 failed. Readiness, backup cancel/export/import, import-to-completed-strength, run/strength process relaunch, and the 157-assertion disk suite passed. The failure was the long-identifier test query described above. Log: `simulator.log`. The invocation then hung finalizing its bundle and was stopped after its exact process identity was checked; no readable completed bundle is claimed for this run. |
| Isolated review-branch Release build | Passed for generic iOS Simulator, signing disabled; `isolated-release-build.log`. |
| Isolated review-branch integration | Debug test build passed. All 5 targeted iPhone 17e / iOS 26.5 tests passed: deletion/disclosure, canonical run paused relaunch/partial save, import/review/strength completion, persistence/execution/schedule (128 disk assertions), and recorded-strength process relaunch. `xcodebuild` exited 0 with `TEST EXECUTE SUCCEEDED`; `isolated-final.log` and `isolated-final.xcresult`. |

The original XcodeBuildMCP test call timed out after 300 seconds and left `focused.xcresult` without a readable `Info.plist`. Its `xcodebuild` process was confirmed stopped before retrying. No passed suite is claimed for that attempt. The documented `xcodebuild` route was then used with a durable log. A temporary executor disconnect also prevented confirmation of a stronger copied-method migration probe; no result is claimed for it.

Native Files JSON selection was not newly verified: the fresh simulator did not have the fixture prerequisite, and locating its local provider container did not succeed. Paste/review and domain import checks are distinct evidence. The September native Files journey remains historical. No personal JSON was supplied or used.

### Historical evidence, not new acceptance

`usability-followup.md` describes September simulator/host checks and a signed Release 2.5 build 5 installation on the owner's iPhone on 14 September. The note says automatic launch was blocked by a locked phone. This review did not independently recheck that inventory, launch the phone app, or extend that installation into physical UI acceptance. `implementation-status.md` describes the earlier implementation acceptance snapshot; its counts are not new October results.

## Recovery and pilot gates

1. Resolve R1 and R2 with deterministic synthetic regressions before using a new local-ownership transition or concurrent draft-editing workflow in a paid pilot.
2. Prove export → external saved file → fresh Coach store restore with exact occurrence, execution, actual, target, and photo identities. Archive corruption, rollback, old JSON compatibility, and interrupted-file checks passed in synthetic harnesses; full device recovery, real disk-full, forced termination during commit, and large-history performance remain unverified. Coach's selected local directory is excluded from automatic backup, so the explicit recovery path is a release gate.
3. Run the signed candidate on an authorized physical device using synthetic records. Complete a strength and run session, relaunch, and verify exactly one completed activity and the same canonical occurrence. Test locked-screen/background interval/rest guidance, interruption and paused recovery, notification delivery, and storage protection across lock/reboot.
4. Under later, separate account/device authorization, verify legacy CloudKit transition while another device/import is active, source retention, post-switch local-only edits, Health permission/source corrections and exact sample links, remote Photos offline/download behavior, and selected Calendar/reminder writes. None was performed here.
5. Finish physical VoiceOver, supported text sizes, and ordinary-device performance/thermal acceptance. Existing SwiftUI invalid-frame warnings were observed during simulator navigation; a passed journey does not establish app-wide layout-warning resolution.

For a future paid pilot, acceptance should demonstrate repeated scheduled use over more than one day and deliberate recovery without lost or duplicate history. The current review supplies technical evidence; it does not establish willingness to pay or permission to begin charging.

## Delivery and push safety

The isolated five-file patch received independent read-only approval with no actionable findings. Its diff was confirmed as 30 insertions and 8 deletions before this report was added.

The original checkout's tracked edits were restored exactly after copying only this task's patch to the isolated checkout. `cmp` against the initial binary Git diff passed; both files have SHA-256 `065c133f2441635de8ed4787973b96d2a40e34b7a5fce1a9a857ace670ceefb1`. The new report and ignored validation artifacts are separate from the preserved owner edits.

The existing remote was verified as `https://github.com/JustJ0rsh/Pace-Plates.git`; `origin/main` matched base `a3a869f6232bbd970b45951a49f17d7245141120`. GitHub reported no Actions workflows and the checked-in Fastlane file only runs screenshots. `GET /repos/JustJ0rsh/Pace-Plates/hooks` was denied with HTTP 404 and an explicit missing `admin:repo_hook` scope. Production push triggers therefore could not be fully verified. No credentials/scope change was attempted. Push and draft PR creation remain blocked pending that verification; neither was attempted, and no remote commit or CI pass is claimed.

Final exact-branch QA passed as recorded above. The local commit identity is recorded at handoff. The fresh synthetic simulator is kept separate from existing simulators; no physical-device acceptance is implied.
