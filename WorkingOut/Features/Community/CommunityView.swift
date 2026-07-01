import SwiftUI

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @State private var didRequestGameCenterAccess = false
    @State private var authTimeoutTask: Task<Void, Never>?

    var body: some View {
        List {
            Section("Game Center") {
                Button {
                    GameCenterService.shared.presentLeaderboards()
                } label: { Label("Leaderboards", systemImage: "rosette") }

                Button {
                    GameCenterService.shared.presentAchievements()
                } label: { Label("Achievements", systemImage: "trophy.fill") }
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
        .onAppear {
            guard !didRequestGameCenterAccess else { return }
            requestGameCenterAccess()
        }
        .onDisappear {
            authTimeoutTask?.cancel()
        }
    }

    private func requestGameCenterAccess() {
        didRequestGameCenterAccess = true
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
                if let error {
                    showSignInError = error.localizedDescription
                }
            }
        }
    }
}
