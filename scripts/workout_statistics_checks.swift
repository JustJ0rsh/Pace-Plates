import Foundation

@main
struct WorkoutStatisticsChecks {
    @MainActor static func main() throws {
        let count = try WorkoutStatisticsRegressionChecks.run()
        print("Workout statistics: \(count) checks passed")
    }
}
