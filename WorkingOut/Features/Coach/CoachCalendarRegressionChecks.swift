#if DEBUG
import SwiftUI
import SwiftData
import EventKit
import UserNotifications

struct CoachCalendarRegressionChecksView: View {
    @State private var result = "Running Calendar checks…"
    var body: some View {
        Text(result).font(.caption).padding().background(.regularMaterial)
            .accessibilityIdentifier("coach.calendar.regression.result")
            .task {
                do { result = "Calendar checks passed: \(try await CoachCalendarRegressionChecks.run())" }
                catch { result = "Calendar checks failed: \(error.localizedDescription)" }
            }
    }
}

@MainActor
enum CoachCalendarRegressionChecks {
    static func run() async throws -> Int {
        // Every Calendar write is restricted to two newly created local calendars.
        #if !targetEnvironment(simulator)
        throw CoachRepositoryError.invalidValue("Simulator-only Calendar fixture")
        #else
        let eventStore = EKEventStore()
        guard try await eventStore.requestFullAccessToEvents(),
              let source = eventStore.sources.first(where: { $0.sourceType == .local }) else {
            throw CoachRepositoryError.invalidValue("Calendar access and a local Simulator calendar source")
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Coach disposable audit \(UUID())"; calendar.source = source
        try eventStore.saveCalendar(calendar, commit: true)
        let calendarID = calendar.calendarIdentifier
        defer { if let value = eventStore.calendar(withIdentifier: calendarID) { try? eventStore.removeCalendar(value, commit: true) } }
        let copyCalendar = EKCalendar(for: .event, eventStore: eventStore)
        copyCalendar.title = "Coach disposable copy audit \(UUID())"; copyCalendar.source = source
        try eventStore.saveCalendar(copyCalendar, commit: true)
        let copyCalendarID = copyCalendar.calendarIdentifier
        defer { if let value = eventStore.calendar(withIdentifier: copyCalendarID) { try? eventStore.removeCalendar(value, commit: true) } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CoachCalendarAudit-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = PersistenceController.coachSchema
        let databaseURL = directory.appendingPathComponent("calendar.store")
        func openContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(CoachPersistence.configurationName, schema: schema, url: databaseURL, cloudKitDatabase: .none)])
        }
        let container = try openContainer()
        let context = container.mainContext; context.autosaveEnabled = false
        let repository = CoachRepository(context: context)
        let projection = CoachCalendarProjection(context: context, store: eventStore)
        let anchor = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let document = CoachPlanDocument(programId: "calendar_audit", title: "Calendar audit", goal: "Synthetic verification",
            phases: [.init(id: "phase", title: "Phase", advanceMode: .scheduled)],
            sessionTemplates: [.recovery(.init(id: "recovery", title: "Private session title", instructions: "Private guidance"))],
            weekPatterns: [.init(id: "pattern", title: "Week", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "recovery")])],
            weeks: [.init(id: "week", phaseId: "phase", weekPatternId: "pattern")])
        let planID = try await repository.importPlan(document: document, startDate: anchor, activate: true)
        let row = try repository.occurrences(planID: planID)[0]
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            checks += 1
            if !value { throw CoachRepositoryError.invalidValue("Calendar regression: " + message) }
        }
        func reject(_ message: String, _ action: () async throws -> Void) async throws {
            do { try await action() }
            catch { checks += 1; return }
            throw CoachRepositoryError.invalidValue("Calendar regression accepted " + message)
        }
        func events(_ store: EKEventStore, _ identifier: String) -> [EKEvent] {
            guard let selected = store.calendar(withIdentifier: identifier) else { return [] }
            return store.events(matching: store.predicateForEvents(withStart: anchor.addingTimeInterval(-86_400),
                end: anchor.addingTimeInterval(60 * 86_400), calendars: [selected]))
        }
        func savedMapping(_ modelContainer: ModelContainer) throws -> CoachCalendarMapping {
            guard let mapping = try ModelContext(modelContainer).fetch(FetchDescriptor<CoachCalendarMapping>()).first(where: { $0.plannedSessionID == row.id }) else { throw CoachRepositoryError.missingRecord }
            return mapping
        }
        func updateMapping(_ action: (CoachCalendarMapping) -> Void) throws {
            let isolated = ModelContext(container); isolated.autosaveEnabled = false
            let mapping = try isolated.fetch(FetchDescriptor<CoachCalendarMapping>()).first { $0.plannedSessionID == row.id }!
            action(mapping); try isolated.save()
        }
        try await projection.export([row], calendarID: calendarID, hour: 10, durationMinutes: 45, useTitles: false)
        var exported = events(eventStore, calendarID)
        try require(exported.count == 1, "first export creates one event")
        let eventID = exported[0].eventIdentifier!
        let link = exported[0].url!
        try require(exported[0].title == "Training session" && exported[0].notes == nil, "default export excludes private title and notes")
        try require(exported[0].endDate.timeIntervalSince(exported[0].startDate) == 2700, "reviewed duration is applied")
        try require(link.lastPathComponent == row.id.uuidString, "event is linked to the exact occurrence")
        try await projection.export([row], calendarID: calendarID, hour: 11, durationMinutes: 60, useTitles: true)
        exported = events(eventStore, calendarID)
        try require(exported.count == 1 && exported[0].eventIdentifier == eventID, "repeat export updates without duplicates")
        try require(exported[0].title == row.title && exported[0].notes == nil, "title opt-in still omits guidance")
        let copied = EKEvent(eventStore: eventStore)
        copied.calendar = copyCalendar; copied.title = "User copy of linked event"; copied.url = link
        copied.startDate = exported[0].startDate; copied.endDate = copied.startDate.addingTimeInterval(600)
        try eventStore.save(copied, span: .thisEvent, commit: true)
        let copiedID = copied.eventIdentifier!
        let duplicate = EKEvent(eventStore: eventStore)
        duplicate.calendar = calendar; duplicate.title = "Duplicate URL in mapped calendar"; duplicate.url = link
        duplicate.startDate = exported[0].startDate; duplicate.endDate = duplicate.startDate.addingTimeInterval(600)
        try eventStore.save(duplicate, span: .thisEvent, commit: true)
        try await projection.export([row], calendarID: calendarID, hour: 12, durationMinutes: 30, useTitles: false)
        try require(events(eventStore, calendarID).count == 2 && eventStore.event(withIdentifier: duplicate.eventIdentifier)?.title == "Duplicate URL in mapped calendar",
            "exact identifier updates only the mapped event despite a same-calendar URL copy")
        try require(events(eventStore, copyCalendarID).count == 1 && eventStore.event(withIdentifier: copiedID)?.title == "User copy of linked event",
            "export leaves copied URLs in another calendar untouched")
        try updateMapping { $0.eventID = ""; $0.pendingProjection = true }
        try await reject("ambiguous token export") { try await projection.export([row], calendarID: calendarID, hour: 9, durationMinutes: 30, useTitles: false) }
        try await reject("ambiguous token removal") { try await projection.removeMappedEvents([row]) }
        try require(events(eventStore, calendarID).count == 2 && (try savedMapping(container)).eventID.isEmpty,
            "ambiguous recovery leaves all events and the durable mapping unchanged")
        try eventStore.remove(duplicate, span: .thisEvent, commit: true)
        // Simulate the saved pending state, then reopen both storage boundaries.
        let movedDate = anchor.addingTimeInterval(14 * 86_400)
        try repository.moveSession(id: row.id, to: movedDate)
        let reopened = try openContainer()
        let reloadedStore = EKEventStore()
        let reloadedProjection = CoachCalendarProjection(context: reopened.mainContext, store: reloadedStore)
        let refreshed = try ModelContext(reopened).fetch(FetchDescriptor<PlannedSession>()).first { $0.id == row.id }!
        try await reloadedProjection.export([refreshed], calendarID: calendarID, hour: 12, durationMinutes: 30, useTitles: false)
        exported = events(reloadedStore, calendarID)
        try require(exported.count == 1 && exported[0].eventIdentifier == eventID, "reopened retry recovers the original event after a move beyond its current-date lookup window")
        try require(Calendar.current.isDate(exported[0].startDate, inSameDayAs: movedDate), "recovered event moves to the reviewed date")
        let recoveredMapping = try savedMapping(reopened)
        try require(!recoveredMapping.pendingProjection && recoveredMapping.eventID == eventID, "fresh model context sees the committed recovered mapping")
        try require(events(reloadedStore, copyCalendarID).count == 1, "recovery ignores the token copy in an unselected calendar")
        try await reloadedProjection.export([refreshed], calendarID: copyCalendarID, hour: 12, durationMinutes: 30, useTitles: false)
        let movedMapping = CoachBackupGraph.CoachCalendarMappingSnapshot(try savedMapping(reopened))
        try require(events(reloadedStore, calendarID).isEmpty && events(reloadedStore, copyCalendarID).count == 2 && movedMapping.calendarID == copyCalendarID,
            "explicit destination change moves only the exact mapped event")
        try updateMapping { $0.calendarID = calendarID; $0.eventID = ""; $0.pendingProjection = true }
        try await reloadedProjection.export([refreshed], calendarID: copyCalendarID, hour: 12, durationMinutes: 30, useTitles: false)
        try require(events(reloadedStore, copyCalendarID).count == 2 && (try savedMapping(reopened)).calendarID == copyCalendarID,
            "pending move can recover inside the explicitly reviewed destination calendar")
        let stableMapping = CoachBackupGraph.CoachCalendarMappingSnapshot(try savedMapping(reopened))
        try updateMapping { $0.calendarID = UUID().uuidString; $0.eventID = "missing-event"; $0.pendingProjection = true }
        try await reject("unavailable mapped calendar") { try await reloadedProjection.removeMappedEvents([refreshed]) }
        try require(try savedMapping(reopened).pendingProjection, "unavailable Calendar preserves the pending mapping")
        try updateMapping { stableMapping.apply(to: $0) }
        let editContext = ModelContext(reopened); editContext.autosaveEnabled = false
        let rest = PlannedSession(title: "Retired training now rest", activityType: "rest", scheduledDate: movedDate, weekIndex: 0, dayIndex: 1)
        let past = PlannedSession(title: "Past reminder", activityType: "recovery", scheduledDate: Date().addingTimeInterval(-172800), weekIndex: 0, dayIndex: 1)
        editContext.insert(rest); editContext.insert(past); try editContext.save()
        try await reject("invalid later batch row") { try await reloadedProjection.export([refreshed, rest], calendarID: calendarID, hour: 8, durationMinutes: 30, useTitles: false) }
        try require(events(reloadedStore, calendarID).isEmpty && (try savedMapping(reopened)).calendarID == copyCalendarID,
            "whole-batch export preflight prevents changes to an earlier valid row")
        try await reject("duration integer overflow") { try await reloadedProjection.export([refreshed], calendarID: calendarID, hour: 8, durationMinutes: Int.max, useTitles: false) }
        try await reject("past later reminder") { try await reloadedProjection.reminders([refreshed, past], hour: 8) }
        let reminderIDs: Set<String> = ["coach.session.\(refreshed.id.uuidString)", "coach.session.\(past.id.uuidString)"]
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        try require(!requests.contains { reminderIDs.contains($0.identifier) }, "whole-batch reminder preflight leaves no earlier notification scheduled")
        let nearbyCopy = reloadedStore.event(withIdentifier: copiedID)!
        nearbyCopy.startDate = movedDate; nearbyCopy.endDate = movedDate.addingTimeInterval(600)
        try reloadedStore.save(nearbyCopy, span: .thisEvent, commit: true)
        let unrelated = EKEvent(eventStore: reloadedStore)
        unrelated.calendar = reloadedStore.calendar(withIdentifier: calendarID); unrelated.title = "Unrelated audit event"
        unrelated.startDate = anchor; unrelated.endDate = anchor.addingTimeInterval(600)
        try reloadedStore.save(unrelated, span: .thisEvent, commit: true)
        try await reloadedProjection.removeMappedEvents([refreshed])
        try require(events(reloadedStore, calendarID).count == 1 && events(reloadedStore, copyCalendarID).count == 1 && reloadedStore.event(withIdentifier: copiedID)?.title == "User copy of linked event",
            "exact mapped removal preserves unrelated events and a nearby copied token")
        try require(try ModelContext(reopened).fetchCount(FetchDescriptor<CoachCalendarMapping>()) == 0, "successful removal clears its durable mapping")
        try await reloadedProjection.removeMappedEvents([refreshed])
        try require(events(reloadedStore, copyCalendarID).count == 1, "repeated removal never scans unrelated token copies")
        let reviewedSelection = try CoachCalendarProjection.captureSelection([refreshed], context: reopened.mainContext)
        try CoachCalendarProjection.validateSelection(reviewedSelection, context: reopened.mainContext); checks += 1
        try CoachRepository(context: reopened.mainContext).moveSession(id: refreshed.id, to: movedDate.addingTimeInterval(7 * 86_400))
        try await reject("schedule changed during permission wait") {
            try CoachCalendarProjection.validateSelection(reviewedSelection, context: reopened.mainContext)
        }
        let beforeSkip = try CoachCalendarProjection.captureSelection([refreshed], context: reopened.mainContext)
        try CoachRepository(context: reopened.mainContext).markSession(id: refreshed.id, status: .skipped)
        try await reject("session skipped during notification wait") {
            try CoachCalendarProjection.validateSelection(beforeSkip, context: reopened.mainContext)
        }
        let beforeDeletion = try CoachCalendarProjection.captureSelection([refreshed], context: reopened.mainContext)
        try CoachRepository(context: reopened.mainContext).transaction { isolated in
            if let selected = try isolated.fetch(FetchDescriptor<PlannedSession>()).first(where: { $0.id == refreshed.id }) { isolated.delete(selected) }
        }
        try await reject("session deleted during notification wait") {
            try CoachCalendarProjection.validateSelection(beforeDeletion, context: reopened.mainContext)
        }
        let priorPurge = CoachCalendarProjection.Selection(occurrences: [], purgeGeneration: WearableWorkoutInboxService.localDataPurgeGeneration &- 1)
        try await reject("purge generation changed during notification wait") {
            try CoachCalendarProjection.validateSelection(priorPurge, context: reopened.mainContext)
        }
        let reminderOwner = try CoachCalendarProjection.beginReminderOperation()
        defer { CoachCalendarProjection.finishReminderOperation(reminderOwner) }
        try await reject("overlapping reminder invocation") { _ = try CoachCalendarProjection.beginReminderOperation() }
        CoachCalendarProjection.finishReminderOperation(UUID())
        try await reject("another invocation releasing the reminder owner") { _ = try CoachCalendarProjection.beginReminderOperation() }
        CoachCalendarProjection.finishReminderOperation(reminderOwner)
        let nextOwner = try CoachCalendarProjection.beginReminderOperation()
        defer { CoachCalendarProjection.finishReminderOperation(nextOwner) }
        try require(nextOwner != reminderOwner, "only the owning invocation releases reminder scheduling for the next call")
        CoachCalendarProjection.finishReminderOperation(nextOwner)
        try reloadedStore.removeCalendar(reloadedStore.calendar(withIdentifier: copyCalendarID)!, commit: true)
        try reloadedStore.removeCalendar(reloadedStore.calendar(withIdentifier: calendarID)!, commit: true)
        let cleanupStore = EKEventStore()
        try require(cleanupStore.calendar(withIdentifier: calendarID) == nil && cleanupStore.calendar(withIdentifier: copyCalendarID) == nil,
            "both disposable calendars are removed before reporting success")
        return checks
        #endif
    }
}
#endif
