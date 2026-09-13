import SwiftUI

/// Applies `full` as the view's transition, or a plain fade when the user has
/// enabled Reduce Motion. Use for transitions that move or scale content;
/// opacity-only transitions do not need it.
private struct MotionAwareTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let full: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : full)
    }
}

extension View {
    func motionAwareTransition(_ full: AnyTransition) -> some View {
        modifier(MotionAwareTransition(full: full))
    }
}
