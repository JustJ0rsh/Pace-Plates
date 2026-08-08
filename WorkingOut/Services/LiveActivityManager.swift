import Foundation
import SwiftUI

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct RunningActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startDate: Date
        var duration: TimeInterval
        var distanceMeters: Double
        var paceSecondsPerUnit: Double?
        var distanceUnit: String // "km" or "mi"
        var isPaused: Bool
        var timerReferenceDate: Date // Date() - duration; used by Text(date, style: .timer)
        
        // Computed properties for display
        var distanceInUnits: Double {
            distanceUnit == "km" ? distanceMeters / 1000.0 : distanceMeters / 1609.34
        }
        
        var formattedDuration: String {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            let seconds = Int(duration) % 60
            
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%02d:%02d", minutes, seconds)
            }
        }
        
        var formattedPace: String {
            guard let pace = paceSecondsPerUnit, pace > 0 && pace.isFinite else {
                return "--:--"
            }
            let mins = Int(pace / 60)
            let secs = Int(pace.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d", mins, secs)
        }
        
        var formattedDistance: String {
            String(format: "%.2f", distanceInUnits)
        }
    }

    var title: String
}

@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var activity: Activity<RunningActivityAttributes>?

    private init() {}

    private var activeActivities: [Activity<RunningActivityAttributes>] {
        var activities = Activity<RunningActivityAttributes>.activities
        if let activity, !activities.contains(where: { $0.id == activity.id }) {
            activities.append(activity)
        }
        return activities
    }

    private func adoptSystemActivityIfNeeded() {
        guard activity == nil else { return }
        activity = Activity<RunningActivityAttributes>.activities.first
    }

    func start(startDate: Date, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String, activityType: String = "running") {
        // End any existing activity first
        end()
        guard !AppLaunchConfiguration.current.isUITest else { return }
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are not enabled")
            return
        }
        
        // Map activity type to display title
        let titleText: String
        switch activityType {
        case "walking":
            titleText = "Active Walk"
        case "hiking":
            titleText = "Active Hike"
        default: // "running"
            titleText = "Active Run"
        }
        
        let attributes = RunningActivityAttributes(title: titleText)
        let content = RunningActivityAttributes.ContentState(
            startDate: startDate,
            duration: 0,
            distanceMeters: distanceMeters,
            paceSecondsPerUnit: paceSecondsPerUnit,
            distanceUnit: distanceUnit,
            isPaused: false,
            timerReferenceDate: startDate
        )
        
        do {
            let staleDate = Date().addingTimeInterval(3600) // 1 hour from now
            let activityContent = ActivityContent(state: content, staleDate: staleDate)
            activity = try Activity.request(attributes: attributes, content: activityContent, pushType: nil)
            print("✅ Live Activity started successfully")
        } catch {
            print("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func update(startDate: Date, duration: TimeInterval, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String, isPaused: Bool = false) {
        guard !AppLaunchConfiguration.current.isUITest else { return }

        adoptSystemActivityIfNeeded()
        guard let activity else {
            print("⚠️ No active Live Activity to update")
            return
        }

        let content = RunningActivityAttributes.ContentState(
            startDate: startDate,
            duration: duration,
            distanceMeters: distanceMeters,
            paceSecondsPerUnit: paceSecondsPerUnit,
            distanceUnit: distanceUnit,
            isPaused: isPaused,
            timerReferenceDate: Date().addingTimeInterval(-duration)
        )
        
        Task {
            let staleDate = Date().addingTimeInterval(3600) // 1 hour from now
            await activity.update(ActivityContent(state: content, staleDate: staleDate))
        }
    }

    func end() {
        guard !AppLaunchConfiguration.current.isUITest else {
            activity = nil
            return
        }

        let activitiesToEnd = activeActivities
        guard !activitiesToEnd.isEmpty else {
            activity = nil
            return
        }

        Task {
            for activity in activitiesToEnd {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            print("✅ Live Activity ended immediately")
        }
        
        self.activity = nil
    }

    func reconcileActivities(hasRecoverableRun: Bool) {
        guard !AppLaunchConfiguration.current.isUITest else {
            activity = nil
            return
        }

        if hasRecoverableRun {
            adoptSystemActivityIfNeeded()
            return
        }

        end()
    }
    
    var isActive: Bool {
        guard !AppLaunchConfiguration.current.isUITest else { return false }
        adoptSystemActivityIfNeeded()
        return activity != nil
    }
}
#else
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}
    func start(startDate: Date, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String, activityType: String = "running") {}
    func update(startDate: Date, duration: TimeInterval, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String, isPaused: Bool = false) {}
    func end() {}
    func reconcileActivities(hasRecoverableRun: Bool) {}
    var isActive: Bool { false }
}
#endif
