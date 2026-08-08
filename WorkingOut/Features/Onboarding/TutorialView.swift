import SwiftUI

struct TutorialView: View {
    var onFinish: (() -> Void)?

    @AppStorage("didCompleteProfileSetup") private var didCompleteProfileSetup: Bool = false

    @State private var step: Step = .focus
    @State private var selectedFocus: OnboardingFocus?
    @State private var measurementSystem: String
    @State private var sex: String
    @State private var experienceLevel: String
    @State private var ageText: String
    @State private var heightValue: Double
    @State private var heightUnit: String
    @State private var goalWeightText: String
    @State private var weightUnit: String
    @State private var weightGoal: String
    @State private var showHeightPicker: Bool = false

    @FocusState private var ageFocused: Bool
    @FocusState private var goalWeightFocused: Bool

    init(onFinish: (() -> Void)? = nil) {
        self.onFinish = onFinish

        let defaults = UserDefaults.standard
        let storedMeasurementSystem = defaults.string(forKey: "measurementSystem") ?? "imperial"
        let storedAge = defaults.integer(forKey: "age")
        let storedTargetWeight = defaults.double(forKey: "targetWeight")

        _selectedFocus = State(
            initialValue: defaults.string(forKey: "onboardingPrimaryGoal")
                .flatMap(OnboardingFocus.init(rawValue:))
        )
        _measurementSystem = State(initialValue: storedMeasurementSystem)
        _sex = State(initialValue: defaults.string(forKey: "sex") ?? "")
        _experienceLevel = State(initialValue: defaults.string(forKey: "experienceLevel") ?? "")
        _ageText = State(initialValue: storedAge > 0 ? String(storedAge) : "")
        _heightValue = State(initialValue: defaults.double(forKey: "heightValue"))
        _heightUnit = State(
            initialValue: defaults.string(forKey: "heightUnit")
                ?? (storedMeasurementSystem == "metric" ? "cm" : "in")
        )
        _goalWeightText = State(
            initialValue: storedTargetWeight > 0
                ? Self.formatDecimal(storedTargetWeight)
                : ""
        )
        _weightUnit = State(
            initialValue: defaults.string(forKey: "weightUnit")
                ?? (storedMeasurementSystem == "metric" ? "kg" : "lbs")
        )
        _weightGoal = State(initialValue: defaults.string(forKey: "weightGoal") ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.gradientHome.ignoresSafeArea()

                Group {
                    switch step {
                    case .focus:
                        focusPage
                    case .profile:
                        profilePage
                    }
                }
            }
            .foregroundStyle(AppTheme.textColor)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .sheet(isPresented: $showHeightPicker) {
                HeightPickerSheet(
                    heightUnit: heightUnit,
                    initialValue: heightValue > 0 ? heightValue : nil
                ) { newValue in
                    heightValue = newValue ?? 0
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button {
                        if goalWeightFocused {
                            goalWeightFocused = false
                            ageFocused = true
                        }
                    } label: {
                        Label("Previous field", systemImage: "chevron.up")
                    }
                    .disabled(ageFocused)

                    Button {
                        if ageFocused {
                            ageFocused = false
                            goalWeightFocused = true
                        }
                    } label: {
                        Label("Next field", systemImage: "chevron.down")
                    }
                    .disabled(goalWeightFocused)

                    Spacer()

                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
    }

    private var focusPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                onboardingHeader(
                    icon: "scope",
                    title: "What do you want to focus on?",
                    message: "Choose a starting point. You can use every part of Pace & Plates and change this later."
                )

                VStack(spacing: 12) {
                    ForEach(OnboardingFocus.allCases) { focus in
                        focusButton(focus)
                    }
                }

                Text("No account or personal details are required to get started.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var profilePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    dismissKeyboard()
                    withAnimation(.easeInOut) {
                        step = .focus
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityHint("Returns to focus selection")

                onboardingHeader(
                    icon: "person.crop.circle",
                    title: "Personalize your guidance",
                    message: "Everything here is optional. Leave any field blank and add it later in Settings."
                )

                unitsSection
                trainingSection
                personalDetailsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Units")
                .font(.headline)

            Picker("Measurement system", selection: $measurementSystem) {
                Text("Metric").tag("metric")
                Text("Imperial").tag("imperial")
            }
            .pickerStyle(.segmented)
            .onChange(of: measurementSystem) { oldValue, newValue in
                convertProfileValues(from: oldValue, to: newValue)
            }
            .accessibilityHint("Sets the units used for height, weight, distance, and weather")
        }
        .profileSectionStyle()
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Training preferences")
                .font(.headline)

            optionalMenuPicker(
                title: "Experience",
                selection: $experienceLevel,
                options: [
                    ("beginner", "New to training"),
                    ("experienced", "Experienced")
                ]
            )

            Divider()

            optionalMenuPicker(
                title: "Weight goal",
                selection: $weightGoal,
                options: [
                    ("lose", "Lose weight"),
                    ("maintain", "Maintain weight"),
                    ("gain", "Gain weight")
                ]
            )

            Text("These choices tailor workout suggestions and nutrition guidance.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryTextColor)
        }
        .profileSectionStyle()
    }

    private var personalDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal details")
                .font(.headline)

            optionalMenuPicker(
                title: "Sex",
                selection: $sex,
                options: [
                    ("male", "Male"),
                    ("female", "Female")
                ]
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Age (optional)")
                    .font(.subheadline.weight(.medium))

                TextField("Not set", text: $ageText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .focused($ageFocused)
                    .tint(AppTheme.accentColor)
                    .onChange(of: ageText) { _, newValue in
                        let sanitized = sanitizeDigits(newValue)
                        if sanitized != newValue {
                            ageText = sanitized
                        }
                    }
                    .accessibilityLabel("Age, optional")
                    .accessibilityHint("Leave blank to keep your age unknown")

                if !isAgeInputValid {
                    Text("Enter an age from 13 to 120, or leave this blank.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Age error. Enter an age from 13 to 120, or leave this blank.")
                }
            }

            Divider()

            Button {
                dismissKeyboard()
                showHeightPicker = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Height (optional)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textColor)
                    HStack {
                        Text(heightDisplayValue)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Height, optional")
            .accessibilityValue(heightDisplayValue)
            .accessibilityHint("Opens a height picker. Leave unset to keep your height unknown.")

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Goal weight (optional)")
                    .font(.subheadline.weight(.medium))

                HStack {
                    TextField("Not set", text: $goalWeightText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($goalWeightFocused)
                        .tint(AppTheme.accentColor)
                        .onChange(of: goalWeightText) { _, newValue in
                            let sanitized = sanitizeDecimal(newValue)
                            if sanitized != newValue {
                                goalWeightText = sanitized
                            }
                        }
                        .accessibilityLabel("Goal weight, optional")
                        .accessibilityHint("Leave blank to keep your goal weight unknown")

                    Text(weightUnit)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .accessibilityHidden(true)
                }

                if !isGoalWeightInputValid {
                    Text("Enter a number greater than zero, or leave this blank.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Goal weight error. Enter a number greater than zero, or leave this blank.")
                }
            }

            Text("Body details are stored on your device and are only used to improve estimates and guidance.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryTextColor)
        }
        .profileSectionStyle()
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Step.allCases) { item in
                    Capsule()
                        .fill(item == step ? AppTheme.accentColor : AppTheme.textColor.opacity(0.22))
                        .frame(width: item == step ? 28 : 14, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    secondaryActionButton
                    Spacer(minLength: 8)
                    primaryActionButton
                }

                VStack(spacing: 10) {
                    primaryActionButton
                        .frame(maxWidth: .infinity)
                    secondaryActionButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppTheme.backgroundColor.opacity(0.96))
        .overlay(alignment: .top) {
            Divider().opacity(0.4)
        }
    }

    @ViewBuilder
    private var secondaryActionButton: some View {
        switch step {
        case .focus:
            Button("Skip Setup") {
                completeOnboarding(saveGoal: false, saveProfile: false)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Starts using the app without saving a goal or profile details")
        case .profile:
            Button("Do This Later") {
                completeOnboarding(saveGoal: true, saveProfile: false)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Saves your focus but leaves all profile details unchanged")
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch step {
        case .focus:
            Button("Continue") {
                withAnimation(.easeInOut) {
                    step = .profile
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedFocus == nil)
            .accessibilityHint(
                selectedFocus == nil
                    ? "Select a focus first"
                    : "Continues to optional profile details"
            )
        case .profile:
            Button("Save & Start") {
                completeOnboarding(saveGoal: true, saveProfile: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isProfileInputValid)
            .accessibilityHint("Saves the details you entered and starts using the app")
        }
    }

    private func onboardingHeader(icon: String, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.body)
                .foregroundStyle(AppTheme.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func focusButton(_ focus: OnboardingFocus) -> some View {
        let isSelected = selectedFocus == focus

        return Button {
            selectedFocus = focus
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: focus.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(focus.title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textColor)
                    Text(focus.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.accentColor : AppTheme.secondaryTextColor)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? AppTheme.accentColor.opacity(0.16)
                            : AppTheme.secondaryBackgroundColor
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? AppTheme.accentColor : AppTheme.textColor.opacity(0.12),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focus.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(focus.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func optionalMenuPicker(
        title: String,
        selection: Binding<String>,
        options: [(value: String, label: String)]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Not set").tag("")
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .tint(AppTheme.accentColor)
        .accessibilityHint("Optional. Choose Not set to leave this unknown.")
    }

    private var heightDisplayValue: String {
        guard heightValue > 0 else { return "Not set" }

        if heightUnit == "in" {
            let totalInches = Int(heightValue.rounded())
            return "\(totalInches / 12)′ \(totalInches % 12)″"
        }

        return "\(Self.formatDecimal(heightValue)) cm"
    }

    private var isAgeInputValid: Bool {
        guard !ageText.isEmpty else { return true }
        guard let age = Int(ageText) else { return false }
        return (13...120).contains(age)
    }

    private var isGoalWeightInputValid: Bool {
        guard !goalWeightText.isEmpty else { return true }
        guard let targetWeight = Double(goalWeightText) else { return false }
        return targetWeight > 0
    }

    private var isProfileInputValid: Bool {
        isAgeInputValid && isGoalWeightInputValid
    }

    private func sanitizeDigits(_ text: String) -> String {
        String(text.filter(\.isNumber))
    }

    private func sanitizeDecimal(_ text: String) -> String {
        var output = ""
        var hasDecimalSeparator = false

        for character in text {
            if character.isNumber {
                output.append(character)
            } else if (character == "." || character == ",") && !hasDecimalSeparator {
                output.append(".")
                hasDecimalSeparator = true
            }
        }

        return output
    }

    private func convertProfileValues(from oldSystem: String, to newSystem: String) {
        guard oldSystem != newSystem else { return }

        if newSystem == "metric" {
            if heightValue > 0, heightUnit == "in" {
                heightValue = ((heightValue * 2.54) * 10).rounded() / 10
            }
            if let targetWeight = Double(goalWeightText), targetWeight > 0, weightUnit == "lbs" {
                goalWeightText = Self.formatDecimal(((targetWeight / 2.20462) * 10).rounded() / 10)
            }
            heightUnit = "cm"
            weightUnit = "kg"
        } else {
            if heightValue > 0, heightUnit == "cm" {
                heightValue = (heightValue / 2.54).rounded()
            }
            if let targetWeight = Double(goalWeightText), targetWeight > 0, weightUnit == "kg" {
                goalWeightText = Self.formatDecimal(((targetWeight * 2.20462) * 10).rounded() / 10)
            }
            heightUnit = "in"
            weightUnit = "lbs"
        }
    }

    private func completeOnboarding(saveGoal: Bool, saveProfile: Bool) {
        dismissKeyboard()

        if saveGoal, let selectedFocus {
            UserDefaults.standard.set(selectedFocus.rawValue, forKey: "onboardingPrimaryGoal")
        }

        if saveProfile {
            persistProfile()
        }

        didCompleteProfileSetup = true
        onFinish?()
    }

    private func persistProfile() {
        let defaults = UserDefaults.standard
        defaults.set(measurementSystem, forKey: "measurementSystem")
        defaults.set(heightUnit, forKey: "heightUnit")
        defaults.set(weightUnit, forKey: "weightUnit")

        persistOptional(sex, forKey: "sex", in: defaults)
        persistOptional(experienceLevel, forKey: "experienceLevel", in: defaults)
        persistOptional(weightGoal, forKey: "weightGoal", in: defaults)

        if let age = Int(ageText), age > 0 {
            defaults.set(age, forKey: "age")
        } else {
            defaults.removeObject(forKey: "age")
        }

        if heightValue > 0 {
            defaults.set(heightValue, forKey: "heightValue")
        } else {
            defaults.removeObject(forKey: "heightValue")
        }

        if let targetWeight = Double(goalWeightText), targetWeight > 0 {
            defaults.set(targetWeight, forKey: "targetWeight")
        } else {
            defaults.removeObject(forKey: "targetWeight")
        }
    }

    private func persistOptional(_ value: String, forKey key: String, in defaults: UserDefaults) {
        if value.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    private func dismissKeyboard() {
        ageFocused = false
        goalWeightFocused = false
    }

    private static func formatDecimal(_ value: Double) -> String {
        String(
            format: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f",
            value
        )
    }
}

private extension TutorialView {
    enum Step: Int, CaseIterable, Identifiable {
        case focus
        case profile

        var id: Int { rawValue }
    }

    enum OnboardingFocus: String, CaseIterable, Identifiable {
        case strength
        case running
        case nutrition
        case balanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .strength: return "Build strength"
            case .running: return "Run better"
            case .nutrition: return "Nutrition guidance"
            case .balanced: return "Balance everything"
            }
        }

        var subtitle: String {
            switch self {
            case .strength: return "Plan workouts and track progress in the gym."
            case .running: return "Build consistency, pace, and endurance."
            case .nutrition: return "Get practical guidance that supports your goals."
            case .balanced: return "Combine strength, running, weight, and recovery."
            }
        }

        var icon: String {
            switch self {
            case .strength: return "dumbbell.fill"
            case .running: return "figure.run"
            case .nutrition: return "fork.knife"
            case .balanced: return "circle.grid.2x2.fill"
            }
        }
    }
}

private extension View {
    func profileSectionStyle() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floatingTile()
    }
}

private struct HeightPickerSheet: View {
    let heightUnit: String
    let initialValue: Double?
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feet: Int
    @State private var inches: Int
    @State private var centimeters: Int
    @State private var centimeterDecimal: Int

    init(heightUnit: String, initialValue: Double?, onSave: @escaping (Double?) -> Void) {
        self.heightUnit = heightUnit
        self.initialValue = initialValue
        self.onSave = onSave

        if heightUnit == "in" {
            let totalInches = Int((initialValue ?? 68).rounded())
            _feet = State(initialValue: max(3, min(8, totalInches / 12)))
            _inches = State(initialValue: max(0, min(11, totalInches % 12)))
            _centimeters = State(initialValue: 175)
            _centimeterDecimal = State(initialValue: 0)
        } else {
            let value = initialValue ?? 175
            let wholeCentimeters = Int(floor(value))
            let decimal = Int(((value - floor(value)) * 10).rounded())
            _feet = State(initialValue: 5)
            _inches = State(initialValue: 8)
            _centimeters = State(initialValue: max(120, min(230, wholeCentimeters)))
            _centimeterDecimal = State(initialValue: max(0, min(9, decimal)))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Choose a height only if you want to add one now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if heightUnit == "in" {
                    HStack(spacing: 0) {
                        Picker("Feet", selection: $feet) {
                            ForEach(3...8, id: \.self) { value in
                                Text("\(value) ft").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("Inches", selection: $inches) {
                            ForEach(0...11, id: \.self) { value in
                                Text("\(value) in").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                } else {
                    HStack(spacing: 0) {
                        Picker("Centimeters", selection: $centimeters) {
                            ForEach(120...230, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)

                        Picker("Tenths of a centimeter", selection: $centimeterDecimal) {
                            ForEach(0...9, id: \.self) { value in
                                Text(".\(value)").tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                    }
                }

                if initialValue != nil {
                    Button("Clear Height", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    .accessibilityHint("Removes the saved height")
                }
            }
            .padding(.top)
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedHeight)
                        dismiss()
                    }
                }
            }
        }
    }

    private var selectedHeight: Double {
        if heightUnit == "in" {
            return Double(feet * 12 + inches)
        }

        return Double(centimeters) + Double(centimeterDecimal) / 10
    }
}

#Preview {
    TutorialView()
}
