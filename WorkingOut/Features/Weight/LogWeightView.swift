import SwiftUI
import SwiftData

struct LogWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var weight: Double? // Use optional Double for TextField
    @FocusState private var weightFocused: Bool
    @AppStorage("weightUnit") private var weightUnit = "lbs" // Default unit
    
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
        }
    }
    
    private func saveWeight() {
        guard let weightValue = weight else { return }
        
        let newEntry = WeightEntry(weight: weightValue, weightUnit: weightUnit)
        modelContext.insert(newEntry)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            // Consider surfacing a user-facing alert if needed
        }
    }
} 
