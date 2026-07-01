import Foundation

/// Centralized prompt construction for AI fitness coaching
/// Keeps prompts concise to avoid context window overflow
enum AIPromptBuilder {
    static let maxPromptChars = 3500
    
    // MARK: - Core Instructions
    
    static func baseCoachInstructions() -> String {
        "You are a concise fitness/nutrition coach. Provide practical, varied guidance. Tailor advice to the listed equipment and prefer exercises from the user's library. Keep responses actionable."
    }
    
    // MARK: - Conversation Prompts
    
    static func buildConversationPrompt(
        goal: String,
        question: String,
        weightUnit: String,
        distanceUnit: String,
        userStats: WorkoutPlanGenerator.UserStats,
        equipment: String? = nil,
        conversationContext: String? = nil
    ) -> String {
        var lines: [String] = []
        
        lines.append(baseCoachInstructions())
        lines.append("Goal: \(goal) | Units: \(weightUnit), \(distanceUnit)")
        lines.append("")

        // Equipment (single line)
        if let eq = equipment?.trimmingCharacters(in: .whitespacesAndNewlines), !eq.isEmpty {
            lines.append("Equipment: \(eq)")
        }

        // User stats summary (compact for Ask mode)
        lines.append(contentsOf: formatUserStats(userStats, compact: true))
        lines.append("Nutrition math rule: if using g/kg and body weight is in lb, convert lb ÷ 2.20462 first. Never treat lb as kg.")
        if let base = userStats.typicalRunDistance {
            lines.append("Typical run distance: \(String(format: "%.1f", base)) \(distanceUnit)")
        }
        if let longTarget = userStats.suggestedLongRunDistance {
            lines.append("Long run target this week: ~\(String(format: "%.1f", longTarget)) \(distanceUnit)")
        }
        lines.append("For strength suggestions: list 5–6 distinct exercises with 'sets x reps @ weight \(weightUnit)'. Use last working weight when available; otherwise use conservative e1RM-derived loads. Round to \(weightUnit == "kg" ? "2.5 kg" : "5 lb") and keep first-week increases ≤5%.")
        if let conversationContext, !conversationContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Conversation context:")
            lines.append(conversationContext)
            lines.append("Stay consistent with that prior context. Avoid repeating the entire history unless it changes the answer.")
        }
        
        lines.append("\nQuestion: \(question)")
        
        return clamp(lines.joined(separator: "\n"))
    }
    
    // MARK: - Plan Generation Prompts
    
    static func buildPlanPrompt(
        goal: String,
        context: String,
        weightUnit: String,
        distanceUnit: String,
        userStats: WorkoutPlanGenerator.UserStats
    ) -> String {
        var lines: [String] = []
        
        // TEMPORARILY COMMENTED OUT: Testing @Generable guided generation instead of Markdown
        /*
        lines.append("Generate a creative 1-week training plan in Markdown.")
        lines.append("Goal: \(goal) | Units: \(weightUnit), \(distanceUnit)")
        if !context.isEmpty { lines.append("Notes: \(context)") }
        lines.append("")
        
        // User stats
        lines.append(contentsOf: formatUserStats(userStats))
        
        // Format guidelines
        lines.append("")
        lines.append("## FORMAT:")
        lines.append("- Heading: '## This Week's Training Plan'")
        lines.append("- Days: 'Day 1:' through 'Day 7:' — Title each day as 'Day N: [Type]' where [Type] is one of: Strength Upper, Strength Lower, Full Body Strength, Run Easy, Run Tempo, Run Intervals, Long Run, Cycling Endurance, Rowing, Swimming, Active Recovery, Rest")
        lines.append("- Strength Items: **Exercise** — sets x reps @ weight (e.g., **Bench Press** — 4x6 @ 185 \(weightUnit))")
        lines.append("- Strength days: include 4–6 total exercises. Aim for 2–3 compound lifts (e.g., squat/deadlift/press/row), 2–3 accessories (e.g., lunges, flyes, lateral raises, curls/extensions), and (optionally) 1 core/finisher.")
        
        // Running format with user's actual pace
        if let avgPace = userStats.avgRecentPace {
            lines.append("- Running: 'Run: X.X \(distanceUnit) — pace mm:ss per \(distanceUnit) using baseline \(avgPace), adjusted for easy/moderate/tempo/interval/long; include total time computed from distance x pace'")
        } else {
            lines.append("- Running: 'Run: X.X \(distanceUnit) at easy/moderate pace'")
        }
        
        lines.append("- Rest days: If a day is rest, the section should be exactly 'Rest Day' or 'Active Recovery'. Do NOT add a 'Rest' line to a training day. Include 1–2 rest/recovery days in the week as appropriate.")
        lines.append("")
        lines.append("VARIETY: Mix rep schemes (3x5, 4x8, 3x10), intensities, and exercises")
        lines.append("WEIGHTS: Compute and show numeric working weights in the user's unit using e1RM and recent performance. Output numbers (e.g., 3x5 @ 185), not % of e1RM. If no baseline exists, suggest a conservative start and a small progression.")
        
        // Cycling guidance distinct from running
        lines.append("CYCLING: Express as duration + effort (RPE or HR zone). If adding numbers, use a speed range (e.g., 12–16 mph or 20–26 km/h). Do NOT use running-style pace (mm:ss per unit), and avoid unrealistic values like '200:30'.")
        
        // Running pace guidance
        if let avgPace = userStats.avgRecentPace {
            lines.append("")
            lines.append("RUNNING PACE: User's recent average is \(avgPace). Use this as baseline. For each run, include an explicit pace target (mm:ss per \(distanceUnit)):")
            lines.append("- Easy: +30–60s per \(distanceUnit) slower than baseline")
            lines.append("- Moderate: at or near baseline")
            lines.append("- Tempo: −10–25s per \(distanceUnit) faster than baseline")
            lines.append("- Intervals: −20–60s per \(distanceUnit) faster than baseline")
            lines.append("- Long run: baseline to +20s per \(distanceUnit)")
            lines.append("If you include total time, compute it from distance × target pace and keep it consistent with the pace you provide. Avoid unrealistic times.")
        }

        // Exercise selection guidance
        lines.append("")
        lines.append("EXERCISE SELECTION: Use only exercises from the user's library list below when suggesting workouts. You may choose any of them, not just ones with past logs.")
        
        // Cardio variety across the week
        lines.append("")
        lines.append("CARDIO VARIETY: Rotate modalities to target different muscles and limit overuse. Mix running, cycling, rowing, swimming, stair climbing, jump rope, brisk hiking. Include at least 2 different cardio types during the week. Provide duration + effort guidance (RPE 3–8 or HR zones). For non-running cardio, avoid mm:ss pace; prefer speed ranges (mph/km/h), cadence, or stroke rate.")

        // Experience-based guidance
        lines.append("")
        if userStats.experienceLevel == "beginner" {
            lines.append("BEGINNER GUIDANCE:")
            lines.append("- User is NEW TO WORKING OUT. Prioritize form, safety, and building confidence.")
            lines.append("- Choose BEGINNER-FRIENDLY exercises: machines, bodyweight, dumbbells. Avoid complex barbell movements initially.")
            lines.append("- Prefer exercises like: Push-Ups, Goblet Squats, Dumbbell Press, Lat Pulldowns, Leg Press, Machine exercises.")
            lines.append("- Start with LOWER weights (40-60% estimated capacity), MODERATE volume (2-3 sets), and HIGHER reps (10-15).")
            lines.append("- Include REST days and focus on RECOVERY. Suggest 3-4 training days per week.")
            lines.append("- For cardio: walking, light jogging, stationary bike, swimming. Keep intensity LOW to MODERATE (RPE 3-6).")
        } else {
            lines.append("EXPERIENCED GUIDANCE:")
            lines.append("- User is EXPERIENCED. You can suggest any beneficial workout including advanced techniques.")
            lines.append("- Use a full range of exercises: compound barbell lifts, Olympic variations, advanced techniques.")
            lines.append("- Vary intensity: include heavy (3-5 reps), moderate (6-8 reps), and volume (10-15 reps) work.")
            lines.append("- Can handle 4-6 training days per week with proper periodization.")
            lines.append("- For cardio: can include tempo runs, intervals, hill work, and longer endurance sessions.")
        }
        
        // STRICT OUTPUT RULES
        lines.append("")
        lines.append("STRICT RULES:")
        lines.append("- Strength days: include 4–6 exercises total. Aim 2–3 compound lifts + 2–3 accessories + optional 1 core/finisher.")
        lines.append("- Sets/Reps: provide specific sets and reps for each exercise.")
        lines.append("- Weights: output numeric working weights in \(weightUnit). Do NOT write '% of 1RM'. If no baseline, give a conservative numeric start.")
        lines.append("- Running: include distance (\(distanceUnit)), pace as mm:ss per \(distanceUnit), and total time = distance × pace. Keep time consistent.")
        lines.append("- Other cardio: include duration and effort; if numbers are given, use speed ranges (mph/km/h). Do not present mm:ss pace for non-running cardio.")
        
        */
        
        // TESTING: Simple prompt for @Generable guided generation
        lines.append("Create a 1-week training plan.")
        lines.append("Goal: \(goal) | Units: \(weightUnit), \(distanceUnit)")
        if !context.isEmpty { lines.append("Context: \(context)") }
        
        // User stats (full for Plan mode)
        lines.append(contentsOf: formatUserStats(userStats, compact: false))
        if let base = userStats.typicalRunDistance {
            lines.append("Typical run distance: \(String(format: "%.1f", base)) \(distanceUnit)")
        }
        if let longTarget = userStats.suggestedLongRunDistance {
            lines.append("Suggested long run this week: ~\(String(format: "%.1f", longTarget)) \(distanceUnit)")
        }
        
        // Key guidance for structured generation
        lines.append("")
        if userStats.experienceLevel == "beginner" {
            lines.append("User is NEW to working out. Choose beginner-friendly exercises (machines, bodyweight, dumbbells). Start with lower weights, 2-3 sets, 10-15 reps. Include rest days.")
        } else {
            lines.append("User is EXPERIENCED. Include compound lifts, varied rep schemes, and 4-6 training days.")
        }
        
        lines.append("Strength days: 5–6 exercises (2–3 compound + 2–3 accessories). All exercises per day must be distinct (no duplicates).")
        lines.append("Use exercises from the user's library when possible. Include 1–2 rest/recovery days.")
        lines.append("For EACH strength item, include 'sets x reps @ weight \(weightUnit)'.")
        lines.append("Weights: Base values on the Exercise baselines listed below. Prefer the last working weight for that rep range; if unavailable, derive from e1RM conservatively and round to \(weightUnit == "kg" ? "2.5 kg" : "5 lb").")
        lines.append("Progression: keep first-week increases small (≤5% above last working weight) and never exceed e1RM. Avoid unrealistic numbers.")
        
        if let avgPace = userStats.avgRecentPace { lines.append("Running baseline: \(avgPace). Use this to set easy/tempo/interval/long run paces.") }
        if let base = userStats.typicalRunDistance {
            let incrUnit = distanceUnit.lowercased().contains("km") ? "km" : "mi"
            let baseStr = String(format: "%.1f", base)
            lines.append("Use \(baseStr) \(distanceUnit) for easy runs; set long run ~10–15% above that. Round run distances to 0.5 \(incrUnit) increments.")
        }
        
        return clamp(lines.joined(separator: "\n"))
    }

    static func buildOpenRouterStructuredPlanPrompt(
        goal: String,
        context: String,
        weightUnit: String,
        distanceUnit: String,
        userStats: WorkoutPlanGenerator.UserStats
    ) -> String {
        var lines: [String] = []
        lines.append(buildPlanPrompt(
            goal: goal,
            context: context,
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            userStats: userStats
        ))
        lines.append("")
        lines.append("Return ONLY valid JSON with this exact structure:")
        lines.append("""
        {
          "title": "string",
          "overview": "string",
          "unit": "\(weightUnit)",
          "weeks": [
            {
              "title": "Week 1",
              "days": [
                {
                  "title": "string",
                  "type": "strengthUpper | strengthLower | fullBodyStrength | runEasy | runTempo | runIntervals | longRun | cyclingEndurance | rowing | swimming | activeRecovery | rest",
                  "items": [
                    {
                      "name": "string",
                      "sets": 3,
                      "reps": 8,
                      "suggestedWeight": "135 \(weightUnit)",
                      "notes": "short technique cue",
                      "distance": null,
                      "distanceUnit": null,
                      "pace": null,
                      "durationMinutes": null,
                      "effort": null
                    }
                  ]
                }
              ]
            }
          ],
          "guidance": "string"
        }
        """)
        lines.append("Rules:")
        lines.append("- Include exactly 1 week and exactly 7 days.")
        lines.append("- Rest and active recovery days should have an empty items array.")
        lines.append("- Strength items should use sets/reps and suggestedWeight fields.")
        lines.append("- Running items should use distance, distanceUnit, pace, durationMinutes, and effort when relevant.")
        lines.append("- Non-running cardio should avoid running pace math and can use durationMinutes plus effort.")
        lines.append("- Use null for fields that do not apply.")
        lines.append("- Do not include Markdown fences or commentary.")
        return clamp(lines.joined(separator: "\n"))
    }
    
    // MARK: - Helper Methods
    
    private static func formatUserStats(_ stats: WorkoutPlanGenerator.UserStats, compact: Bool) -> [String] {
        var lines: [String] = []
        
        // Experience level
        lines.append("Experience Level: \(stats.experienceLevel == "beginner" ? "New to Working Out (Beginner)" : "Experienced")")
        
        if let weight = stats.latestWeight {
            let weightLine: String
            if stats.weightUnit.lowercased() == "lbs" {
                let kg = convertWeight(weight, from: "lbs", to: "kg")
                weightLine = "Weight: \(String(format: "%.1f", weight)) lbs (\(String(format: "%.1f", kg)) kg)"
            } else if stats.weightUnit.lowercased() == "kg" {
                let lbs = convertWeight(weight, from: "kg", to: "lbs")
                weightLine = "Weight: \(String(format: "%.1f", weight)) kg (\(String(format: "%.1f", lbs)) lbs)"
            } else {
                weightLine = "Weight: \(String(format: "%.1f", weight)) \(stats.weightUnit)"
            }
            lines.append(weightLine)
        }
        
        if compact {
            // Minimal cardio summary
            if let pace = stats.avgRecentPace { lines.append("Avg running pace (recent): \(pace)") }
            if stats.runSessions > 0 {
                lines.append("Runs last 14d: \(stats.runSessions), distance: \(String(format: "%.1f", stats.totalDistance)) \(stats.distanceUnit)")
            }
            return lines
        }
        
        // Full details for plan mode
        if let steps = stats.todaySteps, steps > 0 {
            lines.append("Today's steps: \(steps)")
        }
        if stats.workoutSessions > 0 {
            lines.append("Recent training (14d): \(stats.workoutSessions) sessions")
            if stats.totalLifted > 0 {
                lines.append("Volume: \(String(format: "%.0f", stats.totalLifted)) \(stats.weightUnit)")
            }
        }
        if stats.weeklyRunSessions > 0 || stats.runSessions > 0 || stats.recentHealthKitRuns > 0 {
            let weekStr = "This week: \(stats.weeklyRunSessions) runs, \(String(format: "%.1f", stats.weeklyDistance)) \(stats.distanceUnit)"
            lines.append("Cardio — \(weekStr)")
            let last14 = "Last 14d: \(stats.runSessions) runs, \(String(format: "%.1f", stats.totalDistance)) \(stats.distanceUnit)"
            lines.append(last14)
            if stats.recentHealthKitRuns > 0 { lines.append("Imported HealthKit runs (14d): \(stats.recentHealthKitRuns)") }
            if let pace = stats.avgRecentPace { lines.append("Avg pace (recent): \(pace)") }
        }
        if !stats.exerciseLibrary.isEmpty {
            lines.append("\nAvailable exercises (library):")
            for name in stats.exerciseLibrary.prefix(30) { lines.append("- \(name)") }
        }
        if !stats.exerciseBaselines.isEmpty {
            lines.append("\nExercise baselines (recent performance):")
            for baseline in stats.exerciseBaselines.prefix(5) {
                let recent = baseline.lastByReps.sorted { $0.key < $1.key }
                    .map { "\($0.key)x@\(Int($0.value))" }
                    .prefix(3)
                    .joined(separator: ", ")
                lines.append("- \(baseline.name): e1RM ~\(Int(baseline.e1rm)) \(stats.weightUnit) (\(recent))")
            }
        }
        return lines
    }

    
    
    private static func clamp(_ text: String) -> String {
        text.count <= maxPromptChars ? text : String(text.prefix(maxPromptChars))
    }

    private static func convertWeight(_ value: Double, from: String, to: String) -> Double {
        if from == to { return value }
        if from == "kg" && to == "lbs" { return value * 2.20462 }
        if from == "lbs" && to == "kg" { return value / 2.20462 }
        return value
    }
}
