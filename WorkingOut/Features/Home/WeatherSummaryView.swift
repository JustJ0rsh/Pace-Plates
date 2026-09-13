import SwiftUI

struct WeatherSummaryView: View {
    private let launchConfiguration = AppLaunchConfiguration.current
    @StateObject private var vm = WeatherViewModel()
    @AppStorage("measurementSystem") private var measurementSystem: String = "imperial"

    private var displayedSummary: WeatherSummary? {
        launchConfiguration.stubWeatherSummary ?? vm.summary
    }

    private var displayedErrorText: String? {
        launchConfiguration.stubWeatherSummary == nil ? vm.errorText : nil
    }

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
                        .foregroundColor(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh weather")
            }

            if let s = displayedSummary {
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
                            // `.title` is 28pt at the default size and scales with Dynamic Type.
                            .font(.title.weight(.semibold))
                        Text(s.condition)
                            .foregroundStyle(AppTheme.secondaryTextColor)
                    }
                    Spacer()
                }
            } else if let err = displayedErrorText {
                Text(err)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            } else {
                Text("—")
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }

            if displayedSummary != nil {
                HStack {
                    Spacer()
                    Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "apple.logo")
                            Text("Weather")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .floatingTile()
        .onAppear {
            guard launchConfiguration.stubWeatherSummary == nil else { return }
            // Throttle initial fetch slightly to avoid contention with other stores at app startup
            Task { try? await Task.sleep(nanoseconds: 300_000_000); vm.fetch() }
        }
    }
}

#Preview {
    WeatherSummaryView()
}
