import Foundation
import EventKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for scheduling workout plans to the user's calendar
final class WorkoutCalendarService {
    static let shared = WorkoutCalendarService()
    private init() {}
    
    private let eventStore = EKEventStore()
    private let eventIdentifiersKeyPrefix = "WorkoutCalendarService.eventIdentifiers."
    
    enum CalendarError: LocalizedError {
        case accessDenied
        case calendarNotFound
        case failedToParseWorkouts
        case failedToCreateEvents
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Calendar access is required. Please enable it in Settings."
            case .calendarNotFound:
                return "Could not find a calendar to add events to."
            case .failedToParseWorkouts:
                return "Could not parse workout days from the plan."
            case .failedToCreateEvents:
                return "Failed to create calendar events."
            }
        }
    }
    
    /// Request calendar access
    func requestAccess() async throws {
        // If already authorized, return early
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess, .writeOnly: return
            case .notDetermined:
                let granted = try await eventStore.requestFullAccessToEvents()
                guard granted else { throw CalendarError.accessDenied }
                return
            default:
                // .denied, .restricted
                throw CalendarError.accessDenied
            }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            if status == .authorized { return }
            if status == .notDetermined {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if granted {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: CalendarError.accessDenied)
                        }
                    }
                }
            } else {
                throw CalendarError.accessDenied
            }
        }
    }
    
    /// Get all writable calendars
    func getWritableCalendars() -> [EKCalendar] {
        return eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }
    
    /// Get calendar by identifier, falling back to default if not found
    func getCalendar(identifier: String?) -> EKCalendar? {
        if let identifier = identifier,
           let calendar = eventStore.calendar(withIdentifier: identifier),
           calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.defaultCalendarForNewEvents
    }
    
    /// Schedule a workout plan to the calendar
    func scheduleWorkoutPlan(_ conversation: AIConversation,
                             startHour: Int? = nil,
                             startMinute: Int? = nil,
                             durationMinutes: Int? = nil,
                             calendarIdentifier: String? = nil) async throws {
        // Request calendar access
        try await requestAccess()
        
        // Get calendar (user-selected or default)
        guard let calendar = getCalendar(identifier: calendarIdentifier) else {
            throw CalendarError.calendarNotFound
        }
        
        // Parse workout days from the conversation
        // Try structured plan first, fall back to markdown parsing
        let workoutDays: [(title: String, details: String)]
        if let structuredJSON = conversation.structuredPlanJSON,
           let jsonData = structuredJSON.data(using: .utf8) {
            workoutDays = parseStructuredPlan(from: jsonData)
        } else {
            workoutDays = WorkoutCalendarPlan.parseWorkoutDays(from: conversation.response)
        }
        
        guard !workoutDays.isEmpty else {
            throw CalendarError.failedToParseWorkouts
        }
        
        // Create events starting tomorrow
        guard let startDate = WorkoutCalendarPlan.startDate(after: Date()) else {
            throw CalendarError.failedToCreateEvents
        }
        
        var scheduledEvents: [Int: EKEvent] = [:]
        let storedIdentifiers = storedEventIdentifiers(for: conversation.id)
        for (dayIndex, workoutInfo) in workoutDays.enumerated() {
            let dayDate = Calendar.current.date(byAdding: .day, value: dayIndex, to: startDate)!

            // Reuse the previously scheduled event for this plan/day. This makes
            // tapping Schedule again idempotent while still allowing changed
            // times, notes, or calendars to update the existing event.
            let event: EKEvent
            if let identifier = storedIdentifiers[String(dayIndex)],
               let existing = eventStore.event(withIdentifier: identifier) {
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
            }

            // Title/emoji hint for rest vs training
            let lowerTitle = workoutInfo.title.lowercased()
            let lowerDetails = workoutInfo.details.lowercased()
            let isRest = lowerTitle.contains("rest") || lowerTitle.contains("active recovery") || lowerDetails == "rest day" || lowerDetails == "active recovery"
            event.title = (isRest ? "🧘" : "💪") + " " + workoutInfo.title
            event.notes = workoutInfo.details
            event.calendar = calendar
            
            // Time window: defaults to 8:00–9:00 unless options provided
            let hour = startHour ?? 8
            let minute = startMinute ?? 0
            let duration = max(15, durationMinutes ?? 60)
            var startComponents = Calendar.current.dateComponents([.year, .month, .day], from: dayDate)
            startComponents.hour = hour
            startComponents.minute = minute
            let eventStart = Calendar.current.date(from: startComponents)!
            
            event.startDate = eventStart
            event.endDate = eventStart.addingTimeInterval(TimeInterval(duration * 60))
            
            // Add reminder 30 minutes before
            let hasThirtyMinuteAlarm = (event.alarms ?? []).contains {
                $0.absoluteDate == nil && $0.relativeOffset == -1800
            }
            if !hasThirtyMinuteAlarm {
                let alarm = EKAlarm(relativeOffset: -1800) // 30 minutes before
                event.addAlarm(alarm)
            }
            
            // Save event
            try eventStore.save(event, span: .thisEvent, commit: false)
            scheduledEvents[dayIndex] = event
        }
        
        // Commit all changes at once
        try eventStore.commit()

        guard !scheduledEvents.isEmpty else {
            throw CalendarError.failedToCreateEvents
        }

        let identifiers: [String: String] = Dictionary(uniqueKeysWithValues: scheduledEvents.compactMap { dayIndex, event in
            guard let identifier = event.eventIdentifier else { return nil }
            return (String(dayIndex), identifier)
        })
        UserDefaults.standard.set(
            identifiers,
            forKey: eventIdentifiersKeyPrefix + conversation.id.uuidString
        )

        print("✅ Successfully scheduled \(scheduledEvents.count) workout events in calendar")
    }

    private func storedEventIdentifiers(for conversationID: UUID) -> [String: String] {
        UserDefaults.standard.dictionary(
            forKey: eventIdentifiersKeyPrefix + conversationID.uuidString
        ) as? [String: String] ?? [:]
    }
    
    /// Parse workout days from structured JSON plan
    #if canImport(FoundationModels)
    private func parseStructuredPlan(from jsonData: Data) -> [(title: String, details: String)] {
        guard let plan = try? JSONDecoder().decode(WorkoutPlan.self, from: jsonData) else {
            return []
        }
        
        var workoutDays: [(String, String)] = []
        
        // Extract all days from all weeks
        for week in plan.weeks {
            for day in week.days {
                // Build details from items
                var details: [String] = []
                
                for item in day.items {
                    var itemLine = item.name
                    
                    // Add sets/reps if present
                    if let sets = item.sets, let reps = item.reps {
                        itemLine += " - \(sets) sets of \(reps) reps"
                    } else if let sets = item.sets {
                        itemLine += " - \(sets) sets"
                    } else if let reps = item.reps {
                        itemLine += " - \(reps) reps"
                    }
                    
                    // Add suggested weight if present
                    if let weight = item.suggestedWeight {
                        itemLine += " (\(weight))"
                    }
                    
                    // Add cardio info if present
                    if let distance = item.distance, let unit = item.distanceUnit {
                        itemLine += " - \(distance) \(unit)"
                    }
                    if let pace = item.pace {
                        itemLine += " at \(pace)"
                    }
                    if let duration = item.durationMinutes {
                        itemLine += " - \(duration) minutes"
                    }
                    if let effort = item.effort {
                        itemLine += " (\(effort))"
                    }
                    
                    details.append(itemLine)
                    
                    // Add notes if present
                    if let notes = item.notes, !notes.isEmpty {
                        details.append("  • \(notes)")
                    }
                }
                
                let detailsText = details.joined(separator: "\n")
                workoutDays.append((day.title, detailsText))
            }
        }
        
        return workoutDays
    }
    #else
    private func parseStructuredPlan(from jsonData: Data) -> [(title: String, details: String)] {
        return []
    }
    #endif
    
}
