import Foundation
import HealthKit
import CoreLocation

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()

    // MARK: - Types
    private let readTypes: Set<HKObjectType> = {
        var set = Set<HKObjectType>()
        set.insert(HKObjectType.workoutType())
        set.insert(HKObjectType.quantityType(forIdentifier: .heartRate)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .stepCount)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .vo2Max)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .runningPower)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .runningSpeed)!)
        // Read workout routes so we can render maps for Apple Watch runs
        set.insert(HKSeriesType.workoutRoute())
        return set
    }()

    private let writeTypes: Set<HKSampleType> = {
        var set = Set<HKSampleType>()
        set.insert(HKObjectType.workoutType())
        set.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
        set.insert(HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)
        return set
    }()

    @Published private(set) var isAuthorized = false

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        await MainActor.run { self.isAuthorized = self.authorizationStatusOK() }
    }

    private func authorizationStatusOK() -> Bool {
        // Consider authorized if workout and distance are allowed
        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let distanceStatus = healthStore.authorizationStatus(for: distanceType)
        return workoutStatus == .sharingAuthorized || distanceStatus == .sharingAuthorized
    }

    // MARK: - Save Workout
    func saveRunWorkout(start: Date, end: Date, distanceMeters: Double, energyBurned: Double? = nil, route: [CLLocation]? = nil) async throws {
        let store = self.healthStore

        // Prepare quantities
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
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

        // Define the workout configuration for a running workout
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        // Build the workout using HKWorkoutBuilder (iOS 17+ recommended)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        // Set the workout start and end dates using async alternatives
        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)

        // Add samples to the builder using async API
        try await builder.addSamples(additionalSamples)

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

        // Optionally save route data (must be associated after workout is saved)
        if let route = route, !route.isEmpty {
            let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                routeBuilder.insertRouteData(route) { _, error in
                    if let error = error { continuation.resume(throwing: error); return }
                    routeBuilder.finishRoute(with: workout, metadata: nil) { _, finishError in
                        if let finishError = finishError { continuation.resume(throwing: finishError); return }
                        continuation.resume(returning: ())
                    }
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
    func fetchRecentRuns(limit: Int = 25) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error = error { continuation.resume(throwing: error); return }
                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
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
        for w in runs where w.workoutActivityType == .running {
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
}
