#if DEBUG
import SwiftUI

/// Explicit synthetic test entry point. It is not reachable in Release and
/// exercises disposable directories, never the selected application history.
struct StorageIntegrationAcceptanceView: View {
    @State private var status = "Running synthetic storage checks…"
    @State private var started = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Synthetic storage acceptance").font(.title2.bold())
            Text(status).accessibilityIdentifier("storage.acceptance.result")
        }
        .padding()
        .task {
            guard !started, AppLaunchConfiguration.current.usesIsolatedStore else { return }
            started = true
            let runID = UUID().uuidString
            let startedAt = ISO8601DateFormatter().string(from: Date())
            let result: [String: Any]
            do {
                let count = try await CoachPersistenceRegressionChecks.run()
                let coldUnavailable = CoachPersistenceRegressionChecks.coldSourceMigrationStatus.hasPrefix("unsupported")
                status = "PASS: \(count) synthetic storage checks"
                    + (coldUnavailable ? "\nCold-source migration is unavailable; recovery safely retains its history." : "")
                result = ["result": coldUnavailable ? "passed_with_limitations" : "passed", "checks": count,
                          "scope": "Disposable synthetic SwiftData stores; no real integrations",
                          "runID": runID, "startedAt": startedAt,
                          "coldSourceMigration": CoachPersistenceRegressionChecks.coldSourceMigrationStatus,
                          "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                          "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""]
            } catch {
                status = "FAIL: \(error.localizedDescription)"
                result = ["result": "failed", "error": error.localizedDescription,
                          "runID": runID, "startedAt": startedAt,
                          "coldSourceMigration": CoachPersistenceRegressionChecks.coldSourceMigrationStatus,
                          "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                          "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                          "scope": "Disposable synthetic SwiftData stores; no real integrations"]
            }
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("PaceStorageAcceptance.json")
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                status += " (Could not save acceptance receipt: \(error.localizedDescription))"
            }
        }
    }
}
#endif
