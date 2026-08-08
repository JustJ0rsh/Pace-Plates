import SwiftData
import SwiftUI

/// The action-first surface at the top of Home.
///
/// Priority is intentionally deterministic: recoverable cardio, the active
/// plan's current/next session, a repeatable workout, then weight check-in.
/// Plan persistence is adapted into `HomePlanSessionCandidate` so the Coach
/// model can replace/augment the legacy Running Assistant source in one place.
struct HomeTodayCard: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<RunningPlan>(\.updatedAt, order: .reverse)])
    private var runningPlans: [RunningPlan]
    @Query(sort: [SortDescriptor<RunningSession>(\.date, order: .reverse)])
    private var runningSessions: [RunningSession]
    @Query(sort: [SortDescriptor<TrainingPlan>(\.updatedAt, order: .reverse)])
    private var trainingPlans: [TrainingPlan]
    @Query private var workoutTemplates: [WorkoutTemplate]
    @Query private var runningPlanSessions: [RunningPlanSession]

    let workoutSessions: [WorkoutSession]
    let weightEntries: [WeightEntry]
    let preferredWeightUnit: String
    let distanceUnit: String
    let runTracker: RunTracker
    let onStartCardio: (String, ScheduledRunTarget?) -> Void
    let onOpenWorkout: (WorkoutSession) -> Void
    let onLogWeight: () -> Void
    let onSaveError: (String) -> Void

    private enum HomePlanSessionTiming {
        case today
        case upcoming
        case overdue
        case unscheduled

        var allowsDisposition: Bool {
            switch self {
            case .today, .overdue:
                return true
            case .upcoming, .unscheduled:
                return false
            }
        }
    }

    /// Extend this enum when the generalized Coach source is ready. The card
    /// content and priority rules do not need to know which model supplied it.
    private enum HomePlanSessionSource {
        case coach(plan: TrainingPlan, session: PlannedSession)
        case runningAssistant(plan: RunningPlan, session: RunningPlanSession)
    }

    private enum HomePlanMoveSource {
        case coach(date: Date)
        case runningAssistant(restSession: RunningPlanSession)
    }

    private struct HomePlanMoveOption: Identifiable {
        let id: UUID
        let date: Date
        let source: HomePlanMoveSource
    }

    private struct HomePlanSessionCandidate: Identifiable {
        let id: UUID
        let planName: String
        let sessionName: String
        let scheduleText: String
        let summaryText: String
        let timing: HomePlanSessionTiming
        let icon: String
        let primaryActionTitle: String
        let primaryActionIcon: String
        let moveOptions: [HomePlanMoveOption]
        let source: HomePlanSessionSource
    }

    private var activeRunningPlan: RunningPlan? {
        runningPlans.first(where: { $0.isActive && !$0.isArchived })
    }

    private var activeTrainingPlan: TrainingPlan? {
        trainingPlans.first(where: { $0.status == "active" })
    }

    private var lastRepeatableWorkout: WorkoutSession? {
        workoutSessions.first(where: { !($0.exerciseLogs ?? []).isEmpty })
    }

    private var badgeText: String {
        if runTracker.hasRecoverableActivity { return "In Progress" }
        if homePlanSessionCandidate != nil { return "Plan" }
        if lastRepeatableWorkout != nil { return "Repeat" }
        return "Check-in"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today")
                    .font(.title3.weight(.bold))

                Spacer(minLength: 8)

                Text(badgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.accentColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            primaryContent
        }
        .floatingTile()
        .accessibilityIdentifier("home.today.card")
        .task(id: activeRunningPlan?.id) {
            reconcileRunningPlanIfNeeded()
        }
        .onChange(of: runningSessions.count) { _, _ in
            reconcileRunningPlanIfNeeded()
        }
    }

    @ViewBuilder
    private var primaryContent: some View {
        if runTracker.hasRecoverableActivity {
            hero(
                icon: activeActivityIcon,
                eyebrow: activeActivityStatus,
                title: "Resume \(activeActivityName)",
                detail: activeActivitySummary
            )

            Button {
                onStartCardio(runTracker.activityType, nil)
            } label: {
                Label("Resume \(activeActivityName)", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            .accessibilityLabel(activeActivityAccessibilityLabel)
            .accessibilityHint("Opens the active activity.")
            .accessibilityIdentifier("home.activeActivity.resume")
        } else if let candidate = homePlanSessionCandidate {
            hero(
                icon: candidate.icon,
                eyebrow: "\(candidate.planName) • \(candidate.scheduleText)",
                title: candidate.sessionName,
                detail: candidate.summaryText
            )

            Button {
                startPlanSession(candidate)
            } label: {
                Label(candidate.primaryActionTitle, systemImage: candidate.primaryActionIcon)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home.today.plan.start")

            if candidate.timing.allowsDisposition || !candidate.moveOptions.isEmpty {
                planOptionsMenu(candidate)
            }
        } else if let workout = lastRepeatableWorkout {
            hero(
                icon: "figure.strengthtraining.traditional",
                eyebrow: "Last trained \(workout.date.formatted(date: .abbreviated, time: .omitted))",
                title: workout.title.isEmpty ? "Repeat Workout" : workout.title,
                detail: repeatWorkoutSummary(workout)
            )

            Button {
                repeatWorkout(workout)
            } label: {
                Label("Repeat Workout", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home.today.workout.repeat")
        } else {
            hero(
                icon: "scalemass",
                eyebrow: "Daily check-in",
                title: "Log Weight",
                detail: weightCheckInSummary
            )

            Button {
                Haptics.playImpact(.light)
                onLogWeight()
            } label: {
                Label("Log Weight", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            .accessibilityIdentifier("home.today.weight.log")
        }
    }

    private func hero(
        icon: String,
        eyebrow: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 44, height: 44)
                .background(AppTheme.accentColor.opacity(0.16))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryTextColor)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textColor)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func planOptionsMenu(_ candidate: HomePlanSessionCandidate) -> some View {
        Menu {
            if candidate.timing.allowsDisposition {
                Button {
                    completePlanSession(candidate)
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle")
                }

                Button {
                    skipPlanSession(candidate)
                } label: {
                    Label("Skip Session", systemImage: "forward.end")
                }
            }

            if !candidate.moveOptions.isEmpty {
                Section("Move Session") {
                    ForEach(candidate.moveOptions) { option in
                        Button {
                            movePlanSession(candidate, to: option)
                        } label: {
                            Label(
                                option.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                                systemImage: "calendar"
                            )
                        }
                    }
                }
            }
        } label: {
            Label("Plan Options", systemImage: "ellipsis.circle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(minHeight: 44)
        .accessibilityHint("Complete, skip, or move this planned session.")
        .accessibilityIdentifier("home.today.plan.options")
    }

    // MARK: - Plan adapter

    /// Legacy Running Assistant fallback. Replace or precede this factory with
    /// a generalized `PlannedSession` query when the Coach model is integrated.
    private var homePlanSessionCandidate: HomePlanSessionCandidate? {
        if let plan = activeTrainingPlan,
           let candidate = coachCandidate(for: plan) {
            return candidate
        }

        guard let plan = activeRunningPlan else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let pendingSessions = (plan.sessions ?? [])
            .filter { $0.sessionType != "rest" && $0.status == "pending" }

        let todaysSession = pendingSessions
            .filter { session in
                guard let date = session.scheduledDate else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }
            .sorted { $0.dayIndex < $1.dayIndex }
            .first

        let upcomingSession = pendingSessions
            .filter { ($0.scheduledDate ?? .distantPast) >= tomorrow }
            .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            .first

        let overdueSession = pendingSessions
            .filter { ($0.scheduledDate ?? .distantFuture) < today }
            .sorted { ($0.scheduledDate ?? .distantPast) > ($1.scheduledDate ?? .distantPast) }
            .first

        let unscheduledSession = pendingSessions
            .filter { $0.scheduledDate == nil }
            .sorted {
                if $0.weekIndex == $1.weekIndex { return $0.dayIndex < $1.dayIndex }
                return $0.weekIndex < $1.weekIndex
            }
            .first

        let selection: (RunningPlanSession, HomePlanSessionTiming)? = {
            if let todaysSession { return (todaysSession, .today) }
            if let upcomingSession { return (upcomingSession, .upcoming) }
            if let overdueSession { return (overdueSession, .overdue) }
            if let unscheduledSession { return (unscheduledSession, .unscheduled) }
            return nil
        }()

        guard let (session, timing) = selection else { return nil }

        let moveOptions = (plan.sessions ?? [])
            .filter { restSession in
                guard restSession.sessionType == "rest",
                      restSession.status == "pending",
                      restSession.weekIndex == session.weekIndex,
                      let restDate = restSession.scheduledDate,
                      let sessionDate = session.scheduledDate
                else { return false }

                return restDate >= today && !calendar.isDate(restDate, inSameDayAs: sessionDate)
            }
            .compactMap { restSession -> HomePlanMoveOption? in
                guard let date = restSession.scheduledDate else { return nil }
                return HomePlanMoveOption(
                    id: restSession.id,
                    date: date,
                    source: .runningAssistant(restSession: restSession)
                )
            }
            .sorted { $0.date < $1.date }

        return HomePlanSessionCandidate(
            id: session.id,
            planName: plan.name,
            sessionName: planSessionName(session),
            scheduleText: planScheduleText(for: session.scheduledDate, timing: timing),
            summaryText: planSessionSummary(session),
            timing: timing,
            icon: "figure.run",
            primaryActionTitle: "Start Planned Run",
            primaryActionIcon: "play.fill",
            moveOptions: moveOptions,
            source: .runningAssistant(plan: plan, session: session)
        )
    }

    private func coachCandidate(for plan: TrainingPlan) -> HomePlanSessionCandidate? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let pending = (plan.sessions ?? [])
            .filter { $0.status == "pending" && $0.activityType != "rest" }

        let todaySession = pending
            .filter { calendar.isDate($0.scheduledDate, inSameDayAs: today) }
            .sorted { $0.dayIndex < $1.dayIndex }
            .first
        let upcoming = pending
            .filter { $0.scheduledDate > today }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .first
        let overdue = pending
            .filter { $0.scheduledDate < today }
            .sorted { $0.scheduledDate > $1.scheduledDate }
            .first

        let selection: (PlannedSession, HomePlanSessionTiming)? = {
            if let todaySession { return (todaySession, .today) }
            if let upcoming { return (upcoming, .upcoming) }
            if let overdue { return (overdue, .overdue) }
            return nil
        }()
        guard let (session, timing) = selection else { return nil }

        let moveOptions = (1...3).compactMap { offset -> HomePlanMoveOption? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  !calendar.isDate(date, inSameDayAs: session.scheduledDate) else { return nil }
            return HomePlanMoveOption(id: UUID(), date: date, source: .coach(date: date))
        }

        return HomePlanSessionCandidate(
            id: session.id,
            planName: plan.title,
            sessionName: session.title,
            scheduleText: planScheduleText(for: session.scheduledDate, timing: timing),
            summaryText: coachSessionSummary(session),
            timing: timing,
            icon: coachIcon(for: session.activityType),
            primaryActionTitle: coachActionTitle(for: session.activityType),
            primaryActionIcon: session.activityType == "recovery" ? "checkmark" : "play.fill",
            moveOptions: moveOptions,
            source: .coach(plan: plan, session: session)
        )
    }

    private func coachIcon(for activityType: String) -> String {
        switch activityType {
        case "run": return "figure.run"
        case "strength": return "dumbbell.fill"
        case "recovery": return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }

    private func coachActionTitle(for activityType: String) -> String {
        switch activityType {
        case "run": return "Start Planned Run"
        case "recovery": return "Finish Recovery"
        default: return "Start Workout"
        }
    }

    private func coachSessionSummary(_ session: PlannedSession) -> String {
        var parts: [String] = []
        if let meters = session.targetDistanceMeters, meters > 0 {
            let divisor = distanceUnit == "km" ? 1_000.0 : 1_609.344
            parts.append("\((meters / divisor).formatted(.number.precision(.fractionLength(1)))) \(distanceUnit)")
        }
        if let seconds = session.targetDurationSeconds, seconds >= 60 {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }
        if let pace = session.targetPaceMinPerMile, pace > 0 {
            let converted = distanceUnit == "km" ? pace / 1.609_344 : pace
            let totalSeconds = Int((converted * 60).rounded())
            parts.append(String(format: "%d:%02d/%@", totalSeconds / 60, totalSeconds % 60, distanceUnit))
        }
        if let intensity = session.intensityLevel, !intensity.isEmpty {
            parts.append(intensity.capitalized)
        }
        if parts.isEmpty, let notes = session.notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? "Coach session" : parts.joined(separator: " • ")
    }

    private func planSessionName(_ session: RunningPlanSession) -> String {
        let name = session.sessionType
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
        return name.lowercased().contains("run") ? name : "\(name) Run"
    }

    private func planScheduleText(for date: Date?, timing: HomePlanSessionTiming) -> String {
        switch timing {
        case .today:
            return "Scheduled today"
        case .upcoming:
            guard let date else { return "Up next" }
            return "Next • \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        case .overdue:
            guard let date else { return "Needs attention" }
            return "Overdue • \(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))"
        case .unscheduled:
            return "Up next"
        }
    }

    private func planSessionSummary(_ session: RunningPlanSession) -> String {
        var parts: [String] = []

        if let meters = session.targetDistanceMeters, meters > 0 {
            let divisor = distanceUnit == "km" ? 1_000.0 : 1_609.344
            let distance = (meters / divisor).formatted(.number.precision(.fractionLength(1)))
            parts.append("\(distance) \(distanceUnit)")
        }

        if let seconds = session.targetDurationSeconds, seconds >= 60 {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }

        if let pace = session.targetPaceMinPerMile, pace > 0 {
            let convertedPace = distanceUnit == "km" ? pace / 1.609_344 : pace
            let totalSeconds = max(0, Int((convertedPace * 60).rounded()))
            parts.append(String(format: "%d:%02d/%@", totalSeconds / 60, totalSeconds % 60, distanceUnit))
        }

        if parts.isEmpty,
           let notes = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            parts.append(notes)
        }

        if parts.isEmpty {
            parts.append("\(session.intensityLevel.capitalized) effort")
        }
        return parts.joined(separator: " • ")
    }

    // MARK: - Actions

    private func startPlanSession(_ candidate: HomePlanSessionCandidate) {
        switch candidate.source {
        case let .coach(_, session):
            switch session.activityType {
            case "run":
                let target: ScheduledRunTarget
                if let sourceID = session.runningPlanSessionID,
                   let source = runningPlanSessions.first(where: { $0.id == sourceID }) {
                    target = ScheduledRunTarget(session: source)
                } else {
                    target = ScheduledRunTarget(
                        sessionID: session.id,
                        sessionType: "planned",
                        targetDistanceMeters: session.targetDistanceMeters,
                        targetDurationSeconds: session.targetDurationSeconds,
                        targetPaceMinPerMile: session.targetPaceMinPerMile,
                        intensityLevel: session.intensityLevel ?? "moderate",
                        notes: session.notes
                    )
                }
                onStartCardio("running", target)
            case "recovery":
                TrainingPlanService.shared.mark(session, status: "completed", context: modelContext)
            default:
                guard let templateID = session.workoutTemplateID,
                      let template = workoutTemplates.first(where: { $0.id == templateID }) else {
                    onSaveError("This planned workout is missing its template. Rebuild it from Coach.")
                    return
                }
                let workout = WorkoutTemplateService.shared.createWorkoutFromTemplate(
                    template: template,
                    context: modelContext
                )
                onOpenWorkout(workout)
            }
        case let .runningAssistant(_, session):
            onStartCardio("running", ScheduledRunTarget(session: session))
        }
    }

    private func completePlanSession(_ candidate: HomePlanSessionCandidate) {
        switch candidate.source {
        case let .coach(_, session):
            TrainingPlanService.shared.mark(session, status: "completed", context: modelContext)
        case let .runningAssistant(_, session):
            RunAssistantService.shared.markSession(
                session.id,
                status: "completed",
                completionSource: "manual",
                completedRunSessionID: nil,
                context: modelContext
            )
        }
        Haptics.notify(.success)
    }

    private func skipPlanSession(_ candidate: HomePlanSessionCandidate) {
        switch candidate.source {
        case let .coach(_, session):
            TrainingPlanService.shared.mark(session, status: "skipped", context: modelContext)
        case let .runningAssistant(_, session):
            RunAssistantService.shared.markSession(
                session.id,
                status: "skipped",
                completionSource: "manual",
                completedRunSessionID: nil,
                context: modelContext
            )
        }
        Haptics.notify(.warning)
    }

    private func movePlanSession(
        _ candidate: HomePlanSessionCandidate,
        to option: HomePlanMoveOption
    ) {
        switch (candidate.source, option.source) {
        case let (.coach(_, session), .coach(date)):
            TrainingPlanService.shared.move(session, to: date, context: modelContext)
        case let (.runningAssistant(plan, session), .runningAssistant(restSession)):
            guard let sessionDate = session.scheduledDate,
                  let restDate = restSession.scheduledDate
            else { return }

            RunAssistantService.shared.moveRestDay(
                planID: plan.id,
                weekIndex: session.weekIndex,
                fromWeekday: RunAssistantWeekday.weekday(of: restDate),
                toWeekday: RunAssistantWeekday.weekday(of: sessionDate),
                context: modelContext
            )
        default:
            return
        }
        Haptics.playImpact(.light)
    }

    private func repeatWorkout(_ source: WorkoutSession) {
        let session = WorkoutSession(
            date: Date(),
            notes: source.notes,
            title: source.title,
            sourceTemplateID: source.sourceTemplateID
        )
        modelContext.insert(session)

        let sourceLogs = (source.exerciseLogs ?? []).sorted {
            if $0.exerciseOrder == $1.exerciseOrder {
                return $0.setNumber < $1.setNumber
            }
            return $0.exerciseOrder < $1.exerciseOrder
        }

        for sourceLog in sourceLogs {
            let copy = ExerciseLog(
                reps: sourceLog.reps,
                weight: sourceLog.weight,
                weightUnit: sourceLog.weightUnit,
                setNumber: sourceLog.setNumber,
                exerciseName: sourceLog.exerciseName,
                exerciseOrder: sourceLog.exerciseOrder,
                exerciseType: sourceLog.exerciseType,
                durationSeconds: sourceLog.durationSeconds,
                distance: sourceLog.distance,
                distanceUnit: sourceLog.distanceUnit,
                caloriesBurned: nil,
                avgHeartRate: nil,
                notes: sourceLog.notes,
                isCompleted: false
            )
            copy.exerciseDefinition = sourceLog.exerciseDefinition
            copy.isIsolated = sourceLog.isIsolated
            copy.workoutSession = session
            modelContext.insert(copy)
        }

        guard PersistenceSave.commit(
            modelContext,
            action: "repeat workout",
            onFailure: onSaveError
        ) else {
            modelContext.delete(session)
            return
        }

        Haptics.notify(.success)
        onOpenWorkout(session)
    }

    private func reconcileRunningPlanIfNeeded() {
        guard let plan = activeRunningPlan else { return }
        RunAssistantService.shared.reconcileCompletions(
            activePlan: plan,
            runs: runningSessions,
            context: modelContext
        )
    }

    // MARK: - Formatting

    private var activeActivityName: String {
        switch runTracker.activityType {
        case "walking": return "Walk"
        case "hiking": return "Hike"
        case "cycling": return "Ride"
        case "rowing": return "Row"
        case "elliptical": return "Elliptical"
        case "stairStepper", "stairClimbing": return "Stair Climb"
        default: return "Run"
        }
    }

    private var activeActivityIcon: String {
        switch runTracker.activityType {
        case "walking": return "figure.walk"
        case "hiking": return "figure.hiking"
        case "cycling": return "bicycle"
        case "rowing": return "figure.rower"
        case "elliptical": return "figure.core.training"
        case "stairStepper", "stairClimbing": return "figure.stairs"
        default: return "figure.run"
        }
    }

    private var activeActivityStatus: String {
        runTracker.isRunning ? "Active" : "Paused"
    }

    private var activeActivityDistance: Double {
        runTracker.distance / (distanceUnit == "km" ? 1_000 : 1_609.344)
    }

    private var activeActivitySummary: String {
        let distance = activeActivityDistance.formatted(.number.precision(.fractionLength(2)))
        return "\(activeActivityStatus) • \(formatActivityDuration(runTracker.duration)) • \(distance) \(distanceUnit)"
    }

    private var activeActivityAccessibilityLabel: String {
        let distance = activeActivityDistance.formatted(.number.precision(.fractionLength(2)))
        let distanceName = distanceUnit == "km" ? "kilometers" : "miles"
        return "Resume \(activeActivityName), \(activeActivityStatus.lowercased()), \(accessibleActivityDuration(runTracker.duration)), \(distance) \(distanceName)"
    }

    private func formatActivityDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func accessibleActivityDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60
        var parts: [String] = []

        if hours > 0 {
            parts.append("\(hours) \(hours == 1 ? "hour" : "hours")")
        }
        if minutes > 0 || hours > 0 {
            parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")")
        }
        parts.append("\(seconds) \(seconds == 1 ? "second" : "seconds")")
        return parts.joined(separator: ", ")
    }

    private var weightCheckInSummary: String {
        guard let entry = weightEntries.first else {
            return "Add a baseline so your progress has somewhere to begin."
        }

        let convertedWeight = UnitConverter.weight(
            entry.weight,
            from: entry.weightUnit,
            to: preferredWeightUnit
        )
        let weight = convertedWeight.formatted(.number.precision(.fractionLength(1)))
        if Calendar.current.isDateInToday(entry.date) {
            return "Today’s entry is \(weight) \(preferredWeightUnit). Add another measurement if needed."
        }
        return "Last entry: \(weight) \(preferredWeightUnit) on \(entry.date.formatted(date: .abbreviated, time: .omitted))."
    }

    private func repeatWorkoutSummary(_ session: WorkoutSession) -> String {
        let logs = session.exerciseLogs ?? []
        let exerciseCount = Set(logs.compactMap(\.exerciseName)).count
        let exerciseText = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        let setText = logs.count == 1 ? "1 set" : "\(logs.count) sets"
        return "\(exerciseText) • \(setText)"
    }
}
