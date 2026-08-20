import SwiftUI

/// 三颗圆点依次缩放跳动的轻量加载提示，用于「思考中 / 生成中」状态。
struct TypingIndicatorView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textSecondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.13),
                        value: phase
                    )
            }
        }
        .onAppear {
            withAnimation { phase = (phase + 1) % 3 }
        }
    }
}

#Preview {
    TypingIndicatorView()
        .padding()
        .background(Theme.background)
}
