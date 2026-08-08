import Foundation
import CoreLocation
import SwiftUI
#if canImport(WeatherKit)
import WeatherKit
#endif

struct WeatherSummary: Equatable {
    var temperatureC: Double
    var condition: String
    var symbolName: String
}

protocol WeatherProviding {
    func currentWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSummary
}

final class WeatherClient: WeatherProviding {
    static let shared: WeatherProviding = WeatherClient()
    private init() {}

    enum WeatherError: Error { case unavailable }

    func currentWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSummary {
        #if canImport(WeatherKit)
        if #available(iOS 16.0, *) {
            let service = WeatherKit.WeatherService()
            let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let weather = try await service.weather(for: loc)
            let tempC = weather.currentWeather.temperature.converted(to: .celsius).value
            let condition = weather.currentWeather.condition.description
            let symbol = weather.currentWeather.symbolName
            return WeatherSummary(temperatureC: tempC, condition: condition, symbolName: symbol)
        } else {
            throw WeatherError.unavailable
        }
        #else
        throw WeatherError.unavailable
        #endif
    }
}

@MainActor
final class WeatherViewModel: NSObject, ObservableObject, @MainActor CLLocationManagerDelegate {
    @Published var summary: WeatherSummary? = nil
    @Published var errorText: String? = nil
    private let provider: WeatherProviding

    private let manager = CLLocationManager()
    private var isFetching = false

    init(provider: WeatherProviding = WeatherClient.shared) {
        self.provider = provider
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch() {
        guard !isFetching else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            // Defer prompting for location to the Runs tab as requested
            self.errorText = nil
            return
        }
        isFetching = true
        if let location = manager.location, isUsableRecentLocation(location) {
            Task { await load(for: location.coordinate) }
        } else {
            manager.requestLocation()
        }
    }

    private func load(for coord: CLLocationCoordinate2D) async {
        defer { isFetching = false }
        do {
            let s = try await provider.currentWeather(at: coord)
            self.summary = s
            self.errorText = nil
        } catch {
            self.summary = nil
            self.errorText = "Weather unavailable"
        }
    }

    private func isUsableRecentLocation(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 1_000
            && abs(location.timestamp.timeIntervalSinceNow) <= 300
    }

    // CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last(where: isUsableRecentLocation) {
            Task { await load(for: location.coordinate) }
        } else {
            isFetching = false
            errorText = "Current location not available"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isFetching = false
        errorText = "Location error: \(error.localizedDescription)"
    }
}
