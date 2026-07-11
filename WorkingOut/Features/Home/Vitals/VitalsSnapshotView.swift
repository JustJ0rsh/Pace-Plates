import SwiftUI

struct VitalsSnapshotView: View {
    @AppStorage(WearableDevicePreference.storageKey) private var preferredWearableRaw = WearableDevicePreference.none.rawValue
    @StateObject private var model = VitalsModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var selectedWearable: WearableDevicePreference {
        WearableDevicePreference(rawValue: preferredWearableRaw) ?? .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vitals Snapshot")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppTheme.textColor)
                    Text(selectedWearable.vitalsSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryTextColor)
                }
                Spacer()
                Button {
                    Task { await model.loadVitals(for: selectedWearable) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh Vitals")
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.metrics) { metric in
                    VitalCard(metric: metric)
                }
            }
        }
        .task(id: preferredWearableRaw) {
            await model.loadVitals(for: selectedWearable)
        }
        .refreshable {
            await model.loadVitals(for: selectedWearable)
        }
        .floatingTile()
        .accessibilityElement(children: .contain)
    }
}

private struct VitalCard: View {
    let metric: VitalMetric

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: metric.systemName)
                .font(.title3)
                .foregroundColor(AppTheme.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    AppTheme.secondaryBackgroundColor.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryTextColor)
                Text(metric.value)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
                Text(metric.source)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryTextColor)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            AppTheme.secondaryBackgroundColor,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.textColor.opacity(0.12), lineWidth: 1)
        )
    }
}
