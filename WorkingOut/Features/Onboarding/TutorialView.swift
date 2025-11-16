import SwiftUI

struct TutorialView: View {
    var onFinish: (() -> Void)?

    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                tutorialPage(
                    title: "Welcome to Pace & Plates",
                    icon: "sparkles",
                    bullets: [
                        "Your complete fitness companion for workouts, runs, and nutrition tracking",
                        "Beautiful charts and insights with no account required",
                        "Privacy-first with optional iCloud sync across devices"
                    ]
                ).tag(0)

                tutorialPage(
                    title: "Smart Workouts",
                    icon: "dumbbell.fill",
                    bullets: [
                        "Track strength and cardio exercises in one place",
                        "Add notes to each set for progress tracking",
                        "Use built-in templates or create custom workouts",
                        "See your lifting volume and progress charts"
                    ]
                ).tag(1)

                tutorialPage(
                    title: "AI Workout Planning",
                    icon: "sparkles",
                    bullets: [
                        "Get personalized workout plans powered by Apple Intelligence",
                        "Plans adapt to your experience level and goals",
                        "Save and reuse your favorite workout routines",
                        "Export plans as templates for future sessions"
                    ]
                ).tag(2)

                tutorialPage(
                    title: "Running & Cardio",
                    icon: "figure.run",
                    bullets: [
                        "GPS tracking with pace-colored routes on the map",
                        "Apple Watch runs import automatically",
                        "Track cycling, hiking, and rowing workouts",
                        "Live Activity support for at-a-glance stats"
                    ]
                ).tag(3)

                tutorialPage(
                    title: "Home Dashboard",
                    icon: "house.fill",
                    bullets: [
                        "View streaks and workout calendar at a glance",
                        "Track daily steps, sleep, and vital health metrics",
                        "See current weather for outdoor workouts",
                        "Earn Game Center achievements for consistency"
                    ]
                ).tag(4)

                tutorialPage(
                    title: "Weight & Nutrition",
                    icon: "scalemass.fill",
                    bullets: [
                        "Log weight in lbs or kg with automatic unit conversion",
                        "Set goals: lose, maintain, or gain weight",
                        "Track progress with visual charts",
                        "Get weekly reminders to stay consistent"
                    ]
                ).tag(5)

                tutorialPage(
                    title: "Permissions",
                    icon: "hand.raised.fill",
                    bullets: [
                        "Health access enables workout and run sync",
                        "Location is used for GPS routes and weather",
                        "Notifications for weekly weight reminders (optional)",
                        "All data stays on your device unless you enable iCloud"
                    ]
                ).tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                Button("Skip") { onFinish?() }
                    .foregroundStyle(.secondary)
                Spacer()
                if page < 6 {
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { onFinish?() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
    }

    @ViewBuilder
    private func tutorialPage(title: String, icon: String, bullets: [String]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
            Text(title)
                .font(.title2).bold()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentColor)
                        Text(line).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal)
    }
}

#Preview {
    TutorialView()
}
