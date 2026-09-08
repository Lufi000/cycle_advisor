import SwiftUI

/// 近 14 天体温迷你趋势图（纯线条，无坐标轴）
struct TemperatureSparkline: View {
    let entries: [BasalTemperatureEntry]

    var body: some View {
        GeometryReader { geo in
            let values = entries.map(\.celsius)
            let minValue = (values.min() ?? 36.0) - 0.05
            let maxValue = (values.max() ?? 37.0) + 0.05
            let range = max(maxValue - minValue, 0.01)

            Path { path in
                for (index, entry) in entries.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(entries.count - 1, 1))
                    let ratio = (entry.celsius - minValue) / range
                    let y = geo.size.height * (1 - CGFloat(ratio))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
