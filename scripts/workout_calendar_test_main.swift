@main
struct WorkoutCalendarTests {
    static func main() throws {
        print("Workout Calendar checks passed: \(try WorkoutCalendarPlanRegressionChecks.run())")
    }
}
