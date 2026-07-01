import SwiftUI

struct QuickActionSheetAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let role: ButtonRole?
    let accessibilityIdentifier: String?
    let handler: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        role: ButtonRole? = nil,
        accessibilityIdentifier: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.role = role
        self.accessibilityIdentifier = accessibilityIdentifier
        self.handler = handler
    }
}

struct QuickActionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let actions: [QuickActionSheetAction]

    var body: some View {
        NavigationStack {
            List(actions) { action in
                Button(role: action.role) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        action.handler()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(action.role == .destructive ? .red : AppTheme.accentColor)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.title)
                                .foregroundStyle(action.role == .destructive ? .red : AppTheme.textColor)

                            if let subtitle = action.subtitle {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier(action.accessibilityIdentifier ?? action.id)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .appBackground(AppTheme.gradientSettings)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
