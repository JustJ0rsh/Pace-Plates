import SwiftUI
import UIKit

struct TutorialView: View {
    var onFinish: (() -> Void)?

    @State private var page: Int = 0
    private let pageCount: Int = 4
    
    // Profile setup state
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"
    @AppStorage("sex") private var sex: String = "male"
    @AppStorage("experienceLevel") private var experienceLevel: String = "beginner"
    @AppStorage("age") private var age: Int = 0
    @AppStorage("heightValue") private var heightValue: Double = 0
    @AppStorage("heightUnit") private var heightUnit: String = "in"
    @AppStorage("targetWeight") private var targetWeight: Double = 0
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("weightGoal") private var weightGoal: String = "maintain"
    @AppStorage("didCompleteProfileSetup") private var didCompleteProfileSetup: Bool = false
    
    @State private var showHeightPicker: Bool = false
    @FocusState private var ageFocused: Bool
    @FocusState private var goalWeightFocused: Bool
    @State private var ageText: String = ""
    @State private var goalWeightText: String = ""
    @State private var isKeyboardVisible: Bool = false

    private var isEditingProfileField: Bool {
        page == 3 && (isKeyboardVisible || ageFocused || goalWeightFocused)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    tutorialPage(
                        title: "Welcome to Pace & Plates",
                        icon: "sparkles",
                        bullets: [
                            "Your complete fitness companion for workouts, runs, and nutrition tracking",
                            "Beautiful charts and insights with no account required",
                            "Privacy-first with optional iCloud sync across devices"
                        ]
                    ).tag(0)

                    tutorialPage(
                        title: "Track Everything",
                        icon: "chart.xyaxis.line",
                        bullets: [
                            "Log strength workouts with exercise templates",
                            "GPS tracking for runs with pace-colored routes",
                            "Track weight and nutrition goals",
                            "AI-powered workout planning with Apple Intelligence",
                            "View streaks and earn achievements"
                        ]
                    ).tag(1)

                    tutorialPage(
                        title: "Permissions",
                        icon: "hand.raised.fill",
                        bullets: [
                            "Health access enables workout and run sync",
                            "Location is used for GPS routes and weather",
                            "Notifications for weekly weight reminders (optional)",
                            "All data stays on your device unless you enable iCloud"
                        ]
                    ).tag(2)
                    
                    // Profile Setup Page
                    profileSetupPage()
                        .tag(3)
                }
                // Avoid toggling the built-in page indicator during keyboard transitions,
                // which can cause TabView to re-measure and "flash" its layout height.
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // LAYOUT CONTROL: When `isEditingProfileField` is true (keyboard showing), these
                // bottom controls are removed from the VStack layout entirely, allowing the
                // TabView/ScrollView above to expand downward closer to the keyboard.
                // To RAISE the content (more space above keyboard): keep these in layout (use opacity instead of if)
                // To LOWER the content (less space above keyboard): this current approach removes them from layout
                if !isEditingProfileField {
                    // Custom page indicator.
                    HStack(spacing: 8) {
                        ForEach(0..<pageCount, id: \.self) { idx in
                            Circle()
                                .fill((idx == page) ? AppTheme.textColor.opacity(0.9) : AppTheme.textColor.opacity(0.25))
                                .frame(width: idx == page ? 7 : 6, height: idx == page ? 7 : 6)
                        }
                    }
                    .frame(height: 18)
                    .allowsHitTesting(false)

                    HStack {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        if page < 3 {
                            Button("Next") { withAnimation { page += 1 } }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Button("Get Started") {
                                completeOnboarding()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { AppTheme.gradientHome.ignoresSafeArea() }
            .foregroundColor(AppTheme.textColor)
            .sheet(isPresented: $showHeightPicker) {
                HeightPickerSheet(heightUnit: $heightUnit, heightValue: $heightValue)
                    .presentationDetents([.height(340), .medium])
                    .presentationDragIndicator(.visible)
            }
            // TOOLBAR: Must be on NavigationStack level to appear on first tap
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Back button - go to previous field
                    Button {
                        if goalWeightFocused {
                            goalWeightFocused = false
                            ageFocused = true
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(ageFocused)
                    
                    // Next button - go to next field
                    Button {
                        if ageFocused {
                            ageFocused = false
                            goalWeightFocused = true
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(goalWeightFocused)
                    
                    Spacer()
                    
                    Button("Done") {
                        ageFocused = false
                        goalWeightFocused = false
                        dismissKeyboard()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                // Make layout changes happen in sync with the keyboard animation to avoid "jumping" gaps.
                if page == 3 { isKeyboardVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
        }
    }

    private func sanitizeDigits(_ text: String) -> String {
        String(text.filter { $0.isNumber })
    }

    private func sanitizeDecimal(_ text: String) -> String {
        var out = ""
        var hasDot = false
        for ch in text {
            if ch.isNumber {
                out.append(ch)
            } else if (ch == "." || ch == ",") && !hasDot {
                out.append(".")
                hasDot = true
            }
        }
        return out
    }

    private func completeOnboarding() {
        applyProfileDefaultsIfNeeded()
        didCompleteProfileSetup = true
        onFinish?()
    }

    private func applyProfileDefaultsIfNeeded() {
        if age <= 0 {
            let sanitized = sanitizeDigits(ageText)
            age = Int(sanitized) ?? 25
            ageText = String(age)
        }

        if heightValue <= 0 {
            heightValue = heightUnit == "cm" ? 175.0 : 68.0
        }

        if targetWeight <= 0 {
            let sanitized = sanitizeDecimal(goalWeightText)
            targetWeight = Double(sanitized) ?? (weightUnit == "kg" ? 80.0 : 180.0)
            goalWeightText = String(
                format: targetWeight.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f",
                targetWeight
            )
        }
    }

    @ViewBuilder
    private func tutorialPage(title: String, icon: String, bullets: [String]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
            Text(title)
                .font(.title2).bold()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accentColor)
                        Text(line).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func profileSetupPage() -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.accentColor)
                    Text("Set Up Your Profile")
                        .font(.title2).bold()
                    Text("Help us personalize your experience")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                
                VStack(spacing: 20) {
                    // Units Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Units")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Picker("Measurement System", selection: $measurementSystem) {
                            Text("Metric").tag("metric")
                            Text("Imperial").tag("imperial")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: measurementSystem) { _, newValue in
                            if newValue == "imperial" {
                                weightUnit = "lbs"
                                heightUnit = "in"
                            } else {
                                weightUnit = "kg"
                                heightUnit = "cm"
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingTile()
                    
                    // Profile Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Picker("Sex", selection: $sex) {
                            Text("Male").tag("male")
                            Text("Female").tag("female")
                        }
                        .pickerStyle(.segmented)
                        
                        Picker("Experience Level", selection: $experienceLevel) {
                            Text("New to Working Out").tag("beginner")
                            Text("Experienced").tag("experienced")
                        }
                        .pickerStyle(.segmented)
                        
                        // Age Input
                        HStack {
                            Text("Age")
                                .foregroundColor(AppTheme.textColor)
                            Spacer()
                            TextField("25", text: $ageText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                                .focused($ageFocused)
                                .foregroundColor(AppTheme.textColor)
                                .tint(AppTheme.accentColor)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.secondaryBackgroundColor)
                        .cornerRadius(12)
                        .onChange(of: ageText) { _, newValue in
                            let sanitized = sanitizeDigits(newValue)
                            if sanitized != newValue { ageText = sanitized }
                            age = Int(sanitized) ?? 0
                        }
                        
                        // Height Picker
                        Button {
                            showHeightPicker = true
                        } label: {
                            HStack {
                                Text("Height")
                                    .foregroundColor(AppTheme.textColor)
                                Spacer()
                                if heightUnit == "in" {
                                    let totalInches = heightValue > 0 ? Int(round(heightValue)) : (5 * 12 + 8)
                                    let feet = max(0, totalInches / 12)
                                    let inches = max(0, min(11, totalInches % 12))
                                    Text("\(feet)′ \(inches)″")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(String(format: "%.1f", heightValue > 0 ? heightValue : 175.0))
                                        .foregroundStyle(.secondary)
                                    Text("cm")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.secondaryBackgroundColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        
                        // Goal Weight
                        HStack {
                            Text("Goal Weight")
                                .foregroundColor(AppTheme.textColor)
                            Spacer()
                            TextField(weightUnit == "kg" ? "80" : "180", text: $goalWeightText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                .focused($goalWeightFocused)
                                .foregroundColor(AppTheme.textColor)
                                .tint(AppTheme.accentColor)
                            Text(weightUnit)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.secondaryBackgroundColor)
                        .cornerRadius(12)
                        .onChange(of: goalWeightText) { _, newValue in
                            let sanitized = sanitizeDecimal(newValue)
                            if sanitized != newValue { goalWeightText = sanitized }
                            targetWeight = Double(sanitized) ?? 0
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingTile()
                    
                    // Goals Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Goals")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Picker("Weight Goal", selection: $weightGoal) {
                            Text("Lose").tag("lose")
                            Text("Maintain").tag("maintain")
                            Text("Gain").tag("gain")
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .floatingTile()
                }
                .padding(.horizontal)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Seed text fields from saved values, but don't show "0" as actual text
            if ageText.isEmpty { ageText = age > 0 ? String(age) : "" }
            if goalWeightText.isEmpty {
                if targetWeight > 0 {
                    goalWeightText = String(format: targetWeight.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", targetWeight)
                } else {
                    goalWeightText = ""
                }
            }
        }
    }
}

// MARK: - Height Picker Sheet
private struct HeightPickerSheet: View {
    @Binding var heightUnit: String
    @Binding var heightValue: Double
    @Environment(\.dismiss) private var dismiss
    @State private var feet: Int = 5
    @State private var inches: Int = 9
    @State private var cmInt: Int = 175
    @State private var cmDec: Int = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if heightUnit == "in" {
                    HStack(spacing: 0) {
                        Picker("Feet", selection: $feet) {
                            ForEach(3...8, id: \.self) { Text("\($0) ft") }
                        }
                        .pickerStyle(.wheel)
                        Picker("Inches", selection: $inches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in") }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 200)
                    .onChange(of: feet) { _,_ in applyImperial() }
                    .onChange(of: inches) { _,_ in applyImperial() }
                    .onAppear { loadImperial() }
                } else {
                    HStack(spacing: 0) {
                        Picker("Centimeters", selection: $cmInt) {
                            ForEach(120...230, id: \.self) { Text("\($0)") }
                        }
                        .pickerStyle(.wheel)
                        Picker("Decimal", selection: $cmDec) {
                            ForEach(0...9, id: \.self) { Text(".\($0)") }
                        }
                        .pickerStyle(.wheel)
                    }
                    .frame(height: 200)
                    .onChange(of: cmInt) { _,_ in applyMetric() }
                    .onChange(of: cmDec) { _,_ in applyMetric() }
                    .onAppear { loadMetric() }
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func loadImperial() {
        let storedHeight = heightValue > 0 ? heightValue : 68.0
        let f = Int(floor(storedHeight / 12.0))
        let i = Int(round(storedHeight - Double(f) * 12.0))
        feet = max(3, min(8, f))
        inches = max(0, min(11, i))
    }
    
    private func applyImperial() {
        heightValue = Double(max(0, feet)) * 12.0 + Double(max(0, min(11, inches)))
    }
    
    private func loadMetric() {
        let v = heightValue > 0 ? heightValue : 175.0
        cmInt = Int(floor(v))
        cmDec = min(9, max(0, Int(round((v - floor(v)) * 10))))
    }
    
    private func applyMetric() {
        heightValue = Double(cmInt) + Double(cmDec) / 10.0
    }
}

#Preview {
    TutorialView()
}
