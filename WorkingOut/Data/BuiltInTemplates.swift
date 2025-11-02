import Foundation

// MARK: - Built-In Workout Template Library
// Research-based workout templates organized by experience level and goal

struct BuiltInTemplateData {
    let title: String
    let description: String
    let experienceLevel: String
    let goal: String
    let difficulty: Int
    let estimatedDuration: Int
    let equipment: [String]
    let muscleGroups: [String]
    let exercises: [ExerciseData]
    
    struct ExerciseData {
        let name: String
        let sets: Int
        let reps: Int
        let suggestedWeight: Double?
        let weightUnit: String
        let notes: String?
        let order: Int
    }
}

// MARK: - Template Library
class BuiltInTemplateLibrary {
    
    // MARK: - BEGINNER LEVEL
    
    // GOAL: Full Body Foundation
    static let beginnerFullBody: [BuiltInTemplateData] = [
        // Template 1: Starting Strength A (Based on Mark Rippetoe's Starting Strength)
        BuiltInTemplateData(
            title: "Beginner Barbell Basics A - Squat, Bench, Deadlift",
            description: "Classic beginner barbell program focusing on the main compound lifts. Perfect for building foundational strength.",
            experienceLevel: "beginner",
            goal: "full_body_foundation",
            difficulty: 2,
            estimatedDuration: 45,
            equipment: ["barbell", "squat_rack", "bench"],
            muscleGroups: ["legs", "chest", "back", "core"],
            exercises: [
                .init(name: "Back Squat", sets: 3, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Focus on depth and form", order: 0),
                .init(name: "Bench Press", sets: 3, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Lower to chest, pause, press", order: 1),
                .init(name: "Deadlift", sets: 1, reps: 5, suggestedWeight: 95, weightUnit: "lbs", notes: "One heavy set, focus on form", order: 2),
                .init(name: "Plank", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold for 30 seconds", order: 3)
            ]
        ),
        
        // Template 2: Starting Strength B
        BuiltInTemplateData(
            title: "Beginner Barbell Basics B - Squat, Press, Clean",
            description: "Alternate day for Starting Strength program. Focuses on overhead press and pulls.",
            experienceLevel: "beginner",
            goal: "full_body_foundation",
            difficulty: 2,
            estimatedDuration: 45,
            equipment: ["barbell", "squat_rack", "pull_up_bar"],
            muscleGroups: ["legs", "shoulders", "back", "arms"],
            exercises: [
                .init(name: "Back Squat", sets: 3, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Same as Day A", order: 0),
                .init(name: "Overhead Press", sets: 3, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Press from chest to lockout", order: 1),
                .init(name: "Power Clean", sets: 5, reps: 3, suggestedWeight: 45, weightUnit: "lbs", notes: "Explosive from floor to shoulders", order: 2),
                .init(name: "Chin-Ups", sets: 3, reps: 5, suggestedWeight: nil, weightUnit: "lbs", notes: "Use assistance if needed", order: 3)
            ]
        ),
        
        // Template 3: StrongLifts 5x5 A (Based on Mehdi's StrongLifts)
        BuiltInTemplateData(
            title: "Beginner 5x5 Program A - Squat, Bench, Row",
            description: "Simple and effective 5x5 program. Three exercises, five sets each. Linear progression.",
            experienceLevel: "beginner",
            goal: "full_body_foundation",
            difficulty: 2,
            estimatedDuration: 50,
            equipment: ["barbell", "squat_rack", "bench"],
            muscleGroups: ["legs", "chest", "back"],
            exercises: [
                .init(name: "Back Squat", sets: 5, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Add 5 lbs each workout", order: 0),
                .init(name: "Bench Press", sets: 5, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Add 5 lbs each workout", order: 1),
                .init(name: "Barbell Row", sets: 5, reps: 5, suggestedWeight: 65, weightUnit: "lbs", notes: "Pull to lower chest", order: 2)
            ]
        ),
        
        // Template 4: StrongLifts 5x5 B
        BuiltInTemplateData(
            title: "Beginner 5x5 Program B - Squat, Press, Deadlift",
            description: "Alternate workout for StrongLifts. Overhead press and deadlifts.",
            experienceLevel: "beginner",
            goal: "full_body_foundation",
            difficulty: 2,
            estimatedDuration: 50,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs", "shoulders", "back"],
            exercises: [
                .init(name: "Back Squat", sets: 5, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Add 5 lbs each workout", order: 0),
                .init(name: "Overhead Press", sets: 5, reps: 5, suggestedWeight: 45, weightUnit: "lbs", notes: "Add 2.5 lbs each workout", order: 1),
                .init(name: "Deadlift", sets: 1, reps: 5, suggestedWeight: 95, weightUnit: "lbs", notes: "Add 10 lbs each workout", order: 2)
            ]
        ),
        
        // Template 5: Dumbbell Full Body
        BuiltInTemplateData(
            title: "Beginner Dumbbell Full Body",
            description: "Complete workout using only dumbbells. Great for home gyms or beginners.",
            experienceLevel: "beginner",
            goal: "full_body_foundation",
            difficulty: 1,
            estimatedDuration: 40,
            equipment: ["dumbbells", "bench"],
            muscleGroups: ["legs", "chest", "back", "shoulders", "arms"],
            exercises: [
                .init(name: "Goblet Squat", sets: 3, reps: 12, suggestedWeight: 25, weightUnit: "lbs", notes: "Hold dumbbell at chest", order: 0),
                .init(name: "Dumbbell Bench Press", sets: 3, reps: 10, suggestedWeight: 20, weightUnit: "lbs", notes: "Each hand", order: 1),
                .init(name: "Dumbbell Row", sets: 3, reps: 10, suggestedWeight: 25, weightUnit: "lbs", notes: "Each arm", order: 2),
                .init(name: "Dumbbell Shoulder Press", sets: 3, reps: 10, suggestedWeight: 15, weightUnit: "lbs", notes: "Each hand", order: 3),
                .init(name: "Romanian Deadlift", sets: 3, reps: 12, suggestedWeight: 30, weightUnit: "lbs", notes: "Hinge at hips", order: 4),
                .init(name: "Plank", sets: 3, reps: 45, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold for 45 seconds", order: 5)
            ]
        )
    ]
    
    // GOAL: Weight Loss Starter
    static let beginnerWeightLoss: [BuiltInTemplateData] = [
        // Template 1: HIIT Basics
        BuiltInTemplateData(
            title: "Beginner HIIT Cardio for Fat Loss",
            description: "High-intensity interval training for beginners. Burns calories, improves cardiovascular fitness.",
            experienceLevel: "beginner",
            goal: "weight_loss",
            difficulty: 2,
            estimatedDuration: 30,
            equipment: ["bodyweight", "dumbbells"],
            muscleGroups: ["full_body", "cardio"],
            exercises: [
                .init(name: "Jumping Jacks", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "30 seconds on, 30 seconds rest", order: 0),
                .init(name: "Bodyweight Squat", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Controlled tempo", order: 1),
                .init(name: "Push-ups", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Knees okay if needed", order: 2),
                .init(name: "Mountain Climbers", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Alternating legs", order: 3),
                .init(name: "Dumbbell Thrusters", sets: 3, reps: 12, suggestedWeight: 10, weightUnit: "lbs", notes: "Squat to press", order: 4),
                .init(name: "High Knees", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "30 seconds", order: 5)
            ]
        ),
        
        // Template 2: Metabolic Circuit
        BuiltInTemplateData(
            title: "Beginner Fat Burning Circuit",
            description: "Circuit training to boost metabolism. Minimal rest between exercises.",
            experienceLevel: "beginner",
            goal: "weight_loss",
            difficulty: 2,
            estimatedDuration: 35,
            equipment: ["dumbbells", "kettlebell"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Kettlebell Swing", sets: 4, reps: 15, suggestedWeight: 20, weightUnit: "lbs", notes: "Hip hinge power", order: 0),
                .init(name: "Dumbbell Squat to Press", sets: 3, reps: 12, suggestedWeight: 12, weightUnit: "lbs", notes: "Combine movements", order: 1),
                .init(name: "Burpees", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Full range of motion", order: 2),
                .init(name: "Dumbbell Renegade Row", sets: 3, reps: 8, suggestedWeight: 15, weightUnit: "lbs", notes: "Plank position, row each arm", order: 3),
                .init(name: "Jump Squats", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Explosive", order: 4),
                .init(name: "Bicycle Crunches", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "Alternating", order: 5)
            ]
        ),
        
        // Template 3: Cardio Strength Mix
        BuiltInTemplateData(
            title: "Beginner Cardio & Strength Mix",
            description: "Mix of cardio bursts and strength exercises. Great for calorie burn and muscle building.",
            experienceLevel: "beginner",
            goal: "weight_loss",
            difficulty: 2,
            estimatedDuration: 40,
            equipment: ["dumbbells", "bodyweight"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Jog in Place", sets: 3, reps: 60, suggestedWeight: nil, weightUnit: "lbs", notes: "1 minute warm-up", order: 0),
                .init(name: "Dumbbell Goblet Squat", sets: 3, reps: 15, suggestedWeight: 25, weightUnit: "lbs", notes: "Deep squats", order: 1),
                .init(name: "High Knees", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "30 seconds max effort", order: 2),
                .init(name: "Push-ups", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Modify as needed", order: 3),
                .init(name: "Jumping Jacks", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "30 seconds", order: 4),
                .init(name: "Dumbbell Lunges", sets: 3, reps: 20, suggestedWeight: 15, weightUnit: "lbs", notes: "10 each leg", order: 5),
                .init(name: "Plank", sets: 3, reps: 45, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold 45 seconds", order: 6)
            ]
        ),
        
        // Template 4: Bodyweight Fat Burner
        BuiltInTemplateData(
            title: "Beginner Bodyweight Fat Burner - No Equipment",
            description: "Effective fat-burning workout requiring no equipment. Do anywhere, anytime.",
            experienceLevel: "beginner",
            goal: "weight_loss",
            difficulty: 1,
            estimatedDuration: 25,
            equipment: ["bodyweight"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Burpees", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Step back if needed", order: 0),
                .init(name: "Bodyweight Squat", sets: 4, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Full depth", order: 1),
                .init(name: "Mountain Climbers", sets: 4, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "Fast pace", order: 2),
                .init(name: "Lunge Jumps", sets: 3, reps: 16, suggestedWeight: nil, weightUnit: "lbs", notes: "8 each leg", order: 3),
                .init(name: "Push-ups", sets: 3, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Chest to ground", order: 4),
                .init(name: "Flutter Kicks", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "30 seconds", order: 5)
            ]
        ),
        
        // Template 5: Beginner Tabata
        BuiltInTemplateData(
            title: "Beginner Tabata Intervals - 20 Min Fat Burn",
            description: "4-minute Tabata intervals. 20 seconds work, 10 seconds rest. Maximum calorie burn.",
            experienceLevel: "beginner",
            goal: "weight_loss",
            difficulty: 3,
            estimatedDuration: 20,
            equipment: ["bodyweight"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Squat", sets: 8, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "20 sec on, 10 sec rest", order: 0),
                .init(name: "Push-ups", sets: 8, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "20 sec on, 10 sec rest", order: 1),
                .init(name: "High Knees", sets: 8, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "20 sec on, 10 sec rest", order: 2),
                .init(name: "Plank", sets: 8, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "20 sec on, 10 sec rest", order: 3)
            ]
        )
    ]
    
    // GOAL: Home Workout Basics
    static let beginnerHome: [BuiltInTemplateData] = [
        // Template 1: No Equipment Home Workout
        BuiltInTemplateData(
            title: "Beginner Bodyweight Home Workout",
            description: "Complete workout using only your body. No equipment needed.",
            experienceLevel: "beginner",
            goal: "home_workout",
            difficulty: 1,
            estimatedDuration: 30,
            equipment: ["bodyweight"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Air Squat", sets: 4, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Bodyweight only", order: 0),
                .init(name: "Push-ups", sets: 4, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Knees down if needed", order: 1),
                .init(name: "Reverse Lunge", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "10 each leg", order: 2),
                .init(name: "Pike Push-up", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Targets shoulders", order: 3),
                .init(name: "Glute Bridge", sets: 4, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Squeeze at top", order: 4),
                .init(name: "Plank", sets: 3, reps: 45, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold 45 seconds", order: 5)
            ]
        ),
        
        // Template 2: Resistance Band Total Body
        BuiltInTemplateData(
            title: "Beginner Resistance Band Full Body",
            description: "Full body workout using resistance bands. Portable and effective.",
            experienceLevel: "beginner",
            goal: "home_workout",
            difficulty: 1,
            estimatedDuration: 35,
            equipment: ["resistance_bands"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Band Squat", sets: 3, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Stand on band", order: 0),
                .init(name: "Band Chest Press", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Anchor behind you", order: 1),
                .init(name: "Band Row", sets: 3, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Pull to chest", order: 2),
                .init(name: "Band Shoulder Press", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Stand on band", order: 3),
                .init(name: "Band Deadlift", sets: 3, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Hip hinge", order: 4),
                .init(name: "Band Pull-Apart", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Rear delts", order: 5)
            ]
        ),
        
        // Template 3: Furniture Workout
        BuiltInTemplateData(
            title: "Beginner Chair & Couch Home Workout",
            description: "Creative workout using chairs, couches, and walls. Make your home your gym.",
            experienceLevel: "beginner",
            goal: "home_workout",
            difficulty: 1,
            estimatedDuration: 30,
            equipment: ["bodyweight", "chair"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Chair Dips", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Hands on chair", order: 0),
                .init(name: "Bulgarian Split Squat", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Back foot on chair, 10 each leg", order: 1),
                .init(name: "Incline Push-ups", sets: 3, reps: 15, suggestedWeight: nil, weightUnit: "lbs", notes: "Hands on chair", order: 2),
                .init(name: "Wall Sit", sets: 3, reps: 45, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold 45 seconds", order: 3),
                .init(name: "Step-ups", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "10 each leg", order: 4),
                .init(name: "Superman Hold", sets: 3, reps: 30, suggestedWeight: nil, weightUnit: "lbs", notes: "Hold 30 seconds", order: 5)
            ]
        ),
        
        // Template 4: Minimal Equipment Essential
        BuiltInTemplateData(
            title: "Beginner Single Pair Dumbbell Workout",
            description: "Only need one pair of dumbbells. Complete full body training.",
            experienceLevel: "beginner",
            goal: "home_workout",
            difficulty: 2,
            estimatedDuration: 40,
            equipment: ["dumbbells"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Goblet Squat", sets: 4, reps: 12, suggestedWeight: 25, weightUnit: "lbs", notes: "One dumbbell", order: 0),
                .init(name: "Dumbbell Floor Press", sets: 3, reps: 10, suggestedWeight: 20, weightUnit: "lbs", notes: "Lie on floor", order: 1),
                .init(name: "Single Arm Row", sets: 3, reps: 12, suggestedWeight: 25, weightUnit: "lbs", notes: "Each arm", order: 2),
                .init(name: "Dumbbell Shoulder Press", sets: 3, reps: 10, suggestedWeight: 15, weightUnit: "lbs", notes: "Standing or seated", order: 3),
                .init(name: "Dumbbell Romanian Deadlift", sets: 3, reps: 12, suggestedWeight: 30, weightUnit: "lbs", notes: "One or two DBs", order: 4),
                .init(name: "Plank", sets: 3, reps: 60, suggestedWeight: nil, weightUnit: "lbs", notes: "1 minute hold", order: 5)
            ]
        ),
        
        // Template 5: Apartment-Friendly Quiet Workout
        BuiltInTemplateData(
            title: "Beginner Quiet Apartment Workout - No Jumping",
            description: "Low-impact workout perfect for apartments. No jumping, no noise.",
            experienceLevel: "beginner",
            goal: "home_workout",
            difficulty: 1,
            estimatedDuration: 30,
            equipment: ["bodyweight", "dumbbells"],
            muscleGroups: ["full_body"],
            exercises: [
                .init(name: "Static Squat", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Controlled pace", order: 0),
                .init(name: "Wide Push-ups", sets: 3, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Hands wide", order: 1),
                .init(name: "Reverse Lunge", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Slow and controlled", order: 2),
                .init(name: "Plank Shoulder Tap", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "Alternate hands", order: 3),
                .init(name: "Glute Bridge Hold", sets: 3, reps: 45, suggestedWeight: nil, weightUnit: "lbs", notes: "45 second hold", order: 4),
                .init(name: "Bird Dog", sets: 3, reps: 20, suggestedWeight: nil, weightUnit: "lbs", notes: "10 each side", order: 5)
            ]
        )
    ]
    
    // MARK: - INTERMEDIATE LEVEL
    
    // GOAL: Muscle Building
    static let intermediateHypertrophy: [BuiltInTemplateData] = [
        // Template 1: Push Day (Based on Push/Pull/Legs split)
        BuiltInTemplateData(
            title: "Intermediate Push Day - Chest, Shoulders, Triceps",
            description: "Volume-focused push workout. Chest, shoulders, triceps. Classic PPL split.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 3,
            estimatedDuration: 60,
            equipment: ["barbell", "dumbbells", "cables", "bench"],
            muscleGroups: ["chest", "shoulders", "triceps"],
            exercises: [
                .init(name: "Barbell Bench Press", sets: 4, reps: 8, suggestedWeight: 135, weightUnit: "lbs", notes: "Progressive overload", order: 0),
                .init(name: "Incline Dumbbell Press", sets: 4, reps: 10, suggestedWeight: 50, weightUnit: "lbs", notes: "Upper chest", order: 1),
                .init(name: "Cable Chest Fly", sets: 3, reps: 12, suggestedWeight: 30, weightUnit: "lbs", notes: "Stretch and squeeze", order: 2),
                .init(name: "Overhead Press", sets: 4, reps: 8, suggestedWeight: 95, weightUnit: "lbs", notes: "Barbell or dumbbell", order: 3),
                .init(name: "Lateral Raise", sets: 3, reps: 15, suggestedWeight: 15, weightUnit: "lbs", notes: "Side delts", order: 4),
                .init(name: "Tricep Rope Pushdown", sets: 3, reps: 12, suggestedWeight: 50, weightUnit: "lbs", notes: "Full extension", order: 5),
                .init(name: "Overhead Tricep Extension", sets: 3, reps: 12, suggestedWeight: 40, weightUnit: "lbs", notes: "Stretch triceps", order: 6)
            ]
        ),
        
        // Template 2: Pull Day
        BuiltInTemplateData(
            title: "Intermediate Pull Day - Back & Biceps",
            description: "Complete back and bicep hypertrophy workout. Multiple angles for full development.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 3,
            estimatedDuration: 65,
            equipment: ["barbell", "dumbbells", "cables", "pull_up_bar"],
            muscleGroups: ["back", "biceps"],
            exercises: [
                .init(name: "Deadlift", sets: 4, reps: 6, suggestedWeight: 185, weightUnit: "lbs", notes: "Build total back", order: 0),
                .init(name: "Pull-ups", sets: 4, reps: 8, suggestedWeight: nil, weightUnit: "lbs", notes: "Add weight if possible", order: 1),
                .init(name: "Barbell Row", sets: 4, reps: 8, suggestedWeight: 115, weightUnit: "lbs", notes: "Bent over, pull to belly", order: 2),
                .init(name: "Dumbbell Row", sets: 3, reps: 10, suggestedWeight: 60, weightUnit: "lbs", notes: "Each arm", order: 3),
                .init(name: "Face Pull", sets: 4, reps: 15, suggestedWeight: 40, weightUnit: "lbs", notes: "Rear delts", order: 4),
                .init(name: "Barbell Curl", sets: 3, reps: 10, suggestedWeight: 60, weightUnit: "lbs", notes: "Strict form", order: 5),
                .init(name: "Hammer Curl", sets: 3, reps: 12, suggestedWeight: 30, weightUnit: "lbs", notes: "Neutral grip", order: 6)
            ]
        ),
        
        // Template 3: Leg Day
        BuiltInTemplateData(
            title: "Intermediate Leg Day - Quads, Glutes, Hamstrings",
            description: "High-volume leg workout emphasizing quads. Progressive overload on squats.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 4,
            estimatedDuration: 70,
            equipment: ["barbell", "leg_press", "machines"],
            muscleGroups: ["quads", "glutes", "hamstrings", "calves"],
            exercises: [
                .init(name: "Back Squat", sets: 5, reps: 8, suggestedWeight: 185, weightUnit: "lbs", notes: "Core lift, add weight weekly", order: 0),
                .init(name: "Romanian Deadlift", sets: 4, reps: 10, suggestedWeight: 135, weightUnit: "lbs", notes: "Hamstring stretch", order: 1),
                .init(name: "Leg Press", sets: 4, reps: 12, suggestedWeight: 270, weightUnit: "lbs", notes: "Full depth", order: 2),
                .init(name: "Walking Lunge", sets: 3, reps: 20, suggestedWeight: 30, weightUnit: "lbs", notes: "10 each leg", order: 3),
                .init(name: "Leg Curl", sets: 3, reps: 12, suggestedWeight: 80, weightUnit: "lbs", notes: "Hamstrings", order: 4),
                .init(name: "Leg Extension", sets: 3, reps: 15, suggestedWeight: 90, weightUnit: "lbs", notes: "Quad isolation", order: 5),
                .init(name: "Calf Raise", sets: 4, reps: 20, suggestedWeight: 135, weightUnit: "lbs", notes: "Full range", order: 6)
            ]
        ),
        
        // Template 4: Upper Body Power
        BuiltInTemplateData(
            title: "Intermediate Upper Body Power & Size",
            description: "Combined power and volume for upper body. Best of both worlds.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 3,
            estimatedDuration: 65,
            equipment: ["barbell", "dumbbells", "cables"],
            muscleGroups: ["chest", "back", "shoulders", "arms"],
            exercises: [
                .init(name: "Bench Press", sets: 5, reps: 5, suggestedWeight: 155, weightUnit: "lbs", notes: "Heavy, power movement", order: 0),
                .init(name: "Barbell Row", sets: 4, reps: 6, suggestedWeight: 135, weightUnit: "lbs", notes: "Power rows", order: 1),
                .init(name: "Incline Dumbbell Press", sets: 3, reps: 10, suggestedWeight: 55, weightUnit: "lbs", notes: "Hypertrophy range", order: 2),
                .init(name: "Cable Row", sets: 3, reps: 12, suggestedWeight: 120, weightUnit: "lbs", notes: "Volume work", order: 3),
                .init(name: "Dumbbell Shoulder Press", sets: 3, reps: 10, suggestedWeight: 45, weightUnit: "lbs", notes: "Controlled tempo", order: 4),
                .init(name: "Dumbbell Curl", sets: 3, reps: 10, suggestedWeight: 30, weightUnit: "lbs", notes: "Each arm", order: 5),
                .init(name: "Rope Tricep Extension", sets: 3, reps: 12, suggestedWeight: 50, weightUnit: "lbs", notes: "High volume", order: 6)
            ]
        ),
        
        // Template 5: Chest & Triceps
        BuiltInTemplateData(
            title: "Intermediate Chest & Triceps Muscle Building",
            description: "Classic chest and tri day. Multiple angles for complete development.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 3,
            estimatedDuration: 60,
            equipment: ["barbell", "dumbbells", "cables", "dip_station"],
            muscleGroups: ["chest", "triceps"],
            exercises: [
                .init(name: "Barbell Bench Press", sets: 4, reps: 8, suggestedWeight: 145, weightUnit: "lbs", notes: "Compound movement", order: 0),
                .init(name: "Incline Dumbbell Press", sets: 4, reps: 10, suggestedWeight: 50, weightUnit: "lbs", notes: "Upper chest focus", order: 1),
                .init(name: "Decline Dumbbell Press", sets: 3, reps: 10, suggestedWeight: 50, weightUnit: "lbs", notes: "Lower chest", order: 2),
                .init(name: "Cable Chest Fly", sets: 3, reps: 12, suggestedWeight: 25, weightUnit: "lbs", notes: "Stretch and squeeze", order: 3),
                .init(name: "Dips", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Add weight if possible", order: 4),
                .init(name: "Close Grip Bench Press", sets: 3, reps: 10, suggestedWeight: 95, weightUnit: "lbs", notes: "Tricep mass", order: 5),
                .init(name: "Overhead Cable Extension", sets: 3, reps: 12, suggestedWeight: 40, weightUnit: "lbs", notes: "Full stretch", order: 6)
            ]
        ),
        
        // Template 6: Back & Biceps
        BuiltInTemplateData(
            title: "Intermediate Back & Biceps Muscle Building",
            description: "High volume back and bicep workout. Width and thickness focus.",
            experienceLevel: "intermediate",
            goal: "muscle_building",
            difficulty: 3,
            estimatedDuration: 65,
            equipment: ["barbell", "dumbbells", "cables", "pull_up_bar"],
            muscleGroups: ["back", "biceps"],
            exercises: [
                .init(name: "Pull-ups", sets: 4, reps: 8, suggestedWeight: nil, weightUnit: "lbs", notes: "Weighted if possible", order: 0),
                .init(name: "Barbell Row", sets: 4, reps: 8, suggestedWeight: 115, weightUnit: "lbs", notes: "Pull to lower chest", order: 1),
                .init(name: "Dumbbell Row", sets: 4, reps: 10, suggestedWeight: 60, weightUnit: "lbs", notes: "Each arm, full range", order: 2),
                .init(name: "Lat Pulldown", sets: 3, reps: 12, suggestedWeight: 120, weightUnit: "lbs", notes: "Pull to chest", order: 3),
                .init(name: "Face Pull", sets: 3, reps: 15, suggestedWeight: 40, weightUnit: "lbs", notes: "Rear delts", order: 4),
                .init(name: "Barbell Curl", sets: 4, reps: 10, suggestedWeight: 60, weightUnit: "lbs", notes: "EZ bar okay", order: 5),
                .init(name: "Hammer Curl", sets: 3, reps: 12, suggestedWeight: 30, weightUnit: "lbs", notes: "Brachialis focus", order: 6)
            ]
        )
    ]
    
    // GOAL: Strength Gains
    static let intermediateStrength: [BuiltInTemplateData] = [
        // Template 1: 5/3/1 Squat (Based on Jim Wendler's 5/3/1)
        BuiltInTemplateData(
            title: "Intermediate 5/3/1 Squat Strength Day",
            description: "Jim Wendler's proven 5/3/1 program for squats. Progressive strength building.",
            experienceLevel: "intermediate",
            goal: "strength_gains",
            difficulty: 4,
            estimatedDuration: 60,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs", "core"],
            exercises: [
                .init(name: "Back Squat - Warm-up", sets: 2, reps: 5, suggestedWeight: 95, weightUnit: "lbs", notes: "40% of training max", order: 0),
                .init(name: "Back Squat - Set 1", sets: 1, reps: 5, suggestedWeight: 135, weightUnit: "lbs", notes: "65% of training max", order: 1),
                .init(name: "Back Squat - Set 2", sets: 1, reps: 5, suggestedWeight: 155, weightUnit: "lbs", notes: "75% of training max", order: 2),
                .init(name: "Back Squat - Set 3", sets: 1, reps: 5, suggestedWeight: 175, weightUnit: "lbs", notes: "85% of training max, AMRAP", order: 3),
                .init(name: "Front Squat", sets: 5, reps: 10, suggestedWeight: 95, weightUnit: "lbs", notes: "Assistance work", order: 4),
                .init(name: "Leg Curl", sets: 5, reps: 10, suggestedWeight: 70, weightUnit: "lbs", notes: "Hamstrings", order: 5),
                .init(name: "Ab Wheel Rollout", sets: 5, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Core strength", order: 6)
            ]
        ),
        
        // Template 2: 5/3/1 Bench
        BuiltInTemplateData(
            title: "Intermediate 5/3/1 Bench Press Strength Day",
            description: "5/3/1 bench press progression with assistance work.",
            experienceLevel: "intermediate",
            goal: "strength_gains",
            difficulty: 4,
            estimatedDuration: 55,
            equipment: ["barbell", "dumbbells", "bench"],
            muscleGroups: ["chest", "shoulders", "triceps"],
            exercises: [
                .init(name: "Bench Press - Warm-up", sets: 2, reps: 5, suggestedWeight: 65, weightUnit: "lbs", notes: "40% of training max", order: 0),
                .init(name: "Bench Press - Set 1", sets: 1, reps: 5, suggestedWeight: 95, weightUnit: "lbs", notes: "65% of training max", order: 1),
                .init(name: "Bench Press - Set 2", sets: 1, reps: 5, suggestedWeight: 115, weightUnit: "lbs", notes: "75% of training max", order: 2),
                .init(name: "Bench Press - Set 3", sets: 1, reps: 5, suggestedWeight: 125, weightUnit: "lbs", notes: "85% of training max, AMRAP", order: 3),
                .init(name: "Incline Dumbbell Press", sets: 5, reps: 10, suggestedWeight: 45, weightUnit: "lbs", notes: "Assistance", order: 4),
                .init(name: "Dumbbell Row", sets: 5, reps: 10, suggestedWeight: 50, weightUnit: "lbs", notes: "Back work", order: 5),
                .init(name: "Face Pull", sets: 5, reps: 15, suggestedWeight: 30, weightUnit: "lbs", notes: "Shoulder health", order: 6)
            ]
        ),
        
        // Template 3: Texas Method Squat (Based on Texas Method)
        BuiltInTemplateData(
            title: "Intermediate Texas Method Volume Squat - 5x5",
            description: "Texas Method volume day. 5x5 at 90% of 5RM. Proven intermediate program.",
            experienceLevel: "intermediate",
            goal: "strength_gains",
            difficulty: 4,
            estimatedDuration: 70,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs"],
            exercises: [
                .init(name: "Back Squat", sets: 5, reps: 5, suggestedWeight: 185, weightUnit: "lbs", notes: "90% of 5RM, volume day", order: 0),
                .init(name: "Romanian Deadlift", sets: 3, reps: 8, suggestedWeight: 135, weightUnit: "lbs", notes: "Assistance", order: 1),
                .init(name: "Leg Press", sets: 3, reps: 10, suggestedWeight: 270, weightUnit: "lbs", notes: "Extra volume", order: 2),
                .init(name: "Leg Curl", sets: 3, reps: 10, suggestedWeight: 70, weightUnit: "lbs", notes: "Hamstrings", order: 3),
                .init(name: "Calf Raise", sets: 3, reps: 15, suggestedWeight: 135, weightUnit: "lbs", notes: "Calves", order: 4),
                .init(name: "Plank", sets: 3, reps: 60, suggestedWeight: nil, weightUnit: "lbs", notes: "Core stability", order: 5)
            ]
        ),
        
        // Template 4: Westside for Skinny Bastards (Based on Joe DeFranco's program)
        BuiltInTemplateData(
            title: "Intermediate Max Effort Upper Body Strength",
            description: "Westside-inspired max effort day. Work up to heavy triple.",
            experienceLevel: "intermediate",
            goal: "strength_gains",
            difficulty: 4,
            estimatedDuration: 65,
            equipment: ["barbell", "dumbbells"],
            muscleGroups: ["chest", "back", "shoulders"],
            exercises: [
                .init(name: "Floor Press", sets: 1, reps: 3, suggestedWeight: 155, weightUnit: "lbs", notes: "Work up to heavy 3RM", order: 0),
                .init(name: "Incline Barbell Press", sets: 3, reps: 6, suggestedWeight: 115, weightUnit: "lbs", notes: "Supplemental", order: 1),
                .init(name: "Dumbbell Row", sets: 4, reps: 8, suggestedWeight: 65, weightUnit: "lbs", notes: "Heavy", order: 2),
                .init(name: "Barbell Curl", sets: 3, reps: 8, suggestedWeight: 65, weightUnit: "lbs", notes: "Arm work", order: 3),
                .init(name: "Tricep Extension", sets: 3, reps: 10, suggestedWeight: 50, weightUnit: "lbs", notes: "Triceps", order: 4),
                .init(name: "Face Pull", sets: 3, reps: 15, suggestedWeight: 40, weightUnit: "lbs", notes: "Rear delts", order: 5)
            ]
        ),
        
        // Template 5: Max Effort Lower
        BuiltInTemplateData(
            title: "Intermediate Max Effort Lower Body Strength",
            description: "Lower body max effort. Work to heavy single, double, or triple.",
            experienceLevel: "intermediate",
            goal: "strength_gains",
            difficulty: 5,
            estimatedDuration: 70,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs", "back"],
            exercises: [
                .init(name: "Box Squat", sets: 1, reps: 2, suggestedWeight: 225, weightUnit: "lbs", notes: "Work up to heavy double", order: 0),
                .init(name: "Romanian Deadlift", sets: 4, reps: 6, suggestedWeight: 185, weightUnit: "lbs", notes: "Supplemental", order: 1),
                .init(name: "Bulgarian Split Squat", sets: 3, reps: 8, suggestedWeight: 60, weightUnit: "lbs", notes: "Each leg", order: 2),
                .init(name: "Glute Ham Raise", sets: 3, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Hamstrings", order: 3),
                .init(name: "Leg Curl", sets: 3, reps: 12, suggestedWeight: 80, weightUnit: "lbs", notes: "Extra ham work", order: 4),
                .init(name: "Weighted Plank", sets: 3, reps: 45, suggestedWeight: 25, weightUnit: "lbs", notes: "Plate on back", order: 5)
            ]
        )
    ]
    
    // MARK: - ADVANCED LEVEL
    
    // GOAL: Powerlifting
    static let advancedPowerlifting: [BuiltInTemplateData] = [
        // Template 1: Sheiko Squat Day (Based on Boris Sheiko programs)
        BuiltInTemplateData(
            title: "Advanced Powerlifting - Sheiko Heavy Squat",
            description: "High-volume Russian powerlifting program. Multiple working sets at varying intensities.",
            experienceLevel: "advanced",
            goal: "powerlifting",
            difficulty: 5,
            estimatedDuration: 90,
            equipment: ["barbell", "squat_rack", "bench"],
            muscleGroups: ["legs", "chest", "back"],
            exercises: [
                .init(name: "Back Squat", sets: 5, reps: 5, suggestedWeight: 225, weightUnit: "lbs", notes: "80% of 1RM", order: 0),
                .init(name: "Bench Press", sets: 5, reps: 5, suggestedWeight: 175, weightUnit: "lbs", notes: "75% of 1RM", order: 1),
                .init(name: "Back Squat", sets: 5, reps: 4, suggestedWeight: 245, weightUnit: "lbs", notes: "85% of 1RM", order: 2),
                .init(name: "Good Morning", sets: 4, reps: 6, suggestedWeight: 135, weightUnit: "lbs", notes: "Assistance", order: 3),
                .init(name: "Leg Press", sets: 3, reps: 10, suggestedWeight: 360, weightUnit: "lbs", notes: "Volume work", order: 4),
                .init(name: "Ab Wheel", sets: 4, reps: 12, suggestedWeight: nil, weightUnit: "lbs", notes: "Core", order: 5)
            ]
        ),
        
        // Template 2: Smolov Squat Cycle
        BuiltInTemplateData(
            title: "Advanced Powerlifting - Smolov Squat Cycle",
            description: "Brutal Russian squat program. 4 squat days per week, high volume and intensity.",
            experienceLevel: "advanced",
            goal: "powerlifting",
            difficulty: 5,
            estimatedDuration: 60,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs"],
            exercises: [
                .init(name: "Back Squat", sets: 4, reps: 9, suggestedWeight: 205, weightUnit: "lbs", notes: "70% of 1RM", order: 0),
                .init(name: "Back Squat", sets: 5, reps: 7, suggestedWeight: 225, weightUnit: "lbs", notes: "75% of 1RM", order: 1),
                .init(name: "Back Squat", sets: 7, reps: 5, suggestedWeight: 245, weightUnit: "lbs", notes: "80% of 1RM", order: 2),
                .init(name: "Back Squat", sets: 10, reps: 3, suggestedWeight: 265, weightUnit: "lbs", notes: "85% of 1RM", order: 3)
            ]
        ),
        
        // Template 3: Conjugate Method - Max Effort Squat
        BuiltInTemplateData(
            title: "Advanced Powerlifting - Westside Max Effort Squat",
            description: "Westside Barbell conjugate method. Work to max, then volume work.",
            experienceLevel: "advanced",
            goal: "powerlifting",
            difficulty: 5,
            estimatedDuration: 85,
            equipment: ["barbell", "squat_rack", "chains", "bands"],
            muscleGroups: ["legs", "back"],
            exercises: [
                .init(name: "Box Squat with Chains", sets: 1, reps: 1, suggestedWeight: 275, weightUnit: "lbs", notes: "Work to 1RM", order: 0),
                .init(name: "Speed Deadlift", sets: 8, reps: 3, suggestedWeight: 225, weightUnit: "lbs", notes: "60% with bands", order: 1),
                .init(name: "Belt Squat", sets: 4, reps: 12, suggestedWeight: 180, weightUnit: "lbs", notes: "Volume", order: 2),
                .init(name: "Glute Ham Raise", sets: 4, reps: 10, suggestedWeight: nil, weightUnit: "lbs", notes: "Add weight", order: 3),
                .init(name: "Reverse Hyper", sets: 4, reps: 15, suggestedWeight: 90, weightUnit: "lbs", notes: "Low back", order: 4),
                .init(name: "Weighted Sit-ups", sets: 4, reps: 15, suggestedWeight: 45, weightUnit: "lbs", notes: "Abs", order: 5)
            ]
        ),
        
        // Template 4: Conjugate Dynamic Effort - Bench
        BuiltInTemplateData(
            title: "Advanced Powerlifting - Westside Speed Bench",
            description: "Speed bench day. 8-10 sets of 3 reps at 50-60% with bands or chains.",
            experienceLevel: "advanced",
            goal: "powerlifting",
            difficulty: 4,
            estimatedDuration: 75,
            equipment: ["barbell", "bands", "dumbbells"],
            muscleGroups: ["chest", "triceps", "shoulders"],
            exercises: [
                .init(name: "Speed Bench Press", sets: 9, reps: 3, suggestedWeight: 135, weightUnit: "lbs", notes: "55% + bands, explosive", order: 0),
                .init(name: "Board Press", sets: 5, reps: 5, suggestedWeight: 185, weightUnit: "lbs", notes: "3-board", order: 1),
                .init(name: "Dumbbell Row", sets: 4, reps: 12, suggestedWeight: 80, weightUnit: "lbs", notes: "Heavy", order: 2),
                .init(name: "JM Press", sets: 4, reps: 8, suggestedWeight: 95, weightUnit: "lbs", notes: "Triceps", order: 3),
                .init(name: "Rear Delt Fly", sets: 4, reps: 15, suggestedWeight: 25, weightUnit: "lbs", notes: "Shoulder health", order: 4),
                .init(name: "Cable Tricep Pushdown", sets: 4, reps: 20, suggestedWeight: 70, weightUnit: "lbs", notes: "Pump", order: 5)
            ]
        ),
        
        // Template 5: Bulgarian Method - Squat
        BuiltInTemplateData(
            title: "Advanced Powerlifting - Bulgarian Daily Max Squat",
            description: "Work up to daily max squat, then back-off sets. Advanced training only.",
            experienceLevel: "advanced",
            goal: "powerlifting",
            difficulty: 5,
            estimatedDuration: 75,
            equipment: ["barbell", "squat_rack"],
            muscleGroups: ["legs"],
            exercises: [
                .init(name: "Back Squat", sets: 1, reps: 1, suggestedWeight: 285, weightUnit: "lbs", notes: "Work to daily max (90-97%)", order: 0),
                .init(name: "Back Squat", sets: 3, reps: 2, suggestedWeight: 255, weightUnit: "lbs", notes: "Drop to 85-90%", order: 1),
                .init(name: "Front Squat", sets: 3, reps: 3, suggestedWeight: 185, weightUnit: "lbs", notes: "Work to heavy triple", order: 2),
                .init(name: "Bulgarian Split Squat", sets: 3, reps: 8, suggestedWeight: 80, weightUnit: "lbs", notes: "Each leg", order: 3),
                .init(name: "Nordic Curl", sets: 3, reps: 6, suggestedWeight: nil, weightUnit: "lbs", notes: "Eccentric focus", order: 4)
            ]
        )
    ]
    
    // Combine all templates
    static let allTemplates: [BuiltInTemplateData] = 
        beginnerFullBody + 
        beginnerWeightLoss + 
        beginnerHome +
        intermediateHypertrophy +
        intermediateStrength +
        advancedPowerlifting
}

