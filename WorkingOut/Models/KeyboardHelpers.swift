import SwiftUI

// Global keyboard helpers to stabilize number pad usage across the app.
// - Adds a toolbar with Done/Next controls above the keyboard
// - Provides utilities to dismiss keyboard cleanly before dismissing views

public enum KeyboardDismissPolicy { case none, dismissView }

public struct KeyboardToolbar: ViewModifier {
    let title: String?
    let onPrimary: () -> Void
    let primaryTitle: String

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let title { Text(title).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
                Button(primaryTitle) { onPrimary() }
            }
        }
        #else
        content
        #endif
    }
}

public extension View {
    // Adds a keyboard toolbar with a single trailing button (e.g., Done/Next)
    func keyboardToolbar(title: String? = nil, primaryTitle: String = "Done", onPrimary: @escaping () -> Void) -> some View {
        modifier(KeyboardToolbar(title: title, onPrimary: onPrimary, primaryTitle: primaryTitle))
    }

    // Programmatically dismisses the keyboard (resigns first responder)
    func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
