import Foundation

// Portable prescriptions only. Actual results and local schedule state use separate models.
enum CoachWeightUnit: String, Codable, CaseIterable, Sendable { case kg, lb }
enum CoachDistanceUnit: String, Codable, CaseIterable, Sendable { case m, km, mi }
enum CoachPreferredDistanceUnit: String, Codable, CaseIterable, Sendable { case km, mi }
enum CoachSetRole: String, Codable, CaseIterable, Sendable { case warmup, working, backoff, drop }
enum CoachPrescriptionBasis: String, Codable, CaseIterable, Sendable { case total, perSide }
enum CoachLoadBasis: String, Codable, CaseIterable, Sendable { case totalExternal, perImplement, addedToBodyweight, assistance }
enum CoachActivity: String, Codable, CaseIterable, Sendable { case walk, jog, run, cycle, row, swim, elliptical, other }
enum CoachCheckInField: String, Codable, CaseIterable, Sendable { case sleep, soreness, energy, pain }
enum CoachAdvanceMode: String, Codable, CaseIterable, Sendable { case scheduled, reviewRequired }
enum CoachEffortScale: String, Codable, CaseIterable, Sendable { case rir, rpe }
struct CoachPreferredUnits: Codable, Equatable, Sendable {
    var weight: CoachWeightUnit = .kg
    var distance: CoachPreferredDistanceUnit = .km
}
struct CoachNumericRange: Codable, Equatable, Sendable { var min: Double; var max: Double }
struct CoachEffort: Codable, Equatable, Sendable {
    var scale: CoachEffortScale
    var min: Double
    var max: Double
}

struct CoachWeight: Codable, Equatable, Sendable {
    var value: Double
    var unit: CoachWeightUnit

    init(value: Double, unit: CoachWeightUnit) {
        self.value = value
        self.unit = unit
    }
}

struct CoachDistance: Codable, Equatable, Sendable {
    var value: Double
    var unit: CoachDistanceUnit

    init(value: Double, unit: CoachDistanceUnit) {
        self.value = value
        self.unit = unit
    }
}

struct CoachExerciseChoice: Codable, Equatable, Sendable {
    var key: String
    var name: String
    var equipment: [String]
    var catalogExerciseId: String?

    init(key: String, name: String, equipment: [String] = [], catalogExerciseId: String? = nil) {
        self.key = key
        self.name = name
        self.equipment = equipment
        self.catalogExerciseId = catalogExerciseId
    }
}

struct CoachStrengthSet: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var role: CoachSetRole
    var target: CoachSetTarget
    var load: CoachWeight?
    var effort: CoachEffort?
    var restAfterSeconds: Int?
    var notes: String?

    init(id: String = UUID().uuidString, role: CoachSetRole, target: CoachSetTarget, load: CoachWeight? = nil, effort: CoachEffort? = nil, restAfterSeconds: Int? = nil, notes: String? = nil) {
        self.id = id
        self.role = role
        self.target = target
        self.load = load
        self.effort = effort
        self.restAfterSeconds = restAfterSeconds
        self.notes = notes
    }
}

struct CoachStrengthExercise: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var exercise: CoachExerciseChoice
    var prescriptionBasis: CoachPrescriptionBasis
    var loadBasis: CoachLoadBasis
    var sets: [CoachStrengthSet]
    var substitutions: [CoachExerciseChoice]?
    var notes: String?

    init(id: String = UUID().uuidString, exercise: CoachExerciseChoice, prescriptionBasis: CoachPrescriptionBasis, loadBasis: CoachLoadBasis, sets: [CoachStrengthSet] = [], substitutions: [CoachExerciseChoice]? = nil, notes: String? = nil) {
        self.id = id
        self.exercise = exercise
        self.prescriptionBasis = prescriptionBasis
        self.loadBasis = loadBasis
        self.sets = sets
        self.substitutions = substitutions
        self.notes = notes
    }
}

struct CoachPaceRange: Codable, Equatable, Sendable {
    var minSeconds: Int
    var maxSeconds: Int
    var per: CoachPreferredDistanceUnit

    init(minSeconds: Int, maxSeconds: Int, per: CoachPreferredDistanceUnit) {
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.per = per
    }
}

struct CoachSegmentIntensity: Codable, Equatable, Sendable {
    var rpe: CoachEffort?
    var pace: CoachPaceRange?
    var cue: String?

    init(rpe: CoachEffort? = nil, pace: CoachPaceRange? = nil, cue: String? = nil) {
        self.rpe = rpe
        self.pace = pace
        self.cue = cue
    }
}

struct CoachSegment: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String?
    var activity: CoachActivity
    var target: CoachSegmentTarget
    var intensity: CoachSegmentIntensity?
    var notes: String?

    init(kind: String = "segment", id: String = UUID().uuidString, title: String? = nil, activity: CoachActivity, target: CoachSegmentTarget, intensity: CoachSegmentIntensity? = nil, notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.activity = activity
        self.target = target
        self.intensity = intensity
        self.notes = notes
    }
}

struct CoachRepeatBlock: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var count: Int
    var segments: [CoachSegment]
    var notes: String?

    init(kind: String = "repeat", id: String = UUID().uuidString, count: Int, segments: [CoachSegment] = [], notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.count = count
        self.segments = segments
        self.notes = notes
    }
}

struct CoachStrengthSession: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var exercises: [CoachStrengthExercise]
    var notes: String?

    init(kind: String = "strength", id: String = UUID().uuidString, title: String, exercises: [CoachStrengthExercise] = [], notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.exercises = exercises
        self.notes = notes
    }
}

struct CoachCardioSession: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var warmup: [CoachIntervalBlock]
    var main: [CoachIntervalBlock]
    var cooldown: [CoachIntervalBlock]
    var notes: String?

    init(kind: String = "cardio", id: String = UUID().uuidString, title: String, warmup: [CoachIntervalBlock] = [], main: [CoachIntervalBlock] = [], cooldown: [CoachIntervalBlock] = [], notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.warmup = warmup
        self.main = main
        self.cooldown = cooldown
        self.notes = notes
    }
}

struct CoachRecoverySession: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var durationSeconds: Int?
    var instructions: String

    init(kind: String = "recovery", id: String = UUID().uuidString, title: String, durationSeconds: Int? = nil, instructions: String) {
        self.kind = kind
        self.id = id
        self.title = title
        self.durationSeconds = durationSeconds
        self.instructions = instructions
    }
}

struct CoachRestSession: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var notes: String?

    init(kind: String = "rest", id: String = UUID().uuidString, title: String, notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.notes = notes
    }
}

struct CoachNutritionTargets: Codable, Equatable, Sendable {
    var caloriesKcal: Int?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var notes: String?

    init(caloriesKcal: Int? = nil, proteinGrams: Double? = nil, carbohydrateGrams: Double? = nil, fatGrams: Double? = nil, notes: String? = nil) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.notes = notes
    }
}

struct CoachRecoveryTargets: Codable, Equatable, Sendable {
    var sleepHours: CoachNumericRange?
    var checkInFields: [CoachCheckInField]?
    var notes: String?

    init(sleepHours: CoachNumericRange? = nil, checkInFields: [CoachCheckInField]? = nil, notes: String? = nil) {
        self.sleepHours = sleepHours
        self.checkInFields = checkInFields
        self.notes = notes
    }
}

struct CoachPhase: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var overview: String?
    var advanceMode: CoachAdvanceMode
    var nutritionTargets: CoachNutritionTargets?
    var recoveryTargets: CoachRecoveryTargets?

    init(id: String = UUID().uuidString, title: String, overview: String? = nil, advanceMode: CoachAdvanceMode, nutritionTargets: CoachNutritionTargets? = nil, recoveryTargets: CoachRecoveryTargets? = nil) {
        self.id = id
        self.title = title
        self.overview = overview
        self.advanceMode = advanceMode
        self.nutritionTargets = nutritionTargets
        self.recoveryTargets = recoveryTargets
    }
}

struct CoachSlot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var dayOffset: Int
    var sessionTemplateId: String
    var label: String?
    var notes: String?
    var optional: Bool

    init(id: String = UUID().uuidString, dayOffset: Int, sessionTemplateId: String, label: String? = nil, notes: String? = nil, optional: Bool = false) {
        self.id = id
        self.dayOffset = dayOffset
        self.sessionTemplateId = sessionTemplateId
        self.label = label
        self.notes = notes
        self.optional = optional
    }
    private enum CodingKeys: String, CodingKey { case id, dayOffset, sessionTemplateId, label, notes, optional }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        dayOffset = try c.decode(Int.self, forKey: .dayOffset)
        sessionTemplateId = try c.decode(String.self, forKey: .sessionTemplateId)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        optional = try c.decodeIfPresent(Bool.self, forKey: .optional) ?? false
    }
}

struct CoachWeekPattern: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var slots: [CoachSlot]

    init(id: String = UUID().uuidString, title: String, slots: [CoachSlot] = []) {
        self.id = id
        self.title = title
        self.slots = slots
    }
}

struct CoachWeek: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var phaseId: String
    var weekPatternId: String
    var label: String?

    init(id: String = UUID().uuidString, phaseId: String, weekPatternId: String, label: String? = nil) {
        self.id = id
        self.phaseId = phaseId
        self.weekPatternId = weekPatternId
        self.label = label
    }
}

struct CoachDoubleProgressionRule: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var sessionTemplateId: String
    var exerciseId: String
    var requiredSuccessfulOccurrences: Int
    var minimumRIR: Double
    var increment: CoachWeight
    var reviewRequired: Bool
    var notes: String?

    init(kind: String = "doubleProgression", id: String = UUID().uuidString, title: String, sessionTemplateId: String, exerciseId: String, requiredSuccessfulOccurrences: Int, minimumRIR: Double, increment: CoachWeight, reviewRequired: Bool = true, notes: String? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.sessionTemplateId = sessionTemplateId
        self.exerciseId = exerciseId
        self.requiredSuccessfulOccurrences = requiredSuccessfulOccurrences
        self.minimumRIR = minimumRIR
        self.increment = increment
        self.reviewRequired = reviewRequired
        self.notes = notes
    }
}

struct CoachManualReviewRule: Codable, Equatable, Sendable, Identifiable {
    var kind: String
    var id: String
    var title: String
    var sessionTemplateIds: [String]
    var instructions: String
    var reviewRequired: Bool

    init(kind: String = "manualReview", id: String = UUID().uuidString, title: String, sessionTemplateIds: [String] = [], instructions: String, reviewRequired: Bool = true) {
        self.kind = kind
        self.id = id
        self.title = title
        self.sessionTemplateIds = sessionTemplateIds
        self.instructions = instructions
        self.reviewRequired = reviewRequired
    }
}

struct CoachProgramDocumentV1: Codable, Equatable, Sendable {
    var format: String
    var schemaVersion: Int
    var programId: String
    var revision: Int
    var title: String
    var goal: String
    var overview: String?
    var guidance: String?
    var preferredUnits: CoachPreferredUnits
    var nutritionTargets: CoachNutritionTargets?
    var recoveryTargets: CoachRecoveryTargets?
    var phases: [CoachPhase]
    var sessionTemplates: [CoachSessionTemplate]
    var weekPatterns: [CoachWeekPattern]
    var weeks: [CoachWeek]
    var progressionRules: [CoachProgressionRule]?

    init(format: String = "pace-and-plates.coach-program", schemaVersion: Int = 1, programId: String = UUID().uuidString, revision: Int = 1, title: String, goal: String, overview: String? = nil, guidance: String? = nil, preferredUnits: CoachPreferredUnits = CoachPreferredUnits(), nutritionTargets: CoachNutritionTargets? = nil, recoveryTargets: CoachRecoveryTargets? = nil, phases: [CoachPhase] = [], sessionTemplates: [CoachSessionTemplate] = [], weekPatterns: [CoachWeekPattern] = [], weeks: [CoachWeek] = [], progressionRules: [CoachProgressionRule]? = nil) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.programId = programId
        self.revision = revision
        self.title = title
        self.goal = goal
        self.overview = overview
        self.guidance = guidance
        self.preferredUnits = preferredUnits
        self.nutritionTargets = nutritionTargets
        self.recoveryTargets = recoveryTargets
        self.phases = phases
        self.sessionTemplates = sessionTemplates
        self.weekPatterns = weekPatterns
        self.weeks = weeks
        self.progressionRules = progressionRules
    }
}

typealias CoachPlanDocument = CoachProgramDocumentV1

private enum CoachDiscriminator: String, CodingKey { case kind, min, max, seconds, distance }

enum CoachSetTarget: Codable, Equatable, Sendable {
    case reps(min: Int, max: Int)
    case duration(seconds: Int)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CoachDiscriminator.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "reps": self = .reps(min: try c.decode(Int.self, forKey: .min), max: try c.decode(Int.self, forKey: .max))
        case "duration": self = .duration(seconds: try c.decode(Int.self, forKey: .seconds))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unsupported set target")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CoachDiscriminator.self)
        switch self {
        case let .reps(min, max):
            try c.encode("reps", forKey: .kind); try c.encode(min, forKey: .min); try c.encode(max, forKey: .max)
        case let .duration(seconds):
            try c.encode("duration", forKey: .kind); try c.encode(seconds, forKey: .seconds)
        }
    }
}

enum CoachSegmentTarget: Codable, Equatable, Sendable {
    case duration(seconds: Int)
    case distance(CoachDistance)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CoachDiscriminator.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "duration": self = .duration(seconds: try c.decode(Int.self, forKey: .seconds))
        case "distance": self = .distance(try c.decode(CoachDistance.self, forKey: .distance))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unsupported segment target")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CoachDiscriminator.self)
        switch self {
        case let .duration(seconds): try c.encode("duration", forKey: .kind); try c.encode(seconds, forKey: .seconds)
        case let .distance(distance): try c.encode("distance", forKey: .kind); try c.encode(distance, forKey: .distance)
        }
    }
}

enum CoachIntervalBlock: Codable, Equatable, Sendable {
    case segment(CoachSegment)
    case repeatBlock(CoachRepeatBlock)
    var id: String { switch self { case let .segment(v): v.id; case let .repeatBlock(v): v.id } }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CoachDiscriminator.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "segment": self = .segment(try CoachSegment(from: decoder))
        case "repeat": self = .repeatBlock(try CoachRepeatBlock(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unsupported interval block")
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self { case let .segment(v): try v.encode(to: encoder); case let .repeatBlock(v): try v.encode(to: encoder) }
    }
}

enum CoachSessionTemplate: Codable, Equatable, Sendable, Identifiable {
    case strength(CoachStrengthSession)
    case running(CoachCardioSession)
    case cardio(CoachCardioSession)
    case recovery(CoachRecoverySession)
    case rest(CoachRestSession)
    var id: String {
        switch self { case let .strength(v): v.id; case let .running(v), let .cardio(v): v.id; case let .recovery(v): v.id; case let .rest(v): v.id }
    }
    var title: String {
        switch self { case let .strength(v): v.title; case let .running(v), let .cardio(v): v.title; case let .recovery(v): v.title; case let .rest(v): v.title }
    }
    var kind: String {
        switch self { case .strength: "strength"; case .running: "running"; case .cardio: "cardio"; case .recovery: "recovery"; case .rest: "rest" }
    }
    var notes: String? {
        switch self { case let .strength(v): v.notes; case let .running(v), let .cardio(v): v.notes; case let .recovery(v): v.instructions; case let .rest(v): v.notes }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CoachDiscriminator.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "strength": self = .strength(try CoachStrengthSession(from: decoder))
        case "running": self = .running(try CoachCardioSession(from: decoder))
        case "cardio": self = .cardio(try CoachCardioSession(from: decoder))
        case "recovery": self = .recovery(try CoachRecoverySession(from: decoder))
        case "rest": self = .rest(try CoachRestSession(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unsupported session kind")
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case let .strength(v): try v.encode(to: encoder)
        case var .running(v): v.kind = "running"; try v.encode(to: encoder)
        case var .cardio(v): v.kind = "cardio"; try v.encode(to: encoder)
        case let .recovery(v): try v.encode(to: encoder)
        case let .rest(v): try v.encode(to: encoder)
        }
    }
}

enum CoachProgressionRule: Codable, Equatable, Sendable, Identifiable {
    case doubleProgression(CoachDoubleProgressionRule)
    case manualReview(CoachManualReviewRule)
    var id: String { switch self { case let .doubleProgression(v): v.id; case let .manualReview(v): v.id } }
    var title: String { switch self { case let .doubleProgression(v): v.title; case let .manualReview(v): v.title } }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CoachDiscriminator.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "doubleProgression": self = .doubleProgression(try CoachDoubleProgressionRule(from: decoder))
        case "manualReview": self = .manualReview(try CoachManualReviewRule(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unsupported progression rule")
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self { case let .doubleProgression(v): try v.encode(to: encoder); case let .manualReview(v): try v.encode(to: encoder) }
    }
}
