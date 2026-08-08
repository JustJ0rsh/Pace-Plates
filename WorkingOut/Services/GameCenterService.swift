import Foundation
import GameKit
import UIKit

final class GameCenterService: NSObject {
    static let shared = GameCenterService()
    private static let communityAccessKey = "gameCenterCommunityAccessEnabled"

    private(set) var isAuthenticated: Bool = GKLocalPlayer.local.isAuthenticated
    private var apObserver: NSKeyValueObservation? = nil

    private override init() { }

    var isCommunityAccessEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.communityAccessKey)
    }

    /// Clears the opt-in flag and deactivates the Game Center Access Point so no
    /// further scores/achievements are uploaded and the on-screen dot is hidden.
    func disableCommunityAccess() {
        UserDefaults.standard.set(false, forKey: Self.communityAccessKey)
        apObserver?.invalidate()
        apObserver = nil
        GKAccessPoint.shared.isActive = false
    }

    // MARK: - Authentication
    func authenticate(presenting viewController: UIViewController? = nil, completion: ((Error?) -> Void)? = nil) {
        guard isCommunityAccessEnabled else { completion?(nil); return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] authVC, error in
            if let authVC {
                if let presenter = viewController ?? GameCenterService.topViewController() {
                    presenter.present(authVC, animated: true)
                }
            } else {
                self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                completion?(error)
            }
        }
    }

    func enableCommunityAccessAndAuthenticate(
        presenting viewController: UIViewController? = nil,
        completion: ((Error?) -> Void)? = nil
    ) {
        UserDefaults.standard.set(true, forKey: Self.communityAccessKey)

        if isAuthenticated || GKLocalPlayer.local.isAuthenticated {
            completion?(nil)
            return
        }

        authenticate(presenting: viewController, completion: completion)
    }

    // MARK: - UI Presentation (modern: Access Point trigger, no deprecated controllers)
    func presentLeaderboards(leaderboardID: String? = nil, from presenter: UIViewController? = nil) {
        guard isCommunityAccessEnabled else { return }
        guard isAuthenticated || GKLocalPlayer.local.isAuthenticated else {
            authenticate(presenting: presenter) { [weak self] error in
                guard error == nil, GKLocalPlayer.local.isAuthenticated else { return }
                self?.presentLeaderboards(leaderboardID: leaderboardID, from: presenter)
            }
            return
        }

        presentAccessPoint(state: .leaderboards)
    }

    func presentAchievements(from presenter: UIViewController? = nil) {
        guard isCommunityAccessEnabled else { return }
        guard isAuthenticated || GKLocalPlayer.local.isAuthenticated else {
            authenticate(presenting: presenter) { [weak self] error in
                guard error == nil, GKLocalPlayer.local.isAuthenticated else { return }
                self?.presentAchievements(from: presenter)
            }
            return
        }

        presentAccessPoint(state: .achievements)
    }

    // MARK: - Score Reporting
    func reportScore(_ value: Int64, to leaderboardID: String, completion: ((Error?) -> Void)? = nil) {
        guard isCommunityAccessEnabled else { return }

        let submit = {
            GKLeaderboard.submitScore(Int(value),
                                      context: 0,
                                      player: GKLocalPlayer.local,
                                      leaderboardIDs: [leaderboardID]) { error in
                completion?(error)
            }
        }

        if isAuthenticated || GKLocalPlayer.local.isAuthenticated {
            submit()
        } else {
            authenticate { _ in submit() }
        }
    }

    // MARK: - Helpers for specific boards
    // Note: Leaderboard vendor identifiers from GameCenterResources.gamekit
    enum Board: String {
        case bench = "Bench"
        case squat = "Squat"
        case deadlift = "Deadlift"
        case bestSessionVolume = "Best_Session_Volume"
        case longestRun = "Longest_Run"
        case fastestRun = "Fastest_Run"
    }

    // MARK: - Achievements (streaks)
    func updateStreakAchievements(dailyStreak: Int, weeklyStreak: Int) {
        var achievements: [GKAchievement] = []

        // Daily streaks
        for t in StreakService.dailyThresholds {
            let id = String(format: "streak_days_%03d", t)
            let a = GKAchievement(identifier: id)
            let pct = min(100.0, (Double(dailyStreak) / Double(t)) * 100.0)
            a.percentComplete = pct
            a.showsCompletionBanner = true
            achievements.append(a)
        }

        // Weekly streaks
        for t in StreakService.weeklyThresholds {
            let id = String(format: "streak_weeks_%03d", t)
            let a = GKAchievement(identifier: id)
            let pct = min(100.0, (Double(weeklyStreak) / Double(t)) * 100.0)
            a.percentComplete = pct
            a.showsCompletionBanner = true
            achievements.append(a)
        }

        GKAchievement.report(achievements) { error in
            if let error { print("GameCenter: Failed to report achievements: \(error)") }
        }
    }

    // Convert kg to lbs
    private func lbs(from weight: Double, unit: String) -> Double {
        if unit.lowercased() == "kg" { return weight * 2.20462 }
        return weight
    }

    // Submit strength PRs and volume for a given session
    func reportStrengthForSession(exerciseLogs: [ExerciseLog]?, preferredWeightUnit: String = "lbs") {
        guard let logs = exerciseLogs, !logs.isEmpty else { return }

        // Session totals / PRs (in lbs)
        var bestBench: Double = 0
        var bestSquat: Double = 0
        var bestDeadlift: Double = 0
        var sessionVolumeLbs: Double = 0

        for log in logs where (log.isCompleted || log.workoutSession?.sourceTemplateID == nil)
            && (log.exerciseType ?? "strength") == "strength"
            && log.reps > 0
            && log.weight > 0 {
            let name = (log.exerciseName ?? "").lowercased()
            let weightLbs = lbs(from: log.weight, unit: log.weightUnit)
            sessionVolumeLbs += Double(log.effectiveReps) * weightLbs

            if name.contains("bench") { bestBench = max(bestBench, weightLbs) }
            if name.contains("squat") { bestSquat = max(bestSquat, weightLbs) }
            if name.contains("deadlift") { bestDeadlift = max(bestDeadlift, weightLbs) }
        }

        if bestBench > 0 { reportScore(Int64(bestBench.rounded()), to: Board.bench.rawValue) }
        if bestSquat > 0 { reportScore(Int64(bestSquat.rounded()), to: Board.squat.rawValue) }
        if bestDeadlift > 0 { reportScore(Int64(bestDeadlift.rounded()), to: Board.deadlift.rawValue) }
        if sessionVolumeLbs > 0 { reportScore(Int64(sessionVolumeLbs.rounded()), to: Board.bestSessionVolume.rawValue) }
    }

    // Submit run stats for a saved session
    func reportRunStats(distance: Double, distanceUnit: String, duration: TimeInterval) {
        guard distance > 0, duration > 0 else { return }

        // Longest run leaderboard expects miles with 2 decimals (format DECIMAL_POINT_2_PLACE)
        let miles: Double = distanceUnit.lowercased() == "km" ? (distance / 1.60934) : distance
        let longestRunScaled = Int64((miles * 100).rounded())
        if longestRunScaled > 0 { reportScore(longestRunScaled, to: Board.longestRun.rawValue) }

        // Fastest run leaderboard expects pace minutes per mile with 2 decimals, sorted ascending
        let minutesPerMile: Double = (duration / 60.0) / max(miles, 0.0001)
        let fastestScaled = Int64((minutesPerMile * 100).rounded())
        if fastestScaled > 0 { reportScore(fastestScaled, to: Board.fastestRun.rawValue) }
    }

    // MARK: - VC helper
    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        if let base = base {
            if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
            if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
            if let presented = base.presentedViewController { return topViewController(base: presented) }
            return base
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }), let root = window.rootViewController {
                return topViewController(base: root)
            }
        }
        if let scene = scenes.first, let root = scene.windows.first?.rootViewController {
            return topViewController(base: root)
        }
        return nil
    }

    // Ensure Access Point dot is shown only during presentation and restored afterward
    private func presentAccessPoint(state: GKGameCenterViewControllerState) {
        let ap = GKAccessPoint.shared
        ap.location = .topTrailing
        let previous = ap.isActive
        ap.isActive = true

        // Clean up any previous observer
        apObserver?.invalidate()
        apObserver = ap.observe(\.isPresentingGameCenter, options: [.new]) { [weak self] _, change in
            guard let presenting = change.newValue else { return }
            if presenting == false {
                DispatchQueue.main.async {
                    GKAccessPoint.shared.isActive = previous
                }
                self?.apObserver?.invalidate()
                self?.apObserver = nil
            }
        }

        ap.trigger(state: state, handler: {})
    }
}
