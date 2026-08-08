import SwiftUI

enum HistoryRange: String, CaseIterable, Identifiable {
    case all
    case days30
    case months3
    case year1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Time"
        case .days30:
            return "30 Days"
        case .months3:
            return "3 Months"
        case .year1:
            return "1 Year"
        }
    }

    func contains(_ date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard self != .all else { return true }

        let today = calendar.startOfDay(for: now)
        let cutoff: Date?
        switch self {
        case .all:
            cutoff = nil
        case .days30:
            cutoff = calendar.date(byAdding: .day, value: -29, to: today)
        case .months3:
            cutoff = calendar.date(byAdding: .month, value: -3, to: today)
        case .year1:
            cutoff = calendar.date(byAdding: .year, value: -1, to: today)
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return cutoff.map { date >= $0 && date < tomorrow } ?? true
    }
}

struct HistoryFilterOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct HistoryFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedRange: HistoryRange
    @Binding var selectedCategory: String?

    @State private var draftSearchText = ""
    @FocusState private var isSearchFocused: Bool

    let resultCount: Int
    let searchPrompt: String
    let accessibilityIdentifier: String
    var categories: [HistoryFilterOption] = []

    private var hasActiveFilters: Bool {
        !draftSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            selectedRange != .all ||
            selectedCategory != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Find History", systemImage: "magnifyingglass")
                    .font(.headline)

                Spacer(minLength: 8)

                Text(resultCount == 1 ? "1 result" : "\(resultCount) results")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryTextColor)

                Button("Clear") {
                    clearFilters()
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(!hasActiveFilters)
                .opacity(hasActiveFilters ? 1 : 0.45)
                .accessibilityIdentifier("\(accessibilityIdentifier).clear_filters")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.secondaryTextColor)
                    .accessibilityHidden(true)

                TextField(searchPrompt, text: $draftSearchText)
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        applyDraftSearch()
                        isSearchFocused = false
                    }
                    .accessibilityLabel(searchPrompt)
                    .accessibilityIdentifier("\(accessibilityIdentifier).search")

                if !draftSearchText.isEmpty {
                    Button {
                        draftSearchText = ""
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.secondaryTextColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("\(accessibilityIdentifier).clear_search")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, draftSearchText.isEmpty ? 12 : 0)
            .frame(minHeight: 48)
            .background(AppTheme.secondaryBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(HistoryRange.allCases) { range in
                        HistoryFilterChip(
                            title: range.title,
                            isSelected: selectedRange == range,
                            accessibilityIdentifier: "\(accessibilityIdentifier).range.\(range.id)"
                        ) {
                            selectedRange = range
                        }
                    }

                    if !categories.isEmpty {
                        Divider()
                            .frame(height: 28)

                        HistoryFilterChip(
                            title: "All Types",
                            isSelected: selectedCategory == nil,
                            accessibilityIdentifier: "\(accessibilityIdentifier).category.all"
                        ) {
                            selectedCategory = nil
                        }

                        ForEach(categories) { category in
                            HistoryFilterChip(
                                title: category.title,
                                isSelected: selectedCategory == category.id,
                                accessibilityIdentifier: "\(accessibilityIdentifier).category.\(category.id)"
                            ) {
                                selectedCategory = category.id
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("\(accessibilityIdentifier).options")
        }
        .onAppear {
            if draftSearchText != searchText {
                draftSearchText = searchText
            }
        }
        .onChange(of: searchText) { _, newValue in
            if draftSearchText != newValue {
                draftSearchText = newValue
            }
        }
        .task(id: draftSearchText) {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            applyDraftSearch()
        }
    }

    private func clearFilters() {
        draftSearchText = ""
        searchText = ""
        selectedRange = .all
        selectedCategory = nil
    }

    private func applyDraftSearch() {
        guard searchText != draftSearchText else { return }
        searchText = draftSearchText
    }
}

struct HistoryNoResultsView: View {
    let title: String
    let message: String
    let accessibilityIdentifier: String
    let clearFilters: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: "magnifyingglass",
                description: Text(message)
            )
            .accessibilityIdentifier(accessibilityIdentifier)

            Button("Clear Filters", action: clearFilters)
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("\(accessibilityIdentifier).clear_filters")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct HistoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? AppTheme.accentColor : AppTheme.textColor)
            .background(
                isSelected
                    ? AppTheme.accentColor.opacity(0.18)
                    : AppTheme.secondaryBackgroundColor
            )
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        isSelected ? AppTheme.accentColor.opacity(0.45) : AppTheme.textColor.opacity(0.12),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
