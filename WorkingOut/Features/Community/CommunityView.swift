import SwiftUI
#if canImport(GameKit)
import GameKit
import UIKit
#endif
import SwiftData

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: String = "lbs"

    var body: some View {
        NavigationStack {
            List {
                Section("Leaderboards") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Compete on lifts, volume, and running.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text("Max Bench • Squat • Deadlift")
                            Text("Best Session Volume")
                            Text("Longest Run • Fastest 5K")
                        }
                        .font(.subheadline)
                        HStack {
                            if GKLocalPlayer.local.isAuthenticated {
                                Text("Signed in as \(GKLocalPlayer.local.displayName)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Not signed into Game Center")
                                    .font(.footnote).foregroundStyle(.orange)
                                Spacer()
                                Button {
                                    // Prompt to enable Game Center
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: { Label("Open Settings", systemImage: "gear") }
                                .buttonStyle(.bordered)
                            }
                        }
                        Button {
                            GameCenterService.submitAllMetrics(context: modelContext, preferredUnit: weightUnit) { results in
                                var lines: [String] = []
                                for (label, err) in results.sorted(by: { $0.key < $1.key }) {
                                    lines.append("\(label): \(err == nil ? "OK" : (err!.localizedDescription))")
                                }
                                // After submit, verify scores we see for this player
                                if #available(iOS 14.0, *) {
                                    GameCenterService.fetchMyScores { scores, _ in
                                        var verify: [String] = ["— My Scores —"]
                                        for (id, val) in scores.sorted(by: { $0.key < $1.key }) {
                                            verify.append("\(id): \(val != nil ? String(val!) : "None")")
                                        }
                                        showSignInError = (lines + verify).joined(separator: "\n")
                                    }
                                } else {
                                    showSignInError = lines.joined(separator: "\n")
                                }
                            }
                        } label: { Label("Update Leaderboards", systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(.borderedProminent)
                        Button { presentLeaderboards() } label: { Label("View Leaderboards", systemImage: "list.number") }
                            .buttonStyle(.bordered)
                    }
                }

                Section("Groups & Challenges") {
                    NavigationLink { GroupsPlaceholderView() } label: { Label("My Groups", systemImage: "person.3.fill") }
                    NavigationLink { ChallengesPlaceholderView() } label: { Label("Challenges", systemImage: "flag.checkered") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Community")
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert("Game Center", isPresented: Binding(get: { showSignInError != nil }, set: { if !$0 { showSignInError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(showSignInError ?? "") }
            .onAppear {
                #if canImport(GameKit)
                if #available(iOS 14.0, *) {
                    GKAccessPoint.shared.location = .topLeading
                    GKAccessPoint.shared.isActive = true
                }
                // Auto-authenticate on entering Community
                GameCenterService.ensureAuthenticated { ok in
                    if !ok {
                        DispatchQueue.main.async {
                            showSignInError = "Please enable Game Center in Settings and sign in."
                        }
                    }
                }
                #endif
            }
            .onDisappear {
                #if canImport(GameKit)
                if #available(iOS 14.0, *) {
                    GKAccessPoint.shared.isActive = false
                }
                #endif
            }
        }
    }

    private func signInTapped() {
        #if canImport(GameKit)
        if GKLocalPlayer.local.isAuthenticated {
            showSignInError = "Already signed in as \(GKLocalPlayer.local.displayName)."
            return
        }
        isAuthenticating = true
        GameCenterService.ensureAuthenticated { ok in
            isAuthenticating = false
            if ok {
                if #available(iOS 14.0, *) {
                    GKAccessPoint.shared.location = .topLeading
                    GKAccessPoint.shared.isActive = true
                }
            } else {
                showSignInError = "Please sign in to Game Center in Settings > Game Center, then return here."
            }
        }
        #else
        showSignInError = "GameKit not available on this build."
        #endif
    }

    private func presentLeaderboards() {
        #if canImport(GameKit)
        if !GKLocalPlayer.local.isAuthenticated {
            GameCenterService.ensureAuthenticated { ok in
                DispatchQueue.main.async {
                    if ok { presentLeaderboards() } else { showSignInError = "Sign into Game Center first." }
                }
            }
            return
        }
        if #available(iOS 26, *) {
            // Use overlay on newer iOS; if service is unavailable, show a hint
            GKAccessPoint.shared.location = .topLeading
            GKAccessPoint.shared.isActive = true
            if !GKAccessPoint.shared.isPresentingGameCenter {
                GKAccessPoint.shared.trigger(handler: { })
            }
        } else {
            GameCenterService.presentLeaderboardsDashboardLegacy()
        }
        #endif
    }
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
            ContentUnavailableView("Coming Soon", systemImage: "flag.checkered", description: Text("Leaderboards, streaks, trophies via Game Center."))
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
