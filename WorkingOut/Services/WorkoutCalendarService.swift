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
            workoutDays = parseWorkoutDays(from: conversation.response)
        }
        
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
    
    /// Parse workout days from markdown plan
    private func parseWorkoutDays(from text: String) -> [(title: String, details: String)] {
        var workoutDays: [(String, String)] = []
        
        let lines = text.components(separatedBy: .newlines)
        var currentDay: String?
        var currentDetails: [String] = []
        var inWorkoutSection = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty { continue }
            
            // Check if we're entering the workout section (after "Training Plan Overview:" or similar)
            let lowerLine = trimmed.lowercased()
            if lowerLine.contains("training plan") || lowerLine.contains("workout:") || 
               lowerLine.contains("week 1") || lowerLine.contains("this week") {
                inWorkoutSection = true
                continue
            }
            
            // Check if this is a day header (e.g., "### Day 1:", "- Day 1:", "Day 1:")
            if let dayMatch = extractDayTitle(from: trimmed) {
                // Save previous day if exists
                if let day = currentDay, !currentDetails.isEmpty {
                    let cleanedDetails = normalizeDetails(currentDetails)
                    workoutDays.append((day, cleanedDetails))
                }
                
                // Start new day
                currentDay = dayMatch
                currentDetails = []
                inWorkoutSection = true
            } else if currentDay != nil && inWorkoutSection {
                // Skip headers and section markers
                if trimmed.hasPrefix("#") || lowerLine.contains("workout:") { 
                    continue 
                }
                
                // Add details to current day
                // Remove markdown formatting but keep the structure
                let cleaned = trimmed
                    .replacingOccurrences(of: "**", with: "")
                
                if !cleaned.isEmpty {
                    currentDetails.append(cleaned)
                }
            }
        }
        
        // Don't forget the last day
        if let day = currentDay, !currentDetails.isEmpty {
            let cleanedDetails = normalizeDetails(currentDetails)
            workoutDays.append((day, cleanedDetails))
        }
        
        return workoutDays
    }
    
    /// Extract day title from a line
    private func extractDayTitle(from line: String) -> String? {
        // Pattern 1: "### Day 1: Upper Body" or "## Day 1" (supports 1-6 hash marks)
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*(?::|\\s+|$)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 2,
                   let dayNumRange = Range(match.range(at: 1), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                    let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                    return "Day \(dayNum)\(title.isEmpty ? "" : ": \(title)")"
                }
            }
        }
        
        // Pattern 2: "### Monday: Strength Training" - Day of week names
        let dayNames = "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)"
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s*\\*{0,2}\\s*\(dayNames)\\s*\\*{0,2}\\s*:(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 2,
                   let dayNameRange = Range(match.range(at: 1), in: line) {
                    let dayName = String(line[dayNameRange])
                    let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                    let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                    return "\(dayName.capitalized)\(title.isEmpty ? "" : ": \(title)")"
                }
            }
        }
        
        // Pattern 3: "- Day 1: Upper Body" or "• Day 1" (bullet lists)
        if let regex = try? NSRegularExpression(pattern: "^[-•]\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*(?::|\\s+|$)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 2,
                   let dayNumRange = Range(match.range(at: 1), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                    let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                    return "Day \(dayNum)\(title.isEmpty ? "" : ": \(title)")"
                }
            }
        }
        
        // Pattern 4: "Day 1: Upper Body" or "Day 1" (no prefix)
        if let regex = try? NSRegularExpression(pattern: "^\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*(?::|\\s+|$)(.*)$", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                if match.numberOfRanges >= 2,
                   let dayNumRange = Range(match.range(at: 1), in: line) {
                    let dayNum = String(line[dayNumRange])
                    let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                    let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                    return "Day \(dayNum)\(title.isEmpty ? "" : ": \(title)")"
                }
            }
        }
        
        return nil
    }

    /// Normalize day details: if any non-rest content exists, drop 'Rest Day'/'Active Recovery' lines; otherwise keep a single rest label
    private func normalizeDetails(_ details: [String]) -> String {
        let tokens: [(String, String)] = details.map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            // Remove bullet markers for comparison but keep original
            var s = t
            if s.hasPrefix("- ") { s.removeFirst(2) }
            if s.hasPrefix("• ") { s.removeFirst(2) }
            return (t, s.lowercased().trimmingCharacters(in: .whitespaces))
        }
        
        let hasTraining = tokens.contains { (_, low) in 
            !low.isEmpty && (
                (low != "rest day" && 
                 low != "active recovery" &&
                 !low.starts(with: "rest") &&
                 !low.starts(with: "light")) ||
                low.contains("compound") ||
                low.contains("accessory") ||
                low.contains("cardio") ||
                low.contains("sets")
            )
        }
        
        if hasTraining {
            // Keep all training-related lines, clean up bullet markers consistently
            let kept = tokens.compactMap { (orig, low) -> String? in
                if low == "rest day" || low == "active recovery" { return nil }
                // Ensure consistent bullet formatting for calendar
                var line = orig
                if !line.hasPrefix("• ") && !line.hasPrefix("- ") {
                    line = "• " + line
                }
                return line
            }
            return kept.joined(separator: "\n")
        } else {
            // Rest day
            if tokens.contains(where: { $0.1.contains("active recovery") }) { return "Active Recovery" }
            if tokens.contains(where: { $0.1.contains("rest") }) { return "Rest Day" }
            return details.isEmpty ? "Rest Day" : details.joined(separator: "\n")
        }
    }
}
