import SwiftUI

/// 年度节气时间线 — 按季分组展示 24 节气
struct SolarTermTimelineView: View {
    let yearTerms: [SolarTermInfo]
    let currentTerm: SolarTerm?

    private var termsBySeason: [(Season, [SolarTermInfo])] {
        let sorted = yearTerms.sorted { $0.date < $1.date }
        return Season.allCases.map { season in
            (season, sorted.filter { $0.term.season == season })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(termsBySeason, id: \.0) { season, terms in
                VStack(alignment: .leading, spacing: 8) {
                    // 季节标题
                    HStack(spacing: 6) {
                        Circle()
                            .fill(season.color)
                            .frame(width: 8, height: 8)
                        Text(season.displayName)
                            .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                            .foregroundStyle(season.color)
                    }
                    .padding(.leading, 4)

                    // 该季节的节气列表
                    VStack(spacing: 4) {
                        ForEach(terms) { info in
                            timelineRow(info: info)
                        }
                    }
                }
            }
        }
        .grainCardStyle(seed: 500)
    }

    @ViewBuilder
    private func timelineRow(info: SolarTermInfo) -> some View {
        let isCurrent = info.term == currentTerm
        HStack(spacing: 10) {
            Image(info.term.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(info.term.displayName)
                .font(.system(size: Theme.bodySize, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)

            Spacer()

            Text(info.date, format: .dateTime.month(.abbreviated).day())
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textSecondary)

            if isCurrent {
                Text(String(localized: "home.cycle_detail.current_badge"))
                    .font(.system(size: Theme.captionSize, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(info.term.season.color)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrent ? info.term.season.color.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
