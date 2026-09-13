import Foundation
import CoreLocation

struct RunCoordinate: Codable, Identifiable, Sendable {
    var id = UUID()
    var latitude: Double
    var longitude: Double
    var altitude: Double? = nil // meters above sea level
    var timestamp: Date? = nil // When this coordinate was recorded
    var cl: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case altitude
        case timestamp
    }
}
