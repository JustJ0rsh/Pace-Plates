import Foundation

struct VitalMetricValues: Equatable {
    var restingHeartRate: String = "—"
    var heartRate: String = "—"
    var stepsToday: String = "—"
    var activeEnergy: String = "—"
    var hrv: String = "—"
    var spo2: String = "—"
    var bodyTemp: String = "—"
    var sleepDuration: String = "—"
    var sleepScore: String = "—"
    var respiratoryRate: String = "—"
    var vo2Max: String = "—"

    var restingHeartRateOrHeartRate: String {
        restingHeartRate != "—" ? restingHeartRate : heartRate
    }

    var sleepScoreDisplay: String {
        sleepScore == "—" ? "—" : "\(sleepScore) / 100"
    }
}

struct VitalMetric: Identifiable, Equatable {
    let id: String
    let title: String
    let systemName: String
    let value: String
    let source: String

    static func metrics(for preference: WearableDevicePreference, values: VitalMetricValues) -> [VitalMetric] {
        switch preference {
        case .none:
            return [
                metric("steps", "Steps", "figure.walk", values.stepsToday, "Apple Health"),
                metric("activeEnergy", "Active Energy", "flame.fill", values.activeEnergy, "Apple Health"),
                metric("sleep", "Sleep", "bed.double.fill", values.sleepDuration, "Apple Health"),
                metric("sleepScore", "Sleep Score", "zzz", values.sleepScoreDisplay, "Estimated")
            ]
        case .appleWatch:
            return [
                metric("restingHeartRate", "Resting HR", "heart.fill", values.restingHeartRateOrHeartRate, "Apple Watch"),
                metric("hrv", "HRV", "waveform.path.ecg", values.hrv, "Apple Watch"),
                metric("respiratoryRate", "Resp. Rate", "lungs.fill", values.respiratoryRate, "Apple Watch"),
                metric("spo2", "SpO2", "drop.fill", values.spo2, "Apple Watch"),
                metric("bodyTemp", "Temperature", "thermometer.medium", values.bodyTemp, "Apple Watch"),
                metric("sleep", "Sleep", "bed.double.fill", values.sleepDuration, "Apple Watch"),
                metric("steps", "Steps", "figure.walk", values.stepsToday, "Apple Health"),
                metric("vo2Max", "VO2 Max", "figure.run", values.vo2Max, "Apple Health")
            ]
        case .ouraRing:
            return [
                metric("sleep", "Sleep", "bed.double.fill", values.sleepDuration, "Oura"),
                metric("sleepScore", "Sleep Score", "zzz", values.sleepScoreDisplay, "Estimated"),
                metric("heartRate", "Heart Rate", "heart.fill", values.restingHeartRateOrHeartRate, "Oura"),
                metric("respiratoryRate", "Resp. Rate", "lungs.fill", values.respiratoryRate, "Oura"),
                metric("steps", "Steps", "figure.walk", values.stepsToday, "Apple Health"),
                metric("activeEnergy", "Active Energy", "flame.fill", values.activeEnergy, "Apple Health")
            ]
        case .fitbit:
            return [
                metric("steps", "Steps", "figure.walk", values.stepsToday, "Apple Health"),
                metric("activeEnergy", "Active Energy", "flame.fill", values.activeEnergy, "Apple Health"),
                metric("restingHeartRate", "Resting HR", "heart.fill", values.restingHeartRateOrHeartRate, "Fitbit"),
                metric("sleep", "Sleep", "bed.double.fill", values.sleepDuration, "Fitbit"),
                metric("spo2", "SpO2", "drop.fill", values.spo2, "Fitbit"),
                metric("respiratoryRate", "Resp. Rate", "lungs.fill", values.respiratoryRate, "Fitbit")
            ]
        }
    }

    private static func metric(
        _ id: String,
        _ title: String,
        _ systemName: String,
        _ value: String,
        _ source: String
    ) -> VitalMetric {
        VitalMetric(id: id, title: title, systemName: systemName, value: value, source: source)
    }
}
