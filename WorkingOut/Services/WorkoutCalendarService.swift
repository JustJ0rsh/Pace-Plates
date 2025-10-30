import Foundation
import EventKit

/// Service for scheduling workout plans to the user's calendar
final class WorkoutCalendarService {
    static let shared = WorkoutCalendarService()
    private init() {}
    
    private let eventStore = EKEventStore()
    
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
    private func requestAccess() async throws {
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
    
    /// Schedule a workout plan to the calendar
    func scheduleWorkoutPlan(_ conversation: AIConversation,
                             startHour: Int? = nil,
                             startMinute: Int? = nil,
                             durationMinutes: Int? = nil) async throws {
        // Request calendar access
        try await requestAccess()
        
        // Get default calendar
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarError.calendarNotFound
        }
        
        // Parse workout days from the conversation
        let workoutDays = parseWorkoutDays(from: conversation.response)
        guard !workoutDays.isEmpty else {
            throw CalendarError.failedToParseWorkouts
        }
        
        // Create events starting tomorrow
        let startDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)) // Tomorrow
        
        var createdCount = 0
        for (dayIndex, workoutInfo) in workoutDays.enumerated() {
            let dayDate = Calendar.current.date(byAdding: .day, value: dayIndex, to: startDate)!
            
            // Create event
            let event = EKEvent(eventStore: eventStore)
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
            let alarm = EKAlarm(relativeOffset: -1800) // 30 minutes before
            event.addAlarm(alarm)
            
            // Save event
            try eventStore.save(event, span: .thisEvent, commit: false)
            createdCount += 1
        }
        
        // Commit all changes at once
        try eventStore.commit()
        
        guard createdCount > 0 else {
            throw CalendarError.failedToCreateEvents
        }
        
        print("✅ Successfully created \(createdCount) workout events in calendar")
    }
    
    /// Parse workout days from markdown plan
    private func parseWorkoutDays(from text: String) -> [(title: String, details: String)] {
        var workoutDays: [(String, String)] = []
        
        let lines = text.components(separatedBy: .newlines)
        var currentDay: String?
        var currentDetails: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this is a day header (e.g., "### Day 1:", "- Day 1:", "Day 1:")
            if let dayMatch = extractDayTitle(from: trimmed) {
                // Save previous day if exists
                if let day = currentDay {
                    let cleanedDetails = normalizeDetails(currentDetails)
                    workoutDays.append((day, cleanedDetails))
                }
                
                // Start new day
                currentDay = dayMatch
                currentDetails = []
            } else if currentDay != nil && !trimmed.isEmpty {
                // Add details to current day
                // Remove markdown formatting for cleaner notes
                let cleaned = trimmed
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "- ", with: "")
                    .replacingOccurrences(of: "• ", with: "")
                
                if !cleaned.isEmpty && !cleaned.hasPrefix("#") {
                    currentDetails.append(cleaned)
                }
            }
        }
        
        // Don't forget the last day
        if let day = currentDay {
            let cleanedDetails = normalizeDetails(currentDetails)
            workoutDays.append((day, cleanedDetails))
        }
        
        return workoutDays
    }
    
    /// Extract day title from a line
    private func extractDayTitle(from line: String) -> String? {
        // Pattern 1: "### Day 1: Upper Body"
        if let regex = try? NSRegularExpression(pattern: "^#{1,3}\\s*Day\\s+(\\d+)(?::|\\s+)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 3,
                   let dayNumRange = Range(match.range(at: 1), in: line),
                   let titleRange = Range(match.range(at: 2), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
                    return "Day \(dayNum): \(title.isEmpty ? "Workout" : title)"
                }
            }
        }
        
        // Pattern 2: "- Day 1: Upper Body" or "• Day 1: Upper Body"
        if let regex = try? NSRegularExpression(pattern: "^[-•]\\s*Day\\s+(\\d+)(?::|\\s+)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 3,
                   let dayNumRange = Range(match.range(at: 1), in: line),
                   let titleRange = Range(match.range(at: 2), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
                    return "Day \(dayNum): \(title.isEmpty ? "Workout" : title)"
                }
            }
        }
        
        // Pattern 3: "Day 1: Upper Body" (no prefix)
        if let regex = try? NSRegularExpression(pattern: "^Day\\s+(\\d+)(?::|\\s+)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 3,
                   let dayNumRange = Range(match.range(at: 1), in: line),
                   let titleRange = Range(match.range(at: 2), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let title = String(line[titleRange]).trimmingCharacters(in: .whitespaces)
                    return "Day \(dayNum): \(title.isEmpty ? "Workout" : title)"
                }
            }
        }
        
        return nil
    }

    /// Normalize day details: if any non-rest content exists, drop 'Rest Day'/'Active Recovery' lines; otherwise keep a single rest label
    private func normalizeDetails(_ details: [String]) -> String {
        let tokens: [(String, String)] = details.map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            var s = t
            if s.hasPrefix("- ") { s.removeFirst(2) }
            if s.hasPrefix("• ") { s.removeFirst(2) }
            return (line, s.lowercased())
        }
        let hasTraining = tokens.contains { !($0.1 == "rest day" || $0.1 == "active recovery") && !$0.1.isEmpty }
        if hasTraining {
            let kept = tokens.compactMap { (orig, low) in
                (low == "rest day" || low == "active recovery") ? nil : orig
            }
            return kept.joined(separator: "\n")
        } else {
            if tokens.contains(where: { $0.1 == "active recovery" }) { return "Active Recovery" }
            if tokens.contains(where: { $0.1 == "rest day" }) { return "Rest Day" }
            return ""
        }
    }
}
