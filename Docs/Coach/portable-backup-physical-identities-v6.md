# Portable history backup version 6

Backups whose model UUIDs are unique retain the version 5 format and merge behavior. Backups containing repeated UUIDs use the `PACECOACH6` header and a version 6 manifest. Version 1–5 imports remain supported.

The ordinary snapshots retain every original application UUID. `physicalRecords` identifies each snapshot by collection, index and an opaque archive key, and records exact physical relationship targets. Validation checks complete coverage, identity uniqueness, bounds, allowed relationship names/types/cardinalities, UUID snapshots and inverse consistency before creating models. No schema or app-model fields were added.

A physical import stages collision-free internal IDs in an unsaved isolated context, restores original UUIDs and exact object relationships, then saves once. Health inbox rows are reconstructed without replacement/deduplication heuristics. The ordinary public import rollback handles a failed final save; its regression uses a real read-only destination.

For duplicate components, complete row payloads and graph structure must match retained history before an exact-repeat import is skipped. Changed or partial ambiguous components reject before any records are inserted. New disconnected records can be added. Unique records preserve existing non-destructive merge rules and the current-plan-revision conflict guard.

Multiple photo metadata rows may share a verified image asset; the archive streams that asset once and checks each metadata reference. Export without photos removes both photo records and their physical identities.

The saved-file regression populates all 24 current model types, includes duplicate definitions/workouts/sets/runs/planned slots/inbox/photo rows, and verifies exact parent links, large route data, photo bytes, reopening, repeat imports, mixed additions, ambiguous rejection and failed-save rollback. Separate compatibility checks cover older JSON formats and the previous revision-conflict checks. This is synthetic storage verification, not a claim that deleted local-only data can be recreated without a surviving backup.

Older version 1–5 archives containing duplicate UUIDs can be upgraded in memory when their saved foreign keys identify exactly one physical relationship graph. This includes standalone unlinked duplicate runs, identical unlinked weight rows, and duplicate rows unrelated to uniquely referenced parents. The original archive bytes and v5 header/manifest remain unchanged. Missing parents, duplicate parent references, or conflicting inverse links reject before mutation with recovery guidance; no date/name/content heuristic chooses a parent. Ordinary legacy archives without duplicate IDs keep their existing path.
