import Foundation

/// Reads saved one-week AI conversations without depending on FoundationModels.
/// Missing or ambiguous essential values remain editable, invalid draft fields;
/// the shared validator must pass before the draft can be imported or executed.
enum CoachLegacyPlanAdapter {
    private struct LegacyPlan: Decodable {
        var title: String
        var overview: String
        var unit: String
        var guidance: String
        var weeks: [LegacyWeek]
    }
    private struct LegacyWeek: Decodable { var title: String; var days: [LegacyDay] }
    private struct LegacyDay: Decodable { var title: String; var type: String; var items: [LegacyItem] }
    private struct LegacyItem: Decodable {
        var name: String
        var sets: Int?
        var reps: Int?
        var suggestedWeight: String?
        var notes: String?
        var distance: Double?
        var distanceUnit: String?
        var pace: String?
        var durationMinutes: Int?
        var effort: String?
    }
    static func draft(json: String, sourceID: UUID, goal: String) throws -> CoachPlanDocument {
        guard let data = json.data(using: .utf8), data.count <= 2 * 1_024 * 1_024 else { throw CocoaError(.fileReadCorruptFile) }
        let legacy = try JSONDecoder().decode(LegacyPlan.self, from: data)
        guard !legacy.weeks.isEmpty, legacy.weeks.count <= 104 else { throw CocoaError(.fileReadCorruptFile) }
        let phase = CoachPhase(id: "legacy-phase", title: "Reviewed legacy plan", advanceMode: .reviewRequired)
        var document = CoachPlanDocument(programId: "legacy-" + sourceID.uuidString, title: legacy.title, goal: goal,
            overview: legacy.overview, guidance: legacy.guidance, preferredUnits: .init(weight: legacy.unit == "kg" ? .kg : .lb, distance: legacy.unit == "kg" ? .km : .mi), phases: [phase])
        for (weekIndex, week) in legacy.weeks.enumerated() {
            guard week.days.count <= 7 else { throw CocoaError(.fileReadCorruptFile) }
            var slots: [CoachSlot] = []
            for (dayIndex, day) in week.days.enumerated() {
                let id = "week-\(weekIndex + 1)-day-\(dayIndex + 1)"
                let template: CoachSessionTemplate
                let notes = day.items.map { item in
                    [item.name, item.notes, item.suggestedWeight.map { "Original load suggestion: " + $0 }, item.pace.map { "Original pace guidance: " + $0 }, item.effort.map { "Original effort guidance: " + $0 }].compactMap { $0 }.joined(separator: ". ")
                }.joined(separator: "\n")
                switch day.type {
                case "rest": template = .rest(.init(id: id, title: day.title, notes: notes.isEmpty ? nil : notes))
                case "activeRecovery": template = .recovery(.init(id: id, title: day.title, instructions: notes))
                case "strengthUpper", "strengthLower", "fullBodyStrength":
                    let rows = day.items.enumerated().map { index, item in
                        let sets = (item.sets ?? 0) > 0 && (item.sets ?? 0) <= 20 && (item.reps ?? 0) > 0
                            ? (0..<(item.sets ?? 0)).map { CoachStrengthSet(id: "set-\($0 + 1)", role: .working, target: .reps(min: item.reps!, max: item.reps!)) } : []
                        return CoachStrengthExercise(id: "exercise-\(index + 1)", exercise: .init(key: id + "-exercise-\(index + 1)", name: item.name), prescriptionBasis: .total, loadBasis: .totalExternal, sets: sets,
                            notes: [item.notes, item.suggestedWeight.map { "Unresolved original load: " + $0 }].compactMap { $0 }.joined(separator: "\n").nilIfEmpty)
                    }
                    template = .strength(.init(id: id, title: day.title, exercises: rows, notes: "Review set targets, per-side counting, and load basis. Legacy records did not store these distinctions."))
                default:
                    let running = ["runEasy", "runTempo", "runIntervals", "longRun"].contains(day.type)
                    let activity: CoachActivity = running ? .run : day.type == "cyclingEndurance" ? .cycle : day.type == "rowing" ? .row : day.type == "swimming" ? .swim : .other
                    let blocks: [CoachIntervalBlock] = day.items.enumerated().compactMap { index, item in
                        let target: CoachSegmentTarget
                        // Two simultaneous targets require a manual choice; an
                        // arbitrary winner would change the authored prescription.
                        if let minutes = item.durationMinutes, item.distance == nil, minutes > 0, minutes <= 1_440 { target = .duration(seconds: minutes * 60) }
                        else if let distance = item.distance, item.durationMinutes == nil, let raw = item.distanceUnit, let unit = CoachDistanceUnit(rawValue: raw), distance > 0 { target = .distance(.init(value: distance, unit: unit)) }
                        else { return nil }
                        return .segment(.init(id: "segment-\(index + 1)", title: item.name, activity: activity, target: target, intensity: item.effort.map { .init(cue: $0) }, notes: item.notes))
                    }
                    let unresolved = day.items.filter { ($0.durationMinutes == nil) == ($0.distance == nil) }.map { "Review \($0.name): duration \($0.durationMinutes.map(String.init) ?? "unspecified") minutes; distance \($0.distance.map { String($0) } ?? "unspecified") \($0.distanceUnit ?? ""). Choose one structured target." }.joined(separator: "\n")
                    let cardio = CoachCardioSession(kind: running ? "running" : "cardio", id: id, title: day.title, main: blocks.count == day.items.count ? blocks : [], notes: (notes + "\n" + unresolved).nilIfEmpty)
                    template = running ? .running(cardio) : .cardio(cardio)
                }
                document.sessionTemplates.append(template)
                slots.append(.init(id: id, dayOffset: dayIndex, sessionTemplateId: id))
            }
            let pattern = CoachWeekPattern(id: "pattern-\(weekIndex + 1)", title: week.title, slots: slots)
            document.weekPatterns.append(pattern)
            document.weeks.append(.init(id: "week-\(weekIndex + 1)", phaseId: phase.id, weekPatternId: pattern.id, label: week.title))
        }
        return document
    }
}

private extension String { var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self } }

struct CoachLegacyDraftRequest: Identifiable { let id = UUID(); let document: CoachPlanDocument }
