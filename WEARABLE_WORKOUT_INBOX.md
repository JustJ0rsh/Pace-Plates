# Wearable Workout Inbox

## Overview

Non-cardio workouts recorded on an Apple Watch or other wearable (strength,
functional strength, HIIT, core, cross-training, yoga, pilates, flexibility,
martial arts) now flow into a **Workout Inbox** in the Workouts tab. The user
triages each imported workout, choosing one of three actions:

- **Link** it to an existing logged gym session, attaching the watch metrics
  (duration, calories, average heart rate, source) to that session.
- **Create Workout** — turn the wearable activity into a brand-new workout
  session, then open it in the detail view to add exercises.
- **Dismiss** it, hiding it from the inbox permanently.

Cardio activities (running, walking, cycling, hiking, rowing, elliptical,
stair climbing) are unaffected: they continue to auto-import as runs via the
existing cardio pipeline. The inbox handles only the strength/functional
activity types that don't map cleanly onto a run.

---

## User Flow

1. **Record a workout on your watch** (e.g. a strength session). After it
   syncs to Apple Health, the next inbox sync surfaces it.
2. **Open the inbox.** From the Workouts tab, tap the tray icon in the
   toolbar. A badge shows the number of pending items.
3. **Review the item.** Each row shows the activity name and icon, the
   start date/time, the recording source (e.g. "Apple Watch"), and the
   available metrics (duration, kcal, avg bpm).
4. **Triage:**
   - **Create Workout** → a new `WorkoutSession` is created from the activity
     and immediately opened in `WorkoutSessionDetailView` so exercises can be
     added. The watch metrics are attached.
   - **Link…** → a picker lists nearby logged sessions. Selecting one attaches
     the watch metrics to it and marks the inbox item linked.
   - **Dismiss** → the item is marked dismissed and removed from the list.
5. **See attached metrics.** Any session with linked wearable data shows a
   `WearableMetricsTile` in its detail view (watch source, activity, duration,
   calories, avg heart rate).

---

## Architecture

### Models

**`HealthWorkoutInboxItem`** (`WorkingOut/Models/HealthWorkoutInboxItem.swift`)

A new `@Model` representing one wearable workout awaiting triage:

| Field | Type | Notes |
| --- | --- | --- |
| `id` | `UUID` | Local identity |
| `healthWorkoutUUID` | `String` | `HKWorkout.uuid` string; prevents re-import and enables deletion sync |
| `startDate` / `endDate` | `Date` | Activity bounds |
| `activityType` | `String` | Raw activity key, e.g. `"traditionalStrengthTraining"` |
| `duration` | `TimeInterval` | Recorded duration |
| `calories` | `Double?` | Active energy (kcal), nil when zero/absent |
| `avgHeartRate` | `Double?` | Average heart rate (bpm), when available |
| `sourceName` | `String?` | Recording device/app, e.g. `"Apple Watch"` |
| `statusRaw` | `String` | Backing store for `status` |
| `linkedWorkoutSessionID` | `UUID?` | Set when linked/created |
| `createdAt` | `Date` | Insertion time |

`status` is a computed `Status` enum (`pending`, `linked`, `dismissed`)
projected over `statusRaw`. All stored properties have defaults so the model
is CloudKit-compatible.

**`WorkoutSession`** (`WorkingOut/Models/WorkoutSession.swift`) — new optional
fields hold the metrics copied from a linked inbox item:

- `healthWorkoutUUID: String?`
- `healthDuration: TimeInterval?`
- `healthCalories: Double?`
- `healthAvgHeartRate: Double?`
- `healthSourceName: String?`
- `healthActivityType: String?`

A non-empty `healthWorkoutUUID` marks a session as already linked, which both
the sync dedupe and the link picker use to avoid double-linking.

### Service

**`WearableWorkoutInboxService`**
(`WorkingOut/Services/WearableWorkoutInboxService.swift`) — a `@MainActor enum`
of static functions:

- **`sync(context:)`** → `Int` — pulls new/deleted wearable workouts from
  Health and reconciles the inbox. Returns the number of newly inserted items.
- **`link(_:to:context:)`** → `Bool` — copies the item's metrics onto an
  existing session, sets the item's status to `linked`, and records the
  session id.
- **`createSession(from:context:)`** → `WorkoutSession?` — creates a session
  titled after the activity, attaches the metrics, links the item, and returns
  the new session (or nil if the save fails).
- **`dismiss(_:context:)`** — sets the item's status to `dismissed`.
- **Activity mapping** — `activityKey(for:)`, `activityDisplayName(for:)`, and
  `activityIcon(for:)` translate between `HKWorkoutActivityType`, the raw key,
  a human-readable name, and an SF Symbol. Unrecognized types map to `"other"`
  / "Workout".

Metric attachment and clearing are centralized in the private helpers
`applyMetrics(from:to:)` and `clearHealthLink(on:)`.

### HealthKit layer

**`HealthKitManager`** (`WorkingOut/Services/HealthKitManager.swift`)

- **`supportedStrengthTypes`** — the `Set<HKWorkoutActivityType>` routed to the
  inbox: traditional/functional strength training, HIIT, core, cross-training,
  yoga, pilates, flexibility, martial arts. (Cardio types live in a separate
  set and continue to import as runs.)
- **`fetchStrengthWorkoutChanges(since:resetAnchor:limit:)`** — runs an
  `HKAnchoredObjectQuery` over `HKObjectType.workoutType()`, predicated on the
  supported strength types AND `startDate >= since`. Returns a
  `CardioWorkoutChanges` struct (reused type) carrying `added` workouts,
  `deletedUUIDs`, and the new anchor.
- **Separate anchor** — the strength query uses its own anchor persisted under
  `UserDefaults` key `"healthKit.strengthWorkoutAnchor"`, independent of the
  cardio anchor. `persistStrengthWorkoutAnchor(_:)` stores it.

### UI

- **`WorkoutLogView`** (`WorkingOut/Features/Workouts/WorkoutLogView.swift`) —
  adds a badged tray toolbar item (`tray.fill`) that opens the inbox. The badge
  count comes from a `@Query` of pending `HealthWorkoutInboxItem`s (capped at 99
  in the label, with an accessibility label announcing the pending count). Sync
  runs on `.task` and again whenever a `.healthKitWorkoutsDidChange`
  notification arrives.
- **`WearableInboxView`** (`WorkingOut/Features/Workouts/WearableInboxView.swift`)
  — the inbox list. It queries pending items sorted newest-first and syncs on
  `.task` and pull-to-refresh. Rows expose Create / Link / Dismiss. The link
  picker (`WearableLinkPickerView`) lists **unlinked** sessions within ±7 days
  of the activity, sorted by proximity, tagging same-day matches with a
  "Same day" badge; if none are nearby it falls back to the 20 most recent
  unlinked sessions. "Create Workout" pushes the new session into
  `WorkoutSessionDetailView`.
- **`WearableMetricsTile`**
  (`WorkingOut/Features/Workouts/WorkoutSessionSubviews.swift`) — rendered in a
  workout's detail view when the session carries linked wearable data.

### Persistence

`HealthWorkoutInboxItem.self` is registered in the SwiftData `Schema` in
`WorkingOut/Data/PersistenceController.swift`, so inbox items participate in
local persistence and (when enabled) CloudKit sync like every other model.

---

## Data Lifecycle

### Statuses

An inbox item moves through three states:

- **`pending`** — imported, awaiting triage. Only pending items appear in the
  inbox list and contribute to the toolbar badge.
- **`linked`** — the user linked it to (or created) a session. The item leaves
  the inbox but is retained so its `healthWorkoutUUID` continues to block
  re-import.
- **`dismissed`** — the user dismissed it. It leaves the inbox and stays
  retained for the same dedupe reason. Dismissal is permanent — there is no
  in-app "undo" or un-dismiss.

### First-scan cutoff

On the very first sync the service computes a lower bound of **30 days before
now** and stores it in `UserDefaults` under `"wearableInbox.firstScanDate"`.
Every subsequent sync reuses that stored value as the fixed `since:` bound for
the Health query. This prevents an initial install from flooding the inbox with
the user's entire watch history while still allowing recent workouts to surface.

### Anchored query & dedupe

Sync uses an `HKAnchoredObjectQuery`, so after the first run it receives only
incremental changes (new and deleted workouts) rather than re-scanning
everything. Newly added workouts are still deduped defensively:

- against existing `HealthWorkoutInboxItem`s (by `healthWorkoutUUID`), and
- against `WorkoutSession`s that already carry that `healthWorkoutUUID` (a
  workout that was linked before its inbox row existed, or whose row was
  removed).

Calories/heart rate are fetched per workout and stored as `nil` when zero or
unavailable.

### Deletion sync

When a workout is deleted from Apple Health, the anchored query reports its UUID
in `deletedUUIDs`. The service then:

- deletes any matching inbox item (in **any** status), and
- clears the health-link fields on any `WorkoutSession` that pointed at it
  (via `clearHealthLink`), leaving the manually logged session intact but
  detached from the now-gone Health record.

### Anchor persistence ordering

The new anchor is persisted **only after** the SwiftData save succeeds
(`PersistenceSave.commit` returns true). If the save fails, the anchor is not
advanced, so the next sync re-fetches the same changes and retries. A transient
Health fetch failure likewise leaves the anchor untouched.

Sync is also skipped entirely when Health data is unavailable or when
`AppLaunchConfiguration.current.shouldSkipAutomationSideEffects` is set (e.g.
UI-test launches).

---

## Edge Cases

- **Already-linked UUIDs.** A workout whose UUID is already attached to a
  session is never re-added to the inbox, even if its inbox row was removed.
- **Health deletions.** Removing the workout in Health cascades: the inbox row
  is deleted and any linked session is unlinked (its own data preserved).
- **Dismissal permanence.** Dismissed items remain in the store (to keep
  deduping) but never reappear in the UI; there is no un-dismiss path.
- **No nearby sessions to link.** The link picker falls back to the 20 most
  recent unlinked sessions, and shows an empty state prompting the user to log
  a workout or use Create Workout if there are none.
- **Save failure on create.** If persisting the new session fails,
  `createSession` returns nil and no navigation occurs; the item stays pending.

---

## Known Limitations

- **Backup export gap.** `DataBackupService`'s `WorkoutSessionDTO` currently
  serializes only `id`, `date`, `notes`, and `title`. The new `health*` fields
  on `WorkoutSession` are **not** included in the JSON backup/export, so linked
  wearable metrics do not round-trip through export/import. `HealthWorkoutInboxItem`
  is likewise not part of the backup file. (Both are recovered on-device from
  Health on the next sync, but a restore onto a fresh device without Health
  access would lose the attached metrics.)
- **Sync surface.** `HealthWorkoutInboxItem`s are device-local and, when iCloud
  is enabled, sync across the user's devices through SwiftData/CloudKit like
  other models — but the source of truth for import is each device's local
  HealthKit store and its own anchor.
- **First-scan window is fixed.** The 30-day initial lookback is not
  user-configurable; workouts older than the first-scan date are never imported.
