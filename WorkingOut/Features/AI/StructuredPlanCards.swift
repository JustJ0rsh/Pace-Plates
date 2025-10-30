import SwiftUI
#if canImport(FoundationModels)
import Foundation

// Decodes a WorkoutPlan JSON string and renders a simple card-based view.
struct StructuredPlanCards: View {
    let plan: WorkoutPlan

    init(json: String) throws {
        let data = json.data(using: .utf8) ?? Data()
        let decoder = JSONDecoder()
        self.plan = try decoder.decode(WorkoutPlan.self, from: data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let week = plan.weeks.first {
                ForEach(0..<week.days.count, id: \.self) { i in
                    DayCard(day: week.days[i])
                }
            } else {
                Text("(No days)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DayCard: View {
    let day: Day
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(day.title, systemImage: iconName)
                    .font(.headline)
                Spacer()
            }
            if day.items.isEmpty {
                Text(day.type == .activeRecovery ? "Active Recovery" : (day.type == .rest ? "Rest Day" : ""))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(0..<day.items.count, id: \.self) { i in
                    let it = day.items[i]
                    Text(formatItem(it))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
    }
    
    private var iconName: String {
        switch day.type {
        case .strengthUpper, .strengthLower, .fullBodyStrength: return "dumbbell.fill"
        case .runEasy, .runTempo, .runIntervals, .longRun: return "figure.run"
        case .cyclingEndurance: return "bicycle"
        case .rowing: return "figure.rower"
        case .swimming: return "figure.pool.swim"
        case .activeRecovery: return "leaf"
        case .rest: return "bed.double"
        }
    }
    
    private func formatItem(_ it: Item) -> String {
        if let sets = it.sets, let reps = it.reps {
            if let w = it.suggestedWeight, !w.isEmpty {
                return "• \(it.name) — \(sets)x\(reps) @ \(w)"
            } else {
                return "• \(it.name) — \(sets)x\(reps)"
            }
        }
        if let d = it.distance, let u = it.distanceUnit {
            var s = "• \(it.name): \(String(format: "%.1f", d)) \(u)"
            if let p = it.pace { s += " @ \(p)" }
            if let m = it.durationMinutes { s += " (\(m) min)" }
            if let e = it.effort, !e.isEmpty { s += " — \(e)" }
            return s
        }
        return it.notes.map { "• \(it.name): \($0)" } ?? "• \(it.name)"
    }
}
#endif

