import SwiftUI
import SwiftData

struct LogWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight: Double? // Use optional Double for TextField
    @FocusState private var weightFocused: Bool
    @AppStorage("weightUnit") private var weightUnit = "lbs" // Default unit
    @State private var saveErrorMessage: String? = nil
    @State private var healthErrorMessage: String? = nil
    @State private var savedEntry: WeightEntry? = nil
    @State private var isSaving = false
    
    private var isInputValid: Bool {
        weight != nil && weight ?? 0 > 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Enter weight", value: $weight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($weightFocused)
                }
                
                Picker("Unit", selection: $weightUnit) {
                    Text("Pounds (lbs)").tag("lbs")
                    Text("Kilograms (kg)").tag("kg")
                }
            }
            .appBackground(AppTheme.gradientWeight)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .gesture(DragGesture().onChanged { _ in dismissKeyboard() })
            // The decimal pad has no return key, so give it an explicit Done.
            .keyboardToolbar {
                weightFocused = false
                dismissKeyboard()
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || savedEntry != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWeight()
                    }
                    .disabled(!isInputValid || isSaving || savedEntry != nil)
                }
            }
            .interactiveDismissDisabled(isSaving || savedEntry != nil)
            .onAppear { weightFocused = true }
            .alert("Saved in Pace & Plates", isPresented: Binding(
                get: { healthErrorMessage != nil },
                set: { if !$0 { healthErrorMessage = nil } }
            )) {
                Button("Retry") { healthErrorMessage = nil; syncWeightToHealth() }
                Button("Done") { healthErrorMessage = nil; dismiss() }
            } message: {
                Text(healthErrorMessage ?? "The weight could not be saved to Apple Health.")
            }
            .alert("Save Failed", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Couldn’t save your changes. Please try again.")
            }
        }
    }
    
    private func saveWeight() {
        guard let weightValue = weight else { return }
        
        let newEntry = WeightEntry(weight: weightValue, weightUnit: weightUnit)
        if CoachPersistence.isLocal(modelContext) { newEntry.provenance = "manual" }
        modelContext.insert(newEntry)

        if PersistenceSave.commit(
            modelContext,
            action: "save weight entry",
            onFailure: { message in saveErrorMessage = message }
        ) {
            savedEntry = newEntry
            syncWeightToHealth()
        } else {
            Haptics.notify(.error)
            modelContext.delete(newEntry)
        }
    }

    private func syncWeightToHealth() {
        guard let entry = savedEntry, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await HealthKitManager.shared.saveBodyWeight(entry.weight, unit: entry.weightUnit, date: entry.date) { sampleID in
                    if CoachPersistence.isLocal(modelContext) {
                        entry.sourceHealthSampleID = sampleID.uuidString
                        try modelContext.save()
                    }
                }
                isSaving = false
                Haptics.notify(.success)
                dismiss()
            } catch {
                if CoachPersistence.isLocal(modelContext), entry.sourceHealthSampleID != nil {
                    entry.sourceHealthSampleID = nil
                    try? modelContext.save()
                }
                isSaving = false
                Haptics.notify(.error)
                healthErrorMessage = "Your weight was saved in Pace & Plates, but not in Apple Health. \(error.localizedDescription)"
            }
        }
    }
}
