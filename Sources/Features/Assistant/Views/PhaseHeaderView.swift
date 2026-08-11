import SwiftUI

/// 助手页顶部固定 Header，展示关键健康指标
struct PhaseHeaderView: View {
    let context: CycleContext

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                if let hrv = context.healthMetrics.hrvCurrent {
                    metricChip(
                        label: String(localized: "assistant.header.hrv"),
                        value: String(format: String(localized: "unit.hrv_ms %lld"), Int(hrv))
                    )
                }
                if let exercise = context.healthMetrics.formattedExerciseDuration {
                    metricChip(label: String(localized: "assistant.header.exercise"), value: exercise)
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
        .padding(.bottom, 20)
        .background(
            Theme.background
                .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private func metricChip(label: String, value: String) -> some View {
        let parts = metricValueParts(value)
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.itim(size: 18))
                .foregroundStyle(Color.black.opacity(0.30))
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
    PhaseHeaderView(context: MockData.lutealContext)
}
