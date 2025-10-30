import Foundation
import SwiftData

struct ExerciseLibrary {
    // Beginner-friendly exercises (bodyweight, machines, simple movements)
    static let beginnerExercises: [(name: String, muscleGroup: String)] = [
        // Chest - Beginner
        ("Push-Ups", "Chest"),
        ("Knee Push-Ups", "Chest"),
        ("Wall Push-Ups", "Chest"),
        ("Machine Chest Press", "Chest"),
        ("Dumbbell Press", "Chest"),
        
        // Back - Beginner
        ("Assisted Pull-Ups", "Back"),
        ("Lat Pulldowns", "Back"),
        ("Seated Cable Rows", "Back"),
        ("Machine Rows", "Back"),
        ("Dumbbell Rows", "Back"),
        
        // Legs - Beginner
        ("Bodyweight Squats", "Legs"),
        ("Goblet Squats", "Legs"),
        ("Leg Press", "Legs"),
        ("Leg Extensions", "Legs"),
        ("Leg Curls", "Legs"),
        ("Step-Ups", "Legs"),
        ("Wall Sits", "Legs"),
        ("Glute Bridges", "Legs"),
        
        // Shoulders - Beginner
        ("Dumbbell Shoulder Press", "Shoulders"),
        ("Machine Shoulder Press", "Shoulders"),
        ("Lateral Raises (Light)", "Shoulders"),
        ("Front Raises (Light)", "Shoulders"),
        
        // Arms - Beginner
        ("Dumbbell Bicep Curls", "Arms"),
        ("Machine Bicep Curls", "Arms"),
        ("Tricep Pushdowns (Cable)", "Arms"),
        ("Overhead Tricep Extension (Dumbbell)", "Arms"),
        
        // Core - Beginner
        ("Plank", "Core"),
        ("Dead Bug", "Core"),
        ("Bird Dog", "Core"),
        ("Knee Raises", "Core"),
        ("Bicycle Crunches", "Core"),
        ("Side Plank", "Core"),
        ("Cat-Cow Stretch", "Core"),
        
        // Cardio - Beginner
        ("Walking", "Cardio"),
        ("Light Jogging", "Cardio"),
        ("Stationary Bike", "Cardio"),
        ("Elliptical", "Cardio"),
        ("Swimming", "Cardio"),
        ("Jumping Jacks", "Cardio")
    ]
    
    static let predefinedExercises: [(name: String, muscleGroup: String)] = [
        // Chest
        ("Bench Press", "Chest"),
        ("Incline Bench Press", "Chest"),
        ("Decline Bench Press", "Chest"),
        ("Dumbbell Press", "Chest"),
        ("Incline Dumbbell Press", "Chest"),
        ("Decline Dumbbell Press", "Chest"),
        ("Push-Ups", "Chest"),
        ("Chest Flyes", "Chest"),
        ("Incline Chest Flyes", "Chest"),
        ("Decline Chest Flyes", "Chest"),
        
        // Back
        ("Pull-Ups", "Back"),
        ("Lat Pulldowns", "Back"),
        ("Bent Over Rows", "Back"),
        ("Seated Rows", "Back"),
        ("Deadlifts", "Back"),
        ("Romanian Deadlifts", "Back"),
        ("Face Pulls", "Back"),
        ("Reverse Flyes", "Back"),
        ("Good Mornings", "Back"),
        ("Hyperextensions", "Back"),
        
        // Legs
        ("Squats", "Legs"),
        ("Front Squats", "Legs"),
        ("Romanian Squats", "Legs"),
        ("Leg Press", "Legs"),
        ("Lunges", "Legs"),
        ("Walking Lunges", "Legs"),
        ("Leg Extensions", "Legs"),
        ("Leg Curls", "Legs"),
        ("Calf Raises", "Legs"),
        ("Hip Thrusts", "Legs"),
        
        // Shoulders
        ("Military Press", "Shoulders"),
        ("Dumbbell Shoulder Press", "Shoulders"),
        ("Lateral Raises", "Shoulders"),
        ("Front Raises", "Shoulders"),
        ("Rear Delt Flyes", "Shoulders"),
        ("Shrugs", "Shoulders"),
        ("Upright Rows", "Shoulders"),
        ("Arnold Press", "Shoulders"),
        ("Face Pulls", "Shoulders"),
        ("Cable Lateral Raises", "Shoulders"),
        
        // Arms
        ("Bicep Curls", "Arms"),
        ("Hammer Curls", "Arms"),
        ("Preacher Curls", "Arms"),
        ("Tricep Pushdowns", "Arms"),
        ("Tricep Extensions", "Arms"),
        ("Skull Crushers", "Arms"),
        ("Close Grip Bench Press", "Arms"),
        ("Concentration Curls", "Arms"),
        ("Reverse Grip Curls", "Arms"),
        ("Dips", "Arms"),
        
        // Core
        ("Crunches", "Core"),
        ("Plank", "Core"),
        ("Russian Twists", "Core"),
        ("Mountain Climbers", "Core"),
        ("Leg Raises", "Core"),
        ("Bicycle Crunches", "Core"),
        ("Side Plank", "Core"),
        ("Woodchoppers", "Core"),
        ("Flutter Kicks", "Core"),
        ("V-Ups", "Core"),
        
        // Cardio
        ("Running", "Cardio"),
        ("Cycling", "Cardio"),
        ("Swimming", "Cardio"),
        ("Jump Rope", "Cardio"),
        ("Burpees", "Cardio"),
        ("Mountain Climbers", "Cardio"),
        ("High Knees", "Cardio"),
        ("Jumping Jacks", "Cardio"),
        ("Rowing", "Cardio"),
        ("Stair Climbing", "Cardio")
    ]
    
    static func populateInitialExercises(context: ModelContext) {
        // Check if we already have exercises
        let descriptor = FetchDescriptor<ExerciseDefinition>()
        let existingExercises = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existingExercises.map { $0.name })
        
        // Combine beginner and standard exercises
        let allExercises = beginnerExercises + predefinedExercises
        
        // Add exercises that don't already exist
        var addedCount = 0
        for exercise in allExercises {
            if !existingNames.contains(exercise.name) {
                let exerciseDef = ExerciseDefinition(
                    name: exercise.name,
                    muscleGroup: exercise.muscleGroup,
                    isUserDefined: false
                )
                context.insert(exerciseDef)
                addedCount += 1
            }
        }
        
        if addedCount > 0 {
            print("✅ Added \(addedCount) new exercises to library")
            try? context.save()
        }
    }
    
    /// Returns beginner-friendly exercise names for filtering
    static func beginnerExerciseNames() -> Set<String> {
        return Set(beginnerExercises.map { $0.name })
    }
} 
