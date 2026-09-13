# Coach storage and rollout boundary

The existing `PersistenceController` opens one SwiftData schema with automatic CloudKit and a local fallback. The schema includes workouts/sets, routes/runs, weight, AI conversations, plans, templates, and Health inbox records. `UserProfileStore` separately uses Keychain. Existing run recovery and preferences have separate storage. The old configuration remains the default until the user explicitly chooses local ownership.

Coach's new personal records require the `CoachLocal` configuration, with CloudKit `.none`. Its store, progress-photo assets, and staging files live in protected Application Support directories excluded from automatic backup. This is not a claim that the existing cloud history has been removed or that release privacy acceptance is complete.

The first-use review describes the effect before the switch: copy this device's existing records; verify all entity identities; use the local copy across every tab; stop sending subsequent app record edits from this device to the legacy CloudKit store. Other devices do not receive these subsequent edits. Deliberate history exports become the user's transfer/recovery mechanism. Original Apple Health and Photos library data are independent.

The migration uses SQLite's read-only backup API to include committed WAL content and preserve every historical database field and relationship, including fields outside portable backup DTOs. It opens the copied store with the current schema and CloudKit disabled, checks identities, then atomically writes a selected-store marker. Before this marker, interruption leaves the old store selected; afterward, restart opens the local store. A failed selected-store open must show an error instead of silently falling back to stale history. The original database files remain available for recovery and no remote records are deleted. Never switch during an active run.

Migration validation uses disposable on-disk stores. Required release checks include relationship/value preservation, source and destination identity equality, WAL content, interruption before/after selection, failure recovery, file protection, automatic-backup exclusion, and real-device CloudKit behavior. A simulator copy alone does not prove the final device/cloud boundary.

The app's first-use choice authorizes its own copy/switch. Implementation work does not authorize running it against Joshua's live history, installing on a physical device, deleting the legacy store, or deleting remote records.

Primary references: [Apple's health-data review guideline](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research), [backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup).
