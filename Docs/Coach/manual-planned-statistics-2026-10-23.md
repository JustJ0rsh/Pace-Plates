# Manual logging and planned workouts

The owner reported that a manually entered workout from yesterday was present in Workouts with all sets and weights, but Home showed no volume and a zero streak. The set circles were empty. The old Home predicate treated those saved manual sets as unperformed.

The owner clarified the intended behavior: manual entry should count without checking circles; circles belong to planned workouts. This change implements that distinction without rewriting historical records, completion flags or numeric values.

## Behavior

- Existing manual history and newly entered manual sets contribute valid recorded reps/weight or duration directly. Manual rows do not show completion circles.
- Template/Coach/scheduled sessions and sessions explicitly marked `planned_workout` are plans. Only checked planned sets contribute to statistics; known zero or invalid actuals never fall back to nonzero targets.
- **+ Plan** appears beside **+ Exercise**. An empty new draft can become a plan; starting a plan from existing history creates a separate planned workout. It does not convert recorded manual history into an unchecked plan.
- Repeating an old workout creates a planned workout, because its prefilled values are targets rather than newly entered results.
- Home volume, workout charts and quick views, Home streak eligibility, the streak calendar, and streak-service workout eligibility use the shared read-only projection. Existing daily/weekly date-anchor rules remain unchanged. Game Center volume-submission policy is outside this patch.
- Finish and swipe-dismiss persistence remain unchanged. No redundant workout Done button or QA banner is added.

## Validation and limits

**60 focused regression checks passed**, using the real models and a disposable local SwiftData store. They cover manual unchecked values, data-preserving reopen, plan/template/Coach flags, partial checked plans, copied targets, valid zero-load work, timed work, unit conversion, invalid/extreme numbers, finite aggregation and per-exercise subsets. Nil/matching/conflicting inverse ownership IDs exercise the exact production compatibility predicate; SwiftData repairs inverses itself, so the fixture does not pretend to reproduce a corrupt relationship store.

Evidence: `/tmp/pace-workout-statistics-final-membership-20261023/`. Existing rows are classified by their stored planning identifiers; ambiguous older unmarked rows are not rewritten or backfilled.

The source has independent review and Swift parsing checks. The initial iOS QA build passed 270 device checks (210 storage/recovery and 60 statistics checks). Physical UI testing confirmed manual rows without circles, Finish saving directly, and planned rows with circles. That UI test also caught Home's latest-workout destination changing when a new plan reordered its query. Home now pins the tapped workout until its detail is dismissed; this follow-up passed independent source review and requires the explicit phone regression below before normal installation.

Phone regression: open a manual workout from Home; create a separate plan with different values; Finish the plan; verify the original detail still shows its original title, manual mode and values. Return Home and verify the latest row opens the new plan; reopen the original from history and verify it is unchanged.

No model fields were added. The plan marker uses an existing provenance string on newly chosen plans only. No real workout records were inspected or edited during development. Before the normal app update, a fresh private app/shared-container recovery copy was made under the owner's explicit approval without inspecting record contents. The prior recovery backup remains untouched.

Local test evidence and final counts are recorded in the associated handoff; no App Store upload or release is part of this change.
