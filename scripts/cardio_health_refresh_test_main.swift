import Foundation

// Run with:
// swiftc WorkingOut/Services/CardioHealthRefreshPolicy.swift scripts/cardio_health_refresh_test_main.swift -o /tmp/cardio-health-refresh-tests
// /tmp/cardio-health-refresh-tests
@main
struct CardioHealthRefreshTestMain {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        expect(CardioHealthRefreshPolicy.isDue(lastAttempt: nil, now: now, interval: 900), "unvisited history is immediately due")
        expect(!CardioHealthRefreshPolicy.isDue(lastAttempt: now, now: now.addingTimeInterval(899), interval: 900), "unchanged data waits for its interval")
        expect(CardioHealthRefreshPolicy.isDue(lastAttempt: now, now: now.addingTimeInterval(900), interval: 900), "data becomes eligible at its refresh boundary")
        expect(CardioHealthRefreshPolicy.isDue(lastAttempt: now.addingTimeInterval(60), now: now, interval: 900), "clock corrections cannot strand history")
        var history = (0..<151).map { index in
            CardioHealthRefreshPolicy.Candidate(
                id: UUID(),
                date: now.addingTimeInterval(Double(-index) * 86_400),
                lastAttempt: nil
            )
        }
        let oldestID = history.last!.id
        var visited: Set<UUID> = []
        for pass in 0..<4 {
            let batch = CardioHealthRefreshPolicy.batchIDs(history, limit: 50)
            expect(batch.count == 50, "Health queries remain bounded")
            visited.formUnion(batch)
            history = recordingAttempt(batch, in: history, at: now.addingTimeInterval(Double(pass)))
        }
        expect(visited.count == 151, "all saved workouts, including history beyond 100, get checked")
        expect(visited.contains(oldestID), "oldest saved workout is reached")

        // All eleven remain eligible forever, as when sources omit heart rate
        // or Health returns no readable workout. Attempts must still rotate.
        var missing = Array(history.prefix(11)).map {
            CardioHealthRefreshPolicy.Candidate(id: $0.id, date: $0.date, lastAttempt: nil)
        }
        let first = CardioHealthRefreshPolicy.batchIDs(missing, limit: 10)
        missing = recordingAttempt(first, in: missing, at: now)
        let second = CardioHealthRefreshPolicy.batchIDs(missing, limit: 10)
        expect(first.union(second).count == 11, "missing metrics cannot starve the eleventh item")
        missing = recordingAttempt(second, in: missing, at: now.addingTimeInterval(1))

        let neverAttempted = CardioHealthRefreshPolicy.Candidate(
            id: UUID(), date: .distantPast, lastAttempt: nil
        )
        expect(
            CardioHealthRefreshPolicy.batchIDs(missing + [neverAttempted], limit: 1) == [neverAttempted.id],
            "unvisited history takes precedence over previously attempted recent records"
        )
        expect(CardioHealthRefreshPolicy.batchIDs(history, limit: 0).isEmpty, "zero budget performs no work")
        print("PASS: bounded queries, complete history coverage, unavailable-data rotation, and unvisited priority")
    }

    private static func recordingAttempt(
        _ ids: Set<UUID>, in candidates: [CardioHealthRefreshPolicy.Candidate], at date: Date
    ) -> [CardioHealthRefreshPolicy.Candidate] {
        candidates.map {
            .init(id: $0.id, date: $0.date, lastAttempt: ids.contains($0.id) ? date : $0.lastAttempt)
        }
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
