import CoreLocation
import Foundation
import HealthKit
import SwiftData

/// Imports cardio workouts from Apple Health into a review inbox. A wearable
/// representation is never allowed to overwrite an app-tracked activity by a
/// fuzzy match; the user explicitly links it or creates a new activity.
@MainActor
enum CardioWorkoutInboxService {
    struct SyncResult {
        let inserted: Int
        let errorMessage: String?

        static let noChanges = SyncResult(inserted: 0, errorMessage: nil)
    }

    private struct PageResult {
        let inserted: Int
        let observedChanges: Int
        let errorMessage: String?
    }

    private struct WorkoutDetails {
        let healthWorkoutUUID: String
        let sourceName: String
        let sourceBundleIdentifier: String
        let distanceMeters: Double
        let calories: Double?
        let heartRate: HealthKitManager.WorkoutHeartRateSummary
        let avgCadence: Double?
        let maxCadence: Double?
        let avgStrideLength: Double?
        let verticalOscillation: Double?
        let groundContactTime: Double?
        let avgPower: Double?
        let maxPower: Double?
        let routeData: Data?
        let elevation: (ascent: Double, descent: Double, min: Double, max: Double)?
    }

    private struct WorkoutRepresentation {
        let healthWorkoutUUID: String
        let workout: HKWorkout
        let sourceName: String
        let sourceBundleIdentifier: String
        let distanceMeters: Double
        let calories: Double?
        let heartRate: HealthKitManager.WorkoutHeartRateSummary
    }

    private static let replacementGracePeriod: TimeInterval = 24 * 60 * 60
    private static let fingerprintDateTolerance: TimeInterval = 120
    private static let fingerprintDurationTolerance: TimeInterval = 180
    private static let fingerprintDistanceToleranceMeters: Double = 250
    private static let initialLookbackDays = 30
    private static let firstScanDateKey = "healthKit.cardioInboxFirstScanCutoff"
    private static var syncInProgress = false

    @discardableResult
    static func sync(
        context: ModelContext,
        pageLimit: Int = 50,
        requestAuthorization: Bool = false
    ) async -> SyncResult {
        guard !syncInProgress else { return .noChanges }
        guard HKHealthStore.isHealthDataAvailable() else { return .noChanges }
        guard !AppLaunchConfiguration.current.shouldSkipAutomationSideEffects else {
            return .noChanges
        }

        syncInProgress = true
        defer { syncInProgress = false }

        if requestAuthorization {
            do {
                try await HealthKitManager.shared.requestAuthorization()
            } catch {
                return SyncResult(
                    inserted: 0,
                    errorMessage: error.localizedDescription
                )
            }
        }

        let expectedPurgeGeneration =
            WearableWorkoutInboxService.localDataPurgeGeneration
        var totalInserted = 0

        // Drain a short backlog in one refresh instead of requiring repeated
        // tab visits when several wearable activities arrived together.
        for pageIndex in 0..<5 {
            guard WearableWorkoutInboxService
                .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
                return .noChanges
            }

            let page = await performSingleSync(
                context: context,
                limit: max(pageLimit, 1),
                forceRefresh: requestAuthorization && pageIndex == 0,
                expectedPurgeGeneration: expectedPurgeGeneration
            )
            totalInserted += page.inserted
            if let errorMessage = page.errorMessage {
                return SyncResult(
                    inserted: totalInserted,
                    errorMessage: errorMessage
                )
            }
            if page.observedChanges < max(pageLimit, 1) { break }
        }

        return SyncResult(inserted: totalInserted, errorMessage: nil)
    }

    private static func performSingleSync(
        context: ModelContext,
        limit: Int,
        forceRefresh: Bool,
        expectedPurgeGeneration: Int
    ) async -> PageResult {
        let changes: HealthKitManager.CardioWorkoutChanges
        do {
            changes = try await HealthKitManager.shared
                .fetchCardioWorkoutChanges(
                    resetAnchor: false,
                    limit: limit,
                    since: scanCutoffDate()
                )
        } catch {
            return PageResult(
                inserted: 0,
                observedChanges: 0,
                errorMessage: error.localizedDescription
            )
        }

        guard WearableWorkoutInboxService
            .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
            return PageResult(inserted: 0, observedChanges: 0, errorMessage: nil)
        }

        let sessions: [RunningSession]
        var items: [CardioWorkoutInboxItem]
        do {
            sessions = try context.fetch(FetchDescriptor<RunningSession>())
            items = try context.fetch(FetchDescriptor<CardioWorkoutInboxItem>())
        } catch {
            return PageResult(
                inserted: 0,
                observedChanges: 0,
                errorMessage: "The cardio inbox could not read its local data."
            )
        }

        var inserted = 0
        let addedUUIDs = Set(changes.added.map { $0.uuid.uuidString })
        let purgeCutoff = WearableWorkoutInboxService.localDataPurgeCutoffDate

        for workout in changes.added {
            if let purgeCutoff, workout.endDate <= purgeCutoff { continue }
            guard let activityType = activityKey(for: workout.workoutActivityType) else {
                continue
            }
            let uuid = workout.uuid.uuidString

            if let exactSession = sessions.first(where: {
                knownHealthUUIDs(for: $0).contains(uuid)
            }) {
                // The app already knows this exact Health representation.
                if exactSession.healthWorkoutUUID == nil,
                   workout.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier {
                    exactSession.healthWorkoutUUID = uuid
                }
                if exactSession.healthWorkoutUUID == uuid,
                   workout.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier {
                    setImportedDistance(
                        HealthKitManager.recordedDistanceMeters(for: workout),
                        on: exactSession
                    )
                }
                continue
            }

            // Pace-owned workouts carry the local RunningSession ID. This closes
            // the observer race between Health saving the workout and SwiftData
            // persisting the returned UUID.
            if workout.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier,
               let externalID = normalizedMetadataString(
                    workout.metadata?[HKMetadataKeyExternalUUID]
               ),
               let localID = UUID(uuidString: externalID),
               let localSession = sessions.first(where: { $0.id == localID }) {
                localSession.healthWorkoutUUID = uuid
                addHealthUUID(uuid, to: localSession)
                continue
            }

            let caloriesValue = try? await HealthKitManager.shared
                .activeEnergyKilocalories(for: workout)
            guard WearableWorkoutInboxService
                .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
                return PageResult(inserted: 0, observedChanges: 0, errorMessage: nil)
            }
            let heartRate = (try? await HealthKitManager.shared
                .heartRateSummary(for: workout)) ?? emptyHeartRateSummary

            let candidate = CardioWorkoutInboxItem(
                healthWorkoutUUID: uuid,
                startDate: workout.startDate,
                endDate: workout.endDate,
                activityType: activityType,
                distanceMeters: HealthKitManager.recordedDistanceMeters(
                    for: workout
                ),
                duration: workout.duration,
                calories: positive(caloriesValue),
                avgHeartRate: heartRate.average,
                maxHeartRate: heartRate.maximum,
                minHeartRate: heartRate.minimum,
                sourceName: workout.sourceRevision.source.name,
                sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                healthSyncIdentifier: normalizedMetadataString(
                    workout.metadata?[HKMetadataKeySyncIdentifier]
                ),
                healthSyncVersion: metadataInt(
                    workout.metadata?[HKMetadataKeySyncVersion]
                ),
                healthExternalUUID: normalizedMetadataString(
                    workout.metadata?[HKMetadataKeyExternalUUID]
                ),
                metricSourceHealthWorkoutUUID: heartRate.hasValues ? uuid : nil,
                metricSourceName: heartRate.hasValues
                    ? workout.sourceRevision.source.name : nil,
                metricSourceBundleIdentifier: heartRate.hasValues
                    ? workout.sourceRevision.source.bundleIdentifier : nil
            )
            recordCurrentSyncVersion(on: candidate)

            if let existing = items.first(where: {
                knownHealthUUIDs(for: $0).contains(uuid) ||
                    sameLogicalWorkout($0, candidate)
            }) {
                merge(candidate, into: existing)
                let details = await loadDetails(for: existing)
                if let details {
                    apply(details, to: existing)
                }
                if existing.status == .linked,
                   let sessionID = existing.linkedRunningSessionID,
                   let linkedSession = sessions.first(where: { $0.id == sessionID }) {
                    if let details {
                        apply(details, to: linkedSession)
                    }
                    applySummary(from: existing, to: linkedSession)
                    repairImportedDistance(from: existing, on: linkedSession)
                    // Use only identifiers retained by merge. In particular, a
                    // rejected lower sync version must never be promoted to the
                    // linked session as a replacement.
                    applyHealthIdentity(from: existing, to: linkedSession)
                }
            } else {
                candidate.suggestedRunningSessionID = suggestedSession(
                    for: candidate,
                    in: sessions
                )?.id
                context.insert(candidate)
                items.append(candidate)
                inserted += 1
            }
        }

        reconcileDeletions(
            changes.deletedUUIDs.filter { !addedUUIDs.contains($0) },
            items: items,
            sessions: sessions,
            context: context
        )
        await refreshMissingMetrics(
            items: items,
            sessions: sessions,
            forceRefresh: forceRefresh,
            expectedPurgeGeneration: expectedPurgeGeneration
        )
        await refreshImportedDistances(
            items: items,
            sessions: sessions,
            forceRefresh: forceRefresh,
            expectedPurgeGeneration: expectedPurgeGeneration
        )
        expireReplacementTombstones(
            items: items,
            sessions: sessions,
            context: context
        )
        refreshSuggestedMatches(items: items, sessions: sessions)

        guard WearableWorkoutInboxService
            .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
            return PageResult(inserted: 0, observedChanges: 0, errorMessage: nil)
        }
        guard PersistenceSave.commit(context, action: "sync cardio inbox") else {
            return PageResult(
                inserted: 0,
                observedChanges: 0,
                errorMessage: "The cardio inbox could not save its latest Health update."
            )
        }

        HealthKitManager.shared.persistCardioWorkoutAnchor(changes.newAnchor)
        return PageResult(
            inserted: inserted,
            observedChanges: changes.added.count + changes.deleted.count,
            errorMessage: nil
        )
    }

    /// Keep a new install's inbox useful instead of filling it with years of
    /// historical Health workouts. The fixed cutoff still permits later
    /// updates and deletions for everything considered on the first scan.
    private static func scanCutoffDate() -> Date {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: firstScanDateKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -initialLookbackDays,
            to: Date()
        ) ?? Date()
        defaults.set(cutoff.timeIntervalSince1970, forKey: firstScanDateKey)
        return cutoff
    }

    private static func refreshMissingMetrics(
        items: [CardioWorkoutInboxItem],
        sessions: [RunningSession],
        forceRefresh: Bool,
        expectedPurgeGeneration: Int
    ) async {
        let now = Date()
        let eligible = items.filter {
            let recent = now.timeIntervalSince($0.endDate) < 48 * 60 * 60
            let missing = $0.avgHeartRate == nil || $0.maxHeartRate == nil ||
                $0.minHeartRate == nil || $0.calories == nil ||
                ($0.avgHeartRate != nil && $0.metricSourceHealthWorkoutUUID == nil)
            return $0.status != .dismissed && $0.healthDeletionObservedAt == nil &&
                (missing || recent || forceRefresh) &&
                (forceRefresh || CardioHealthRefreshPolicy.isDue(
                    lastAttempt: $0.healthDetailsLastAttemptAt, now: now,
                    interval: recent ? 15 * 60 : 24 * 60 * 60
                ))
        }
        let selectedIDs = CardioHealthRefreshPolicy.batchIDs(eligible.map {
            .init(id: $0.id, date: $0.endDate, lastAttempt: $0.healthDetailsLastAttemptAt)
        }, limit: 10)

        for item in eligible where selectedIDs.contains(item.id) {
            guard WearableWorkoutInboxService
                .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
                return
            }
            let details = await loadDetails(for: item)
            guard WearableWorkoutInboxService
                .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
                return
            }
            item.healthDetailsLastAttemptAt = Date()
            guard item.healthDeletionObservedAt == nil,
                  item.status != .dismissed,
                  let details else { continue }
            apply(details, to: item)

            if item.status == .linked,
               let linkedID = item.linkedRunningSessionID,
               let session = sessions.first(where: { $0.id == linkedID }) {
                apply(details, to: session)
                applySummary(from: item, to: session)
                repairImportedDistance(from: item, on: session)
                applyHealthIdentity(from: item, to: session)
            }
        }
    }

    private static func refreshImportedDistances(
        items: [CardioWorkoutInboxItem],
        sessions: [RunningSession],
        forceRefresh: Bool,
        expectedPurgeGeneration: Int
    ) async {
        let now = Date()
        let candidates = sessions.filter {
            (forceRefresh || CardioHealthRefreshPolicy.isDue(lastAttempt: $0.healthDistanceLastAttemptAt, now: now, interval: 24 * 60 * 60)) &&
            $0.healthWorkoutUUID.flatMap(UUID.init(uuidString:)) != nil &&
                ["running", "walking", "hiking", "cycling", "rowing"].contains($0.activityType)
        }
        let selectedIDs = CardioHealthRefreshPolicy.batchIDs(candidates.map {
            .init(id: $0.id, date: $0.date, lastAttempt: $0.healthDistanceLastAttemptAt)
        }, limit: 50)
        let selected = candidates.filter { selectedIDs.contains($0.id) }
        var uuids = Set(selected.compactMap {
            $0.healthWorkoutUUID.flatMap(UUID.init(uuidString:))
        })
        let eligibleItems = items.filter {
            $0.status != .dismissed && $0.healthDeletionObservedAt == nil &&
                (forceRefresh || CardioHealthRefreshPolicy.isDue(lastAttempt: $0.healthDistanceLastAttemptAt, now: now, interval: 24 * 60 * 60))
        }
        let itemIDs = CardioHealthRefreshPolicy.batchIDs(eligibleItems.map {
            .init(id: $0.id, date: $0.endDate, lastAttempt: $0.healthDistanceLastAttemptAt)
        }, limit: 50)
        let selectedItems = eligibleItems.filter { itemIDs.contains($0.id) }
        for item in selectedItems {
            uuids.formUnion(knownHealthUUIDs(for: item).compactMap(UUID.init(uuidString:)))
        }
        let workouts = try? await HealthKitManager.shared.workoutsForUUIDs(uuids)
        guard WearableWorkoutInboxService
            .isCurrentLocalDataPurgeGeneration(expectedPurgeGeneration) else {
            return
        }

        // Missing/deleted or temporarily unreadable workouts must not monopolize
        // the queue. They remain eligible for a later pass.
        let attemptedAt = Date()
        for session in selected { session.healthDistanceLastAttemptAt = attemptedAt }
        for item in selectedItems { item.healthDistanceLastAttemptAt = attemptedAt }
        guard let workouts else { return }
        let workoutsByUUID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.uuid, $0) })
        for item in selectedItems where item.healthDeletionObservedAt == nil && item.status != .dismissed {
            let meters = knownHealthUUIDs(for: item).compactMap(UUID.init(uuidString:))
                .compactMap { workoutsByUUID[$0] }
                .map { HealthKitManager.recordedDistanceMeters(for: $0) }.max() ?? 0
            if meters > 0 { item.distanceMeters = meters }
            if let linkedID = item.linkedRunningSessionID,
               let session = sessions.first(where: { $0.id == linkedID }) {
                repairImportedDistance(from: item, on: session)
            }
        }
        for session in selected {
            guard let uuid = session.healthWorkoutUUID.flatMap(UUID.init(uuidString:)),
                  let workout = workoutsByUUID[uuid],
                  workout.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier else {
                continue
            }
            setImportedDistance(
                HealthKitManager.recordedDistanceMeters(for: workout),
                on: session
            )
        }
    }

    static func refreshSuggestedMatches(context: ModelContext) {
        guard let items = try? context.fetch(
            FetchDescriptor<CardioWorkoutInboxItem>()
        ), let sessions = try? context.fetch(
            FetchDescriptor<RunningSession>()
        ) else { return }

        refreshSuggestedMatches(items: items, sessions: sessions)
        _ = PersistenceSave.commit(context, action: "refresh cardio suggestions")
    }

    private static func refreshSuggestedMatches(
        items: [CardioWorkoutInboxItem],
        sessions: [RunningSession]
    ) {
        for item in items where
            item.status == .pending && item.healthDeletionObservedAt == nil {
            item.suggestedRunningSessionID = suggestedSession(
                for: item,
                in: sessions
            )?.id
        }
    }

    static func suggestedSession(
        for item: CardioWorkoutInboxItem,
        in sessions: [RunningSession]
    ) -> RunningSession? {
        let candidates = rankedCandidates(for: item, in: sessions)
            .filter { isConfidentMatch(item, $0) }
        guard let first = candidates.first else { return nil }
        if candidates.count > 1 {
            let firstScore = matchScore(item, first)
            let secondScore = matchScore(item, candidates[1])
            guard secondScore - firstScore >= 1.5 else { return nil }
        }
        return first
    }

    static func rankedCandidates(
        for item: CardioWorkoutInboxItem,
        in sessions: [RunningSession]
    ) -> [RunningSession] {
        sessions
            .filter { session in
                guard session.activityType == item.activityType else { return false }
                guard abs(session.date.timeIntervalSince(item.endDate)) <= 24 * 60 * 60 else {
                    return false
                }
                if let metricUUID = session.metricSourceHealthWorkoutUUID,
                   !metricUUID.isEmpty,
                   !knownHealthUUIDs(for: item).contains(metricUUID) {
                    return false
                }
                return true
            }
            .sorted { matchScore(item, $0) < matchScore(item, $1) }
    }

    @discardableResult
    static func link(
        _ item: CardioWorkoutInboxItem,
        to session: RunningSession,
        context: ModelContext
    ) async -> Bool {
        guard item.healthDeletionObservedAt == nil else { return false }

        if let details = await loadDetails(for: item) {
            apply(details, to: item)
            apply(details, to: session)
        }
        applySummary(from: item, to: session)
        repairImportedDistance(from: item, on: session)
        applyHealthIdentity(from: item, to: session)
        item.status = .linked
        item.linkedRunningSessionID = session.id
        item.suggestedRunningSessionID = session.id
        return PersistenceSave.commit(context, action: "link cardio Health activity")
    }

    static func createSession(
        from item: CardioWorkoutInboxItem,
        context: ModelContext
    ) async -> RunningSession? {
        let sessions = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        if let linkedID = item.linkedRunningSessionID,
           let existing = sessions.first(where: { $0.id == linkedID }) {
            _ = await link(item, to: existing, context: context)
            return existing
        }
        let itemUUIDs = knownHealthUUIDs(for: item)
        if let existing = sessions.first(where: {
            !knownHealthUUIDs(for: $0).isDisjoint(with: itemUUIDs)
        }) {
            _ = await link(item, to: existing, context: context)
            return existing
        }

        let details = await loadDetails(for: item)
        if let details {
            apply(details, to: item)
        }

        let unit = UserDefaults.standard.string(forKey: "distanceUnit") ?? "mi"
        let distance = unit == "mi"
            ? item.distanceMeters / 1609.34
            : item.distanceMeters / 1000
        let session = RunningSession(
            date: item.endDate,
            distance: distance,
            distanceUnit: unit,
            duration: item.duration,
            calories: item.calories,
            healthWorkoutUUID: item.healthWorkoutUUID,
            metricSourceHealthWorkoutUUID:
                item.metricSourceHealthWorkoutUUID ?? item.healthWorkoutUUID,
            healthMetricSourceName: item.metricSourceName ?? item.sourceName,
            activityType: item.activityType,
            avgHeartRate: item.avgHeartRate,
            maxHeartRate: item.maxHeartRate,
            minHeartRate: item.minHeartRate
        )
        context.insert(session)
        for uuid in itemUUIDs { addHealthUUID(uuid, to: session) }
        if let details {
            apply(details, to: session)
        }
        applySummary(from: item, to: session)
        applyHealthIdentity(from: item, to: session)
        item.status = .linked
        item.linkedRunningSessionID = session.id
        item.suggestedRunningSessionID = session.id

        guard PersistenceSave.commit(context, action: "create activity from cardio inbox") else {
            return nil
        }
        return session
    }

    static func dismiss(
        _ item: CardioWorkoutInboxItem,
        context: ModelContext
    ) {
        item.status = .dismissed
        item.suggestedRunningSessionID = nil
        _ = PersistenceSave.commit(context, action: "dismiss cardio Health activity")
    }

    /// Evaluates every Health representation before selecting the one with the
    /// richest real heart-rate series. Extended metrics are then loaded only
    /// from that selected representation.
    private static func loadDetails(
        for item: CardioWorkoutInboxItem
    ) async -> WorkoutDetails? {
        var representations: [WorkoutRepresentation] = []
        for uuid in knownHealthUUIDs(for: item).sorted() {
            if let representation = await loadRepresentation(for: uuid) {
                representations.append(representation)
            }
        }
        guard let selected = richestRepresentation(
            in: representations,
            preferredUUID: item.metricSourceHealthWorkoutUUID,
            primaryUUID: item.healthWorkoutUUID
        ) else { return nil }
        let distanceMeters = representations
            .map(\.distanceMeters)
            .filter { $0.isFinite && $0 > 0 }
            .max() ?? 0
        return await loadDetails(
            for: selected,
            distanceMeters: distanceMeters
        )
    }

    private static func loadRepresentation(
        for uuid: String
    ) async -> WorkoutRepresentation? {
        guard let workout = try? await HealthKitManager.shared
            .workoutForUUID(uuid) else { return nil }
        let calories = positive(
            try? await HealthKitManager.shared.activeEnergyKilocalories(for: workout)
        )
        let heartRate = (try? await HealthKitManager.shared
            .heartRateSummary(for: workout)) ?? emptyHeartRateSummary
        return WorkoutRepresentation(
            healthWorkoutUUID: uuid,
            workout: workout,
            sourceName: workout.sourceRevision.source.name,
            sourceBundleIdentifier:
                workout.sourceRevision.source.bundleIdentifier,
            distanceMeters: HealthKitManager.recordedDistanceMeters(
                for: workout
            ),
            calories: calories,
            heartRate: heartRate
        )
    }

    private static func richestRepresentation(
        in representations: [WorkoutRepresentation],
        preferredUUID: String?,
        primaryUUID: String
    ) -> WorkoutRepresentation? {
        representations.max { first, second in
            representationIsRicher(
                second,
                than: first,
                preferredUUID: preferredUUID,
                primaryUUID: primaryUUID
            )
        }
    }

    private static func representationIsRicher(
        _ candidate: WorkoutRepresentation,
        than current: WorkoutRepresentation,
        preferredUUID: String?,
        primaryUUID: String
    ) -> Bool {
        let candidateFields = heartRateFieldCount(candidate.heartRate)
        let currentFields = heartRateFieldCount(current.heartRate)
        if candidateFields != currentFields {
            return candidateFields > currentFields
        }
        if candidate.heartRate.sampleCount != current.heartRate.sampleCount {
            return candidate.heartRate.sampleCount > current.heartRate.sampleCount
        }
        if candidate.heartRate.coveredDuration != current.heartRate.coveredDuration {
            return candidate.heartRate.coveredDuration > current.heartRate.coveredDuration
        }
        let candidateIsOura = candidate.heartRate.hasValues &&
            isRecognizedOuraSource(
                name: candidate.sourceName,
                bundleIdentifier: candidate.sourceBundleIdentifier
            )
        let currentIsOura = current.heartRate.hasValues &&
            isRecognizedOuraSource(
                name: current.sourceName,
                bundleIdentifier: current.sourceBundleIdentifier
            )
        if candidateIsOura != currentIsOura { return candidateIsOura }
        let candidateIsPreferred = candidate.healthWorkoutUUID == preferredUUID
        let currentIsPreferred = current.healthWorkoutUUID == preferredUUID
        if candidateIsPreferred != currentIsPreferred { return candidateIsPreferred }
        let candidateIsPrimary = candidate.healthWorkoutUUID == primaryUUID
        let currentIsPrimary = current.healthWorkoutUUID == primaryUUID
        if candidateIsPrimary != currentIsPrimary { return candidateIsPrimary }
        if (candidate.calories != nil) != (current.calories != nil) {
            return candidate.calories != nil
        }
        return candidate.healthWorkoutUUID < current.healthWorkoutUUID
    }

    private static func isRecognizedOuraSource(
        name: String?,
        bundleIdentifier: String?
    ) -> Bool {
        let bundle = normalized(bundleIdentifier)
        let name = normalized(name)
        return bundle == "com.ouraring.oura" ||
            bundle.hasPrefix("com.ouraring.") ||
            name == "oura" || name == "oura ring"
    }

    private static func heartRateFieldCount(
        _ summary: HealthKitManager.WorkoutHeartRateSummary
    ) -> Int {
        (summary.average == nil ? 0 : 1) +
            (summary.maximum == nil ? 0 : 1) +
            (summary.minimum == nil ? 0 : 1)
    }

    private static func loadDetails(
        for representation: WorkoutRepresentation,
        distanceMeters: Double
    ) async -> WorkoutDetails {
        let workout = representation.workout
        let cadence = try? await HealthKitManager.shared.cadenceStats(for: workout)
        let avgStrideLength = try? await HealthKitManager.shared.averageStrideLength(for: workout)
        let verticalOscillation = try? await HealthKitManager.shared.averageVerticalOscillation(for: workout)
        let groundContactTime = try? await HealthKitManager.shared.averageGroundContactTime(for: workout)
        let avgPower = try? await HealthKitManager.shared.averagePower(for: workout)
        let maxPower = try? await HealthKitManager.shared.maxPower(for: workout)

        var routeData: Data?
        var elevation: (ascent: Double, descent: Double, min: Double, max: Double)?
        if let locations = try? await HealthKitManager.shared.routeLocations(for: workout),
           !locations.isEmpty {
            let reduced = downsample(locations)
            let coordinates = reduced.map {
                RunCoordinate(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    altitude: $0.altitude,
                    timestamp: $0.timestamp
                )
            }
            routeData = try? JSONEncoder().encode(coordinates)
            elevation = ElevationCalculator.calculateElevationMetrics(from: coordinates)
        }

        return WorkoutDetails(
            healthWorkoutUUID: representation.healthWorkoutUUID,
            sourceName: representation.sourceName,
            sourceBundleIdentifier: representation.sourceBundleIdentifier,
            distanceMeters: distanceMeters,
            calories: representation.calories,
            heartRate: representation.heartRate,
            avgCadence: cadence?.average,
            maxCadence: cadence?.maximum,
            avgStrideLength: avgStrideLength,
            verticalOscillation: verticalOscillation,
            groundContactTime: groundContactTime,
            avgPower: avgPower,
            maxPower: maxPower,
            routeData: routeData,
            elevation: elevation
        )
    }

    private static func applySummary(
        from item: CardioWorkoutInboxItem,
        to session: RunningSession
    ) {
        if let calories = positive(item.calories) { session.calories = calories }
        if let value = item.avgHeartRate { session.avgHeartRate = value }
        if let value = item.maxHeartRate { session.maxHeartRate = value }
        if let value = item.minHeartRate { session.minHeartRate = value }
    }

    /// Correct only sessions whose canonical workout is one of this inbox
    /// item's Health representations. Linking a wearable to a locally tracked
    /// activity must enrich it without replacing its locally measured distance.
    private static func repairImportedDistance(
        from item: CardioWorkoutInboxItem,
        on session: RunningSession
    ) {
        guard item.distanceMeters > 0,
              let canonicalUUID = session.healthWorkoutUUID,
              knownHealthUUIDs(for: item).contains(canonicalUUID) else {
            return
        }
        setImportedDistance(item.distanceMeters, on: session)
    }

    private static func setImportedDistance(
        _ distanceMeters: Double,
        on session: RunningSession
    ) {
        guard distanceMeters.isFinite, distanceMeters > 0 else { return }
        let currentMeters = HealthKitManager.metersFor(
            distance: session.distance,
            unit: session.distanceUnit
        )
        guard distanceMeters > currentMeters else { return }
        session.distance = session.distanceUnit == "mi"
            ? distanceMeters / 1609.34
            : distanceMeters / 1000
    }

    /// Copies wearable identities without changing `healthWorkoutUUID`, which
    /// remains the canonical Pace/local Health workout used for deletion.
    private static func applyHealthIdentity(
        from item: CardioWorkoutInboxItem,
        to session: RunningSession
    ) {
        for uuid in knownHealthUUIDs(for: item) {
            addHealthUUID(uuid, to: session)
        }
        let known = knownHealthUUIDs(for: item)
        let metricUUID = item.metricSourceHealthWorkoutUUID.flatMap {
            known.contains($0) ? $0 : nil
        } ?? item.healthWorkoutUUID
        session.metricSourceHealthWorkoutUUID = metricUUID
        session.healthMetricSourceName =
            metricUUID == item.metricSourceHealthWorkoutUUID
                ? (item.metricSourceName ?? item.sourceName)
                : item.sourceName
    }

    private static func apply(
        _ details: WorkoutDetails,
        to item: CardioWorkoutInboxItem
    ) {
        if details.distanceMeters > 0 {
            item.distanceMeters = details.distanceMeters
        }
        if let value = details.calories { item.calories = value }
        guard details.heartRate.hasValues else { return }
        item.avgHeartRate = details.heartRate.average
        item.maxHeartRate = details.heartRate.maximum
        item.minHeartRate = details.heartRate.minimum
        item.metricSourceHealthWorkoutUUID = details.healthWorkoutUUID
        item.metricSourceName = details.sourceName
        item.metricSourceBundleIdentifier = details.sourceBundleIdentifier
    }

    private static func apply(_ details: WorkoutDetails, to session: RunningSession) {
        if let value = details.calories { session.calories = value }
        if let value = details.heartRate.average { session.avgHeartRate = value }
        if let value = details.heartRate.maximum { session.maxHeartRate = value }
        if let value = details.heartRate.minimum { session.minHeartRate = value }
        if let value = details.avgCadence { session.avgCadence = value }
        if let value = details.maxCadence { session.maxCadence = value }
        if let value = details.avgStrideLength { session.avgStrideLength = value }
        if let value = details.verticalOscillation { session.verticalOscillation = value }
        if let value = details.groundContactTime { session.groundContactTime = value }
        if let value = details.avgPower { session.avgPower = value }
        if let value = details.maxPower { session.maxPower = value }
        if session.locations.isEmpty,
           let routeData = details.routeData,
           !routeData.isEmpty {
            session.locations = routeData
        }
        if let elevation = details.elevation {
            if session.totalAscent == nil { session.totalAscent = elevation.ascent }
            if session.totalDescent == nil { session.totalDescent = elevation.descent }
            if session.minElevation == nil { session.minElevation = elevation.min }
            if session.maxElevation == nil { session.maxElevation = elevation.max }
        }
    }

    private static func reconcileDeletions(
        _ deletedUUIDs: [String],
        items: [CardioWorkoutInboxItem],
        sessions: [RunningSession],
        context: ModelContext
    ) {
        let deletedSet = Set(deletedUUIDs)
        guard !deletedSet.isEmpty else { return }

        for item in items {
            let known = knownHealthUUIDs(for: item)
            let remaining = known.subtracting(deletedSet)
            guard remaining.count != known.count else { continue }

            if remaining.isEmpty {
                item.healthDeletionObservedAt = item.healthDeletionObservedAt ?? Date()
            } else {
                setKnownHealthUUIDs(remaining, on: item)
                if let metricUUID = item.metricSourceHealthWorkoutUUID,
                   !remaining.contains(metricUUID) {
                    item.metricSourceHealthWorkoutUUID = nil
                    item.metricSourceName = nil
                    item.metricSourceBundleIdentifier = nil
                }
                item.healthDeletionObservedAt = nil
            }
        }

        // Re-apply each surviving linked inbox identity after pruning deleted
        // aliases. This keeps a replacement as the metric source even when its
        // superseded UUID is deleted in the same anchored-query page.
        for item in items where item.healthDeletionObservedAt == nil {
            guard item.status == .linked,
                  let linkedID = item.linkedRunningSessionID,
                  let session = sessions.first(where: { $0.id == linkedID }) else {
                continue
            }
            applyHealthIdentity(from: item, to: session)
        }

        for session in sessions {
            if let uuid = session.healthWorkoutUUID,
               deletedSet.contains(uuid) {
                session.healthWorkoutUUID = nil
            }
            if let uuid = session.metricSourceHealthWorkoutUUID,
               deletedSet.contains(uuid) {
                session.metricSourceHealthWorkoutUUID = nil
            }
            let remaining = knownHealthUUIDs(for: session).subtracting(deletedSet)
            session.linkedHealthWorkoutUUIDsRaw = remaining.sorted().joined(separator: "\n")
        }
    }

    private static func expireReplacementTombstones(
        items: [CardioWorkoutInboxItem],
        sessions: [RunningSession],
        context: ModelContext
    ) {
        let cutoff = Date().addingTimeInterval(-replacementGracePeriod)
        for item in items {
            guard let deletedAt = item.healthDeletionObservedAt,
                  deletedAt <= cutoff else { continue }
            if let linkedID = item.linkedRunningSessionID,
               let session = sessions.first(where: { $0.id == linkedID }),
               session.metricSourceHealthWorkoutUUID == item.healthWorkoutUUID {
                session.metricSourceHealthWorkoutUUID = nil
            }
            context.delete(item)
        }
    }

    private static func sameLogicalWorkout(
        _ first: CardioWorkoutInboxItem,
        _ second: CardioWorkoutInboxItem
    ) -> Bool {
        let firstSource = stableSourceIdentity(
            name: first.sourceName,
            bundleIdentifier: first.sourceBundleIdentifier
        )
        let secondSource = stableSourceIdentity(
            name: second.sourceName,
            bundleIdentifier: second.sourceBundleIdentifier
        )
        let sameSource = !firstSource.isEmpty && firstSource == secondSource
        let firstSync = normalized(first.healthSyncIdentifier)
        let secondSync = normalized(second.healthSyncIdentifier)
        let firstExternal = normalized(first.healthExternalUUID)
        let secondExternal = normalized(second.healthExternalUUID)

        if sameSource {
            if !firstSync.isEmpty, !secondSync.isEmpty, firstSync != secondSync {
                return false
            }
            if !firstExternal.isEmpty,
               !secondExternal.isEmpty,
               firstExternal != secondExternal {
                return false
            }
            if !firstSync.isEmpty && firstSync == secondSync { return true }
            if !firstExternal.isEmpty && firstExternal == secondExternal {
                return true
            }
        }

        return first.activityType == second.activityType &&
            abs(first.startDate.timeIntervalSince(second.startDate)) <= fingerprintDateTolerance &&
            abs(first.endDate.timeIntervalSince(second.endDate)) <= fingerprintDateTolerance &&
            abs(first.duration - second.duration) <= fingerprintDurationTolerance &&
            (first.distanceMeters <= 0 || second.distanceMeters <= 0 ||
                abs(first.distanceMeters - second.distanceMeters) <= fingerprintDistanceToleranceMeters)
    }

    private static func merge(
        _ candidate: CardioWorkoutInboxItem,
        into item: CardioWorkoutInboxItem
    ) {
        var versionLedger = syncVersionLedger(for: item)
        recordSyncVersion(
            sourceName: item.sourceName,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            syncIdentifier: item.healthSyncIdentifier,
            externalUUID: item.healthExternalUUID,
            version: item.healthSyncVersion,
            in: &versionLedger
        )
        let itemIdentityKeys = syncVersionIdentityKeys(
            sourceName: item.sourceName,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            syncIdentifier: item.healthSyncIdentifier,
            externalUUID: item.healthExternalUUID
        )
        let candidateIdentityKeys = syncVersionIdentityKeys(
            sourceName: candidate.sourceName,
            sourceBundleIdentifier: candidate.sourceBundleIdentifier,
            syncIdentifier: candidate.healthSyncIdentifier,
            externalUUID: candidate.healthExternalUUID
        )
        let previousMaximum = candidateIdentityKeys.compactMap {
            versionLedger[$0]
        }.max()
        let candidateIsOlderRevision = previousMaximum != nil &&
            (candidate.healthSyncVersion == nil ||
                candidate.healthSyncVersion! < previousMaximum!)
        item.healthSyncVersionsByStableIdentityRaw =
            encodedSyncVersionLedger(versionLedger)

        // Anchored queries may replay an older representation after a newer
        // replacement. Ignore it completely so it cannot overwrite metrics or
        // clear the replacement tombstone for the current record.
        guard !candidateIsOlderRevision else { return }

        let candidateSharesPrimaryIdentity =
            !itemIdentityKeys.isDisjoint(with: candidateIdentityKeys)
        let candidateIsNewerRevision = candidateSharesPrimaryIdentity &&
            candidate.healthSyncVersion != nil &&
            (item.healthSyncVersion == nil ||
                candidate.healthSyncVersion! > item.healthSyncVersion!)
        recordSyncVersion(
            sourceName: candidate.sourceName,
            sourceBundleIdentifier: candidate.sourceBundleIdentifier,
            syncIdentifier: candidate.healthSyncIdentifier,
            externalUUID: candidate.healthExternalUUID,
            version: candidate.healthSyncVersion,
            in: &versionLedger
        )
        item.healthSyncVersionsByStableIdentityRaw =
            encodedSyncVersionLedger(versionLedger)
        var identifiers = knownHealthUUIDs(for: item)
        identifiers.formUnion(knownHealthUUIDs(for: candidate))
        let candidateHasRicherHeartRate = item.avgHeartRate == nil && candidate.avgHeartRate != nil
        setKnownHealthUUIDs(
            identifiers,
            on: item,
            preferredPrimary: candidateIsNewerRevision ||
                item.healthDeletionObservedAt != nil
                ? candidate.healthWorkoutUUID
                : item.healthWorkoutUUID
        )

        if candidateIsNewerRevision ||
            item.healthDeletionObservedAt != nil {
            item.startDate = candidate.startDate
            item.endDate = candidate.endDate
            item.activityType = candidate.activityType
            item.distanceMeters = candidate.distanceMeters
            item.duration = candidate.duration
            item.sourceName = candidate.sourceName
            item.sourceBundleIdentifier = candidate.sourceBundleIdentifier
            item.healthSyncIdentifier = candidate.healthSyncIdentifier
            item.healthSyncVersion = candidate.healthSyncVersion
            item.healthExternalUUID = candidate.healthExternalUUID
        }
        if candidateIsNewerRevision || item.calories == nil,
           let value = candidate.calories {
            item.calories = value
        }
        if candidateIsNewerRevision || candidateHasRicherHeartRate {
            if let value = candidate.avgHeartRate { item.avgHeartRate = value }
            if let value = candidate.maxHeartRate { item.maxHeartRate = value }
            if let value = candidate.minHeartRate { item.minHeartRate = value }
            if candidate.avgHeartRate != nil {
                item.metricSourceHealthWorkoutUUID =
                    candidate.metricSourceHealthWorkoutUUID ??
                    candidate.healthWorkoutUUID
                item.metricSourceName =
                    candidate.metricSourceName ?? candidate.sourceName
                item.metricSourceBundleIdentifier =
                    candidate.metricSourceBundleIdentifier ??
                    candidate.sourceBundleIdentifier
            }
        }
        item.healthDeletionObservedAt = nil
    }

    private static func recordCurrentSyncVersion(
        on item: CardioWorkoutInboxItem
    ) {
        var ledger = syncVersionLedger(for: item)
        recordSyncVersion(
            sourceName: item.sourceName,
            sourceBundleIdentifier: item.sourceBundleIdentifier,
            syncIdentifier: item.healthSyncIdentifier,
            externalUUID: item.healthExternalUUID,
            version: item.healthSyncVersion,
            in: &ledger
        )
        item.healthSyncVersionsByStableIdentityRaw =
            encodedSyncVersionLedger(ledger)
    }

    private static func recordSyncVersion(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        syncIdentifier: String?,
        externalUUID: String?,
        version: Int?,
        in ledger: inout [String: Int]
    ) {
        guard let version else { return }
        let keys = syncVersionIdentityKeys(
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            syncIdentifier: syncIdentifier,
            externalUUID: externalUUID
        )
        for key in keys {
            ledger[key] = max(ledger[key] ?? Int.min, version)
        }
    }

    private static func syncVersionIdentityKeys(
        sourceName: String?,
        sourceBundleIdentifier: String?,
        syncIdentifier: String?,
        externalUUID: String?
    ) -> Set<String> {
        let source = stableSourceIdentity(
            name: sourceName,
            bundleIdentifier: sourceBundleIdentifier
        )
        guard !source.isEmpty else { return [] }

        var keys = Set<String>()
        let sync = normalized(syncIdentifier)
        if !sync.isEmpty {
            keys.insert(stableIdentityKey(source: source, kind: "sync", value: sync))
        }
        let external = normalized(externalUUID)
        if !external.isEmpty {
            keys.insert(
                stableIdentityKey(
                    source: source,
                    kind: "external",
                    value: external
                )
            )
        }
        return keys
    }

    private static func stableSourceIdentity(
        name: String?,
        bundleIdentifier: String?
    ) -> String {
        let bundle = normalized(bundleIdentifier)
        return bundle.isEmpty ? normalized(name) : bundle
    }

    private static func stableIdentityKey(
        source: String,
        kind: String,
        value: String
    ) -> String {
        [source, kind, value]
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }

    private static func syncVersionLedger(
        for item: CardioWorkoutInboxItem
    ) -> [String: Int] {
        guard let data = item.healthSyncVersionsByStableIdentityRaw
            .data(using: .utf8),
              !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private static func encodedSyncVersionLedger(
        _ ledger: [String: Int]
    ) -> String {
        guard !ledger.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ledger) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func isConfidentMatch(
        _ item: CardioWorkoutInboxItem,
        _ session: RunningSession
    ) -> Bool {
        guard item.activityType == session.activityType else { return false }
        let endDifference = abs(session.date.timeIntervalSince(item.endDate))
        let durationDifference = abs(session.duration - item.duration)
        let start = session.date.addingTimeInterval(-session.duration)
        let startDifference = abs(start.timeIntervalSince(item.startDate))
        let sessionMeters = HealthKitManager.metersFor(
            distance: session.distance,
            unit: session.distanceUnit
        )
        let distanceDifference = abs(sessionMeters - item.distanceMeters)

        guard endDifference <= 10 * 60,
              startDifference <= 10 * 60,
              durationDifference <= max(5 * 60, item.duration * 0.2) else {
            return false
        }
        if sessionMeters > 0 && item.distanceMeters > 0 {
            return distanceDifference <= max(400, item.distanceMeters * 0.2)
        }
        return true
    }

    private static func matchScore(
        _ item: CardioWorkoutInboxItem,
        _ session: RunningSession
    ) -> Double {
        let sessionMeters = HealthKitManager.metersFor(
            distance: session.distance,
            unit: session.distanceUnit
        )
        let endMinutes = abs(session.date.timeIntervalSince(item.endDate)) / 60
        let durationMinutes = abs(session.duration - item.duration) / 60
        let distanceHundreds = abs(sessionMeters - item.distanceMeters) / 100
        return endMinutes + durationMinutes + min(distanceHundreds, 20)
    }

    static func knownHealthUUIDs(for item: CardioWorkoutInboxItem) -> Set<String> {
        var identifiers = Set(
            item.alternateHealthWorkoutUUIDsRaw
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        if !item.healthWorkoutUUID.isEmpty {
            identifiers.insert(item.healthWorkoutUUID)
        }
        return identifiers
    }

    static func knownHealthUUIDs(for session: RunningSession) -> Set<String> {
        var identifiers = Set(
            session.linkedHealthWorkoutUUIDsRaw
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
        )
        if let uuid = session.healthWorkoutUUID, !uuid.isEmpty {
            identifiers.insert(uuid)
        }
        if let uuid = session.metricSourceHealthWorkoutUUID, !uuid.isEmpty {
            identifiers.insert(uuid)
        }
        return identifiers
    }

    private static func setKnownHealthUUIDs(
        _ identifiers: Set<String>,
        on item: CardioWorkoutInboxItem,
        preferredPrimary: String? = nil
    ) {
        let cleaned = Set(identifiers.filter { !$0.isEmpty })
        guard !cleaned.isEmpty else { return }
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

    private static func addHealthUUID(_ uuid: String, to session: RunningSession) {
        guard !uuid.isEmpty else { return }
        var identifiers = knownHealthUUIDs(for: session)
        identifiers.insert(uuid)
        session.linkedHealthWorkoutUUIDsRaw = identifiers.sorted().joined(separator: "\n")
    }

    private static func activityKey(for type: HKWorkoutActivityType) -> String? {
        switch type {
        case .running: return "running"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stairClimbing"
        default: return nil
        }
    }

    static func activityDisplayName(for key: String) -> String {
        switch key {
        case "running": return "Run"
        case "walking": return "Walk"
        case "hiking": return "Hike"
        case "cycling": return "Ride"
        case "rowing": return "Row"
        case "elliptical": return "Elliptical"
        case "stairClimbing", "stairStepper": return "Stair Climb"
        default: return "Cardio Activity"
        }
    }

    static func activityIcon(for key: String) -> String {
        switch key {
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "figure.outdoor.cycle"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.elliptical"
        case "stairClimbing", "stairStepper": return "figure.stair.stepper"
        default: return "figure.run"
        }
    }

    private static var emptyHeartRateSummary: HealthKitManager.WorkoutHeartRateSummary {
        .init(average: nil, maximum: nil, minimum: nil)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func normalizedMetadataString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func metadataInt(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private static func downsample(
        _ locations: [CLLocation],
        maxPoints: Int = 1_200
    ) -> [CLLocation] {
        guard locations.count > maxPoints else { return locations }
        let strideLength = max(1, locations.count / maxPoints)
        var reduced = Swift.stride(
            from: 0,
            to: locations.count,
            by: strideLength
        ).map { locations[$0] }
        if let last = locations.last,
           reduced.last?.timestamp != last.timestamp {
            reduced.append(last)
        }
        return reduced
    }
}
