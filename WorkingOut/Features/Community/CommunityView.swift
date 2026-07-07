import SwiftUI

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @State private var authTimeoutTask: Task<Void, Never>?
    // Drives which state (explainer vs. enabled) is shown. Seeded from the
    // persisted opt-in flag so existing opted-in users see the enabled UI.
    @State private var isCommunityEnabled = GameCenterService.shared.isCommunityAccessEnabled

    var body: some View {
        List {
            if isCommunityEnabled {
                enabledContent
            } else {
                explainerContent
            }
        }
        .disabled(isAuthenticating)
        .overlay {
            if isAuthenticating {
                ProgressView("Connecting to Game Center...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .alert("Notice", isPresented: Binding(get: { showSignInError != nil }, set: { if !$0 { showSignInError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(showSignInError ?? "") }
        .onDisappear {
            authTimeoutTask?.cancel()
        }
    }

    // MARK: - Opted-out explainer

    @ViewBuilder
    private var explainerContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Community & Game Center", systemImage: "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.textColor)

                Text("Enabling Community connects the app to Apple's Game Center. When it's on, the app can:")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryTextColor)

                VStack(alignment: .leading, spacing: 8) {
                    explainerRow(icon: "rosette", text: "Post your PRs, best runs, and session volume to leaderboards.")
                    explainerRow(icon: "trophy.fill", text: "Track streak achievements in Game Center.")
                    explainerRow(icon: "person.crop.circle.badge.checkmark", text: "Sign you in with your Apple Game Center account.")
                }

                Text("Nothing is shared until you turn this on, and you can disable it again at any time.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }
            .padding(.vertical, 4)
        }

        Section {
            Button {
                enableCommunity()
            } label: {
                Label("Enable Community Features", systemImage: "checkmark.seal.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentColor)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private func explainerRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.accentColor)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textColor)
        }
    }

    // MARK: - Opted-in content

    @ViewBuilder
    private var enabledContent: some View {
        Section("Game Center") {
            Button {
                GameCenterService.shared.presentLeaderboards()
            } label: { Label("Leaderboards", systemImage: "rosette") }

            Button {
                GameCenterService.shared.presentAchievements()
            } label: { Label("Achievements", systemImage: "trophy.fill") }
        }

        Section {
            Button(role: .destructive) {
                disableCommunity()
            } label: {
                Label("Disable Community Features", systemImage: "xmark.circle")
            }
        } footer: {
            Text("Turns off Game Center and stops uploading scores and achievements. Your existing Game Center data isn't deleted by the app.")
        }
    }

    // MARK: - Opt-in / opt-out

    private func enableCommunity() {
        isAuthenticating = true

        authTimeoutTask?.cancel()
        authTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled, isAuthenticating else { return }
            isAuthenticating = false
            showSignInError = "Game Center is taking longer than expected. You can keep using the app and try again from Leaderboards or Achievements."
        }

        GameCenterService.shared.enableCommunityAccessAndAuthenticate { error in
            Task { @MainActor in
                authTimeoutTask?.cancel()
                isAuthenticating = false
                isCommunityEnabled = GameCenterService.shared.isCommunityAccessEnabled
                if let error {
                    showSignInError = error.localizedDescription
                }
            }
        }
    }

    private func disableCommunity() {
        authTimeoutTask?.cancel()
        isAuthenticating = false
        GameCenterService.shared.disableCommunityAccess()
        isCommunityEnabled = false
    }
}
