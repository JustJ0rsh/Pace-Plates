# Coach Simulator audit — September 13, 2026

The audit is finished for the tested Simulator scope. All 48 defined UI test cases have passing results across the audit runs, alongside 190 independent domain/file checks, 128 on-disk app assertions, and 36 Calendar assertions. The [per-test matrix](ui-test-matrix.md) identifies the passing run for every UI case; the complete baseline and later focused reruns are distinguished below.

This tests the local implementation on `codex/coach-programs`. All app history, photos, and Calendar events used here are synthetic and disposable. No personal store, physical device, CloudKit account, or remote Calendar was changed. At the close of this simulator audit, changes were local and uncommitted; this report records that validation snapshot.

## Defects found and corrected

| Area | Failure and correction |
| --- | --- |
| Prompt preview | The long bundled schema pushed Copy below the prompt. Copy now stays in the navigation bar and the preview scrolls within a bounded area. |
| Daily records | Restoring two nutrition or recovery records for the same civil day could create duplicate totals. Conflicting archive days are rejected before writes. Restored calorie targets must also be bounded, finite integers. |
| Recovery corrections | Moving a manually edited recovery day could move Health sleep away from its measured day. Manual fields move; Health observations remain attached to their original civil day and source. |
| Photo preservation | Interrupted photo installation could leave partial files, and repeated deletion could fail on an already absent copy. Archive installation now verifies a journal-owned temporary file before atomic rename; deletion tolerates an absent app copy. |
| Photo comparison | A native-picker journey reproduced Compare also invoking Edit and opening Photo Details. The two row buttons now use independent borderless actions; the regression explicitly rejects presentation of the edit sheet from Compare. Evidence before the fix: `.tmp/coach-audit-photo-pass8.xcresult` and `.tmp/coach-photo-compare-before.png`. |
| Workout results | Mismatched prescription identities, duplicate/foreign actuals, extreme durations, or a deleted terminal workout could produce invalid execution state. Validation now precedes mutation and terminal sessions cannot be recreated as new work. |
| Progression | Skipped occurrences could leave a misleading consecutive evidence chain; old edited check-ins could appear current; assistance loads could be treated as added resistance. Evidence is rechecked at acceptance, readiness uses observed civil days, and assistance requires manual review. |
| Calendar | Retry could find copied event tokens outside the intended calendar; unavailable calendars could erase useful mappings; stale selections could write events or reminders after a move, skip, or deletion. Lookup is scoped, exact saved identities take precedence, ambiguity is rejected, and current source state is checked before external effects. |
| Editing feedback | A previously saved check-in could keep displaying Saved after new edits. Editing now clears that status. Manual-builder Review also remains accessible from the navigation bar. |
| Recovered run distance | A source review found that revoking location permission could relabel an already measured route as unknown. Recorded route evidence now remains available, while unauthorized new callbacks cannot add samples. Four synthetic integration checks exercise the distinction. |
| Overlapping reminders | Two reminder writers could overlap across view instances and a stale writer could remove a newer request during cleanup. A shared ownership guard serializes Coach reminder writers through their awaited operations and cleanup. |

## Verification record

The installed toolchain is Xcode 27 beta. Disposable iPhone 17e and iPad Pro 11-inch (M5) simulators ran iOS 26.5; a separate disposable iPhone ran iOS 27 beta (24A5380i).

| Evidence | Result |
| --- | --- |
| Existing complete iPhone UI suite | 32 tests passed, 0 failures (`.tmp/coach-audit-baseline.xcresult`). This was the baseline before the audit fixes. |
| Contract / expansion / invalid-input checks | 77 passed (`.tmp/coach-audit-contract.log`). |
| Execution / progression checks | 48 passed (`.tmp/coach-audit-execution.log`). |
| Numeric entry and measurement units | 14 + 8 passed (`.tmp/coach-audit-entry.log`). |
| Archive and photo-file boundaries | 34 passed (`.tmp/coach-audit-archive.log`). |
| Real SQLite and external-asset migration | 9 passed (`.tmp/coach-audit-migration.log`). |
| Real EventKit Calendar projection | 36 assertions passed on iPhone / iOS 26.5 (`.tmp/coach-audit-phone-pass4.xcresult`). |
| On-disk app persistence/execution | 128 assertions passed on iPhone / iOS 26.5 (`.tmp/coach-audit-phone-pass4.xcresult`). Includes the four final permission/distance checks. |
| Actual lifting process relaunch | Passed: recorded reps survive terminating and relaunching the app against its isolated disk store; finishing creates one workout (`.tmp/coach-audit-phone-retest.xcresult`). |
| Actual canonical run process relaunch | Passed, including exact paused duration before/after relaunch and saving Partial to the same occurrence (`.tmp/coach-audit-phone-pass4.xcresult`). |
| Unrecorded lifting finish | Passed: cancel the finish confirmation, save Partial, reopen without invented actuals or a new Start action (`.tmp/coach-audit-phone-pass4.xcresult`). |
| iOS 27 beta smoke | 5/5 passed: import/log/finish, daily unknown values, invalid JSON correction, prompt copy, and lifting process relaunch (`.tmp/coach-audit-ios27-smoke.xcresult`). |
| Final legacy run/backup checks | 7/7 passed on iOS 27 beta: five backup flows plus interrupted-run recovery and activity-type preservation (`.tmp/coach-audit-legacy-final.xcresult`). |
| iPad weight/waist | Both shared-weight CRUD and independent waist observation corrections passed (`.tmp/coach-audit-ipad-pass4.xcresult`). |
| iPad manual builder and largest type | 2/2 passed: template/week/phase authoring, reviewed draft without activity, and Review through native toolbar overflow with the keyboard open at accessibility XXXL (`.tmp/coach-audit-ipad-pass5.xcresult`). |
| iPad nutrition replacement | Passed: replaces daily totals, preserves blank versus zero, reopens saved values (`.tmp/coach-audit-ipad-daily-pass5.xcresult`). |
| iPad recovery and target editing | 2/2 passed: invalid input, zero/unknown preservation, correction/deletion, effective target snapshots, and unsaved nutrition totals preserved across target editing (`.tmp/coach-audit-ipad-daily-pass7.xcresult`). |
| Native Photos round trip | Passed: import two synthetic images, decode and compare both, edit date and pose, reopen persisted metadata, delete both app copies, reselect both library originals, cancel without new app copies (`.tmp/coach-audit-photo-pass10.xcresult`). Also verifies Compare does not open Edit. |
| Unsigned generic-iOS Release build | Passed with the final photo-action fix (`.tmp/coach-audit-release-final.log`). |

The final Debug test build and `git diff --check` passed. All seven new editing cases passed on iPad across their focused runs. The full native Photos journey passed on iPhone. These results do not imply that all 48 tests ran in one final invocation or on every device/runtime combination.

All three disposable audit simulators were shut down and removed after testing. The existing user Simulator remained unchanged. `.tmp/coach-audit-cleanup.json` records the exact cleanup; result bundles and logs remain under the repository's ignored `.tmp` directory. Evidence paths in this report and the matrix are relative to the repository root.

Early expanded UI runs exposed test-harness faults: gestures started on the tab bar, windowed-iPad coordinates applied the window origin twice, software-keyboard assumptions rejected valid focus, text deletion assumed the caret position, and a native confirmation popover had no visible cancel button. Those failed attempts are retained in `.tmp/coach-audit-*` bundles and are not counted as passing app journeys. Timestamped screenshots now accompany every XCTest issue.

Further corrections handled native toolbar overflow, remote Photos image hit-testing, lazy form feedback above the viewport, numeric-keypad caret behavior, and explicit calendar-popover dismissal. One photo attempt executed a stale picker helper despite the installed runner matching the rebuilt binary; reinstalling only the disposable test runner made the next attempt execute the current helper. This is recorded as test infrastructure behavior, with no claim of an app defect.

## Evidence limits

Simulator checks do not establish real GPS accuracy, locked-screen execution, background notification delivery, physical Health source/permission changes, remote Photos downloads, or migration of an actual user's CloudKit-backed history. Calendar checks use disposable local calendars. Foundation and fixture checks are separate from observed interactive journeys.

XCTest also reported an intermittent `Invalid frame dimension (negative or non-finite)` warning while navigating into the import form, including passing journeys on both iOS 26.5 and 27 beta. No corresponding invalid app frame calculation or failing behavior has been established; attribution remains unconfirmed. The beta runtime also logged a duplicate Apple accessibility-loader class; no associated crash was observed.
