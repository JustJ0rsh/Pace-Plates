# Coach data: iCloud sync or backup — recommendation (2026-11-14)

Status: option (b) and the other-device guard are implemented on `claude/admiring-noyce-e7f406`. Option (a) is not. Read against `origin/main` @ 44e80e3 (2.5.3).

## Where things stand

- Legacy history (`PersistenceController.legacyModelTypes`, including `TrainingPlan` and `PlannedSession`) mirrors to `iCloud.com.workingout.jorsh` through the `.automatic` configuration in `CloudSyncRestoration.makeContainer`.
- The ten `CoachPersistence.modelTypes` live in the `CoachLocal` configuration with `cloudKitDatabase: .none`. `CoachPersistence.protect` marks the directory and photo files `isExcludedFromBackup`. Deleting the app, or setting up a new phone, loses them unless the user exported a Backup & Data archive.
- This was deliberate (`Docs/Coach/storage-boundary.md`). The 2.5 privacy policy says Coach data stays local, and the boundary doc cites Apple's health-data review guideline.
- `CoachPersistence.isLocal(_:)` (29 call sites) refuses Coach writes unless the Coach configuration has `cloudKitContainerIdentifier == nil`. Any sync design has to redefine that gate on purpose.

### A cross-device bug that exists today (found in code, not reproduced)

`TrainingPlan.currentRevisionID` and `PlannedSession.executionID` sync, but the `CoachPlanRevision` and `CoachSessionExecution` rows they point to stay on the phone that created them. On a second device signed into the same iCloud account:

- `HomeTodayCard` and `CoachHomeView` treat the plan as active or saved, because `currentRevisionID != nil`.
- `CoachRepository.document(for:)` returns `nil`, because the revision is missing, so the program view comes up empty.

Whatever we decide below, this needs a guard: "This program was created on another device. Restore a backup from that device to see it here."

## Constraint to settle first: App Review 5.1.3(ii)

The guideline says apps "may not store personal health information in iCloud." Apple doesn't define the phrase. Coach data includes:

- `CoachRecoveryCheckIn.healthSleepHours`, `healthSleepSource`, `healthSampleCoverageData` — read directly from HealthKit. This is the clearest case.
- Pain score and location, soreness, waist measurements, and body progress photos.

The legacy store already syncs workouts and body weight, and that has passed review. Coach data is a step closer to the line. **Recommendation:** don't sync HealthKit-derived fields under any option; each device can re-read them from Health, which syncs on its own. Before shipping (a), get a written answer from App Review (via App Store Connect "Contact Us" or a pre-submission question) on syncing the remaining Coach fields.

## Options

### (a) A second CloudKit-mirrored configuration

**Shape that fits "don't risk existing history":**

- Use a **separate container**, `iCloud.com.workingout.jorsh.coach`, set with `cloudKitDatabase: .private("iCloud.com.workingout.jorsh.coach")`. Don't reuse the legacy container. Two stores mirroring into one container's default `com.apple.coredata.cloudkit.zone` is poorly documented, and every failure mode there lands next to the history users already lost once. A separate container never touches the legacy zone, its schema, or its tokens. Cost: a new entitlement value and provisioning update. A container ID can never be deleted once it's created.
- **Use a new store file** rather than turning on mirroring for the existing `coach.store`. Copy rows into the new store with a journal, the same way `CloudSyncRestoration.prepare` does (copy, verify, checkpoint, select). Keep the original local store untouched as the rollback. The mirroring delegate writes metadata and history into whatever store it opens, so flipping the existing store in place leaves no clean fallback.
- **Synced set:** `CoachPlanRevision`, `CoachSessionExecution`, `CoachProgressionSuggestion`, `CoachNutritionTargetPeriod`, `CoachNutritionLog`, `CoachPhaseReview`, `CoachWaistMeasurement`, and `CoachRecoveryCheckIn` with the Health-derived fields left out.
- **Kept local:**
  - `CoachCalendarMapping`. Its `calendarID` and `eventID` are EventKit identifiers that differ per device, so syncing them would make the other device move or duplicate events.
  - `CoachProgressPhoto` and its files (see (c)).
  - The Health-derived sleep fields. A configuration can't split one model by field, so these move to a small local companion model keyed by check-in `id`. That's a schema change, and it gets its own migration check.
- **CloudKit compatibility:** the models already qualify (defaults or optionals, no unique constraints, no relationships). Mark free-text and pain fields `.allowsCloudEncryption`. This has to be decided before the first production deploy, because changing it later is a breaking schema change.

**Production schema deployment:**

1. In a Debug build against the Development environment, call `initializeCloudKitSchema` (through the underlying `NSPersistentCloudKitContainer`, or by seeding one of every entity).
2. Inspect the `CD_*` record types in the CloudKit Console.
3. **Deploy Schema Changes** to Production before any TestFlight or App Store build, since those builds use Production.
4. Production is additive-only from then on. Fields and record types can't be removed or renamed, so model names and field types are frozen once deployed.

**Migrating existing local data:**

- The first launch of the new version runs the journaled copy: local Coach store → new mirrored store.
- Core Data then exports every row on its first mirror pass.
- Device B does the same with its own local rows.
- The old store stays on disk, read-only, until the user deletes it or a later release does after a soak period.

**Duplicate risk across devices** (CloudKit has no uniqueness):

| Case | How it happens | Resolution |
| --- | --- | --- |
| Same `id` on two devices | A Backup & Data archive restored onto device B, then both upload | Merge by `id`; the higher `updatedAt`/`createdAt` wins. The rows are identical copies, so dropping one loses nothing. |
| Same day, different `id` | `CoachNutritionLog` / `CoachRecoveryCheckIn` written for the same `civilDate` on both devices | Keep both and show a "two entries for this day" resolution UI. No silent delete: the values may differ. |
| Same suggestion generated twice | `CoachProgressionSuggestion` on (`planID`, `ruleID`, `evidenceFingerprint`) | Deterministic winner (decided status beats pending, then lowest UUID string). Losers are marked superseded, not deleted. |
| Same revision content | `CoachPlanRevision` with the same `fingerprint` but a different `id` | Keep both. `TrainingPlan.currentRevisionID` already says which one is live. |

Run the dedupe from persistent-history transactions after each import, the way Apple's "Synchronizing a local store to the cloud" sample does. Make it idempotent so both devices reach the same result.

**Cost and risk:** large.

- 29 `isLocal` call sites.
- A new migration journal.
- A dedupe service.
- A schema split for the Health fields.
- Privacy policy and in-app wording changes.
- The 5.1.3 question.
- The legacy store is touched only to the extent that the `ModelContainer` gains a third configuration.

### (b) Stay local, make it obvious, and make the existing export easier to use

- The Backup & Data screen and Coach first-run text say plainly: "Coach programs, results, nutrition, recovery, and photos are on this iPhone only. They are not in iCloud and not in iPhone backups. Export a backup to keep them."
- Show the last export date and a nudge after N new Coach records, or after 14 days without an export.
- Make sure Settings → Backup can import a `CoachHistoryArchive` (photos included) on a fresh install before any Coach data exists. The path already exists (`DataBackupService` restore, `validateMerge`).
- Add the second-device guard for the missing-revision bug above.

**Cost and risk:** small. No CloudKit schema change, no change to the legacy store, no 5.1.3 exposure. It keeps the 2.5 privacy promise.
**Downside:** recovery still depends on users remembering to export. There's no live multi-device use.

### (b′) Possible cheap add-on: stop excluding the Coach store from iPhone backup

Clearing `isExcludedFromBackup` on `CoachLocal` would let an iCloud or Finder device backup carry Coach data to a new phone restored from that backup. It does **not** help with reinstalling on the same phone, and it reverses the stated design. It's a product and privacy decision, not an engineering one. If chosen, it needs a migration check that `protect()` no longer sets the flag on existing directories.

### (c) Photos

- **Keep them local** (recommended for every option). Body photos are the most sensitive data and the most likely to raise 5.1.3. At about 0.5–1 MB each (2048 px JPEG) they also count against the user's iCloud storage. The existing archive already carries them (`includePhotos`).
- If photos sync later: use a separate `CoachProgressPhotoAsset` model with `@Attribute(.externalStorage, .allowsCloudEncryption) var jpeg: Data`. Core Data mirrors external-storage blobs as `CKAsset`. Keep `CoachProgressPhoto` metadata local or synced with `importState = "remote_pending"` until the asset arrives. Don't mirror the `Photos/` directory by hand with raw `CKAsset` uploads; that's a second sync engine to maintain.

## Recommendation

1. **Now (2.5.4):** ship (b) plus the missing-revision guard. It's low risk, fixes a real cross-device bug, and makes the data-loss risk visible instead of silent.
2. **Next (2.6), only after App Review answers 5.1.3:** build (a) in its separate-container form, with the synced and local split above. Photos stay local.
3. **Don't** flip `CoachLocal` to CloudKit in place, and don't put Coach records in the legacy container.

## Verification any implementation must pass

**Existing check scripts to keep green and extend:**

- `scripts/run_coach_repository_checks.py`
- `scripts/run_cold_snapshot_checks.py`
- `scripts/run_synthetic_local_remediation_checks.py`
- `scripts/test-coach-execution.sh`
- `scripts/coach_migration_test_main.swift`
- `scripts/coach_archive_test_main.swift`
- In-app suites: `CloudSyncRestorationRegressionChecks`, `CoachPersistenceRegressionChecks*`, `CoachLegacyDuplicateBackupRegressionChecks`, `CoachDuplicateBackupRegressionChecks`

**New checks for (a):**

- Interrupting the journaled copy at each phase leaves the original selected and unchanged.
- The legacy store's `persistentStoreID` and checkpoint are unchanged after the Coach migration.
- Dedupe gives the same result on both orderings.
- Health-derived fields never appear in a mirrored-store export.
- `CoachCalendarMapping` never leaves the local configuration.

**For (b):**

- An archive exported on install A restores on a fresh install B, with photos byte-for-byte equal (by digest).
- A second device with a synced `TrainingPlan` but no revision shows the guard, not an empty program.

**Two-device sync test (a):**

- Two simulators on Apple-silicon Xcode, both signed into the same sandbox Apple Account, Development environment.
- Write on A, relaunch or foreground B, assert the rows arrive.
- Write the same `civilDate` on both, assert the resolution UI appears.
- Restore one archive onto both, assert no duplicate `id`s after sync.
- `LiveCloudSyncVerificationView` receipts gain a `coachCloudContainerMatches` check.
- A simulator pass doesn't prove production behavior. `storage-boundary.md` already says a real-device pass is required.

Sources:

- [Developer Forums: "Guideline 5.1.3(ii) — what counts as personal health information for CloudKit?"](https://developer.apple.com/forums/thread/844159)
- [Developer Forums: NSPersistentCloudKitContainer with multiple stores](https://developer.apple.com/forums/thread/128563)
- [NSPersistentCloudKitContainer documentation](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer)
