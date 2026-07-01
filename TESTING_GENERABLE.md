# Testing @Generable Guided Generation

## 🧪 What Was Changed

This document tracks the temporary changes made to test `@Generable` + `@Guide` structured generation instead of Markdown/JSON prompts.

## 📝 Changes Made

### 1. **AIPromptBuilder.swift** - Simplified Prompt
- **Location**: Lines 73-182
- **What**: Commented out all Markdown formatting instructions and detailed rules
- **Replaced with**: Simple, concise prompt relying on `@Guide` descriptions in the schema
- **New prompt structure**:
  ```swift
  "Create a 1-week training plan."
  "Goal: {goal} | Units: {weightUnit}, {distanceUnit}"
  "Context: {context}"
  // User stats (exercises, baselines, pace)
  // Key guidance (beginner vs experienced)
  ```

### 2. **WorkoutPlanGenerator.swift** - Enabled Guided Generation
- **Location**: Lines 485-496, 628-655
- **What**: Switched from `session.respond(to: prompt)` to `session.generate(WorkoutPlan.self)`
- **Key change**:
  ```swift
  // OLD: Free-form text response
  let response = try await session.respond(to: prompt)
  
  // NEW: Structured guided generation
  let workoutPlan = try await session.generate(WorkoutPlan.self) { stream in
      try await stream.append(prompt: Self.clampPrompt(prompt))
  }
  let markdown = Self.formatMarkdown(from: workoutPlan, ...)
  ```

### 3. **WorkoutPlanGenerator.swift** - Commented Out JSON Schema
- **Location**: Lines 952-1025
- **What**: Disabled the manual JSON schema prompt approach
- **Why**: Testing pure `@Generable` approach without any JSON hints

## 🎯 How It Works Now

### The Schema (`PlanSchema.swift`)
The AI uses these `@Generable` structures with `@Guide` descriptions:

```swift
@Generable
struct WorkoutPlan: Codable, Equatable {
    @Guide(description: "A concise, motivating title for the 4-week plan.")
    let title: String
    
    @Guide(description: "One-paragraph overview of the plan focus and approach.")
    let overview: String
    
    @Guide(description: "The unit for weights and distances, e.g. 'lbs' or 'kg'.")
    let unit: String
    
    @Guide(description: "Four weeks of training.")
    let weeks: [Week]
    
    @Guide(description: "Short guidance on nutrition, recovery, and progression.")
    let guidance: String
}

@Generable
struct Week: Codable, Equatable {
    @Guide(description: "Human-friendly label for the week, e.g. 'Week 1'.")
    let title: String
    
    @Guide(description: "Seven day plan for this week.")
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
    
    @Guide(description: "Any short note or intensity guidance.")
    let notes: String?
    
    // Cardio fields
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
```

### The Generation Flow

1. **User requests plan** → AI Planner View
2. **Build simple prompt** → AIPromptBuilder (no formatting rules, just context)
3. **Call guided generation** → `session.generate(WorkoutPlan.self)`
4. **Model reads @Guide descriptions** → Understands schema structure
5. **Returns structured WorkoutPlan** → Type-safe Swift object
6. **Convert to Markdown** → `formatMarkdown(from: workoutPlan)`
7. **Stream to UI** → Display in conversation sheet

## 🔍 What to Test

### Success Criteria
- ✅ Model generates valid `WorkoutPlan` structure
- ✅ All required fields are populated
- ✅ Days have appropriate `DayType` enum values
- ✅ Strength days have 4-6 exercises
- ✅ Cardio items have distance/pace/duration
- ✅ Weights are numeric (not percentages)
- ✅ Plan respects user's experience level

### Potential Issues
- ⚠️ Model might hang (previous issue with nested schemas)
- ⚠️ Model might not follow `@Guide` descriptions precisely
- ⚠️ Optional fields might be inconsistently populated
- ⚠️ Enum values might not match `DayType` cases
- ⚠️ Performance might be slower than Markdown approach

## 📊 Comparison

### Before (Markdown + Detailed Prompts)
- **Approach**: Detailed formatting instructions in prompt
- **Output**: Free-form Markdown text
- **Parsing**: Direct display (no parsing needed)
- **Flexibility**: Model can deviate from format
- **Reliability**: Generally works but format varies

### After (@Generable + @Guide)
- **Approach**: Schema-driven with minimal prompt
- **Output**: Structured `WorkoutPlan` object
- **Parsing**: Type-safe Swift structs
- **Flexibility**: Model constrained to schema
- **Reliability**: Either works perfectly or fails completely

## 🔄 How to Revert

If testing shows this approach doesn't work well:

1. **Uncomment** the Markdown instructions in `AIPromptBuilder.swift` (lines 74-157)
2. **Comment out** the new simple prompt (lines 159-182)
3. **Revert** `WorkoutPlanGenerator.swift` to use `session.respond(to:)` instead of `session.generate(_:)`
4. **Uncomment** JSON schema approach if needed (lines 954-1023)

## 📝 Notes

- Previous attempt noted this was "too complex and unreliable" (line 485 comment)
- The nested schema (4 levels: Plan → Week → Day → Item) was causing hangs
- Current test uses same schema but with simplified prompt
- Foundation Models framework should handle the schema natively via `@Generable`

## 🎯 Expected Behavior

When working correctly, you should see in console:
```
🎯 TESTING: Using @Generable guided generation with WorkoutPlan schema
Prompt: Create a 1-week training plan...
✅ Guided generation completed, converting to Markdown...
✅ Markdown formatted, length: 1234
```

The UI will display structured workout plan in Markdown format, converted from the `WorkoutPlan` object.

