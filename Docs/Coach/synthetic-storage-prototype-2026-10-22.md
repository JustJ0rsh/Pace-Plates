# Synthetic local-storage remediation prototype

22 October 2026. Based on PR8 head `dd254b6f2849a21cf4de3e6e7fa9c6b41721fbf3`. This is a **standalone protocol experiment**, not a production migration, a change to the default store, or a completed privacy remediation. No application target references the prototype. Existing CloudKit configuration, entitlements, production onboarding and real user data are unchanged.

## Implemented boundary

`scripts/synthetic_local_remediation/prototype.py` creates its own temporary root with a per-run synthetic ownership marker. It has no parameter for an existing source store or application container. It creates a WAL-backed SQLite fixture from the checked-in [field inventory](cloudkit-field-inventory-2026-10-22.json): all **14 legacy model names, 253 scalar/blob field names, and 14 declared relationship names**, with three rows per model. A declaration comparison against the actual Swift source fails closed on inventory drift, including new inferred-type stored properties. The parser is intentionally narrow; future Swift syntax changes require review.

The fixture covers stable UUIDs, nil values, dates, Unicode/newlines, numeric values, raw blob bytes, ordering fields, Health-labelled values, unknown `manual_or_legacy` provenance, and relationship target IDs. These are generated SQLite representations. **They are not the app's actual SwiftData model objects or its backup serialization format.** Relationship edges are explicit fixture values; the test checks all target identities exist. Two generated auxiliary assets are also copied and hashed.

The experiment provides:

- A cross-process exclusive writer lock and atomic, fsynced journal/selection replacement. Directories use mode `0700` and files use `0600`; this is host filesystem isolation, not a claim about iOS data protection or encryption.
- States `allocated → checkpointed → copied → verified → active`, with selection written after verifying the source, copied schema, every fixture value, and auxiliary assets. The source and unselected copies remain available throughout the run.
- Resume after injected interruption, including a complete copy before the copied journal and selection committed before the active journal. Retrying a selected copy does not recopy it or discard later local events.
- One centralized selected-state validator before writes, migration retries, restart checks, rollback and forward recovery. It verifies the selected directory, journal/version/generation binding, known schema, preserved graph/assets, and the operation/event ledger. Missing/tampered journals, changed selected fixture fields and unknown schema additions require recovery rather than writes or source fallback.
- Generic inert ingress labels for manual, Health strength/cardio/weight, plan generation, run recovery, callbacks, and backup versions 1–5. They exercise **one modeled destination guard** against a fake cloud-capable destination. They do not call or prove coverage of those production app entry points, HealthKit, CloudKit or backup formats.
- Stable operation identities committed in the same SQLite transaction as new synthetic events. Exact replay is idempotent; the same ID with different content is rejected without advancing the fake anchor. Distinct unknown-provenance IDs with equal values remain distinct. A stale store-generation token cannot write or advance an anchor.
- Pre-write rollback only when both retained histories still match the verified checkpoint. Once a new local event exists, rollback is rejected even if interruption left the marker's write count stale. Forward recovery copies current local history into another local store, changes its epoch, and retains both previous local and original source histories.

Only the synthetic event ledger is mutable after selection. The 14-model fixture graph is deliberately immutable so the validator can distinguish damaged copied data from the permitted new-event stream. A production implementation would need transaction-aware baseline evolution for real model edits; the prototype does not supply that integration.

## Verification

Run the complete host checks from the repository root:

```sh
python3 scripts/run_synthetic_local_remediation_checks.py --output /tmp/pace-synthetic-remediation-evidence-20261022
```

The runner uses `/Applications/Xcode.app/Contents/Developer` explicitly and a fresh module cache, avoiding the machine's different default toolchain and `/tmp` versus `/private/tmp` cache aliases. `--python-only` runs only the protocol experiment where SwiftData is unavailable. Xcode's macro plugin needs permission to start under a nested filesystem sandbox; no device/account permission is involved.

| Evidence | Result | Scope |
| --- | --- | --- |
| `test_prototype.py` | 35 tests passed | All inventoried fixture fields/relations and assets, source preservation, source/remote-change simulation, copy/marker I/O errors, eight migration interruption boundaries, two forward-recovery boundaries, corrupt/missing/unknown metadata/schema/assets, selected-state validation, all modeled ingress labels, stale epochs, exact/conflicting replay, model commit before anchor failure, cross-process lock contention, pre-write rollback and post-write forward recovery |
| Existing `scripts/coach_migration_test_main.swift`, compiled with unmodified production `CoachLocalOwnership.swift` and `CoachLocalOwnership+Assets.swift` | 9 checks passed | **Actual SwiftData** disposable two-model probe with `.none`, committed WAL, 2,500,000-byte external blob, scalar/UUID/relationship/optional fidelity, reopened destination, readable original, separate interrupted copy, and symlink rejection |

The second row is separate evidence for the actual production SQLite/asset copier; its probe aliases the legacy model names and does not instantiate all 14 app models. The protocol tests do not replace that distinction. Core Data emitted `unable to check registration for posting store changed notification` in the host sandbox; the nine assertions completed successfully.

The run writes logs and a source-hash manifest to the evidence directory. Failed development attempts exposed a Swift macro sandbox restriction and then a module-cache alias collision; the final runner uses a fresh canonical cache and the successful result is recorded separately. No simulator was used by these host checks.

## Remaining gates

`restart()` re-reads the same owned fixture files after an injected exception; it is **not** an OS process kill, power-loss, reboot, filesystem durability or device-lock test. Disk-full behavior is an injected copy/marker I/O error, not an exhausted physical disk. Source-change hooks are synthetic SQLite edits, not a live CloudKit reconciliation test. Metadata/checksum checks detect invalid state; the journal is not cryptographically authenticated against an attacker rewriting all files.

The ten Coach-local types/photos, live model setters, actual v1–v5 restore formats, production async import/service callbacks and anchors, active-run fencing, app extensions, multi-device/old-client conflict policy, real iOS backup exclusion/data protection, and physical-device acceptance need implementation and verification before a production proposal. No source store or cloud record is deleted, no real store is opened, and no release decision is made here. The existing [remediation design](local-storage-remediation-design-2026-10-22.md) remains the policy and integration review boundary.
