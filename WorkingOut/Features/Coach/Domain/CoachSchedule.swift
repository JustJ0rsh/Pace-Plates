import Foundation

struct CoachScheduledOccurrence: Codable, Equatable, Sendable, Identifiable {
    var sourceKey: String
    var programId: String
    var weekId: String
    var slotId: String
    var phaseId: String
    var templateId: String
    var dayOffset: Int
    var weekIndex: Int
    var civilDate: String
    var intraDayOrder: Int
    var isOptional: Bool
    var label: String?
    var notes: String?
    var template: CoachSessionTemplate
    var id: String { sourceKey }
}

enum CoachExecutionStepPayload: Codable, Equatable, Sendable {
    case strength(exercise: CoachStrengthExercise, set: CoachStrengthSet)
    case segment(CoachSegment)
    case recovery(CoachRecoverySession)
    case rest(CoachRestSession)
}

struct CoachExecutionStep: Codable, Equatable, Sendable, Identifiable {
    /// Append this to the occurrence's local identity. It is stable across date changes.
    var id: String
    var section: String?
    var blockId: String?
    var iteration: Int?
    var exerciseId: String?
    var setId: String?
    var payload: CoachExecutionStepPayload
}

enum CoachSchedule {
    static func expand(_ validated: CoachValidatedProgram, startDate: Date, timeZone: TimeZone) throws -> [CoachScheduledOccurrence] {
        let document = validated.document
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: startDate)
        let patterns = Dictionary(uniqueKeysWithValues: document.weekPatterns.map { ($0.id, $0) })
        let templates = Dictionary(uniqueKeysWithValues: document.sessionTemplates.map { ($0.id, $0) })
        var occurrences: [CoachScheduledOccurrence] = []
        for (weekIndex, week) in document.weeks.enumerated() {
            guard let pattern = patterns[week.weekPatternId] else { throw scheduleError("$.weeks[\(weekIndex)].weekPatternId", "Week pattern no longer resolves.") }
            var dayOrders: [Int: Int] = [:]
            // Sort days while preserving authored slot order within a day.
            let slots = pattern.slots.enumerated().sorted {
                $0.element.dayOffset == $1.element.dayOffset ? $0.offset < $1.offset : $0.element.dayOffset < $1.element.dayOffset
            }
            for (_, slot) in slots {
                guard let template = templates[slot.sessionTemplateId],
                      let date = calendar.date(byAdding: .day, value: weekIndex * 7 + slot.dayOffset, to: start) else {
                    throw scheduleError("$.weeks[\(weekIndex)]", "Could not expand the schedule in the selected plan time zone.")
                }
                let order = dayOrders[slot.dayOffset, default: 0]
                dayOrders[slot.dayOffset] = order + 1
                occurrences.append(.init(sourceKey: sourceKey(programId: document.programId, weekId: week.id, slotId: slot.id), programId: document.programId, weekId: week.id, slotId: slot.id, phaseId: week.phaseId, templateId: template.id, dayOffset: slot.dayOffset, weekIndex: weekIndex, civilDate: civilDate(date, timeZone: timeZone), intraDayOrder: order, isOptional: slot.optional, label: slot.label, notes: slot.notes, template: template))
            }
        }
        return occurrences
    }

    static func sourceKey(programId: String, weekId: String, slotId: String) -> String {
        // ':' cannot occur in a valid authored ID, so this representation is unambiguous.
        "\(programId):\(weekId):\(slotId)"
    }

    static func civilDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }

    static func date(from civilDate: String, timeZone: TimeZone) -> Date? {
        let components = civilDate.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].count == 4, components[1].count == 2, components[2].count == 2,
              let year = Int(components[0]), let month = Int(components[1]), let day = Int(components[2]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              Self.civilDate(date, timeZone: timeZone) == civilDate else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Full imports validate semantics first; the resource preflight also protects restored snapshots.
    static func steps(for template: CoachSessionTemplate) throws -> [CoachExecutionStep] {
        try checkExpansionResources(template)
        var steps: [CoachExecutionStep] = []
        switch template {
        case let .strength(session):
            for exercise in session.exercises {
                for set in exercise.sets {
                    steps.append(.init(id: "strength:\(exercise.id):\(set.id)", section: nil, blockId: nil, iteration: nil, exerciseId: exercise.id, setId: set.id, payload: .strength(exercise: exercise, set: set)))
                }
            }
        case let .running(session), let .cardio(session):
            for (section, blocks) in [("warmup", session.warmup), ("main", session.main), ("cooldown", session.cooldown)] {
                for block in blocks {
                    switch block {
                    case let .segment(segment):
                        steps.append(.init(id: "\(section):\(segment.id)", section: section, blockId: segment.id, iteration: nil, exerciseId: nil, setId: nil, payload: .segment(segment)))
                    case let .repeatBlock(repeated):
                        for iteration in 1...repeated.count {
                            for segment in repeated.segments {
                                steps.append(.init(id: "\(section):\(repeated.id):\(iteration):\(segment.id)", section: section, blockId: repeated.id, iteration: iteration, exerciseId: nil, setId: nil, payload: .segment(segment)))
                            }
                        }
                    }
                }
            }
        case let .recovery(session): steps.append(.init(id: "recovery:\(session.id)", section: nil, blockId: nil, iteration: nil, exerciseId: nil, setId: nil, payload: .recovery(session)))
        case let .rest(session): steps.append(.init(id: "rest:\(session.id)", section: nil, blockId: nil, iteration: nil, exerciseId: nil, setId: nil, payload: .rest(session)))
        }
        return steps
    }

    static func nutritionTargets(in document: CoachProgramDocumentV1, phaseId: String) -> CoachNutritionTargets? {
        document.phases.first(where: { $0.id == phaseId })?.nutritionTargets ?? document.nutritionTargets
    }
    static func recoveryTargets(in document: CoachProgramDocumentV1, phaseId: String) -> CoachRecoveryTargets? {
        document.phases.first(where: { $0.id == phaseId })?.recoveryTargets ?? document.recoveryTargets
    }
    private static func checkExpansionResources(_ template: CoachSessionTemplate) throws {
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw scheduleError("$.sessionTemplates", message) }
        }
        var count = 0
        var duration = 0
        switch template {
        case let .strength(session):
            try require((1...40).contains(session.exercises.count), "Expected 1–40 strength exercise rows.")
            for row in session.exercises {
                try require((1...20).contains(row.sets.count), "Expected 1–20 sets per exercise row.")
                count += row.sets.count
                for set in row.sets {
                    if case let .duration(seconds) = set.target {
                        try require((1...86_400).contains(seconds), "Duration goal is outside the supported range.")
                        duration += seconds
                    }
                }
            }
            try require(count <= 200, "Strength sessions are limited to 200 total sets.")
        case let .running(session), let .cardio(session):
            for blocks in [session.warmup, session.main, session.cooldown] {
                try require(blocks.count <= 32, "Each interval section is limited to 32 blocks.")
                for block in blocks {
                    let segments: [CoachSegment]
                    let repetitions: Int
                    switch block {
                    case let .segment(segment): segments = [segment]; repetitions = 1
                    case let .repeatBlock(repeated):
                        try require((2...100).contains(repeated.count), "Repeat count must be 2–100.")
                        try require((1...16).contains(repeated.segments.count), "Repeat blocks require 1–16 segments.")
                        segments = repeated.segments; repetitions = repeated.count
                    }
                    count += segments.count * repetitions
                    for segment in segments {
                        if case let .duration(seconds) = segment.target {
                            try require((1...86_400).contains(seconds), "Duration goal is outside the supported range.")
                            duration += seconds * repetitions
                        }
                    }
                }
            }
            try require(count <= 2_000, "Running/cardio sessions are limited to 2,000 expanded segments.")
        case let .recovery(session):
            if let seconds = session.durationSeconds { try require((1...86_400).contains(seconds), "Duration goal is outside the supported range.") }
        case .rest: break
        }
        try require(duration <= 86_400, "Explicit duration goals exceed the 86,400-second session limit.")
    }
    private static func scheduleError(_ path: String, _ message: String) -> CoachValidationError { .init(issues: [.init(path: path, message: message)]) }
}
