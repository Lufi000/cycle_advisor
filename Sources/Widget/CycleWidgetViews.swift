import SwiftUI
import WidgetKit

// MARK: - Small Widget

struct CycleSmallWidgetView: View {
    let entry: CycleWidgetEntry

    private var metrics: HealthMetrics { context.healthMetrics }
    private var context: CycleContext { entry.context }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetMetricHeaderView(
                title: String(localized: "widget.today_health"),
                phase: context.phase,
                isPredicted: context.isPredicted
            )

            Spacer(minLength: 0)

            WidgetPrimaryMetricView(
                icon: "sun.max.fill",
                label: String(localized: "widget.daylight"),
                value: metrics.formattedDaylightDuration ?? "--",
                trend: metrics.daylightTrend,
                tint: Theme.phaseOvulation,
                compact: true
            )

            WidgetSecondaryMetricView(
                icon: "heart.fill",
                label: "HRV",
                value: hrvText,
                trend: metrics.hrvTrend,
                tint: Theme.phaseMenstrual
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var hrvText: String {
        guard let hrv = metrics.hrvCurrent else { return "--" }
        return "\(Int(hrv))ms"
    }
}

// MARK: - Medium Widget

struct CycleMediumWidgetView: View {
    let entry: CycleWidgetEntry

    private var context: CycleContext { entry.context }
    private var metrics: HealthMetrics { context.healthMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetMetricHeaderView(
                title: String(localized: "widget.today_health"),
                phase: context.phase,
                isPredicted: context.isPredicted
            )

            HStack(spacing: 10) {
                WidgetPrimaryMetricView(
                    icon: "sun.max.fill",
                    label: String(localized: "widget.daylight"),
                    value: metrics.formattedDaylightDuration ?? "--",
                    trend: metrics.daylightTrend,
                    tint: Theme.phaseOvulation,
                    compact: false
                )

                WidgetMetricDivider()

                VStack(alignment: .leading, spacing: 10) {
                    WidgetPrimaryMetricView(
                        icon: "heart.fill",
                        label: "HRV",
                        value: hrvText,
                        trend: metrics.hrvTrend,
                        tint: Theme.phaseMenstrual,
                        compact: false
                    )

                    if let avg = metrics.hrvWeeklyAvg {
                        Text(String(format: String(localized: "widget.hrv_avg %lld"), Int64(Int(avg))))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var hrvText: String {
        guard let hrv = metrics.hrvCurrent else { return "--" }
        return "\(Int(hrv))ms"
    }
}

// MARK: - Metric Views

struct WidgetMetricHeaderView: View {
    let title: String
    let phase: CyclePhase
    let isPredicted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                Text(phase.emoji)
                    .font(.system(size: 13))
                Text(isPredicted ? String(localized: "phase.predicted_label") : phase.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isPredicted ? Theme.textSecondary : phase.color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(phase.color.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}

struct WidgetPrimaryMetricView: View {
    let icon: String
    let label: String
    let value: String
    let trend: Trend?
    let tint: Color
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 13 : 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: compact ? 28 : 30, height: compact ? 28 : 30)
                    .background(tint.opacity(0.13))
                    .clipShape(Circle())

                Text(label)
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: compact ? 25 : 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if let trend {
                    Text(trend.symbol)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .foregroundStyle(trendColor(trend))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetSecondaryMetricView: View {
    let icon: String
    let label: String
    let value: String
    let trend: Trend?
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.13))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 0)

            if let trend {
                Text(trend.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(trendColor(trend))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.cardBackgroundSolid.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WidgetMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.textSecondary.opacity(0.14))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

private func trendColor(_ trend: Trend) -> Color {
    switch trend {
    case .rising:    return Theme.phaseFollicular
    case .stable:    return Theme.textSecondary
    case .declining: return Theme.phaseMenstrual
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    CycleAdvisorWidget()
} timeline: {
    CycleWidgetEntry(date: .now, context: MockData.lutealContext,
                     suggestion: MockData.sampleSuggestions.suggestion(for: .sleep))
    CycleWidgetEntry(date: .now, context: MockData.ovulationContext,
                     suggestion: MockData.sampleSuggestions.suggestion(for: .exercise))
}

#Preview("Medium", as: .systemMedium) {
    CycleAdvisorWidget()
} timeline: {
    CycleWidgetEntry(date: .now, context: MockData.follicularContext,
                     suggestion: MockData.sampleSuggestions.suggestion(for: .diet))
    CycleWidgetEntry(date: .now, context: MockData.menstrualContext,
                     suggestion: MockData.sampleSuggestions.suggestion(for: .mood))
}
