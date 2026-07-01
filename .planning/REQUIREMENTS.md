# Requirements: Pace & Plates

**Defined:** 2026-04-14
**Core Value:** Users can trust Pace & Plates to capture and preserve real workout progress without losing an in-flight session.

## v1 Requirements

### Tracking State

- [ ] **TRK-01**: User can reopen the app after an interruption and recover the current run with elapsed time, distance, and activity type intact.
- [ ] **TRK-02**: User can recover recorded route samples for an interrupted run when a local draft exists.
- [ ] **TRK-03**: User can have at most one active or recoverable run draft at a time.
- [ ] **TRK-04**: User can see whether a pending run is actively recording or awaiting recovery before opening the tracker.

### Live Activity Lifecycle

- [ ] **LIV-01**: User sees a Live Activity only while a corresponding active or recoverable run exists.
- [ ] **LIV-02**: User no longer sees the Live Activity after saving or discarding the run, even if the app was relaunched in between.
- [ ] **LIV-03**: App reconciles orphaned Live Activities on launch or foreground entry without requiring manual force-close/reopen cycles.
- [ ] **LIV-04**: Live Activity attributes are defined once and shared across app and widget targets so updates remain compatible.

### Save and Recovery UX

- [ ] **SAV-01**: User can resume, save, or discard an interrupted run from the Runs surface after relaunch.
- [ ] **SAV-02**: User keeps a locally saved `RunningSession` even if HealthKit workout or route sync fails afterward.
- [ ] **SAV-03**: User sees actionable messaging when post-save sync fails or when a recoverable run cannot be restored cleanly.
- [ ] **SAV-04**: User cannot accidentally start a new run while a recoverable run still needs action.

### Verification

- [ ] **QA-01**: Automated coverage verifies draft persistence, duplicate-active-run guards, and lifecycle reconciliation logic.
- [ ] **QA-02**: Manual device validation verifies Live Activity start/update/end behavior across backgrounding, force-quit, relaunch, save, and discard flows.

## v2 Requirements

### Recovery Enhancements

- **REC-01**: App checkpoints in-progress run state periodically while tracking in the background.
- **REC-02**: User can recover an interrupted run after device reboot, not just app relaunch.

### Observability

- **OBS-01**: Support diagnostics explain why a run draft could not be recovered or why a Live Activity was cleaned up.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New activity types beyond the current run/walk/hike tracking scope | Not required to solve the reported bug |
| Full Runs feature rewrite | Too broad for a reliability milestone |
| Live Activity visual redesign | Behavior correctness is the current priority |
| Cross-device recovery of active runs | Requires broader sync design beyond this milestone |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| TRK-01 | Phase 1 | Pending |
| TRK-02 | Phase 1 | Pending |
| TRK-03 | Phase 1 | Pending |
| LIV-04 | Phase 1 | Pending |
| TRK-04 | Phase 2 | Pending |
| LIV-01 | Phase 2 | Pending |
| LIV-03 | Phase 2 | Pending |
| SAV-01 | Phase 2 | Pending |
| SAV-04 | Phase 2 | Pending |
| LIV-02 | Phase 3 | Pending |
| SAV-02 | Phase 3 | Pending |
| SAV-03 | Phase 3 | Pending |
| QA-01 | Phase 4 | Pending |
| QA-02 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-04-14*
*Last updated: 2026-04-14 after initial definition*
