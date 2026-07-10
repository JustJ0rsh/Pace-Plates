import Foundation

@main
struct WearableVitalsTestMain {
    static func main() {
        expect(
            WearableDevicePreference.allCases.map(\.displayName) == [
                "Apple Health Only", "Apple Watch", "Oura Ring", "Fitbit"
            ],
            "wearable preferences expose the expected choices"
        )

        let values = VitalMetricValues(
            restingHeartRate: "54 bpm",
            heartRate: "61 bpm",
            stepsToday: "4,200",
            activeEnergy: "320 kcal",
            hrv: "62 ms",
            spo2: "98%",
            bodyTemp: "98.1 °F",
            sleepDuration: "7.6 h",
            sleepScore: "84",
            respiratoryRate: "14 br/min",
            vo2Max: "47.2"
        )

        expect(
            VitalMetric.metrics(for: .appleWatch, values: values).map(\.id) == [
                "restingHeartRate", "hrv", "respiratoryRate", "spo2",
                "bodyTemp", "sleep", "steps", "vo2Max"
            ],
            "Apple Watch exposes its Apple Health vitals"
        )
        expect(
            VitalMetric.metrics(for: .ouraRing, values: values).map(\.id) == [
                "sleep", "sleepScore", "heartRate", "respiratoryRate", "steps", "activeEnergy"
            ],
            "Oura only exposes metrics it exports to Apple Health"
        )
        expect(
            VitalMetric.metrics(for: .fitbit, values: values).map(\.id) == [
                "steps", "activeEnergy", "restingHeartRate", "sleep", "spo2", "respiratoryRate"
            ],
            "Fitbit exposes supported Apple Health bridge metrics"
        )
        expect(
            WearableDevicePreference.fitbit.healthSourceNameHints.contains("Fitbit"),
            "Fitbit samples are source-filtered"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }
}
