import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Attributes
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

// MARK: - Live Activity Widget
@available(iOS 16.1, *)
struct RunningLiveActivity: Widget {
    let kind: String = "Jorsh.WorkingOut.RunningWidget"

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunningActivityAttributes.self) { context in
            // Lock screen/banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Distance", systemImage: "figure.run")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.formattedDistance) \(context.state.distanceUnit)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("Pace", systemImage: "speedometer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.formattedPace)/\(context.state.distanceUnit)")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text("Active Run")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.state.formattedDuration)
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        // Progress indicator
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .foregroundColor(.green)
                            Text("Running")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        // Live indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                }
            } compactLeading: {
                // Compact leading (left side of Dynamic Island)
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
            } compactTrailing: {
                // Compact trailing (right side of Dynamic Island)
                Text(context.state.formattedDuration)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } minimal: {
                // Minimal view (when multiple activities are active)
                Image(systemName: "figure.run")
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Lock Screen View
@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RunningActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "figure.run.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
                Text(context.attributes.title)
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
            
            // Main stats
            HStack(spacing: 16) {
                // Distance
                VStack(alignment: .leading, spacing: 4) {
                    Label("Distance", systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(context.state.formattedDistance)
                            .font(.title2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text(context.state.distanceUnit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Duration
                VStack(spacing: 4) {
                    Label("Time", systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(context.state.formattedDuration)
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                
                // Pace
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Pace", systemImage: "speedometer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(context.state.formattedPace)
                            .font(.title2)
                            .fontWeight(.bold)
                            .monospacedDigit()
                        Text("/\(context.state.distanceUnit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.3))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Widget Registration
// Note: Live Activities don't need a WidgetBundle with @main when embedded in the app.
// The ActivityConfiguration is automatically discovered by ActivityKit when
// Activity.request() is called in LiveActivityManager. The widget UI is rendered
// by the system based on this configuration.

