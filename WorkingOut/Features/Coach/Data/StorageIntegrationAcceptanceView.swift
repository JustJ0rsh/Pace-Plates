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
            let result: [String: Any]
            do {
                let count = try await CoachPersistenceRegressionChecks.run()
                status = "PASS: \(count) synthetic storage checks"
                result = ["result": "passed", "checks": count,
                          "scope": "Disposable synthetic SwiftData stores; no real integrations",
                          "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                          "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""]
            } catch {
                status = "FAIL: \(error.localizedDescription)"
                result = ["result": "failed", "error": error.localizedDescription,
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
