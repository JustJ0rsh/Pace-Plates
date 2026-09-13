import Foundation

/// Rotate bounded Health queries through the entire saved history, including
/// records whose source never supplies optional metrics.
enum CardioHealthRefreshPolicy {
    nonisolated static func isDue(lastAttempt: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastAttempt else { return true }
        // A clock correction must not strand a future-dated attempt.
        return lastAttempt > now || now.timeIntervalSince(lastAttempt) >= interval
    }

    struct Candidate {
        let id: UUID
        let date: Date
        let lastAttempt: Date?
    }

    nonisolated static func batchIDs(_ candidates: [Candidate], limit: Int) -> Set<UUID> {
        Set(candidates.sorted {
            let firstAttempt = $0.lastAttempt ?? .distantPast
            let secondAttempt = $1.lastAttempt ?? .distantPast
            if firstAttempt != secondAttempt { return firstAttempt < secondAttempt }
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(max(0, limit)).map(\.id))
    }
}
