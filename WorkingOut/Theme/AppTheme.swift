// MARK: - AppTheme

import SwiftUI
import UIKit

// MARK: - Theme Selection

enum AppThemeOption: String, CaseIterable, Identifiable {
    case appDefault
    case light
    case dark
    case ocean
    case sunset
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appDefault: return "App Default"
        case .light: return "Light"
        case .dark: return "Dark"
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .forest: return "Forest"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .appDefault, .dark, .ocean, .sunset, .forest:
            return .dark
        }
    }
}

// MARK: - Theme Tokens

enum AppTheme {
    static let storageKey = "appTheme"

    static var option: AppThemeOption {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let option = AppThemeOption(rawValue: raw)
        else { return .appDefault }
        return option
    }

    static var preferredColorScheme: ColorScheme? { option.preferredColorScheme }

    static var toolbarColorScheme: ColorScheme? {
        switch option {
        case .light:
            return .light
        case .appDefault, .dark, .ocean, .sunset, .forest:
            return .dark
        }
    }

    static var backgroundColor: Color { palette.backgroundColor }
    static var secondaryBackgroundColor: Color { palette.secondaryBackgroundColor }
    static var textColor: Color { palette.textColor }
    static var secondaryTextColor: Color {
        switch option {
        case .light:
            return palette.textColor.opacity(0.65)
        case .appDefault, .dark, .ocean, .sunset, .forest:
            return palette.textColor.opacity(0.78)
        }
    }
    static var accentColor: Color { palette.accentColor }
    
    // A set of dark, but visible gradients tuned per section
    static var backgroundGradient: LinearGradient { palette.backgroundGradient }

    static var gradientHome: LinearGradient { palette.gradientHome }

    static var gradientWorkouts: LinearGradient { palette.gradientWorkouts }

    static var gradientRuns: LinearGradient { palette.gradientRuns }

    static var gradientAI: LinearGradient { palette.gradientAI }

    static var gradientWeight: LinearGradient { palette.gradientWeight }

    static var gradientSettings: LinearGradient { palette.gradientSettings }
    
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 16
    
    static let buttonStyle = BorderedProminentButtonStyle()

    private struct Palette {
        let backgroundColor: Color
        let secondaryBackgroundColor: Color
        let textColor: Color
        let accentColor: Color

        let backgroundGradient: LinearGradient
        let gradientHome: LinearGradient
        let gradientWorkouts: LinearGradient
        let gradientRuns: LinearGradient
        let gradientAI: LinearGradient
        let gradientWeight: LinearGradient
        let gradientSettings: LinearGradient
    }

    private static var palette: Palette {
        switch option {
        case .appDefault:
            return Palette(
                backgroundColor: Color(hex: 0x1A202C),
                secondaryBackgroundColor: Color(hex: 0x252D3A),
                textColor: Color(hex: 0xE2E8F0),
                accentColor: Color(hex: 0x008CFF),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.07, blue: 0.11),
                        Color(red: 0.02, green: 0.03, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.08, blue: 0.25),
                        Color(red: 0.02, green: 0.08, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.08, blue: 0.24),
                        Color(red: 0.05, green: 0.06, blue: 0.14)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(red: 0.00, green: 0.18, blue: 0.30),
                        Color(red: 0.02, green: 0.04, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.04, blue: 0.18),
                        Color(red: 0.01, green: 0.08, blue: 0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.20, blue: 0.10),
                        Color(red: 0.05, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.08, blue: 0.08),
                        Color(red: 0.05, green: 0.06, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .light:
            return Palette(
                backgroundColor: Color(hex: 0xF6F7FB),
                secondaryBackgroundColor: Color(hex: 0xE9ECF3),
                textColor: Color(hex: 0x141824),
                accentColor: Color(hex: 0x0A84FF),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(hex: 0xF6F7FB),
                        Color(hex: 0xEAF0FF)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(hex: 0xEEF3FF),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(hex: 0xF1F7FF),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(hex: 0xEAFBFF),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(hex: 0xF4F0FF),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(hex: 0xF0FFF6),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(hex: 0xFFF1F1),
                        Color(hex: 0xF6F7FB)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .dark:
            return Palette(
                backgroundColor: Color(hex: 0x0B0D10),
                secondaryBackgroundColor: Color(hex: 0x1A1F2A),
                textColor: Color(hex: 0xF3F5F7),
                accentColor: Color(hex: 0x0A84FF),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(hex: 0x10131A),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(hex: 0x141828),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(hex: 0x1B1533),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(hex: 0x001C2E),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(hex: 0x120B22),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(hex: 0x122015),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(hex: 0x221010),
                        Color(hex: 0x07090D)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .ocean:
            return Palette(
                backgroundColor: Color(hex: 0x07121D),
                secondaryBackgroundColor: Color(hex: 0x122334),
                textColor: Color(hex: 0xE6F2FF),
                accentColor: Color(hex: 0x00C2FF),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(hex: 0x0A1B2C),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(hex: 0x082C3A),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(hex: 0x0B2438),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(hex: 0x00324D),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(hex: 0x0B1833),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(hex: 0x0D2A26),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(hex: 0x0D1F2B),
                        Color(hex: 0x050A12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .sunset:
            return Palette(
                backgroundColor: Color(hex: 0x1A0B12),
                secondaryBackgroundColor: Color(hex: 0x2A1420),
                textColor: Color(hex: 0xFFF1F4),
                accentColor: Color(hex: 0xFF7A00),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(hex: 0x2A0E1A),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(hex: 0x3A1431),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(hex: 0x2E1030),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(hex: 0x3A140E),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(hex: 0x240A2E),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(hex: 0x2E1A0A),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(hex: 0x3A140E),
                        Color(hex: 0x0D0508)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .forest:
            return Palette(
                backgroundColor: Color(hex: 0x07140D),
                secondaryBackgroundColor: Color(hex: 0x11261A),
                textColor: Color(hex: 0xECFFF4),
                accentColor: Color(hex: 0x34C759),
                backgroundGradient: LinearGradient(
                    colors: [
                        Color(hex: 0x0B2317),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientHome: LinearGradient(
                    colors: [
                        Color(hex: 0x12331F),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWorkouts: LinearGradient(
                    colors: [
                        Color(hex: 0x162B1A),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientRuns: LinearGradient(
                    colors: [
                        Color(hex: 0x0A2E22),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientAI: LinearGradient(
                    colors: [
                        Color(hex: 0x0C1F18),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientWeight: LinearGradient(
                    colors: [
                        Color(hex: 0x112B15),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                gradientSettings: LinearGradient(
                    colors: [
                        Color(hex: 0x0F2417),
                        Color(hex: 0x050A07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    static func applyGlobalTheme() {
        let palette = Self.palette
        // Set Accent Color (Tint)
        UIView.appearance().tintColor = UIColor(palette.accentColor)

        // Navigation Bar Appearance (ensures titles stay visible with custom toolbars)
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(palette.backgroundColor)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(palette.textColor)]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(palette.textColor)]
        navBarAppearance.shadowColor = UIColor.clear

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance = navBarAppearance
        navBar.scrollEdgeAppearance = navBarAppearance
        navBar.compactAppearance = navBarAppearance
        navBar.compactScrollEdgeAppearance = navBarAppearance
        navBar.tintColor = UIColor(palette.accentColor)
        navBar.isTranslucent = false
        navBar.prefersLargeTitles = true

        // Tab Bar Appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(palette.backgroundColor)
        // Selected item color
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(palette.accentColor)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(palette.accentColor)]
        // Normal item color
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(palette.textColor)
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(palette.textColor)]
        tabBarAppearance.inlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(palette.textColor)
        UITabBar.appearance().tintColor = UIColor(palette.accentColor)
    }
} 

// MARK: - View Helpers

extension View {
    func appCardStyle() -> some View {
        self
    }
    
    /// Applies the app's gradient background consistently.
    /// - Parameter gradient: Optional gradient override; defaults to the base background gradient.
    func appBackground(_ gradient: LinearGradient? = nil) -> some View {
        self.background(gradient ?? AppTheme.backgroundGradient)
    }
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}
