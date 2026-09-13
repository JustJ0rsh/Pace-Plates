import Foundation
import SwiftData

@MainActor
enum RunHistoryStore {
    struct Page {
        let sessions: [RunningSession]
        let matchingCount: Int
        let totalCount: Int
    }

    static func fetch(context: ModelContext, search: String, range: HistoryRange,
                      activity: String?, limit: Int, now: Date = Date()) throws -> Page {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch range {
        case .all: start = .distantPast
        case .days30: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .months3: start = calendar.date(byAdding: .month, value: -3, to: today) ?? today
        case .year1: start = calendar.date(byAdding: .year, value: -1, to: today) ?? today
        }
        let end = range == .all ? Date.distantFuture : (calendar.date(byAdding: .day, value: 1, to: today) ?? now)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = activity ?? ""
        let allTypes = activity == nil
        let stairs = type == "stairClimbing"
        let labels = ["running": "Run", "walking": "Walk", "hiking": "Hike",
                      "cycling": "Cycle", "rowing": "Row", "elliptical": "Elliptical",
                      "stairStepper": "Stair Stepper", "stairClimbing": "Stair Climbing"]
        let matchingTypes = labels.filter { $0.value.localizedCaseInsensitiveContains(query) }.map(\.key)
        let emptyQuery = query.isEmpty
        let predicate = #Predicate<RunningSession> { session in
            session.date >= start && session.date < end &&
            (allTypes || session.activityType == type || (stairs && session.activityType == "stairStepper")) &&
            (emptyQuery || session.activityType.localizedStandardContains(query) ||
             matchingTypes.contains(session.activityType) ||
             (session.notes?.localizedStandardContains(query) ?? false))
        }
        var descriptor = FetchDescriptor<RunningSession>(predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        let matchingCount = try context.fetchCount(descriptor)
        descriptor.fetchLimit = max(1, limit)
        return Page(sessions: try context.fetch(descriptor), matchingCount: matchingCount,
                    totalCount: try context.fetchCount(FetchDescriptor<RunningSession>()))
    }
}
