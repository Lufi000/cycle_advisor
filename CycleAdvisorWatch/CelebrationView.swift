import SwiftUI
import WatchKit

/// 全屏庆祝页（spec §2.3）：插图 + 成功震动 + 鼓励文案
struct CelebrationView: View {
    let posterAssetName: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.warmShell.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(posterAssetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 8)
                Text("watch.celebration.message")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "watch.celebration.done")) { onDismiss() }
                    .font(.system(size: 13))
            }
        }
        .onAppear {
            WKInterfaceDevice.current().play(.success)
        }
    }
}
