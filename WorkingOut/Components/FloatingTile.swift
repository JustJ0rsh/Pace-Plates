// MARK: - FloatingTile
import SwiftUI

// MARK: - Modifier
struct FloatingTile: ViewModifier {
    var cornerRadius: CGFloat = 16
    var shadowOpacity: Double = 0.15
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 6
    var strokeOpacity: Double = 0.35

    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.secondaryBackgroundColor.opacity(strokeOpacity))
            )
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: shadowY)
    }
}

// MARK: - View Helpers
extension View {
    func floatingTile(cornerRadius: CGFloat = 16) -> some View {
        modifier(FloatingTile(cornerRadius: cornerRadius))
    }
}
