// MARK: - GlassBackground

import SwiftUI

// MARK: - Modifiers

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 16
    var opacity: CGFloat = 0.35

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(opacity))
                    .background(
                        // Inner subtle blur and light effect
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .blur(radius: 10)
                            .offset(x: -5, y: -5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                .linearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.08),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 15, x: 0, y: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

 // MARK: - View Helpers

extension View {
    func glassBackground(cornerRadius: CGFloat = 16, opacity: CGFloat = 0.35) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius, opacity: opacity))
    }
}

// MARK: - Toolbar Helpers

struct GlassToolbarBackground: ToolbarContent {
    var body: some ToolbarContent {
        // Provide an empty toolbar container by default; you can add items if needed
        ToolbarItem(placement: .automatic) {
            EmptyView()
        }
    }
}

extension View {
    /// Applies a glass-like background to navigation/tool bars using system materials.
    /// - Parameters:
    ///   - visibility: The visibility of the toolbar background. Defaults to `.visible`.
    ///   - material: The material to use for the background. Defaults to `.ultraThinMaterial`.
    ///   - bars: The bars to which the background should apply. Defaults to `.navigationBar`.
    func glassToolbarBackground(
        _ visibility: Visibility = .visible,
        material: Material = .ultraThinMaterial,
        for bars: ToolbarPlacement = .navigationBar
    ) -> some View {
        self
            .toolbarBackground(visibility, for: bars)
            .toolbarBackground(material, for: bars)
    }
}
