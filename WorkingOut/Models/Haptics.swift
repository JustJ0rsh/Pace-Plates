#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
    // MARK: - Simple impact styles
    enum ImpactStyle { case light, medium, heavy, soft, rigid }
    enum NotificationType { case success, warning, error }

    // MARK: - Public API
    static func playImpact(_ style: ImpactStyle) {
        #if canImport(UIKit)
        // UIFeedbackGenerator is safe on Simulator and devices; it no-ops when unavailable
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light: generator = UIImpactFeedbackGenerator(style: .light)
        case .medium: generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy: generator = UIImpactFeedbackGenerator(style: .heavy)
        case .soft: generator = UIImpactFeedbackGenerator(style: .soft)
        case .rigid: generator = UIImpactFeedbackGenerator(style: .rigid)
        }
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func notify(_ type: NotificationType) {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        switch type {
        case .success: generator.notificationOccurred(.success)
        case .warning: generator.notificationOccurred(.warning)
        case .error: generator.notificationOccurred(.error)
        }
        #endif
    }

}
