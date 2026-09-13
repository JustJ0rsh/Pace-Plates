import Foundation
import CryptoKit

@main
struct CoachContractChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
        let fixtureDirectory = root.appendingPathComponent("WorkingOut/Resources/Coach")
        let validator = CoachPlanValidator(schemaData: try Data(contentsOf: fixtureDirectory.appendingPathComponent("coach-plan-v1.schema.json")))
        let fixture = try Data(contentsOf: fixtureDirectory.appendingPathComponent("example-coach-plan.json"))
        let text = String(decoding: fixture, as: UTF8.self)
        let original = try JSONSerialization.jsonObject(with: fixture)
        let valid = try validator.validate(fixture)
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        func replacement(_ node: Any, _ path: ArraySlice<String>, _ value: Any?) -> Any {
            guard let key = path.first else { return value ?? NSNull() }
            if var object = node as? [String: Any] {
                if path.count == 1 { object[key] = value }
                else { object[key] = replacement(object[key]!, path.dropFirst(), value) }
                return object
            }
            var array = node as! [Any]
            array[Int(key)!] = replacement(array[Int(key)!], path.dropFirst(), value)
            return array
        }
        func changed(_ path: String, _ value: Any?) throws -> Data {
            try JSONSerialization.data(withJSONObject: replacement(original, ArraySlice(path.split(separator: ".").map(String.init)), value), options: [.sortedKeys])
        }
        func rejects(_ data: Data, _ path: String, _ name: String) {
            do { _ = try validator.validate(data); preconditionFailure("Accepted invalid \(name)") }
            catch let error as CoachValidationError {
                check(error.issues.contains { $0.severity == .error && $0.path.hasPrefix(path) }, "\(name): wrong error path \(error)")
            } catch { preconditionFailure("\(name): unexpected error \(error)") }
        }
        func rejectsText(_ text: String, _ path: String = "$", _ name: String) { rejects(Data(text.utf8), path, name) }
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let start = CoachSchedule.date(from: "2026-03-28", timeZone: berlin)!
        let schedule = try CoachSchedule.expand(valid, startDate: start, timeZone: berlin)
        check(schedule.count == 8, "Fixture occurrence count")
        check(schedule.filter { $0.template.kind == "strength" }.count == 4, "Fixture strength occurrences")
        check(schedule.filter { $0.isOptional }.count == 2, "Optional run slots")
        check(schedule.filter { $0.template.kind == "rest" }.count == 2, "Explicit rest occurrences")
        check(try schedule.reduce(0) { $0 + (try CoachSchedule.steps(for: $1.template).count) } == 30, "Fixture expanded step count")
        check(Set(schedule.map(\.sourceKey)).count == 8, "Reused templates have separate occurrence identity")
        check(try CoachSchedule.steps(for: valid.document.sessionTemplates[1]).count == 8, "Run repeats expand to eight steps")
        check(Set(try CoachSchedule.steps(for: valid.document.sessionTemplates[1]).map(\.id)).count == 8, "Repeated interval step IDs are distinct")
        check(schedule[0].intraDayOrder == 0 && schedule[1].intraDayOrder == 1, "Preserve same-day slot order")
        check(schedule[3].civilDate == "2026-04-03" && schedule[4].civilDate == "2026-04-04", "Calendar-day expansion crosses DST")
        let fallSchedule = try CoachSchedule.expand(valid, startDate: CoachSchedule.date(from: "2026-10-24", timeZone: berlin)!, timeZone: berlin)
        check(fallSchedule[4].civilDate == "2026-10-31", "Fall DST preserves civil dates")
        check(CoachSchedule.date(from: "2026-02-30", timeZone: berlin) == nil, "Invalid civil date rejected")
        check(schedule.map(\.sourceKey) == fallSchedule.map(\.sourceKey), "Date changes preserve author occurrence identity")
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!, kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        let chosenDay = CoachSchedule.date(from: "2026-09-13", timeZone: honolulu)!
        let preservedDay = CoachSchedule.date(from: CoachSchedule.civilDate(chosenDay, timeZone: honolulu), timeZone: kiritimati)!
        check(CoachSchedule.civilDate(preservedDay, timeZone: kiritimati) == "2026-09-13", "Time-zone selection preserves chosen civil start day")
        let western = try CoachSchedule.expand(valid, startDate: chosenDay, timeZone: honolulu)
        let eastern = try CoachSchedule.expand(valid, startDate: preservedDay, timeZone: kiritimati)
        check(western.map(\.civilDate) == eastern.map(\.civilDate), "Date-line zones produce the same reviewed civil schedule")
        check(western.map(\.sourceKey) == eastern.map(\.sourceKey), "Time-zone selection preserves occurrence identity")
        check(CoachSchedule.date(from: "2011-12-30", timeZone: TimeZone(identifier: "Pacific/Apia")!) == nil, "A skipped civil day must not be silently changed")
        let decodedExport = try validator.validate(valid.canonicalData)
        check(decodedExport.document == valid.document && decodedExport.fingerprint == valid.fingerprint, "Portable round trip")
        let fenced = try validator.validate("\u{FEFF} \n```json\n\(text)\n``` \n")
        check(fenced.fingerprint == valid.fingerprint, "BOM/fence normalization")
        check(try validator.validate("```\n\(text)\n```").fingerprint == valid.fingerprint, "Unlabeled fence")
        check(try validator.validate(changed("revision", 2)).fingerprint == valid.fingerprint, "Revision excluded from fingerprint")
        check(try validator.validate(changed("weekPatterns.0.slots.0.optional", false)).fingerprint == valid.fingerprint, "Omitted optional normalizes to false")
        check(try validator.validate(text.replacingOccurrences(of: "\"min\": 2,", with: "\"min\": 2.0,")).fingerprint == valid.fingerprint, "Equivalent numeric encoding")
        check(try validator.validate(changed("overview", "Changed actual instructions")).fingerprint != valid.fingerprint, "Notes/instructions preserved in fingerprint")
        var reversed = valid.document
        reversed.sessionTemplates.reverse()
        check(try validator.validate(reversed).fingerprint != valid.fingerprint, "Array order remains meaningful")
        var fingerprintObject = try JSONSerialization.jsonObject(with: valid.canonicalData) as! [String: Any]
        fingerprintObject.removeValue(forKey: "revision")
        // All fixture numbers have exact JSONSerialization-compatible canonical spellings.
        let referenceData = try JSONSerialization.data(withJSONObject: fingerprintObject, options: [.sortedKeys, .withoutEscapingSlashes])
        check(SHA256.hash(data: referenceData).map { String(format: "%02x", $0) }.joined() == valid.fingerprint, "Fingerprint matches platform SHA256")
        rejectsText(text.replacingOccurrences(of: "\"title\": \"Import and Tracking Demo\",", with: "\"title\": \"First\", \"title\": \"Second\","), "$.title", "duplicate root key")
        rejectsText(text.replacingOccurrences(of: "\"weight\": \"kg\",", with: "\"weight\": \"kg\", \"we\\u0069ght\": \"lb\","), "$.preferredUnits.weight", "escaped duplicate key")
        rejectsText(text + text, "$", "multiple JSON objects")
        rejectsText("Here is your plan: " + text, "$", "surrounding prose")
        rejectsText("```swift\n" + text + "\n```", "$", "unsupported fence language")
        rejectsText("```json\n" + text + "\n```\n```json\n" + text + "\n```", "$", "multiple fences")
        rejectsText(text.replacingOccurrences(of: "\"revision\": 1,", with: "\"revision\": NaN,"), "$.revision", "nonfinite NaN")
        rejectsText(text.replacingOccurrences(of: "\"revision\": 1,", with: "\"revision\": 1e999,"), "$.revision", "nonfinite overflow")
        rejectsText(text.replacingOccurrences(of: "\"revision\": 1,", with: "\"revision\": 01,"), "$", "leading zero")
        rejectsText(text.dropLast(2) + ",}", "$", "trailing comma")
        rejects(Data(repeating: 32, count: CoachPlanValidator.maximumInputBytes + 1), "$", "input byte limit")
        check(try validator.validate(text.replacingOccurrences(of: "\"schemaVersion\": 1,", with: "\"schemaVersion\": 1.0,")).fingerprint == valid.fingerprint, "Integral float schema version")
        rejects(try changed("programId", "program\n"), "$.programId", "identifier trailing newline")
        rejectsText(text.replacingOccurrences(of: "\"value\": 2.5,", with: "\"value\": 1e-999,"), "$.progressionRules[0].increment.value", "numeric underflow")
        rejects(try changed("schemaVersion", 2), "$.schemaVersion", "unsupported version")
        rejects(try changed("schemaVersion", true), "$.schemaVersion", "boolean version is not integer")
        rejects(try changed("title", nil), "$.title", "missing required key")
        rejects(try changed("typo", 1), "$.typo", "unknown root key")
        rejects(try changed("preferredUnits.typo", "kg"), "$.preferredUnits.typo", "unknown nested key")
        rejects(try changed("preferredUnits.weight", "stone"), "$.preferredUnits.weight", "unknown unit")
        rejects(try changed("nutritionTargets.proteinGrams", "150"), "$.nutritionTargets.proteinGrams", "numeric string")
        rejects(try changed("sessionTemplates.0.exercises.0.sets.0.target.extra", 1), "$.sessionTemplates[0].exercises[0].sets[0].target.extra", "unknown nested union field")
        rejects(try changed("sessionTemplates.0.exercises.0.sets.0.target.min", 11), "$.sessionTemplates[0].exercises[0].sets[0].target", "reversed rep range")
        rejects(try changed("sessionTemplates.0.exercises.0.sets.0.effort.min", 4), "$.sessionTemplates[0].exercises[0].sets[0].effort", "reversed effort range")
        rejects(try changed("sessionTemplates.0.exercises.0.sets.1.id", "work-1"), "$.sessionTemplates[0].exercises[0].sets[1].id", "duplicate set ID")
        rejects(try changed("weekPatterns.0.slots.1.id", "day-1-lift"), "$.weekPatterns[0].slots[1].id", "duplicate slot ID")
        rejects(try changed("weeks.1.id", "week-01"), "$.weeks[1].id", "duplicate week ID")
        rejects(try changed("weeks.0.weekPatternId", "missing"), "$.weeks[0].weekPatternId", "unknown pattern reference")
        rejects(try changed("weekPatterns.0.slots.0.sessionTemplateId", "missing"), "$.weekPatterns[0].slots[0].sessionTemplateId", "unknown template reference")
        rejects(try changed("weekPatterns.0.slots.3.dayOffset", 0), "$.weekPatterns[0].slots", "rest/workout conflict")
        rejects(try changed("nutritionTargets", ["notes": "no numeric target"]), "$.nutritionTargets", "empty nutrition numeric targets")
        rejects(try changed("recoveryTargets", [:] as [String: Any]), "$.recoveryTargets", "empty recovery target")
        rejects(try changed("recoveryTargets.checkInFields", ["pain", "pain"]), "$.recoveryTargets.checkInFields[1]", "duplicate recovery fields")
        rejects(try changed("sessionTemplates.1.main.0.segments.0.intensity", [:] as [String: Any]), "$.sessionTemplates[1].main[0].segments[0].intensity", "empty intensity")
        rejects(try changed("sessionTemplates.1.main.0.segments.0.activity", "cycle"), "$.sessionTemplates[1].main[0].segments[0].activity", "unsupported running activity")
        rejects(try changed("sessionTemplates.1.main.0.segments.0.kind", "repeat"), "$.sessionTemplates[1].main[0].segments[0].kind", "nested repeats")
        rejects(try changed("sessionTemplates.1.cooldown.0.id", "jog"), "$.sessionTemplates[1].cooldown[0].id", "IDs across cardio sections")
        rejects(try changed("progressionRules.0.reviewRequired", false), "$.progressionRules[0].reviewRequired", "unreviewed progression")
        rejects(try changed("progressionRules.0.increment.value", 0), "$.progressionRules[0].increment.value", "zero progression increment")
        rejects(try changed("progressionRules.0.sessionTemplateId", "run-walk"), "$.progressionRules[0].sessionTemplateId", "wrong progression session kind")
        rejects(try changed("progressionRules.0.exerciseId", "plank"), "$.progressionRules[0].exerciseId", "timed progression row")
        rejects(try changed("sessionTemplates.0.exercises.0.sets.0.effort.scale", "rpe"), "$.progressionRules[0].exerciseId", "RPE is not RIR")
        let inconsistentCalories = try validator.validate(changed("nutritionTargets.caloriesKcal", 3000))
        check(inconsistentCalories.issues.contains { $0.severity == .warning && $0.path == "$.nutritionTargets" }, "Macro inconsistency warns")
        var full = valid.document
        full.phases.append(.init(id: "second", title: "Second phase", advanceMode: .reviewRequired, nutritionTargets: .init(proteinGrams: 160)))
        full.weeks = (1...26).map { .init(id: "week-\($0)", phaseId: $0 <= 13 ? "intro" : "second", weekPatternId: "example-week") }
        let fullValidated = try validator.validate(full)
        let fullExpanded = try CoachSchedule.expand(fullValidated, startDate: start, timeZone: berlin)
        check(fullExpanded.count == 104 && Set(fullExpanded.map(\.sourceKey)).count == 104, "Complete 26-week expansion")
        check(try validator.validate(fullValidated.canonicalData).document == full, "26-week content round trip")
        check(CoachSchedule.nutritionTargets(in: full, phaseId: "second")?.caloriesKcal == nil, "Phase targets replace entire blocks")
        var noncontiguous = full
        noncontiguous.weeks[25].phaseId = "intro"
        rejects(try JSONEncoder().encode(noncontiguous), "$.weeks[25].phaseId", "noncontiguous phase")
        var manySets = valid.document
        if case var .strength(session) = manySets.sessionTemplates[0] {
            session.exercises = (0..<11).map { index in
                var row = session.exercises[0]; row.id = "row-\(index)"
                row.sets = (0..<20).map { index in var set = row.sets[0]; set.id = "set-\(index)"; return set }
                return row
            }
            manySets.sessionTemplates[0] = .strength(session)
        }
        rejects(try JSONEncoder().encode(manySets), "$.sessionTemplates[0].exercises", "aggregate strength set cap")
        var huge = valid.document
        huge.progressionRules = nil
        let segments = (0..<16).map { CoachSegment(id: "s-\($0)", activity: .run, target: .duration(seconds: 1)) }
        huge.sessionTemplates = [.running(.init(id: "huge-run", title: "Resource boundary", main: [.repeatBlock(.init(id: "r1", count: 100, segments: segments)), .repeatBlock(.init(id: "r2", count: 100, segments: segments.enumerated().map { index, value in var s = value; s.id = "second-\(index)"; return s }))]))]
        huge.weekPatterns = [.init(id: "pattern", title: "Resource boundary", slots: [.init(id: "slot", dayOffset: 0, sessionTemplateId: "huge-run")])]
        huge.weeks = [.init(id: "week", phaseId: "intro", weekPatternId: "pattern")]
        rejects(try JSONEncoder().encode(huge), "$.sessionTemplates[0]", "expanded segment cap")
        if case var .running(session) = huge.sessionTemplates[0] {
            session.main = [.repeatBlock(.init(id: "repeat", count: 100, segments: segments))]
            huge.sessionTemplates[0] = .running(session)
        }
        huge.weekPatterns[0].slots.append(.init(id: "slot-two", dayOffset: 1, sessionTemplateId: "huge-run"))
        huge.weeks = (0..<104).map { .init(id: "week-\($0)", phaseId: "intro", weekPatternId: "pattern") }
        rejects(try JSONEncoder().encode(huge), "$.weeks", "program aggregate expansion cap")
        do {
            _ = try CoachSchedule.steps(for: .running(.init(id: "bad", title: "Corrupt repeat", main: [.repeatBlock(.init(id: "bad-block", count: Int.max, segments: segments))])))
            preconditionFailure("Expanded malformed repeat count")
        } catch is CoachValidationError { checks += 1 }
        print("Coach contract checks passed: \(checks)")
    }
}
