import SwiftUI
import SwiftData
import EventKit
import UserNotifications

@MainActor
final class CoachCalendarProjection {
    private let store: EKEventStore
    private let context: ModelContext
    private static var reminderOperationID: UUID?
    init(context: ModelContext, store: EKEventStore = EKEventStore()) { self.context = context; self.store = store }

    private enum ProjectionError: LocalizedError {
        case unresolved, ambiguous, changedIdentity, staleSelection, remindersBusy
        var errorDescription: String? {
            switch self {
            case .unresolved: return "The saved Calendar event could not be verified. Its mapping was kept. Restore access to its calendar, then retry the export using the same destination calendar."
            case .ambiguous: return "More than one Calendar event has this saved link. No changes were made. Resolve the duplicate events in Calendar before retrying."
            case .changedIdentity: return "The saved Calendar event no longer has its expected link. Its mapping was kept for review."
            case .staleSelection: return "The selected sessions changed while this operation was waiting. Review their current dates and try again."
            case .remindersBusy: return "Reminder scheduling is already running. Wait for it to finish, then try again."
            }
        }
    }
    private struct ExportRequest {
        let row: PlannedSession
        let mapping: CoachCalendarMapping?
        let event: EKEvent?
        let start: Date
        let zone: TimeZone
    }
    struct OccurrenceSnapshot: Equatable {
        let id: UUID
        let planID: UUID?
        let planStatus: String?
        let timeZoneIdentifier: String
        let civilDate: String?
        let scheduledDate: Date
        let scheduleRevision: Int
        let status: String
        let activityType: String
        let completionProvenance: String?
        let executionID: UUID?
        let title: String

        @MainActor init(_ row: PlannedSession) {
            id = row.id; planID = row.plan?.id; planStatus = row.plan?.status
            timeZoneIdentifier = row.plan.map(CoachRepository.timeZone)?.identifier ?? TimeZone.current.identifier
            civilDate = row.currentCivilDate; scheduledDate = row.scheduledDate; scheduleRevision = row.scheduleRevision
            status = row.status; activityType = row.activityType; completionProvenance = row.completionProvenance
            executionID = row.executionID; title = row.title
        }
    }
    struct Selection: Equatable {
        let occurrences: [OccurrenceSnapshot]
        let purgeGeneration: Int
    }

    static func beginReminderOperation() throws -> UUID {
        guard reminderOperationID == nil else { throw ProjectionError.remindersBusy }
        let id = UUID(); reminderOperationID = id; return id
    }

    static func finishReminderOperation(_ id: UUID) {
        if reminderOperationID == id { reminderOperationID = nil }
    }

    static func captureSelection(_ rows: [PlannedSession], context: ModelContext) throws -> Selection {
        try CoachRepository(context: context).requireLocal()
        let ids = rows.map(\.id)
        guard Set(ids).count == ids.count else { throw CoachRepositoryError.invalidValue("distinct selected sessions") }
        let fresh = ModelContext(context.container); fresh.autosaveEnabled = false
        let saved = try fresh.fetch(FetchDescriptor<PlannedSession>())
        let snapshots = try ids.map { id in
            guard let row = saved.first(where: { $0.id == id }) else { throw ProjectionError.staleSelection }
            return OccurrenceSnapshot(row)
        }
        return Selection(occurrences: snapshots, purgeGeneration: WearableWorkoutInboxService.localDataPurgeGeneration)
    }

    static func validateSelection(_ selection: Selection, context: ModelContext) throws {
        try Task.checkCancellation()
        guard WearableWorkoutInboxService.isCurrentLocalDataPurgeGeneration(selection.purgeGeneration) else { throw ProjectionError.staleSelection }
        let fresh = ModelContext(context.container); fresh.autosaveEnabled = false
        let saved = try fresh.fetch(FetchDescriptor<PlannedSession>())
        for snapshot in selection.occurrences {
            guard let row = saved.first(where: { $0.id == snapshot.id }), OccurrenceSnapshot(row) == snapshot else { throw ProjectionError.staleSelection }
        }
    }

    func calendars() async throws -> [EKCalendar] {
        guard try await store.requestFullAccessToEvents() else { throw WorkoutCalendarService.CalendarError.accessDenied }
        return store.calendars(for: .event).filter(\.allowsContentModifications)
    }

    private func isolatedContext() throws -> ModelContext {
        try CoachRepository(context: context).requireLocal()
        let isolated = ModelContext(context.container); isolated.autosaveEnabled = false
        return isolated
    }

    private func selectedRows(_ selection: Selection, context: ModelContext) throws -> [PlannedSession] {
        let saved = try context.fetch(FetchDescriptor<PlannedSession>())
        return try selection.occurrences.map { snapshot in
            guard let row = saved.first(where: { $0.id == snapshot.id }) else { throw CoachRepositoryError.missingRecord }
            return row
        }
    }

    private func startDate(_ row: PlannedSession, hour: Int) throws -> (Date, TimeZone) {
        guard (0...23).contains(hour) else { throw CoachRepositoryError.invalidValue("calendar start hour from 0 to 23") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = row.plan.map(CoachRepository.timeZone) ?? .current
        let civil = row.currentCivilDate ?? CoachRepository.civilDate(row.scheduledDate, timeZone: calendar.timeZone)
        let day = try CoachRepository.date(civil, timeZone: calendar.timeZone)
        guard let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { throw CoachRepositoryError.invalidValue("calendar start time") }
        return (start, calendar.timeZone)
    }

    private func token(_ id: UUID) -> URL { URL(string: "https://paceandplates.local/calendar/\(id.uuidString)")! }

    private func tokenEvents(_ token: URL, near dates: [Date], calendars: [EKCalendar]) -> [EKEvent] {
        var found: [String: EKEvent] = [:]
        for date in dates {
            let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-172800), end: date.addingTimeInterval(172800), calendars: calendars)
            for event in store.events(matching: predicate) where event.url == token {
                if let id = event.eventIdentifier { found[id] = event }
            }
        }
        return Array(found.values)
    }

    /// An exact saved identifier takes priority over copies of its URL. Fallback
    /// lookup is limited to the actual mapped calendar and reviewed destination.
    private func resolve(_ mapping: CoachCalendarMapping, dates: [Date], destination: EKCalendar? = nil) throws -> EKEvent? {
        let expectedURL = token(mapping.plannedSessionID)
        if !mapping.eventID.isEmpty, let event = store.event(withIdentifier: mapping.eventID) {
            guard event.url == expectedURL else { throw ProjectionError.changedIdentity }
            guard event.calendar.allowsContentModifications else { throw WorkoutCalendarService.CalendarError.calendarNotFound }
            return event
        }
        guard let actualCalendar = store.calendar(withIdentifier: mapping.calendarID), actualCalendar.allowsContentModifications else { throw ProjectionError.unresolved }
        var calendars = [actualCalendar]
        if let destination, destination.calendarIdentifier != actualCalendar.calendarIdentifier { calendars.append(destination) }
        let candidates = tokenEvents(expectedURL, near: dates, calendars: calendars)
        guard candidates.count <= 1 else { throw ProjectionError.ambiguous }
        if let event = candidates.first { return event }
        // A pending cross-calendar save may have succeeded without a final local
        // commit. Absence from this bounded lookup cannot prove that event gone.
        guard !mapping.pendingProjection, !mapping.eventID.isEmpty, mapping.requestedStartDate != nil else { throw ProjectionError.unresolved }
        return nil
    }

    func export(_ rows: [PlannedSession], calendarID: String, hour: Int, durationMinutes: Int, useTitles: Bool) async throws {
        guard (5...1440).contains(durationMinutes), (0...23).contains(hour) else { throw CoachRepositoryError.invalidValue("calendar hour and duration") }
        let selection = try Self.captureSelection(rows, context: context)
        guard try await store.requestFullAccessToEvents() else { throw WorkoutCalendarService.CalendarError.accessDenied }
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else { throw WorkoutCalendarService.CalendarError.calendarNotFound }
        try Self.validateSelection(selection, context: context)
        let isolated = try isolatedContext()
        let selected = try selectedRows(selection, context: isolated)
        let mappings = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>())
        // Resolve every deterministic error before saving mappings or events.
        let requests: [ExportRequest] = try selected.map { row in
            guard row.activityType != "rest", row.completionProvenance != "removed_by_reviewed_revision" else {
                throw CoachRepositoryError.invalidValue("training sessions for export; use Remove Selected App Events to clear retired or rest events")
            }
            let matches = mappings.filter { $0.plannedSessionID == row.id }
            guard matches.count <= 1 else { throw ProjectionError.ambiguous }
            let (start, zone) = try startDate(row, hour: hour)
            let mapping = matches.first
            let dates = [mapping?.requestedStartDate, row.scheduledDate, start].compactMap { $0 }
            let event = try mapping.flatMap { try resolve($0, dates: dates, destination: calendar) }
            return ExportRequest(row: row, mapping: mapping, event: event, start: start, zone: zone)
        }
        do {
            for request in requests {
                let row = request.row
                let mapping = request.mapping ?? CoachCalendarMapping()
                if request.mapping == nil { isolated.insert(mapping); mapping.plannedSessionID = row.id }
                let event = request.event ?? EKEvent(eventStore: store)
                mapping.pendingProjection = true
                if let recoveredID = event.eventIdentifier { mapping.eventID = recoveredID }
                // Until EventKit confirms a move, this remains the actual calendar.
                mapping.calendarID = request.event?.calendar.calendarIdentifier ?? calendar.calendarIdentifier
                mapping.requestedStartDate = request.start
                try isolated.save()
                event.title = useTitles ? row.title : "Training session"
                event.notes = nil; event.url = token(row.id); event.calendar = calendar
                event.startDate = request.start; event.endDate = request.start.addingTimeInterval(Double(durationMinutes) * 60)
                event.timeZone = request.zone
                try store.save(event, span: .thisEvent, commit: true)
                mapping.calendarID = calendar.calendarIdentifier; mapping.eventID = event.eventIdentifier
                mapping.exportedScheduleRevision = row.scheduleRevision; mapping.pendingProjection = false
                try isolated.save()
            }
        } catch { isolated.rollback(); throw error }
    }

    func reminders(_ rows: [PlannedSession], hour: Int) async throws {
        let operationID = try Self.beginReminderOperation()
        defer { Self.finishReminderOperation(operationID) }
        let selection = try Self.captureSelection(rows, context: context)
        let isolated = try isolatedContext()
        let selected = try selectedRows(selection, context: isolated)
        guard selected.count <= 60, selected.allSatisfy({ $0.status == "pending" && $0.activityType != "rest" && $0.completionProvenance != "removed_by_reviewed_revision" }) else {
            throw CoachRepositoryError.invalidValue("at most 60 unstarted training sessions for reminders")
        }
        let requests: [UNNotificationRequest] = try selected.map { row in
            let (start, zone) = try startDate(row, hour: hour)
            guard start > Date() else { throw CoachRepositoryError.invalidValue("a future reminder date for \(row.title)") }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            components.calendar = calendar; components.timeZone = zone
            let content = UNMutableNotificationContent(); content.title = "Training session"
            content.body = "Open Coach to review your planned session."; content.sound = .default
            return UNNotificationRequest(identifier: "coach.session.\(row.id.uuidString)", content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        }
        let center = UNUserNotificationCenter.current()
        let selectedIDs = Set(requests.map(\.identifier))
        let otherPending = await center.pendingNotificationRequests().filter { !selectedIDs.contains($0.identifier) }.count
        guard otherPending + requests.count <= 60 else { throw CoachRepositoryError.invalidValue("at most 60 pending reminders across the app; remove old reminders or select fewer sessions") }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw CoachRepositoryError.invalidValue("notification permission; your in-app schedule is still available") }
        var addedIDs: [String] = []
        do {
            for request in requests {
                try Self.validateSelection(selection, context: context)
                try await center.add(request)
                addedIDs.append(request.identifier)
                try Self.validateSelection(selection, context: context)
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: addedIDs)
            throw error
        }
    }

    func removeMappedEvents(_ rows: [PlannedSession]) async throws {
        let selection = try Self.captureSelection(rows, context: context)
        let ids = Set(selection.occurrences.map(\.id))
        let hasMappings = try ModelContext(context.container).fetch(FetchDescriptor<CoachCalendarMapping>()).contains { ids.contains($0.plannedSessionID) }
        if hasMappings {
            guard try await store.requestFullAccessToEvents() else { throw WorkoutCalendarService.CalendarError.accessDenied }
        }
        try Self.validateSelection(selection, context: context)
        let isolated = try isolatedContext()
        let selected = try selectedRows(selection, context: isolated)
        let mappings = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>()).filter { ids.contains($0.plannedSessionID) }
        guard Set(mappings.map(\.plannedSessionID)).count == mappings.count else { throw ProjectionError.ambiguous }
        let removals: [(CoachCalendarMapping, EKEvent?)] = try mappings.map { mapping in
            let dates = [mapping.requestedStartDate, selected.first { $0.id == mapping.plannedSessionID }?.scheduledDate].compactMap { $0 }
            return (mapping, try resolve(mapping, dates: dates))
        }
        do {
            for (mapping, event) in removals {
                if let event { try store.remove(event, span: .thisEvent, commit: true) }
                isolated.delete(mapping); try isolated.save()
            }
        } catch { isolated.rollback(); throw error }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: selected.map { "coach.session.\($0.id.uuidString)" })
    }
}

struct CoachCalendarReviewView: View {
    let plan: TrainingPlan
    @Environment(\.modelContext) private var context
    @Query private var allRows: [PlannedSession]
    @Query private var mappings: [CoachCalendarMapping]
    @State private var selected: Set<UUID> = []
    @State private var calendars: [EKCalendar] = []
    @State private var calendarID = ""
    @State private var hour = 8
    @State private var duration = 60
    @State private var useTitles = false
    @State private var status: String?
    @State private var error: String?
    @State private var working = false
    @State private var reminderIDs: Set<String> = []
    private var rows: [PlannedSession] { allRows.filter { row in
        row.plan?.id == plan.id && ((row.activityType != "rest" && row.completionProvenance != "removed_by_reviewed_revision") || mappings.contains { $0.plannedSessionID == row.id })
    }.sorted { $0.scheduledDate < $1.scheduledDate } }
    var body: some View {
        Form {
            Section {
                Text("Only selected sessions are exported. Calendar access and notifications are optional. Health and check-in notes are never included.")
                Stepper("Start time: \(hour):00", value: $hour, in: 0...23)
                Stepper("Calendar duration: \(duration) minutes", value: $duration, in: 5...1_440, step: 5)
                Toggle("Use session titles in Calendar", isOn: $useTitles)
            }
            Section("Review dates") {
                ForEach(rows) { row in
                    Toggle(isOn: Binding(get: { selected.contains(row.id) }, set: { if $0 { selected.insert(row.id) } else { selected.remove(row.id) } })) {
                        VStack(alignment: .leading) {
                            Text(row.title)
                            Text((row.currentCivilDate ?? "") + " at \(hour):00 · \(plan.timeZoneIdentifier)").font(.caption)
                            if mappings.contains(where: { $0.plannedSessionID == row.id && $0.pendingProjection }) { Text("Calendar update needs retry").font(.caption).foregroundStyle(.orange) }
                            if reminderIDs.contains("coach.session.\(row.id.uuidString)") { Text("Reminder scheduled").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("Calendar") {
                Button("Choose Calendar") { run { calendars = try await CoachCalendarProjection(context: context).calendars(); calendarID = calendars.first?.calendarIdentifier ?? "" } }
                if !calendars.isEmpty {
                    Picker("Calendar", selection: $calendarID) { ForEach(calendars, id: \.calendarIdentifier) { Text($0.title).tag($0.calendarIdentifier) } }
                    Button("Export / Update Selected Events") { run { try await CoachCalendarProjection(context: context).export(rows.filter { selected.contains($0.id) }, calendarID: calendarID, hour: hour, durationMinutes: duration, useTitles: useTitles); status = "Selected calendar events saved." } }.disabled(selected.isEmpty || calendarID.isEmpty)
                }
                Button("Remove Selected App Events", role: .destructive) { run { try await CoachCalendarProjection(context: context).removeMappedEvents(rows.filter { selected.contains($0.id) }); status = "Mapped events and reminders removed." } }.disabled(selected.isEmpty)
            }
            Section("Reminders") {
                Text("Moving, skipping or revising a session cancels its previous reminder. Review the new dates here before scheduling again. Pending Calendar changes stay visible until you update or remove the mapped events.").font(.caption)
                Button("Schedule Selected Reminders") { run { try await CoachCalendarProjection(context: context).reminders(rows.filter { selected.contains($0.id) }, hour: hour); status = "Selected reminders scheduled." } }.disabled(selected.isEmpty)
                Button("Remove Selected Reminders", role: .destructive) { run {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: selected.map { "coach.session.\($0.uuidString)" })
                    status = "Selected reminders removed."
                } }.disabled(selected.isEmpty)
            }
            if working { ProgressView() }
            if let status { Text(status) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Calendar & Reminders").disabled(working)
            .task { await refreshReminders() }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        working = true; status = nil; error = nil
        Task { @MainActor in defer { working = false }; do { try await action() } catch { self.error = error.localizedDescription }; await refreshReminders() }
    }
    private func refreshReminders() async { reminderIDs = Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)) }
}
