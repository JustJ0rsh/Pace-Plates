# Cold WAL snapshot preparation — 2026-10-23

The prior physical QA build safely refused a valid, fully checkpointed WAL-format SQLite main file when no WAL/SHM sidecars remained. The source-read path now handles this state through a disposable clone. This is integrated into `CoachLocalOwnership.copyStore`, `rawCheckpoint`, and source diagnostics; it is not a standalone replacement app or a change to the live user's files.

## Source preservation

`CoachSQLiteReadSnapshot.withReadOnlySource` identifies a WAL 2/2 header with no WAL, SHM or rollback-journal path before opening SQLite. This avoids allowing a read-only SQLite connection to create sidecars beside the original. Other states use the existing read-only SQLite transaction; no arbitrary SQLite error triggers a cold fallback.

The cold path holds a no-follow, read-only source descriptor. It checks regular-file identity, pathname binding, nanosecond modification/change timestamps, size and SHA-256 before and after work. Sidecar checks use `lstat`, so a dangling link does not count as absence. `fclonefileat` creates a new COW clone in a private protected temporary directory; unsupported cloning fails rather than substituting a live file copy. The clone must differ from the original inode and match its bytes.

Only the clone is opened writable. It must pass SQLite integrity checks, retain all schema objects/declared column values and relevant header PRAGMAs across journal normalization, and close successfully. Its normalized bytes are pinned before consumers receive a read-only transaction. Source and clone verification repeat before returning a result, including failure/cancellation paths. Temporary cleanup only removes the owned snapshot directory. Original files, source sidecars and external assets are not deleted or normalized.

Atomic COW creation is not SQLite writer coordination. Observed source activity, file replacement, sidecar arrival or content changes reject the operation. This path verifies available materialized history; it cannot establish whether somebody previously lost a WAL containing newer commits, and does not invent or recover absent records. Existing all-field, relationship, external-asset, selection-journal and recovery checks remain in place.

## Executed local checks

- `scripts/run_cold_snapshot_checks.py`: **198 checks passed** against the actual production helper. Cases include cold routing, read-only source/directory, null/blob/relationship values, six interruption phases and retry, source replacement/content changes, sidecar arrival/dangling link, hardlink/symlink replacement of the clone, normalized-copy tampering, metadata/schema/record tampering, truncated sources, FIFO rejection, consumer failure, task cancellation and cancellation concurrent with a source change.
- `scripts/run_synthetic_local_remediation_checks.py --copier-only`: **22 checks passed** using the actual production reader, checkpoint verifier, SQLite backup and external-asset copier with a two-model SwiftData probe. Cold migration preserves stable IDs, scalar values, a relationship with an unknown actual, and a 2.5 MB external payload. Retry does not duplicate records; retained source bytes and asset digest remain identical.
- The app's existing full-model regression fixture now requires successful cold migration, four cold journal interruption/retry cases and safe rejection of a damaged cold source. Those iOS fixture changes have not been executed on a physical device during this local-only preparation.

Reproduce the focused checks without a device or simulator:

```sh
python3 scripts/run_cold_snapshot_checks.py --output /tmp/pace-cold-evidence
python3 scripts/run_synthetic_local_remediation_checks.py --copier-only --output /tmp/pace-copier-evidence
```

On macOS, SwiftData macros may require normal host execution rather than a nested restricted sandbox. Both tools accept an optional `--module-cache` path and only create their own disposable test stores. No user-store path is accepted.

## Remaining acceptance

The new source still needs the full iOS regression run and normal UI verification on the isolated **Pace Full QA** app when phone access is explicitly authorized again. Preserve its existing QA store and production app. Recheck the cold migration result, full-model fields/assets, all interruption cases, legacy restore formats, and existing Finish/swipe behavior. An unsigned local build is preparation, not installation or an App Store artifact.

Older shipped-schema compatibility, active/recoverable run transitions, real Health/CloudKit integration, reboot/locked-device/power-loss durability, production signing/provenance, and release privacy declarations remain separate release gates. No merge, production migration or release is authorized by these local checks.
