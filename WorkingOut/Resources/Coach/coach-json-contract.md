# Coach program JSON interchange contract, version 1

Status: proposed implementation specification, not an implemented feature. The authoritative artifacts are `coach-plan-v1.schema.json` for shape/types and this document for semantics and import behavior. `example-coach-plan.json` is a generic two-week import fixture, not an individualized exercise or nutrition prescription.

## Boundary and implementation ownership

Implement unconditional Foundation/Codable `CoachProgramDocumentV1` DTOs in a shared domain/import layer. They must compile and validate without FoundationModels. Manual creation, paste, file import, and AI generation produce the same DTO and use the same validation, preview, and persistence pipeline. Keep FoundationModels-specific generation types as adapters into that DTO; do not move the new interchange contract inside `#if canImport(FoundationModels)`.

The existing `WorkoutPlan` in `Features/AI/PlanSchema.swift` is a one-week, FoundationModels-gated legacy format. Retain an explicit legacy adapter for already-saved data. Do not pretend legacy records contain structured rest, RIR, intervals, or completion associations that were never recorded. Surface unresolved legacy values for review.

Version 1 contains program definitions and prescribed targets. It contains no start date, actual workouts, completed sets, food intake, body measurements, recovery check-ins, photo bytes/URLs, private health records, Apple Health identifiers, credentials, or executable expressions. Program sharing/export and private full backup are separate formats. Importing a program never marks anything complete or writes Health data, reminders, or Calendar events.

## Document and identities

Required root keys are `format`, `schemaVersion`, `programId`, `revision`, `title`, `goal`, `preferredUnits`, `phases`, `sessionTemplates`, `weekPatterns`, and `weeks`. The only recognized format is `pace-and-plates.coach-program`, and the only supported schemaVersion is integer 1. Unknown versions fail with an actionable compatibility error before any write. This proposal intentionally does not define a future extension namespace: unknown fields are errors, including unknown nested fields.

`programId` is an opaque author key, not a display title or an authoritative local database ID. `revision` is a positive author revision number, not schemaVersion. All author IDs are case-sensitive ASCII strings matching the schema. Preserve them when revising the same program. Each local imported copy receives its own UUID and import-family UUID, so two unrelated documents using the same programId cannot overwrite one another or collide across imports or restores. Persist author IDs as source identifiers alongside local identities. Follow the implementation plan's protected local ownership boundary for personalized programs and tracking.

Uniqueness rules:

- IDs are unique within each root collection: phases, templates, patterns, weeks, and progression rules.
- Slot IDs are unique across an entire week pattern, including different days. Multiple slots on one day are allowed, up to eight.
- Exercise-row IDs are unique within a strength template; set IDs are unique within their exercise row.
- All segment and repeat-block IDs are unique across all three sections of a running/cardio template, including segments nested within repeat blocks.
- An exercise `key` consistently identifies one authored movement throughout the document. Reusing the same key for incompatible names, equipment, or catalog IDs is a conflict requiring correction.

The expanded external occurrence key is `(programId, week.id, slot.id)` within the local import family. Never use a date, title, template ID alone, array index alone, or generated random UUID as the sole deduplication key. A reused template has separate occurrences every time it appears. A set's prescribed identity adds the exercise-row ID and set ID. An interval's identity adds section, block/segment ID, and one-based repeat iteration where applicable.

Copying a week inside the app assigns a new week ID; repeating a week on the live schedule creates new occurrence identities linked to the source week and repetition, without reusing the old completed occurrences. IDs must not be recycled to represent a different workout in later revisions.

## Compact schedule and date semantics

`weeks` is an explicit, ordered list; its array order defines consecutive program weeks. Every week references exactly one phase and one reusable week pattern. A 26-week plan therefore has exactly 26 week entries. It may reuse a small number of week patterns and session templates. There are no range expressions, recurrence strings, nested repeat weeks, or ambiguous deep-merge overrides in version 1. Different prescriptions use alternate templates and/or patterns.

Within each pattern, `dayOffset` is 0 through 6 relative to the selected start day of that program week. Day 0 does not inherently mean Monday. Slots on the same day retain array order. Missing days are unscheduled, not automatically rest; explicit rest uses a rest template. Reject a pattern that places rest alongside another slot on the same day. Optional workout slots are labeled optional and excluded from required-session adherence denominators.

The import preview selects the start date and shows actual dates for every week before activation. Expand with calendar-day arithmetic in a saved plan time zone, never multiples of 86,400 seconds. Persist planned civil dates separately from actual result timestamps. Device travel must not silently move workouts to another day. Changing plan time zone, start date, or weekdays requires a schedule preview and only affects selected unstarted future occurrences. Completed/started occurrence identities and prescription snapshots remain fixed.

Every phase reference must resolve, all declared phases must be used, and phase appearances follow declaration order in contiguous week ranges. A phase's `advanceMode: scheduled` allows its future sessions to become available by schedule. `reviewRequired` requires explicit user confirmation before activating that phase; advancing the date alone must not satisfy it. Import start/review can supply that confirmation for the first phase. Nutrition/recovery targets at a phase replace the corresponding complete program-level target block; fields absent from a replacement are unset. There is no invisible partial merge.

## Prescription semantics

Strength exercises are ordered rows. Every set has its own stable ID, role, and either an inclusive rep range or a duration in seconds. Optional load, rest, effort, and notes are retained per set. `prescriptionBasis` states total versus per-side reps/time; `loadBasis` distinguishes total external load, load per implement, added bodyweight load, and assistance. A missing load means unspecified, not zero. A zero external/added load is a valid explicit value; zero assistance is distinct from missing. Units on individual values are authoritative; preferredUnits controls initial presentation only.

An exercise may offer alternative movement choices. Match catalogExerciseId only if it exists in the installed catalog; never accept a made-up ID as a successful match. Name-only matches require a confident exact/canonical match or user resolution. Do not silently substitute a different movement. Unmatched names can become user-confirmed custom exercises. A selected alternative retains reps/time/rest/effort until reviewed, clears suggested loads, and requires confirmation of its load basis. Record the actual selected movement in the workout result. Program-owned prescriptions must not change when a shared library template is later edited.

Running and cardio use ordered `warmup`, `main`, and `cooldown` arrays. Each block is a segment or a repeat of segments; nested repeat blocks are invalid. Segment goals are duration or distance, never both. Version 1 running activity values must be walk, jog, or run; the broader enum is available only to general cardio. Intensity is optional. If present, it must contain at least one of RPE, pace, or cue. Numeric RPE/pace targets remain structured; do not derive them by parsing notes. `minSeconds` in a pace range is the faster bound and `maxSeconds` the slower bound. A distance-driven segment cannot auto-advance without a trustworthy distance source; the execution UI must allow deliberate manual completion and record how it was completed.

Recovery sessions contain instructions and an optional target duration. Explicit rest sessions are schedule information, not performed exercise. Completing a check-in on a rest day does not create a workout, exercise minutes, or a streak event.

## Progression rules

All progression is proposed for review. Both rule kinds require `reviewRequired: true`; false is invalid. Imported text cannot define executable code, formulas, tool calls, automatic Calendar changes, diagnosis, or remote fetches.

`doubleProgression` references a strength template and exercise row. That row must have at least one working set; every working set must use a rep target and prescribe RIR. The increment must be greater than zero and refers to that row's load basis. It is eligible only after the specified number of consecutive comparable, completed occurrences have actual load, reps, and RIR for all working sets, meet every upper rep bound, and meet minimumRIR. Partial/skipped occurrences, unresolved substitutions, incompatible units/load bases, or missing effort do not count. Never convert RPE to RIR implicitly. Warm-up, back-off, and drop sets do not satisfy this particular rule.

Do not generate an eligible suggestion while the relevant session has a pain flag, incomplete readiness review, or inconsistent actual loads that prevent a meaningful comparable increment. No pain entry must not be interpreted as a documented pain-free session. The application records which inputs supported a suggestion, shows prior performance and proposed changes, and requires acceptance before affecting selected unstarted future prescriptions. Rejected suggestions leave targets unchanged. If no appropriate equipment increment is available, offer manual review rather than applying an invented load.

`manualReview` stores authored instructions and referenced templates for running or other progression. It is guidance to review alongside actual performance, effort, and recovery; version 1 never interprets that prose as automatic progression logic. App-authored later rule kinds require a new compatible contract version and explicit validation support.

## Validation and resource limits

Perform input normalization, strict JSON parsing, version dispatch, schema validation, semantic validation, reference resolution, and review before one atomic persistence operation. Swift Codable alone is insufficient because unknown properties are normally ignored. Explicitly reject unknown properties and duplicate object keys. An optional single outer Markdown code fence labeled `json` or with no language may be stripped, along with surrounding whitespace and an initial UTF-8 BOM. Reject other surrounding prose, more than one JSON document/fence, trailing commas, non-finite numbers, and arbitrary text repair. Preserve user input for correction, but do not persist it in analytics or diagnostic logs.

Report actionable errors with JSON paths, e.g. `$.weeks[3].weekPatternId references an unknown pattern`. Do not truncate a plan, drop a field, coerce a number from a string, silently choose one of several JSON blocks, invent a missing workout, or replace unknown units to make import pass.

Schema bounds are technical resource controls, not exercise recommendations. Enforce the following additional aggregate bounds before allocating expanded models:

- At most 2 MiB UTF-8 input, 104 weeks, 104 phases/patterns, 300 templates, and 200 progression rules.
- At most 56 slots per pattern, eight slots per day, and 5,824 expanded occurrences.
- At most 40 exercise rows and 200 total prescribed sets per strength session, with at most 20 sets per row.
- At most 2,000 expanded segments per cardio/running session. Count each repeat's segment count multiplied by its repeat count before expansion.
- At most 200,000 total expanded execution steps across the program, counting strength sets, running/cardio segments, and one step per recovery/rest occurrence. Reject over-limit input before copying full payloads into occurrences.
- Explicit duration goals total at most 86,400 seconds in any session. Distance-goal segments contribute no invented duration. These permissive caps prevent resource abuse; they do not imply a 24-hour workout is appropriate.

Validate all cross-references, all uniqueness constraints, inclusive `min <= max` ranges, positive progression increments, progression target compatibility, phase contiguity, matching exercise keys, supported activities, and per-day rest conflicts. Nutrition requires at least one numeric target. Recovery requires at least one property. Empty intensity objects are invalid. All references must resolve even in otherwise unused templates/patterns. Unused templates or patterns produce review warnings, not silent deletion.

Warnings requiring review, rather than inferred corrections, include incompatible equipment, unmatched exercises, an excessive or surprising training load, substantial changes from the existing plan, and calorie/macro inconsistency. If all four nutrition fields are present, compare calories with `4 * proteinGrams + 4 * carbohydrateGrams + 9 * fatGrams`; warn when the difference exceeds the greater of 100 kcal or 10% of declared calories. Never silently modify either number. Clinical suitability remains a user/qualified-professional review and cannot be established by JSON validation.

## Duplicate, revision, and commit behavior

Canonicalize a successfully validated DTO for fingerprinting: sort object keys, preserve array order, represent numbers consistently, omit absent optional properties, and explicitly normalize only documented defaults such as omitted slot `optional` to false. Exclude the author revision number from the content fingerprint so a revision-only change is recognized as unchanged content; store revision separately. Do not strip notes or informational fields. Use a deterministic canonicalization implementation with fixtures for numeric encodings and optional defaults; a raw pasted-text hash is inadequate.

Resolve imports by validated source programId plus user-selected local import family and content fingerprint:

1. Same programId and same normalized content: show Already Imported; offer Open Existing or Create Separate Copy. Never create an accidental duplicate.
2. Same programId with different content: show a field/session-level diff and explicit target plan. A higher revision is not authorization to overwrite. Equal or lower author revision with changed content is a conflict; require correction or an explicit separate copy.
3. More than one local import family matches programId: user selects the intended copy before any update. Never choose by recency alone.
4. Draft update: after reviewed confirmation, replace the draft document and regenerate its unstarted schedule atomically. Preserve unrelated library items and user data.
5. Active update: create a pending reviewed revision. Present added/changed/removed future occurrences, user-edited future slots, and retained history. Update only explicitly approved unstarted future occurrences. Started, completed, partial, skipped, moved, and locally edited occurrences remain untouched unless the user separately resolves the conflict. Removed completed occurrences stay in history; do not delete or reassign their results. Changing progression rules affects future suggestions, not historical decisions.
6. Separate copy: assign new local/import-family UUIDs while preserving source metadata for provenance. Starting it follows normal active-plan conflict review.

Before committing a reviewed import, recheck the target revision and plan state in case another app edit or a supported legacy projection changed it while the preview was open. A stale preview requires refresh. Cancellation, validation failure, save failure, or failed conflict review leaves no partial plan, orphan templates, dangling completion links, or duplicate schedule rows. If framework save behavior prevents atomic staging directly, prepare a validated in-memory representation and commit through a dedicated import transaction strategy with rollback/recovery tests.

## Copy ChatGPT Prompt behavior

The Coach Add Plan flow provides Copy ChatGPT Prompt. The copied prompt must name the exact schema version and include the complete current contract/schema or a self-contained compact equivalent; a private local schema file path alone is unusable by ChatGPT. Include one small example and the required semantic constraints. Keep the example explicitly marked as format-only, not personal exercise advice. Do not require ChatGPT to call an API or access the app.

The prompt asks for exactly one JSON object and no prose or Markdown fences, stable IDs, explicit ordered weeks, references that resolve, real numeric types and units, structured sets/intervals, reviewed progression only, and no actual personal logs. It prohibits unsupported fields and directs ChatGPT to leave optional unavailable targets absent rather than guessing. It explains that multi-session days use multiple slots, repeated weeks use explicit week entries referencing reusable patterns, and changed prescriptions use separate templates/patterns.

Allow users to edit optional goal/equipment/schedule/context text before copying. Export no existing body measurements, injury history, recovery notes, photos, or other health data by default. If a user chooses to include personal context, show the exact text to be copied and require a deliberate copy action; nothing is uploaded by the app. A future revision prompt should include the current portable program with unchanged source IDs and an instruction to increment revision, while keeping actual results out unless separately and explicitly selected by the user.

Manual authoring and in-app AI use the same preview, unresolved-exercise resolution, unit handling, schedule selection, and activation controls. Users can save a valid draft before choosing to activate it. Home execution and all trackers consume persisted reviewed prescriptions, never untrusted pasted text.

## Acceptance cases

1. The included fixture expands to eight occurrences across two weeks: four strength, two optional runs, and two rest days. Each run expands to eight segments. Each lift has three prescribed sets. Total expanded steps are 30. It demonstrates two sessions on day 0 and distinct occurrence identities for the repeated lifts.
2. A complete 26-week fixture shows every week/phase, multiple daily sessions, notes, per-side/timed sets, substitutions, and intervals without truncation; exported program round-trips to the same normalized content and source IDs.
3. Unknown root/nested field, duplicate object key, missing required key, unsupported version/unit/kind, numeric string, duplicate ID, dangling reference, reversed range, invalid progression target, nested repeat, and over-limit expansion fail before writes with precise error paths.
4. Exact JSON, whitespace-only changes, object-key reordering, `1` versus `1.0` where semantically numeric, and documented optional defaults have predictable fingerprint behavior. Changing actual instructions changes the fingerprint. Array order changes remain meaningful.
5. Identical import does not duplicate; higher-revision draft update preserves identity after preview; equal/lower conflicting revision is blocked; separate copy is distinct; active updates preserve historical/started/local edits and only apply approved future changes.
6. Cancel at every preview step and simulate a persistence failure: zero partial plans or orphan records. Change the target through another app edit during review: stale preview cannot overwrite it.
7. Starting on a non-Monday, crossing DST, travelling time zones, and changing the start date retain stable identities and expected displayed civil dates. A review-required phase never activates from the clock alone.
8. Disable FoundationModels/AI availability: manual, paste, file import, preview, tracking, and export remain usable offline. Existing one-week mixed plans and dedicated running plans retain their original records through compatibility migration.
9. Resolve an unknown exercise to custom, choose a substitution with a different load basis, and verify the full prescription is reviewed and the actual selected movement is logged. Editing the shared library later cannot rewrite prior prescriptions or results.
10. Completed and partial sets/intervals, actual nutrition/body/recovery values, photos, Health IDs, and Calendar/event identifiers never appear in portable export. Full private backup is tested separately.

## Artifact verification performed

The schema and example were generated as UTF-8 JSON and checked with Python's JSON parser. The verification accompanying delivery checks every local schema reference, strict object shapes, the example against every schema keyword used here, aggregate expansion counts, cross-references, identities, and targeted invalid mutations. This dependency-free check covers this document's schema subset; it is not an independent conformance certification of JSON Schema 2020-12. Both the bundled and system Python lacked `jsonschema`, and no dependency was installed. App implementation must add a real standards-conformant validation path or a tested native equivalent and run the full acceptance suite on the persisted Coach flows.
