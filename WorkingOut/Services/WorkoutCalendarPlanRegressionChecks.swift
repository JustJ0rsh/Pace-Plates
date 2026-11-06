#if DEBUG
import Foundation

enum WorkoutCalendarPlanRegressionChecks {
    static func run() throws -> Int {
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw CheckFailure(message: message) }
        }

        let plain = """
        ## Training Plan Overview
        ### Day 1: Upper Body
        - Bench press: 3 sets of 8
        ### Day 2: Lower Body
        - Squat: 3 sets of 8
        """
        let qualified = plain.replacingOccurrences(of: "### Day", with: "### Week 1, Day")
        let days = WorkoutCalendarPlan.parseWorkoutDays(from: qualified)
        try require(days.count == 2, "week-qualified headings produce both days")
        try require(days.map(\.title) == ["Day 1: Upper Body", "Day 2: Lower Body"], "day titles remain separate")
        try require(days.map(\.details) == ["- Bench press: 3 sets of 8", "- Squat: 3 sets of 8"], "each prescription belongs to its own day")
        let plainDays = WorkoutCalendarPlan.parseWorkoutDays(from: plain)
        try require(plainDays.map(\.title) == days.map(\.title) && plainDays.map(\.details) == days.map(\.details), "plain day headings retain their existing behavior")
        let laterWeek = WorkoutCalendarPlan.parseWorkoutDays(from: qualified.replacingOccurrences(of: "Week 1", with: "Week 2"))
        try require(laterWeek.count == 2, "later-week headings also parse")
        let workoutTitle = WorkoutCalendarPlan.parseWorkoutDays(from: "### Day 1: Workout: Upper Body\nBench press: 3 sets of 8")
        try require(workoutTitle.count == 1 && workoutTitle.first?.title == "Day 1: Workout: Upper Body", "workout wording in a day title is not treated as an overview")
        let weekday = WorkoutCalendarPlan.parseWorkoutDays(from: "### Monday: Strength\nSquat: 3 sets\n### Tuesday: Rest\nRest Day")
        try require(weekday.count == 2 && weekday.last?.details == "Rest Day", "weekday and rest-day parsing remain supported")
        try require(WorkoutCalendarPlan.parseWorkoutDays(from: "Training Plan Overview\nThis week\nNo daily prescription").isEmpty, "overview alone cannot fabricate a workout")

        func checkTomorrow(zone: String, year: Int, month: Int, day: Int, hour: Int, minute: Int, expectedYear: Int, expectedMonth: Int, expectedDay: Int) throws {
            var calendar = Calendar(identifier: .gregorian)
            guard let timeZone = TimeZone(identifier: zone) else { throw CheckFailure(message: "missing test time zone") }
            calendar.timeZone = timeZone
            guard let now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)),
                  let start = WorkoutCalendarPlan.startDate(after: now, calendar: calendar) else {
                throw CheckFailure(message: "could not construct civil date")
            }
            let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            try require(actual == DateComponents(year: expectedYear, month: expectedMonth, day: expectedDay, hour: 0, minute: 0), "tomorrow uses the next civil day in \(zone) at \(year)-\(month)-\(day) \(hour):\(minute)")
        }
        try checkTomorrow(zone: "America/New_York", year: 2026, month: 11, day: 1, hour: 0, minute: 30, expectedYear: 2026, expectedMonth: 11, expectedDay: 2)
        try checkTomorrow(zone: "America/New_York", year: 2026, month: 3, day: 7, hour: 23, minute: 30, expectedYear: 2026, expectedMonth: 3, expectedDay: 8)
        try checkTomorrow(zone: "Asia/Jerusalem", year: 2026, month: 10, day: 25, hour: 0, minute: 30, expectedYear: 2026, expectedMonth: 10, expectedDay: 26)
        try checkTomorrow(zone: "UTC", year: 2026, month: 12, day: 31, hour: 23, minute: 30, expectedYear: 2027, expectedMonth: 1, expectedDay: 1)
        return checks
    }

    private struct CheckFailure: LocalizedError {
        let message: String
        var errorDescription: String? { "Workout Calendar regression: " + message }
    }
}
#endif
