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
        ("Incline Machine Chest Press", "Chest"),
        ("Flat Machine Chest Press", "Chest"),
        ("Decline Machine Chest Press", "Chest"),
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
        
        // Arms - Beginner (split into Biceps / Triceps)
        ("Dumbbell Bicep Curls", "Biceps"),
        ("Machine Bicep Curls", "Biceps"),
        ("Tricep Pushdowns (Cable)", "Triceps"),
        ("Overhead Tricep Extension (Dumbbell)", "Triceps"),

        // Forearms - Beginner
        ("Wrist Curls", "Forearms"),
        ("Reverse Wrist Curls", "Forearms"),
        ("Farmer's Carry", "Forearms"),
        
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
        ("Incline Machine Chest Press", "Chest"),
        ("Flat Machine Chest Press", "Chest"),
        ("Decline Machine Chest Press", "Chest"),
        ("Smith Machine Bench Press", "Chest"),
        ("Smith Machine Incline Bench Press", "Chest"),
        ("Smith Machine Decline Bench Press", "Chest"),
        
        // Back
        ("Pull-Ups", "Back"),
        ("Lat Pulldowns", "Back"),
        ("Bent Over Rows", "Back"),
        ("Barbell Rows", "Back"),
        ("Seated Rows", "Back"),
        ("Cable Rows", "Back"),
        ("Deadlifts", "Back"),
        ("Romanian Deadlifts", "Back"),
        ("T-Bar Row", "Back"),
        ("Chest-Supported Row", "Back"),
        ("Face Pulls", "Back"),
        ("Reverse Flyes", "Back"),
        ("Good Mornings", "Back"),
        ("Hyperextensions", "Back"),
        
        // Legs
        ("Squats", "Legs"),
        ("Front Squats", "Legs"),
        ("Bulgarian Split Squats", "Legs"),
        ("Leg Press", "Legs"),
        ("Hack Squat", "Legs"),
        ("Smith Machine Squat", "Legs"),
        ("Lunges", "Legs"),
        ("Walking Lunges", "Legs"),
        ("Leg Extensions", "Legs"),
        ("Leg Curls", "Legs"),
        ("Calf Raises", "Legs"),
        ("Hip Thrusts", "Legs"),
        
        // Shoulders
        ("Military Press", "Shoulders"),
        ("Dumbbell Shoulder Press", "Shoulders"),
        ("Smith Machine Shoulder Press", "Shoulders"),
        ("Lateral Raises", "Shoulders"),
        ("Front Raises", "Shoulders"),
        ("Rear Delt Flyes", "Shoulders"),
        ("Shrugs", "Shoulders"),
        ("Upright Rows", "Shoulders"),
        ("Arnold Press", "Shoulders"),
        ("Face Pulls", "Shoulders"),
        ("Cable Lateral Raises", "Shoulders"),
        
        // Arms (split)
        ("Bicep Curls", "Biceps"),
        ("Hammer Curls", "Biceps"),
        ("Preacher Curls", "Biceps"),
        ("Concentration Curls", "Biceps"),
        ("Reverse Grip Curls", "Biceps"),
        ("Tricep Pushdowns", "Triceps"),
        ("Tricep Extensions", "Triceps"),
        ("Skull Crushers", "Triceps"),
        ("Close Grip Bench Press", "Triceps"),
        ("Dips", "Triceps"),

        // Forearms
        ("Wrist Curls", "Forearms"),
        ("Reverse Wrist Curls", "Forearms"),
        ("Farmer's Carry", "Forearms"),
        
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
        
        // Normalize names so we don't create duplicates that differ only by case/spacing/punctuation
        func normalize(_ s: String) -> String {
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Normalize common punctuation variants
            t = t.replacingOccurrences(of: "\u{2019}", with: "'") // curly apostrophe
            t = t.replacingOccurrences(of: "\u{2018}", with: "'") // left single quote
            t = t.replacingOccurrences(of: "\u{2013}", with: "-") // en dash
            t = t.replacingOccurrences(of: "\u{2014}", with: "-") // em dash
            // Replace non-alphanumerics with spaces and collapse spaces
            t = t.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }.reduce("") { $0 + String($1) }
            while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var seen = Set(existingExercises.map { normalize($0.name) })
        
        // Combine beginner and standard exercises
        let allExercises = beginnerExercises + predefinedExercises
        
        // Add exercises that don't already exist (using normalized comparison)
        var addedCount = 0
        for exercise in allExercises {
            let key = normalize(exercise.name)
            if !seen.contains(key) {
                let exerciseDef = ExerciseDefinition(
                    name: exercise.name,
                    muscleGroup: exercise.muscleGroup,
                    isUserDefined: false
                )
                context.insert(exerciseDef)
                seen.insert(key) // ensure subsequent duplicates in the source lists don't get inserted
                addedCount += 1
            }
        }
        
        if addedCount > 0 {
            print("✅ Added \(addedCount) new exercises to library")
            _ = PersistenceSave.commit(context, action: "save changes")
        }
    }
    
    /// Returns beginner-friendly exercise names for filtering
    static func beginnerExerciseNames() -> Set<String> {
        return Set(beginnerExercises.map { $0.name })
    }
} 
