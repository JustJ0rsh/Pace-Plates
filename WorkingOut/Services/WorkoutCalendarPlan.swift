import Foundation

/// Pure preparation shared by Calendar export and deterministic regression checks.
enum WorkoutCalendarPlan {
    static func startDate(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    /// Parse workout days from markdown plan
    static func parseWorkoutDays(from text: String) -> [(title: String, details: String)] {
        var workoutDays: [(String, String)] = []

        let lines = text.components(separatedBy: .newlines)
        var currentDay: String?
        var currentDetails: [String] = []
        var inWorkoutSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { continue }

            let lowerLine = trimmed.lowercased()

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
            } else if lowerLine.contains("training plan") || lowerLine.contains("workout:") ||
                        lowerLine.contains("week 1") || lowerLine.contains("this week") {
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

    /// Extract day title from a line - flexible patterns for various AI output formats
    private static func extractDayTitle(from line: String) -> String? {
        // More flexible patterns for various AI output formats
        let dayPatterns = [
            // "### Day 1: Title" or "## Day 1" (1-6 hash marks)
            "^#{1,6}\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "- Day 1: Title" or "• Day 1" (bullet lists)
            "^[-•*]\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "1. Day 1: Title" (numbered lists)
            "^\\d+\\.\\s*\\*{0,2}\\s*Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$",
            // "**Day 1: Title**" (bold without prefix)
            "^\\*{2}\\s*Day\\s+(\\d+)\\s*[:\\-–]?\\s*(.*)\\*{0,2}$",
            // "Day 1: Title" (no prefix at all)
            "^Day\\s+(\\d+)\\s*[:\\-–]?\\s*(.*)$",
            // "### Week 1, Day 1: Title" or "Week 1 - Day 1"
            "^#{0,6}\\s*\\*{0,2}\\s*Week\\s*\\d+[,:\\-–\\s]+Day\\s+(\\d+)\\s*\\*{0,2}\\s*[:\\-–]?\\s*(.*)$"
        ]

        for pattern in dayPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 {
                    if let dayNumRange = Range(match.range(at: 1), in: line) {
                        let dayNum = String(line[dayNumRange]).trimmingCharacters(in: .whitespaces)
                        let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                        let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                        return "Day \(dayNum)\(title.isEmpty ? "" : ": \(title)")"
                    }
                }
            }
        }

        // Weekday patterns
        let dayNames = "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon|Tue|Wed|Thu|Fri|Sat|Sun)"
        let weekdayPatterns = [
            // "### Monday: Title"
            "^#{1,6}\\s*\\*{0,2}\\s*\(dayNames)\\s*\\*{0,2}\\s*[:\\-–](.*)$",
            // "- Monday: Title" (bullet lists)
            "^[-•*]\\s*\\*{0,2}\\s*\(dayNames)\\s*\\*{0,2}\\s*[:\\-–](.*)$",
            // "Monday: Title" or "**Monday: Title**" (no prefix)
            "^\\*{0,2}\\s*\(dayNames)\\s*\\*{0,2}\\s*[:\\-–](.*)$"
        ]

        for pattern in weekdayPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 2 {
                    if let dayNameRange = Range(match.range(at: 1), in: line) {
                        let dayName = String(line[dayNameRange]).trimmingCharacters(in: .whitespaces)
                        let titleRange = match.numberOfRanges >= 3 ? Range(match.range(at: 2), in: line) : nil
                        let title = titleRange.map { String(line[$0]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") } ?? ""
                        return "\(dayName.capitalized)\(title.isEmpty ? "" : ": \(title)")"
                    }
                }
            }
        }

        return nil
    }

    /// Normalize day details: if any non-rest content exists, drop 'Rest Day'/'Active Recovery' lines; otherwise keep a single rest label
    private static func normalizeDetails(_ details: [String]) -> String {
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
