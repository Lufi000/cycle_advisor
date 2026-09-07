import SwiftUI
import UserNotifications

@main
struct CycleAdvisorWatchApp: App {
    private let observer = WatchWorkoutObserver()
    private let celebrationStore = CelebrationStore()
    @State private var showCelebration = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .fullScreenCover(isPresented: $showCelebration) {
                    if let pending = celebrationStore.pending {
                        CelebrationView(posterAssetName: pending.posterAssetName) {
                            celebrationStore.markCelebrated(pending.workoutUUID)
                            celebrationStore.pending = nil
                            showCelebration = false
                        }
                    }
                }
                .onAppear { observer.start() }
                .onChange(of: scenePhase) { _, phase in
                    // 前台路径：延迟窗口内用户主动打开 app → 立即展示并取消未发通知
                    guard phase == .active, let pending = celebrationStore.pending else { return }
                    UNUserNotificationCenter.current()
                        .removePendingNotificationRequests(withIdentifiers: [pending.notificationID])
                    celebrationStore.markCelebrated(pending.workoutUUID)
                    // 超过 5 分钟的 pending 早已错过时机（通知兜底已发过），静默清掉不再全屏展示
                    if pending.fireDate < Date().addingTimeInterval(-300) {
                        celebrationStore.pending = nil
                        return
                    }
                    showCelebration = true
                }
        }
    }
}
