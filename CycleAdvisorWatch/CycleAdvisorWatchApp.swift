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
                    showCelebration = true
                }
        }
    }
}
