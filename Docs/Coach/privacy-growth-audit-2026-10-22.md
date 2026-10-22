# Pace privacy, storage and first-use readiness audit

22 October 2026. Audit base: main `a3a869f6232bbd970b45951a49f17d7245141120`; reviewed candidate: draft [PR7](https://github.com/JustJ0rsh/Pace-Plates/pull/7), head `0f69a4022f17f54fe54fb5b2d1fc6201a8c75ec2`. Public claims are separately summarized in [product facts](product-facts-2026-10-22.md). The public version is not proven to match either source snapshot. The original dirty checkout is excluded from shipping claims; its tracked diff retains SHA-256 `065c133f2441635de8ed4787973b96d2a40e34b7a5fce1a9a857ace670ceefb1`, and unrelated untracked files were not edited.

## P1 — Default personal-data storage can use CloudKit

Apple [App Review guideline 5.1.3(ii)](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research) says apps “may not store personal health information in iCloud.” Its wording is not limited to public CloudKit databases. This audit identifies a code-supported policy risk, not a legal determination, an Apple enforcement prediction, or evidence that any particular user's records were uploaded. No Health or cloud store was opened.

Both main and PR7 call the normal `PersistenceController` initializer with `cloudKitMode: .automatic`. In PR7, `PersistenceController.swift:119` defaults the mode and `:144–168` constructs the legacy schema/configuration. The entitlement names `iCloud.com.workingout.jorsh`. On an eligible account this is a CloudKit-capable path before the user chooses Coach-local storage. PR7 fixes stale app import writes during the switch; it does not remove this initial/default path.

The schema contains **14 model types with 253 listed stored scalar/blob fields and 14 relationship declarations**. All model sources are identical between main and PR7. The complete field/declaration/line inventory is [the full field inventory](cloudkit-field-inventory-2026-10-22.json). It excludes computed properties and records relationships separately. Persistent blobs and `.externalStorage` are not evidence of local-only storage.

| Models in the legacy schema | Sensitive content / exact fields to review |
| --- | --- |
| `WeightEntry` | `date`, `weight`, `weightUnit`, `sourceHealthSampleID`, `sourceName`, `provenance`. |
| `WorkoutSession` | Workout dates/notes and `healthWorkoutUUID`, `healthDuration`, `healthCalories`, `healthAvgHeartRate`, `healthSourceName`, `healthActivityType`, plus execution/completion IDs/status. |
| `ExerciseLog` | `reps`, `weight`, units, duration/distance, calories, `avgHeartRate`, notes, completion, plus `actualReps`, `actualWeight`, `actualDurationSeconds`, effort and prescription fields. |
| `RunningSession` | Dates, distance/duration/calories, `locations`, Health sample/source links, average/max/min HR, cadence, stride, oscillation, contact time, elevation and power. `RunCoordinate.swift:4` includes latitude, longitude, altitude and timestamps. |
| `HealthWorkoutInboxItem` | Health UUIDs/sync IDs, dates, activity, duration, calories, HR, source identifiers, status, links and deletion-observation time. Records can persist before the user links them to history. |
| `CardioWorkoutInboxItem` | The same identity/provenance family plus distance, min/max HR, per-source sync versions, suggested/linked run IDs and detail/distance attempt times. |
| `RunningPlan`, `RunningPlanSession` | Training targets, dates, results and links. `RunningPlan.profileSnapshotJSON` contains goal, ability, current/target pace, schedule and reminder preferences; `aiPrompt` is retained. |
| `TrainingPlan`, `PlannedSession` | Plans, prescriptions, dates, notes, target pace/distance/duration, completion provenance and execution links. `prescriptionData` can contain structured personal training content. |
| `AIConversation` | `prompt`, `response`, `goal`, `structuredPlanJSON` and other metadata. User free text must not be presumed non-sensitive. |
| `WorkoutTemplate`, `TemplateExercise`, `ExerciseDefinition` | Exercises, loads, reps, notes, goals, program links and user-authored names. |

Relationship graph: definitions ↔ exercise logs; workouts ↔ exercise logs; workouts ↔ generated templates; templates ↔ template exercises; running plans ↔ plan sessions; runs ↔ completed plan sessions; training plans ↔ planned sessions. Scalar UUID links are also retained. Migration must preserve both forms of linkage.

### Proven data-entry paths

- `WearableWorkoutInboxService.swift:115,406–420,484` queries and inserts Health strength inbox records; `:1373` transfers Health identity, duration, calories and HR into `WorkoutSession`.
- `CardioWorkoutInboxService.swift:251` inserts cardio inbox values; `:629–655` creates a saved run; `:795–838,920–941` fetches/assigns Health-derived dynamics, power, elevation and routes.
- `SettingsView.swift:992,1022–1029` and `WeightLogView.swift:425–435` import Health body mass through the legacy `WeightEntry` constructor. These paths omit source IDs/provenance. A missing sample ID or `manual_or_legacy` marker therefore does **not** prove a row was manually entered.
- `DataBackupService.swift:652–655` blocks a nonlocal restore only when `file.coach?.hasPersonalRecords` is true. Legacy v1–v4 backups can still restore workouts, weights, routes, HR and inbox records into the supplied cloud-capable context (`:762–767` is one assignment example). `SettingsView.swift:1085` supplies the selected context.
- Run-plan creation persists the profile snapshot (`RunAssistantService.swift:78–95`, `RunAssistantAIService.swift:159–175`).

### What Coach-local mode does and does not establish

The local factory explicitly uses `.none` (`PersistenceController.swift:105–115`). `CoachPersistence.swift:9–13` adds ten local-only types: plan revision, execution, progression suggestion, nutrition target/log, recovery check-in, waist, progress photo, phase review and calendar mapping. Repository writes require local ownership (`CoachRepository.swift:51`). Sleep/source/coverage data in recovery records, nutrition, waist, photos and modern anchored Health weight imports are guarded locally.

Local directories/assets are explicitly backup-excluded (`CoachLocalOwnership.swift:27`, `CoachPersistence.swift:21–30`). No equivalent exclusion was found in legacy-store setup. That is a source observation only; this audit did not verify anyone's backup settings or whether files were backed up. The policy treatment of user-directed exports and OS backups should be confirmed separately rather than inferred here.

Adoption retains the old source and does not delete existing remote records or alter other devices. Current-store deletion can propagate in legacy cloud mode; local-mode deletion retains old copies. PR7's corrected confirmation/completion text reflects this. Do not claim a single delete removes all copies everywhere.

### Safe remediation plan — not applied

The [local-storage remediation design](local-storage-remediation-design-2026-10-22.md) expands the field classification, partition choices, migration journal, backup and rollback invariants, and owner-permission gates. It is a proposed design, not an implemented migration.

1. Establish a protected, backup-excluded local destination for all new personal records before any Health query, manual health write or legacy restore. Cover all ingress, not only `file.coach`.
2. For existing installations, perform a versioned, verified migration that preserves IDs, relationships, dates, route/asset bytes and unknown-provenance rows; commit the selection marker last. Keep source recovery intact. Do not simply delete model types, flip a flag on the existing store, or silently delete cloud history.
3. Design remote remediation with explicit owner-approved scope and other-device/old-client behavior. A retained local copy does not demonstrate removal of a remote record, and older clients may recreate records.
4. Prove synthetic invariants for every write destination; v1–v5 restore; partial/interrupted copies; resumed import callbacks; active run recovery; marker failures; unknown provenance; old-client races; and rollback. Reuse PR7's 184-assertion baseline, then add missing all-ingress cases.
5. Obtain policy-specific review of the proposed storage and disclosure model before promoting personal-health cloud-sync assurances. This audit changes no user storage.

## P2 — Public/in-app privacy language needs mode and service boundaries

The [website policy](https://paceandplates.com/privacy) still describes the legacy private-iCloud model and JSON backups. The inspected in-app policy (`PrivacyPolicyContent.swift:8,29–32,58`) describes Coach-local mode and archives. They should be reconciled to the release actually being distributed.

The in-app policy's categorical no-third-party-sharing line (`:40`) omits GameKit from its Apple-service list (`:33–37`). `CommunityView.swift:51–62` correctly explains that opted-in Community can publish fitness scores and achievements. WeatherKit receives coordinates (`WeatherService.swift:24–29`); MapKit reverse geocoding receives coordinates (`MapSearchService.swift:76–85`). An absolute no-off-device-data promise is not supported.

No app-owned network backend, analytics/ad SDK, StoreKit purchase flow or ATT/IDFA usage was found in the audited app/extensions. The privacy manifest declares no tracking/collected-data entries. These are source findings, not certification of the live binary. Apple's [privacy-label guidance](https://developer.apple.com/app-store/app-privacy-details/#data-collection) distinguishes collection from every transient service request; do not infer a label violation merely from an Apple framework call. Review actual retention/access and all integrations with the owner before changing declarations.

The website is a separate surface: its public JavaScript sends conversion/support events to `/api/event`, and its HTML includes a Cloudflare beacon. The policy discloses website counts/logging separately. Static GETs were used for this audit; no script, tracking event or support submission was executed. No new analytics are proposed.

## First-use and return-use checks

A disposable iPhone 17e / iOS 26.5 simulator reproduced a first-session bug: new manual sessions are `in_progress`, but their row completion control was exposed only for template-backed sessions. A fresh user could enter valid actuals without a way to mark the set complete. The comparable original-code test entered exactly eight reps and failed at the absent completion control (`onboarding-baseline-red-v2.xcresult`).

Commit `3903821` exposes the existing explicit completion control for manual `in_progress` sessions. It does not automatically complete sets, migrate history, change non-template legacy/completed/partial rows, or alter Coach's separate execution view. Independent review approved the condition. The new test uses the observed accessibility label across roles; the control is a Switch, not a Button.

The final combined build includes both bounded fixes and no temporary launch instrumentation. **Two tests passed, zero failures/skips**, in `onboarding-combined-green.xcresult`: optional profile fields can remain blank after choosing a focus; and Skip Setup → new manual workout → exactly eight reps → explicit Off-to-On completion → Finish/Completed → process relaunch retains Completed and eight reps. The focus choice still lands on general Home, leaving a focused first action as a future UX iteration.

Evidence, screenshots, the red/green test bundles, manual-only patch and exact tested source hashes are under `.tmp/growth-readiness-20261022/onboarding/`. The integrated branch matches all five production/test hashes in `tested-source-sha256.json`. No real permissions, keychain or cloud account were exercised. Physical usability, denied real permissions, actual Game Center traffic and broader return-use behavior are not established by these two tests.

The bounded Community callback fix is implemented on separate branch `codex/pace-growth-readiness-20261022`, commit `a716ac1`, without changing PR7. A shared consent-generation gate invalidates stale score/achievement callbacks after disable or disable/re-enable and keeps the final check and submission together. The original production reporting bodies failed five of 14 inert-platform assertions; the fixed bodies pass all 14, including enabled behavior and synchronous completion reentrancy. An independent reviewer approved the change, an unsigned generic simulator build passed, and a second integrated host run passed. The combined simulator build also includes this exact source. Tests replace GameKit/UIKit/UserDefaults with inert doubles; no real platform upload or preference was touched. The fix cannot retract requests already submitted before opt-out, delete existing Game Center data, or establish live-service behavior.

## Prioritized iterations and acceptance gates

| Priority | Iteration | Safe acceptance test |
| --- | --- | --- |
| P1 | Resolve the complete personal-data storage policy and migration design. | Every sensitive ingress routes to explicit local storage; corrupted/interrupted migration leaves source intact; old clients and legacy backups covered. |
| P1 | Make public privacy/capability claims release-specific, including optional Apple services and retained copies. | Cross-check storefront, website, in-app policy and signed release mapping; owner reviews App Store disclosures. No declaration changed automatically. |
| P2 | Expose explicit completion for first manual workout; keep skipped/partial data honest. | Fresh synthetic user records a set, explicitly marks completion, finishes, relaunches, and finds the same completed activity/actuals; legacy historical flags unchanged. |
| P2 | Cancel stale Community uploads at the final callback boundary. | Delay fake auth/load, disable (and disable/re-enable), resume; zero stale submissions, fresh opted-in submission succeeds. |
| P2 | Reduce first-value ambiguity without more data collection. | Skip profile/integrations, select lifting/run/weight intent, reach a useful manual action; optional Health denial cannot block it. Keep defaults editable and avoid requiring sensitive profile fields. |
| P2 | Make return-use and recovery visible. | Day-two synthetic relaunch shows the canonical result/next session; backup reminder explains deliberate local recovery without coercive permission prompts. |
| P3 | Validate accessibility and public platform wording. | Physical VoiceOver, large text and reduced-motion checks; state hardware-dependent AI and no standalone Watch app. |

No monetization, analytics, account declaration, cloud cleanup, merge or deployment is part of these iterations. DSA status remains an owner-verification item: inspect both Business compliance and app-specific App Information in App Store Connect using [Apple's guidance](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/). The public seller name does not settle that status.
