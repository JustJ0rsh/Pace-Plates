import SwiftUI
import SwiftData
import Charts

struct WeightLogView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppTheme.storageKey) private var appTheme: AppThemeOption = .appDefault
    @AppStorage("weightLastHealthImportAt") private var weightLastHealthImportAt: Double = 0
    private let launchConfiguration = AppLaunchConfiguration.current
    @Query(sort: [SortDescriptor<WeightEntry>(\.date, order: .reverse)]) private var weightEntries: [WeightEntry] // Added sort
    @State private var showingLogWeightSheet = false // State to control sheet presentation
    @State private var showWeightActions = false
    @State private var isEditing: Bool = false
    @AppStorage("weightGoal") private var weightGoal: String = "lose" // "gain" or "lose"
    @AppStorage("weightUnit") private var preferredWeightUnit = "lbs"
    @State private var selectedChartDate: Date? = nil
    @State private var lockedChartDate: Date? = nil // Keeps summary open until X is clicked
    @State private var pendingDeleteEntry: WeightEntry? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var hasScheduledInitialImport = false
    @State private var saveErrorMessage: String? = nil
    @State private var quickViewEntry: WeightEntry? = nil

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
    
    var body: some View {
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
                            Text(weightTrendSummary(entries: filtered))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryTextColor)
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
                                description: Text("Log your current weight or import recent entries from Apple Health.")
                            )

                            Button {
                                showingLogWeightSheet = true
                            } label: {
                                Label("Log Weight", systemImage: "scalemass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                importHealthWeightsSilently(force: true)
                            } label: {
                                Label("Import from Health", systemImage: "heart.text.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .floatingTile()

                    // History Tile
                    if !weightEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("History")
                                .font(.headline)
                            LazyVStack(spacing: 0) {
                                ForEach(weightEntries) { entry in
                                    WeightEntryRowContent(
                                        entry: entry,
                                        preferredWeightUnit: preferredWeightUnit,
                                        isEditing: isEditing,
                                        onDelete: {
                                            pendingDeleteEntry = entry
                                            showDeleteConfirm = true
                                        }
                                    )
                                    .padding(.vertical, 8)
                                    .contextMenu {
                                        Button {
                                            quickViewEntry = entry
                                        } label: {
                                            Label("Quick View", systemImage: "eye")
                                        }

                                        Button(role: .destructive) {
                                            pendingDeleteEntry = entry
                                            showDeleteConfirm = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
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
                        }
                        .floatingTile()
                    }
                }
                .padding(.horizontal, AppTheme.padding)
                .padding(.top)
        }
        .accessibilityIdentifier("weight.ready")
        .appBackground(AppTheme.gradientWeight)
        .foregroundColor(AppTheme.textColor)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(AppTheme.toolbarColorScheme, for: .navigationBar)
        .tint(AppTheme.accentColor)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { isEditing.toggle() }) {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.headline)
                        .foregroundStyle(AppTheme.toolbarButtonColor)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showWeightActions = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.toolbarButtonColor)
                        .accessibilityLabel("Log Weight")
                }
            }
        }
        .sheet(isPresented: $showingLogWeightSheet) {
            LogWeightView()
        }
        .sheet(isPresented: $showWeightActions) {
            QuickActionSheet(
                title: "Weight Actions",
                actions: [
                    QuickActionSheetAction(
                        id: "weight.start-now",
                        title: "Start now",
                        subtitle: "Log your current weight.",
                        systemImage: "scalemass",
                        accessibilityIdentifier: "weight.action.start_now",
                        handler: { showingLogWeightSheet = true }
                    ),
                    QuickActionSheetAction(
                        id: "weight.import-health",
                        title: "Import from Health",
                        subtitle: "Pull recent weight entries from Apple Health.",
                        systemImage: "heart.text.square",
                        accessibilityIdentifier: "weight.action.import_health",
                        handler: { importHealthWeightsSilently(force: true) }
                    )
                ]
            )
        }
        .sheet(item: $quickViewEntry) { entry in
            WeightQuickViewSheet(
                entry: entry,
                comparisonEntry: comparisonEntry(for: entry),
                preferredWeightUnit: preferredWeightUnit,
                weightGoal: weightGoal
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete Weight Entry?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { pendingDeleteEntry = nil }
            Button("Delete", role: .destructive) {
                if let entry = pendingDeleteEntry {
                    withAnimation {
                        modelContext.delete(entry)
                        _ = PersistenceSave.commit(
                            modelContext,
                            action: "delete weight entry",
                            onFailure: { message in saveErrorMessage = message }
                        )
                    }
                }
                pendingDeleteEntry = nil
            }
        } message: {
            if let entry = pendingDeleteEntry {
                Text("Delete the weight entry from \(entry.date.formatted(date: .abbreviated, time: .omitted))?")
            }
        }
        .onAppear {
            if !launchConfiguration.shouldSkipAutomationSideEffects {
                scheduleInitialHealthImportIfNeeded()
            }
        }
        .background {
            Color.clear.alert("Save Failed", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "Couldn’t save your changes. Please try again.")
            }
        }
        .id(appTheme) // Force rebuild when theme changes
    }

    /// Silent auto-import on view appear (like runs/hikes/walks)
    private func importHealthWeightsSilently(force: Bool = false) {
        guard shouldImportHealthWeights(force: force) else { return }

        Task(priority: .utility) {
            do {
                // Request authorization if needed
                try await HealthKitManager.shared.requestAuthorization()

                // Fetch weight history from HealthKit
                let healthWeights = try await HealthKitManager.shared.getWeightHistory()

                // Get existing entry dates (start of day) to avoid duplicates
                let existingDates = await MainActor.run {
                    Set(weightEntries.map { Calendar.current.startOfDay(for: $0.date) })
                }

                // Collapse to the LATEST sample per day within this batch (same rule
                // as the manual import path), then drop days that already exist locally.
                let newWeights = HealthKitManager.latestWeightSamplesPerDay(healthWeights).filter { entry in
                    !existingDates.contains(Calendar.current.startOfDay(for: entry.date))
                }

                guard !newWeights.isEmpty else {
                    await MainActor.run {
                        weightLastHealthImportAt = Date().timeIntervalSince1970
                    }
                    return
                }

                // Import new entries silently
                await MainActor.run {
                    for entry in newWeights {
                        let unit = UnitConverter.canonicalWeightUnit(preferredWeightUnit)
                        let weight = UnitConverter.weight(entry.weightInPounds, from: "lbs", to: unit)

                        let newEntry = WeightEntry(date: entry.date, weight: weight, weightUnit: unit)
                        modelContext.insert(newEntry)
                    }

                    if PersistenceSave.commit(
                        modelContext,
                        action: "import Health weight entries",
                        onFailure: { message in saveErrorMessage = message }
                    ) {
                        weightLastHealthImportAt = Date().timeIntervalSince1970
                    }
                }
            } catch {
                // Silently ignore errors (like runs/hikes/walks)
            }
        }
    }

    private func scheduleInitialHealthImportIfNeeded() {
        guard !hasScheduledInitialImport else { return }
        hasScheduledInitialImport = true

        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            importHealthWeightsSilently()
        }
    }

    private func shouldImportHealthWeights(force: Bool) -> Bool {
        if force { return true }

        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval = 60 * 60 // 1 hour
        return now - weightLastHealthImportAt >= minInterval
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
        let convertedWeights = sorted.map { UnitConverter.weight($0.weight, from: $0.weightUnit, to: preferredWeightUnit) }
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

    private func comparisonEntry(for entry: WeightEntry) -> WeightEntry? {
        guard let index = weightEntries.firstIndex(where: { $0.id == entry.id }) else { return nil }
        let olderIndex = index + 1
        guard weightEntries.indices.contains(olderIndex) else { return nil }
        return weightEntries[olderIndex]
    }

    private func weightTrendSummary(entries: [WeightEntry]) -> String {
        guard let latest = entries.last else {
            return "Log a weight to see your trend."
        }

        let latestValue = UnitConverter.weight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)
        guard let oldest = entries.first, entries.count >= 2 else {
            return "Latest: \(latestValue.formatted(.number.precision(.fractionLength(1)))) \(preferredWeightUnit)."
        }

        let oldestValue = UnitConverter.weight(oldest.weight, from: oldest.weightUnit, to: preferredWeightUnit)
        let delta = latestValue - oldestValue
        guard abs(delta) >= 0.05 else {
            return "No change in \(rangeDescription)."
        }

        let direction = delta < 0 ? "Down" : "Up"
        let formatted = abs(delta).formatted(.number.precision(.fractionLength(1)))
        return "\(direction) \(formatted) \(preferredWeightUnit) over \(rangeDescription)."
    }

    private var rangeDescription: String {
        switch selectedRange {
        case .days7: return "7 days"
        case .month1: return "1 month"
        case .months6: return "6 months"
        case .year1: return "1 year"
        }
    }
}

// MARK: - Optimized Weight Entry Row Content
private struct WeightEntryRowContent: View {
    let entry: WeightEntry
    let preferredWeightUnit: String
    let isEditing: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
            Spacer()
            Text("\(String(format: "%.1f", UnitConverter.weight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))) \(preferredWeightUnit)")
                .foregroundStyle(AppTheme.secondaryTextColor)
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

private struct WeightQuickViewSheet: View {
    let entry: WeightEntry
    let comparisonEntry: WeightEntry?
    let preferredWeightUnit: String
    let weightGoal: String

    private var convertedWeight: Double {
        UnitConverter.weight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit)
    }

    private var weightChange: Double? {
        guard let comparisonEntry else { return nil }
        let previousValue = UnitConverter.weight(comparisonEntry.weight, from: comparisonEntry.weightUnit, to: preferredWeightUnit)
        return convertedWeight - previousValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight Entry")
                        .font(.title3.weight(.semibold))
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }

                quickMetric(
                    title: "Recorded Weight",
                    value: String(format: "%.1f %@", convertedWeight, preferredWeightUnit)
                )

                if let weightChange {
                    let isUp = weightChange >= 0
                    let isGoodChange = (weightGoal == "gain") ? isUp : !isUp

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Change From Previous Entry")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryTextColor)

                        HStack(spacing: 6) {
                            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                            Text(String(format: "%.1f %@", abs(weightChange), preferredWeightUnit))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        .foregroundStyle(isGoodChange ? .green : .red)
                    }
                    .padding(12)
                    .background(AppTheme.secondaryBackgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(AppTheme.padding)
        }
        .appBackground(AppTheme.gradientWeight)
        .foregroundStyle(AppTheme.textColor)
    }

    @ViewBuilder
    private func quickMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryTextColor)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.secondaryBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    var body: some View {
        // Precompute light-weight values to help the type-checker
        let convertedWeights = entries.map { UnitConverter.weight($0.weight, from: $0.weightUnit, to: preferredWeightUnit) }
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
                    y: .value("Weight", UnitConverter.weight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))
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
                        y: .value("Weight", UnitConverter.weight(entry.weight, from: entry.weightUnit, to: preferredWeightUnit))
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
                                .foregroundStyle(AppTheme.secondaryTextColor)
                        }
                    }

                    Divider().opacity(0.3)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weight")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryTextColor)
                            Text(String(format: "%.1f %@", UnitConverter.weight(selectedEntry.weight, from: selectedEntry.weightUnit, to: preferredWeightUnit), preferredWeightUnit))
                                .font(.title3.bold())
                        }

                        if let prev = previousEntry {
                            let currentWeight = UnitConverter.weight(selectedEntry.weight, from: selectedEntry.weightUnit, to: preferredWeightUnit)
                            let prevWeight = UnitConverter.weight(prev.weight, from: prev.weightUnit, to: preferredWeightUnit)
                            let change = currentWeight - prevWeight
                            let isUp = change >= 0
                            let isGoodChange = (weightGoal == "gain") ? isUp : !isUp

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Change")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryTextColor)
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
                            .foregroundStyle(AppTheme.secondaryTextColor)
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
                    Text(String(format: "%.1f", UnitConverter.weight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(preferredWeightUnit)
                        .font(.headline)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                    Spacer()
                    if entries.count >= 2 {
                        let latestConv = UnitConverter.weight(latest.weight, from: latest.weightUnit, to: preferredWeightUnit)
                        let oldestConv = UnitConverter.weight(oldest.weight, from: oldest.weightUnit, to: preferredWeightUnit)
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
