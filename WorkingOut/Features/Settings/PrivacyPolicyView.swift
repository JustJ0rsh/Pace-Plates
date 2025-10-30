import SwiftUI

struct PrivacyPolicyView: View {
    @State private var content: AttributedString = AttributedString("Loading…")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(content)
                    .font(.body)
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(AppTheme.textColor)
                    .tint(.blue)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: 640, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
            .padding(.top)
        }
        .scrollIndicators(.visible)
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .appBackground(AppTheme.gradientSettings)
        .onAppear { loadMarkdown() }
    }

    private func loadMarkdown() {
        if let url = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .full
                if var attr = try? AttributedString(markdown: text, options: options) {
                    // Apply a readable base font and increase paragraph spacing
                    attr.font = .system(.body)
                    attr.foregroundColor = nil // keep theme color via Text modifier

                    // Increase paragraph spacing by adding newlines normalization
                    // (AttributedString doesn't expose paragraph spacing directly across all runs)
                    content = attr
                    return
                }
            }
        }
        content = AttributedString("Privacy policy unavailable.")
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
