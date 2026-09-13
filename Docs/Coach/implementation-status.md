# Coach implementation and acceptance

Implementation and simulator acceptance snapshot for `codex/coach-programs`, based on the supplied September 13, 2026 plan. The specifications are retained alongside this report. At the close of this audit, changes were local; no device installation, deployment, or live-store migration had been performed. Subsequent delivery does not extend the acceptance evidence recorded here. The unrelated `LettersHome/` directory is preserved.

## Implemented behavior

| Area | Local implementation |
| --- | --- |
| Authoring and import | Native phase/week/template/set/interval editors, library copying and substitutions; bundled versioned contract; copyable prompt with opt-in personal context; bounded JSON/file import; strict validation; every-week preview; exercise mapping; explicit start date and time zone; drafts, deduplication, reviewed revisions and portable export |
| Today and programs | Shared Home/Coach projection; today's sessions, separate overdue/next lists; program lifecycle; explicit phase readiness tied to prescription revision; move/swap/repeat with stable identities; selected Calendar/reminder projections and retry state |
| Lifting | Exact occurrence execution; immutable prescription; optional actual reps/load/time/effort; comparable previous results; substitutions and notes; completed/skipped sets; rest timer; pause/relaunch state; explicit completed/partial/attested finish |
| Running/cardio | Bounded structured interval sequence; pause/skip/manual fallback; measured versus unknown distance; saved actual interval results and effort; tagged canonical/legacy references; interrupted recovery remains paused |
| Reviewed progression | Supported deterministic rules, comparable working-set evidence, explicit load increments and equipment basis, readiness holds, stale-evidence rejection, accept/edit/dismiss decisions, selected future changes |
| Nutrition and recovery | Dated optional daily totals and check-ins, unknown-versus-zero preservation, effective target periods and historical snapshots, explicit date correction/merge, selected Health sleep source/manual override, manual operation without readable Health data |
| Body and progress | Shared WeightEntry repository with exact Health sample identity; waist CRUD; bounded selected-photo import, private copies, retry/edit/delete/compare; range-filtered charts plus readable values and source/coverage labels |
| Preservation | Protected local ownership choice, verified legacy copy including SQLite WAL and external route blobs; complete history archive with bounded records and separate digested photos; old JSON backups; interruption journals; targeted deletion and purge-generation guards |

Coach's first-use screen explains the storage consequence before switching: all tabs use a verified local copy, and subsequent changes on that device stop syncing through the legacy CloudKit store. The original store is retained; remote records are not deleted. This transition has been exercised with disposable stores, not Joshua's history.

## Verification

- Foundation contract suite: 77 checks passed.
- Execution/rest/interval/progression suite: 48 checks passed.
- Numeric editing and measurement units: 14 + 8 checks passed.
- Archive/photo file-boundary suite: 34 checks passed.
- Real SQLite/SwiftData external-asset copying: 9 checks passed.
- Debug app/extension build: passed.
- Audit Release app/extension build for generic iOS, signing disabled: passed (`.tmp/coach-audit-release-final.log`).
- iPhone 17e Simulator, iOS 26.5: disposable on-disk persistence/execution/schedule regression fixture passed; nutrition/recovery save/reopen test passed; AI history navigation passed; existing interrupted-run paused-relaunch test passed.
- Import-review-activate-start-log-finish UI journey: passed on iPhone 17e / iOS 26.5 (`.tmp/coach-journey-verified.xcresult`). The test verifies explicit exercise consent, enabled activation, actual reps entry, saved set and completed-session feedback.

Repeatable commands and narrower evidence boundaries are in [contract-validation.md](contract-validation.md), [execution-validation.md](execution-validation.md), and [persistence-validation.md](persistence-validation.md). Central build/test logs and result bundles are under the ignored `.tmp/coach-*` paths. The latest disk-reopen fixture includes the chosen time zone, date-line start day, manual schedule overrides, later reviewed revisions, and repeated-week audit exclusions (`.tmp/coach-import-final.xcresult`). Whitespace verification (`git diff --check`) passes.

The subsequent [Simulator audit](simulator-audit.md) records bugs found and corrected and passing results for all 48 defined UI cases across the complete 32-test baseline and focused reruns. It includes 128 final on-disk assertions, 36 Calendar assertions, actual lifting and running process-relaunch tests, native Photos import/compare/edit/delete, all seven editing journeys on iPad, and the passing iOS 27 beta smoke and legacy regression runs. It distinguishes automation corrections from app defects and records the remaining runtime warnings. The [UI matrix](ui-test-matrix.md) lists the passing artifact for each case.

The first iPad/iOS 27 beta UI attempt blocked inside UIKit's synchronous pasteboard service when focusing a field; its process sample is `.tmp/coach-hang.sample`. A fresh iPhone/iOS 26.5 Simulator did not reproduce that system-service stall. The temporary Simulator was removed after validation. Subsequent UI testing found and fixed a growing JSON editor that hid Review behind the keyboard. Review now remains in the navigation bar and opens the validated review directly.

## Acceptance still requiring a physical device

Locked-screen location and interval guidance, background rest notifications, physical Health sleep/weight source changes, remote Photos downloads, actual user-store/CloudKit transition, device performance/thermal behavior, and physical VoiceOver acceptance remain unverified. iPad accessibility XXXL authoring was tested; other untested device/text-size combinations remain outside this audit. Calendar/reminder external writes were not performed against a live account. These require the corresponding later device/account authorization; simulator and file-fixture results do not establish those behaviors.
