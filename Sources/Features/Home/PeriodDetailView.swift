import SwiftUI

/// 经期详情卡片：展示出血量和当前症状
struct PeriodDetailView: View {
    let symptoms: MenstrualSymptoms
    let phase: CyclePhase
    let dayInPhase: Int
    var showsFlow: Bool = true

    init(symptoms: MenstrualSymptoms, phase: CyclePhase, dayInPhase: Int, showsFlow: Bool = true) {
        self.symptoms = symptoms
        self.phase = phase
        self.dayInPhase = dayInPhase
        self.showsFlow = showsFlow
    }

    private var activeSymptoms: [SymptomEntry] {
        symptoms.activeSymptoms
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题行
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.phaseMenstrual)
                Text("period.detail.title")
                    .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(phase.displayName)
                    .font(.system(size: Theme.captionSize, weight: .medium))
                    .foregroundStyle(phase.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(phase.color.opacity(0.15))
                    .clipShape(Capsule())
            }

            // 出血量
            if showsFlow, let flow = symptoms.flowLevel {
                HStack(spacing: 8) {
                    Text("period.detail.flow")
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(Theme.textSecondary)
                    flowIndicator(flow)
                    Spacer()
                }
            }

            // 症状列表
            if !activeSymptoms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("period.detail.symptoms")
                        .font(.system(size: Theme.bodySize))
                        .foregroundStyle(Theme.textSecondary)

                    FlowLayout(spacing: 6) {
                        ForEach(activeSymptoms) { entry in
                            symptomChip(entry)
                        }
                    }
                }
            }

            // 无数据提示
            if (showsFlow ? symptoms.flowLevel == nil : true) && activeSymptoms.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("period.detail.no_data")
                        .font(.system(size: Theme.bodySize))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .grainCardStyle(seed: 666)
    }

    // MARK: - Flow Indicator

    @ViewBuilder
    private func flowIndicator(_ flow: FlowLevel) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < flowDots(flow) ? Theme.phaseMenstrual : Theme.phaseMenstrual.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
            Text(flow.displayName)
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func flowDots(_ flow: FlowLevel) -> Int {
        switch flow {
        case .none:        return 0
        case .light:       return 1
        case .medium:      return 2
        case .heavy:       return 3
        case .unspecified: return 1
        }
    }

    // MARK: - Symptom Chip

    private func symptomChip(_ entry: SymptomEntry) -> some View {
        HStack(spacing: 4) {
            Image(systemName: entry.type.iconName)
                .font(.system(size: 10))
                .foregroundStyle(severityColor(entry.severity))
            Text(entry.type.displayName)
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textPrimary)
            severityDots(entry.severity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(severityColor(entry.severity).opacity(0.1))
        .clipShape(Capsule())
    }

    private func severityDots(_ severity: SymptomSeverity) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < severity.level ? severityColor(severity) : severityColor(severity).opacity(0.25))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private func severityColor(_ severity: SymptomSeverity) -> Color {
        switch severity {
        case .notPresent: return Theme.textSecondary
        case .mild:       return Theme.phaseFollicular
        case .moderate:   return Theme.phaseOvulation
        case .severe:     return Theme.phaseMenstrual
        }
    }
}

// MARK: - Flow Layout (simple wrapping layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = max(totalHeight, y + rowHeight)
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}

#Preview {
    PeriodDetailView(
        symptoms: MockData.sampleSymptoms,
        phase: .menstrual,
        dayInPhase: 2
    )
    .padding()
}
