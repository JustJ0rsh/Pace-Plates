# Restore boundary acceptance adapter

This Python adapter is **not imported into Pace**. It is a small inert acceptance
model based on PR9 `b1c5830`, now checking the separately implemented production
restore boundary. No app, project, entitlements, startup/default storage, or sync
code references the Python adapter. It opens no database, archive, device,
network, account, or real-data file and accepts no source/store path.
Source-contract reads are fixed to this checkout's two Swift source files.

Run from the checkout root:

```sh
python3 -B scripts/storage_boundary_candidate/test_candidate.py
```

## Concrete gap and integrated boundary

The prior `restorePrepared` and `restore` methods rejected a nonlocal destination
only when `file.coach?.hasPersonalRecords` was true. That failed to protect legacy
weight, workout, route, inbox, custom exercise, template, and free-text records
when Coach was absent/null/empty. The actual Swift methods now require an explicit
local destination with a current, nonretired generation before asset installation,
after its suspension, before model reads/merge, and immediately before commit.
The test pins those source guards and ordering. It complements actual Swift Debug
regression cases added to `CoachPersistenceRegressionChecks`, but does not run them.

The inert adapter models the current, verified, selected **local** destination for
every supported restore, including empty/catalog-only payloads. It does not infer
safety from provenance, a missing Health ID, `isUserDefined`, or version number.
Its additional modeled selected/verified flags are not proof of app state. The
real helper uses the app's explicit local configuration and retirement/epoch gate.

## Evidence and limits

Eleven fast tests cover:

- Pinned top-level `BackupFile` fields (12 record buckets), all 12 Coach graph
  buckets, and production preflight/post-suspension/commit guard sites; drift and
  guard reordering fail the source contract.
- Versions 1–5, absent legacy version, absent/null/empty Coach, all legacy and
  Coach buckets, unknown provenance, route/Health fields, custom/catalog content.
- Rejection before modeled commits/assets for cloud, unselected, unverified,
  retired, mismatched-store, and stale-generation destinations.
- Exact in-memory payload preservation, no-op identical replay, conflicting
  replay rejection, future/invalid versions, unknown top-level keys, malformed
  bucket shapes, duplicate JSON keys, and non-finite JSON numbers.

Fixtures use real envelope/bucket names and representative DTO field names. Nested
rows are deliberately opaque and some omit required Swift DTO fields: these are
**not historical archive samples, complete production DTOs, or evidence that
Swift `JSONDecoder`/`validateForRestore` accepts them**. The current decoder permits
optional buckets in each supported version; the matrix tests the destination
boundary, not historical export conformance. Unknown nested fields are preserved,
not schema-validated.

The adapter's one in-memory commit models side-effect ordering/idempotence only.
It does not prove SwiftData transaction atomicity, real asset installation,
process-death durability, anchor management, or concurrency. No Health anchors
exist or advance in this adapter. Production regression execution must still
validate the actual boundary with real DTO decode and disposable SwiftData/asset
fixtures under fault injection. No SwiftData execution, migration, real
account/service, or physical acceptance is claimed by these Python tests.
