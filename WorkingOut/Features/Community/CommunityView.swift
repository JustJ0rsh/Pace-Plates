import SwiftUI
import SwiftData

struct CommunityView: View {
    @State private var showSignInError: String? = nil
    @State private var isAuthenticating = false
    @Environment(\.modelContext) private var modelContext
	    @AppStorage("weightUnit") private var weightUnit: String = "lbs"

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
	        .listStyle(.insetGrouped)
	        .navigationTitle("Community")
	        .navigationBarTitleDisplayMode(.inline)
	        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
	        .toolbarBackground(.visible, for: .navigationBar)
	        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
	        .alert("Notice", isPresented: Binding(get: { showSignInError != nil }, set: { if !$0 { showSignInError = nil } })) {
	            Button("OK", role: .cancel) {}
	        } message: { Text(showSignInError ?? "") }
	        .onAppear { }
	        .onDisappear { }
	    }

    private func signInTapped() { showSignInError = nil }
}
