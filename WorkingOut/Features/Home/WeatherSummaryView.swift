import SwiftUI

struct WeatherSummaryView: View {
    @StateObject private var vm = WeatherViewModel()
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Weather")
                    .font(.headline)
                Spacer()
                Button {
                    vm.fetch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }

            if let s = vm.summary {
                HStack(spacing: 12) {
                    Image(systemName: s.symbolName)
                        .imageScale(.large)
                    VStack(alignment: .leading) {
                        let tempDisplay: String = {
                            if measurementSystem == "imperial" {
                                let f = s.temperatureC * 9.0/5.0 + 32.0
                                return String(format: "%.0fºF", f)
                            } else {
                                return String(format: "%.0fºC", s.temperatureC)
                            }
                        }()
                        Text(tempDisplay)
                            .font(.system(size: 28, weight: .semibold))
                        Text(s.condition)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else if let err = vm.errorText {
                Text(err)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, AppTheme.padding)
        .padding(.vertical, 12)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { vm.fetch() }
    }
}

#Preview {
    WeatherSummaryView()
}
