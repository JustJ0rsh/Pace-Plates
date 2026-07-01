# Roadmap: Pace & Plates

## Overview

This roadmap stabilizes the run-tracking trust boundary in Pace & Plates by first making active run state durable, then reconciling app and Live Activity lifecycle across relaunches, hardening save and discard behavior, and finally locking the fix down with regression coverage and device validation.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Durable Run Draft Foundation** - Persist active run state beyond process memory and unify the Live Activity contract.
- [ ] **Phase 2: Recovery and Reconciliation UX** - Detect interrupted sessions on relaunch and guide the user back into a recoverable run flow.
- [ ] **Phase 3: Save and Cleanup Hardening** - Make save and discard flows authoritative locally and guarantee Live Activity cleanup.
- [ ] **Phase 4: Regression Protection and Device Validation** - Add test coverage and a repeatable device checklist for lifecycle-sensitive behavior.

## Phase Details

### Phase 1: Durable Run Draft Foundation
**Goal**: Move active run state from singleton-only memory to durable app-owned draft storage and a shared ActivityKit contract.
**Depends on**: Nothing (first phase)
**Requirements**: [TRK-01, TRK-02, TRK-03, LIV-04]
**Success Criteria** (what must be TRUE):
  1. User can relaunch the app after process death and still find the last in-progress run draft with elapsed time, distance, activity type, and route snapshot.
  2. App prevents creation of a second active or recoverable run while a draft already exists.
  3. Live Activity attributes are sourced from one shared definition used by both the app and widget targets.
  4. Durable draft state is available for later launch-time reconciliation and save/discard cleanup flows.
**Plans**: 3 plans

Plans:
- [ ] 01-01: Define persisted active-run draft model and storage lifecycle
- [ ] 01-02: Refactor `RunTracker` bootstrap and resume APIs around draft state
- [ ] 01-03: Move Live Activity attributes into shared app/widget source

### Phase 2: Recovery and Reconciliation UX
**Goal**: Detect interrupted sessions and orphaned Live Activities on launch or foreground entry, then guide the user to resume, save, or discard them from the Runs surface.
**Depends on**: Phase 1
**Requirements**: [TRK-04, LIV-01, LIV-03, SAV-01, SAV-04]
**Success Criteria** (what must be TRUE):
  1. User sees a clear interrupted-run banner after relaunch instead of losing access to the workout.
  2. App reconciles orphaned Live Activities with persisted draft state on launch and foreground entry.
  3. User can resume tracking or explicitly choose save/discard before starting another run.
  4. Live Activity presence matches whether there is an active or recoverable run.
**Plans**: 3 plans

Plans:
- [ ] 02-01: Add app launch and foreground reconciliation for active drafts and Live Activities
- [ ] 02-02: Build Runs-tab recovery banner and resume/save/discard entry points
- [ ] 02-03: Enforce single-active-run guardrails across tracker entry points

### Phase 3: Save and Cleanup Hardening
**Goal**: Make save and discard flows authoritative locally and guarantee Live Activity cleanup even when post-save sync or route export fails.
**Depends on**: Phase 2
**Requirements**: [LIV-02, SAV-02, SAV-03]
**Success Criteria** (what must be TRUE):
  1. User no longer sees a Live Activity after saving or discarding, including when the app was previously terminated.
  2. Local `RunningSession` persistence succeeds independently from HealthKit follow-up work.
  3. User gets actionable feedback when HealthKit or route sync fails after local save.
  4. Discarded or unrecoverable drafts are fully cleaned up from local state and activity surfaces.
**Plans**: 3 plans

Plans:
- [ ] 03-01: Separate local save and discard state transitions from asynchronous HealthKit work
- [ ] 03-02: Add durable Live Activity cleanup and orphan handling paths
- [ ] 03-03: Surface recovery and post-save failure states with user-facing messaging

### Phase 4: Regression Protection and Device Validation
**Goal**: Protect the run-lifecycle fix with automated coverage, logging, and a manual validation checklist for real devices.
**Depends on**: Phase 3
**Requirements**: [QA-01, QA-02]
**Success Criteria** (what must be TRUE):
  1. Automated tests cover draft persistence, single-active-run guards, and launch reconciliation behavior.
  2. Manual validation covers backgrounding, force-quit, relaunch, resume, save, discard, and orphan cleanup on device.
  3. Verification artifacts make future run-tracking changes auditable before release.
**Plans**: 2 plans

Plans:
- [ ] 04-01: Add lifecycle-focused tests and test seams for run recovery state
- [ ] 04-02: Create device validation checklist and logging hooks for Live Activity verification

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Durable Run Draft Foundation | 0/3 | Not started | - |
| 2. Recovery and Reconciliation UX | 0/3 | Not started | - |
| 3. Save and Cleanup Hardening | 0/3 | Not started | - |
| 4. Regression Protection and Device Validation | 0/2 | Not started | - |
