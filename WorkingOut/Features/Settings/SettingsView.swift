import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial" // "metric" or "imperial"
    @AppStorage("weightUnit") private var weightUnit = "lbs"
    @AppStorage("distanceUnit") private var distanceUnit = "mi"
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // lose | maintain | gain
    @AppStorage("heightUnit") private var heightUnit: String = "in" // or "cm"
    @AppStorage("heightValue") private var heightValue: Double = 0
    @AppStorage("targetWeight") private var targetWeight: Double = 0
    @AppStorage("age") private var age: Int = 0
    @AppStorage("sex") private var sex: String = "male" // "male" or "female"
    @AppStorage("experienceLevel") private var experienceLevel: String = "beginner" // "beginner" or "experienced"
    @AppStorage("useStructuredPlanView") private var useStructuredPlanView: Bool = false
    @AppStorage("enableWeeklyWeightReminder") private var enableWeeklyWeightReminder: Bool = false
    @FocusState private var ageFocused: Bool
    @FocusState private var heightFocused: Bool
    @FocusState private var goalWeightFocused: Bool
    @State private var showHeightPicker: Bool = false
    // Reminder prefs
    @AppStorage("reminderWeekday") private var reminderWeekday: Int = 2
    @AppStorage("reminderHour") private var reminderHour: Int = 9
    @AppStorage("reminderMinute") private var reminderMinute: Int = 0
    @State private var reminderTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    
    var body: some View {
        NavigationStack {
            List {
                Section("Units") {
                    Picker("Measurement System", selection: $measurementSystem) {
                        Text("Metric").tag("metric")
                        Text("Imperial").tag("imperial")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: measurementSystem) { _, newValue in
                        if newValue == "imperial" {
                            weightUnit = "lbs"
                            distanceUnit = "mi"
                            heightUnit = "in"
                        } else {
                            weightUnit = "kg"
                            distanceUnit = "km"
                            heightUnit = "cm"
                        }
                        applyMeasurementSystemChange(newValue)
                    }
                }

                Section("Profile") {
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

                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("0", value: $age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .focused($ageFocused)
                    }

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
                                Text("\(feet)′ \(inches)″").foregroundStyle(.secondary)
                            } else {
                                Text(String(format: "%.1f", heightValue)).foregroundStyle(.secondary)
                                Text("cm").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showHeightPicker) { HeightPickerSheet(heightUnit: $heightUnit, heightValue: $heightValue) }

                    HStack {
                        Text("Goal Weight")
                        Spacer()
                        TextField("0", value: $targetWeight, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .focused($goalWeightFocused)
                        Text(weightUnit)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Goals") {
                    Picker("Weight Goal", selection: $weightGoal) {
                        Text("Lose").tag("lose")
                        Text("Maintain").tag("maintain")
                        Text("Gain").tag("gain")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundColor(AppTheme.textColor)
                        Spacer()
                        Text("1.4.1")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI & Plans") {
                    Toggle(isOn: $useStructuredPlanView) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Structured Plan View")
                            Text("Display saved plans as interactive cards when structured data is available. Note: New plan generation uses proven Markdown format for reliability.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Reminders") {
                    Toggle(isOn: $enableWeeklyWeightReminder) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weekly Weight Reminder")
                            Text("Reminds you to log your weight weekly.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: enableWeeklyWeightReminder) { _, newValue in
                        if newValue {
                            ReminderService.scheduleIfEnabled()
                        } else {
                            ReminderService.cancelWeeklyWeightReminder()
                        }
                    }

                    if enableWeeklyWeightReminder {
                        // Day and time pickers
                        Picker("Day", selection: $reminderWeekday) {
                            Text("Sun").tag(1)
                            Text("Mon").tag(2)
                            Text("Tue").tag(3)
                            Text("Wed").tag(4)
                            Text("Thu").tag(5)
                            Text("Fri").tag(6)
                            Text("Sat").tag(7)
                        }
                        .onChange(of: reminderWeekday) { _, _ in
                            ReminderService.scheduleWeeklyWeightReminder(weekday: reminderWeekday, hour: reminderHour, minute: reminderMinute)
                        }

                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { _, newTime in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                reminderHour = comps.hour ?? 9
                                reminderMinute = comps.minute ?? 0
                                ReminderService.scheduleWeeklyWeightReminder(weekday: reminderWeekday, hour: reminderHour, minute: reminderMinute)
                            }
                    }
                }

                Section("Backup") {
                    Button {
                        exportTapped()
                    } label: {
                        Label("Export Data", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                    .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                        switch result {
                        case .success(let url):
                            importFrom(url: url)
                        case .failure(let err):
                            alertMessage = "Import failed: \(err.localizedDescription)"
                            showAlert = true
                        }
                    }
                }

                // Move Privacy & Data to the bottom
                Section("Privacy & Data") {
                    Button(role: .destructive) {
                        confirmDeleteAll = true
                    } label: {
                        Label("Delete All Data", systemImage: "trash.slash")
                    }
                    Link(destination: URL(string: "https://github.com/JustJ0rsh/Pace-Plates/blob/main/Privacy%20Policy")!) {
                        Label("Privacy Policy", systemImage: "doc.text")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .appBackground(AppTheme.gradientSettings)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Settings")
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(item: $exportURL, onDismiss: { exportURL = nil }) { item in
                ShareSheet(items: [item.url])
            }
            .alert("Backup", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("Delete All Data?", isPresented: $confirmDeleteAll) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteAllEverywhere() }
            } message: {
                let cloud = PersistenceController.shared.isCloudBacked
                Text(cloud ? "This will remove all data from this device and iCloud for your account. This action cannot be undone." : "This will remove all data on this device. This action cannot be undone.")
            }
        }
        .ignoresSafeArea(.keyboard)
        // Provide a keyboard toolbar for numeric fields to dismiss the keyboard
        .toolbar { 
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    ageFocused = false
                    heightFocused = false
                    goalWeightFocused = false
                    dismissKeyboard()
                }
            }
        }
    }
    
    // MARK: - Backup actions
    @State private var showImporter: Bool = false
    private struct IdentifiableURL: Identifiable { let id = UUID(); let url: URL }
    @State private var exportURL: IdentifiableURL? = nil
    // Use URL-bound sheet to avoid blank first presentation
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var confirmDeleteAll: Bool = false
    
    private func exportTapped() {
        do {
            let url = try DataBackupService.exportAll(context: modelContext)
            exportURL = IdentifiableURL(url: url)
        } catch {
            alertMessage = "Export failed: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    private func importFrom(url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            // Copy into our sandbox first to avoid security-scope hiccups
            let fm = FileManager.default
            let tmp = fm.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
            try fm.copyItem(at: url, to: tmp)
            try DataBackupService.import(from: tmp, context: modelContext)
            // Clean up duplicates and ensure built-ins remain after import
            PersistenceController.shared.deduplicateExerciseDefinitions()
            PersistenceController.shared.ensureDefaultExercisesPresent()
            alertMessage = "Import complete"
            showAlert = true
        } catch {
            alertMessage = "Import failed: \(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Data deletion
    private func deleteAllLocal() {
        do {
            try deleteAllEntities()
            alertMessage = "All data on this device has been removed."
            showAlert = true
        } catch {
            alertMessage = "Delete failed: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func deleteAllEverywhere() {
        // With Cloud Sync enabled, deleting from the context propagates to iCloud.
        deleteAllLocal()
    }

    private func deleteAllEntities() throws {
        // Delete children first, then parents
        let logItems = try modelContext.fetch(FetchDescriptor<ExerciseLog>())
        logItems.forEach { modelContext.delete($0) }
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSession>())
        sessions.forEach { modelContext.delete($0) }
        // Keep preloaded library exercises; only delete user-defined
        let defs = try modelContext.fetch(FetchDescriptor<ExerciseDefinition>())
        defs.filter { $0.isUserDefined }.forEach { modelContext.delete($0) }
        let runs = try modelContext.fetch(FetchDescriptor<RunningSession>())
        runs.forEach { modelContext.delete($0) }
        let weights = try modelContext.fetch(FetchDescriptor<WeightEntry>())
        weights.forEach { modelContext.delete($0) }
        try modelContext.save()
    }
}

// MARK: - Unit conversion helpers
extension SettingsView {
    private func applyMeasurementSystemChange(_ system: String) {
        // Convert stored data so measurements remain the same in the new unit system
        // ExerciseLog weights
        if let logs: [ExerciseLog] = try? modelContext.fetch(FetchDescriptor<ExerciseLog>()) {
            for log in logs {
                if system == "imperial", log.weightUnit == "kg" {
                    log.weight = log.weight * 2.20462
                    log.weightUnit = "lbs"
                } else if system == "metric", log.weightUnit == "lbs" {
                    log.weight = log.weight / 2.20462
                    log.weightUnit = "kg"
                }
            }
        }
        // WeightEntry entries
        if let weights: [WeightEntry] = try? modelContext.fetch(FetchDescriptor<WeightEntry>()) {
            for entry in weights {
                if system == "imperial", entry.weightUnit == "kg" {
                    entry.weight = entry.weight * 2.20462
                    entry.weightUnit = "lbs"
                } else if system == "metric", entry.weightUnit == "lbs" {
                    entry.weight = entry.weight / 2.20462
                    entry.weightUnit = "kg"
                }
            }
        }
        // RunningSession distances
        if let runs: [RunningSession] = try? modelContext.fetch(FetchDescriptor<RunningSession>()) {
            for run in runs {
                if system == "imperial", run.distanceUnit == "km" {
                    run.distance = run.distance / 1.60934 // km -> mi
                    run.distanceUnit = "mi"
                } else if system == "metric", run.distanceUnit == "mi" {
                    run.distance = run.distance * 1.60934 // mi -> km
                    run.distanceUnit = "km"
                }
            }
        }
        // Profile height value stored in AppStorage
        if system == "imperial" {
            heightValue = (heightValue / 2.54).rounded() // cm -> in, nearest inch
            heightUnit = "in"
            // Convert goal weight kg -> lbs (1 dec)
            targetWeight = ((targetWeight * 2.20462) * 10).rounded() / 10.0
        } else {
            heightValue = ((heightValue * 2.54) * 10).rounded() / 10.0 // in -> cm, 1 dec
            heightUnit = "cm"
            // Convert goal weight lbs -> kg (1 dec)
            targetWeight = ((targetWeight / 2.20462) * 10).rounded() / 10.0
        }
        try? modelContext.save()
    }

    // MARK: - Height Picker
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
                            Picker("Feet", selection: $feet) { ForEach(3...8, id: \.self) { Text("\($0) ft") } }
                                .pickerStyle(.wheel)
                            Picker("Inches", selection: $inches) { ForEach(0...11, id: \.self) { Text("\($0) in") } }
                                .pickerStyle(.wheel)
                        }
                        .frame(height: 200)
                        .onChange(of: feet) { _,_ in applyImperial() }
                        .onChange(of: inches) { _,_ in applyImperial() }
                        .onAppear { loadImperial() }
                    } else {
                        HStack(spacing: 0) {
                            Picker("Centimeters", selection: $cmInt) { ForEach(120...230, id: \.self) { Text("\($0)") } }
                                .pickerStyle(.wheel)
                            Picker("Decimal", selection: $cmDec) { ForEach(0...9, id: \.self) { Text(".\($0)") } }
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
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
        private func loadImperial() {
            let f = Int(floor(heightValue / 12.0))
            let i = Int(round(heightValue - Double(f) * 12.0))
            feet = max(3, min(8, f)); inches = max(0, min(11, i))
        }
        private func applyImperial() { heightValue = Double(max(0, feet)) * 12.0 + Double(max(0, min(11, inches))) }
        private func loadMetric() { let v = max(0, heightValue); cmInt = Int(floor(v)); cmDec = min(9, max(0, Int(round((v - floor(v)) * 10)))) }
        private func applyMetric() { heightValue = Double(cmInt) + Double(cmDec) / 10.0 }
    }
}
