import SwiftUI

/// Watch 速览（spec §2.1）：周期进度环 + 当前阶段 + 预测经期日期/倒计时。
struct WatchHomeView: View {
    @State private var viewModel = WatchCycleViewModel()

    var body: some View {
        Group {
            if let context = viewModel.context {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(context.phase.color.opacity(0.25), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: min(1, context.cycleProgress))
                            .stroke(context.phase.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text(context.phase.emoji)
                                .font(.system(size: 20))
                            Text("\(context.cycleDay)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    Text(context.phase.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let prediction = viewModel.prediction {
                        Text(prediction.text)
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if viewModel.hasNoData {
                Text("watch.no_data")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.warmShell)
        .containerBackground(Theme.warmShell, for: .navigation)
        .task { await viewModel.load() }
    }
}
