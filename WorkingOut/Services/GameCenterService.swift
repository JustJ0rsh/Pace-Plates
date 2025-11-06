import Foundation
import SwiftData
#if canImport(GameKit)
import GameKit
import UIKit
#endif

enum Leaderboards {
    // Replace these IDs with your App Store Connect leaderboard identifiers
    static let maxBench = "Bench"
    static let maxSquat = "Squat"
    static let maxDeadlift = "Deadlift"
    static let bestSessionVolume = "Best_Session_Volume"
    static let longestRunMeters = "Longest_Run"
    static let fastest5kSeconds = "Fastest_Run"
}

struct GameCenterService {
    #if canImport(GameKit)
    @available(iOS 26.0, *)
    private static func presentAccessPointDashboard() {
        // Ensure authentication first
        if !GKLocalPlayer.local.isAuthenticated {
            ensureAuthenticated { ok in
                DispatchQueue.main.async {
                    if ok { presentAccessPointDashboard() }
                    else { print("Game Center: not authenticated; cannot present dashboard") }
                }
            }
            return
        }
        let accessPoint = GKAccessPoint.shared
        accessPoint.location = .topLeading
        accessPoint.isActive = true
        if !accessPoint.isPresentingGameCenter {
            accessPoint.trigger(handler: { })
        }
    }

    private static func present(_ vc: UIViewController) {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }),
           var top = window.rootViewController {
            while let presented = top.presentedViewController { top = presented }
            // Avoid re-presenting the same view controller if it's already on top
            if top === vc { return }
            top.present(vc, animated: true)
        }
    }

    static func ensureAuthenticated(completion: @escaping (Bool) -> Void) {
        if GKLocalPlayer.local.isAuthenticated { completion(true); return }
        GKLocalPlayer.local.authenticateHandler = { vc, error in
            if let error { print("GameCenter auth error: \(error.localizedDescription)") }
            if let vc { present(vc) }
            // Call back on next runloop so isAuthenticated has time to update after dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                completion(GKLocalPlayer.local.isAuthenticated)
            }
        }
    }

    @available(iOS 14.0, *)
    private static func submitInt(_ value: Int, leaderboardID: String, completion: @escaping (Error?) -> Void) {
        GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID]) { error in
            if let error { print("GK submit error (\(leaderboardID)): \(error.localizedDescription)") }
            completion(error)
        }
    }

    private static func scaledInt(_ value: Double, scale: Double) -> Int {
        let scaled = (value * scale).rounded()
        let int64 = Int64(scaled)
        if int64 > Int64(Int.max) { return Int.max }
        if int64 < Int64(Int.min) { return Int.min }
        return Int(int64)
    }

    // Present the full Game Center dashboard, routing to the correct UI per iOS version
    static func presentLeaderboardsDashboard() {
        if #available(iOS 26.0, *) {
            presentAccessPointDashboard()
        } else {
            presentLeaderboardsDashboardLegacy()
        }
    }

    @available(iOS, introduced: 14, deprecated: 26, message: "Use GKAccessPoint on iOS 26+")
    private final class GCDelegate: NSObject, GKGameCenterControllerDelegate {
        static let shared = GCDelegate()
        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            gameCenterViewController.dismiss(animated: true)
        }
    }
    // MARK: - Legacy dashboard (pre‑iOS 26)
    @available(iOS, introduced: 14, deprecated: 26, message: "Use GKAccessPoint on iOS 26+")
    static func presentLeaderboardsDashboardLegacy() {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        let vc = GKGameCenterViewController()
        vc.viewState = .leaderboards
        vc.gameCenterDelegate = GCDelegate.shared
        present(vc)
    }
    #endif

    static func maxWeight(for names: [String], context: ModelContext, preferredUnit: String) -> Double? {
        let fd = FetchDescriptor<ExerciseLog>()
        let logs = (try? context.fetch(fd)) ?? []
        let needles = names.map { $0.lowercased() }
        var bestKg: Double = 0
        for l in logs {
            // Only consider strength sets for lift PRs
            if (l.exerciseType ?? "strength").lowercased() == "cardio" { continue }
            // Prefer the snapshot exerciseName; fall back to the linked definition's name
            let rawName = (l.exerciseName?.isEmpty == false ? l.exerciseName : l.exerciseDefinition?.name) ?? ""
            let lname = rawName.lowercased()
            if needles.contains(where: { lname.contains($0) }) {
                let kg = l.weightUnit == "kg" ? l.weight : (l.weight / 2.20462)
                if kg > bestKg { bestKg = kg }
            }
        }
        if bestKg <= 0 { return nil }
        return preferredUnit == "kg" ? bestKg : bestKg * 2.20462
    }

    static func bestSessionVolume(context: ModelContext, preferredUnit: String) -> Double? {
        let sessions: [WorkoutSession] = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        var best: Double = 0
        for s in sessions {
            let volKg = (s.exerciseLogs ?? []).reduce(0.0) { acc, log in
                // Only count strength sets into session volume
                if (log.exerciseType ?? "strength").lowercased() == "cardio" { return acc }
                let kg = log.weightUnit == "kg" ? log.weight : (log.weight / 2.20462)
                return acc + Double(max(0, log.reps)) * max(0, kg)
            }
            if volKg > best { best = volKg }
        }
        return best <= 0 ? nil : (preferredUnit == "kg" ? best : best * 2.20462)
    }

    static func longestRunMeters(context: ModelContext) -> Double? {
        // Include both dedicated RunningSession entries and cardio logs saved inside workouts
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let runMetersFromSessions = runs.map { r -> Double in
            let unit = r.distanceUnit.lowercased()
            if unit.contains("mi") { return r.distance * 1609.34 }
            return r.distance * 1000.0
        }
        let logs: [ExerciseLog] = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        // Heuristic: treat cardio logs whose name suggests running as runs
        let runMetersFromLogs = logs.compactMap { log -> Double? in
            guard (log.exerciseType ?? "").lowercased() == "cardio" else { return nil }
            let name = ((log.exerciseName?.isEmpty == false ? log.exerciseName : log.exerciseDefinition?.name) ?? "").lowercased()
            let looksLikeRun = ["run", "jog", "tread"].contains(where: { name.contains($0) })
            guard looksLikeRun, let d = log.distance, let unit = log.distanceUnit?.lowercased(), d > 0 else { return nil }
            return unit.contains("mi") ? (d * 1609.34) : (d * 1000.0)
        }
        let meters = max(runMetersFromSessions.max() ?? 0, runMetersFromLogs.max() ?? 0)
        return meters > 0 ? meters : nil
    }

    static func fastest5kSeconds(context: ModelContext) -> Double? {
        // Compute from RunningSession plus cardio logs that look like runs
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        var best: Double = .greatestFiniteMagnitude
        for r in runs {
            let unit = r.distanceUnit.lowercased()
            let km = unit.contains("mi") ? (r.distance * 1.60934) : r.distance
            guard km > 0, r.duration > 0 else { continue }
            let factor = 5.0 / km
            let est = r.duration * factor
            if est < best { best = est }
        }
        let logs: [ExerciseLog] = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        for log in logs {
            guard (log.exerciseType ?? "").lowercased() == "cardio" else { continue }
            let name = ((log.exerciseName?.isEmpty == false ? log.exerciseName : log.exerciseDefinition?.name) ?? "").lowercased()
            let looksLikeRun = ["run", "jog", "tread"].contains(where: { name.contains($0) })
            guard looksLikeRun, let d = log.distance, let unit = log.distanceUnit?.lowercased(), d > 0, let sec = log.durationSeconds, sec > 0 else { continue }
            let km = unit.contains("mi") ? (d * 1.60934) : d
            let est = Double(sec) * (5.0 / km)
            if est < best { best = est }
        }
        return best == .greatestFiniteMagnitude ? nil : best
    }

    static func submitAllMetrics(context: ModelContext, preferredUnit: String, completion: (([String: Error?]) -> Void)? = nil) {
        #if canImport(GameKit)
        ensureAuthenticated { ok in
            guard ok else { print("GK submit aborted: not authenticated"); return }
            if #available(iOS 14.0, *) {
                var results: [String: Error?] = [:]
                let group = DispatchGroup()

                func push(_ label: String, value: Double?, scale: Double, id: String) {
                    guard let v = value else { results[label] = NSError(domain: "GameCenter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No value"]); return }
                    group.enter()
                    submitInt(scaledInt(v, scale: scale), leaderboardID: id) { err in
                        results[label] = err
                        group.leave()
                    }
                }

                push("Max Bench", value: maxWeight(for: ["bench press", "incline bench press", "decline bench press", "barbell bench press", "dumbbell bench press", "bench"], context: context, preferredUnit: preferredUnit), scale: 100, id: Leaderboards.maxBench)
                push("Max Squat", value: maxWeight(for: ["squat", "squats", "back squat", "barbell back squat", "front squat", "front squats"], context: context, preferredUnit: preferredUnit), scale: 100, id: Leaderboards.maxSquat)
                push("Max Deadlift", value: maxWeight(for: ["deadlift", "deadlifts", "barbell deadlift", "romanian deadlift", "rdl"], context: context, preferredUnit: preferredUnit), scale: 100, id: Leaderboards.maxDeadlift)
                push("Best Session Volume", value: bestSessionVolume(context: context, preferredUnit: preferredUnit), scale: 1, id: Leaderboards.bestSessionVolume)
                push("Longest Run (m)", value: longestRunMeters(context: context), scale: 1, id: Leaderboards.longestRunMeters)
                push("Fastest 5K (s)", value: fastest5kSeconds(context: context), scale: 1, id: Leaderboards.fastest5kSeconds)

                group.notify(queue: .main) {
                    completion?(results)
                }
            } else {
                // Older iOS versions fallback omitted; app targets modern iOS
            }
        }
        #endif
    }

    // MARK: - Verify scores helper (loads local player's scores for boards)
    @available(iOS 14.0, *)
    static func fetchMyScores(completion: @escaping ([String: Int?], Error?) -> Void) {
        ensureAuthenticated { ok in
            guard ok else { completion([:], NSError(domain: "GameCenter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])) ; return }
            let ids = [Leaderboards.maxBench, Leaderboards.maxSquat, Leaderboards.maxDeadlift, Leaderboards.bestSessionVolume, Leaderboards.longestRunMeters, Leaderboards.fastest5kSeconds]
            GKLeaderboard.loadLeaderboards(IDs: ids) { boards, error in
                if let error { completion([:], error); return }
                guard let boards else { completion([:], nil); return }
                var results: [String: Int?] = [:]
                let group = DispatchGroup()
                for b in boards {
                    group.enter()
                    b.loadEntries(for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 1)) { local, _, _, err in
                        let key = b.baseLeaderboardID
                        if let err { results[key] = nil; print("Load entry error for \(key): \(err.localizedDescription)") }
                        else if let score = local?.score { results[key] = score }
                        else { results[key] = nil }
                        group.leave()
                    }
                }
                group.notify(queue: .main) { completion(results, nil) }
            }
        }
    }
}
