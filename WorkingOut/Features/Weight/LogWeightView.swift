import SwiftUI
import SwiftData

struct LogWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight: Double? // Use optional Double for TextField
    @FocusState private var weightFocused: Bool
    @AppStorage("weightUnit") private var weightUnit = "lbs" // Default unit
    @State private var saveErrorMessage: String? = nil
    
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
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveWeight()
                    }
                    .disabled(!isInputValid)
                }
            }
            .onAppear { weightFocused = true }
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
        modelContext.insert(newEntry)

        if PersistenceSave.commit(
            modelContext,
            action: "save weight entry",
            onFailure: { message in saveErrorMessage = message }
        ) {
            dismiss()
        } else {
            modelContext.delete(newEntry)
        }
    }
}
