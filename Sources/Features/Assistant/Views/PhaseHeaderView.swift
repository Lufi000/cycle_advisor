import SwiftUI

/// 助手页顶部 Header，展示关键健康指标。
/// 支持折叠：聊天时可以把“今日概览”和指标标签收成一条细状态条，留出更多沉浸式聊天空间。
struct PhaseHeaderView: View {
    let context: CycleContext
    let displayName: String
    @Binding var isCollapsed: Bool

    var body: some View {
        Group {
            if isCollapsed {
                collapsedHeader
            } else {
                expandedHeader
            }
        }
        .background(
            Theme.background
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - 展开态：标题 + 指标标签

    private var expandedHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayName)
                    Text(String(localized: "assistant.header.summary_title"))
                }
                .font(Theme.itim(size: 22))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isCollapsed = true
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.56))
                        .clipShape(Circle())
                }
                .accessibilityLabel(String(localized: "assistant.header.collapse_a11y"))
            }

            HStack(spacing: 10) {
                if let hrv = context.healthMetrics.hrvCurrent {
                    metricChip(
                        label: String(localized: "assistant.header.hrv"),
                        value: String(format: String(localized: "unit.hrv_ms %lld"), Int(hrv))
                    )
                }
                if let exercise = context.healthMetrics.formattedExerciseDuration {
                    metricChip(label: String(localized: "assistant.header.exercise"), value: exercise)
                }
                if let sleep = context.healthMetrics.formattedSleepDuration {
                    metricChip(label: String(localized: "assistant.header.sleep"), value: sleep)
                }
            }

            if let steps = context.healthMetrics.formattedSteps {
                HStack {
                    metricChip(label: String(localized: "assistant.header.steps"), value: steps)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 折叠态：单行状态条

    private var collapsedHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isCollapsed = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(displayName)
                    .lineLimit(1)
                Text(String(localized: "assistant.header.summary_title"))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(Theme.itim(size: 18))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "assistant.header.expand_a11y"))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func metricChip(label: String, value: String) -> some View {
        let parts = metricValueParts(value)
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.itim(size: 18))
                .foregroundStyle(Theme.accent)
            Text(parts.number)
                .font(Theme.itim(size: 18))
                .foregroundStyle(Color.black)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(Theme.itim(size: 18))
                    .foregroundStyle(Color.black.opacity(0.30))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 28)
        .frame(height: 33)
        .background(Color.white.opacity(0.56))
        .clipShape(Capsule())
    }

    private func metricValueParts(_ value: String) -> (number: String, unit: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstNonNumeric = trimmed.firstIndex(where: { !$0.isNumber && $0 != "." && $0 != "," }) else {
            return (trimmed, "")
        }
        let number = String(trimmed[..<firstNonNumeric]).trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = String(trimmed[firstNonNumeric...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? (trimmed, "") : (number, unit)
    }
}

#Preview {
    @Previewable @State var collapsed = false
    PhaseHeaderView(context: MockData.lutealContext, displayName: "Lufi", isCollapsed: $collapsed)
}
