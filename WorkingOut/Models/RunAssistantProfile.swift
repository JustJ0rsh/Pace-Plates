import Foundation

struct RunAssistantProfile: Codable, Equatable {
    var goalFocus: String // endurance | speed | hybrid
    var targetDistanceMiles: Double // 1 | 2 | 3
    var abilityLevel: String // brand_new | run_walk | continuous
    var currentAveragePaceMinPerMile: Double // current baseline pace in minutes per mile
    var paceGoalMinPerMile: Double // target pace in minutes per mile
    var daysPerWeek: Int // 3 | 4 | 5 | 6
    var longRunWeekday: Int // 1...7 (Sun...Sat)
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int

    var targetDistanceMeters: Double {
        targetDistanceMiles * 1609.34
    }

    var primaryGoal: String {
        goalFocus
    }

    static let `default` = RunAssistantProfile(
        goalFocus: "hybrid",
        targetDistanceMiles: 3,
        abilityLevel: "run_walk",
        currentAveragePaceMinPerMile: 12.0,
        paceGoalMinPerMile: 9.5,
        daysPerWeek: 4,
        longRunWeekday: 7,
        reminderEnabled: false,
        reminderHour: 7,
        reminderMinute: 0
    )

    private enum CodingKeys: String, CodingKey {
        case goalFocus
        case targetDistanceMiles
        case abilityLevel
        case currentAveragePaceMinPerMile
        case paceGoalMinPerMile
        case daysPerWeek
        case longRunWeekday
        case reminderEnabled
        case reminderHour
        case reminderMinute
    }

    init(
        goalFocus: String,
        targetDistanceMiles: Double,
        abilityLevel: String,
        currentAveragePaceMinPerMile: Double = 12.0,
        paceGoalMinPerMile: Double = 9.5,
        daysPerWeek: Int,
        longRunWeekday: Int,
        reminderEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int
    ) {
        self.goalFocus = goalFocus
        self.targetDistanceMiles = targetDistanceMiles
        self.abilityLevel = abilityLevel
        self.currentAveragePaceMinPerMile = currentAveragePaceMinPerMile
        self.paceGoalMinPerMile = paceGoalMinPerMile
        self.daysPerWeek = daysPerWeek
        self.longRunWeekday = longRunWeekday
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goalFocus = try container.decodeIfPresent(String.self, forKey: .goalFocus) ?? "hybrid"
        targetDistanceMiles = try container.decodeIfPresent(Double.self, forKey: .targetDistanceMiles) ?? 3
        abilityLevel = try container.decodeIfPresent(String.self, forKey: .abilityLevel) ?? "run_walk"
        currentAveragePaceMinPerMile = try container.decodeIfPresent(Double.self, forKey: .currentAveragePaceMinPerMile)
            ?? Self.defaultCurrentAveragePace(for: abilityLevel)
        paceGoalMinPerMile = try container.decodeIfPresent(Double.self, forKey: .paceGoalMinPerMile) ?? 9.5
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 4
        longRunWeekday = try container.decodeIfPresent(Int.self, forKey: .longRunWeekday) ?? 7
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 7
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
    }

    private static func defaultCurrentAveragePace(for abilityLevel: String) -> Double {
        switch abilityLevel {
        case "brand_new": return 13.5
        case "continuous": return 10.5
        default: return 12.0
        }
    }
}

extension RunAssistantProfile {
    func asJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSONString(_ json: String?) -> RunAssistantProfile? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RunAssistantProfile.self, from: data)
    }
}

struct RunAssistantAIGenerationRequest {
    var style: String // speed | endurance | hybrid
    var titleHint: String
}

struct RunAssistantAIGenerationResult {
    var planName: String
    var style: String
    var targetDistanceMeters: Double
    var primaryGoal: String
    var durationWeeks: Int
    var daysPerWeek: Int
    var sessions: [RunPlanSessionBlueprint]
    var prompt: String
}
