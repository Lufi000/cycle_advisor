import SwiftUI

/// 首页备孕卡片：黄体期进度 / 验孕提示（possible / likely）+ 触发原因 + 反馈闭环。
/// 合规红线：文案只出现"可能怀孕 / 建议验孕确认"，永不出现"你已怀孕"。
struct ConceptionCardView: View {

    private var manager = ConceptionInsightManager.shared
    private var store = ConceptionStore.shared
    @State private var isBBTEntryPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if manager.recentTemperatures.count >= 2 {
                TemperatureSparkline(entries: manager.recentTemperatures)
                    .frame(height: 44)
            }

            content

            NavigationLink {
                TemperatureLogView()
            } label: {
                HStack {
                    Text("conception.log.title")
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.cardPadding)
        .grainCardStyle(seed: 701)
        .sheet(isPresented: $isBBTEntryPresented) {
            BBTEntryView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Label(String(localized: "conception.card.title"), systemImage: "thermometer.medium")
                .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                isBBTEntryPresented = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "conception.bbt.entry"))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.insight {
        case .insufficient:
            if case .positive = store.testFeedback {
                Text("conception.card.positive_recorded")
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("-")
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textSecondary)
            }

        case .tracking(let lutealDay):
            Text(String(format: String(localized: "conception.card.luteal_day"), Int64(lutealDay)))
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

        case .possible(let reasons):
            promptBody(
                title: String(localized: "conception.card.possible"),
                reasons: reasons
            )

        case .likely(let reasons):
            promptBody(
                title: String(localized: "conception.card.likely"),
                reasons: reasons
            )
        }
    }

    private func promptBody(title: String, reasons: [InsightReason]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: Theme.bodySize, weight: .semibold))
                .foregroundStyle(Theme.accent)

            ForEach(reasons, id: \.self) { reason in
                Text("· \(reasonText(reason))")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                Button(String(localized: "conception.feedback.positive")) {
                    manager.recordPositive()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button(String(localized: "conception.feedback.negative")) {
                    manager.recordNegative()
                }
                .buttonStyle(.bordered)

                Button(String(localized: "conception.feedback.dismiss")) {
                    manager.dismissPrompt()
                }
                .buttonStyle(.borderless)
                .font(.system(size: Theme.captionSize))
            }
            .font(.system(size: Theme.bodySize))
        }
    }

    private func reasonText(_ reason: InsightReason) -> String {
        switch reason {
        case .sustainedHighTemperature(let days):
            return String(format: String(localized: "conception.reason.high_temp"), Int64(days))
        case .periodLate(let days):
            return String(format: String(localized: "conception.reason.period_late"), Int64(days))
        case .elevatedRestingHeartRate(let delta):
            return String(format: String(localized: "conception.reason.rhr"), Int64(delta))
        case .suppressedHRV(let percent):
            return String(format: String(localized: "conception.reason.hrv"), Int64(percent))
        case .earlySymptoms(let count):
            return String(format: String(localized: "conception.reason.symptoms"), Int64(count))
        }
    }
}

#Preview {
    ConceptionCardView()
        .padding()
        .background(Theme.background)
}
