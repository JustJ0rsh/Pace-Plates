import Foundation
import SwiftData
import GameKit

enum StreakService {
    // Daily streak thresholds: 7, 14, 30, 60, 90, 120, ... up to 365
    static let dailyThresholds: [Int] = [7, 14, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330, 365]
    // Weekly streak thresholds up to 54 weeks
    static let weeklyThresholds: [Int] = [4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 54]

    static func refreshAndReport(using context: ModelContext) {
        let daily = dailyStreak(using: context)
        let weekly = weeklyStreak(using: context)
        reportAchievements(dailyStreak: daily, weeklyStreak: weekly)
    }

    static func dailyStreak(using context: ModelContext) -> Int {
        let cal = Calendar.current
        // Collect unique days with activity (workout session or running session)
        var daySet: Set<Date> = []
        if let workouts: [WorkoutSession] = try? context.fetch(FetchDescriptor<WorkoutSession>()) {
            for s in workouts { daySet.insert(cal.startOfDay(for: s.date)) }
        }
        if let runs: [RunningSession] = try? context.fetch(FetchDescriptor<RunningSession>()) {
            for r in runs { daySet.insert(cal.startOfDay(for: r.date)) }
        }
        guard let lastDay = daySet.max() else { return 0 }
        var count = 0
        var cursor = lastDay
        while daySet.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    static func weeklyStreak(using context: ModelContext) -> Int {
        let cal = Calendar.current
        // Build set of (yearForWeekOfYear, weekOfYear)
        struct WeekKey: Hashable { let year: Int; let week: Int }
        var weekSet: Set<WeekKey> = []

        if let workouts: [WorkoutSession] = try? context.fetch(FetchDescriptor<WorkoutSession>()) {
            for s in workouts {
                let comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: s.date)
                if let w = comps.weekOfYear, let y = comps.yearForWeekOfYear { weekSet.insert(.init(year: y, week: w)) }
            }
        }
        if let runs: [RunningSession] = try? context.fetch(FetchDescriptor<RunningSession>()) {
            for r in runs {
                let comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: r.date)
                if let w = comps.weekOfYear, let y = comps.yearForWeekOfYear { weekSet.insert(.init(year: y, week: w)) }
            }
        }
        guard !weekSet.isEmpty else { return 0 }

        // Anchor at the most recent activity week (by date), then walk back week-by-week
        // Find the latest date among all activities
        var latestDate: Date? = nil
        var fdW = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fdW.fetchLimit = 1
        if let lastWorkout: WorkoutSession = try? context.fetch(fdW).first {
            latestDate = max(latestDate ?? lastWorkout.date, lastWorkout.date)
        }
        var fdR = FetchDescriptor<RunningSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fdR.fetchLimit = 1
        if let lastRun: RunningSession = try? context.fetch(fdR).first {
            latestDate = max(latestDate ?? lastRun.date, lastRun.date)
        }
        guard let anchor = latestDate else { return 0 }

        // Start from anchor week and count consecutive weeks present
        var count = 0
        var cursor = anchor
        while true {
            let comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: cursor)
            if let w = comps.weekOfYear, let y = comps.yearForWeekOfYear, weekSet.contains(.init(year: y, week: w)) {
                count += 1
                guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
                cursor = prev
            } else {
                break
            }
        }
        return count
    }
}

private extension StreakService {
    static func reportAchievements(dailyStreak: Int, weeklyStreak: Int) {
        guard GameCenterService.shared.isCommunityAccessEnabled else { return }

        // Load existing player achievement states so we only report improvements
        GKAchievement.loadAchievements { existing, error in
            if let error { print("GameCenter: Load achievements failed: \(error)") }
            let map: [String: GKAchievement] = Dictionary(uniqueKeysWithValues: (existing ?? []).map { ach in
                (ach.identifier, ach)
            })

            var toReport: [GKAchievement] = []

            func consider(id: String, percent: Double) {
                let clamped = max(0.0, min(100.0, percent))
                let current = map[id]?.percentComplete ?? 0.0
                let alreadyCompleted = map[id]?.isCompleted ?? false
                // Only report if progress increased
                if clamped > current + 0.001 {
                    let a = GKAchievement(identifier: id)
                    a.percentComplete = clamped
                    // Only show banner when transitioning to 100% for the first time
                    a.showsCompletionBanner = (!alreadyCompleted && current < 100.0 && clamped >= 100.0)
                    toReport.append(a)
                }
            }

            for t in dailyThresholds {
                let id = String(format: "streak_days_%03d", t)
                consider(id: id, percent: (Double(dailyStreak) / Double(t)) * 100.0)
            }

            for t in weeklyThresholds {
                let id = String(format: "streak_weeks_%03d", t)
                consider(id: id, percent: (Double(weeklyStreak) / Double(t)) * 100.0)
            }

            if !toReport.isEmpty {
                GKAchievement.report(toReport) { error in
                    if let error { print("GameCenter: Failed to report streak achievements: \(error)") }
                }
            }
        }
    }
}
