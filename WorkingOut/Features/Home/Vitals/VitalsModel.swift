import Foundation
import HealthKit

@MainActor
final class VitalsModel: ObservableObject {
    @Published private(set) var metrics: [VitalMetric] = []
    @Published private(set) var wearablePreference: WearableDevicePreference = .none

    private let healthKit = HealthKitManager.shared

    private var useImperialUnits: Bool {
        UserDefaults.standard.string(forKey: "measurementSystem") != "metric"
    }

    func loadVitals(for preference: WearableDevicePreference? = nil) async {
        let preference = preference ?? storedPreference
        wearablePreference = preference
        let sourceHints = preference.healthSourceNameHints
        var values = VitalMetricValues()

        if let sample = try? await latestSample(for: .restingHeartRate, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            values.restingHeartRate = String(format: "%.0f bpm", value)
        } else if let sample = try? await latestSample(for: .heartRate, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
            values.heartRate = String(format: "%.0f bpm", value)
        }

        if let value = try? await healthKit.todaySum(for: .stepCount, unit: .count()) {
            values.stepsToday = NumberFormatter.localizedString(
                from: NSNumber(value: Int(value)),
                number: .decimal
            )
        }

        if let value = try? await healthKit.todaySum(for: .activeEnergyBurned, unit: .kilocalorie()) {
            values.activeEnergy = String(format: "%.0f kcal", value)
        }

        if let sample = try? await latestSample(for: .heartRateVariabilitySDNN, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
            values.hrv = String(format: "%.0f ms", value)
        }

        if let sample = try? await latestSample(for: .oxygenSaturation, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: .percent())
            values.spo2 = String(format: "%.0f%%", value * 100)
        }

        if let sample = try? await latestSample(for: .bodyTemperature, sourceHints: sourceHints) {
            let celsius = sample.quantity.doubleValue(for: .degreeCelsius())
            values.bodyTemp = useImperialUnits
                ? String(format: "%.1f °F", celsius * 9 / 5 + 32)
                : String(format: "%.1f °C", celsius)
        }

        if let sample = try? await latestSample(for: .respiratoryRate, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            values.respiratoryRate = String(format: "%.0f br/min", value)
        }

        if let sample = try? await latestSample(for: .vo2Max, sourceHints: sourceHints) {
            let value = sample.quantity.doubleValue(for: HKUnit(from: "ml/kg*min"))
            values.vo2Max = String(format: "%.1f", value)
        }

        if let breakdown = try? await healthKit.lastNightSleepScoreBreakdown(matchingSourceHints: sourceHints) {
            values.sleepDuration = String(format: "%.1f h", breakdown.sleepDurationSeconds / 3600)
            values.sleepScore = "\(breakdown.totalScore)"
        }

        metrics = VitalMetric.metrics(for: preference, values: values)
    }

    private var storedPreference: WearableDevicePreference {
        let rawValue = UserDefaults.standard.string(forKey: WearableDevicePreference.storageKey) ?? ""
        return WearableDevicePreference(rawValue: rawValue) ?? .none
    }

    private func latestSample(
        for identifier: HKQuantityTypeIdentifier,
        sourceHints: [String]
    ) async throws -> HKQuantitySample? {
        guard !sourceHints.isEmpty else {
            return try await healthKit.latestQuantitySample(for: identifier)
        }
        return try await healthKit.latestQuantitySample(
            for: identifier,
            matchingSourceHints: sourceHints
        )
    }
}
