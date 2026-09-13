#if DEBUG
import SwiftUI
import SwiftData

struct CoachRegressionChecksView: View {
    @State private var result = "Running Coach checks…"
    var body: some View {
        Text(result).font(.caption).padding().background(.regularMaterial)
            .accessibilityIdentifier("coach.regression.result")
            .task {
                do {
                    let executionCount = try await CoachExecutionRegressionChecks.run()
                    let persistenceCount = try await CoachPersistenceRegressionChecks.run()
                    let scheduleCount = try await CoachScheduleRegressionChecks.run()
                    result = "Coach checks passed: \(executionCount + persistenceCount + scheduleCount)"
                } catch { result = "Coach checks failed: \(error.localizedDescription)" }
            }
    }
}
#endif
