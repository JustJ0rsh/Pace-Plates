import Foundation
import CoreLocation
import MapKit

/// Pace bucket used to color route polylines. Kept as a plain enum so the
/// preparation work can run off the main actor and the view decides the colors.
enum RoutePaceClass: Sendable {
    case walk
    case jog
    case run
}

struct RouteRenderSegment: Sendable {
    let points: [CLLocationCoordinate2D]
    let pace: RoutePaceClass
}

struct RouteRenderParameters: Sendable {
    var mapSimplifyMaxPoints: Int = 700
    var mapSimplifyMinDistanceMeters: Double = 6
    /// Speed thresholds in m/s.
    var walkMaxSpeed: Double = 1.5
    var jogMaxSpeed: Double = 3.0
}

/// Everything the run detail map needs, computed from a session's stored route
/// JSON. Decoding and simplifying a long route (thousands of points) is the
/// single largest chunk of synchronous work on the run detail screen, so this
/// is a pure value-in / value-out pipeline that can run on a background task.
struct RouteRenderPreparation: Sendable {
    let decoded: [RunCoordinate]
    let simplified: [CLLocationCoordinate2D]
    let segments: [RouteRenderSegment]

    static let empty = RouteRenderPreparation(decoded: [], simplified: [], segments: [])

    static func make(
        from locations: Data,
        duration: TimeInterval,
        parameters: RouteRenderParameters = RouteRenderParameters()
    ) -> RouteRenderPreparation {
        guard !locations.isEmpty,
              let decoded = try? JSONDecoder().decode([RunCoordinate].self, from: locations),
              !decoded.isEmpty else {
            return .empty
        }
        let simplified = simplifyForMap(decoded.map(\.cl), parameters: parameters)
        let segments = buildSegments(from: simplified, duration: duration, parameters: parameters)
        return RouteRenderPreparation(decoded: decoded, simplified: simplified, segments: segments)
    }

    // MARK: - Simplification

    private static func simplifyForMap(
        _ points: [CLLocationCoordinate2D],
        parameters: RouteRenderParameters
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var reduced: [CLLocationCoordinate2D] = [points[0]]
        reduced.reserveCapacity(min(points.count, parameters.mapSimplifyMaxPoints))
        var last = CLLocation(latitude: points[0].latitude, longitude: points[0].longitude)

        for point in points.dropFirst().dropLast() {
            let current = CLLocation(latitude: point.latitude, longitude: point.longitude)
            if current.distance(from: last) >= parameters.mapSimplifyMinDistanceMeters {
                reduced.append(point)
                last = current
            }
        }
        reduced.append(points[points.count - 1])
        return trimToMaxPoints(reduced, maxPoints: parameters.mapSimplifyMaxPoints)
    }

    private static func trimToMaxPoints(_ points: [CLLocationCoordinate2D], maxPoints: Int) -> [CLLocationCoordinate2D] {
        guard points.count > maxPoints, maxPoints > 2 else { return points }
        let first = points[0]
        let last = points[points.count - 1]
        let interiorLimit = maxPoints - 2
        let interiorCount = points.count - 2
        if interiorCount <= interiorLimit { return points }

        var trimmed: [CLLocationCoordinate2D] = [first]
        trimmed.reserveCapacity(maxPoints)
        let step = Double(interiorCount) / Double(interiorLimit)
        var lastIndex = 0
        for i in 1...interiorLimit {
            let raw = Int((Double(i) * step).rounded(.down))
            let index = min(max(1, raw), points.count - 2)
            if index == lastIndex { continue }
            trimmed.append(points[index])
            lastIndex = index
        }
        trimmed.append(last)
        return trimmed
    }

    // MARK: - Pace segments

    private static func buildSegments(
        from points: [CLLocationCoordinate2D],
        duration: TimeInterval,
        parameters: RouteRenderParameters
    ) -> [RouteRenderSegment] {
        guard points.count > 1 else { return [] }
        // Stored routes carry no per-point timestamps for pace, so approximate a
        // uniform time step from the session duration.
        let total = Double(points.count - 1)
        let avgDt = max(duration / max(total, 1), 1)

        func paceClass(forSpeed v: Double) -> RoutePaceClass {
            if v <= parameters.walkMaxSpeed { return .walk }
            if v <= parameters.jogMaxSpeed { return .jog }
            return .run
        }

        var segments: [RouteRenderSegment] = []
        var currentPace: RoutePaceClass? = nil
        var currentPoints: [CLLocationCoordinate2D] = []

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            let distance = MKMapPoint(a).distance(to: MKMapPoint(b))
            let pace = paceClass(forSpeed: distance / max(avgDt, 1))
            if currentPace == nil {
                currentPace = pace
                currentPoints = [a, b]
            } else if pace == currentPace {
                currentPoints.append(b)
            } else {
                if currentPoints.count >= 2, let currentPace {
                    segments.append(RouteRenderSegment(points: currentPoints, pace: currentPace))
                }
                currentPace = pace
                currentPoints = [a, b]
            }
        }
        if currentPoints.count >= 2, let currentPace {
            segments.append(RouteRenderSegment(points: currentPoints, pace: currentPace))
        }
        return segments
    }
}
