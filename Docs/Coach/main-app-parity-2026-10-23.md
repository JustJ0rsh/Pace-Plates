# Preserve the existing main-app workflows

The owner's installed development app is version 2.5 (5). The original, still-dirty checkout's `Docs/Coach/usability-followup.md` records that build as coming from the uncommitted working tree. The reviewed PR9 tree omitted those edits, so an immediate replacement would risk losing existing Coach workflows.

This follow-up combines those existing edits with PR9 at `f1b008c44e13848620f030cc8b1809e00b049741`. It restores planned workout/run cards and lists, Coach dashboard and saved-plan navigation, separate paste/file import and review guidance, phase readiness guidance, active-recording attestation protection, and the transaction-time active-plan acknowledgement check. The newer draft timestamp check, removed-occurrence rejection, numeric bounds, local-storage boundary, and Finish/swipe-save behavior remain intact. Original files were never overwritten.

All 15 `@Model`-bearing files are byte-identical to both the reviewed source and the original dirty checkout. This is not proof of the installed database's schema or a substitute for preserving its data before replacement. A configuration-only read found an existing version-1 local selection marker on Eagle 1; the current startup code supports that marker without invoking legacy migration.

The in-app privacy text now describes this version's local-only history, retained legacy copies, deliberate backups, optional Apple services and user-initiated sharing. Website and App Store declarations have not been changed or certified.

## Focused validation

- Independent source review found no remaining must-fix after correcting old UI tests that still expected Finish to mark completion or ask to save a partial workout. Those tests now expect saved/resumable actuals without invented completion.
- 22 host checks passed using the actual production repository/domain/model code and disposable SwiftData stores, with inert notification and generation adapters. They cover active-plan review, draft timestamp conflicts, idempotent replay, removed occurrences and valid start/resume. Evidence: `/tmp/pace-parity-repository-final-20261023/`.
- 47 save-boundary checks passed, and 15 source-wiring checks passed. They retain Finish and dismissal persistence, duplicate/reentrant callback guards and recoverable save errors.
- Restored SwiftUI files and tests passed syntax parsing. This is not a claim of UI execution.
- The first normal production-ID Debug build from the prior PR9 source passed, but was withheld after the feature-parity mismatch was found. A combined build and isolated on-device regression run are required before delivery.

The isolated storage acceptance entry point now runs the planned-activity suite once; that suite includes activation regressions. No real records or services are used by those fixtures. Real app/shared-container backup requires the owner's separate approval. Main-app install/launch and release signing remain later gates; no App Store upload or release is established by these source checks.
