import Foundation
import SwiftData

#if DEBUG
/// Generates realistic sample data for testing purposes (DEBUG builds only)
enum DebugDataGenerator {

    // Hidden markers to identify debug/sample data (not visible to user)
    // Legacy IDs used by older builds (keep for cleanup only)
    private static let legacyWorkoutTemplateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let legacyRunUUIDPrefix = "DEBUG_SAMPLE_"
    // Legacy marker previously written into notes (keep for cleanup only)
    private static let legacyDebugMarker = "[SAMPLE_DATA]"
    private static var didSeedUITestFixture = false

    // MARK: - UI Test Fixtures

    static func generateUITestFixture(named fixtureName: String, context: ModelContext) {
        guard fixtureName == "core_tabs", !didSeedUITestFixture else { return }

        didSeedUITestFixture = true
        generateCoreTabsFixture(context: context)
    }

    private static func generateCoreTabsFixture(context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let weightFixtures: [(dayOffset: Int, weight: Double)] = [
            (6, 184.6),
            (5, 184.1),
            (4, 183.8),
            (3, 183.5),
            (2, 183.2),
            (1, 182.9),
            (0, 182.6),
        ]

        let runFixtures: [(dayOffset: Int, miles: Double, durationMinutes: Double, activityType: String)] = [
            (5, 3.2, 29, "running"),
            (3, 4.1, 36, "running"),
            (1, 2.4, 43, "walking"),
        ]

        let workoutFixtures: [(dayOffset: Int, title: String, exercises: [(name: String, muscleGroup: String, sets: [(reps: Int, weight: Double)])])] = [
            (
                4,
                "Upper Body Focus",
                [
                    ("Bench Press", "Chest", [(8, 185), (8, 185), (6, 195)]),
                    ("Barbell Row", "Back", [(10, 155), (10, 155), (8, 165)]),
                    ("Overhead Press", "Shoulders", [(8, 115), (8, 115), (6, 120)]),
                ]
            ),
            (
                2,
                "Leg Day",
                [
                    ("Squat", "Legs", [(8, 225), (8, 225), (6, 245)]),
                    ("Romanian Deadlift", "Back", [(10, 185), (10, 185), (8, 205)]),
                    ("Leg Press", "Legs", [(12, 360), (12, 360), (10, 410)]),
                ]
            ),
            (
                0,
                "Push Day",
                [
                    ("Incline Dumbbell Press", "Chest", [(10, 65), (10, 65), (8, 70)]),
                    ("Tricep Pushdown", "Triceps", [(12, 50), (12, 55), (10, 60)]),
                    ("Lateral Raise", "Shoulders", [(15, 20), (15, 20), (12, 25)]),
                ]
            ),
        ]

        for entry in weightFixtures {
            guard let date = calendar.date(byAdding: .day, value: -entry.dayOffset, to: today) else { continue }
            let weightEntry = WeightEntry(date: calendar.date(byAdding: .hour, value: 7, to: date) ?? date, weight: entry.weight, weightUnit: "lbs")
            context.insert(weightEntry)
        }

        for fixture in runFixtures {
            guard let date = calendar.date(byAdding: .day, value: -fixture.dayOffset, to: today) else { continue }
            let sessionDate = calendar.date(byAdding: .hour, value: 6, to: date) ?? date
            let run = RunningSession(
                date: sessionDate,
                distance: fixture.miles,
                distanceUnit: "mi",
                duration: fixture.durationMinutes * 60,
                calories: fixture.miles * 105,
                locations: Data(),
                activityType: fixture.activityType,
                avgHeartRate: fixture.activityType == "running" ? 148 : 112,
                maxHeartRate: fixture.activityType == "running" ? 172 : 128,
                minHeartRate: 82,
                avgCadence: fixture.activityType == "running" ? 170 : 108,
                totalAscent: fixture.activityType == "running" ? 145 : 40,
                totalDescent: fixture.activityType == "running" ? 145 : 40
            )
            run.isSampleData = true
            context.insert(run)
        }

        for fixture in workoutFixtures {
            guard let date = calendar.date(byAdding: .day, value: -fixture.dayOffset, to: today) else { continue }
            let sessionDate = calendar.date(byAdding: .hour, value: 18, to: date) ?? date
            let session = WorkoutSession(date: sessionDate, notes: nil, title: fixture.title)
            session.isSampleData = true
            context.insert(session)

            for (exerciseOrder, exerciseFixture) in fixture.exercises.enumerated() {
                let definition = findOrCreateExercise(
                    name: exerciseFixture.name,
                    muscleGroup: exerciseFixture.muscleGroup,
                    context: context
                )

                for (setIndex, setFixture) in exerciseFixture.sets.enumerated() {
                    let log = ExerciseLog(
                        reps: setFixture.reps,
                        weight: setFixture.weight,
                        weightUnit: "lbs",
                        setNumber: setIndex + 1,
                        exerciseName: exerciseFixture.name,
                        exerciseOrder: exerciseOrder,
                        isCompleted: true
                    )
                    log.exerciseDefinition = definition
                    log.workoutSession = session
                    context.insert(log)
                }
            }
        }

        _ = PersistenceSave.commit(context, action: "save changes")
    }

    // MARK: - Sample Data Generation

    /// Generates 1 month of realistic sample data (workouts and cardio only)
    static func generateSampleData(context: ModelContext) {
        migrateLegacySampleMarkers(context: context)
        if hasAnySampleData(context: context) {
            _ = PersistenceSave.commit(context, action: "save changes")
            return
        }

        let calendar = Calendar.current
        let today = Date()

        // Generate data for the past 30 days
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            // Workouts - about 4-5 per week (not every day)
            if shouldHaveWorkout(dayOffset: dayOffset) {
                generateWorkoutSession(for: date, dayOffset: dayOffset, context: context)
            }

            // Cardio - about 3-4 per week
            if shouldHaveCardio(dayOffset: dayOffset) {
                generateRunningSession(for: date, dayOffset: dayOffset, context: context)
            }
        }

        _ = PersistenceSave.commit(context, action: "save changes")
    }

    static func hideLegacySampleMarkers(context: ModelContext) {
        migrateLegacySampleMarkers(context: context)
        _ = PersistenceSave.commit(context, action: "save changes")
    }

    private static func hasAnySampleData(context: ModelContext) -> Bool {
        if let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()),
           sessions.contains(where: { $0.isSampleData || $0.sourceTemplateID == legacyWorkoutTemplateID }) {
            return true
        }
        if let runs = try? context.fetch(FetchDescriptor<RunningSession>()),
           runs.contains(where: { $0.isSampleData || ($0.healthWorkoutUUID ?? "").hasPrefix(legacyRunUUIDPrefix) }) {
            return true
        }
        return false
    }

    private static func migrateLegacySampleMarkers(context: ModelContext) {
        // Workout sessions: convert visible notes marker -> hidden isSampleData flag
        if let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) {
            for session in sessions where
                (session.notes ?? "").contains(legacyDebugMarker) || session.sourceTemplateID == legacyWorkoutTemplateID {
                session.isSampleData = true
                session.notes = stripLegacyMarker(from: session.notes)
                if session.sourceTemplateID == legacyWorkoutTemplateID {
                    session.sourceTemplateID = nil
                }
            }
        }

        // Exercise logs: remove visible marker from notes (if present)
        if let logs = try? context.fetch(FetchDescriptor<ExerciseLog>()) {
            for log in logs where (log.notes ?? "").contains(legacyDebugMarker) {
                log.notes = stripLegacyMarker(from: log.notes)
            }
        }

        // Running sessions: remove visible marker from notes and convert legacy UUID marker -> isSampleData
        if let runs = try? context.fetch(FetchDescriptor<RunningSession>()) {
            for run in runs where
                (run.notes ?? "").contains(legacyDebugMarker) || (run.healthWorkoutUUID ?? "").hasPrefix(legacyRunUUIDPrefix) {
                run.isSampleData = true
                run.notes = stripLegacyMarker(from: run.notes)
                if (run.healthWorkoutUUID ?? "").hasPrefix(legacyRunUUIDPrefix) {
                    run.healthWorkoutUUID = nil
                }
            }
        }
    }

    private static func stripLegacyMarker(from text: String?) -> String? {
        let cleaned = (text ?? "")
            .replacingOccurrences(of: legacyDebugMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Removes only sample/debug data (not user data)
    static func removeSampleData(context: ModelContext) {
        // Delete exercise logs belonging to sample sessions (delete logs first since WorkoutSession->ExerciseLog is nullify)
        let sampleSessionIDs: Set<UUID>
        if let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) {
            let sampleSessions = sessions.filter {
                $0.isSampleData || $0.sourceTemplateID == legacyWorkoutTemplateID || ($0.notes ?? "").contains(legacyDebugMarker)
            }
            sampleSessionIDs = Set(sampleSessions.map(\.id))

            if let logs = try? context.fetch(FetchDescriptor<ExerciseLog>()) {
                let sampleLogs = logs.filter { log in
                    if let sessionID = log.workoutSession?.id, sampleSessionIDs.contains(sessionID) {
                        return true
                    }
                    return (log.notes ?? "").contains(legacyDebugMarker)
                }
                sampleLogs.forEach { context.delete($0) }
            }

            sampleSessions.forEach { context.delete($0) }
        } else {
            sampleSessionIDs = []
        }

        // Delete running sessions marked as sample data
        if let runs = try? context.fetch(FetchDescriptor<RunningSession>()) {
            let sampleRuns = runs.filter {
                $0.isSampleData || ($0.healthWorkoutUUID ?? "").hasPrefix(legacyRunUUIDPrefix) || ($0.notes ?? "").contains(legacyDebugMarker)
            }
            sampleRuns.forEach { context.delete($0) }
        }

        // Delete legacy sample weight entries (if any were generated in older builds)
        let storedIDs = UserDefaults.standard.stringArray(forKey: "debugWeightEntryIDs") ?? []
        if !storedIDs.isEmpty, let weights = try? context.fetch(FetchDescriptor<WeightEntry>()) {
            let sampleWeights = weights.filter { storedIDs.contains($0.id.uuidString) }
            sampleWeights.forEach { context.delete($0) }
        }
        UserDefaults.standard.removeObject(forKey: "debugWeightEntryIDs")

        _ = PersistenceSave.commit(context, action: "save changes")
    }

    // MARK: - Workout Generation

    private static func shouldHaveWorkout(dayOffset: Int) -> Bool {
        // Roughly 4-5 workouts per week pattern
        let dayOfWeek = dayOffset % 7
        return [0, 1, 3, 4, 5].contains(dayOfWeek) // Mon, Tue, Thu, Fri, Sat pattern
    }

    private static func generateWorkoutSession(for date: Date, dayOffset: Int, context: ModelContext) {
        let workoutTypes = [
            ("Push Day", ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Tricep Pushdown", "Lateral Raise"]),
            ("Pull Day", ["Barbell Row", "Lat Pulldown", "Face Pull", "Barbell Curl", "Hammer Curl"]),
            ("Leg Day", ["Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise"]),
            ("Upper Body", ["Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown", "Barbell Curl"]),
            ("Full Body", ["Squat", "Bench Press", "Barbell Row", "Overhead Press", "Romanian Deadlift"])
        ]

        let muscleGroups: [String: String] = [
            "Bench Press": "Chest",
            "Overhead Press": "Shoulders",
            "Incline Dumbbell Press": "Chest",
            "Tricep Pushdown": "Triceps",
            "Lateral Raise": "Shoulders",
            "Barbell Row": "Back",
            "Lat Pulldown": "Back",
            "Face Pull": "Back",
            "Barbell Curl": "Biceps",
            "Hammer Curl": "Biceps",
            "Squat": "Legs",
            "Romanian Deadlift": "Legs",
            "Leg Press": "Legs",
            "Leg Curl": "Legs",
            "Calf Raise": "Legs"
        ]

        let workoutIndex = dayOffset % workoutTypes.count
        let (title, exercises) = workoutTypes[workoutIndex]

        // Set workout time to afternoon/evening (4-7 PM)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = Int.random(in: 16...19)
        components.minute = Int.random(in: 0...59)
        let sessionDate = calendar.date(from: components) ?? date

        let session = WorkoutSession(date: sessionDate, notes: nil, title: title)
        session.isSampleData = true
        context.insert(session)

        // Generate exercise logs
        for (exerciseOrder, exerciseName) in exercises.enumerated() {
            let muscleGroup = muscleGroups[exerciseName] ?? "Other"

            // Find or create exercise definition
            let exerciseDef = findOrCreateExercise(name: exerciseName, muscleGroup: muscleGroup, context: context)

            // Generate 3-4 sets per exercise
            let setCount = Int.random(in: 3...4)
            for setNumber in 1...setCount {
                let baseWeight = weightForExercise(exerciseName)
                let weight = baseWeight + Double.random(in: -10...10)
                let reps = Int.random(in: 6...12)

                let log = ExerciseLog(
                    reps: reps,
                    weight: weight,
                    weightUnit: "lbs",
                    setNumber: setNumber,
                    exerciseName: exerciseName,
                    exerciseOrder: exerciseOrder,
                    isCompleted: true
                )
                log.exerciseDefinition = exerciseDef
                log.workoutSession = session
                context.insert(log)
            }
        }
    }

    private static func weightForExercise(_ name: String) -> Double {
        switch name {
        case "Bench Press": return 185.0
        case "Overhead Press": return 115.0
        case "Incline Dumbbell Press": return 65.0
        case "Tricep Pushdown": return 50.0
        case "Lateral Raise": return 20.0
        case "Barbell Row": return 155.0
        case "Lat Pulldown": return 140.0
        case "Face Pull": return 40.0
        case "Barbell Curl": return 75.0
        case "Hammer Curl": return 35.0
        case "Squat": return 225.0
        case "Romanian Deadlift": return 185.0
        case "Leg Press": return 360.0
        case "Leg Curl": return 90.0
        case "Calf Raise": return 180.0
        default: return 100.0
        }
    }

    private static func findOrCreateExercise(name: String, muscleGroup: String, context: ModelContext) -> ExerciseDefinition {
        let descriptor = FetchDescriptor<ExerciseDefinition>(
            predicate: #Predicate { $0.name == name }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let newExercise = ExerciseDefinition(name: name, muscleGroup: muscleGroup, isUserDefined: false)
        context.insert(newExercise)
        return newExercise
    }

    // MARK: - Running Generation

    private static func shouldHaveCardio(dayOffset: Int) -> Bool {
        // Roughly 3-4 cardio sessions per week
        let dayOfWeek = dayOffset % 7
        return [0, 2, 4, 6].contains(dayOfWeek)
    }

    private static func generateRunningSession(for date: Date, dayOffset: Int, context: ModelContext) {
        let activityTypes = ["running", "running", "walking", "hiking", "cycling", "rowing", "elliptical", "stairClimbing"]
        let activityType = activityTypes[dayOffset % activityTypes.count]

        // Set cardio time to morning or evening
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let isMorning = Bool.random()
        components.hour = isMorning ? Int.random(in: 6...8) : Int.random(in: 17...19)
        components.minute = Int.random(in: 0...59)
        let sessionDate = calendar.date(from: components) ?? date

        let (distance, duration, calories, unit) = cardioStats(for: activityType)

        let session = RunningSession(
            date: sessionDate,
            distance: distance,
            distanceUnit: unit,
            duration: duration,
            calories: calories,
            activityType: activityType,
            avgHeartRate: Double.random(in: 130...165),
            maxHeartRate: Double.random(in: 170...185),
            minHeartRate: Double.random(in: 90...110),
            avgCadence: activityType == "running" ? Double.random(in: 165...180) : Double.random(in: 100...120),
            totalAscent: Double.random(in: 50...200),
            totalDescent: Double.random(in: 50...200)
        )
        session.isSampleData = true
        context.insert(session)
    }

    private static func cardioStats(for activityType: String) -> (distance: Double, duration: TimeInterval, calories: Double, unit: String) {
        switch activityType {
        case "running":
            let distance = Double.random(in: 3.0...6.0) // 3-6 miles
            let paceMinPerMile = Double.random(in: 8.0...10.0) // 8-10 min/mile
            let duration = distance * paceMinPerMile * 60 // Convert to seconds
            let calories = distance * 100 // Rough estimate
            return (distance, duration, calories, "mi")

        case "walking":
            let distance = Double.random(in: 1.5...3.0) // 1.5-3 miles
            let paceMinPerMile = Double.random(in: 15.0...20.0) // 15-20 min/mile
            let duration = distance * paceMinPerMile * 60
            let calories = distance * 60
            return (distance, duration, calories, "mi")

        case "hiking":
            let distance = Double.random(in: 2.0...5.0) // 2-5 miles
            let paceMinPerMile = Double.random(in: 18.0...25.0) // 18-25 min/mile (slower due to elevation)
            let duration = distance * paceMinPerMile * 60
            let calories = distance * 80
            return (distance, duration, calories, "mi")

        case "cycling":
            let distance = Double.random(in: 6.0...18.0) // miles
            let mph = Double.random(in: 12.0...18.0)
            let duration = (distance / mph) * 3600
            let calories = duration / 60 * Double.random(in: 7.0...10.0)
            return (distance, duration, calories, "mi")

        case "rowing":
            let distance = Double.random(in: 2.0...6.0) // km
            let paceMinPerKm = Double.random(in: 5.5...7.5)
            let duration = distance * paceMinPerKm * 60
            let calories = duration / 60 * Double.random(in: 6.0...9.0)
            return (distance, duration, calories, "km")

        case "elliptical":
            let duration = Double.random(in: 20.0...50.0) * 60
            let distance = Double.random(in: 1.5...5.0)
            let calories = duration / 60 * Double.random(in: 7.0...10.0)
            return (distance, duration, calories, "mi")

        case "stairClimbing":
            let duration = Double.random(in: 10.0...30.0) * 60
            let distance = Double.random(in: 0.5...2.0)
            let calories = duration / 60 * Double.random(in: 8.0...12.0)
            return (distance, duration, calories, "mi")

        default:
            return (3.0, 1800, 300, "mi")
        }
    }
}
#endif
