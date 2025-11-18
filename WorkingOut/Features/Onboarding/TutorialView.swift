import SwiftUI

struct TutorialView: View {
    var onFinish: (() -> Void)?

    @State private var page: Int = 0
    
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

    var body: some View {
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
            .tabViewStyle(.page(indexDisplayMode: .always))

            HStack {
                Button("Skip") { 
                    didCompleteProfileSetup = true
                    onFinish?()
                }
                .foregroundStyle(.secondary)
                Spacer()
                if page < 3 {
                    Button("Next") { withAnimation { page += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        didCompleteProfileSetup = true
                        onFinish?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .appBackground(AppTheme.gradientHome)
        .foregroundColor(AppTheme.textColor)
        .sheet(isPresented: $showHeightPicker) {
            HeightPickerSheet(heightUnit: $heightUnit, heightValue: $heightValue)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    ageFocused = false
                    goalWeightFocused = false
                    dismissKeyboard()
                }
            }
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
                .padding(.top)
                
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
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    
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
                            Spacer()
                            TextField("0", value: $age, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                                .focused($ageFocused)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Height Picker
                        Button {
                            showHeightPicker = true
                        } label: {
                            HStack {
                                Text("Height")
                                Spacer()
                                if heightUnit == "in" {
                                    let totalInches = Int(round(heightValue))
                                    let feet = max(0, totalInches / 12)
                                    let inches = max(0, min(11, totalInches % 12))
                                    Text("\(feet)′ \(inches)″")
                                        .foregroundStyle(heightValue > 0 ? .primary : .secondary)
                                } else {
                                    if heightValue > 0 {
                                        Text(String(format: "%.1f cm", heightValue))
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text("0.0 cm")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        // Goal Weight
                        HStack {
                            Text("Goal Weight")
                            Spacer()
                            TextField("0", value: $targetWeight, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                                .focused($goalWeightFocused)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            Text(weightUnit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    
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
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
        }
        .scrollDismissesKeyboard(.immediately)
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
        let f = Int(floor(heightValue / 12.0))
        let i = Int(round(heightValue - Double(f) * 12.0))
        feet = max(3, min(8, f))
        inches = max(0, min(11, i))
    }
    
    private func applyImperial() {
        heightValue = Double(max(0, feet)) * 12.0 + Double(max(0, min(11, inches)))
    }
    
    private func loadMetric() {
        let v = max(0, heightValue)
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
