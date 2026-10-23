# Coach storage-switch and draft integrity follow-up

22 October 2026. This follows the initial [release readiness review](release-readiness-2026-10-22.md). Work is isolated on `codex/coach-release-safety-20261022`, after commit `9fdee8f13a45f07c4d6a2ddcd7cb961b50d9412a`. The original dirty checkout is not the implementation target and its tracked diff remains byte-for-byte unchanged.

## Outcome

The two reported integrity risks now have deterministic production-model reproductions and focused fixes. The combined on-disk regression suite passes **167 assertions**: 128 existing checks, 31 storage-transition checks, and 8 draft-replacement checks. The Release simulator build and all eight final user journeys pass. Independent review of the complete patch found no actionable findings.

No real Health, iCloud, workout, Photos, account, or physical-device records were accessed or changed. The storage fixtures create temporary `.none` CloudKit configurations, use synthetic workout/sample objects, inject query results and anchor callbacks, and write the selection marker only into their temporary directory. They call the same private adoption and import pipelines as production; they do not copy those implementations into a parallel test harness. DEBUG-only dependency-injection entry points require UI-test mode.

## P1: suspend an import, select local storage, resume the old operation

Before retirement was integrated into successful selection, the final synthetic baseline failed with actual retained-store writes and anchor callback advancement after resumption. This occurred for strength query completion, cardio authorization/query/detail completion, and the anchored weight pipeline. Starting a new operation with the retired context also proceeded. The test preserved the selected copy's pre-import digest, making the divergence directly observable. The authoritative pre-fix artifact is `p1-before-final.xcresult` / `p1-before-final.log`.

The fix retires the source `ModelContainer` immediately after the selection marker commits and before the controller swaps containers. There is no suspension between those operations. Retirement advances the existing shared operation epoch and weakly records the retired container. Import checks now validate both the captured epoch and the context's container, so an old task cannot capture a fresh epoch after authorization and continue using an old context. Marker/copy failures do not retire the source or advance its epoch.

Strength, cardio and weight imports validate before mutation and after their relevant awaits; anchors remain after successful model commit in the same MainActor turn. Cardio builds each page in an isolated context with autosave disabled and rolls it back on abort. The details fixture suspends after a candidate has been inserted into that page, verifies the source view context is still clean, selects the local copy, and resumes the stale page. It cannot leak that partial candidate into the retained store or the selected copy. Async cardio link/create, active run enrichment, route loading, legacy weight imports, and backup entry/continuation guards also reject retired contexts.

The 31 checks cover:

- Suspension during strength query, cardio authorization, cardio query, cardio details, and weight query.
- Exact source and selected snapshot preservation, blocked anchor advancement, and rejection before a late source-context query starts.
- Idempotent retry of the unconsumed batch on selected storage, retaining one inbox/Health observation identity and the existing weight row.
- Isolation of a partial cardio page from an autosaving source context.
- Failed marker selection retaining the original selected container, writable context and epoch.

The anchored weight repository requires a Coach schema, so its fixture uses a synthetic Coach-schema source to exercise container retirement. The initial legacy Weight view's unanchored query path received the same context-aware entry/mutation guards; its real Health authorization/query timing was not exercised. No claim is made that the tests stop CloudKit's own remote merges into the retained legacy store: the fix concerns app import writes and anchors.

## P2: replace a reviewed draft after another context moves its session

`p2-before2.xcresult` / `p2-before2.log` reproduced the original defect with the actual models and repository. A second context moved the exact pending occurrence without changing its prescription revision. Replacement accepted the stale review and removed that moved occurrence.

Import review now captures `updatedAt` together with the draft revision when the draft is selected. The repository requires a nonnil matching timestamp and matching revision inside its isolated transaction, before deleting any occurrence. A missing token is rejected. A deliberately refreshed review can replace the draft while retaining its plan identity.

Eight assertions verify the same-revision schedule change, stale-token rejection, byte-for-byte preservation of the complete serialized Coach graph after rejection, exact moved occurrence/date retention, missing-token rejection, refreshed-review success with the same plan ID and newly authored dates, and no invented completed activity or exercise-library records.

## Verification

Artifacts are in the original checkout's ignored `.tmp/integrity-fixes-20261022/` directory.

| Check | Result |
| --- | --- |
| P2 production-model baseline | Expected failure: stale replacement accepted and moved occurrence lost; `p2-before2.log`. |
| P1 final baseline without retirement integration | Expected failure: retained-context writes/anchors and late starts reproduced at the listed suspension points; `p1-before-final.log`. |
| Final combined disk regression | **Passed**, 167 assertions; XCTest exited 0, `after-core-final.xcresult` / `after-core-final.log`. |
| Final Release simulator build | **Passed**, signing disabled; `release-build.log`. DEBUG fixture code is absent from this build. |
| Final user journeys | **Passed**, 8 tests, 0 failures, 0 skips; XCTest exited 0 with `TEST EXECUTE SUCCEEDED`; `final-journeys.xcresult` / `final-journeys.log`. |
| Independent review and whitespace | Approved, no actionable findings; `git diff --check` passes. |

Fixture preparation included failed builds for helper integration ordering, optional-closure type inference, a throwing expression and a DEBUG wrapper return. Those were corrected before the final frozen-source runtime runs; they are not evidence of an app data failure. The expected red baselines above are separate from those preparation failures.

The eight final journeys cover backup export cancellation, backup import picker cancellation, cardio linking without duplication, paused run relaunch and partial save, draft replacement/duplicate/skip/attestation lifecycle, import/review/strength completion/check-in, recorded-strength process relaunch, and corrected wearable metrics across batches. These ran on the disposable iPhone 17e / iOS 26.5 simulator. The backup picker/cancellation checks do not establish external-file recovery. Machine-readable summaries are saved beside the result bundles.

To repeat the combined fixture, use a disposable simulator and the isolated branch:

```sh
xcodebuild -project 'Pace & Plates.xcodeproj' -scheme WorkingOut \
  -configuration Debug -destination 'platform=iOS Simulator,id=YOUR_DISPOSABLE_SIMULATOR_ID' \
  -derivedDataPath /tmp/pace-coach-integrity-checks \
  -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO \
  -only-testing:WorkingOutUITests/WorkingOutUITests/testCoachPersistenceAndExecutionRegressions test
```

The fixture runner is `CoachStorageTransitionRegressionChecks.run()` followed by the existing execution/persistence/schedule checks. The schedule runner includes `CoachDraftReplacementRegressionChecks.run()`. All source/copy stores and injected anchor counters belong to the fixture. No real Health query is needed for these race checks.

## Remaining gates and delivery

These two code integrity findings are resolved within the tested synthetic boundary; this is not physical-device or paid-pilot acceptance. Real Health permission/source behavior, CloudKit transition with another device active, device protection and reboot, concurrent interrupted-run recovery during selection, locked/background GPS/rest/interval behavior, remote Photos and Calendar/reminder behavior remain unverified here. Full external-file device recovery, real disk-full/termination-during-commit and large-history performance also remain as listed in the initial review. September's owner-iPhone installation remains historical evidence.

Publication remains blocked. The previously denied repository-hook read required `admin:repo_hook`; it was not retried, no credential scopes were changed, and no materially new deployment-safety evidence was obtained. No push, PR, remote CI run, merge or deployment was attempted. The final local commit and durable patch path are recorded at handoff.
