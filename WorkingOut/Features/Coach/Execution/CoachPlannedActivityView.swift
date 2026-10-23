import SwiftData
import SwiftUI

enum CoachPlannedActivityKind: String {
    case workouts, runs

    var title: String { self == .workouts ? "Planned Workouts" : "Planned Runs & Cardio" }
    var icon: String { self == .workouts ? "dumbbell.fill" : "figure.run" }

    func includes(_ activityType: String) -> Bool {
        switch self {
        case .workouts: return activityType == "strength"
        case .runs: return ["run", "running", "cardio"].contains(activityType)
        }
    }
}

/// Projects canonical occurrences directly; viewing a plan never creates activity history.
struct CoachPlannedActivities {
    let sessions: [PlannedSession]

    init(_ occurrences: [PlannedSession], kind: CoachPlannedActivityKind) {
        sessions = occurrences.filter {
            guard let plan = $0.plan else { return false }
            return plan.currentRevisionID != nil && plan.status != "archived"
                && $0.revisionID != nil && $0.prescriptionData != nil
                && $0.completionProvenance != "removed_by_reviewed_revision"
                && kind.includes($0.activityType)
        }.sorted {
            (Self.priority($0), $0.scheduledDate, $0.intraDayOrder, $0.id.uuidString)
                < (Self.priority($1), $1.scheduledDate, $1.intraDayOrder, $1.id.uuidString)
        }
    }

    var outstanding: [PlannedSession] { sessions.filter { ["pending", "in_progress"].contains($0.status) } }
    var preview: [PlannedSession] { Array(sessions.prefix(3)) }

    static func needsPlanReview(_ session: PlannedSession) -> Bool {
        if session.status == "in_progress", session.executionID != nil { return false }
        return session.plan?.status != "active" && !["completed", "partial"].contains(session.status)
    }

    private static func priority(_ session: PlannedSession) -> Int {
        if session.status == "in_progress", session.executionID != nil { return 0 }
        if session.plan?.status == "active" {
            if session.status == "in_progress" { return 0 }
            if session.status == "pending" { return 1 }
        }
        if ["pending", "in_progress"].contains(session.status) { return 2 }
        return 3
    }
}

struct CoachPlannedActivityCard: View {
    let kind: CoachPlannedActivityKind
    let projection: CoachPlannedActivities

    var body: some View {
        if !projection.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label(kind.title, systemImage: kind.icon).font(.headline)
                    .accessibilityIdentifier("\(kind.rawValue).planned")
                Text("\(projection.outstanding.count) to do · \(projection.sessions.count) planned")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(projection.preview) { session in
                    CoachPlannedActivityRow(session: session, kind: kind)
                }
                NavigationLink {
                    CoachPlannedActivityList(kind: kind)
                } label: {
                    Label("All planned sessions", systemImage: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("\(kind.rawValue).planned.all")
            }
            .floatingTile()
        }
    }
}

private struct CoachPlannedActivityList: View {
    let kind: CoachPlannedActivityKind
    @Query private var occurrences: [PlannedSession]
    @Query private var plans: [TrainingPlan]

    var body: some View {
        let _ = plans.map(\.updatedAt)
        let projection = CoachPlannedActivities(occurrences, kind: kind)
        List {
            Section {
                ForEach(projection.sessions) { session in
                    CoachPlannedActivityRow(session: session, kind: kind)
                }
            } header: {
                Text("All planned sessions")
                    .accessibilityIdentifier("\(kind.rawValue).planned.list")
            }
        }
        .overlay {
            if projection.sessions.isEmpty {
                ContentUnavailableView("No planned sessions", systemImage: kind.icon,
                    description: Text("Your saved Coach program sessions appear here."))
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CoachPlannedActivityRow: View {
    let session: PlannedSession
    let kind: CoachPlannedActivityKind

    var body: some View {
        NavigationLink {
            if CoachPlannedActivities.needsPlanReview(session), let plan = session.plan {
                CoachProgramDetailView(plan: plan)
            } else {
                CoachSessionDetailView(session: session)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon).foregroundStyle(AppTheme.accentColor)
                    .font(.title3).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.headline).foregroundStyle(.primary)
                    Text(session.scheduledDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted,
                        timeZone: TimeZone(identifier: session.plan?.timeZoneIdentifier ?? "") ?? .current)))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let plan = session.plan { Text(plan.title).font(.caption).foregroundStyle(.secondary) }
                    Text(statusText + (session.isOptional ? " · Optional" : ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(kind.rawValue).planned.session.\(session.id.uuidString)")
    }

    private var statusText: String {
        if CoachPlannedActivities.needsPlanReview(session) {
            return "\((session.plan?.status ?? "draft").capitalized) · Review program"
        }
        switch session.status {
        case "pending": return "Planned · Start session"
        case "in_progress": return "In progress · Resume"
        case "completed": return "Done"
        case "partial": return "Partly completed"
        default: return session.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private var statusIcon: String {
        switch session.status {
        case "completed": return "checkmark.circle.fill"
        case "partial": return "circle.lefthalf.filled"
        case "skipped": return "forward.end.circle"
        case "in_progress": return "play.circle.fill"
        default: return "calendar"
        }
    }
}
