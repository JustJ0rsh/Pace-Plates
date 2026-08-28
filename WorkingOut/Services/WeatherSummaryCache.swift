import Foundation

/// Cached copy of the last successful weather fetch, so the Home weather tile
/// can render a real value immediately on launch instead of a placeholder
/// while CoreLocation and WeatherKit warm up.
///
/// Foundation-only so the freshness policy is exercised by
/// `scripts/weather_cache_logic_test_main.swift` with the open-source Swift
/// toolchain.
struct CachedWeatherSummary: Codable, Equatable {
    /// Cached values older than this are ignored at launch.
    static let maxUsableAge: TimeInterval = 90 * 60

    var temperatureC: Double
    var condition: String
    var symbolName: String
    var savedAt: Date

    /// Absolute age is used so a device clock moved backwards cannot make a
    /// cached value appear fresh forever.
    func isFresh(now: Date = Date(), maxAge: TimeInterval = CachedWeatherSummary.maxUsableAge) -> Bool {
        abs(now.timeIntervalSince(savedAt)) <= maxAge
    }
}

extension CodableFileStore where Value == CachedWeatherSummary {
    /// Store for the most recent weather summary.
    static var lastWeatherSummary: CodableFileStore<CachedWeatherSummary> {
        CodableFileStore(name: "weather-last-summary")
    }
}
