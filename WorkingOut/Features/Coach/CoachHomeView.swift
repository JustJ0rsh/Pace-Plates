import SwiftUI
import SwiftData

struct CoachHomeView: View {
    private var persistence: PersistenceController { .shared }

    var body: some View {
        Group {
            if persistence.isCoachLocal {
                CoachLocalHomeView()
            } else {
                CoachStorageReviewView()
            }
        }
        .navigationTitle("Coach")
        .toolbar {
            if persistence.isCoachLocal {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Add Plan", destination: CoachAddPlanView())
                        .accessibilityIdentifier("coach.add_plan.toolbar")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AIPlannerView() } label: {
                    Label("Ask Coach", systemImage: "sparkles").labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("coach.ask")
            }
        }
    }
}

private struct CoachStorageReviewView: View {
    @State private var isCopying = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "figure.mixed.cardio").font(.largeTitle).foregroundStyle(AppTheme.accentColor)
                Text("Your program. Your progress.").font(.largeTitle.bold())
                Text("Build or import a program, follow each session, and track nutrition, recovery, and body measurements in one place.")
                VStack(alignment: .leading, spacing: 12) {
                    Label("Keep Coach on this device", systemImage: "lock.shield").font(.headline)
                    Text("To enable Coach, the app copies your existing history into protected local storage and verifies that your records are preserved. Every tab will use that same history.")
                    Text("After switching, new app records and edits on this device will no longer sync through the app’s legacy iCloud store. Use an explicit history backup to transfer or recover them. The original store is retained for recovery; existing remote records are not deleted.")
                    Text("Apple Health and your Photos library remain separate. A selected photo becomes a private app copy.")
                        .foregroundStyle(.secondary)
                }
                .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("coach.storage.error") }
                Button {
                    isCopying = true
                    Task { @MainActor in
                        do { try await PersistenceController.shared.adoptLocalOwnership() }
                        catch { self.error = error.localizedDescription }
                        isCopying = false
                    }
                } label: {
                    HStack {
                        if isCopying { ProgressView() }
                        Text(isCopying ? "Preparing and verifying your copy…" : "Copy History and Continue Locally")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCopying)
                .accessibilityIdentifier("coach.storage.continue")
                NavigationLink("Open existing Coach and AI history") { AIPlannerView() }
            }
            .padding().frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled(isCopying)
    }
}

private struct CoachLocalHomeView: View {
    var body: some View {
        CoachTodayView()
            .background(AppTheme.backgroundColor)
            .accessibilityIdentifier("coach.dashboard")
    }
}

enum CoachDate {
    static func civil(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
    static func date(_ civil: String, timeZone: TimeZone = .current) -> Date {
        let parts = civil.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard parts.count == 3 else { return calendar.startOfDay(for: Date()) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) ?? Date()
    }
}

struct CoachTodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TrainingPlan.updatedAt, order: .reverse) private var plans: [TrainingPlan]
    @Query private var occurrences: [PlannedSession]
    @State private var checkIn: CoachCheckInDestination?
    var compact = false
    var body: some View {
        let _ = (plans.map(\.updatedAt), occurrences.map(\.status))
        let result = Result { try CoachRepository(context: modelContext).today() }
        Group {
            switch result {
            case .success(let projection):
                if compact { content(projection) }
                else { ScrollView { content(projection).padding().frame(maxWidth: 900).frame(maxWidth: .infinity) } }
            case .failure(let error):
                ContentUnavailableView("Unable to load Coach", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
            }
        }
        .sheet(item: $checkIn) { destination in CoachCheckInView(destination: destination) }
    }

    private func content(_ projection: CoachTodayProjection) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let plan = projection.plan {
                NavigationLink { CoachProgramDetailView(plan: plan) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title).font(.title2.bold()).foregroundStyle(.primary)
                        Label("View Plan", systemImage: "calendar").font(.subheadline)
                        Text(Date(), format: .dateTime.weekday(.wide).month().day()).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("coach.plan.current")
                Text("Today").font(.headline)
                if projection.today.isEmpty { Text("No workouts planned today. Your next sessions are below.").foregroundStyle(.secondary) }
                ForEach(projection.today) { CoachSessionRow(session: $0) }
                if !projection.overdue.isEmpty {
                    DisclosureGroup("Overdue · \(projection.overdue.count)") {
                        ForEach(projection.overdue) { CoachSessionRow(session: $0) }
                    }
                }
                if !compact, !projection.next.isEmpty {
                    Text("Coming up").font(.headline)
                    ForEach(projection.next) { CoachSessionRow(session: $0, showDate: true) }
                }
            } else if let savedPlan = plans.first(where: { $0.currentRevisionID != nil && ["draft", "paused"].contains($0.status) }) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(savedPlan.status == "draft" ? "Your plan is saved" : "Your plan is paused").font(.title2.bold())
                    Text(savedPlan.title).font(.headline)
                    Text("Start your plan to see today’s workouts and runs here. You can also find them in the Workouts and Runs tabs.")
                        .foregroundStyle(.secondary)
                    NavigationLink { CoachProgramDetailView(plan: savedPlan) } label: {
                        Label(savedPlan.status == "draft" ? "Review and Start Plan" : "Review and Resume Plan", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("coach.plan.saved")
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your workouts, ready to follow").font(.title2.bold())
                    Text("Add a plan to schedule workouts and runs, then check them off as you go.")
                        .foregroundStyle(.secondary)
                    NavigationLink { CoachAddPlanView() } label: { Label("Add Plan", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("coach.add_plan")
                }
            }
            if !compact {
                ViewThatFits(in: .horizontal) {
                    HStack { planLinks }
                    VStack(alignment: .leading) { planLinks }
                }
                Divider()
                Text("Daily check-in").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack { checkInButtons }
                    VStack(alignment: .leading) { checkInButtons }
                }
                NavigationLink { CoachBodyProgressView() } label: {
                    Label("Weight, waist and photos", systemImage: "figure.stand")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var planLinks: some View {
        NavigationLink { CoachProgramLibraryView() } label: { Label("Your Plans", systemImage: "calendar") }
            .buttonStyle(.bordered).accessibilityIdentifier("coach.plans.open")
        NavigationLink { CoachProgressView() } label: { Label("Progress", systemImage: "chart.xyaxis.line") }
            .buttonStyle(.bordered).accessibilityIdentifier("coach.progress.open")
    }

    @ViewBuilder private var checkInButtons: some View {
        Button { checkIn = .nutrition(Date()) } label: { Label("Nutrition", systemImage: "fork.knife") }
            .buttonStyle(.bordered).accessibilityIdentifier("coach.nutrition.open")
        Button { checkIn = .recovery(Date()) } label: { Label("Recovery", systemImage: "moon.zzz") }
            .buttonStyle(.bordered).accessibilityIdentifier("coach.recovery.open")
    }
}

struct CoachSessionRow: View {
    let session: PlannedSession
    var showDate = false
    var body: some View {
        NavigationLink { CoachSessionDetailView(session: session) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title2).frame(width: 32).foregroundStyle(AppTheme.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title).font(.headline).foregroundStyle(.primary)
                    if showDate {
                        let zone = session.plan.map(CoachRepository.timeZone) ?? .current
                        Text(CoachDate.date(session.currentCivilDate ?? CoachDate.civil(session.scheduledDate, timeZone: zone), timeZone: zone),
                             format: Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(status + (session.isOptional ? " · Optional" : "")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: session.status == "completed" ? "checkmark.circle.fill" : "chevron.right")
                    .font(session.status == "completed" ? .title3 : .caption)
                    .foregroundStyle(session.status == "completed" ? Color.green : Color.secondary)
            }
            .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.today.session.\(session.id.uuidString)")
    }
    private var status: String {
        switch session.status {
        case "pending": return "Planned"
        case "in_progress": return "In progress · Resume"
        case "completed": return "Done"
        case "partial": return "Partly completed"
        default: return session.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private var icon: String {
        switch session.activityType {
        case "strength": return "figure.strengthtraining.traditional"
        case "run", "running": return "figure.run"
        case "rest": return "bed.double"
        case "recovery": return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }
}
