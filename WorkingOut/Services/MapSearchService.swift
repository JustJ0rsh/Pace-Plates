import Foundation
import MapKit

// Global throttled MapKit search helper to avoid PlaceRequest throttling.
// Serializes MKLocalSearch calls and enforces a minimum delay between requests.
actor MapSearchService {
    static let shared = MapSearchService()

    // Cache by rounded coordinate key to coalesce nearby points
    private var cache: [String: String] = [:]
    private var lastRequestAt: Date? = nil

    // Persistent cache using UserDefaults
    private let cacheKey = "MapSearchService.locationCache"
    private var persistentCache: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String] ?? [:]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cacheKey)
        }
    }

    // Allow up to ~25 requests/minute (minDelay ~2.4s between calls) to stay well under Apple's limits
    // Apple allows ~400 requests per 10 minutes, so we target ~150 requests per 10 minutes for safety
    private let minDelay: TimeInterval = 4.0

    func reverseAddressName(near coordinate: CLLocationCoordinate2D) async -> String? {
        let key = Self.key(for: coordinate)

        // Check in-memory cache first
        if let cached = cache[key] { return cached }

        // Check persistent cache
        if let cached = persistentCache[key] {
            cache[key] = cached // Promote to in-memory cache
            return cached
        }

        // Throttle: wait if last request was too recent
        if let last = lastRequestAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minDelay {
                let wait = minDelay - elapsed
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }

        // Prepare MapKit search for nearest address within a small region
        let span = MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
        let region = MKCoordinateRegion(center: coordinate, span: span)
        let request = MKLocalSearch.Request()
        request.resultTypes = .address
        request.region = region
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            lastRequestAt = Date()
            if let item = response.mapItems.first, let name = item.name, !name.isEmpty {
                cache[key] = name
                var persistent = persistentCache
                persistent[key] = name
                self.persistentCache = persistent
                return name
            }
        } catch {
            lastRequestAt = Date()
        }

        return nil
    }

    private static func key(for coordinate: CLLocationCoordinate2D) -> String {
        // Round to ~11m resolution to reuse addresses for very close points
        let lat = (coordinate.latitude * 10000).rounded() / 10000
        let lon = (coordinate.longitude * 10000).rounded() / 10000
        return String(format: "%.4f,%.4f", lat, lon)
    }
}

