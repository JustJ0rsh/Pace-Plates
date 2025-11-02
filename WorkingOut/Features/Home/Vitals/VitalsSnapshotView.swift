import SwiftUI

struct VitalsSnapshotView: View {
    @StateObject private var model = VitalsModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vitals Snapshot")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.textColor)
                Spacer()
                Button {
                    Task { await model.loadVitals() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh Vitals")
            }

            LazyVGrid(columns: columns, spacing: 12) {
                VitalCard(title: "Resting HR", systemName: "heart.fill", value: model.restingHeartRate != "—" ? model.restingHeartRate : model.heartRate)
                VitalCard(title: "Steps", systemName: "figure.walk", value: model.stepsToday)
                VitalCard(title: "Active Energy", systemName: "flame.fill", value: model.activeEnergy)
                VitalCard(title: "HRV", systemName: "waveform.path.ecg", value: model.hrv)
                VitalCard(title: "SpO₂", systemName: "lungs.fill", value: model.spo2)
                VitalCard(title: "Body Temp", systemName: "thermometer.medium", value: model.bodyTemp)
                VitalCard(title: "Sleep", systemName: "bed.double.fill", value: model.sleepDuration)
                VitalCard(title: "Sleep Score", systemName: "zzz", value: model.simpleSleepScore == "—" ? "—" : model.simpleSleepScore + " / 100")
            }
        }
        .task {
            await model.loadVitals()
        }
        .refreshable {
            await model.loadVitals()
        }
        .floatingTile()
        .accessibilityElement(children: .contain)
    }
}

private struct VitalCard: View {
    let title: String
    let systemName: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.title3)
                .foregroundColor(AppTheme.accentColor)
                .frame(width: 32, height: 32)
                .background(AppTheme.secondaryBackgroundColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundColor(AppTheme.textColor)
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.secondaryBackgroundColor.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
