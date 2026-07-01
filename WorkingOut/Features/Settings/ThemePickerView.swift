import SwiftUI

struct ThemePickerView: View {
    @Binding var appTheme: AppThemeOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(AppThemeOption.allCases) { option in
                    Button {
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            appTheme = option
                        }
                    AppTheme.applyGlobalTheme()
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(swatchColor(for: option))
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(AppTheme.textColor.opacity(0.2), lineWidth: 1))

                            Text(option.displayName)
                                .foregroundStyle(AppTheme.textColor)

                            Spacer()

                            if option == appTheme {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Theme applies immediately across the app.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .appBackground(AppTheme.gradientSettings)
        .tint(AppTheme.accentColor)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func swatchColor(for option: AppThemeOption) -> Color {
        switch option {
        case .appDefault: return Color(hex: 0x008CFF)
        case .light: return Color(hex: 0x0A84FF)
        case .dark: return Color(hex: 0x0A84FF)
        case .ocean: return Color(hex: 0x00C2FF)
        case .sunset: return Color(hex: 0xFF7A00)
        case .forest: return Color(hex: 0x34C759)
        }
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

#Preview {
    @Previewable @State var theme: AppThemeOption = .appDefault
    return NavigationStack { ThemePickerView(appTheme: $theme) }
}
