import SwiftUI

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @State private var didRequestGameCenterAccess = false

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
            didRequestGameCenterAccess = true
            isAuthenticating = true

            GameCenterService.shared.enableCommunityAccessAndAuthenticate { error in
                isAuthenticating = false
                if let error {
                    showSignInError = error.localizedDescription
                }
            }
        }
    }
}
