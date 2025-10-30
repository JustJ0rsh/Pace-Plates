import SwiftUI

struct TutorialView: View {
    var onFinish: (() -> Void)?

    @State private var page: Int = 0

    var body: some View {
        VStack(spacing: 20) {
            TabView(selection: $page) {
                tutorialPage(
                    title: "Welcome to WorkingOut",
                    icon: "sparkles",
                    bullets: [
                        "Track workouts, runs, and weight — no account needed",
                        "Quick, readable charts",
                        "Private by default; optional iCloud sync"
                    ]
                ).tag(0)

                tutorialPage(
                    title: "Workouts",
                    icon: "dumbbell",
                    bullets: [
                        "Tap + to start a Gym Session and Add Exercise",
                        "Tap a set to edit reps & weight",
                        "Click Add Set to duplicate the privious one"
                    ]
                ).tag(1)

                tutorialPage(
                    title: "Runs",
                    icon: "figure.run",
                    bullets: [
                        "Tap + to track; Smart watch runs import automatically from the health app",
                        "See Total Steps per day and an estimated calorie burn per run",
                        "Routes are shown on the map (colored by pace)"
                    ]
                ).tag(2)

                tutorialPage(
                    title: "Weight",
                    icon: "scalemass",
                    bullets: [
                        "Log weight with + in lbs or kg",
                        "Switch Metric/Imperial — history converts automatically",
                        "Progress shown with every entry"
                    ]
                ).tag(3)

                tutorialPage(
                    title: "Goals & Backup",
                    icon: "target",
                    bullets: [
                        "Set goal weight and choose Lose / Maintain / Gain",
                        "Units, profile, and privacy policy in the Settings",
                        "Export/Import backups any time"
                    ]
                ).tag(4)

                tutorialPage(
                    title: "Permissions",
                    icon: "hand.raised",
                    bullets: [
                        "After this tutorial we’ll ask for Health access",
                        "Location prompt shows on Runs (for routes & weather)",
                        "Live Activity while running is optional"
                    ]
                ).tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                Button("Skip") { onFinish?() }
                    .foregroundStyle(.secondary)
                Spacer()
                if page < 5 {
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
