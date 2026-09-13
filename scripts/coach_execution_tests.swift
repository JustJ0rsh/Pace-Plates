import Foundation

@main
struct CoachExecutionTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("FAIL: \(message)") }
    }
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let feedbackNow = ISO8601DateFormatter().date(from: "2026-03-09T12:00:00Z")!
        expect(CoachProgressionRules.shouldHoldForRecovery(civilDate: "2026-03-09", timeZoneIdentifier: "America/New_York", painScore: 2, soreness: nil, now: feedbackNow), "current-day pain feedback holds progression")
        expect(!CoachProgressionRules.shouldHoldForRecovery(civilDate: "2025-12-01", timeZoneIdentifier: "America/New_York", painScore: 2, soreness: nil, now: feedbackNow), "editing old pain feedback does not make its observation recent")
        expect(!CoachProgressionRules.shouldHoldForRecovery(civilDate: "2026-03-10", timeZoneIdentifier: "America/New_York", painScore: 2, soreness: nil, now: feedbackNow), "future-dated feedback is not current recovery evidence")
        expect(CoachProgressionRules.shouldHoldForRecovery(civilDate: "2026-03-03", timeZoneIdentifier: "America/New_York", painScore: nil, soreness: 7, now: feedbackNow), "seven civil-day recovery window survives daylight saving transition")
        expect(!CoachProgressionRules.shouldHoldForRecovery(civilDate: "2026-03-02", timeZoneIdentifier: "America/New_York", painScore: nil, soreness: 7, now: feedbackNow), "feedback before seven-day civil window does not hold progression")
        var rest = CoachRestTimerState(setResultID: "lift/set1", seconds: 90, now: now)
        expect(rest.remaining(at: now.addingTimeInterval(30)) == 60, "rest deadline drives display")
        rest.pause(at: now.addingTimeInterval(30))
        expect(rest.remaining(at: now.addingTimeInterval(900)) == 60, "paused rest does not elapse")
        rest.adjust(by: -15, at: now.addingTimeInterval(900))
        rest.resume(at: now.addingTimeInterval(900))
        expect(rest.remaining(at: now.addingTimeInterval(930)) == 15, "adjust and resume preserve remaining")
        expect(rest.remaining(at: now.addingTimeInterval(1_000)) == 0, "expired rest never restarts")
        expect(rest.remaining(at: now) <= 45, "clock moving backwards cannot invent prolonged rest")
        let encoded = try JSONEncoder().encode(rest)
        let decoded = try JSONDecoder().decode(CoachRestTimerState.self, from: encoded)
        expect(decoded == rest, "rest relaunch snapshot round trip")

        let steps = [CoachRunStep(id: "warm", label: "Walk", repeatIndex: 0, targetSeconds: 60),
                     CoachRunStep(id: "work", label: "Run", repeatIndex: 1, targetMeters: 100),
                     CoachRunStep(id: "recover", label: "Walk", repeatIndex: 1, targetSeconds: 30)]
        var intervals = CoachRunIntervalState(steps: steps, prescriptionRevisionID: UUID(), baselineMeters: 0)
        expect(intervals.isValid, "valid bounded interval state")
        intervals.observe(duration: 30, meters: nil)
        expect(intervals.stepIndex == 0, "time goal incomplete")
        intervals.observe(duration: 60, meters: nil)
        expect(intervals.stepIndex == 1 && intervals.results.first?.distanceMeters == nil, "missing GPS stays unknown")
        intervals.observe(duration: 60, meters: nil)
        expect(intervals.stepIndex == 1, "paused active clock makes no progress")
        intervals.observe(duration: 70, meters: 200)
        expect(intervals.stepIndex == 1, "first late GPS establishes baseline rather than prior distance")
        intervals.observe(duration: 80, meters: 250)
        expect(intervals.stepIndex == 1, "distance target requires real coverage")
        intervals.observe(duration: 90, meters: 305)
        expect(intervals.stepIndex == 2 && intervals.results.last?.distanceMeters == 105, "measured distance completes exact current step")
        intervals.advance(duration: 100, meters: 310, method: .skip)
        expect(intervals.isComplete && !intervals.completedAll, "skip remains distinct from completion")
        expect(intervals.results.last?.state == .skipped, "skip result is explicit")
        let restored = try JSONDecoder().decode(CoachRunIntervalState.self, from: JSONEncoder().encode(intervals))
        expect(restored == intervals, "interval state preserves IDs, baselines, results, revision")
        var invalidAdvance = CoachRunIntervalState(steps: steps, prescriptionRevisionID: nil)
        invalidAdvance.advance(duration: .infinity, meters: nil, method: .manual)
        expect(invalidAdvance.stepIndex == 0, "invalid active duration cannot create interval results")
        invalidAdvance.advance(duration: 10, meters: -.infinity, method: .manual)
        expect(invalidAdvance.stepIndex == 0, "invalid distance cannot advance a manual interval")
        invalidAdvance.advance(duration: 10, meters: nil, method: .manual)
        invalidAdvance.advance(duration: 9, meters: nil, method: .manual)
        expect(invalidAdvance.stepIndex == 1, "a backwards active clock cannot create another completed interval")
        expect(!CoachRunIntervalState(steps: [], prescriptionRevisionID: nil).isValid, "empty interval prescription is invalid")
        var invalidResult = intervals
        invalidResult.results[0].effort = 3; invalidResult.results[0].effortScale = nil
        expect(!invalidResult.isValid, "recorded interval effort requires its explicit scale")
        var delayed = CoachRunIntervalState(steps: [steps[0], steps[0], steps[0]], prescriptionRevisionID: nil)
        delayed.observe(duration: 300, meters: nil)
        expect(delayed.stepIndex == 1, "delayed observation cannot fabricate several interval boundaries")
        delayed.restorePaused(at: 400)
        delayed.observe(duration: 405, meters: nil)
        expect(delayed.stepIndex == 1 && delayed.baselineDuration == 400, "relaunch excludes uncertain time instead of manufacturing completed steps")
        delayed.finishEarly(duration: 405, meters: nil)
        expect(delayed.results.last?.state == .partial && delayed.stepIndex == 2, "early finish preserves unfinished sequence")

        let legacyID = UUID()
        let legacyJSON = """
        {"sessionID":"\(legacyID.uuidString)","sessionType":"easy","intensityLevel":"easy"}
        """
        let legacy = try JSONDecoder().decode(ScheduledRunTarget.self, from: Data(legacyJSON.utf8))
        expect(legacy.legacySessionID == legacyID && legacy.canonicalOccurrenceID == nil, "old recovery target retains legacy model ownership")
        let canonical = ScheduledRunTarget(sessionID: legacyID, sessionType: "run", targetDistanceMeters: nil,
            targetDurationSeconds: nil, targetPaceMinPerMile: nil, intensityLevel: "planned", notes: nil,
            planReference: .canonicalOccurrence(legacyID), executionID: UUID(), structuredSteps: steps)
        expect(canonical.legacySessionID == nil && canonical.canonicalOccurrenceID == legacyID, "tag disambiguates same UUID between models")

        let target = CoachStrengthSet(id: "s", role: .working, target: .reps(min: 8, max: 12), effort: .init(scale: .rir, min: 2, max: 4))
        let exercise = CoachStrengthExercise(id: "e", exercise: .init(key: "squat", name: "Squat", equipment: ["barbell"]),
            prescriptionBasis: .total, loadBasis: .totalExternal, sets: [target])
        let strength = CoachStrengthSession(id: "lift", title: "Lift", exercises: [exercise])
        let rule = CoachDoubleProgressionRule(id: "rule", title: "Progress", sessionTemplateId: "lift", exerciseId: "e",
            requiredSuccessfulOccurrences: 2, minimumRIR: 2, increment: .init(value: 2.5, unit: .kg))
        let actual = CoachSetResult(id: "e/s", exerciseID: "e", setID: "s", performedExerciseID: "squat", performedExerciseName: "Squat",
            equipment: "barbell", reps: 12, load: 30, loadUnit: "kg", loadBasis: "totalExternal", repCounting: "total",
            effortScale: "rir", effort: 2, state: .completed)
        var unsafeActual = actual
        unsafeActual.durationSeconds = 1e100
        expect(!unsafeActual.isValid, "finite duration beyond integer history storage is rejected before conversion")
        unsafeActual = actual; unsafeActual.loadUnit = nil
        expect(!unsafeActual.isValid, "actual load without a unit cannot establish a comparable baseline")
        var evidence = [CoachProgressionEvidence(executionID: UUID(), endedAt: now, status: "completed", prescription: strength, results: [actual], revision: "a", painScore: 0, readinessReviewed: true),
                        CoachProgressionEvidence(executionID: UUID(), endedAt: now.addingTimeInterval(-86_400), status: "completed", prescription: strength, results: [actual], revision: "b", painScore: 0, readinessReviewed: true)]
        if case let .propose(proposal) = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) {
            expect(proposal.newLoads["s"]?.value == 32.5, "actual baseline plus configured increment")
        } else { fatalError("valid evidence must propose") }
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: true) { checks += 1 }
        else { fatalError("pain hold required") }
        evidence[1].painScore = nil
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("unknown historical pain feedback cannot document pain-free progression evidence") }
        evidence[1].painScore = 0; evidence[1].readinessReviewed = false
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("unresolved phase readiness blocks load increase") }
        evidence[1].readinessReviewed = true
        evidence[1].prescription.exercises[0].sets[0].target = .reps(min: 6, max: 10)
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("sessions at another rep range cannot satisfy current progression count") }
        evidence[1].prescription = strength
        var extraSet = target; extraSet.id = "additional"
        evidence[0].prescription.exercises[0].sets.append(extraSet)
        var extraActual = actual; extraActual.setID = "additional"; extraActual.id = "e/additional"
        evidence[0].results.append(extraActual)
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("changed working-set composition requires new comparable history") }
        evidence[0].prescription = strength; evidence[0].results = [actual]
        evidence[0].results[0].effort = .infinity
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("invalid actual effort cannot qualify for progression") }
        evidence[0].results[0] = actual
        let validEvidence = evidence
        for index in evidence.indices {
            evidence[index].prescription.exercises[0].loadBasis = .assistance
            evidence[index].results[0].loadBasis = "assistance"
        }
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("adding assistance must not be suggested as increased resistance") }
        evidence = validEvidence
        evidence[0].results[0].load = nil
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("unknown load cannot create zero baseline") }
        evidence[0].results[0] = actual; evidence[0].results[0].effortScale = "rpe"
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("RPE must never silently convert to RIR") }
        evidence[0].results[0] = actual; evidence[0].results[0].state = .skipped
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("skipped work is not qualifying evidence") }
        evidence[0].results[0] = actual; evidence[0].results[0].performedExerciseID = "other"
        if case .hold = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("unapproved substitution cannot qualify") }
        evidence[0].results[0].substitutionIsEquivalent = true
        if case .propose = try CoachProgressionRules.evaluate(rule: rule, evidence: evidence, holdForRecovery: false) { checks += 1 }
        else { fatalError("explicit equivalence permits substitution") }
        let unchanged = try CoachProgressionRules.fingerprint(evidence)
        evidence[0].results[0].updatedAt = now.addingTimeInterval(500)
        evidence[0].revision = "resaved-with-no-actual-change"
        let unchangedAfterSave = try CoachProgressionRules.fingerprint(evidence)
        expect(unchangedAfterSave == unchanged, "resaving unchanged actuals cannot resurface dismissed suggestions")
        let before = try CoachProgressionRules.fingerprint(evidence)
        evidence[0].results[0].reps = 11
        let after = try CoachProgressionRules.fingerprint(evidence)
        expect(before != after, "actual correction changes evidence revision")
        print("Coach execution checks passed: \(checks)")
    }
}
