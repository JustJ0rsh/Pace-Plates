import SwiftUI
import SwiftData
import Charts

struct WeightLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor<WeightEntry>(\.date, order: .reverse)]) private var weightEntries: [WeightEntry] // Added sort
    @State private var showingLogWeightSheet = false // State to control sheet presentation
    @State private var isEditing: Bool = false
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // "gain" or "lose"
    @AppStorage("weightUnit") private var preferredWeightUnit = "lbs"
    
    // Last 7 days domain for chart X-axis
    private var last7DaysDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return start...end
    }
    
    private func convertWeight(_ value: Double, from unit: String, to target: String) -> Double {
        if unit == target { return value }
        if unit == "kg" && target == "lbs" { return value * 2.20462 }
        if unit == "lbs" && target == "kg" { return value / 2.20462 }
        return value
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Chart Tile (unified header style)
                    VStack(alignment: .leading, spacing: 8) {
                        if !weightEntries.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "scalemass")
                                    .foregroundStyle(AppTheme.textColor)
                                Text("Body Weight")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textColor)
                            }

                            let data = chartPrep(entries: weightEntries, preferredWeightUnit: preferredWeightUnit, xDomain: last7DaysDomain)

                            Chart(data.sorted) { entry in
                                LineMark(
                                    x: .value("Date", entry.date),
                                    y: .value("Weight", convertWeight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))
                                )
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .symbol(Circle())
                                .symbolSize(data.convertedWeights.count <= 8 ? 40 : 0)
                                .foregroundStyle(AppTheme.accentColor)
                            }
                            .chartYScale(domain: data.yLower <= data.yUpper ? data.yLower...data.yUpper : 0...1)
                            .chartXAxis {
                                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.month().day())
                                }
                            }
                            .chartXScale(domain: last7DaysDomain)
                            .chartYAxis { AxisMarks(position: .leading) }
                            .chartPlotStyle { plot in plot.background(.clear) }
                            .frame(height: 200)
                            .foregroundColor(AppTheme.textColor)

                            if let latest = data.latest, let oldest = data.oldest {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(String(format: "%.1f", convertWeight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)))
                                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Text(preferredWeightUnit)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if data.sorted.count >= 2 {
                                        let latestConv = convertWeight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)
                                        let oldestConv = convertWeight(oldest.weight, from: oldest.weightUnit, to: preferredWeightUnit)
                                        let delta = latestConv - oldestConv
                                        let isUp = delta >= 0
                                        let arrow = isUp ? "arrow.up" : "arrow.down"
                                        let deltaText = String(format: "%.1f", abs(delta))
                                        let isGoodChange: Bool = (weightGoal == "gain") ? isUp : !isUp
                                        Label("\(deltaText) \(preferredWeightUnit)", systemImage: arrow)
                                            .font(.subheadline)
                                            .foregroundStyle(isGoodChange ? .green : .red)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        } else {
                            ContentUnavailableView(
                                "No Weight Logged",
                                systemImage: "scalemass.fill",
                                description: Text("Tap the + button to add your first weight entry.")
                            )
                        }
                    }
                    .floatingTile()

                    // History Tile
                    if !weightEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("History")
                                .font(.headline)
                            LazyVStack(spacing: 8) {
                                ForEach(weightEntries) { entry in
                                    HStack {
                                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        Spacer()
                                        Text("\(String(format: "%.1f", entry.weight)) \(entry.weightUnit)")
                                            .foregroundStyle(.secondary)
                                        if isEditing {
                                            Button(role: .destructive) {
                                                if let idx = weightEntries.firstIndex(where: { $0.id == entry.id }) {
                                                    deleteWeightEntries(offsets: IndexSet(integer: idx))
                                                }
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                    .foregroundColor(AppTheme.textColor)
                                    .padding(.vertical, 4)
                                    Divider().opacity(0.2)
                                }
                            }
                        }
                        .floatingTile()
                    }
                }
                .padding(.horizontal, AppTheme.padding)
            }
            .appBackground(AppTheme.gradientWeight)
            .foregroundColor(AppTheme.textColor)
            .navigationTitle("Weight")
            .toolbarBackground(AppTheme.backgroundColor, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(AppTheme.accentColor)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isEditing.toggle() }) {
                        Text(isEditing ? "Done" : "Edit")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingLogWeightSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityLabel("Log Weight")
                    }
                }
            }
            .sheet(isPresented: $showingLogWeightSheet) {
                LogWeightView()
            }
        }
    }
    
    private func deleteWeightEntries(offsets: IndexSet) {
        withAnimation { // Added animation
            offsets.map { weightEntries[$0] }.forEach(modelContext.delete)
            try? modelContext.save() // Save after deleting
        }
    }
    
    private func chartPrep(entries: [WeightEntry], preferredWeightUnit: String, xDomain: ClosedRange<Date>) -> (
        sorted: [WeightEntry],
        convertedWeights: [Double],
        yLower: Double,
        yUpper: Double,
        latest: WeightEntry?,
        oldest: WeightEntry?
    ) {
        let sortedAll = entries.sorted { $0.date < $1.date }
        // Filter to last 7 days
        let sorted = sortedAll.filter { $0.date >= xDomain.lowerBound && $0.date < xDomain.upperBound }
        let convertedWeights = sorted.map { convertWeight($0.weight, from: $0.weightUnit, to: preferredWeightUnit) }
        let cMin = convertedWeights.min() ?? 0
        let cMax = convertedWeights.max() ?? 0
        let cSpan = max(1.0, cMax - cMin)
        let cPad = max(0.5, cSpan * 0.15)
        let yLower = cMin - cPad
        let yUpper = cMax + cPad
        let latest = sorted.last
        let oldest = sorted.first

        return (sorted, convertedWeights, yLower, yUpper, latest, oldest)
    }
} 

