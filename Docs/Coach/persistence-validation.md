# Coach storage, backup, and local validation

Implementation state: local source changes, September 13, 2026. The checks described here use disposable files, model stores, and Simulator calendars. They do not use personal user stores, Health samples, personal Photos assets, CloudKit records, or a physical device.

## Storage and ownership

`CoachRepository` accepts writes only in the `CoachLocal` configuration containing the new Coach entities, or a disposable in-memory container with that schema. The existing activity, weight, and scheduler entities remain the shared identity source. Coach records use UUID links and value snapshots; they do not add another weight or activity history.

`CoachLocalOwnership` copies the existing SQLite store with `sqlite3_backup`, including committed WAL content. `copyAuxiliaryFiles` also copies the sibling `.<store stem>_SUPPORT` directory used by external-storage attributes. A live disposable SwiftData probe confirmed `.default_SUPPORT/_EXTERNAL_DATA/<UUID>` for `default.store`. The copier rejects symbolic links and special files, hashes source and destination assets, and verifies the source again after each copy. The source remains untouched.

The opt-in flow owns selection of the new container. Its final marker must only be written after the ID inventory and normalized value/relationship snapshot agree before copying, after opening the copy, and against a fresh source context. The selected local directory and the Coach photo/staging directories are protected and excluded from automatic backup. Large prescription/execution payloads use external storage to avoid embedding them in ordinary scheduler rows.

This is a non-destructive local-copy implementation. It does not prove physical-device CloudKit behavior, retire the retained legacy store, remove remote copies, or establish a completed privacy review.

## Repository behavior

- Imports validate and expand away from the main actor. Each model transaction uses a separate non-autosaving context, so rollback does not discard unrelated view edits. Source identities, local occurrence UUIDs, revisions, prescription snapshots, and reviewed exercise mappings persist together.
- Duplicate content is matched using source program identity and normalized fingerprint. Changed revisions require an explicit draft replacement or separate copy; replacement requires the expected prior revision. First-phase readiness can be committed with activation.
- New executions require an active program and the readiness gate declared by their immutable revision. Repeated Start uses the existing execution, including resume while a plan is paused. Manual outcomes do not change phase readiness.
- Progress uses inclusive civil dates in the program timezone. Rest, optional slots, and removed revision audit rows are excluded from the required denominator. Genuine skipped required sessions remain in that denominator.
- Daily totals replace selected fields. Zero and absence stay distinct. Manual sleep overrides the displayed Health duration without adding the two. Date correction requires reviewed fields and the expected destination identity; a new or stale collision fails.
- First activation creates effective target periods. Resume preserves them. Documents without nutrition targets preserve existing targets. Explicit target edits affect today or later; logged-day target snapshots remain unchanged.
- Coach and Weight share `WeightEntry`. The local Health importer uses anchored sample UUIDs and exact deletion UUIDs, retains multiple observations per day, and leaves legacy source-unknown rows unknown. Purge generations prevent suspended imports from repopulating deleted history.
- Deleting a program requires active executions to finish or cancel. Calendar mappings require an explicit keep/remove decision. Completed activities and their required prescription history survive. Unused draft revisions and future program targets are removed; prior logged targets remain recoverable. Deterministic local reminders are canceled after the model transaction succeeds.

## Photo files

Selected images are processed individually. Sources are bounded at 25 MiB and 64 megapixels before full decoding. The retained JPEG has a 2,048-pixel maximum edge; its thumbnail has a 512-pixel maximum edge. Pixel re-encoding normalizes orientation and excludes source location metadata. Imports copy into app-owned local storage and never change the original Photos asset.

Import/delete journals record the exact app-owned asset identity. Launch recovery checks those journals and preserves assets referenced by committed metadata. It only removes old UUID-named unreferenced artifacts from the dedicated staging directory; it does not sweep ordinary photos.

## Deliberate backup format

`DataBackupService.exportAll` produces `.pacebackup`, a version-5 uncompressed stream with a manifest, bounded record JSON, and separate image assets. The explicit `includePhotos` option controls whether photo metadata/assets are included. The existing v1–v4 JSON import route remains available.

Limits are enforced against declarations and actual reads: 64 MiB record JSON, 25 MiB per image, 10,000 archive entries, and 2 GiB total bytes including headers. The format supports only declared `records.json` and `photos/<UUID>.jpg` entries. It cannot represent links or arbitrary directories. Duplicate paths, traversal, absolute paths, symbolic-link inputs, trailing entries, missing/corrupt digests, and invalid retained JPEGs are rejected.

The record graph includes generalized plans/occurrences, immutable revisions, execution actuals and timers, reviewed progression records, effective targets, daily logs, recovery, waist, photo metadata, phase gates, and external calendar mappings. Added fields on existing workout, set, run, and weight records are serialized too. Active canonical run checkpoints are mirrored into the execution snapshot immediately before export.

Restore validates records/assets in protected staging, installs assets away from the main actor, and commits models through an isolated context. The journal defaults to rollback until the database save is durable. On interruption, files without committed metadata are removed; files belonging to an already-committed save are retained. Failed/canceled imports cannot silently become a later import. Concurrent restores are serialized. Purge/cancellation checks cover parsing, file installation, pending recovery, and export completion.

## Checks actually run

| Check | Observed result | Scope |
| --- | --- | --- |
| `scripts/coach_archive_test_main.swift` compiled with the production archive and photo-store sources | 34 checks passed | Streamed JPEG/record round trip, asset install and replay, rollback journal intent, interrupted partial installation cleanup, retained committed images, existing-content collisions and retry, damaged staging without final output, precommit image rollback, corruption, truncation, trailing data, missing assets, explicit no-photo export, JSON routing, traversal/absolute paths/symlinks, duplicate/oversized declarations, corrupt source image, orientation, retained dimensions, location-metadata removal, thumbnail dimensions, digest |
| `scripts/coach_migration_test_main.swift` compiled with the production SQLite and auxiliary-file copiers | 9 checks passed | Live disposable on-disk SwiftData store with WAL, 2,500,000-byte external blob, scalar values/UUIDs/relationship/optional value, reopened destination, unchanged readable source, separate interrupted copy, symlink rejection |
| Swift frontend parse of persistence/backup sources | Passed | Syntax only |
| Central on-disk app regression on iPhone / iOS 26.5 | 128 assertions passed | Real app models, persistence/execution/schedule runners, including the 26 follow-up persistence assertions and four final distance/permission checks; `testCoachPersistenceAndExecutionRegressions` in `.tmp/coach-audit-phone-pass4.xcresult` |
| Central local-Calendar regression on iPhone / iOS 26.5 | 36 assertions passed | `testCoachCalendarExportRetryAndRemoval` in `.tmp/coach-audit-phone-pass4.xcresult`; two disposable local calendars and reopened model/EventKit stores |

The standalone archive harness uses minimal Codable model/storage adapters to isolate production file-boundary code from the app UI. The standalone migration harness uses small SwiftData probe models and the production copy functions. Those two results are macOS process checks; the separate central rows above are observed iOS Simulator results. Neither establishes physical-device acceptance.

Reproduction commands from the repository root:

```sh
xcrun swiftc WorkingOut/Features/Coach/Data/CoachHistoryArchive.swift WorkingOut/Features/Coach/Data/CoachPhotoStore.swift scripts/coach_archive_test_main.swift -o /tmp/coach-archive-tests
/tmp/coach-archive-tests
xcrun swiftc WorkingOut/Data/CoachLocalOwnership.swift WorkingOut/Data/CoachLocalOwnership+Assets.swift scripts/coach_migration_test_main.swift -o /tmp/coach-migration-tests
/tmp/coach-migration-tests
```

`CoachPersistenceRegressionChecks.run()` also provides DEBUG-only integration checks using the real application models and disposable on-disk containers. It covers the legacy/local copy, source/value/relationship preservation, backup graph round trip, old-version missing fields, daily source semantics, reviewed date merges, failed isolated writes, and duplicate-backup rejection before writes. Per-run simulator evidence is maintained in [implementation-status.md](implementation-status.md); the standalone host results above are not substituted for that evidence.

## Remaining acceptance boundaries

Physical-device storage protection and actual CloudKit transition behavior, Health permission/source corrections, remote Photos download/offline access, device-locked run/rest recovery, and notification delivery require device acceptance. Real disk-full and forced termination during backup/store commit have not been induced. The fixture rollback tests exercise deliberate transaction failure and interrupted staged copies; they do not simulate every operating-system failure. Large-history performance and real multi-gigabyte export remain unmeasured.

## Central integration result

The coordinated final-source rebuild and unsigned generic-iOS Release build passed. The central iPhone / iOS 26.5 run passed the 128-assertion on-disk regression and 36-assertion Calendar regression, including the final stale-operation and reminder-ownership guards. The legacy regression run passed seven UI tests: five backup flows and two running flows (`.tmp/coach-audit-legacy-final.xcresult`). These are named test results; they do not imply every test in the same result bundle passed. See [simulator-audit.md](simulator-audit.md) for the complete run record, retained failed attempts, and remaining device boundaries, and [implementation-status.md](implementation-status.md) for delivery state.

## Follow-up failure audit

The follow-up simulator testing request exposed additional source-level failure paths. Restoring different UUIDs for an already-logged nutrition/recovery date could create duplicate daily records; restored calorie targets lacked the bound and integral-value check needed before later conversion to `Int`; moving a recovery check-in could relabel Health sleep as belonging to a different day; and a failed direct copy could leave a partial final photo that blocked a later restore. A different active program could also be restored alongside the current active program.

Restore now checks daily conflicts, immutable revision/photo conflicts, and active-program conflicts before any model mutations. Invalid target values and mismatched photo/asset IDs are rejected. Recovery date correction keeps Health coverage on its measured day and moves the reviewed manual fields. Restore images are copied to a journal-owned temporary file, verified, then renamed on the same volume; rollback removes partial installation files and retains committed referenced images. Deleting a photo whose file is already missing is idempotent.

`CoachPersistenceRegressionChecks+Failures.swift` adds 26 real-model, disposable disk assertions. They cover stale nutrition/weight/waist editors; a stale destination merge preserving both entries; measured-day Health sleep retention when manual fields move; destination Health coverage during a reviewed collision; duplicate nutrition/recovery dates within or across backup graphs; rejected imports leaving both the store and restore context unchanged; overflow-sized/fractional target calories; mismatched photo/asset identity; repeated restore; exact same-day workout unlinking and stale progression evidence; and conflicting active-program restore. The central integration entry point includes these assertions; their per-run result is reported with the central simulator evidence, not as a separate host pass.

The 34-check archive harness and syntax/diff validation were run after these edits. The 9-check disk migration harness result remains applicable because its production copy paths were unchanged. No real backup disk-full event, forced process kill during a store commit, personal device data, or live external-service behavior is claimed by this follow-up audit.

## Calendar retry and stale-operation audit

Calendar export/removal uses an isolated model context. Exact stored event identifiers take priority over copies of a token URL. Fallback lookup is restricted to the mapped calendar and an explicitly selected export destination. Ambiguous matches and unavailable or unresolved pending mappings remain available for retry. The actual mapped calendar is retained until EventKit confirms a move; a failed final metadata save rolls back to the persisted pending state.

Every selected row is validated before batch mutations. An immutable selection captures occurrence/plan identity, schedule revision, dates, time zone, execution/status/provenance, title, and the local purge generation. A fresh model context checks those values after permission waits and before external work. Notification scheduling checks again after each awaited addition and removes identifiers added by that invocation if the selection became stale or the operation failed. A main-actor ownership guard prevents overlapping Coach reminder writers across view instances; only the owning invocation releases it, including on failure.

`CoachCalendarRegressionChecks.run()` passed all 36 assertions in the central iPhone / iOS 26.5 run. It creates two fresh local Simulator calendars, checks neutral titles, explicit title/duration/date choices, idempotent export, same-calendar and cross-calendar copied URLs, ambiguous lookup rejection, retry through a reopened `ModelContainer` and new `EKEventStore`, explicit calendar moves, pending move recovery, missing-calendar mapping retention, whole-batch preflight, oversized duration rejection, exact deletion, and verified removal of both disposable calendars. Five deterministic selection checks cover an unchanged snapshot and rejection after move, skip, deletion, or a prior purge generation. The purge case changes only its captured test value, not the app's global purge generation. Three ownership checks reject an overlapping writer, reject release by another invocation, and accept acquisition after the owner releases.

These checks do not claim notification-daemon race reproduction, a real Calendar permission interruption, forced process termination during EventKit/model commit, remote calendar synchronization, or physical notification delivery. The overlap guard is tested deterministically through the same acquisition/release functions used by production; no live notifications are raced by this fixture.
