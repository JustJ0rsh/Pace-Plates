import SwiftUI

struct HealthAuthorizationBanner: View {
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .foregroundStyle(.red)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Health Access Limited")
                    .font(.headline)
                Text("Some Health permissions are missing. Open Settings to enable access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Settings") { onOpenSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding([.horizontal, .top])
    }
}

#Preview {
    HealthAuthorizationBanner(onOpenSettings: {})
        .padding()
}
