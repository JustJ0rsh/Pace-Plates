import Foundation
import SwiftData
import HealthKit

/// Syncs non-cardio wearable workouts (strength, HIIT, yoga, …) from Apple Health
/// into an inbox where the user links them to a logged workout, creates a new
/// workout from them, or dismisses them.
@MainActor
enum WearableWorkoutInboxService {
    private static let firstScanDateKey = "wearableInbox.firstScanDate"
    private static let localPurgeCutoffDateKey = "wearableInbox.localPurgeCutoffDate"
    private static let initialLookbackDays = 30
    private static let fingerprintDateTolerance: TimeInterval = 120
    private static let fingerprintDurationTolerance: TimeInterval = 120
    private static let crossSourceDateTolerance: TimeInterval = 30
    private static let crossSourceDurationTolerance: TimeInterval = 60
    private static let replacementGracePeriod: TimeInterval = 24 * 60 * 60
    private static var syncInProgress = false
    private static var syncRequestedWhileRunning = false
    private static var localPurgeGeneration = 0

    struct ImportedWorkout {
        let healthWorkoutUUID: String
        let startDate: Date
        let endDate: Date
        let activityType: String
        let duration: TimeInterval
        let calories: Double?
        let avgHeartRate: Double?
        let sourceName: String?
        let sourceBundleIdentifier: String?
        let healthSyncIdentifier: String?
        let healthSyncVersion: Int?
        let healthExternalUUID: String?
    }

    private struct ReconciliationResult {
        let inserted: Int
        let didCommit: Bool
    }

    /// Invalidates a suspended sync before an app-local purge. This only
    /// coordinates SwiftData work; it never changes Apple Health.
    static func prepareForLocalDataPurge() {
        localPurgeGeneration &+= 1
        syncRequestedWhileRunning = false
    }

    /// Shared generation used by every Health-to-SwiftData import path. A task
    /// must stop before mutating or advancing an anchor if this value changes.
    static var localDataPurgeGeneration: Int {
        localPurgeGeneration
    }

    static func isCurrentLocalDataPurgeGeneration(_ generation: Int) -> Bool {
        generation == localPurgeGeneration
    }

    /// Records the successful purge boundary so a stale anchored-query batch
    /// cannot replay workouts that the user just removed from app storage.
    static func completeLocalDataPurge(at date: Date = Date()) {
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: localPurgeCutoffDateKey
        )
    }

    /// Successful app-local purge boundary shared by unanchored Health imports.
    /// Samples at or before this date stay in Apple Health but are not silently
    /// recreated in Pace & Plates after Delete All.
    static var localDataPurgeCutoffDate: Date? {
        let timestamp = UserDefaults.standard.double(
            forKey: localPurgeCutoffDateKey
        )
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    /// Fixed lower bound for the Health query, set 30 days back on first sync.
    private static func scanCutoffDate() -> Date {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: firstScanDateKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -initialLookbackDays, to: Date()) ?? Date()
        defaults.set(cutoff.timeIntervalSince1970, forKey: firstScanDateKey)
        return cutoff
    }

    /// Pulls new/deleted wearable workouts from Health and updates inbox items.
    /// Returns the number of newly added inbox items.
    @discardableResult
    static func sync(context: ModelContext) async -> Int {
        guard !syncInProgress else {
            // Coalesce observer/UI triggers instead of dropping a Health update
            // that may have arrived after the active anchored query snapshot.
            syncRequestedWhileRunning = true
            return 0
        }

        syncInProgress = true
        let expectedPurgeGeneration = localPurgeGeneration
        defer {
            syncInProgress = false
            syncRequestedWhileRunning = false
        }

        // Repair duplicate rows already created by older builds before touching
        // HealthKit. This also runs in UI-test mode and never changes Health data.
        _ = repairLocalDuplicateInboxItems(context: context)
        guard expectedPurgeGeneration == localPurgeGeneration else { return 0 }

        guard HKHealthStore.isHealthDataAvailable() else { return 0 }
        guard !AppLaunchConfiguration.current.shouldSkipAutomationSideEffects else { return 0 }

        var totalInserted = 0
        repeat {
            syncRequestedWhileRunning = false
            totalInserted += await performSingleSync(
                context: context,
                expectedPurgeGeneration: expectedPurgeGeneration
            )
        } while syncRequestedWhileRunning &&
                expectedPurgeGeneration == localPurgeGeneration

        return totalInserted
    }

    private static func performSingleSync(
        context: ModelContext,
        expectedPurgeGeneration: Int
    ) async -> Int {
        let changes: HealthKitManager.CardioWorkoutChanges
        do {
            changes = try await HealthKitManager.shared.fetchStrengthWorkoutChanges(since: scanCutoffDate())
        } catch {
            // Transient fetch failure: anchor not advanced, next sync retries.
            return 0
        }
        guard expectedPurgeGeneration == localPurgeGeneration else { return 0 }

        let deletedSet = Set(changes.deletedUUIDs)
        let purgeCutoff = localDataPurgeCutoffDate
        var importedWorkouts: [ImportedWorkout] = []
        for workout in changes.added
        where !deletedSet.contains(workout.uuid.uuidString) &&
            (purgeCutoff.map { workout.endDate > $0 } ?? true) {
            let calorieValue = try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout)
            guard expectedPurgeGeneration == localPurgeGeneration else { return 0 }
            let heartRate = try? await HealthKitManager.shared.averageHeartRate(for: workout)
            guard expectedPurgeGeneration == localPurgeGeneration else { return 0 }

            importedWorkouts.append(
                importedWorkout(
                    from: workout,
                    calories: (calorieValue ?? 0) > 0 ? calorieValue : nil,
                    avgHeartRate: heartRate
                )
            )
        }

        guard expectedPurgeGeneration == localPurgeGeneration else { return 0 }
        let result = reconcile(
            importedWorkouts: importedWorkouts,
            deleted: changes.deleted,
            observedAt: Date(),
            context: context
        )
        if result.didCommit,
           expectedPurgeGeneration == localPurgeGeneration {
            HealthKitManager.shared.persistStrengthWorkoutAnchor(changes.newAnchor)
        }
        return result.didCommit ? result.inserted : 0
    }

    /// Applies already-read Health changes to SwiftData. Keeping reconciliation
    /// independent from Health queries makes replacement behavior deterministic
    /// and testable without writing to Apple Health.
    private static func reconcile(
        importedWorkouts: [ImportedWorkout],
        deleted: [HealthKitManager.CardioWorkoutChanges.DeletedWorkout],
        observedAt: Date,
        context: ModelContext
    ) -> ReconciliationResult {
        let existingItems: [HealthWorkoutInboxItem]
        let sessions: [WorkoutSession]
        do {
            existingItems = try context.fetch(FetchDescriptor<HealthWorkoutInboxItem>())
            sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        } catch {
            // Never advance the anchor when local identity cannot be read.
            return ReconciliationResult(inserted: 0, didCommit: false)
        }

        var allItems = existingItems
        var itemsByUUID: [String: HealthWorkoutInboxItem] = [:]
        for item in existingItems {
            for uuid in knownHealthWorkoutUUIDs(for: item) {
                itemsByUUID[uuid] = item
            }
        }

        let linkedSessionUUIDs = Set(
            sessions.compactMap(\.healthWorkoutUUID).filter { !$0.isEmpty }
        )
        let deletedSet = Set(deleted.map(\.uuid))

        // Older rows did not persist sync metadata. Deleted objects retain the
        // sync identifier/version, so backfill it before matching a replacement.
        var deletionOwnersBySyncIdentifier: [String: [HealthWorkoutInboxItem]] = [:]
        for deletedWorkout in deleted {
            guard let item = itemsByUUID[deletedWorkout.uuid] else { continue }
            let itemIsSourceLess = sourceIdentity(
                bundle: item.sourceBundleIdentifier,
                name: item.sourceName
            ).isEmpty
            let deletionBelongsToCanonicalIdentity =
                deletedWorkout.uuid == item.healthWorkoutUUID
            guard itemIsSourceLess || deletionBelongsToCanonicalIdentity,
                  let syncIdentifier = normalizedString(
                    deletedWorkout.syncIdentifier
                  ) else {
                // Aliases can intentionally span sources, while a deleted
                // Health object does not retain its source. Never splice or
                // index an alias's metadata as the canonical source tuple.
                continue
            }

            let itemSyncIdentifier = normalizedString(
                item.healthSyncIdentifier
            )
            guard itemSyncIdentifier == nil ||
                    itemSyncIdentifier == syncIdentifier else {
                continue
            }

            if itemSyncIdentifier == nil {
                item.healthSyncIdentifier = syncIdentifier
                item.healthSyncVersion = deletedWorkout.syncVersion
            } else if let deletedVersion = deletedWorkout.syncVersion {
                item.healthSyncVersion = max(
                    item.healthSyncVersion ?? deletedVersion,
                    deletedVersion
                )
            }

            var owners = deletionOwnersBySyncIdentifier[syncIdentifier] ?? []
            if !owners.contains(where: { $0 === item }) {
                owners.append(item)
            }
            deletionOwnersBySyncIdentifier[syncIdentifier] = owners
        }

        var inserted = 0
        for candidate in importedWorkouts
            where !deletedSet.contains(candidate.healthWorkoutUUID) {
            let deletionOwner: HealthWorkoutInboxItem? = {
                guard let syncIdentifier = normalizedString(candidate.healthSyncIdentifier),
                      let owners = deletionOwnersBySyncIdentifier[syncIdentifier],
                      !owners.isEmpty else {
                    return nil
                }

                let candidateSource = sourceIdentity(
                    bundle: candidate.sourceBundleIdentifier,
                    name: candidate.sourceName
                )
                let matchingSourceOwners = owners.filter {
                    guard !candidateSource.isEmpty else { return false }
                    return sourceIdentity(
                        bundle: $0.sourceBundleIdentifier,
                        name: $0.sourceName
                    ) == candidateSource
                }
                if matchingSourceOwners.count == 1 {
                    return matchingSourceOwners[0]
                }

                let legacyFingerprintOwners = owners.filter {
                    return sourceIdentity(
                        bundle: $0.sourceBundleIdentifier,
                        name: $0.sourceName
                    ).isEmpty &&
                    sameStrictWorkoutFingerprint($0, candidate)
                }
                return legacyFingerprintOwners.count == 1
                    ? legacyFingerprintOwners[0]
                    : nil
            }()

            let matchingItem = itemsByUUID[candidate.healthWorkoutUUID] ??
                deletionOwner ??
                allItems.first(where: { sameLogicalWorkout($0, candidate) })

            if matchingItem == nil,
               linkedSessionUUIDs.contains(candidate.healthWorkoutUUID) {
                continue
            }

            if let matchingItem {
                let matchedDeletionOwner = deletionOwner === matchingItem
                let matchedSourceLessDeletionOwner =
                    matchedDeletionOwner &&
                    sourceIdentity(
                        bundle: matchingItem.sourceBundleIdentifier,
                        name: matchingItem.sourceName
                    ).isEmpty
                if isLowerSyncVersion(
                    candidate,
                    than: matchingItem,
                    validatedSourceLessIdentity: matchedSourceLessDeletionOwner
                ) {
                    // A stale replacement must not displace the newer local
                    // identity or resurrect a retired Health UUID.
                    continue
                }

                let wasAwaitingReplacement =
                    matchingItem.healthDeletionObservedAt != nil
                let preferCandidateDetails = shouldPreferCandidateDetails(
                    candidate,
                    over: matchingItem,
                    matchedDeletionOwner:
                        matchedDeletionOwner ||
                        wasAwaitingReplacement
                )
                if wasAwaitingReplacement {
                    // Every known UUID on a deletion-only tombstone was retired.
                    // Do not carry one forward as a live alias.
                    setKnownHealthWorkoutUUIDs(
                        [candidate.healthWorkoutUUID],
                        on: matchingItem,
                        preferredPrimary: candidate.healthWorkoutUUID
                    )
                }
                merge(
                    candidate,
                    into: matchingItem,
                    preferCandidateDetails: preferCandidateDetails
                )
                matchingItem.healthDeletionObservedAt = nil
                updateLinkedSession(for: matchingItem, sessions: sessions)
                for uuid in knownHealthWorkoutUUIDs(for: matchingItem) {
                    itemsByUUID[uuid] = matchingItem
                }
                continue
            }

            let item = HealthWorkoutInboxItem(
                healthWorkoutUUID: candidate.healthWorkoutUUID,
                startDate: candidate.startDate,
                endDate: candidate.endDate,
                activityType: candidate.activityType,
                duration: candidate.duration,
                calories: candidate.calories,
                avgHeartRate: candidate.avgHeartRate,
                sourceName: candidate.sourceName,
                sourceBundleIdentifier: candidate.sourceBundleIdentifier,
                healthSyncIdentifier: candidate.healthSyncIdentifier,
                healthSyncVersion: candidate.healthSyncVersion,
                healthExternalUUID: candidate.healthExternalUUID
            )
            context.insert(item)
            allItems.append(item)
            itemsByUUID[candidate.healthWorkoutUUID] = item
            inserted += 1
        }

        // Reconcile deletions after additions. Same-batch replacements promote
        // the new UUID immediately. Deletion-only batches retain a hidden local
        // tombstone for a grace period so a later replacement keeps its state.
        var replacementItemsByDeletedUUID: [String: HealthWorkoutInboxItem] = [:]
        if !deletedSet.isEmpty {
            for item in allItems {
                let before = knownHealthWorkoutUUIDs(for: item)
                let removed = before.intersection(deletedSet)
                guard !removed.isEmpty else { continue }

                let remaining = before.subtracting(deletedSet)
                guard !remaining.isEmpty else {
                    if item.healthDeletionObservedAt == nil {
                        item.healthDeletionObservedAt = observedAt
                    }
                    continue
                }

                setKnownHealthWorkoutUUIDs(
                    remaining,
                    on: item,
                    preferredPrimary: remaining.contains(item.healthWorkoutUUID)
                        ? item.healthWorkoutUUID
                        : nil
                )
                item.healthDeletionObservedAt = nil
                for deletedUUID in removed {
                    replacementItemsByDeletedUUID[deletedUUID] = item
                }
                updateLinkedSession(for: item, sessions: sessions)
            }

            for session in sessions {
                guard let uuid = session.healthWorkoutUUID,
                      deletedSet.contains(uuid) else { continue }

                if let replacement = replacementItemsByDeletedUUID[uuid] {
                    applyMetrics(from: replacement, to: session)
                }
            }
        }

        let expirationCutoff = observedAt.addingTimeInterval(-replacementGracePeriod)
        for item in allItems {
            guard let deletionDate = item.healthDeletionObservedAt,
                  deletionDate <= expirationCutoff else {
                continue
            }

            let knownUUIDs = knownHealthWorkoutUUIDs(for: item)
            for session in sessions where
                session.id == item.linkedWorkoutSessionID ||
                (session.healthWorkoutUUID.map(knownUUIDs.contains) ?? false) {
                clearHealthLink(on: session)
            }
            context.delete(item)
        }

        let didCommit = PersistenceSave.commit(context, action: "sync wearable inbox")
        return ReconciliationResult(
            inserted: didCommit ? inserted : 0,
            didCommit: didCommit
        )
    }

    #if DEBUG
    /// Exercises the same value-type reconciliation used by live Health queries.
    /// Intended only for deterministic UI-test fixtures.
    @discardableResult
    static func reconcileForUITesting(
        importedWorkouts: [ImportedWorkout],
        deleted: [HealthKitManager.CardioWorkoutChanges.DeletedWorkout],
        observedAt: Date,
        context: ModelContext
    ) -> Bool {
        reconcile(
            importedWorkouts: importedWorkouts,
            deleted: deleted,
            observedAt: observedAt,
            context: context
        ).didCommit
    }
    #endif

    /// Consolidates duplicate app-local inbox rows left by older re-entrant
    /// syncs or strict Oura replacement matches. No HealthKit mutation occurs.
    @discardableResult
    private static func repairLocalDuplicateInboxItems(context: ModelContext) -> Int {
        let items: [HealthWorkoutInboxItem]
        let sessions: [WorkoutSession]
        do {
            items = try context.fetch(FetchDescriptor<HealthWorkoutInboxItem>())
            sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        } catch {
            return 0
        }

        let sortedItems = items.sorted {
            let leftScore = canonicalScore($0)
            let rightScore = canonicalScore($1)
            if leftScore != rightScore { return leftScore > rightScore }
            return $0.createdAt < $1.createdAt
        }

        var canonicalItems: [HealthWorkoutInboxItem] = []
        var removedCount = 0

        for item in sortedItems {
            guard let canonical = canonicalItems.first(where: {
                canConsolidate($0, with: item)
            }) else {
                canonicalItems.append(item)
                continue
            }

            merge(item, into: canonical)
            updateLinkedSession(for: canonical, sessions: sessions)
            context.delete(item)
            removedCount += 1
        }

        guard removedCount > 0 else { return 0 }
        return PersistenceSave.commit(context, action: "repair wearable inbox duplicates")
            ? removedCount
            : 0
    }

    private static func importedWorkout(
        from workout: HKWorkout,
        calories: Double?,
        avgHeartRate: Double?
    ) -> ImportedWorkout {
        let metadata = workout.metadata
        return ImportedWorkout(
            healthWorkoutUUID: workout.uuid.uuidString,
            startDate: workout.startDate,
            endDate: workout.endDate,
            activityType: activityKey(for: workout.workoutActivityType),
            duration: workout.duration,
            calories: calories,
            avgHeartRate: avgHeartRate,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
            healthSyncIdentifier: normalizedMetadataString(
                metadata?[HKMetadataKeySyncIdentifier]
            ),
            healthSyncVersion: metadataInt(metadata?[HKMetadataKeySyncVersion]),
            healthExternalUUID: normalizedMetadataString(
                metadata?[HKMetadataKeyExternalUUID]
            )
        )
    }

    private static func normalizedMetadataString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return normalizedString(string)
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func metadataInt(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private static func knownHealthWorkoutUUIDs(
        for item: HealthWorkoutInboxItem
    ) -> Set<String> {
        var identifiers = Set(
            item.alternateHealthWorkoutUUIDsRaw
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        if !item.healthWorkoutUUID.isEmpty {
            identifiers.insert(item.healthWorkoutUUID)
        }
        return identifiers
    }

    private static func setKnownHealthWorkoutUUIDs(
        _ identifiers: Set<String>,
        on item: HealthWorkoutInboxItem,
        preferredPrimary: String? = nil
    ) {
        let cleaned = Set(identifiers.filter { !$0.isEmpty })
        guard !cleaned.isEmpty else {
            item.healthWorkoutUUID = ""
            item.alternateHealthWorkoutUUIDsRaw = ""
            return
        }

        let primary: String
        if let preferredPrimary, cleaned.contains(preferredPrimary) {
            primary = preferredPrimary
        } else if cleaned.contains(item.healthWorkoutUUID) {
            primary = item.healthWorkoutUUID
        } else {
            primary = cleaned.sorted().first!
        }

        item.healthWorkoutUUID = primary
        item.alternateHealthWorkoutUUIDsRaw = cleaned
            .subtracting([primary])
            .sorted()
            .joined(separator: "\n")
    }

    private static func shouldPreferCandidateDetails(
        _ candidate: ImportedWorkout,
        over item: HealthWorkoutInboxItem,
        matchedDeletionOwner: Bool
    ) -> Bool {
        let itemSource = sourceIdentity(
            bundle: item.sourceBundleIdentifier,
            name: item.sourceName
        )
        let candidateSource = sourceIdentity(
            bundle: candidate.sourceBundleIdentifier,
            name: candidate.sourceName
        )
        let sameSource = !itemSource.isEmpty && itemSource == candidateSource
        let itemSyncIdentifier = normalizedString(item.healthSyncIdentifier)
        let candidateSyncIdentifier = normalizedString(candidate.healthSyncIdentifier)
        let sameSyncIdentifier =
            sameSource &&
            itemSyncIdentifier != nil &&
            itemSyncIdentifier == candidateSyncIdentifier
        let itemExternalUUID = normalizedString(item.healthExternalUUID)
        let candidateExternalUUID = normalizedString(candidate.healthExternalUUID)
        let sameExternalUUID =
            sameSource &&
            itemExternalUUID != nil &&
            itemExternalUUID == candidateExternalUUID

        if sameSyncIdentifier,
           let candidateVersion = candidate.healthSyncVersion,
           let itemVersion = item.healthSyncVersion,
           candidateVersion < itemVersion {
            return false
        }

        if matchedDeletionOwner { return true }

        if sameSyncIdentifier,
           let candidateVersion = candidate.healthSyncVersion,
           candidateVersion > (item.healthSyncVersion ?? Int.min) {
            return true
        }

        return !knownHealthWorkoutUUIDs(for: item)
            .contains(candidate.healthWorkoutUUID) &&
            (sameSyncIdentifier || sameExternalUUID)
    }

    private static func isLowerSyncVersion(
        _ candidate: ImportedWorkout,
        than item: HealthWorkoutInboxItem,
        validatedSourceLessIdentity: Bool
    ) -> Bool {
        let itemSource = sourceIdentity(
            bundle: item.sourceBundleIdentifier,
            name: item.sourceName
        )
        let candidateSource = sourceIdentity(
            bundle: candidate.sourceBundleIdentifier,
            name: candidate.sourceName
        )
        let hasComparableSourceIdentity =
            (!itemSource.isEmpty && itemSource == candidateSource) ||
            (validatedSourceLessIdentity && itemSource.isEmpty)
        guard hasComparableSourceIdentity,
              normalizedString(candidate.healthSyncIdentifier) ==
                normalizedString(item.healthSyncIdentifier),
              normalizedString(candidate.healthSyncIdentifier) != nil,
              let candidateVersion = candidate.healthSyncVersion,
              let itemVersion = item.healthSyncVersion else {
            return false
        }
        return candidateVersion < itemVersion
    }

    private static func adoptSourceIdentity(
        from candidate: ImportedWorkout,
        into item: HealthWorkoutInboxItem
    ) {
        item.sourceName = normalizedString(candidate.sourceName)
        item.sourceBundleIdentifier = normalizedString(
            candidate.sourceBundleIdentifier
        )
        item.healthSyncIdentifier = normalizedString(
            candidate.healthSyncIdentifier
        )
        item.healthSyncVersion = candidate.healthSyncVersion
        item.healthExternalUUID = normalizedString(
            candidate.healthExternalUUID
        )
    }

    private static func merge(
        _ candidate: ImportedWorkout,
        into item: HealthWorkoutInboxItem,
        preferCandidateDetails: Bool
    ) {
        var identifiers = knownHealthWorkoutUUIDs(for: item)
        identifiers.insert(candidate.healthWorkoutUUID)
        setKnownHealthWorkoutUUIDs(
            identifiers,
            on: item,
            preferredPrimary: preferCandidateDetails
                ? candidate.healthWorkoutUUID
                : item.healthWorkoutUUID
        )

        if preferCandidateDetails {
            let originalSourceIdentity = sourceIdentity(
                bundle: item.sourceBundleIdentifier,
                name: item.sourceName
            )
            let candidateSourceIdentity = sourceIdentity(
                bundle: candidate.sourceBundleIdentifier,
                name: candidate.sourceName
            )
            item.startDate = candidate.startDate
            item.endDate = candidate.endDate
            item.activityType = candidate.activityType
            item.duration = candidate.duration
            item.calories = candidate.calories ?? item.calories
            item.avgHeartRate = candidate.avgHeartRate ?? item.avgHeartRate

            if !candidateSourceIdentity.isEmpty,
               candidateSourceIdentity != originalSourceIdentity {
                adoptSourceIdentity(from: candidate, into: item)
            } else {
                item.sourceName =
                    normalizedString(candidate.sourceName) ?? item.sourceName
                item.sourceBundleIdentifier =
                    normalizedString(candidate.sourceBundleIdentifier) ??
                    item.sourceBundleIdentifier
                item.healthExternalUUID =
                    normalizedString(candidate.healthExternalUUID) ??
                    item.healthExternalUUID

                let itemSyncIdentifier = normalizedString(
                    item.healthSyncIdentifier
                )
                if let candidateSyncIdentifier = normalizedString(
                    candidate.healthSyncIdentifier
                ) {
                    item.healthSyncIdentifier = candidateSyncIdentifier
                    if candidateSyncIdentifier != itemSyncIdentifier {
                        item.healthSyncVersion = candidate.healthSyncVersion
                    } else if let candidateVersion =
                                candidate.healthSyncVersion {
                        item.healthSyncVersion = candidateVersion
                    }
                }
            }
            return
        }

        if item.calories == nil { item.calories = candidate.calories }
        if item.avgHeartRate == nil { item.avgHeartRate = candidate.avgHeartRate }

        // Cross-source duplicates often pair an Oura workout with an Apple Watch
        // copy that carries heart rate. Keep Oura's stable identity as the
        // canonical replacement identity while retaining the richer metrics.
        let originalSourceIdentity = sourceIdentity(
            bundle: item.sourceBundleIdentifier,
            name: item.sourceName
        )
        let candidateSourceIdentity = sourceIdentity(
            bundle: candidate.sourceBundleIdentifier,
            name: candidate.sourceName
        )
        let shouldAdoptOuraIdentity =
            !isOuraSource(
                bundle: item.sourceBundleIdentifier,
                name: item.sourceName
            ) &&
            isOuraSource(
                bundle: candidate.sourceBundleIdentifier,
                name: candidate.sourceName
            )

        let shouldAdoptCandidateIdentity =
            !candidateSourceIdentity.isEmpty &&
            (originalSourceIdentity.isEmpty || shouldAdoptOuraIdentity)
        if shouldAdoptCandidateIdentity {
            adoptSourceIdentity(from: candidate, into: item)
            return
        }

        guard !originalSourceIdentity.isEmpty,
              originalSourceIdentity == candidateSourceIdentity else {
            return
        }

        if item.sourceName?.isEmpty != false {
            item.sourceName = normalizedString(candidate.sourceName)
        }
        if item.sourceBundleIdentifier?.isEmpty != false {
            item.sourceBundleIdentifier = normalizedString(
                candidate.sourceBundleIdentifier
            )
        }

        let itemSyncIdentifier = normalizedString(item.healthSyncIdentifier)
        let candidateSyncIdentifier = normalizedString(
            candidate.healthSyncIdentifier
        )
        if itemSyncIdentifier == nil,
           let candidateSyncIdentifier {
            item.healthSyncIdentifier = candidateSyncIdentifier
            item.healthSyncVersion = candidate.healthSyncVersion
        } else if let candidateVersion = candidate.healthSyncVersion,
                  itemSyncIdentifier != nil,
                  itemSyncIdentifier == candidateSyncIdentifier {
            item.healthSyncVersion = max(item.healthSyncVersion ?? candidateVersion, candidateVersion)
        }
        if item.healthExternalUUID?.isEmpty != false {
            item.healthExternalUUID = normalizedString(
                candidate.healthExternalUUID
            )
        }
    }

    private static func merge(
        _ duplicate: HealthWorkoutInboxItem,
        into canonical: HealthWorkoutInboxItem
    ) {
        let canonicalDeletionDate = canonical.healthDeletionObservedAt
        let duplicateDeletionDate = duplicate.healthDeletionObservedAt
        let canonicalIsRetired = canonicalDeletionDate != nil
        let duplicateIsRetired = duplicateDeletionDate != nil
        let liveIdentifiers: Set<String>
        switch (canonicalIsRetired, duplicateIsRetired) {
        case (false, true):
            liveIdentifiers = knownHealthWorkoutUUIDs(for: canonical)
        case (true, false):
            liveIdentifiers = knownHealthWorkoutUUIDs(for: duplicate)
        default:
            liveIdentifiers = knownHealthWorkoutUUIDs(for: canonical)
                .union(knownHealthWorkoutUUIDs(for: duplicate))
        }

        let candidate = ImportedWorkout(
            healthWorkoutUUID:
                (!canonicalIsRetired && duplicateIsRetired)
                ? canonical.healthWorkoutUUID
                : duplicate.healthWorkoutUUID,
            startDate: duplicate.startDate,
            endDate: duplicate.endDate,
            activityType: duplicate.activityType,
            duration: duplicate.duration,
            calories: duplicate.calories,
            avgHeartRate: duplicate.avgHeartRate,
            sourceName: duplicate.sourceName,
            sourceBundleIdentifier: duplicate.sourceBundleIdentifier,
            healthSyncIdentifier: duplicate.healthSyncIdentifier,
            healthSyncVersion: duplicate.healthSyncVersion,
            healthExternalUUID: duplicate.healthExternalUUID
        )
        merge(
            candidate,
            into: canonical,
            preferCandidateDetails:
                canonicalIsRetired && !duplicateIsRetired
                ? true
                : (!duplicateIsRetired &&
                    shouldPreferCandidateDetails(
                        candidate,
                        over: canonical,
                        matchedDeletionOwner: false
                    ))
        )

        setKnownHealthWorkoutUUIDs(
            liveIdentifiers,
            on: canonical,
            preferredPrimary:
                canonicalIsRetired && !duplicateIsRetired
                ? duplicate.healthWorkoutUUID
                : canonical.healthWorkoutUUID
        )

        if canonicalDeletionDate == nil || duplicateDeletionDate == nil {
            canonical.healthDeletionObservedAt = nil
        } else {
            canonical.healthDeletionObservedAt = min(
                canonicalDeletionDate!,
                duplicateDeletionDate!
            )
        }

        if statusPriority(duplicate.status) > statusPriority(canonical.status) {
            canonical.status = duplicate.status
            canonical.linkedWorkoutSessionID = duplicate.linkedWorkoutSessionID
        } else if canonical.status == .linked,
                  canonical.linkedWorkoutSessionID == nil {
            canonical.linkedWorkoutSessionID = duplicate.linkedWorkoutSessionID
        }
    }

    private static func canConsolidate(
        _ first: HealthWorkoutInboxItem,
        with second: HealthWorkoutInboxItem
    ) -> Bool {
        if first.status == .linked,
           second.status == .linked,
           let firstSessionID = first.linkedWorkoutSessionID,
           let secondSessionID = second.linkedWorkoutSessionID,
           firstSessionID != secondSessionID {
            return false
        }

        if !knownHealthWorkoutUUIDs(for: first)
            .isDisjoint(with: knownHealthWorkoutUUIDs(for: second)) {
            return true
        }

        return sameLogicalWorkout(first, second)
    }

    private static func sameLogicalWorkout(
        _ item: HealthWorkoutInboxItem,
        _ candidate: ImportedWorkout
    ) -> Bool {
        if sameStableIdentity(
            firstBundle: item.sourceBundleIdentifier,
            firstName: item.sourceName,
            firstSyncIdentifier: item.healthSyncIdentifier,
            firstExternalUUID: item.healthExternalUUID,
            secondBundle: candidate.sourceBundleIdentifier,
            secondName: candidate.sourceName,
            secondSyncIdentifier: candidate.healthSyncIdentifier,
            secondExternalUUID: candidate.healthExternalUUID
        ) {
            return true
        }

        if stableIdentityConflicts(
            firstBundle: item.sourceBundleIdentifier,
            firstName: item.sourceName,
            firstSyncIdentifier: item.healthSyncIdentifier,
            firstExternalUUID: item.healthExternalUUID,
            secondBundle: candidate.sourceBundleIdentifier,
            secondName: candidate.sourceName,
            secondSyncIdentifier: candidate.healthSyncIdentifier,
            secondExternalUUID: candidate.healthExternalUUID
        ) {
            return false
        }

        return sameOuraFingerprint(
            firstStart: item.startDate,
            firstEnd: item.endDate,
            firstDuration: item.duration,
            firstActivity: item.activityType,
            firstBundle: item.sourceBundleIdentifier,
            firstName: item.sourceName,
            secondStart: candidate.startDate,
            secondEnd: candidate.endDate,
            secondDuration: candidate.duration,
            secondActivity: candidate.activityType,
            secondBundle: candidate.sourceBundleIdentifier,
            secondName: candidate.sourceName
        ) || sameCrossSourceStrengthFingerprint(
            firstStart: item.startDate,
            firstEnd: item.endDate,
            firstDuration: item.duration,
            firstActivity: item.activityType,
            firstBundle: item.sourceBundleIdentifier,
            firstName: item.sourceName,
            secondStart: candidate.startDate,
            secondEnd: candidate.endDate,
            secondDuration: candidate.duration,
            secondActivity: candidate.activityType,
            secondBundle: candidate.sourceBundleIdentifier,
            secondName: candidate.sourceName
        )
    }

    private static func sameLogicalWorkout(
        _ first: HealthWorkoutInboxItem,
        _ second: HealthWorkoutInboxItem
    ) -> Bool {
        if sameStableIdentity(
            firstBundle: first.sourceBundleIdentifier,
            firstName: first.sourceName,
            firstSyncIdentifier: first.healthSyncIdentifier,
            firstExternalUUID: first.healthExternalUUID,
            secondBundle: second.sourceBundleIdentifier,
            secondName: second.sourceName,
            secondSyncIdentifier: second.healthSyncIdentifier,
            secondExternalUUID: second.healthExternalUUID
        ) {
            return true
        }

        if stableIdentityConflicts(
            firstBundle: first.sourceBundleIdentifier,
            firstName: first.sourceName,
            firstSyncIdentifier: first.healthSyncIdentifier,
            firstExternalUUID: first.healthExternalUUID,
            secondBundle: second.sourceBundleIdentifier,
            secondName: second.sourceName,
            secondSyncIdentifier: second.healthSyncIdentifier,
            secondExternalUUID: second.healthExternalUUID
        ) {
            return false
        }

        return sameOuraFingerprint(
            firstStart: first.startDate,
            firstEnd: first.endDate,
            firstDuration: first.duration,
            firstActivity: first.activityType,
            firstBundle: first.sourceBundleIdentifier,
            firstName: first.sourceName,
            secondStart: second.startDate,
            secondEnd: second.endDate,
            secondDuration: second.duration,
            secondActivity: second.activityType,
            secondBundle: second.sourceBundleIdentifier,
            secondName: second.sourceName
        ) || sameCrossSourceStrengthFingerprint(
            firstStart: first.startDate,
            firstEnd: first.endDate,
            firstDuration: first.duration,
            firstActivity: first.activityType,
            firstBundle: first.sourceBundleIdentifier,
            firstName: first.sourceName,
            secondStart: second.startDate,
            secondEnd: second.endDate,
            secondDuration: second.duration,
            secondActivity: second.activityType,
            secondBundle: second.sourceBundleIdentifier,
            secondName: second.sourceName
        )
    }

    private static func sameStableIdentity(
        firstBundle: String?,
        firstName: String?,
        firstSyncIdentifier: String?,
        firstExternalUUID: String?,
        secondBundle: String?,
        secondName: String?,
        secondSyncIdentifier: String?,
        secondExternalUUID: String?
    ) -> Bool {
        let firstSource = sourceIdentity(bundle: firstBundle, name: firstName)
        let secondSource = sourceIdentity(bundle: secondBundle, name: secondName)
        guard !firstSource.isEmpty, firstSource == secondSource else {
            return false
        }

        let firstSync = normalizedString(firstSyncIdentifier)
        let secondSync = normalizedString(secondSyncIdentifier)
        if let firstSync, let secondSync {
            return firstSync == secondSync
        }
        let firstExternal = normalizedString(firstExternalUUID)
        let secondExternal = normalizedString(secondExternalUUID)
        if let firstExternal, let secondExternal {
            return firstExternal == secondExternal
        }
        return false
    }

    private static func stableIdentityConflicts(
        firstBundle: String?,
        firstName: String?,
        firstSyncIdentifier: String?,
        firstExternalUUID: String?,
        secondBundle: String?,
        secondName: String?,
        secondSyncIdentifier: String?,
        secondExternalUUID: String?
    ) -> Bool {
        let firstSource = sourceIdentity(bundle: firstBundle, name: firstName)
        let secondSource = sourceIdentity(bundle: secondBundle, name: secondName)
        guard !firstSource.isEmpty, firstSource == secondSource else {
            return false
        }

        let firstSync = normalizedString(firstSyncIdentifier)
        let secondSync = normalizedString(secondSyncIdentifier)
        if let firstSync, let secondSync {
            return firstSync != secondSync
        }

        let firstExternal = normalizedString(firstExternalUUID)
        let secondExternal = normalizedString(secondExternalUUID)
        if let firstExternal, let secondExternal {
            return firstExternal != secondExternal
        }
        return false
    }

    private static func sameOuraFingerprint(
        firstStart: Date,
        firstEnd: Date,
        firstDuration: TimeInterval,
        firstActivity: String,
        firstBundle: String?,
        firstName: String?,
        secondStart: Date,
        secondEnd: Date,
        secondDuration: TimeInterval,
        secondActivity: String,
        secondBundle: String?,
        secondName: String?
    ) -> Bool {
        guard firstActivity == secondActivity,
              isOuraSource(bundle: firstBundle, name: firstName),
              isOuraSource(bundle: secondBundle, name: secondName) else {
            return false
        }

        let durationTolerance = max(
            fingerprintDurationTolerance,
            max(firstDuration, secondDuration) * 0.05
        )
        guard abs(firstDuration - secondDuration) <= durationTolerance else {
            return false
        }

        let boundariesMatch =
            abs(firstStart.timeIntervalSince(secondStart)) <= fingerprintDateTolerance &&
            abs(firstEnd.timeIntervalSince(secondEnd)) <= fingerprintDateTolerance

        let overlapStart = max(firstStart, secondStart)
        let overlapEnd = min(firstEnd, secondEnd)
        let overlap = max(0, overlapEnd.timeIntervalSince(overlapStart))
        let shorterDuration = max(1, min(firstDuration, secondDuration))
        return boundariesMatch || overlap / shorterDuration >= 0.90
    }

    private static func sameCrossSourceStrengthFingerprint(
        firstStart: Date,
        firstEnd: Date,
        firstDuration: TimeInterval,
        firstActivity: String,
        firstBundle: String?,
        firstName: String?,
        secondStart: Date,
        secondEnd: Date,
        secondDuration: TimeInterval,
        secondActivity: String,
        secondBundle: String?,
        secondName: String?
    ) -> Bool {
        let firstSource = sourceIdentity(bundle: firstBundle, name: firstName)
        let secondSource = sourceIdentity(bundle: secondBundle, name: secondName)
        guard !firstSource.isEmpty,
              !secondSource.isEmpty,
              firstSource != secondSource,
              isOuraSource(bundle: firstBundle, name: firstName) ||
                isOuraSource(bundle: secondBundle, name: secondName),
              activityFamily(firstActivity) == "strength",
              activityFamily(secondActivity) == "strength",
              sameStrictWorkoutFingerprint(
                firstStart: firstStart,
                firstEnd: firstEnd,
                firstDuration: firstDuration,
                firstActivity: firstActivity,
                secondStart: secondStart,
                secondEnd: secondEnd,
                secondDuration: secondDuration,
                secondActivity: secondActivity
              ) else {
            return false
        }
        return true
    }

    private static func sameStrictWorkoutFingerprint(
        _ item: HealthWorkoutInboxItem,
        _ candidate: ImportedWorkout
    ) -> Bool {
        sameStrictWorkoutFingerprint(
            firstStart: item.startDate,
            firstEnd: item.endDate,
            firstDuration: item.duration,
            firstActivity: item.activityType,
            secondStart: candidate.startDate,
            secondEnd: candidate.endDate,
            secondDuration: candidate.duration,
            secondActivity: candidate.activityType
        )
    }

    private static func sameStrictWorkoutFingerprint(
        firstStart: Date,
        firstEnd: Date,
        firstDuration: TimeInterval,
        firstActivity: String,
        secondStart: Date,
        secondEnd: Date,
        secondDuration: TimeInterval,
        secondActivity: String
    ) -> Bool {
        activityFamily(firstActivity) == activityFamily(secondActivity) &&
            abs(firstStart.timeIntervalSince(secondStart)) <=
                crossSourceDateTolerance &&
            abs(firstEnd.timeIntervalSince(secondEnd)) <=
                crossSourceDateTolerance &&
            abs(firstDuration - secondDuration) <=
                crossSourceDurationTolerance
    }

    private static func activityFamily(_ activity: String) -> String {
        switch activity {
        case "traditionalStrengthTraining", "functionalStrengthTraining":
            return "strength"
        default:
            return activity
        }
    }

    private static func sourceIdentity(bundle: String?, name: String?) -> String {
        if isOuraSource(bundle: bundle, name: name) { return "oura" }
        let bundleValue = bundle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if !bundleValue.isEmpty { return bundleValue }
        return name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func isOuraSource(bundle: String?, name: String?) -> Bool {
        let normalizedBundle = bundle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalizedBundle == "com.ouraring.oura" ||
            normalizedBundle.hasPrefix("com.ouraring.") {
            return true
        }

        let normalizedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalizedName == "oura" || normalizedName == "oura ring"
    }

    private static func canonicalScore(_ item: HealthWorkoutInboxItem) -> Int {
        (item.healthDeletionObservedAt == nil ? 1_000 : 0) +
            statusPriority(item.status) * 100 +
            (item.linkedWorkoutSessionID == nil ? 0 : 20) +
            (item.avgHeartRate == nil ? 0 : 10) +
            (item.calories == nil ? 0 : 5) +
            (item.healthSyncIdentifier?.isEmpty == false ? 3 : 0) +
            (item.healthExternalUUID?.isEmpty == false ? 2 : 0) +
            (item.sourceBundleIdentifier?.isEmpty == false ? 1 : 0)
    }

    private static func statusPriority(
        _ status: HealthWorkoutInboxItem.Status
    ) -> Int {
        switch status {
        case .linked: return 3
        case .dismissed: return 2
        case .pending: return 1
        }
    }

    private static func updateLinkedSession(
        for item: HealthWorkoutInboxItem,
        sessions: [WorkoutSession]
    ) {
        guard item.status == .linked else { return }
        let knownUUIDs = knownHealthWorkoutUUIDs(for: item)
        let session = item.linkedWorkoutSessionID.flatMap { linkedID in
            sessions.first(where: { $0.id == linkedID })
        } ?? sessions.first(where: {
            guard let uuid = $0.healthWorkoutUUID else { return false }
            return knownUUIDs.contains(uuid)
        })

        guard let session else { return }
        item.linkedWorkoutSessionID = session.id
        applyMetrics(from: item, to: session)
    }

    /// Links an inbox item to an existing logged workout, attaching the wearable metrics.
    @discardableResult
    static func link(_ item: HealthWorkoutInboxItem, to session: WorkoutSession, context: ModelContext) -> Bool {
        applyMetrics(from: item, to: session)
        item.status = .linked
        item.linkedWorkoutSessionID = session.id
        return PersistenceSave.commit(context, action: "link wearable workout")
    }

    /// Creates a new workout session from an inbox item and links it.
    static func createSession(from item: HealthWorkoutInboxItem, context: ModelContext) -> WorkoutSession? {
        let sessions: [WorkoutSession]
        do {
            sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        } catch {
            // If local identity cannot be checked, fail closed instead of
            // risking a second session for the same wearable workout.
            return nil
        }
        let knownUUIDs = knownHealthWorkoutUUIDs(for: item)
        if let existing = item.linkedWorkoutSessionID.flatMap({ linkedID in
            sessions.first(where: { $0.id == linkedID })
        }) ?? sessions.first(where: {
            guard let uuid = $0.healthWorkoutUUID else { return false }
            return knownUUIDs.contains(uuid)
        }) {
            applyMetrics(from: item, to: existing)
            item.status = .linked
            item.linkedWorkoutSessionID = existing.id
            guard PersistenceSave.commit(
                context,
                action: "reuse workout from wearable"
            ) else {
                return nil
            }
            return existing
        }

        let session = WorkoutSession(
            date: item.startDate,
            title: activityDisplayName(for: item.activityType),
            executionStatus: .completed
        )
        applyMetrics(from: item, to: session)
        context.insert(session)
        item.status = .linked
        item.linkedWorkoutSessionID = session.id
        guard PersistenceSave.commit(context, action: "create workout from wearable") else { return nil }
        return session
    }

    static func dismiss(_ item: HealthWorkoutInboxItem, context: ModelContext) {
        item.status = .dismissed
        _ = PersistenceSave.commit(context, action: "dismiss wearable workout")
    }

    private static func applyMetrics(from item: HealthWorkoutInboxItem, to session: WorkoutSession) {
        session.healthWorkoutUUID = item.healthWorkoutUUID
        session.healthDuration = item.duration
        session.healthCalories = item.calories
        session.healthAvgHeartRate = item.avgHeartRate
        session.healthSourceName = item.sourceName
        session.healthActivityType = item.activityType
    }

    private static func clearHealthLink(on session: WorkoutSession) {
        session.healthWorkoutUUID = nil
        session.healthDuration = nil
        session.healthCalories = nil
        session.healthAvgHeartRate = nil
        session.healthSourceName = nil
        session.healthActivityType = nil
    }

    // MARK: - Activity naming

    static func activityKey(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: return "traditionalStrengthTraining"
        case .functionalStrengthTraining: return "functionalStrengthTraining"
        case .highIntensityIntervalTraining: return "highIntensityIntervalTraining"
        case .coreTraining: return "coreTraining"
        case .crossTraining: return "crossTraining"
        case .yoga: return "yoga"
        case .pilates: return "pilates"
        case .flexibility: return "flexibility"
        case .martialArts: return "martialArts"
        default: return "other"
        }
    }

    static func activityDisplayName(for key: String) -> String {
        switch key {
        case "traditionalStrengthTraining": return "Strength Training"
        case "functionalStrengthTraining": return "Functional Strength"
        case "highIntensityIntervalTraining": return "HIIT"
        case "coreTraining": return "Core Training"
        case "crossTraining": return "Cross Training"
        case "yoga": return "Yoga"
        case "pilates": return "Pilates"
        case "flexibility": return "Flexibility"
        case "martialArts": return "Martial Arts"
        default: return "Workout"
        }
    }

    static func activityIcon(for key: String) -> String {
        switch key {
        case "traditionalStrengthTraining", "functionalStrengthTraining": return "dumbbell.fill"
        case "highIntensityIntervalTraining": return "flame.fill"
        case "coreTraining": return "figure.core.training"
        case "crossTraining": return "figure.cross.training"
        case "yoga": return "figure.yoga"
        case "pilates": return "figure.pilates"
        case "flexibility": return "figure.flexibility"
        case "martialArts": return "figure.martial.arts"
        default: return "figure.strengthtraining.traditional"
        }
    }
}
