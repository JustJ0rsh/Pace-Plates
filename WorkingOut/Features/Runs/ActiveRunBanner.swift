import SwiftUI

/// Only this small view observes the one-second duration updates.
struct ActiveRunBanner: View {
    let activityName: (String) -> String
    let activityIcon: (String) -> String
    let onResume: (String) -> Void
    @State private var tracker = RunTracker.shared

    var body: some View {
        if tracker.isRunning || (tracker.duration > 0 && tracker.startDate != nil) {
            Button { onResume(tracker.activityType) } label: {
                HStack(spacing: 12) {
                    Image(systemName: activityIcon(tracker.activityType))
                        .foregroundStyle(AppTheme.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active \(activityName(tracker.activityType)) In Progress").font(.headline)
                        Text("\(durationText)  •  \(distanceText)")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryTextColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryTextColor)
                }
                .padding(12).background(AppTheme.secondaryBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var durationText: String {
        let seconds = Int(max(0, tracker.duration))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var distanceText: String {
        String(format: "%.2f %@", tracker.distance / (tracker.distanceUnit == "km" ? 1000 : 1609.34), tracker.distanceUnit)
    }
}
