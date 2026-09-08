import SwiftUI

/// 温度记录列表：按日期倒序展示每日体温（手表腕温 + 手动 BBT），含来源与干扰标记。
struct TemperatureLogView: View {

    private var manager = ConceptionInsightManager.shared

    private var entries: [BasalTemperatureEntry] {
        manager.mergedTemperatures.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if entries.isEmpty {
                    Text("conception.log.empty")
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 48)
                } else {
                    ForEach(entries, id: \.date) { entry in
                        row(entry)
                    }
                }
            }
            .padding(16)
        }
        .background(
            Theme.background
                .grainTexture(intensity: .subtle, seed: 711)
                .ignoresSafeArea()
        )
        .navigationTitle(String(localized: "conception.log.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: BasalTemperatureEntry) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.year().month().day())
                    .font(.system(size: Theme.bodySize, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)

                if entry.source == .manual, !entry.disturbances.isEmpty {
                    Text(entry.disturbances.map(\.displayName).joined(separator: " · "))
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    Image(systemName: entry.source == .wristTemperature ? "applewatch" : "pencil.line")
                        .font(.system(size: 11))
                    Text(entry.source == .wristTemperature
                         ? String(localized: "conception.log.source.wrist")
                         : String(localized: "conception.log.source.manual"))
                        .font(.system(size: Theme.captionSize))
                }
                .foregroundStyle(Theme.textSecondary)

                Text(String(format: "%.2f°C", entry.celsius))
                    .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(Theme.cardPadding)
        .grainCardStyle(seed: UInt64(entry.date.timeIntervalSince1970) % 997)
    }
}

#Preview {
    NavigationStack {
        TemperatureLogView()
    }
}
