import Foundation
import HealthKit
import CoreLocation

extension Notification.Name {
    static let healthKitWorkoutsDidChange = Notification.Name("healthKitWorkoutsDidChange")
}

private let workoutAnchorDefaultsKey = "healthKit.cardioWorkoutAnchor"
private let strengthWorkoutAnchorDefaultsKey = "healthKit.strengthWorkoutAnchor"

@MainActor
final class HealthKitManager: ObservableObject {
    struct CardioWorkoutChanges {
        let added: [HKWorkout]
        let deletedUUIDs: [String]
        let newAnchor: HKQueryAnchor?
    }

    struct SleepScoreBreakdown {
        let totalScore: Int
        let durationScore: Int
        let bedtimeScore: Int
        let interruptionScore: Int
        let sleepDurationSeconds: TimeInterval
    }

    private struct SleepSessionSummary {
        let start: Date
        let end: Date
        let asleepSeconds: TimeInterval
    }

    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    private var workoutObserverQuery: HKObserverQuery?
    private let supportedCardioTypes: Set<HKWorkoutActivityType> = [
        .running,
        .walking,
        .hiking,
        .cycling,
        .rowing,
        .elliptical,
        .stairClimbing
    ]

    // Non-cardio wearable workouts routed to the workout inbox (cardio auto-imports as runs)
    nonisolated static let supportedStrengthTypes: Set<HKWorkoutActivityType> = [
        .traditionalStrengthTraining,
        .functionalStrengthTraining,
        .highIntensityIntervalTraining,
        .coreTraining,
        .crossTraining,
        .yoga,
        .pilates,
        .flexibility,
        .martialArts
    ]

    // MARK: - Types
    private let readTypes: Set<HKObjectType> = {
        var set = Set<HKObjectType>()
        set.insert(HKObjectType.workoutType())
        set.insert(HKObjectType.quantityType(forIdentifier: .heartRate)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
        if let t = HKObjectType.quantityType(forIdentifier: .distanceCycling) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceRowing) { set.insert(t) }
        set.insert(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .stepCount)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .vo2Max)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .runningPower)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .runningSpeed)!)
        if let t = HKObjectType.quantityType(forIdentifier: .runningStrideLength) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .runningGroundContactTime) { set.insert(t) }
        // Read workout routes so we can render maps for Apple Watch runs
        set.insert(HKSeriesType.workoutRoute())

        // Vitals snapshot types
        set.insert(HKObjectType.quantityType(forIdentifier: .restingHeartRate)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .bodyTemperature)!)
        set.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        
        // Profile characteristics
        set.insert(HKObjectType.quantityType(forIdentifier: .height)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .bodyMass)!)
        set.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
        set.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)

        return set
    }()

    private let writeTypes: Set<HKSampleType> = {
        var set = Set<HKSampleType>()
        set.insert(HKObjectType.workoutType())
        set.insert(HKSeriesType.workoutRoute())
        set.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
        if let t = HKObjectType.quantityType(forIdentifier: .distanceCycling) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceRowing) { set.insert(t) }
        set.insert(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)
        return set
    }()

    @Published private(set) var isAuthorized = false

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        await refreshAuthorizationState()
    }

    func refreshAuthorizationState() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }
        isAuthorized = authorizationStatusOK()
    }

    func authorizationRequiresRequest() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            let status = try await authorizationRequestStatus()
            switch status {
            case .shouldRequest, .unknown:
                return true
            case .unnecessary:
                return false
            @unknown default:
                return true
            }
        } catch {
            return false
        }
    }

    func persistCardioWorkoutAnchor(_ anchor: HKQueryAnchor?) {
        storeWorkoutAnchor(anchor)
    }

    func persistStrengthWorkoutAnchor(_ anchor: HKQueryAnchor?) {
        storeAnchor(anchor, key: strengthWorkoutAnchorDefaultsKey)
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: writeTypes, read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }
    }

    private var requiredWorkoutWriteTypes: [HKSampleType] {
        var types: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        if let cycling = HKObjectType.quantityType(forIdentifier: .distanceCycling) {
            types.append(cycling)
        }
        if let rowing = HKObjectType.quantityType(forIdentifier: .distanceRowing) {
            types.append(rowing)
        }
        return types
    }

    private func authorizationStatusOK() -> Bool {
        requiredWorkoutWriteTypes.allSatisfy { sampleType in
            healthStore.authorizationStatus(for: sampleType) == .sharingAuthorized
        }
    }

    private func cardioWorkoutsPredicate() -> NSPredicate {
        let predicates = supportedCardioTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }

    nonisolated private func storedWorkoutAnchor() -> HKQueryAnchor? {
        storedAnchor(key: workoutAnchorDefaultsKey)
    }

    nonisolated private func storeWorkoutAnchor(_ anchor: HKQueryAnchor?) {
        storeAnchor(anchor, key: workoutAnchorDefaultsKey)
    }

    nonisolated private func storedAnchor(key: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    nonisolated private func storeAnchor(_ anchor: HKQueryAnchor?, key: String) {
        guard let anchor else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Live Workout Change Observation
    func startWorkoutChangeObservationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard workoutObserverQuery == nil else { return }

        let sampleType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard self != nil else { return }
            guard error == nil else { return }

            UserDefaults.standard.set(true, forKey: "runsPendingHealthImport")
            NotificationCenter.default.post(name: .healthKitWorkoutsDidChange, object: nil)
        }

        workoutObserverQuery = query
        healthStore.execute(query)

        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
    }

    func stopWorkoutChangeObservation() {
        guard let query = workoutObserverQuery else { return }
        healthStore.stop(query)
        workoutObserverQuery = nil
    }

    // MARK: - Save Workout
    func saveRunWorkout(start: Date, end: Date, distanceMeters: Double, energyBurned: Double? = nil, activityType: String = "running") async throws -> HKWorkout {
        let store = self.healthStore

        // Prepare quantities
        let distanceType: HKQuantityType = {
            switch activityType {
            case "cycling": return HKQuantityType.quantityType(forIdentifier: .distanceCycling)!
            case "rowing": return HKQuantityType.quantityType(forIdentifier: .distanceRowing)!
            default: return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            }
        }()
        let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: distanceMeters)
        let distanceSample = HKQuantitySample(type: distanceType,
                                              quantity: distanceQuantity,
                                              start: start,
                                              end: end)

        var additionalSamples: [HKSample] = [distanceSample]
        if let energyBurned {
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let energyQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: energyBurned)
            let energySample = HKQuantitySample(type: energyType,
                                                quantity: energyQuantity,
                                                start: start,
                                                end: end)
            additionalSamples.append(energySample)
        }

        // Map activity type to HKWorkoutActivityType
        let hkActivityType: HKWorkoutActivityType
        switch activityType {
        case "walking": hkActivityType = .walking
        case "hiking": hkActivityType = .hiking
        case "cycling": hkActivityType = .cycling
        case "rowing": hkActivityType = .rowing
        default: hkActivityType = .running
        }

        // Define the workout configuration
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = hkActivityType
        configuration.locationType = .outdoor

        // Build the workout using HKWorkoutBuilder (iOS 17+ recommended)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        // Add samples before ending collection so the builder lifecycle stays consistent.
        try await builder.beginCollection(at: start)
        try await builder.addSamples(additionalSamples)
        try await builder.endCollection(at: end)

        // Finish and save the workout
        let workout: HKWorkout = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in
            builder.finishWorkout { workout, error in
                if let error = error { continuation.resume(throwing: error); return }
                guard let workout = workout else {
                    continuation.resume(throwing: NSError(domain: "HealthKitManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Workout builder did not return a workout"]))
                    return
                }
                continuation.resume(returning: workout)
            }
        }

        return workout
    }

    func saveRunRoute(_ route: [CLLocation], for workout: HKWorkout) async throws {
        guard !route.isEmpty else { return }

        let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            routeBuilder.insertRouteData(route) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                routeBuilder.finishRoute(with: workout, metadata: nil) { _, finishError in
                    if let finishError {
                        continuation.resume(throwing: finishError)
                        return
                    }
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Steps
    func todayStepCount() async throws -> Int {
        let store = self.healthStore
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error { continuation.resume(throwing: error); return }
                let value = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(value))
            }
            store.execute(query)
        }
    }

    // MARK: - Queries
    func fetchRecentRuns(limit: Int = 50) async throws -> [HKWorkout] {
        let predicate = cardioWorkoutsPredicate()
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts.filter { self.supportedCardioTypes.contains($0.workoutActivityType) })
            }
            self.healthStore.execute(query)
        }
    }

    func fetchCardioWorkoutChanges(resetAnchor: Bool = false, limit: Int = HKObjectQueryNoLimit) async throws -> CardioWorkoutChanges {
        let anchor = resetAnchor ? nil : storedWorkoutAnchor()
        let predicate = cardioWorkoutsPredicate()

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: .workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                let added = workouts.filter { self.supportedCardioTypes.contains($0.workoutActivityType) }
                let deletedUUIDs = (deleted ?? []).map { $0.uuid.uuidString }
                continuation.resume(
                    returning: CardioWorkoutChanges(
                        added: added,
                        deletedUUIDs: deletedUUIDs,
                        newAnchor: newAnchor
                    )
                )
            }
            self.healthStore.execute(query)
        }
    }

    /// Anchored fetch of non-cardio wearable workouts (strength, HIIT, yoga, …) for the inbox.
    /// `since` bounds the first scan; subsequent calls advance via the stored anchor.
    func fetchStrengthWorkoutChanges(since: Date, resetAnchor: Bool = false, limit: Int = HKObjectQueryNoLimit) async throws -> CardioWorkoutChanges {
        let anchor = resetAnchor ? nil : storedAnchor(key: strengthWorkoutAnchorDefaultsKey)
        let typePredicates = Self.supportedStrengthTypes.map { HKQuery.predicateForWorkouts(with: $0) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: typePredicates),
            HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        ])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: .workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                let added = workouts.filter { Self.supportedStrengthTypes.contains($0.workoutActivityType) }
                let deletedUUIDs = (deleted ?? []).map { $0.uuid.uuidString }
                continuation.resume(
                    returning: CardioWorkoutChanges(
                        added: added,
                        deletedUUIDs: deletedUUIDs,
                        newAnchor: newAnchor
                    )
                )
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Route loading
    func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        // Fetch HKWorkoutRoute samples associated with the workout, then stream all locations.
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: routeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let results = (samples as? [HKWorkoutRoute]) ?? []
                continuation.resume(returning: results)
            }
            self.healthStore.execute(query)
        }

        var all: [CLLocation] = []
        for route in routes {
            var chunk: [CLLocation] = []
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error = error { continuation.resume(throwing: error); return }
                    if let locations { chunk.append(contentsOf: locations) }
                    if done { continuation.resume(returning: ()) }
                }
                self.healthStore.execute(query)
            }
            all.append(contentsOf: chunk)
        }
        return all
    }

    func routeLocationsForUUID(_ uuidString: String) async throws -> [CLLocation] {
        let runs = try await fetchRecentRuns(limit: 100)
        if let w = runs.first(where: { $0.uuid.uuidString == uuidString }) {
            return try await routeLocations(for: w)
        }
        return []
    }

    // MARK: - Active Energy for a Workout
    func activeEnergyKilocalories(for workout: HKWorkout) async throws -> Double {
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }

    // MARK: - Workout Metrics
    
    /// Fetch average heart rate for a workout
    func averageHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Fetch maximum heart rate for a workout
    func maxHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteMax) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Fetch minimum heart rate for a workout
    func minHeartRate(for workout: HKWorkout) async throws -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteMin) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.minimumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Fetch average cadence in steps/minute.
    /// HealthKit does not provide a dedicated running cadence type, so we derive cadence from step samples.
    func averageCadence(for workout: HKWorkout) async throws -> Double? {
        let stats = try await cadenceStats(for: workout)
        return stats.average
    }
    
    /// Fetch maximum cadence in steps/minute.
    func maxCadence(for workout: HKWorkout) async throws -> Double? {
        let stats = try await cadenceStats(for: workout)
        return stats.maximum
    }

    private func cadenceStats(for workout: HKWorkout) async throws -> (average: Double?, maximum: Double?) {
        switch workout.workoutActivityType {
        case .running, .walking, .hiking:
            break
        default:
            return (nil, nil)
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return (nil, nil)
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: stepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let stepSamples = (samples as? [HKQuantitySample]) ?? []
                var totalSteps = 0.0
                var totalDuration = 0.0
                var maxCadence = 0.0

                for sample in stepSamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    guard duration > 0 else { continue }

                    let steps = sample.quantity.doubleValue(for: .count())
                    let cadence = (steps / duration) * 60.0

                    totalSteps += steps
                    totalDuration += duration
                    maxCadence = max(maxCadence, cadence)
                }

                guard totalDuration > 0 else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let averageCadence = (totalSteps / totalDuration) * 60.0
                continuation.resume(returning: (averageCadence, maxCadence > 0 ? maxCadence : nil))
            }
            self.healthStore.execute(query)
        }
    }

    /// Fetch average stride length in meters.
    func averageStrideLength(for workout: HKWorkout) async throws -> Double? {
        guard let strideType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: strideType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.averageQuantity()?.doubleValue(for: .meter())
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }

    /// Fetch average vertical oscillation in centimeters.
    func averageVerticalOscillation(for workout: HKWorkout) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let meters = stats?.averageQuantity()?.doubleValue(for: .meter())
                continuation.resume(returning: meters.map { $0 * 100.0 })
            }
            self.healthStore.execute(query)
        }
    }

    /// Fetch average ground contact time in milliseconds.
    func averageGroundContactTime(for workout: HKWorkout) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let seconds = stats?.averageQuantity()?.doubleValue(for: .second())
                continuation.resume(returning: seconds.map { $0 * 1000.0 })
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Fetch average running power for a workout
    func averagePower(for workout: HKWorkout) async throws -> Double? {
        // Running power requires compatible devices (Stryd, some Garmin watches, etc.)
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: powerType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.averageQuantity()?.doubleValue(for: .watt())
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Fetch maximum running power for a workout
    func maxPower(for workout: HKWorkout) async throws -> Double? {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower) else { return nil }
        let predicate = HKQuery.predicateForObjects(from: workout)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: powerType, quantitySamplePredicate: predicate, options: .discreteMax) { _, stats, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.maximumQuantity()?.doubleValue(for: .watt())
                continuation.resume(returning: value)
            }
            self.healthStore.execute(query)
        }
    }
    
    // MARK: - Delete matching run
    func deleteRun(uuidString: String?, endDate: Date, duration: TimeInterval, distanceMeters: Double? = nil) async throws {
        let runs = try await fetchRecentRuns(limit: 50)
        if let uuidString, let target = runs.first(where: { $0.uuid.uuidString == uuidString }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.delete(target) { ok, error in
                    if let error = error { continuation.resume(throwing: error); return }
                    continuation.resume(returning: ())
                }
            }
            return
        }
        // Choose a workout which end date and duration are close, and (if provided) distance close
        var best: HKWorkout? = nil
        var bestScore: Double = .greatestFiniteMagnitude
        for w in runs where supportedCardioTypes.contains(w.workoutActivityType) {
            let dt = abs(w.endDate.timeIntervalSince(endDate))
            let ddur = abs(w.duration - duration)
            var score = dt + ddur
            if let distanceMeters {
                let dm = abs((w.totalDistance?.doubleValue(for: .meter()) ?? 0) - distanceMeters)
                score += min(dm / 10.0, 600) // scale distance influence
            }
            if score < bestScore { bestScore = score; best = w }
        }
        guard let workout = best, bestScore < 300 /* 5 min tolerance */ else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.delete(workout) { ok, error in
                if let error = error { continuation.resume(throwing: error); return }
                continuation.resume(returning: ())
            }
        }
    }

    // MARK: - Vitals Helpers

    func latestQuantitySample(for id: HKQuantityTypeIdentifier) async throws -> HKQuantitySample? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let pred = HKQuery.predicateForSamples(withStart: .distantPast, end: Date(), options: [])

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(q)
        }
    }

    func todaySum(for id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, stats, err in
                if let err = err { cont.resume(throwing: err); return }
                let val = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                cont.resume(returning: val)
            }
            healthStore.execute(q)
        }
    }

    func lastNightSleepDuration() async throws -> TimeInterval {
        guard let breakdown = try await lastNightSleepScoreBreakdown() else { return 0 }
        return breakdown.sleepDurationSeconds
    }

    func lastNightSleepScoreBreakdown() async throws -> SleepScoreBreakdown? {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let lookbackStart = calendar.date(byAdding: .day, value: -14, to: todayStart)?
            .addingTimeInterval(-6 * 3600) else { return nil }

        let samples = try await fetchSleepSamples(from: lookbackStart, to: now)
        guard !samples.isEmpty else { return nil }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        ]
        let inBedValues: Set<Int> = [HKCategoryValueSleepAnalysis.inBed.rawValue]
        let awakeValues: Set<Int> = [HKCategoryValueSleepAnalysis.awake.rawValue]

        let mergedAsleep = mergeIntervals(intervals: intervals(from: samples, matching: asleepValues))
        guard !mergedAsleep.isEmpty else { return nil }

        let sessions = detectSleepSessions(fromMergedAsleepIntervals: mergedAsleep)
        guard !sessions.isEmpty else { return nil }

        let lastNightCandidates = sessions.filter { $0.end >= todayStart }
        guard let lastNightSession = lastNightCandidates.max(by: { $0.asleepSeconds < $1.asleepSeconds }) else { return nil }

        let mergedInBed = mergeIntervals(intervals: intervals(from: samples, matching: inBedValues))
        let mergedAwake = mergeIntervals(intervals: intervals(from: samples, matching: awakeValues))

        let bedtime = inferredBedtime(for: lastNightSession, inBedIntervals: mergedInBed) ?? lastNightSession.start
        let awakeSeconds = totalOverlapDuration(of: mergedAwake, with: (start: lastNightSession.start, end: lastNightSession.end))
        let interruptionCount = countInterruptions(intervals: mergedAwake, in: (start: lastNightSession.start, end: lastNightSession.end))

        let bedtimeMinutes = minutesSinceMidnight(for: bedtime, calendar: calendar)
        let historicalBedtimes = sessions
            .filter { $0.end < todayStart }
            .sorted { $0.end > $1.end }
            .prefix(7)
            .map { minutesSinceMidnight(for: $0.start, calendar: calendar) }

        let bedtimeDeviation: Double = {
            guard let baseline = circularMeanMinute(of: Array(historicalBedtimes)) else { return 0 }
            return circularMinutesDistance(bedtimeMinutes, baseline)
        }()

        let durationScore = durationPoints(forAsleepSeconds: lastNightSession.asleepSeconds)
        let bedtimeScore = bedtimePoints(forDeviationMinutes: bedtimeDeviation)
        let interruptionScore = interruptionPoints(interruptionCount: interruptionCount, awakeSeconds: awakeSeconds)
        let total = max(0, min(100, durationScore + bedtimeScore + interruptionScore))

        return SleepScoreBreakdown(
            totalScore: total,
            durationScore: durationScore,
            bedtimeScore: bedtimeScore,
            interruptionScore: interruptionScore,
            sleepDurationSeconds: lastNightSession.asleepSeconds
        )
    }

    private func fetchSleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    nonisolated private func intervals(from samples: [HKCategorySample], matching values: Set<Int>) -> [(start: Date, end: Date)] {
        samples
            .filter { values.contains($0.value) && $0.endDate > $0.startDate }
            .map { ($0.startDate, $0.endDate) }
    }

    nonisolated private func mergeIntervals(intervals: [(start: Date, end: Date)], allowingGap gap: TimeInterval = 0) -> [(start: Date, end: Date)] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }

        var merged: [(start: Date, end: Date)] = []
        var current = sorted[0]

        for interval in sorted.dropFirst() {
            if interval.start <= current.end.addingTimeInterval(gap) {
                current.end = max(current.end, interval.end)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    nonisolated private func detectSleepSessions(fromMergedAsleepIntervals intervals: [(start: Date, end: Date)]) -> [SleepSessionSummary] {
        guard !intervals.isEmpty else { return [] }
        let maxGap: TimeInterval = 2 * 3600

        var sessions: [SleepSessionSummary] = []
        var sessionStart = intervals[0].start
        var sessionEnd = intervals[0].end
        var asleepTotal = intervals[0].end.timeIntervalSince(intervals[0].start)

        for interval in intervals.dropFirst() {
            if interval.start <= sessionEnd.addingTimeInterval(maxGap) {
                asleepTotal += interval.end.timeIntervalSince(interval.start)
                sessionEnd = max(sessionEnd, interval.end)
            } else {
                sessions.append(SleepSessionSummary(start: sessionStart, end: sessionEnd, asleepSeconds: asleepTotal))
                sessionStart = interval.start
                sessionEnd = interval.end
                asleepTotal = interval.end.timeIntervalSince(interval.start)
            }
        }

        sessions.append(SleepSessionSummary(start: sessionStart, end: sessionEnd, asleepSeconds: asleepTotal))
        return sessions
    }

    nonisolated private func totalOverlapDuration(of intervals: [(start: Date, end: Date)], with window: (start: Date, end: Date)) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            let overlapStart = max(interval.start, window.start)
            let overlapEnd = min(interval.end, window.end)
            guard overlapEnd > overlapStart else { return total }
            return total + overlapEnd.timeIntervalSince(overlapStart)
        }
    }

    nonisolated private func countInterruptions(intervals: [(start: Date, end: Date)], in window: (start: Date, end: Date)) -> Int {
        intervals.reduce(0) { count, interval in
            let overlapStart = max(interval.start, window.start)
            let overlapEnd = min(interval.end, window.end)
            return overlapEnd.timeIntervalSince(overlapStart) >= 60 ? (count + 1) : count
        }
    }

    nonisolated private func inferredBedtime(for session: SleepSessionSummary, inBedIntervals: [(start: Date, end: Date)]) -> Date? {
        let windowStart = session.start.addingTimeInterval(-3 * 3600)
        let overlapping = inBedIntervals.filter { interval in
            interval.end > windowStart && interval.start < session.end
        }
        return overlapping.map(\.start).min()
    }

    nonisolated private func durationPoints(forAsleepSeconds seconds: TimeInterval) -> Int {
        let hours = max(0, seconds / 3600)
        let raw = min(1.0, hours / 8.0) * 50.0
        return Int(raw.rounded())
    }

    nonisolated private func bedtimePoints(forDeviationMinutes deviation: Double) -> Int {
        let penalty = min(30.0, max(0, deviation) / 9.0)
        return max(0, Int((30.0 - penalty).rounded()))
    }

    nonisolated private func interruptionPoints(interruptionCount: Int, awakeSeconds: TimeInterval) -> Int {
        let awakeMinutes = max(0, awakeSeconds / 60.0)
        let penalty = Double(interruptionCount) * 1.8 + (awakeMinutes / 12.0)
        let raw = 20.0 - penalty
        return max(0, min(20, Int(raw.rounded())))
    }

    nonisolated private func minutesSinceMidnight(for date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hours = Double(components.hour ?? 0)
        let minutes = Double(components.minute ?? 0)
        return hours * 60.0 + minutes
    }

    nonisolated private func circularMeanMinute(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let full = 24.0 * 60.0

        let vectors = values.map { value -> (sin: Double, cos: Double) in
            let angle = (value / full) * 2.0 * .pi
            return (sin(angle), cos(angle))
        }

        let sumSin = vectors.reduce(0.0) { $0 + $1.sin }
        let sumCos = vectors.reduce(0.0) { $0 + $1.cos }
        var angle = atan2(sumSin, sumCos)
        if angle < 0 { angle += 2.0 * .pi }
        return (angle / (2.0 * .pi)) * full
    }

    nonisolated private func circularMinutesDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let full = 24.0 * 60.0
        let raw = abs(lhs - rhs).truncatingRemainder(dividingBy: full)
        return min(raw, full - raw)
    }
    
    // MARK: - User Profile Characteristics
    
    /// Get user's age from HealthKit date of birth
    func getAge() throws -> Int? {
        guard let dateOfBirthComponents = try? healthStore.dateOfBirthComponents() else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirthComponents, to: calendar.dateComponents([.year, .month, .day], from: now))
        return ageComponents.year
    }
    
    /// Get user's biological sex from HealthKit
    func getBiologicalSex() throws -> String? {
        let sexObject = try? healthStore.biologicalSex()
        switch sexObject?.biologicalSex {
        case .male:
            return "male"
        case .female:
            return "female"
        default:
            return nil
        }
    }
    
    /// Get user's height from HealthKit (returns value in inches)
    func getHeight() async throws -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let pred = HKQuery.predicateForSamples(withStart: .distantPast, end: Date(), options: [])

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: heightType, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                if let sample = samples?.first as? HKQuantitySample {
                    // Return height in inches
                    let heightInInches = sample.quantity.doubleValue(for: HKUnit.inch())
                    cont.resume(returning: heightInInches)
                } else {
                    cont.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }

    /// Get user's latest body weight from HealthKit (returns value in pounds)
    func getBodyWeight() async throws -> Double? {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let pred = HKQuery.predicateForSamples(withStart: .distantPast, end: Date(), options: [])

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: pred, limit: 1, sortDescriptors: [sort]) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                if let sample = samples?.first as? HKQuantitySample {
                    let weightInPounds = sample.quantity.doubleValue(for: HKUnit.pound())
                    cont.resume(returning: weightInPounds)
                } else {
                    cont.resume(returning: nil)
                }
            }
            healthStore.execute(query)
        }
    }

    /// Fetch weight entries from HealthKit within a date range
    /// Returns tuples of (date, weightInPounds)
    func getWeightHistory(from startDate: Date = .distantPast, to endDate: Date = Date()) async throws -> [(date: Date, weightInPounds: Double)] {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let pred = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: bodyMassType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, err in
                if let err = err { cont.resume(throwing: err); return }
                let results = (samples as? [HKQuantitySample])?.map { sample in
                    (date: sample.endDate, weightInPounds: sample.quantity.doubleValue(for: HKUnit.pound()))
                } ?? []
                cont.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }

    /// Collapse a batch of weight samples to the LATEST sample per calendar day.
    /// getWeightHistory returns samples oldest-first, so a later same-day sample
    /// (e.g. an evening correction) should overwrite an earlier one on import.
    /// Shared by both the manual and silent auto-import paths so they agree.
    static func latestWeightSamplesPerDay(
        _ samples: [(date: Date, weightInPounds: Double)],
        calendar: Calendar = .current
    ) -> [(date: Date, weightInPounds: Double)] {
        var latestByDay: [Date: (date: Date, weightInPounds: Double)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if let existing = latestByDay[day], existing.date >= sample.date { continue }
            latestByDay[day] = sample
        }
        return latestByDay.values.sorted { $0.date < $1.date }
    }

    // MARK: - Run similarity (shared dedup / link matching)

    /// Meters represented by a stored distance value in the given unit. Uses the
    /// same conversion factors as the rest of the app (1609.34 m/mi, 1000 m/km).
    static func metersFor(distance: Double, unit: String) -> Double {
        (unit == "mi") ? (distance * 1609.34) : (distance * 1000.0)
    }

    /// Shared time window for treating two runs as "the same run" during import
    /// matching and deduplication. Applied consistently in all sites.
    static let runMatchDateWindow: TimeInterval = 120
    static let runMatchDurationTolerance: TimeInterval = 120
    /// Physical distance tolerance in meters — unit-independent so a run logged in
    /// "mi" still matches after the user switches the app to "km".
    static let runMatchDistanceToleranceMeters: Double = 100

    /// Unit-independent similarity test for two runs. All distances are converted to
    /// meters before comparison so unit switches don't produce duplicate rows.
    static func runsAreSimilar(
        aDate: Date, aDuration: TimeInterval, aDistance: Double, aUnit: String,
        bDate: Date, bDuration: TimeInterval, bDistance: Double, bUnit: String
    ) -> Bool {
        let aMeters = metersFor(distance: aDistance, unit: aUnit)
        let bMeters = metersFor(distance: bDistance, unit: bUnit)
        return abs(aDate.timeIntervalSince(bDate)) <= runMatchDateWindow &&
            abs(aDuration - bDuration) <= runMatchDurationTolerance &&
            abs(aMeters - bMeters) <= runMatchDistanceToleranceMeters
    }

    /// Fetch all heart rate samples for a workout with timestamps
    func heartRateSamples(for workout: HKWorkout) async throws -> [(timestamp: Date, bpm: Double)] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let heartRateSamples = (samples as? [HKQuantitySample]) ?? []
                let results = heartRateSamples.map { sample in
                    (timestamp: sample.startDate, bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                }
                continuation.resume(returning: results)
            }
            self.healthStore.execute(query)
        }
    }
    
    /// Get a workout by UUID string
    func workoutForUUID(_ uuidString: String) async throws -> HKWorkout? {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        let predicate = HKQuery.predicateForObject(with: uuid)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            self.healthStore.execute(query)
        }
    }
}
