import SwiftUI
import SwiftData

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"

    var body: some View {
        NavigationStack {
            List {
                // Community landing
                Section("Community") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Groups and challenges coming soon.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Groups & Challenges") {
                    NavigationLink { GroupsPlaceholderView() } label: { Label("My Groups", systemImage: "person.3.fill") }
                    NavigationLink { ChallengesPlaceholderView() } label: { Label("Challenges", systemImage: "flag.checkered") }
                }

                Section("Game Center") {
                    Button {
                        GameCenterService.shared.presentLeaderboards()
                    } label: { Label("Leaderboards", systemImage: "rosette") }

                    Button {
                        GameCenterService.shared.presentAchievements()
                    } label: { Label("Achievements", systemImage: "trophy.fill") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Community")
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Notice", isPresented: Binding(get: { showSignInError != nil }, set: { if !$0 { showSignInError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(showSignInError ?? "") }
            .onAppear { }
            .onDisappear { }
        }
    }

    private func signInTapped() { showSignInError = "Leaderboards are disabled on this branch." }

    private func presentLeaderboards() { }
}

private struct GroupsPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Groups").font(.headline)
            Text("Create or join a group to compare progress with friends for accountability and competition.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            ContentUnavailableView("Coming Soon", systemImage: "person.3.fill", description: Text("Group leaderboards, invites, and private challenges."))
            Spacer()
        }
        .padding()
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
    }
}

private struct ChallengesPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Challenges").font(.headline)
            Text("Compete on max lifts, volume, or running with weekly and monthly challenges.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
            ContentUnavailableView("Coming Soon", systemImage: "flag.checkered", description: Text("Leaderboards, streaks, and trophies."))
            Spacer()
        }
        .padding()
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
    }
}
