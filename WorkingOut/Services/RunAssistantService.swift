import Foundation
import SwiftData

/// Centralized weekday <-> date math for running plans.
///
/// Sessions store `weekday` as a locale-independent number (1=Sun ... 7=Sat).
/// The pitfall: `DateComponents.weekday` resolves *within the calendar's week*,
/// and which dates fall in a given `.weekOfYear` depends on `calendar.firstWeekday`.
/// In a Monday-first locale (UK/EU), setting `comps.weekday = 1` (Sunday) on a
/// week-of-year anchor lands on a Sunday in a *different* calendar week than a
/// Sunday-first locale would produce — pushing the session into an adjacent week.
///
/// To stay deterministic regardless of locale we never assign `comps.weekday`.
/// Instead we compute the start of the target week (which respects firstWeekday,
/// so its own weekday == `calendar.firstWeekday`) and add a fixed day offset:
///     offset = (weekday - calendar.firstWeekday + 7) % 7
/// All conversions between the stored 1=Sun...7=Sat number and a date go through
/// here so scheduling, rest-day moves, and the dashboard agree.
enum RunAssistantWeekday {
    /// Resolves a stored weekday (1=Sun ... 7=Sat) to a concrete date within the
    /// week `weekOffset` weeks after `startDate`, independent of `firstWeekday`.
    static func scheduledDate(startDate: Date, weekOffset: Int, weekday: Int) -> Date {
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)) ?? startDate
        let offsetWeekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: weekStart) ?? weekStart
        let offset = ((weekday - calendar.firstWeekday) + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: offsetWeekStart) ?? offsetWeekStart
    }

    /// Reads the stored weekday number (1=Sun ... 7=Sat) from a scheduled date.
    /// `.weekday` is already locale-independent, so this is a straight component read.
    static func weekday(of date: Date) -> Int {
        Calendar.current.component(.weekday, from: date)
    }
}

@MainActor
final class RunAssistantService {
    static let shared = RunAssistantService()

    private init() {}

    // MARK: - Public API

    func recommendedTemplates(for profile: RunAssistantProfile) -> [RunPlanTemplateDescriptor] {
        RunPlanCatalog.allTemplates
            .map { template in
                (template, score(template: template, profile: profile))
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.name < rhs.0.name
                }
                return lhs.1 > rhs.1
            }
            .map { $0.0 }
    }

    @discardableResult
    func createPlan(
        from template: RunPlanTemplateDescriptor,
        profile: RunAssistantProfile,
        startDate: Date,
        context: ModelContext
    ) -> RunningPlan {
        let now = Date()
        let plan = RunningPlan(
            name: template.name,
            source: template.source,
            style: template.style,
            targetDistanceMeters: template.targetDistanceMeters,
            primaryGoal: template.primaryGoal,
            durationWeeks: template.durationWeeks,
            daysPerWeek: profile.daysPerWeek,
            startDate: startDate,
            isActive: false,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            profileSnapshotJSON: profile.asJSONString(),
            aiPrompt: nil
        )

        context.insert(plan)

        let blueprints = blueprintsForTemplate(template, profile: profile, startDate: startDate, context: context)
        for item in blueprints {
            let session = RunningPlanSession(
                plan: plan,
                weekIndex: item.weekIndex,
                dayIndex: item.dayIndex,
                scheduledDate: scheduledDate(startDate: startDate, weekOffset: item.weekIndex, weekday: item.scheduledWeekday),
                sessionType: item.sessionType,
                targetDistanceMeters: item.targetDistanceMeters,
                targetDurationSeconds: item.targetDurationSeconds,
                targetPaceMinPerMile: item.targetPaceMinPerMile,
                intensityLevel: item.intensityLevel,
                notes: item.notes,
                status: "pending"
            )
            context.insert(session)
        }

        plan.updatedAt = Date()
        _ = PersistenceSave.commit(context, action: "save changes")
        return plan
    }

    func blueprintsForTemplate(
        _ template: RunPlanTemplateDescriptor,
        profile: RunAssistantProfile,
        startDate: Date,
        context: ModelContext
    ) -> [RunPlanSessionBlueprint] {
        buildBuiltInBlueprints(template: template, profile: profile, startDate: startDate, context: context)
    }

    func setActivePlan(_ planID: UUID, context: ModelContext) {
        let allPlans = (try? context.fetch(FetchDescriptor<RunningPlan>())) ?? []
        var activePlan: RunningPlan?

        for plan in allPlans {
            if plan.id == planID {
                plan.isArchived = false
                plan.isActive = true
                plan.updatedAt = Date()
                activePlan = plan
            } else if plan.isActive {
                plan.isActive = false
                plan.updatedAt = Date()
                ReminderService.cancelRunningPlanReminders(planID: plan.id)
            }
        }

        if let activePlan {
            reschedulePlanRemindersIfNeeded(for: activePlan)
        }

        _ = PersistenceSave.commit(context, action: "save changes")
    }

    func archivePlan(_ planID: UUID, context: ModelContext) {
        guard let plan = fetchPlan(id: planID, context: context) else { return }
        plan.isArchived = true
        plan.isActive = false
        plan.updatedAt = Date()
        ReminderService.cancelRunningPlanReminders(planID: planID)
        _ = PersistenceSave.commit(context, action: "save changes")
    }

    func markSession(
        _ sessionID: UUID,
        status: String,
        completionSource: String?,
        completedRunSessionID: UUID?,
        context: ModelContext
    ) {
        guard let session = fetchSession(id: sessionID, context: context) else { return }
        session.status = status
        session.completionSource = completionSource
        session.completedRunSessionID = completedRunSessionID
        session.completedAt = (status == "completed" || status == "skipped") ? Date() : nil
        session.plan?.updatedAt = Date()
        _ = PersistenceSave.commit(context, action: "save changes")
    }

    func updateSessionIntensity(_ sessionID: UUID, intensityLevel: String, context: ModelContext) {
        guard let session = fetchSession(id: sessionID, context: context) else { return }
        session.intensityLevel = intensityLevel
        session.plan?.updatedAt = Date()
        _ = PersistenceSave.commit(context, action: "save changes")
    }

    func moveRestDay(
        planID: UUID,
        weekIndex: Int,
        fromWeekday: Int,
        toWeekday: Int,
        context: ModelContext
    ) {
        guard let plan = fetchPlan(id: planID, context: context),
              let sessions = plan.sessions else { return }

        let targetWeek = sessions.filter { $0.weekIndex == weekIndex }

        guard let restToMove = targetWeek.first(where: {
            $0.sessionType == "rest" && RunAssistantWeekday.weekday(of: $0.scheduledDate ?? plan.startDate) == fromWeekday
        }),
        let sessionToSwap = targetWeek.first(where: {
            $0.sessionType != "rest" && RunAssistantWeekday.weekday(of: $0.scheduledDate ?? plan.startDate) == toWeekday
        }) else {
            return
        }

        let oldType = sessionToSwap.sessionType
        let oldIntensity = sessionToSwap.intensityLevel
        let oldDistance = sessionToSwap.targetDistanceMeters
        let oldDuration = sessionToSwap.targetDurationSeconds
        let oldPace = sessionToSwap.targetPaceMinPerMile
        let oldNotes = sessionToSwap.notes

        sessionToSwap.sessionType = "rest"
        sessionToSwap.intensityLevel = "easy"
        sessionToSwap.targetDistanceMeters = nil
        sessionToSwap.targetDurationSeconds = nil
        sessionToSwap.targetPaceMinPerMile = nil
        sessionToSwap.notes = "Moved to rest day"

        restToMove.sessionType = oldType
        restToMove.intensityLevel = oldIntensity
        restToMove.targetDistanceMeters = oldDistance
        restToMove.targetDurationSeconds = oldDuration
        restToMove.targetPaceMinPerMile = oldPace
        restToMove.notes = oldNotes

        plan.updatedAt = Date()
        reschedulePlanRemindersIfNeeded(for: plan)
        _ = PersistenceSave.commit(context, action: "save changes")

    }

    func reconcileCompletions(activePlan: RunningPlan, runs: [RunningSession], context: ModelContext) {
        guard let sessions = activePlan.sessions, !sessions.isEmpty else { return }
        var didMutate = false

        // Heal previously auto-completed sessions that were matched before the plan started.
        for session in sessions where session.status == "completed" && session.completionSource == "auto" {
            if let completedAt = session.completedAt, completedAt < activePlan.startDate {
                session.status = "pending"
                session.completionSource = nil
                session.completedAt = nil
                session.completedRunSessionID = nil
                didMutate = true
            }
        }

        let eligibleRuns = runs
            .filter { ["running", "walking", "hiking"].contains($0.activityType) && $0.date >= activePlan.startDate }
            .sorted { $0.date < $1.date }

        var pendingSessions = sessions
            .filter { $0.status == "pending" }
            .sorted { lhs, rhs in
                if lhs.weekIndex == rhs.weekIndex {
                    return lhs.dayIndex < rhs.dayIndex
                }
                return lhs.weekIndex < rhs.weekIndex
            }

        var usedRunIDs = Set(sessions.compactMap { $0.completedRunSessionID })

        for run in eligibleRuns {
            guard !usedRunIDs.contains(run.id) else { continue }

            let runDistanceMeters = runDistanceInMeters(run)
            var bestMatchIndex: Int? = nil
            var bestScore: Double = .greatestFiniteMagnitude

            for (idx, session) in pendingSessions.enumerated() {
                guard session.status == "pending" else { continue }
                guard matches(run: run, runDistanceMeters: runDistanceMeters, session: session) else { continue }

                let dateScore: Double
                if let scheduled = session.scheduledDate {
                    dateScore = abs(scheduled.timeIntervalSince(run.date))
                } else {
                    dateScore = 0
                }

                if dateScore < bestScore {
                    bestScore = dateScore
                    bestMatchIndex = idx
                }
            }

            guard let bestMatchIndex else { continue }
            let session = pendingSessions.remove(at: bestMatchIndex)
            session.status = "completed"
            session.completionSource = "auto"
            session.completedAt = run.date
            session.completedRunSessionID = run.id
            usedRunIDs.insert(run.id)
            didMutate = true
        }

        if didMutate {
            activePlan.updatedAt = Date()
            _ = PersistenceSave.commit(context, action: "save changes")
        }
    }

    // MARK: - Shared helpers for UI

    func activePlan(context: ModelContext) -> RunningPlan? {
        let descriptor = FetchDescriptor<RunningPlan>(
            predicate: #Predicate { $0.isActive == true && $0.isArchived == false }
        )
        return (try? context.fetch(descriptor))?.first
    }

    func savedPlans(context: ModelContext) -> [RunningPlan] {
        let descriptor = FetchDescriptor<RunningPlan>(
            sortBy: [SortDescriptor(\RunningPlan.updatedAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.isArchived }
    }

    func sessionsForWeek(plan: RunningPlan, weekIndex: Int) -> [RunningPlanSession] {
        guard let sessions = plan.sessions, !sessions.isEmpty else { return [] }
        let clampedWeek = clampedWeekIndex(weekIndex, plan: plan)

        return sessions
            .filter { $0.weekIndex == clampedWeek }
            .sorted { lhs, rhs in
                let leftWeekday = weekdayNumber(for: lhs)
                let rightWeekday = weekdayNumber(for: rhs)
                if leftWeekday == rightWeekday {
                    return lhs.dayIndex < rhs.dayIndex
                }
                return leftWeekday < rightWeekday
            }
    }

    func isWeekComplete(plan: RunningPlan, weekIndex: Int) -> Bool {
        let weekSessions = sessionsForWeek(plan: plan, weekIndex: weekIndex)
        guard !weekSessions.isEmpty else { return false }
        return weekSessions.allSatisfy { $0.status != "pending" }
    }

    func calendarWeekIndex(plan: RunningPlan, referenceDate: Date = Date()) -> Int {
        let calendar = Calendar.current
        let raw = calendar.dateComponents([.weekOfYear], from: plan.startDate, to: referenceDate).weekOfYear ?? 0
        return clampedWeekIndex(max(0, raw), plan: plan)
    }

    func autoDisplayWeekIndex(plan: RunningPlan, referenceDate: Date = Date()) -> Int {
        let baseWeek = calendarWeekIndex(plan: plan, referenceDate: referenceDate)
        let lastWeek = max(0, plan.durationWeeks - 1)

        guard isWeekComplete(plan: plan, weekIndex: baseWeek), baseWeek < lastWeek else {
            return baseWeek
        }
        return baseWeek + 1
    }

    func sessionsForCurrentWeek(plan: RunningPlan, referenceDate: Date = Date()) -> [RunningPlanSession] {
        sessionsForWeek(
            plan: plan,
            weekIndex: calendarWeekIndex(plan: plan, referenceDate: referenceDate)
        )
    }

    func clampedWeekIndex(_ weekIndex: Int, plan: RunningPlan) -> Int {
        let maxWeek = max(0, plan.durationWeeks - 1)
        return min(max(0, weekIndex), maxWeek)
    }

    func totalWeekCount(plan: RunningPlan) -> Int {
        max(1, plan.durationWeeks)
    }

    // MARK: - Private

    private func fetchPlan(id: UUID, context: ModelContext) -> RunningPlan? {
        let plans = (try? context.fetch(FetchDescriptor<RunningPlan>())) ?? []
        return plans.first(where: { $0.id == id })
    }

    private func fetchSession(id: UUID, context: ModelContext) -> RunningPlanSession? {
        let sessions = (try? context.fetch(FetchDescriptor<RunningPlanSession>())) ?? []
        return sessions.first(where: { $0.id == id })
    }

    private func score(template: RunPlanTemplateDescriptor, profile: RunAssistantProfile) -> Int {
        var result = 0

        if abs(template.targetDistanceMiles - profile.targetDistanceMiles) < 0.01 { result += 80 }
        if template.primaryGoal == profile.goalFocus { result += 60 }
        if template.style == "hybrid" && profile.goalFocus == "hybrid" { result += 20 }
        if template.recommendedAbilityLevels.contains(profile.abilityLevel) { result += 35 }

        if profile.abilityLevel == "brand_new" && template.style.contains("intermediate") {
            result -= 30
        }

        // small tie-breaker favoring duration close to distance expectation
        result -= abs(template.durationWeeks - RunPlanCatalog.durationWeeks(targetMiles: profile.targetDistanceMiles, style: template.style))
        return result
    }

    private func buildBuiltInBlueprints(
        template: RunPlanTemplateDescriptor,
        profile: RunAssistantProfile,
        startDate: Date,
        context: ModelContext
    ) -> [RunPlanSessionBlueprint] {
        let weekdays = trainingWeekdays(daysPerWeek: profile.daysPerWeek, longRunWeekday: profile.longRunWeekday)
        let baselinePace = baselinePaceMinPerMile(
            context: context,
            abilityLevel: profile.abilityLevel,
            profileCurrentAveragePace: profile.currentAveragePaceMinPerMile
        )
        let targetMiles = template.targetDistanceMiles

        var output: [RunPlanSessionBlueprint] = []

        for week in 0..<template.durationWeeks {
            let weeklyFactor = weeklyProgressFactor(weekIndex: week, totalWeeks: template.durationWeeks)

            for (dayIdx, weekday) in weekdays.enumerated() {
                let sessionType = sessionTypeForDay(
                    style: template.style,
                    dayPosition: dayIdx,
                    dayCount: weekdays.count,
                    weekday: weekday,
                    longRunWeekday: profile.longRunWeekday
                )

                let distanceMiles = targetMilesForSession(
                    sessionType: sessionType,
                    weekIndex: week,
                    totalWeeks: template.durationWeeks,
                    targetMiles: targetMiles,
                    weeklyFactor: weeklyFactor,
                    abilityLevel: profile.abilityLevel
                )

                let paceMinPerMile = paceForSession(sessionType: sessionType, baselinePaceMinPerMile: baselinePace)

                let notes = notesForSession(
                    sessionType: sessionType,
                    weekIndex: week,
                    totalWeeks: template.durationWeeks,
                    targetMiles: targetMiles
                )

                if sessionType == "rest" {
                    output.append(
                        RunPlanSessionBlueprint(
                            weekIndex: week,
                            dayIndex: dayIdx,
                            scheduledWeekday: weekday,
                            sessionType: sessionType,
                            targetDistanceMeters: nil,
                            targetDurationSeconds: nil,
                            targetPaceMinPerMile: nil,
                            intensityLevel: "easy",
                            notes: notes
                        )
                    )
                    continue
                }

                let distanceMeters = distanceMiles * 1609.34
                let durationSeconds = max(0, distanceMiles * paceMinPerMile * 60.0)
                output.append(
                    RunPlanSessionBlueprint(
                        weekIndex: week,
                        dayIndex: dayIdx,
                        scheduledWeekday: weekday,
                        sessionType: sessionType,
                        targetDistanceMeters: distanceMeters,
                        targetDurationSeconds: durationSeconds,
                        targetPaceMinPerMile: paceMinPerMile,
                        intensityLevel: intensityForSession(sessionType),
                        notes: notes
                    )
                )
            }

            // Add passive rest days so week cards show full week context
            let planned = Set(weekdays)
            for weekday in 1...7 where !planned.contains(weekday) {
                output.append(
                    RunPlanSessionBlueprint(
                        weekIndex: week,
                        dayIndex: weekday + 100,
                        scheduledWeekday: weekday,
                        sessionType: "rest",
                        targetDistanceMeters: nil,
                        targetDurationSeconds: nil,
                        targetPaceMinPerMile: nil,
                        intensityLevel: "easy",
                        notes: "Recovery day"
                    )
                )
            }
        }

        return output.sorted {
            if $0.weekIndex == $1.weekIndex {
                if $0.scheduledWeekday == $1.scheduledWeekday {
                    return $0.dayIndex < $1.dayIndex
                }
                return $0.scheduledWeekday < $1.scheduledWeekday
            }
            return $0.weekIndex < $1.weekIndex
        }
    }

    private func baselinePaceMinPerMile(
        context: ModelContext,
        abilityLevel: String,
        profileCurrentAveragePace: Double?
    ) -> Double {
        if let profileCurrentAveragePace, profileCurrentAveragePace.isFinite, (5.0...20.0).contains(profileCurrentAveragePace) {
            return profileCurrentAveragePace
        }

        let runs = ((try? context.fetch(FetchDescriptor<RunningSession>())) ?? [])
            .filter { $0.duration > 0 && $0.distance > 0 }
            .prefix(20)

        var paces: [Double] = []
        for run in runs {
            let distanceMiles = run.distanceUnit == "mi" ? run.distance : run.distance / 1.60934
            guard distanceMiles > 0 else { continue }
            paces.append((run.duration / 60.0) / distanceMiles)
        }

        if !paces.isEmpty {
            let sorted = paces.sorted()
            return sorted[sorted.count / 2]
        }

        switch abilityLevel {
        case "brand_new": return 13.5
        case "continuous": return 10.5
        default: return 12.0
        }
    }

    private func weeklyProgressFactor(weekIndex: Int, totalWeeks: Int) -> Double {
        let baseGrowth = pow(1.09, Double(weekIndex))
        var factor = baseGrowth

        let weekNumber = weekIndex + 1
        if weekNumber % 4 == 0 {
            factor *= 0.85
        }

        if weekIndex == totalWeeks - 1 {
            factor *= 0.90
        }

        return factor
    }

    private func trainingWeekdays(daysPerWeek: Int, longRunWeekday: Int) -> [Int] {
        let validDays = min(max(daysPerWeek, 3), 6)
        let clampedLong = min(max(longRunWeekday, 1), 7)

        var candidates = [2, 3, 4, 5, 6]
        candidates.removeAll(where: { $0 == clampedLong })

        var selected: [Int] = [clampedLong]
        for day in candidates {
            if selected.count >= validDays { break }
            selected.append(day)
        }

        while selected.count < validDays {
            let fallback = ((selected.last ?? 1) % 7) + 1
            if !selected.contains(fallback) {
                selected.append(fallback)
            } else {
                break
            }
        }

        return selected.sorted()
    }

    private func sessionTypeForDay(
        style: String,
        dayPosition: Int,
        dayCount: Int,
        weekday: Int,
        longRunWeekday: Int
    ) -> String {
        if weekday == longRunWeekday {
            return "long"
        }

        let nonLongDayCount = max(1, dayCount - 1)
        let idx = min(dayPosition, nonLongDayCount - 1)

        switch style {
        case "endurance_beginner":
            let sequence = ["easy", "recovery", "easy", "tempo", "easy"]
            return sequence[min(idx, sequence.count - 1)]
        case "endurance_intermediate":
            let sequence = ["easy", "tempo", "easy", "recovery", "tempo"]
            return sequence[min(idx, sequence.count - 1)]
        case "speed_beginner":
            let sequence = ["easy", "interval", "easy", "tempo", "recovery"]
            return sequence[min(idx, sequence.count - 1)]
        case "speed_intermediate":
            let sequence = ["interval", "easy", "tempo", "interval", "recovery"]
            return sequence[min(idx, sequence.count - 1)]
        default: // hybrid
            let sequence = ["easy", "interval", "tempo", "easy", "recovery"]
            return sequence[min(idx, sequence.count - 1)]
        }
    }

    private func targetMilesForSession(
        sessionType: String,
        weekIndex: Int,
        totalWeeks: Int,
        targetMiles: Double,
        weeklyFactor: Double,
        abilityLevel: String
    ) -> Double {
        let abilityBase: Double
        switch abilityLevel {
        case "brand_new": abilityBase = 0.45
        case "continuous": abilityBase = 0.72
        default: abilityBase = 0.58
        }

        let sessionFraction: Double
        switch sessionType {
        case "long": sessionFraction = 1.0
        case "tempo": sessionFraction = 0.72
        case "interval": sessionFraction = 0.62
        case "easy": sessionFraction = 0.58
        case "recovery": sessionFraction = 0.45
        default: sessionFraction = 0
        }

        if sessionType == "long" && weekIndex == totalWeeks - 1 {
            return targetMiles
        }

        let value = max(0.4, targetMiles * abilityBase * weeklyFactor * sessionFraction)
        return min(max(value, 0.35), targetMiles)
    }

    private func paceForSession(sessionType: String, baselinePaceMinPerMile: Double) -> Double {
        switch sessionType {
        case "interval":
            return max(6.0, baselinePaceMinPerMile - 0.9)
        case "tempo":
            return max(6.0, baselinePaceMinPerMile - 0.5)
        case "easy":
            return baselinePaceMinPerMile + 0.8
        case "recovery":
            return baselinePaceMinPerMile + 1.2
        case "long":
            return baselinePaceMinPerMile + 0.5
        default:
            return baselinePaceMinPerMile
        }
    }

    private func intensityForSession(_ type: String) -> String {
        switch type {
        case "interval", "tempo": return "hard"
        case "long", "easy": return "moderate"
        case "recovery", "rest": return "easy"
        default: return "moderate"
        }
    }

    private func notesForSession(
        sessionType: String,
        weekIndex: Int,
        totalWeeks: Int,
        targetMiles: Double
    ) -> String {
        if weekIndex == totalWeeks - 1 && sessionType == "long" {
            return "Target test run: \(String(format: "%.1f", targetMiles)) mile goal effort"
        }

        switch sessionType {
        case "interval": return "Warm up 10 minutes, keep repeats controlled"
        case "tempo": return "Sustain comfortably hard effort"
        case "long": return "Keep effort conversational and steady"
        case "recovery": return "Very easy aerobic recovery"
        case "rest": return "Recovery day"
        default: return "Easy aerobic session"
        }
    }

    private func scheduledDate(startDate: Date, weekOffset: Int, weekday: Int) -> Date {
        RunAssistantWeekday.scheduledDate(startDate: startDate, weekOffset: weekOffset, weekday: weekday)
    }

    private func sessionWeekdays(for plan: RunningPlan) -> [Int] {
        guard let sessions = plan.sessions else { return [] }
        let calendar = Calendar.current
        let today = Date()
        let currentWeek = max(0, calendar.dateComponents([.weekOfYear], from: plan.startDate, to: today).weekOfYear ?? 0)

        let inCurrentWeek = sessions.filter { $0.weekIndex == currentWeek && $0.sessionType != "rest" }
        let currentWeekdays = inCurrentWeek.compactMap { $0.scheduledDate.map { RunAssistantWeekday.weekday(of: $0) } }
        if !currentWeekdays.isEmpty {
            return Array(Set(currentWeekdays)).sorted()
        }

        let week0 = sessions.filter { $0.weekIndex == 0 && $0.sessionType != "rest" }
        let fallback = week0.compactMap { $0.scheduledDate.map { RunAssistantWeekday.weekday(of: $0) } }
        return Array(Set(fallback)).sorted()
    }

    private func reschedulePlanRemindersIfNeeded(for plan: RunningPlan) {
        guard let profile = RunAssistantProfile.fromJSONString(plan.profileSnapshotJSON) else {
            ReminderService.cancelRunningPlanReminders(planID: plan.id)
            return
        }

        if profile.reminderEnabled && plan.isActive && !plan.isArchived {
            ReminderService.scheduleRunningPlanReminders(
                planID: plan.id,
                weekdays: sessionWeekdays(for: plan),
                hour: profile.reminderHour,
                minute: profile.reminderMinute,
                title: plan.name
            )
        } else {
            ReminderService.cancelRunningPlanReminders(planID: plan.id)
        }
    }

    private func runDistanceInMeters(_ run: RunningSession) -> Double {
        if run.distanceUnit == "mi" {
            return run.distance * 1609.34
        }
        return run.distance * 1000.0
    }

    private func matches(run: RunningSession, runDistanceMeters: Double, session: RunningPlanSession) -> Bool {
        if let scheduled = session.scheduledDate {
            let dateDistance = abs(scheduled.timeIntervalSince(run.date))
            if dateDistance > 3 * 24 * 60 * 60 { return false }
        }

        if let targetDistance = session.targetDistanceMeters, targetDistance > 0 {
            let tolerance = targetDistance * 0.10
            return abs(runDistanceMeters - targetDistance) <= tolerance
        }

        if let targetDuration = session.targetDurationSeconds, targetDuration > 0 {
            let tolerance = targetDuration * 0.10
            return abs(run.duration - targetDuration) <= tolerance
        }

        return false
    }

    private func weekdayNumber(for session: RunningPlanSession) -> Int {
        guard let date = session.scheduledDate else { return 8 }
        return RunAssistantWeekday.weekday(of: date)
    }
}
