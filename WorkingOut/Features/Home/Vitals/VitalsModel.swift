import Foundation
import HealthKit

@MainActor
final class VitalsModel: ObservableObject {
    @Published var restingHeartRate: String = "—"
    @Published var heartRate: String = "—"
    @Published var stepsToday: String = "—"
    @Published var activeEnergy: String = "—"
    @Published var hrv: String = "—"
    @Published var spo2: String = "—"
    @Published var bodyTemp: String = "—"
    @Published var sleepDuration: String = "—"
    @Published var simpleSleepScore: String = "—" // optional (vs goal)

    private let hk = HealthKitManager.shared

    // Unit preferences - imperial by default, user can change in settings
    private var useImperialUnits: Bool {
        // Check user preference from Settings, default to imperial
        UserDefaults.standard.string(forKey: "measurementSystem") == "imperial"
    }


    func loadVitals() async {
        // Store units preference at start to avoid main actor isolation issues
        let useImperial = useImperialUnits

        await withTaskGroup(of: Void.self) { group in
            // Resting HR (fallback to latest HR)
            group.addTask {
                if let s = try? await self.hk.latestQuantitySample(for: .restingHeartRate) {
                    let v = s.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    await MainActor.run { self.restingHeartRate = String(format: "%.0f bpm", v) }
                } else if let s = try? await self.hk.latestQuantitySample(for: .heartRate) {
                    let v = s.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    await MainActor.run { self.heartRate = String(format: "%.0f bpm", v) }
                }
            }

            // Steps (today)
            group.addTask {
                if let val = try? await self.hk.todaySum(for: .stepCount, unit: .count()) {
                    await MainActor.run { self.stepsToday = NumberFormatter.localizedString(from: NSNumber(value: Int(val)), number: .decimal) }
                }
            }

            // Active energy (today, kcal)
            group.addTask {
                if let val = try? await self.hk.todaySum(for: .activeEnergyBurned, unit: .kilocalorie()) {
                    await MainActor.run { self.activeEnergy = String(format: "%.0f kcal", val) }
                }
            }

            // HRV (ms)
            group.addTask {
                if let s = try? await self.hk.latestQuantitySample(for: .heartRateVariabilitySDNN) {
                    let v = s.quantity.doubleValue(for: .secondUnit(with: .milli))
                    await MainActor.run { self.hrv = String(format: "%.0f ms", v) }
                }
            }

            // SpO2 (%)
            group.addTask {
                if let s = try? await self.hk.latestQuantitySample(for: .oxygenSaturation) {
                    let v = s.quantity.doubleValue(for: HKUnit.percent())
                    await MainActor.run { self.spo2 = String(format: "%.0f%%", v * 100.0) }
                }
            }

            // Body Temp (imperial by default, user can switch)
            group.addTask {
                if let s = try? await self.hk.latestQuantitySample(for: .bodyTemperature) {
                    let celsius = s.quantity.doubleValue(for: .degreeCelsius())
                    if useImperial {
                        let fahrenheit = celsius * 9/5 + 32
                        await MainActor.run { self.bodyTemp = String(format: "%.1f °F", fahrenheit) }
                    } else {
                        await MainActor.run { self.bodyTemp = String(format: "%.1f °C", celsius) }
                    }
                }
            }

            // Sleep (last night duration)
            group.addTask {
                if let seconds = try? await self.hk.lastNightSleepDuration(), seconds > 0 {
                    let hours = seconds / 3600.0
                    await MainActor.run { self.sleepDuration = String(format: "%.1f h", hours) }

                    // Optional simple score vs 8h goal
                    let score = max(0, min(100, (hours / 8.0) * 100.0))
                    await MainActor.run { self.simpleSleepScore = String(format: "%.0f", score) }
                }
            }
        }
    }
}
