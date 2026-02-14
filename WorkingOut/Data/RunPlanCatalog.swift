import Foundation

struct RunPlanSessionBlueprint: Codable, Equatable {
    var weekIndex: Int
    var dayIndex: Int
    var scheduledWeekday: Int
    var sessionType: String
    var targetDistanceMeters: Double?
    var targetDurationSeconds: Double?
    var targetPaceMinPerMile: Double?
    var intensityLevel: String
    var notes: String?
}

struct RunPlanTemplateDescriptor: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var source: String = "built_in"
    var style: String // endurance_beginner | endurance_intermediate | speed_beginner | speed_intermediate | hybrid
    var targetDistanceMiles: Double
    var targetDistanceMeters: Double
    var primaryGoal: String // endurance | speed | hybrid
    var durationWeeks: Int
    var recommendedAbilityLevels: [String]

    init(
        id: String,
        name: String,
        style: String,
        targetDistanceMiles: Double,
        primaryGoal: String,
        durationWeeks: Int,
        recommendedAbilityLevels: [String]
    ) {
        self.id = id
        self.name = name
        self.style = style
        self.targetDistanceMiles = targetDistanceMiles
        self.targetDistanceMeters = targetDistanceMiles * 1609.34
        self.primaryGoal = primaryGoal
        self.durationWeeks = durationWeeks
        self.recommendedAbilityLevels = recommendedAbilityLevels
    }
}

enum RunPlanCatalog {
    static let allTemplates: [RunPlanTemplateDescriptor] = {
        var output: [RunPlanTemplateDescriptor] = []

        let distances: [Double] = [1, 2, 3]
        let styles: [(style: String, goal: String, label: String, ability: [String])] = [
            ("endurance_beginner", "endurance", "Endurance Beginner", ["brand_new", "run_walk"]),
            ("endurance_intermediate", "endurance", "Endurance Intermediate", ["run_walk", "continuous"]),
            ("speed_beginner", "speed", "Speed Beginner", ["brand_new", "run_walk"]),
            ("speed_intermediate", "speed", "Speed Intermediate", ["run_walk", "continuous"]),
            ("hybrid", "hybrid", "Hybrid", ["brand_new", "run_walk", "continuous"])
        ]

        for miles in distances {
            for spec in styles {
                let duration = durationWeeks(targetMiles: miles, style: spec.style)
                let titleMiles = miles == floor(miles) ? String(Int(miles)) : String(format: "%.1f", miles)
                let id = "\(Int(miles))mi_\(spec.style)"
                output.append(
                    RunPlanTemplateDescriptor(
                        id: id,
                        name: "\(titleMiles) Mile \(spec.label)",
                        style: spec.style,
                        targetDistanceMiles: miles,
                        primaryGoal: spec.goal,
                        durationWeeks: duration,
                        recommendedAbilityLevels: spec.ability
                    )
                )
            }
        }

        return output
    }()

    static func durationWeeks(targetMiles: Double, style: String) -> Int {
        if targetMiles <= 1.0 {
            if style.hasPrefix("speed") { return 7 }
            return 6
        }
        if targetMiles <= 2.0 {
            if style.hasPrefix("speed") { return 9 }
            return 8
        }

        if style == "hybrid" { return 11 }
        if style.hasPrefix("speed") { return 12 }
        return 10
    }

    static func template(id: String) -> RunPlanTemplateDescriptor? {
        allTemplates.first { $0.id == id }
    }
}
