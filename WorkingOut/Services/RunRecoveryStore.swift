import Foundation
import os

struct RunRecoverySnapshot: Codable, Sendable {
    struct Point: Codable, Sendable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let timestamp: Date
    }

    let sessionID: UUID
    let startDate: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let distanceUnit: String
    let activityType: String
    let plannedTarget: ScheduledRunTarget?
    let points: [Point]
    var recordedAt: Date? = nil
    var completedPauses: [DateInterval]? = nil

    var isValid: Bool {
        duration.isFinite && duration >= 0 && distanceMeters.isFinite && distanceMeters >= 0 &&
        startDate.timeIntervalSince1970.isFinite && ["mi", "km"].contains(distanceUnit) &&
        points.allSatisfy {
            $0.latitude.isFinite && (-90...90).contains($0.latitude) &&
            $0.longitude.isFinite && (-180...180).contains($0.longitude) &&
            $0.altitude.isFinite && $0.timestamp.timeIntervalSince1970.isFinite
        }
    }
}

/// Serial disk operations preserve save/discard ordering without doing JSON or
/// file I/O on the UI thread. This local recovery file is excluded from backup.
final class RunRecoveryStore: @unchecked Sendable {
    static let shared = RunRecoveryStore()
    private let queue = DispatchQueue(label: "pace.run-recovery", qos: .utility)
    private let logger = Logger(subsystem: "Jorsh.WorkingOut", category: "run-recovery")
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ActiveRun/recovery.json")
    }

    func save(_ snapshot: RunRecoverySnapshot) {
        queue.async { [self] in
            do {
                guard snapshot.isValid else { return }
                let directory = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var directoryURL = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directoryURL.setResourceValues(values)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            } catch {
                logger.error("Could not checkpoint active run: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func load() async -> RunRecoverySnapshot? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? JSONDecoder().decode(RunRecoverySnapshot.self, from: data),
                      snapshot.isValid else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: snapshot)
            }
        }
    }

    func clear() {
        queue.async { [self] in
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                logger.error("Could not remove active run checkpoint: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
