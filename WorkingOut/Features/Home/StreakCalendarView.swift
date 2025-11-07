import SwiftUI
import SwiftData

struct StreakCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)]) private var runningSessions: [RunningSession]
    @Query(sort: [SortDescriptor<WorkoutSession>(\.date, order: .reverse)]) private var workoutSessions: [WorkoutSession]

    private var calendar: Calendar { Calendar.current }

    // Generate a scrollable range of months (e.g., last 12 months up to current)
    private var months: [Date] {
        let today = calendar.startOfDay(for: Date())
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        let back = 11
        return (0...back).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset, to: currentMonth)
        }
    }

    // Activity type sets
    private var cardioDays: Set<Date> {
        var set = Set<Date>()
        // Runs
        let runDays = runningSessions.map { calendar.startOfDay(for: $0.date) }
        set.formUnion(runDays)
        // Cardio logged within gym sessions
        for s in workoutSessions {
            if sessionHasCardio(s) { set.insert(calendar.startOfDay(for: s.date)) }
        }
        return set
    }

    private var liftDays: Set<Date> {
        var set = Set<Date>()
        for s in workoutSessions {
            if sessionHasStrength(s) { set.insert(calendar.startOfDay(for: s.date)) }
        }
        return set
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthName(for month: Date) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "LLLL yyyy"
        return fmt.string(from: month)
    }

    private func daysInMonth(_ month: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { day -> Date? in
            var comps = calendar.dateComponents([.year, .month], from: month)
            comps.day = day
            return calendar.date(from: comps)
        }
    }

    private func leadingBlankDays(for month: Date) -> Int {
        let weekday = calendar.component(.weekday, from: month)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        // Narrow symbols like S M T W T F S
        let syms = calendar.shortWeekdaySymbols
        // Rotate so firstWeekday is first
        let idx = calendar.firstWeekday - 1
        return Array(syms[idx...] + syms[..<idx])
    }

    private func sessionHasStrength(_ s: WorkoutSession) -> Bool {
        let logs = s.exerciseLogs ?? []
        return logs.contains { log in
            let type = (log.exerciseType ?? "strength").lowercased()
            if type == "cardio" { return false }
            // consider it strength if reps or weight present
            return (log.reps > 0) || (log.weight > 0)
        }
    }

    private func sessionHasCardio(_ s: WorkoutSession) -> Bool {
        let logs = s.exerciseLogs ?? []
        return logs.contains { log in
            if (log.exerciseType ?? "").lowercased() == "cardio" { return true }
            // Fallback heuristics based on name
            let name = ((log.exerciseName ?? log.exerciseDefinition?.name) ?? "").lowercased()
            let cardioTokens = ["run", "jog", "tread", "elliptical", "bike", "cycle", "swim", "rowing", "rower", "erg", "stair", "assault bike", "airdyne", "spin"]
            let strengthRowTokens = ["barbell row", "bent over row", "bent-over row", "pendlay row", "t-bar row", "dumbbell row", "one-arm row", "one arm row", "seated row", "cable row", "inverted row"]
            let looksCardio = cardioTokens.contains(where: { name.contains($0) })
            let isStrengthRow = strengthRowTokens.contains(where: { name.contains($0) }) && !name.contains("rowing") && !name.contains("rower")
            return looksCardio && !isStrengthRow
        }
    }

    var body: some View {
        ScrollView {
            let cardio = cardioDays
            let lifts = liftDays
            LazyVStack(alignment: .leading, spacing: 16) {
                // Weekday header (static)
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { sym in
                        Text(sym.prefix(2))
                            .frame(maxWidth: .infinity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)

                ForEach(months, id: \.self) { month in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(monthName(for: month)).font(.headline)

                        let blanks = Array(repeating: "", count: leadingBlankDays(for: month))
                        let days = daysInMonth(month)
                        let cells: [Date?] = blanks.map { _ in nil } + days
                        let rows = Int(ceil(Double(cells.count) / 7.0))

                        VStack(spacing: 8) {
                            ForEach(0..<rows, id: \.self) { row in
                                HStack(spacing: 0) {
                                    ForEach(0..<7, id: \.self) { col in
                                        let idx = row * 7 + col
                                        let date = (idx < cells.count) ? cells[idx] : nil
                                        let day = date.map { calendar.startOfDay(for: $0) }
                                        DayCell(date: date,
                                                hasLift: day.map { lifts.contains($0) } ?? false,
                                                hasCardio: day.map { cardio.contains($0) } ?? false)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Legend
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(AppTheme.accentColor).frame(width: 10, height: 10)
                        Text("Workout").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 10, height: 10)
                        Text("Cardio").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .padding(.bottom)
            .padding(.horizontal)
        }
        .navigationTitle("Streak Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
    }
}

private struct DayCell: View {
    let date: Date?
    let hasLift: Bool
    let hasCardio: Bool
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
                .frame(height: 40)
            if let d = date {
                let day = calendar.component(.day, from: d)
                VStack(spacing: 2) {
                    Text("\(day)")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textColor)
                    if hasLift && hasCardio {
                        HStack(spacing: 4) {
                            Circle().fill(AppTheme.accentColor).frame(width: 6, height: 6)
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                        }
                    } else if hasLift {
                        Circle().fill(AppTheme.accentColor).frame(width: 6, height: 6)
                    } else if hasCardio {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                    } else {
                        Circle().fill(Color.clear).frame(width: 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
