#if canImport(FoundationModels)
import Foundation
import FoundationModels

@Generable
enum DayType: String, Codable, Equatable {
    case strengthUpper
    case strengthLower
    case fullBodyStrength
    case runEasy
    case runTempo
    case runIntervals
    case longRun
    case cyclingEndurance
    case rowing
    case swimming
    case activeRecovery
    case rest
}

@Generable
struct WorkoutPlan: Codable, Equatable {
    @Guide(description: "A concise, motivating title for the training plan.")
    let title: String

    @Guide(description: "One-paragraph overview of the plan focus and approach.")
    let overview: String

    @Guide(description: "The unit for weights and distances, e.g. 'lbs' or 'kg'.")
    let unit: String

    @Guide(
        description: "One week of training with 7 days. IMPORTANT: Generate exactly 1 week with 7 days.",
        .count(1)
    )
    let weeks: [Week]

    @Guide(description: "Short guidance on nutrition, recovery, and progression.")
    let guidance: String
}

@Generable
struct Week: Codable, Equatable {
    @Guide(description: "Human-friendly label for the week, e.g. 'Week 1'.")
    let title: String

    @Guide(description: "Seven day plan for this week.", .count(7))
    let days: [Day]
}

@Generable
struct Day: Codable, Equatable {
    @Guide(description: "Day of week or a friendly label, e.g. 'Mon' or 'Strength: Upper'.")
    let title: String

    @Guide(description: "Structured type for the day. One of: strengthUpper, strengthLower, fullBodyStrength, runEasy, runTempo, runIntervals, longRun, cyclingEndurance, rowing, swimming, activeRecovery, rest")
    let type: DayType

    @Guide(description: "List of exercises or activities with sets/reps and optional weight suggestions.")
    let items: [Item]
}

@Generable
struct Item: Codable, Equatable {
    @Guide(description: "Exercise or activity name, e.g. 'Barbell Bench Press'.")
    let name: String

    @Guide(description: "How many sets should be performed.")
    let sets: Int?

    @Guide(description: "How many reps per set, if applicable.")
    let reps: Int?

    @Guide(description: "An optional suggested working weight with unit, e.g. '185 lbs'.")
    let suggestedWeight: String?

    @Guide(description: "Brief technique cue or form reminder to display inline with the exercise, e.g. 'Keep elbows tucked' or 'Control the descent'. Should be concise and directly describe HOW to perform this specific exercise correctly.")
    let notes: String?

    // Optional cardio structure
    @Guide(description: "Distance value, if cardio.")
    let distance: Double?
    @Guide(description: "Distance unit: 'mi' or 'km', if cardio.")
    let distanceUnit: String?
    @Guide(description: "Pace string, e.g. '9:30 per mi', if running.")
    let pace: String?
    @Guide(description: "Duration in minutes, if cardio.")
    let durationMinutes: Int?
    @Guide(description: "Effort guidance, e.g. 'RPE 6' or 'Zone 2'.")
    let effort: String?
}

@Generable
struct CoachAnswer: Codable, Equatable {
    @Guide(description: "Direct answer for the user's question. Keep it concise and practical.")
    let answer: String
}

#endif
