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

    private func signInTapped() { showSignInError = nil }
}
