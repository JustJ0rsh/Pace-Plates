import Foundation

struct OpenRouterUsageBudgetStatus {
    let dailyLimit: Int
    let dailyUsed: Int
    let minuteLimit: Int
    let minuteUsed: Int
    let cooldownUntil: Date?
    let dailyResetAt: Date
    let minuteRetryAt: Date?

    var dailyRemaining: Int { max(0, dailyLimit - dailyUsed) }
    var minuteRemaining: Int { max(0, minuteLimit - minuteUsed) }
    var isCoolingDown: Bool { cooldownUntil.map { $0 > Date() } ?? false }
}

enum OpenRouterUsageBudgetError: LocalizedError {
    case dailyLimitReached(limit: Int, resetAt: Date)
    case minuteLimitReached(limit: Int, retryAt: Date)
    case cooldownActive(until: Date)

    var errorDescription: String? {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        switch self {
        case let .dailyLimitReached(limit, resetAt):
            return "OpenRouter is capped at \(limit) requests per day on this device to protect the shared free-tier quota. Try again \(formatter.localizedString(for: resetAt, relativeTo: Date()))."
        case let .minuteLimitReached(limit, retryAt):
            return "OpenRouter is capped at \(limit) requests per minute on this device. Try again \(formatter.localizedString(for: retryAt, relativeTo: Date()))."
        case let .cooldownActive(until):
            return "OpenRouter free models are being throttled right now. Try again \(formatter.localizedString(for: until, relativeTo: Date()))."
        }
    }
}

enum AIUsageBudgetManager {
    static let openRouterDailyLimitPreferenceKey = "openRouterUsage.dailyLimit"
    static let openRouterFreeUserDailyRequestLimit = 50
    static let openRouterCreditedDailyRequestLimit = 1000
    static let openRouterPerMinuteRequestLimit = 20
    static let openRouterCooldownAfterThrottleSeconds: TimeInterval = 90
    static let maxModelAttemptsPerRequest = 3

    static let openRouterChatOutputTokenLimit = 500
    static let openRouterWorkoutPlanOutputTokenLimit = 1400
    static let openRouterRunPlanOutputTokenLimit = 1800

    private static let dayBucketKey = "openRouterUsage.dayBucket"
    private static let dayCountKey = "openRouterUsage.dayCount"
    private static let recentRequestTimestampsKey = "openRouterUsage.recentRequestTimestamps"
    private static let cooldownUntilKey = "openRouterUsage.cooldownUntil"
    private static let lock = NSLock()

    static var openRouterDailyRequestLimit: Int {
        configuredDailyLimit()
    }

    static func consumeOpenRouterAttempt(now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }

        let status = currentStatusLocked(now: now)
        let dailyLimit = configuredDailyLimit()

        if let cooldownUntil = status.cooldownUntil, cooldownUntil > now {
            throw OpenRouterUsageBudgetError.cooldownActive(until: cooldownUntil)
        }

        if status.dailyUsed >= dailyLimit {
            throw OpenRouterUsageBudgetError.dailyLimitReached(limit: dailyLimit, resetAt: status.dailyResetAt)
        }

        if status.minuteUsed >= openRouterPerMinuteRequestLimit {
            throw OpenRouterUsageBudgetError.minuteLimitReached(
                limit: openRouterPerMinuteRequestLimit,
                retryAt: status.minuteRetryAt ?? now.addingTimeInterval(60)
            )
        }

        let defaults = UserDefaults.standard
        defaults.set(status.dailyUsed + 1, forKey: dayCountKey)

        var timestamps = recentTimestampsLocked(now: now)
        timestamps.append(now.timeIntervalSince1970)
        defaults.set(timestamps, forKey: recentRequestTimestampsKey)
    }

    static func registerOpenRouterThrottle(now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(
            now.addingTimeInterval(openRouterCooldownAfterThrottleSeconds).timeIntervalSince1970,
            forKey: cooldownUntilKey
        )
    }

    static func currentOpenRouterStatus(now: Date = Date()) -> OpenRouterUsageBudgetStatus {
        lock.lock()
        defer { lock.unlock() }
        return currentStatusLocked(now: now)
    }

    static func setOpenRouterDailyLimit(_ limit: Int) {
        let normalized = normalizedDailyLimit(limit)
        UserDefaults.standard.set(normalized, forKey: openRouterDailyLimitPreferenceKey)
    }

    static func resetOpenRouterUsage() {
        lock.lock()
        defer { lock.unlock() }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: dayBucketKey)
        defaults.removeObject(forKey: dayCountKey)
        defaults.removeObject(forKey: recentRequestTimestampsKey)
        defaults.removeObject(forKey: cooldownUntilKey)
    }

    private static func currentStatusLocked(now: Date) -> OpenRouterUsageBudgetStatus {
        normalizeDayBucketLocked(now: now)
        let defaults = UserDefaults.standard
        let dailyLimit = configuredDailyLimit()

        let timestamps = recentTimestampsLocked(now: now)
        defaults.set(timestamps, forKey: recentRequestTimestampsKey)

        let cooldownUntil: Date? = {
            let raw = defaults.double(forKey: cooldownUntilKey)
            guard raw > 0 else { return nil }
            let date = Date(timeIntervalSince1970: raw)
            if date <= now {
                defaults.removeObject(forKey: cooldownUntilKey)
                return nil
            }
            return date
        }()

        let dailyUsed = defaults.integer(forKey: dayCountKey)
        let retryAt = timestamps.first.map { Date(timeIntervalSince1970: $0 + 60) }
        return OpenRouterUsageBudgetStatus(
            dailyLimit: dailyLimit,
            dailyUsed: dailyUsed,
            minuteLimit: openRouterPerMinuteRequestLimit,
            minuteUsed: timestamps.count,
            cooldownUntil: cooldownUntil,
            dailyResetAt: nextUTCMidnight(after: now),
            minuteRetryAt: retryAt
        )
    }

    private static func recentTimestampsLocked(now: Date) -> [Double] {
        let raw = UserDefaults.standard.array(forKey: recentRequestTimestampsKey) as? [Double] ?? []
        let cutoff = now.addingTimeInterval(-60).timeIntervalSince1970
        return raw.filter { $0 > cutoff }.sorted()
    }

    private static func normalizeDayBucketLocked(now: Date) {
        let defaults = UserDefaults.standard
        let currentBucket = utcDayBucket(for: now)
        let storedBucket = defaults.string(forKey: dayBucketKey)

        if storedBucket != currentBucket {
            defaults.set(currentBucket, forKey: dayBucketKey)
            defaults.set(0, forKey: dayCountKey)
        }
    }

    private static func utcDayBucket(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func nextUTCMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startOfToday = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? date.addingTimeInterval(86_400)
    }

    private static func configuredDailyLimit() -> Int {
        let stored = UserDefaults.standard.integer(forKey: openRouterDailyLimitPreferenceKey)
        let normalized = normalizedDailyLimit(stored)
        if stored != normalized {
            UserDefaults.standard.set(normalized, forKey: openRouterDailyLimitPreferenceKey)
        }
        return normalized
    }

    private static func normalizedDailyLimit(_ limit: Int) -> Int {
        limit == openRouterCreditedDailyRequestLimit
            ? openRouterCreditedDailyRequestLimit
            : openRouterFreeUserDailyRequestLimit
    }
}
