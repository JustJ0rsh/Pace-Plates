import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(CoreHaptics)
import CoreHaptics
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
        case .soft:
            if #available(iOS 13.0, *) { generator = UIImpactFeedbackGenerator(style: .soft) } else { generator = UIImpactFeedbackGenerator(style: .light) }
        case .rigid:
            if #available(iOS 13.0, *) { generator = UIImpactFeedbackGenerator(style: .rigid) } else { generator = UIImpactFeedbackGenerator(style: .heavy) }
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

    // MARK: - Advanced Core Haptics pattern (optional)
    // This method safely attempts to play a custom Core Haptics pattern on supported hardware.
    static func playTransientTap() {
        #if canImport(CoreHaptics)
        if !CHHapticEngine.capabilitiesForHardware().supportsHaptics { return }
        var engine: CHHapticEngine?
        do {
            engine = try CHHapticEngine()
            try engine?.start()

            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            // Silently ignore on unsupported devices or simulator
            // print("Haptics: Core Haptics unavailable: \(error)")
        }
        #endif
    }
}
