import SwiftUI

struct CycleRingView: View {
    let context: CycleContext
    /// 非 nil 时进入「全彩浏览」模式：所有阶段显示相位色，highlightedPhase 满饱和，其余降透明度
    var highlightedPhase: CyclePhase? = nil
    /// 预测经期窗口半径（天）：在环顶（下次经期预测点）前后各这么多天画虚线弧
    var predictedWindowDays: Int = 3

    private let lineWidth: CGFloat = 20
    private let dotSize: CGFloat = 24
    private let engine = CyclePhaseEngine()

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                ringSegments(size: size)
                centerContent(size: size)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Ring Segments

    private func ringSegments(size: CGFloat) -> some View {
        let durations = engine.phaseDurations(for: context.avgCycleLength)
        let total = Double(durations.total)

        return ZStack {
            ForEach(CyclePhase.allCases, id: \.self) { phase in
                let (start, end) = segmentAngles(for: phase, durations: durations, total: total)
                let isCurrentPhase = phase == context.phase

                let isHighlighted: Bool = {
                    if let hp = highlightedPhase { return phase == hp }
                    return isCurrentPhase
                }()
                let segColor: Color = {
                    if highlightedPhase != nil {
                        return phase.color
                    }
                    return isCurrentPhase
                        ? phase.color
                        : Theme.warmShell
                }()

                Circle()
                    .trim(from: start, to: end)
                    .stroke(
                        segColor,
                        style: StrokeStyle(
                            lineWidth: isHighlighted ? lineWidth + 2 : lineWidth,
                            lineCap: .butt
                        )
                    )
                    .opacity(highlightedPhase != nil && !isHighlighted ? 0.35 : 1.0)
                    .rotationEffect(.degrees(-90))
            }

            // 预测经期窗口：虚线弧跨环顶（下次经期预测点 = day total+1）
            if highlightedPhase == nil, context.phase != .menstrual {
                predictedWindowArc(total: total)
            }

            // 当前位置指示点
            currentPositionDot(size: size, durations: durations, total: total)
        }
    }

    /// 环顶前后各 predictedWindowDays 天的虚线弧，表达「可能来潮窗口」（对齐 Apple Health 的 possible period days）
    private func predictedWindowArc(total: Double) -> some View {
        let n = Double(predictedWindowDays)
        let tailStart = (total - n) / total   // 本周期末尾 n 天
        let headEnd = n / total               // 下周期开头 n 天
        let style = StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round, dash: [2, 5])
        let color = CyclePhase.menstrual.color.opacity(0.55)

        return ZStack {
            Circle().trim(from: tailStart, to: 1).stroke(color, style: style)
            Circle().trim(from: 0, to: headEnd).stroke(color, style: style)
        }
        .rotationEffect(.degrees(-90))
    }

    private func segmentAngles(for phase: CyclePhase, durations: PhaseDurations, total: Double) -> (CGFloat, CGFloat) {
        let startDay = Double(durations.startDay(for: phase) - 1)
        let duration = Double(durations.duration(for: phase))

        let gap = 0.0 // 段间间隙
        let start = startDay / total + gap
        let end = (startDay + duration) / total - gap

        return (CGFloat(start), CGFloat(end))
    }

    private func currentPositionDot(size: CGFloat, durations: PhaseDurations, total: Double) -> some View {
        let progress = Double(context.cycleDay - 1) / total
        let angle = Angle.degrees(progress * 360 - 90)
        // Circle().stroke() 的路径中心在 size/2，指示点对齐到描边中心线
        let radius = size / 2

        return Circle()
            .fill(Theme.cardBackgroundSolid)
            .frame(width: dotSize, height: dotSize)
            .overlay(
                ZStack {
                    Circle().stroke(context.phase.color.opacity(0.25), lineWidth: 5)
                    Circle().stroke(context.phase.color, lineWidth: 2.5)
                }
            )
            .offset(
                x: radius * cos(angle.radians),
                y: radius * sin(angle.radians)
            )
    }

    // MARK: - Center Content

    private func centerContent(size: CGFloat) -> some View {
        let displayPhase = highlightedPhase ?? context.phase
        let durations = engine.phaseDurations(for: context.avgCycleLength)
        let duration = durations.duration(for: displayPhase)
        // 内圈可用直径 = 描边内边缘直径
        let innerDiameter = size - lineWidth * 2 - 8

        return ZStack {
            RadialGradient(
                colors: [
                    Theme.background.opacity(0),
                    Theme.background.opacity(0.6)
                ],
                center: .center,
                startRadius: innerDiameter * 0.1,
                endRadius: innerDiameter * 0.5
            )
            .clipShape(Circle())

            if highlightedPhase != nil {
                // 交互模式：显示选中阶段信息
                VStack(spacing: 3) {
                    Text(displayPhase.emoji)
                        .font(.system(size: innerDiameter * 0.2))
                    Text(displayPhase.displayName)
                        .font(.system(size: innerDiameter * 0.12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(String(format: String(localized: "home.cycle_detail.duration_format"), duration))
                        .font(.system(size: innerDiameter * 0.085))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                // 默认模式：显示 Day X
                VStack(spacing: 2) {
                    if context.isPredicted {
                        Text("phase.predicted_label")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                    Text("home.cycle_ring.day_label")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(context.cycleDay)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(context.isPredicted ? Theme.textSecondary : Theme.textPrimary)
                }
            }
        }
        .frame(width: innerDiameter, height: innerDiameter)
    }
}

#Preview("Luteal") {
    CycleRingView(context: MockData.lutealContext)
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Menstrual") {
    CycleRingView(context: MockData.menstrualContext)
        .frame(width: 120, height: 120)
        .padding()
}
