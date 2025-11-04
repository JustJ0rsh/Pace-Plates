import Foundation
import SwiftData
#if canImport(GameKit)
import GameKit
import UIKit
#endif

enum Leaderboards {
    // Replace these IDs with your App Store Connect leaderboard identifiers
    static let maxBench = "max_bench"
    static let maxSquat = "max_squat"
    static let maxDeadlift = "max_deadlift"
    static let bestSessionVolume = "best_session_volume"
    static let longestRunMeters = "longest_run_m"
    static let fastest5kSeconds = "fastest_5k_s"
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
    private static func submitInt(_ value: Int, leaderboardID: String) {
        GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [leaderboardID]) { error in
            if let error { print("GK submit error (\(leaderboardID)): \(error.localizedDescription)") }
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
        let nameSet = Set(names.map { $0.lowercased() })
        var bestKg: Double = 0
        for l in logs {
            let lname = (l.exerciseName ?? "").lowercased()
            if nameSet.contains(lname) {
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
                let kg = log.weightUnit == "kg" ? log.weight : (log.weight / 2.20462)
                return acc + Double(log.reps) * kg
            }
            if volKg > best { best = volKg }
        }
        return best <= 0 ? nil : (preferredUnit == "kg" ? best : best * 2.20462)
    }

    static func longestRunMeters(context: ModelContext) -> Double? {
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        let meters = runs.map { $0.distanceUnit == "mi" ? ($0.distance * 1609.34) : ($0.distance * 1000.0) }.max() ?? 0
        return meters > 0 ? meters : nil
    }

    static func fastest5kSeconds(context: ModelContext) -> Double? {
        let runs: [RunningSession] = (try? context.fetch(FetchDescriptor<RunningSession>())) ?? []
        var best: Double = .greatestFiniteMagnitude
        for r in runs {
            let km = r.distanceUnit == "mi" ? (r.distance * 1.60934) : r.distance
            guard km > 0, r.duration > 0 else { continue }
            let factor = 5.0 / km
            let est = r.duration * factor
            if est < best { best = est }
        }
        return best == .greatestFiniteMagnitude ? nil : best
    }

    static func submitAllMetrics(context: ModelContext, preferredUnit: String) {
        #if canImport(GameKit)
        ensureAuthenticated { ok in
            guard ok else { print("GK submit aborted: not authenticated"); return }
            if #available(iOS 14.0, *) {
                if let bench = maxWeight(for: ["bench press", "incline bench press", "decline bench press"], context: context, preferredUnit: preferredUnit) { submitInt(scaledInt(bench, scale: 100), leaderboardID: Leaderboards.maxBench) }
                if let squat = maxWeight(for: ["squats", "front squats"], context: context, preferredUnit: preferredUnit) { submitInt(scaledInt(squat, scale: 100), leaderboardID: Leaderboards.maxSquat) }
                if let deadlift = maxWeight(for: ["deadlifts"], context: context, preferredUnit: preferredUnit) { submitInt(scaledInt(deadlift, scale: 100), leaderboardID: Leaderboards.maxDeadlift) }
                if let volume = bestSessionVolume(context: context, preferredUnit: preferredUnit) { submitInt(scaledInt(volume, scale: 1), leaderboardID: Leaderboards.bestSessionVolume) }
                if let longest = longestRunMeters(context: context) { submitInt(scaledInt(longest, scale: 1), leaderboardID: Leaderboards.longestRunMeters) }
                if let fastest = fastest5kSeconds(context: context) { submitInt(scaledInt(fastest, scale: 1), leaderboardID: Leaderboards.fastest5kSeconds) }
            } else {
                // Older iOS versions fallback omitted; app targets modern iOS
            }
        }
        #endif
    }
}

