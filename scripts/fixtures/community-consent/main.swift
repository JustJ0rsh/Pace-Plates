import Foundation
var count = 0
var failures: [String] = []
func check(_ predicate: @autoclosure () -> Bool, _ name: String) {
    count += 1
    if !predicate() { failures.append(name); print("FAIL: \(name)") }
    else { print("PASS: \(name)") }
}
let service = GameCenterService.shared
func optedInUnauthenticated() {
    service.disableCommunityAccess()
    GKLocalPlayer.local.isAuthenticated = false
    service.enableCommunityAccessAndAuthenticate()
    GKLocalPlayer.local.authenticateHandler?(nil, nil)
    GKLocalPlayer.local.authenticateHandler = nil
    GKLeaderboard.sent = []; GKAchievement.sent = []; GKAchievement.pendingLoad = nil
}
// Disabled requests cannot begin authentication or load achievements.
service.disableCommunityAccess(); GKLocalPlayer.local.authenticateHandler = nil
service.reportScore(10, to: "test")
check(GKLocalPlayer.local.authenticateHandler == nil && GKLeaderboard.sent.isEmpty, "disabled score does not authenticate or submit")
StreakService.reportAchievements(dailyStreak: 7, weeklyStreak: 4)
check(GKAchievement.pendingLoad == nil && GKAchievement.sent.isEmpty, "disabled achievement does not load or report")
// Explicit opt-in can submit new data.
optedInUnauthenticated()
service.reportScore(11, to: "test")
check(GKLocalPlayer.local.authenticateHandler != nil, "enabled score waits for authentication")
GKLocalPlayer.local.isAuthenticated = true
GKLocalPlayer.local.authenticateHandler?(nil, nil)
check(GKLeaderboard.sent == [11], "enabled authenticated score submits once")
// Pending score must be invalidated by disabling, even if reenabled later.
optedInUnauthenticated(); service.reportScore(12, to: "test")
let disabledAuth = GKLocalPlayer.local.authenticateHandler!
service.disableCommunityAccess(); GKLocalPlayer.local.isAuthenticated = true; disabledAuth(nil, nil)
check(GKLeaderboard.sent.isEmpty, "disable cancels pending score submission")
optedInUnauthenticated(); service.reportScore(13, to: "test")
let oldAuth = GKLocalPlayer.local.authenticateHandler!
service.disableCommunityAccess(); service.enableCommunityAccessAndAuthenticate()
GKLocalPlayer.local.isAuthenticated = true; oldAuth(nil, nil)
check(GKLeaderboard.sent.isEmpty, "disable and reenable never revives old score")
// Achievement computation/reporting must obey the same consent boundary.
optedInUnauthenticated(); StreakService.reportAchievements(dailyStreak: 7, weeklyStreak: 4)
check(GKAchievement.pendingLoad != nil, "enabled achievements wait for load")
let disabledLoad = GKAchievement.pendingLoad!
service.disableCommunityAccess(); disabledLoad([], nil)
check(GKAchievement.sent.isEmpty, "disable cancels pending achievement report")
optedInUnauthenticated(); StreakService.reportAchievements(dailyStreak: 7, weeklyStreak: 4)
let oldLoad = GKAchievement.pendingLoad!
service.disableCommunityAccess(); service.enableCommunityAccessAndAuthenticate(); oldLoad([], nil)
check(GKAchievement.sent.isEmpty, "disable and reenable never revives old achievements")
GKAchievement.sent = []; StreakService.reportAchievements(dailyStreak: 7, weeklyStreak: 4)
GKAchievement.pendingLoad?([], nil)
check(GKAchievement.sent.count == 1 && !GKAchievement.sent[0].isEmpty, "fresh enabled achievement report still works")
// Platform completions may be synchronous and reenter opt-out.
optedInUnauthenticated(); GKLocalPlayer.local.isAuthenticated = true
service.reportScore(14, to: "test") { _ in service.disableCommunityAccess() }
check(GKLeaderboard.sent == [14] && !service.isCommunityAccessEnabled, "synchronous completion can opt out without deadlock")
service.reportScore(15, to: "test")
check(GKLeaderboard.sent == [14], "submission stays disabled after reentrant opt-out")
// Legacy direct reporting API must also respect disabled state.
service.disableCommunityAccess(); GKAchievement.sent = []
service.updateStreakAchievements(dailyStreak: 7, weeklyStreak: 4)
check(GKAchievement.sent.isEmpty, "disabled direct achievement reporting cannot submit")
service.enableCommunityAccessAndAuthenticate(); GKAchievement.sent = []
service.updateStreakAchievements(dailyStreak: 7, weeklyStreak: 4)
check(GKAchievement.sent.count == 1 && GKAchievement.sent[0].count == StreakService.dailyThresholds.count + StreakService.weeklyThresholds.count,
      "enabled direct achievement reporting retains all thresholds")
print("\(count) assertions, \(failures.count) failures")
if !failures.isEmpty { exit(1) }
