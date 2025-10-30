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

    func start(startDate: Date, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String) {
        // End any existing activity first
        end()
        
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are not enabled")
            return
        }
        
        let attributes = RunningActivityAttributes(title: "Active Run")
        let content = RunningActivityAttributes.ContentState(
            startDate: startDate,
            duration: 0,
            distanceMeters: distanceMeters,
            paceSecondsPerUnit: paceSecondsPerUnit,
            distanceUnit: distanceUnit
        )
        
        do {
            let activityContent = ActivityContent(state: content, staleDate: nil)
            activity = try Activity.request(attributes: attributes, content: activityContent, pushType: nil)
            print("✅ Live Activity started successfully")
        } catch {
            print("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func update(startDate: Date, duration: TimeInterval, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String) {
        guard let activity else {
            print("⚠️ No active Live Activity to update")
            return
        }
        
        let content = RunningActivityAttributes.ContentState(
            startDate: startDate,
            duration: duration,
            distanceMeters: distanceMeters,
            paceSecondsPerUnit: paceSecondsPerUnit,
            distanceUnit: distanceUnit
        )
        
        Task {
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    func end() {
        guard let activity else { return }
        
        Task {
            let currentState = activity.content.state
            let finalContent = ActivityContent(state: currentState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .default)
            print("✅ Live Activity ended")
        }
        
        self.activity = nil
    }
    
    var isActive: Bool {
        activity != nil
    }
}
#else
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}
    func start(startDate: Date, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String) {}
    func update(startDate: Date, duration: TimeInterval, distanceMeters: Double, paceSecondsPerUnit: Double?, distanceUnit: String) {}
    func end() {}
    var isActive: Bool { false }
}
#endif




