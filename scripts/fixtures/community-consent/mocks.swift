import Foundation

// Inert test doubles only: this harness never imports GameKit or UIKit.
final class UserDefaults {
    static let standard = UserDefaults()
    private var values: [String: Bool] = [:]
    func bool(forKey key: String) -> Bool { values[key] ?? false }
    func set(_ value: Bool, forKey key: String) { values[key] = value }
}
class UIViewController: NSObject {
    var presentedViewController: UIViewController?
    func present(_ controller: UIViewController, animated: Bool) {}
}
final class UINavigationController: UIViewController { var visibleViewController: UIViewController? }
final class UITabBarController: UIViewController { var selectedViewController: UIViewController? }
class UIScene: NSObject {}
final class UIWindowScene: UIScene { var windows: [UIWindow] = [] }
final class UIWindow: NSObject { var isKeyWindow = false; var rootViewController: UIViewController? }
final class UIApplication { static let shared = UIApplication(); var connectedScenes: [UIScene] = [] }
enum GKGameCenterViewControllerState { case leaderboards, achievements }
final class GKLocalPlayer: NSObject {
    static let local = GKLocalPlayer()
    var isAuthenticated = false
    var authenticateHandler: ((UIViewController?, Error?) -> Void)?
}
final class GKAccessPoint: NSObject {
    enum Location { case topTrailing }
    static let shared = GKAccessPoint()
    var isActive = false
    var location = Location.topTrailing
    @objc dynamic var isPresentingGameCenter = false
    func trigger(state: GKGameCenterViewControllerState, handler: () -> Void) { handler() }
}
enum GKLeaderboard {
    static var sent: [Int] = []
    static func submitScore(_ score: Int, context: Int, player: GKLocalPlayer, leaderboardIDs: [String], completionHandler: (Error?) -> Void) {
        sent.append(score); completionHandler(nil)
    }
}
final class GKAchievement {
    static var pendingLoad: (([GKAchievement]?, Error?) -> Void)?
    static var sent: [[GKAchievement]] = []
    let identifier: String
    var percentComplete: Double = 0
    var showsCompletionBanner = false
    var isCompleted: Bool { percentComplete >= 100 }
    init(identifier: String) { self.identifier = identifier }
    static func loadAchievements(completionHandler: @escaping ([GKAchievement]?, Error?) -> Void) { pendingLoad = completionHandler }
    static func report(_ achievements: [GKAchievement], completionHandler: (Error?) -> Void) { sent.append(achievements); completionHandler(nil) }
}
final class WorkoutSession { var executionStatusRaw = "legacy_recorded"; var sourceTemplateID: UUID? }
final class ExerciseLog {
    var isCompleted = true; var workoutSession: WorkoutSession?; var exerciseType: String? = "strength"
    var reps = 1; var weight = 1.0; var exerciseName: String? = "bench"; var weightUnit = "lbs"; var effectiveReps = 1
}
