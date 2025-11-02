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
    @AppStorage("allowAIWebSearch") private var allowAIWebSearch: Bool = false
    @AppStorage("useStructuredPlanView") private var useStructuredPlanView: Bool = false
    @FocusState private var ageFocused: Bool
    @FocusState private var heightFocused: Bool
    @FocusState private var goalWeightFocused: Bool
    
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

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("0", value: $heightValue, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .focused($heightFocused)
                        Text(heightUnit)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Goal Weight")
                        Spacer()
                        TextField("0", value: $targetWeight, format: .number)
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
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("AI & Plans") {
                    Toggle(isOn: $allowAIWebSearch) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow AI Web Search")
                            Text("When enabled, the assistant can search the web for factual information and provide cited sources.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $useStructuredPlanView) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Structured Plan View")
                            Text("Display saved plans as interactive cards when structured data is available. Note: New plan generation uses proven Markdown format for reliability.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
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
            heightValue = heightValue / 2.54 // cm -> in
            heightUnit = "in"
            // Convert goal weight kg -> lbs
            targetWeight = targetWeight * 2.20462
        } else {
            heightValue = heightValue * 2.54 // in -> cm
            heightUnit = "cm"
            // Convert goal weight lbs -> kg
            targetWeight = targetWeight / 2.20462
        }
        try? modelContext.save()
    }
}
