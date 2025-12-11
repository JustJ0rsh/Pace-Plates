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
    @State private var selectedChartDate: Date? = nil
    @State private var lockedChartDate: Date? = nil // Keeps summary open until X is clicked
    @State private var pendingDeleteEntry: WeightEntry? = nil
    @State private var showDeleteConfirm: Bool = false
    
    // Time filter
    private enum TimeRange: String, CaseIterable, Identifiable {
        case days7 = "7 Days"
        case month1 = "1 Month"
        case months6 = "6 Months"
        case year1 = "1 Year"
        var id: String { rawValue }
        var days: Int {
            switch self {
            case .days7: return 7
            case .month1: return 30
            case .months6: return 180
            case .year1: return 365
            }
        }
    }
    @State private var selectedRange: TimeRange = .days7
    
    // Dynamic domain for chart X-axis based on selected filter
    private var last7DaysDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let days = max(1, selectedRange.days - 1)
        let start = cal.date(byAdding: .day, value: -days, to: todayStart) ?? todayStart
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
                            // Filters row
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(TimeRange.allCases) { r in
                                        Button(r.rawValue) { selectedRange = r }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "calendar")
                                        Text(selectedRange.rawValue)
                                    }
                                    .padding(8)
                                    .background(AppTheme.secondaryBackgroundColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "scalemass")
                                    .foregroundStyle(AppTheme.textColor)
                                Text("Body Weight")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textColor)
                            }
                            // Compute and render the chart section in a smaller subview
                            let filtered = chartPrep(entries: weightEntries, preferredWeightUnit: preferredWeightUnit, xDomain: last7DaysDomain).sorted
                            WeightChartSection(
                                entries: filtered,
                                preferredWeightUnit: preferredWeightUnit,
                                weightGoal: weightGoal,
                                xDomain: last7DaysDomain,
                                selectedChartDate: $selectedChartDate,
                                lockedChartDate: $lockedChartDate
                            )
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
                            List {
                                ForEach(weightEntries) { entry in
                                    WeightEntryRowContent(
                                        entry: entry,
                                        isEditing: isEditing,
                                        onDelete: {
                                            pendingDeleteEntry = entry
                                            showDeleteConfirm = true
                                        }
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            pendingDeleteEntry = entry
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .scrollDisabled(true)
                            .frame(height: CGFloat(weightEntries.count) * 44)
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
            .alert("Delete Weight Entry?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { pendingDeleteEntry = nil }
                Button("Delete", role: .destructive) {
                    if let entry = pendingDeleteEntry {
                        withAnimation {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        }
                    }
                    pendingDeleteEntry = nil
                }
            } message: {
                if let entry = pendingDeleteEntry {
                    Text("Delete the weight entry from \(entry.date.formatted(date: .abbreviated, time: .omitted))?")
                }
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

// MARK: - Optimized Weight Entry Row Content
private struct WeightEntryRowContent: View {
    let entry: WeightEntry
    let isEditing: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            Text("\(String(format: "%.1f", entry.weight)) \(entry.weightUnit)")
                .foregroundStyle(.secondary)
            if isEditing {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .padding(.leading, 8)
            }
        }
        .foregroundColor(AppTheme.textColor)
        .contentShape(Rectangle())
    }
}

// MARK: - Extracted subview to lower type-checking complexity
private struct WeightChartSection: View {
    let entries: [WeightEntry]
    let preferredWeightUnit: String
    let weightGoal: String
    let xDomain: ClosedRange<Date>
    @Binding var selectedChartDate: Date?
    @Binding var lockedChartDate: Date?

    private func convertWeight(_ value: Double, from unit: String, to target: String) -> Double {
        if unit == target { return value }
        if unit == "kg" && target == "lbs" { return value * 2.20462 }
        if unit == "lbs" && target == "kg" { return value / 2.20462 }
        return value
    }

    var body: some View {
        // Precompute light-weight values to help the type-checker
        let convertedWeights = entries.map { convertWeight($0.weight, from: $0.weightUnit, to: preferredWeightUnit) }
        let cMin = convertedWeights.min() ?? 0
        let cMax = convertedWeights.max() ?? 0
        let cSpan = max(1.0, cMax - cMin)
        let cPad = max(0.5, cSpan * 0.15)
        let yLower = cMin - cPad
        let yUpper = cMax + cPad
        let yDomain: ClosedRange<Double> = (yLower <= yUpper) ? (yLower...yUpper) : (0...1)

        VStack(alignment: .leading, spacing: 8) {
            Chart(entries) { entry in
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", convertWeight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .symbol(Circle())
                .symbolSize(convertedWeights.count <= 8 ? 40 : 0)
                .foregroundStyle(AppTheme.accentColor)

                // Use locked date for persistent highlight
                if let displayDate = lockedChartDate ?? selectedChartDate,
                   Calendar.current.isDate(entry.date, inSameDayAs: displayDate) {
                    RuleMark(x: .value("Selected", entry.date))
                        .foregroundStyle(AppTheme.accentColor.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", convertWeight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))
                    )
                    .symbol(Circle())
                    .symbolSize(100)
                    .foregroundStyle(AppTheme.accentColor)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month().day())
                }
            }
            .chartXScale(domain: xDomain)
            .chartYAxis { AxisMarks(position: .leading) }
            .chartPlotStyle { plot in plot.background(.clear) }
            .chartXSelection(value: $selectedChartDate)
            .onChange(of: selectedChartDate) { _, newDate in
                // When user taps a new point, lock it
                if let newDate = newDate {
                    withAnimation(.easeOut(duration: 0.2)) {
                        lockedChartDate = newDate
                    }
                }
            }
            .frame(height: 200)
            .foregroundColor(AppTheme.textColor)

            // Selected-day summary (uses locked date to stay open until X is clicked)
            if let lockedDate = lockedChartDate,
               let selectedEntry = entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: lockedDate) }) {
                let selectedDate = lockedDate
                let entriesOnDay = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
                let previousEntry = entries.filter { $0.date < Calendar.current.startOfDay(for: selectedDate) }.last

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                lockedChartDate = nil
                                selectedChartDate = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().opacity(0.3)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weight")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f %@", convertWeight(selectedEntry.weight, from: selectedEntry.weightUnit, to: preferredWeightUnit), preferredWeightUnit))
                                .font(.title3.bold())
                        }

                        if let prev = previousEntry {
                            let currentWeight = convertWeight(selectedEntry.weight, from: selectedEntry.weightUnit, to: preferredWeightUnit)
                            let prevWeight = convertWeight(prev.weight, from: prev.weightUnit, to: preferredWeightUnit)
                            let change = currentWeight - prevWeight
                            let isUp = change >= 0
                            let isGoodChange = (weightGoal == "gain") ? isUp : !isUp

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Change")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                                        .font(.caption)
                                    Text(String(format: "%.1f %@", abs(change), preferredWeightUnit))
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(isGoodChange ? .green : .red)
                            }
                        }
                    }

                    if entriesOnDay.count > 1 {
                        Divider().opacity(0.3)
                        Text("\(entriesOnDay.count) entries this day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // WeightEntry has no notes field
                }
                .padding(12)
                .background(AppTheme.secondaryBackgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            // Latest vs oldest summary
            if let latest = entries.last, let oldest = entries.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.1f", convertWeight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(preferredWeightUnit)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entries.count >= 2 {
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
        }
    }
}
