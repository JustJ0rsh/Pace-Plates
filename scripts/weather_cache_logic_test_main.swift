import Foundation

/// Standalone test for the cached weather summary used by the Home tile.
///
/// Compile with the app sources it exercises (no Apple UI frameworks needed):
///
///   swiftc -swift-version 5 \
///     WorkingOut/Services/WeatherSummaryCache.swift \
///     WorkingOut/Services/CodableFileStore.swift \
///     scripts/weather_cache_logic_test_main.swift \
///     -o /tmp/weather_cache_test && /tmp/weather_cache_test
@main
struct WeatherCacheLogicTestMain {
    static func main() {
        testFreshness()
        testRoundTrip()
        print("PASS: weather-cache logic test")
    }

    static func testFreshness() {
        let now = Date()
        let fresh = CachedWeatherSummary(temperatureC: 21, condition: "Clear", symbolName: "sun.max.fill", savedAt: now.addingTimeInterval(-600))
        expect(fresh.isFresh(now: now), "10-minute-old summary is fresh")

        let borderline = CachedWeatherSummary(temperatureC: 21, condition: "Clear", symbolName: "sun.max.fill", savedAt: now.addingTimeInterval(-CachedWeatherSummary.maxUsableAge))
        expect(borderline.isFresh(now: now), "summary exactly at the age limit is still usable")

        let stale = CachedWeatherSummary(temperatureC: 21, condition: "Clear", symbolName: "sun.max.fill", savedAt: now.addingTimeInterval(-(CachedWeatherSummary.maxUsableAge + 1)))
        expect(!stale.isFresh(now: now), "summary older than the limit is stale")

        let clockRollback = CachedWeatherSummary(temperatureC: 21, condition: "Clear", symbolName: "sun.max.fill", savedAt: now.addingTimeInterval(CachedWeatherSummary.maxUsableAge + 60))
        expect(!clockRollback.isFresh(now: now), "summary 'from the future' after a clock rollback is not trusted")
    }

    static func testRoundTrip() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weather-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodableFileStore<CachedWeatherSummary>(fileURL: directory.appendingPathComponent("summary.json"))

        expect(store.load() == nil, "load returns nil before anything was cached")

        let summary = CachedWeatherSummary(temperatureC: 17.5, condition: "Partly Cloudy", symbolName: "cloud.sun.fill", savedAt: Date())
        store.save(summary)
        expect(store.load() == summary, "summary round-trips through the store")

        store.clear()
        expect(store.load() == nil, "clear removes the cached summary")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            Foundation.exit(1)
        }
    }
}
