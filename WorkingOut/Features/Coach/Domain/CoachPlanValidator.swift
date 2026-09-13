import Foundation

struct CoachValidationIssue: Codable, Equatable, Sendable, Identifiable {
    enum Severity: String, Codable, Sendable { case error, warning }
    var path: String
    var message: String
    var severity: Severity
    var id: String { "\(severity.rawValue):\(path):\(message)" }
    init(path: String, message: String, severity: Severity = .error) {
        self.path = path; self.message = message; self.severity = severity
    }
}

struct CoachValidationError: Error, LocalizedError, Sendable {
    var issues: [CoachValidationIssue]
    var errorDescription: String? { issues.map { "\($0.path): \($0.message)" }.joined(separator: "\n") }
}

struct CoachValidatedProgram: Sendable {
    let document: CoachProgramDocumentV1
    /// Portable normalized document, including the separately tracked author revision.
    let canonicalData: Data
    let fingerprint: String
    let issues: [CoachValidationIssue]
    fileprivate init(document: CoachProgramDocumentV1, canonicalData: Data, fingerprint: String, issues: [CoachValidationIssue]) {
        self.document = document; self.canonicalData = canonicalData; self.fingerprint = fingerprint; self.issues = issues
    }
}

struct CoachPlanValidator {
    static let maximumInputBytes = 2 * 1024 * 1024
    private let schemaData: Data?
    init(schemaData: Data? = nil) { self.schemaData = schemaData }

    func validate(_ document: CoachProgramDocumentV1) throws -> CoachValidatedProgram {
        try validate(JSONEncoder().encode(document))
    }
    func validate(_ input: String) throws -> CoachValidatedProgram { try validate(Data(input.utf8)) }
    func validate(_ input: Data) throws -> CoachValidatedProgram {
        guard input.count <= Self.maximumInputBytes else { throw failure("$", "Input exceeds the 2 MiB limit.") }
        guard var text = String(data: input, encoding: .utf8) else { throw failure("$", "Expected UTF-8 JSON.") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            guard let newline = text.firstIndex(of: "\n") else { throw failure("$", "Expected one complete JSON code fence.") }
            let header = text[..<newline].trimmingCharacters(in: .whitespacesAndNewlines)
            guard header == "```json" || header == "```", text.hasSuffix("```") else {
                throw failure("$", "Only one outer code fence labeled json or without a language is supported.")
            }
            text = String(text[text.index(after: newline)..<text.index(text.endIndex, offsetBy: -3)]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var parser = CoachStrictJSONParser(Data(text.utf8))
        let json = try parser.parse()
        guard case let .object(root) = json else { throw failure("$", "Expected exactly one program JSON object.") }
        if let version = root["schemaVersion"], version != .number(1) {
            throw failure("$.schemaVersion", "Unsupported Coach schema version. Ask for schemaVersion 1, or update the app if the document requires a newer format.")
        }
        if let format = root["format"], format != .string("pace-and-plates.coach-program") {
            throw failure("$.format", "Expected pace-and-plates.coach-program.")
        }
        let schema = try loadSchema()
        let shapeIssues = CoachJSONSchema(schema: schema).validate(json)
        guard shapeIssues.isEmpty else { throw CoachValidationError(issues: shapeIssues) }
        let document: CoachProgramDocumentV1
        do { document = try JSONDecoder().decode(CoachProgramDocumentV1.self, from: Data(text.utf8)) }
        catch { throw failure("$", "The validated document could not be represented: \(error.localizedDescription)") }
        let issues = semanticIssues(document)
        guard !issues.contains(where: { $0.severity == .error }) else { throw CoachValidationError(issues: issues) }
        // Encoding the DTO normalizes documented defaults and omits absent optionals.
        var canonicalParser = CoachStrictJSONParser(try JSONEncoder().encode(document))
        let canonical = try canonicalParser.parse()
        var fingerprintValue = canonical
        if case var .object(object) = fingerprintValue { object.removeValue(forKey: "revision"); fingerprintValue = .object(object) }
        return CoachValidatedProgram(document: document, canonicalData: Data(canonical.canonical.utf8), fingerprint: CoachSHA256.hexDigest(Data(fingerprintValue.canonical.utf8)), issues: issues)
    }

    private func loadSchema() throws -> CoachJSONValue {
        let data: Data
        if let schemaData { data = schemaData }
        else {
            let url = Bundle.main.url(forResource: "coach-plan-v1.schema", withExtension: "json", subdirectory: "Coach")
                ?? Bundle.main.url(forResource: "coach-plan-v1.schema", withExtension: "json")
            guard let url else { throw failure("$", "The Coach v1 validation schema is missing from this app. Reinstall or update the app.") }
            data = try Data(contentsOf: url)
        }
        var parser = CoachStrictJSONParser(data)
        return try parser.parse()
    }
    private func failure(_ path: String, _ message: String) -> CoachValidationError {
        CoachValidationError(issues: [.init(path: path, message: message)])
    }
}

private enum CoachJSONValue: Equatable {
    case object([String: CoachJSONValue]), array([CoachJSONValue]), string(String), number(Double), bool(Bool), null
    var object: [String: CoachJSONValue]? { if case let .object(v) = self { return v }; return nil }
    var array: [CoachJSONValue]? { if case let .array(v) = self { return v }; return nil }
    var string: String? { if case let .string(v) = self { return v }; return nil }
    var number: Double? { if case let .number(v) = self { return v }; return nil }
    var canonical: String {
        switch self {
        case let .object(v): return "{" + v.keys.sorted().map { Self.quote($0) + ":" + v[$0]!.canonical }.joined(separator: ",") + "}"
        case let .array(v): return "[" + v.map(\.canonical).joined(separator: ",") + "]"
        case let .string(v): return Self.quote(v)
        case let .number(v):
            if v == 0 { return "0" }
            var result = String(v).lowercased()
            if result.hasSuffix(".0") { result.removeLast(2) }
            result = result.replacingOccurrences(of: ".0e", with: "e").replacingOccurrences(of: "e+", with: "e")
            return result
        case let .bool(v): return v ? "true" : "false"
        case .null: return "null"
        }
    }
    private static func quote(_ string: String) -> String {
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 0..<32: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}

/// A bounded grammar parser detects duplicate decoded keys before any dictionary can discard them.
private struct CoachStrictJSONParser {
    let bytes: [UInt8]
    var index = 0
    init(_ data: Data) { bytes = Array(data) }
    mutating func parse() throws -> CoachJSONValue {
        let value = try value(path: "$", depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw error("$", "Unexpected trailing content; provide exactly one JSON object.") }
        return value
    }
    mutating func value(path: String, depth: Int) throws -> CoachJSONValue {
        guard depth <= 80 else { throw error(path, "JSON nesting exceeds the supported limit.") }
        skipWhitespace()
        guard index < bytes.count else { throw error(path, "Unexpected end of JSON.") }
        switch bytes[index] {
        case 123:
            index += 1; skipWhitespace(); var result: [String: CoachJSONValue] = [:]
            if consume(125) { return .object(result) }
            while true {
                guard index < bytes.count, bytes[index] == 34 else { throw error(path, "Expected a quoted object key.") }
                let key = try string(path)
                let child = path + "." + key
                guard result[key] == nil else { throw error(child, "Duplicate object key is not allowed.") }
                skipWhitespace(); guard consume(58) else { throw error(child, "Expected ':' after the key.") }
                result[key] = try value(path: child, depth: depth + 1)
                skipWhitespace(); if consume(125) { break }
                guard consume(44) else { throw error(path, "Expected ',' or '}'.") }; skipWhitespace()
            }
            return .object(result)
        case 91:
            index += 1; skipWhitespace(); var result: [CoachJSONValue] = []
            if consume(93) { return .array(result) }
            while true {
                result.append(try value(path: "\(path)[\(result.count)]", depth: depth + 1))
                skipWhitespace(); if consume(93) { break }
                guard consume(44) else { throw error(path, "Expected ',' or ']'.") }
            }
            return .array(result)
        case 34: return .string(try string(path))
        case 116: try literal("true", path); return .bool(true)
        case 102: try literal("false", path); return .bool(false)
        case 110: try literal("null", path); return .null
        case 45, 48...57: return .number(try number(path))
        default: throw error(path, "Invalid JSON value. Numeric strings, comments, and non-finite numbers cannot be repaired automatically.")
        }
    }
    mutating func string(_ path: String) throws -> String {
        let start = index; index += 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                catch { throw self.error(path, "Invalid JSON string or escape.") }
            }
            if byte < 32 { throw error(path, "Unescaped control character in JSON string.") }
            if byte == 92 { guard index < bytes.count else { break }; index += 1 }
        }
        throw error(path, "Unterminated JSON string.")
    }
    mutating func number(_ path: String) throws -> Double {
        let start = index
        _ = consume(45)
        if consume(48) { }
        else {
            guard index < bytes.count, (49...57).contains(bytes[index]) else { throw error(path, "Invalid JSON number.") }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        if consume(46) {
            let fraction = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard fraction != index else { throw error(path, "Expected digits after decimal point.") }
        }
        if consume(101) || consume(69) {
            if !consume(43) { _ = consume(45) }
            let exponent = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard exponent != index else { throw error(path, "Expected exponent digits.") }
        }
        guard let value = Double(String(decoding: bytes[start..<index], as: UTF8.self)), value.isFinite else {
            throw error(path, "Number is non-finite or outside the supported numeric range.")
        }
        let token = String(decoding: bytes[start..<index], as: UTF8.self)
        let mantissa = token.split(whereSeparator: { $0 == "e" || $0 == "E" }).first ?? ""
        if value == 0, mantissa.contains(where: { "123456789".contains($0) }) {
            throw error(path, "Number is too small to represent without losing its value.")
        }
        return value
    }
    mutating func literal(_ value: String, _ path: String) throws {
        for byte in value.utf8 { guard consume(byte) else { throw error(path, "Invalid JSON literal.") } }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }; index += 1; return true
    }
    mutating func skipWhitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    func error(_ path: String, _ message: String) -> CoachValidationError { .init(issues: [.init(path: path, message: message)]) }
}

/// Implements every validation keyword used by the bundled authoritative v1 schema.
private struct CoachJSONSchema {
    let schema: CoachJSONValue
    func validate(_ value: CoachJSONValue) -> [CoachValidationIssue] { validate(value, against: schema, path: "$") }
    func resolved(_ rule: CoachJSONValue) -> CoachJSONValue {
        guard let reference = rule.object?["$ref"]?.string else { return rule }
        return reference.dropFirst(2).split(separator: "/").reduce(schema) { $0.object?[String($1)] ?? .null }
    }
    func validate(_ value: CoachJSONValue, against originalRule: CoachJSONValue, path: String) -> [CoachValidationIssue] {
        guard let rule = resolved(originalRule).object else { return [.init(path: path, message: "Validation schema reference could not be resolved.")] }
        func issue(_ message: String) -> [CoachValidationIssue] { [.init(path: path, message: message)] }
        if let alternatives = rule["oneOf"]?.array {
            // A discriminator gives precise field errors instead of errors from unrelated union members.
            if let kind = value.object?["kind"] ?? value.object?["scale"],
               let selected = alternatives.first(where: { candidate in
                   let properties = resolved(candidate).object?["properties"]?.object
                   return properties?["kind"]?.object?["const"] == kind || properties?["scale"]?.object?["const"] == kind
               }) { return validate(value, against: selected, path: path) }
            let results = alternatives.map { validate(value, against: $0, path: path) }
            if results.filter(\.isEmpty).count == 1 { return [] }
            return issue("Expected exactly one supported variant; check kind or scale and its required fields.")
        }
        if let constant = rule["const"], value != constant { return issue("Expected \(constant.canonical).") }
        if let enumeration = rule["enum"]?.array, !enumeration.contains(value) { return issue("Unsupported value. Expected one of \(enumeration.map(\.canonical).joined(separator: ", ")).") }
        var issues: [CoachValidationIssue] = []
        if let type = rule["type"]?.string {
            let valid: Bool
            switch (type, value) {
            case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool): valid = true
            case let ("integer", .number(number)): valid = number.rounded(.towardZero) == number
            default: valid = false
            }
            guard valid else { return issue("Expected \(type); values are never coerced from another type.") }
        }
        switch value {
        case let .object(object):
            let properties = rule["properties"]?.object ?? [:]
            for required in rule["required"]?.array ?? [] {
                if let key = required.string, object[key] == nil { issues.append(.init(path: path + "." + key, message: "Required property is missing.")) }
            }
            for key in object.keys.sorted() {
                if let childRule = properties[key] { issues += validate(object[key]!, against: childRule, path: path + "." + key) }
                else if rule["additionalProperties"] == .bool(false) { issues.append(.init(path: path + "." + key, message: "Unknown property is not supported in schema v1.")) }
            }
        case let .array(array):
            if let min = rule["minItems"]?.number, Double(array.count) < min { issues += issue("Requires at least \(Int(min)) items.") }
            if let max = rule["maxItems"]?.number, Double(array.count) > max { issues += issue("Exceeds the limit of \(Int(max)) items."); return issues }
            if rule["uniqueItems"] == .bool(true) {
                var seen = Set<String>()
                for (index, item) in array.enumerated() where !seen.insert(item.canonical).inserted { issues.append(.init(path: "\(path)[\(index)]", message: "Duplicate array value is not allowed.")) }
            }
            if let items = rule["items"] { for (index, item) in array.enumerated() { issues += validate(item, against: items, path: "\(path)[\(index)]") } }
        case let .string(string):
            let length = Double(string.unicodeScalars.count)
            if let min = rule["minLength"]?.number, length < min { issues += issue("Requires at least \(Int(min)) characters.") }
            if let max = rule["maxLength"]?.number, length > max { issues += issue("Exceeds the limit of \(Int(max)) characters.") }
            if let pattern = rule["pattern"]?.string {
                let match = string.range(of: pattern, options: .regularExpression)
                if match != string.startIndex..<string.endIndex { issues += issue("Must be a case-sensitive ASCII identifier of 1–64 letters, digits, dots, underscores or hyphens, starting with a letter or digit.") }
            }
        case let .number(number):
            if let min = rule["minimum"]?.number, number < min { issues += issue("Must be at least \(min).") }
            if let max = rule["maximum"]?.number, number > max { issues += issue("Must be at most \(max).") }
        default: break
        }
        return Array(issues.prefix(100))
    }
}

private extension CoachPlanValidator {
    func semanticIssues(_ document: CoachProgramDocumentV1) -> [CoachValidationIssue] {
        var issues: [CoachValidationIssue] = []
        func report(_ path: String, _ message: String, warning: Bool = false) {
            issues.append(.init(path: path, message: message, severity: warning ? .warning : .error))
        }
        func unique(_ ids: [String], _ path: String) {
            var seen = Set<String>()
            for (index, id) in ids.enumerated() where !seen.insert(id).inserted { report("\(path)[\(index)].id", "Duplicate ID '\(id)'.") }
        }
        func range(_ min: Double, _ max: Double, _ path: String) { if min > max { report(path, "Minimum must be less than or equal to maximum.") } }
        func nutrition(_ target: CoachNutritionTargets?, _ path: String) {
            guard let target else { return }
            if target.caloriesKcal == nil && target.proteinGrams == nil && target.carbohydrateGrams == nil && target.fatGrams == nil { report(path, "Nutrition requires at least one numeric target.") }
            if let calories = target.caloriesKcal, let protein = target.proteinGrams, let carbs = target.carbohydrateGrams, let fat = target.fatGrams {
                let macroCalories = 4 * protein + 4 * carbs + 9 * fat
                if abs(Double(calories) - macroCalories) > max(100, Double(calories) * 0.1) { report(path, "Calories differ from the macro-derived total by more than 100 kcal or 10%. Review both values; neither has been changed.", warning: true) }
            }
        }
        func recovery(_ target: CoachRecoveryTargets?, _ path: String) {
            guard let target else { return }
            if target.sleepHours == nil && target.checkInFields == nil && target.notes == nil { report(path, "Recovery targets require at least one property.") }
            if let sleep = target.sleepHours { range(sleep.min, sleep.max, path + ".sleepHours") }
        }
        unique(document.phases.map(\.id), "$.phases")
        unique(document.sessionTemplates.map(\.id), "$.sessionTemplates")
        unique(document.weekPatterns.map(\.id), "$.weekPatterns")
        unique(document.weeks.map(\.id), "$.weeks")
        unique((document.progressionRules ?? []).map(\.id), "$.progressionRules")
        nutrition(document.nutritionTargets, "$.nutritionTargets")
        recovery(document.recoveryTargets, "$.recoveryTargets")
        let templates = Dictionary(document.sessionTemplates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let patterns = Dictionary(document.weekPatterns.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let phaseIndices = Dictionary(document.phases.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var exerciseKeys: [String: CoachExerciseChoice] = [:]
        var stepCounts: [String: Int] = [:]
        var explicitDurations: [String: Int] = [:]
        func checkChoice(_ choice: CoachExerciseChoice, _ path: String) {
            if let prior = exerciseKeys[choice.key] {
                // Equipment order has no semantic bearing on a movement identity.
                if prior.name != choice.name || Set(prior.equipment) != Set(choice.equipment) || prior.catalogExerciseId != choice.catalogExerciseId {
                    report(path + ".key", "Exercise key '\(choice.key)' has conflicting names, equipment, or catalog IDs.")
                }
            } else { exerciseKeys[choice.key] = choice }
        }
        for (index, template) in document.sessionTemplates.enumerated() {
            let path = "$.sessionTemplates[\(index)]"
            var steps = 0
            var duration = 0
            switch template {
            case let .strength(session):
                unique(session.exercises.map(\.id), path + ".exercises")
                for (rowIndex, row) in session.exercises.enumerated() {
                    let rowPath = "\(path).exercises[\(rowIndex)]"
                    checkChoice(row.exercise, rowPath + ".exercise")
                    for (choiceIndex, choice) in (row.substitutions ?? []).enumerated() { checkChoice(choice, "\(rowPath).substitutions[\(choiceIndex)]") }
                    unique(row.sets.map(\.id), rowPath + ".sets")
                    for (setIndex, set) in row.sets.enumerated() {
                        let setPath = "\(rowPath).sets[\(setIndex)]"
                        switch set.target {
                        case let .reps(min, max): range(Double(min), Double(max), setPath + ".target")
                        case let .duration(seconds): duration += seconds
                        }
                        if let effort = set.effort { range(effort.min, effort.max, setPath + ".effort") }
                    }
                    steps += row.sets.count
                }
                if steps > 200 { report(path + ".exercises", "Strength sessions are limited to 200 total prescribed sets.") }
            case let .running(session), let .cardio(session):
                var ids = Set<String>()
                func intervalID(_ id: String, _ idPath: String) {
                    if !ids.insert(id).inserted { report(idPath, "Segment and repeat IDs must be unique across warmup, main, and cooldown.") }
                }
                func segment(_ segment: CoachSegment, _ segmentPath: String, count: Int) {
                    intervalID(segment.id, segmentPath + ".id")
                    if template.kind == "running", ![CoachActivity.walk, .jog, .run].contains(segment.activity) { report(segmentPath + ".activity", "Running sessions support only walk, jog, and run.") }
                    if case let .duration(seconds) = segment.target { duration += seconds * count }
                    if let intensity = segment.intensity {
                        if intensity.rpe == nil && intensity.pace == nil && intensity.cue == nil { report(segmentPath + ".intensity", "Intensity requires at least one RPE, pace, or cue.") }
                        if let effort = intensity.rpe { range(effort.min, effort.max, segmentPath + ".intensity.rpe") }
                        if let pace = intensity.pace { range(Double(pace.minSeconds), Double(pace.maxSeconds), segmentPath + ".intensity.pace") }
                    }
                    steps += count
                }
                for (section, blocks) in [("warmup", session.warmup), ("main", session.main), ("cooldown", session.cooldown)] {
                    for (blockIndex, block) in blocks.enumerated() {
                        let blockPath = "\(path).\(section)[\(blockIndex)]"
                        switch block {
                        case let .segment(value): segment(value, blockPath, count: 1)
                        case let .repeatBlock(value):
                            intervalID(value.id, blockPath + ".id")
                            for (segmentIndex, valueSegment) in value.segments.enumerated() { segment(valueSegment, "\(blockPath).segments[\(segmentIndex)]", count: value.count) }
                        }
                    }
                }
                if steps > 2_000 { report(path, "Running/cardio sessions are limited to 2,000 expanded segments.") }
            case let .recovery(session): steps = 1; duration = session.durationSeconds ?? 0
            case .rest: steps = 1
            }
            if duration > 86_400 { report(path, "Explicit duration goals exceed the 86,400-second session limit.") }
            else if duration > 4 * 3600 { report(path, "Explicit duration goals exceed four hours. Review the training load before activation.", warning: true) }
            stepCounts[template.id] = steps
            explicitDurations[template.id] = duration
        }
                for (index, pattern) in document.weekPatterns.enumerated() {
            let path = "$.weekPatterns[\(index)]"
            unique(pattern.slots.map(\.id), path + ".slots")
            for (slotIndex, slot) in pattern.slots.enumerated() {
                if templates[slot.sessionTemplateId] == nil { report("\(path).slots[\(slotIndex)].sessionTemplateId", "References an unknown session template.") }
            }
            for day in 0...6 {
                let slots = pattern.slots.filter { $0.dayOffset == day }
                if slots.count > 8 { report(path + ".slots", "Day \(day) exceeds eight slots.") }
                if slots.count > 1, slots.contains(where: { templates[$0.sessionTemplateId]?.kind == "rest" }) { report(path + ".slots", "Day \(day) places explicit rest alongside another slot.") }
                if slots.reduce(0, { $0 + (explicitDurations[$1.sessionTemplateId] ?? 0) }) > 4 * 3600 { report(path + ".slots", "Day \(day) prescribes more than four hours of explicit duration goals; review training load.", warning: true) }
            }
        }
        var usedPhases = Set<String>()
        var usedPatterns = Set<String>()
        var previousPhase = -1
        var occurrences = 0
        var totalSteps = 0
        for (index, week) in document.weeks.enumerated() {
            let path = "$.weeks[\(index)]"
            usedPhases.insert(week.phaseId)
            usedPatterns.insert(week.weekPatternId)
            if let phaseIndex = phaseIndices[week.phaseId] {
                if phaseIndex < previousPhase || phaseIndex > previousPhase + 1 { report(path + ".phaseId", "Phases must follow declaration order in contiguous week ranges.") }
                previousPhase = phaseIndex
            } else { report(path + ".phaseId", "References an unknown phase.") }
            if let pattern = patterns[week.weekPatternId] {
                occurrences += pattern.slots.count
                totalSteps += pattern.slots.reduce(0) { $0 + (stepCounts[$1.sessionTemplateId] ?? 0) }
            } else { report(path + ".weekPatternId", "References an unknown week pattern.") }
        }
        if occurrences > 5_824 { report("$.weeks", "Expanded schedule exceeds 5,824 occurrences.") }
        if totalSteps > 200_000 { report("$.weeks", "Expanded program exceeds 200,000 execution steps.") }
        for (index, phase) in document.phases.enumerated() {
            if !usedPhases.contains(phase.id) { report("$.phases[\(index)].id", "Every declared phase must be used by the ordered weeks.") }
            nutrition(phase.nutritionTargets, "$.phases[\(index)].nutritionTargets")
            recovery(phase.recoveryTargets, "$.phases[\(index)].recoveryTargets")
        }
        for (index, pattern) in document.weekPatterns.enumerated() where !usedPatterns.contains(pattern.id) { report("$.weekPatterns[\(index)]", "Unused week pattern is retained for review.", warning: true) }
        let scheduledTemplates = Set(document.weekPatterns.filter { usedPatterns.contains($0.id) }.flatMap { $0.slots.map(\.sessionTemplateId) })
        for (index, template) in document.sessionTemplates.enumerated() where !scheduledTemplates.contains(template.id) { report("$.sessionTemplates[\(index)]", "Unused session template is retained for review.", warning: true) }
        for (index, rule) in (document.progressionRules ?? []).enumerated() {
            let path = "$.progressionRules[\(index)]"
            switch rule {
            case let .doubleProgression(rule):
                if rule.increment.value <= 0 { report(path + ".increment.value", "Progression increment must be greater than zero.") }
                guard let template = templates[rule.sessionTemplateId] else { report(path + ".sessionTemplateId", "References an unknown session template."); continue }
                guard case let .strength(session) = template else { report(path + ".sessionTemplateId", "Double progression requires a strength template."); continue }
                guard let row = session.exercises.first(where: { $0.id == rule.exerciseId }) else { report(path + ".exerciseId", "References an unknown exercise row in the strength template."); continue }
                let working = row.sets.filter { $0.role == .working }
                if working.isEmpty { report(path + ".exerciseId", "Double progression requires at least one working set.") }
                for set in working {
                    if case .reps = set.target { } else { report(path + ".exerciseId", "Every working set targeted by double progression must prescribe reps.") }
                    if set.effort?.scale != .rir { report(path + ".exerciseId", "Every working set targeted by double progression must prescribe RIR.") }
                }
            case let .manualReview(rule):
                for (templateIndex, id) in rule.sessionTemplateIds.enumerated() where templates[id] == nil { report("\(path).sessionTemplateIds[\(templateIndex)]", "References an unknown session template.") }
            }
        }
        return Array((issues.filter { $0.severity == .error } + issues.filter { $0.severity == .warning }).prefix(200))
    }
}

/// SHA-256 keeps persisted fingerprints portable without depending on an optional AI framework.
private enum CoachSHA256 {
    static func hexDigest(_ data: Data) -> String {
        let k: [UInt32] = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
        var h: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        var bytes = Array(data)
        let bitCount = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes.append(contentsOf: (0..<8).reversed().map { UInt8((bitCount >> ($0 * 8)) & 0xff) })
        func rotate(_ value: UInt32, _ amount: UInt32) -> UInt32 { (value >> amount) | (value << (32 - amount)) }
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = (0..<4).reduce(0) { ($0 << 8) | UInt32(bytes[offset + i * 4 + $1]) } }
            for i in 16..<64 {
                let a = w[i-15], b = w[i-2]
                w[i] = w[i-16] &+ (rotate(a, 7) ^ rotate(a, 18) ^ (a >> 3)) &+ w[i-7] &+ (rotate(b, 17) ^ rotate(b, 19) ^ (b >> 10))
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let t1 = hh &+ (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[i] &+ w[i]
                let t2 = (rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            for (i, value) in [a,b,c,d,e,f,g,hh].enumerated() { h[i] = h[i] &+ value }
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}
