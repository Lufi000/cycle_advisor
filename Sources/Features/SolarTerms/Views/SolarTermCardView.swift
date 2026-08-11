import SwiftUI

/// 节气信息卡片 — 展示单个节气的名称、日期、气候或养生信息
struct SolarTermCardView: View {
    let termInfo: SolarTermInfo
    let showWellnessTip: Bool

    init(termInfo: SolarTermInfo, showWellnessTip: Bool = false) {
        self.termInfo = termInfo
        self.showWellnessTip = showWellnessTip
    }

    private var term: SolarTerm { termInfo.term }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 节气名 + 插画
            HStack(spacing: 8) {
                Image(term.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(term.displayName)
                    .font(.system(size: Theme.titleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(term.season.displayName)
                    .font(.system(size: Theme.captionSize, weight: .medium))
                    .foregroundStyle(term.season.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(term.season.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            // 日期
            Text(termInfo.date, format: .dateTime.month(.wide).day())
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.textSecondary)

            // 气候描述
            Text(term.climateSummary)
                .font(.system(size: Theme.bodySize))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(Theme.lineSpacing)

            // 养生建议（可选）
            if showWellnessTip {
                Divider()
                    .foregroundStyle(Theme.textSecondary.opacity(0.2))

                VStack(alignment: .leading, spacing: 6) {
                    Text("🌿")
                        .font(.system(size: 16))
                    Text(term.wellnessTip)
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(Theme.lineSpacing)
                }

            }
        }
        .grainCardStyle(seed: UInt64(term.id + 200))
    }
}
