import Foundation

/// 庆祝的本地状态：待展示的一条 + 已庆祝 UUID 去重集合（只留最近 50 个）
final class CelebrationStore {
    private let defaults = UserDefaults.standard
    private let pendingKey = "watch.pendingCelebration"
    private let celebratedKey = "watch.celebratedUUIDs"

    var pending: PendingCelebration? {
        get {
            guard let data = defaults.data(forKey: pendingKey) else { return nil }
            return try? JSONDecoder().decode(PendingCelebration.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: pendingKey)
            } else {
                defaults.removeObject(forKey: pendingKey)
            }
        }
    }

    var celebratedUUIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: celebratedKey) ?? []).compactMap(UUID.init))
    }

    func markCelebrated(_ uuid: UUID) {
        var list = defaults.stringArray(forKey: celebratedKey) ?? []
        list.append(uuid.uuidString)
        if list.count > 50 { list = Array(list.suffix(50)) }
        defaults.set(list, forKey: celebratedKey)
    }
}

import HealthKit
import UserNotifications
import UIKit

/// 监听手表本地 HealthKit 的新 workout 记录（用户用 Apple 体能训练或任何写
/// HealthKit 的 app 结束运动后触发），规划 1 分钟后的插图庆祝（spec §2.3）。
final class WatchWorkoutObserver: NSObject {
    private let store = HKHealthStore()
    private let celebrationStore = CelebrationStore()
    private var anchor: HKQueryAnchor? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "watch.workoutAnchor") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: "watch.workoutAnchor")
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "watch.workoutAnchor")
        }
    }

    func start() {
        let type = HKWorkoutType.workoutType()
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
            self?.fetchNewWorkouts()
            completionHandler()
        }
        store.execute(query)
        // 冷启动也补一次（错过后台回调时兜底）
        fetchNewWorkouts()
    }

    private func fetchNewWorkouts() {
        let type = HKWorkoutType.workoutType()
        // 首次运行 anchor 为 nil 时查询会返回全部历史记录——只保存 anchor，
        // 历史运动不补庆祝（spec §2.3 边界）
        let isFirstRun = anchor == nil
        let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor,
                                          limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            self.anchor = newAnchor
            guard !isFirstRun else { return }
            for workout in (samples as? [HKWorkout]) ?? [] {
                self.planCelebration(for: workout)
            }
        }
        store.execute(query)
    }

    private func planCelebration(for workout: HKWorkout) {
        let key = HealthKitManager.workoutKey(for: workout.workoutActivityType)
        guard let pending = WorkoutCelebrationPlanner.plan(
            workoutUUID: workout.uuid,
            activityKey: key,
            activityName: key,            // 名称只用于关键词兜底，key 已覆盖绝大多数场景
            workoutEnd: workout.endDate,
            now: Date(),
            celebratedUUIDs: celebrationStore.celebratedUUIDs
        ) else { return }

        // 合并规则：新庆祝顶掉旧的 pending（1 分钟窗口内只留最后一次）
        celebrationStore.pending = pending
        scheduleNotification(for: pending)
    }

    private func scheduleNotification(for pending: PendingCelebration) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("workout.celebration.") }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let content = UNMutableNotificationContent()
            content.title = String(localized: "watch.celebration.title")
            content.body = String(localized: "watch.celebration.body")
            content.sound = .default
            if let url = Self.attachmentURL(assetName: pending.posterAssetName),
               let attachment = try? UNNotificationAttachment(identifier: "poster", url: url) {
                content.attachments = [attachment]
            }
            let interval = max(1, pending.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: pending.notificationID, content: content, trigger: trigger))
        }
    }

    /// UNNotificationAttachment 需要文件 URL：把 bundle 里的插图导出到临时目录
    static func attachmentURL(assetName: String) -> URL? {
        guard let image = UIImage(named: assetName),
              let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(assetName).jpg")
        try? data.write(to: url)
        return url
    }
}
