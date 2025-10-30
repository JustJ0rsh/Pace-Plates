// MARK: - AppTheme

import SwiftUI
import UIKit

// MARK: - Theme

enum AppTheme {
    static let backgroundColor = Color("BackgroundColor") // Dark Blue/Gray
    static let secondaryBackgroundColor = Color("SecondaryBackgroundColor") // Slightly different gray
    static let textColor = Color("TextColor") // Light Gray/Off-White
    static let accentColor = Color("AccentColor") // Teal/Bright Blue
    
    // A set of dark, but visible gradients tuned per section
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.07, blue: 0.11),
            Color(red: 0.02, green: 0.03, blue: 0.06)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let gradientHome = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.08, blue: 0.25),  // indigo
            Color(red: 0.02, green: 0.08, blue: 0.18)   // teal-navy
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientWorkouts = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.08, blue: 0.24),  // purple
            Color(red: 0.05, green: 0.06, blue: 0.14)   // deep slate
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientRuns = LinearGradient(
        colors: [
            Color(red: 0.00, green: 0.18, blue: 0.30),  // blue-cyan
            Color(red: 0.02, green: 0.04, blue: 0.10)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientAI = LinearGradient(
        colors: [
            Color(red: 0.09, green: 0.04, blue: 0.18),  // deep violet
            Color(red: 0.01, green: 0.08, blue: 0.20)   // teal-navy blend
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientWeight = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.20, blue: 0.10),  // olive
            Color(red: 0.05, green: 0.06, blue: 0.12)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gradientSettings = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.08, blue: 0.08),  // crimson tint
            Color(red: 0.05, green: 0.06, blue: 0.12)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    
    static let cornerRadius: CGFloat = 10
    static let padding: CGFloat = 16
    
    static let buttonStyle = BorderedProminentButtonStyle()
    
    static func applyGlobalTheme() {
        // Set Accent Color (Tint)
        UIView.appearance().tintColor = UIColor(accentColor)
        
        // Navigation Bar Appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(backgroundColor)
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor(textColor)]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(textColor)]
        // Set button colors
        let barButtonItemAppearance = UIBarButtonItemAppearance()
        barButtonItemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(accentColor)]
        navBarAppearance.buttonAppearance = barButtonItemAppearance
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor(accentColor)
        
        // Tab Bar Appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(backgroundColor)
        // Selected item color
        tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(accentColor)
        tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(accentColor)]
        // Normal item color
        tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(textColor).withAlphaComponent(0.7) // Slightly dimmer
        tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(textColor).withAlphaComponent(0.7)]
        tabBarAppearance.inlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance
        tabBarAppearance.compactInlineLayoutAppearance = tabBarAppearance.stackedLayoutAppearance
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().unselectedItemTintColor = UIColor(textColor).withAlphaComponent(0.7) // Ensure unselected tint matches
        UITabBar.appearance().tintColor = UIColor(accentColor)
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
