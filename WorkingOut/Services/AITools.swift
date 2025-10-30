import Foundation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - HealthKit Data Tool
#if canImport(FoundationModels)
@available(iOS 26, *)
@MainActor
struct HealthKitDataTool: Tool {
    let name = "getHealthKitData"
    let description = "Retrieves user's health and fitness data from HealthKit and app database including workouts, runs, weight, steps, and exercise performance."
    
    let modelContext: ModelContext
    let weightUnit: String
    let distanceUnit: String
    
    @Generable
    struct Arguments {
        @Guide(description: "Type of data to retrieve: 'workouts', 'runs', 'weight', 'steps', 'all'")
        var dataType: String
        
        @Guide(description: "Number of days to look back (1-90)", .range(1...90))
        var daysBack: Int
    }
    
    struct HealthData: Codable {
        var workoutCount: Int?
        var totalVolumeLifted: Double?
        var runCount: Int?
        var totalDistance: Double?
        var latestWeight: Double?
        var todaySteps: Int?
        var recentWorkouts: [WorkoutDetail]?
        var recentRuns: [RunDetail]?
        var exerciseBaselines: [ExerciseBaselineData]?
    }
    
    struct WorkoutDetail: Codable {
        var date: String
        var exercises: [String]
    }
    
    struct RunDetail: Codable {
        var date: String
        var distance: Double
        var duration: String
        var pace: String
    }
    
    struct ExerciseBaselineData: Codable {
        var name: String
        var e1rm: Double
        var recentPerformance: [String]
    }
    
    func call(arguments: Arguments) async throws -> String {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -arguments.daysBack, to: Date()) ?? Date()
        
        var result = HealthData()
        
        // Fetch data based on requested type
        let shouldFetchAll = arguments.dataType.lowercased() == "all"
        
        if shouldFetchAll || arguments.dataType.lowercased().contains("workout") {
            let workouts: [WorkoutSession] = (try? modelContext.fetch(FetchDescriptor<WorkoutSession>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))) ?? []
            let recentWorkouts = workouts.filter { $0.date >= startDate }
            result.workoutCount = recentWorkouts.count
            
            // Calculate total volume
            let totalVolume = recentWorkouts.reduce(0.0) { acc, session in
                let logs = session.exerciseLogs ?? []
                return acc + logs.reduce(0.0) { s, log in
                    let weight = convertWeight(log.weight, from: log.weightUnit, to: weightUnit)
                    return s + (Double(log.reps) * weight)
                }
            }
            result.totalVolumeLifted = totalVolume
            
            // Get detailed workout info
            result.recentWorkouts = recentWorkouts.prefix(10).map { session in
                let exercises = (session.exerciseLogs ?? []).compactMap { $0.exerciseName }.uniqued()
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                return WorkoutDetail(
                    date: dateFormatter.string(from: session.date),
                    exercises: exercises
                )
            }
            
            // Get exercise baselines
            let baselines = ExerciseRecommendationService.baselines(context: modelContext, preferredUnit: weightUnit)
            result.exerciseBaselines = baselines.prefix(8).map { baseline in
                let recentPerf = baseline.lastByReps.sorted { $0.key < $1.key }.map {
                    "\($0.key) reps @ \(Int($0.value))\(weightUnit)"
                }
                return ExerciseBaselineData(
                    name: baseline.name,
                    e1rm: baseline.e1rm,
                    recentPerformance: recentPerf
                )
            }
        }
        
        if shouldFetchAll || arguments.dataType.lowercased().contains("run") {
            let runs: [RunningSession] = (try? modelContext.fetch(FetchDescriptor<RunningSession>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))) ?? []
            let recentRuns = runs.filter { $0.date >= startDate }
            result.runCount = recentRuns.count
            
            // Calculate total distance
            let totalDist = recentRuns.reduce(0.0) { acc, run in
                let value = run.distance
                let inKm = run.distanceUnit.lowercased().contains("mi") ? value * 1.60934 : value
                let converted = distanceUnit.lowercased().contains("km") ? inKm : inKm / 1.60934
                return acc + converted
            }
            result.totalDistance = totalDist
            
            // Get detailed run info
            result.recentRuns = recentRuns.prefix(10).map { run in
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                
                let distInUnit = distanceUnit.lowercased().contains("km") ?
                    (run.distanceUnit.lowercased().contains("mi") ? run.distance * 1.60934 : run.distance) :
                    (run.distanceUnit.lowercased().contains("mi") ? run.distance : run.distance / 1.60934)
                
                let duration = formatDuration(run.duration)
                let pace = calculatePace(distInUnit, duration: run.duration)
                
                return RunDetail(
                    date: dateFormatter.string(from: run.date),
                    distance: distInUnit,
                    duration: duration,
                    pace: pace
                )
            }
        }
        
        if shouldFetchAll || arguments.dataType.lowercased().contains("weight") {
            let weights: [WeightEntry] = (try? modelContext.fetch(
                FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            )) ?? []
            if let latest = weights.first {
                result.latestWeight = latest.weightUnit == weightUnit ?
                    latest.weight :
                    convertWeight(latest.weight, from: latest.weightUnit, to: weightUnit)
            }
        }
        
        if shouldFetchAll || arguments.dataType.lowercased().contains("step") {
            // Fetch from HealthKit
            let hkManager = HealthKitManager.shared
            if hkManager.isAuthorized {
                result.todaySteps = try? await hkManager.todayStepCount()
            }
        }
        
        // Format as readable text
        return formatHealthData(result)
    }
    
    private func formatHealthData(_ data: HealthData) -> String {
        var lines: [String] = []
        
        if let workouts = data.workoutCount {
            lines.append("Recent Workouts: \(workouts) sessions")
            if let volume = data.totalVolumeLifted {
                lines.append("Total Volume Lifted: \(String(format: "%.0f", volume)) \(weightUnit)")
            }
            
            if let details = data.recentWorkouts, !details.isEmpty {
                lines.append("\nDetailed Workout History:")
                for workout in details {
                    let exerciseList = workout.exercises.joined(separator: ", ")
                    lines.append("• \(workout.date): \(exerciseList)")
                }
            }
        }
        
        if let runs = data.runCount {
            lines.append("\nRecent Runs: \(runs) sessions")
            if let distance = data.totalDistance {
                lines.append("Total Distance: \(String(format: "%.1f", distance)) \(distanceUnit)")
            }
            
            if let details = data.recentRuns, !details.isEmpty {
                lines.append("\nDetailed Run History:")
                for run in details {
                    lines.append("• \(run.date): \(String(format: "%.2f", run.distance)) \(distanceUnit) in \(run.duration) (pace: \(run.pace))")
                }
            }
        }
        
        if let weight = data.latestWeight {
            lines.append("\nCurrent Weight: \(String(format: "%.1f", weight)) \(weightUnit)")
        }
        
        if let steps = data.todaySteps {
            lines.append("Today's Steps: \(steps)")
        }
        
        if let baselines = data.exerciseBaselines, !baselines.isEmpty {
            lines.append("\nExercise Performance Baselines:")
            for baseline in baselines {
                lines.append("• \(baseline.name): e1RM ~\(Int(baseline.e1rm))\(weightUnit)")
                for perf in baseline.recentPerformance.prefix(2) {
                    lines.append("  - \(perf)")
                }
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, secs)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, secs)
        } else {
            return String(format: "%ds", secs)
        }
    }
    
    private func calculatePace(_ distance: Double, duration: TimeInterval) -> String {
        guard distance > 0 else { return "N/A" }
        let paceMinutes = duration / 60.0 / distance
        let mins = Int(paceMinutes)
        let secs = Int((paceMinutes - Double(mins)) * 60)
        return String(format: "%d:%02d per %@", mins, secs, distanceUnit)
    }
    
    private func convertWeight(_ value: Double, from: String, to: String) -> Double {
        if from == to { return value }
        if from == "kg" && to == "lbs" { return value * 2.20462 }
        if from == "lbs" && to == "kg" { return value / 2.20462 }
        return value
    }
}

// Helper extension to get unique elements
extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
#endif

// MARK: - Web Search Tool
#if canImport(FoundationModels)
@available(iOS 26, *)
@MainActor
struct WebSearchTool: Tool {
    let name = "webSearch"
    let description = "Searches DuckDuckGo, Reddit, and Wikipedia for verified information. Use for factual questions, research, definitions, benefits, studies, or health/nutrition advice. Cite sources as [1], [2] in your response."

    @Generable
    struct Arguments {
        @Guide(description: "Search query - be specific and focused")
        var query: String

        @Guide(description: "Max results (1-5), use 3-4 typically", .range(1...5))
        var maxResults: Int
    }

    func call(arguments: Arguments) async throws -> String {
        guard !arguments.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: Query cannot be empty."
        }

        do {
            let results = try await WebSearchService.shared.search(
                query: arguments.query,
                maxResults: arguments.maxResults
            )
            
            guard !results.isEmpty else {
                return "No results found. Try rephrasing your query."
            }

            return WebSearchService.formattedContext(for: results, includeCitations: true)
        } catch {
            throw error
        }
    }
}
#endif

