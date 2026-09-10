import Foundation
import UserNotifications

/// 晨间测温提醒：仅对无手表腕温覆盖的备孕用户调度每日本地通知。
/// 文案避免在锁屏暴露敏感信息（"该测体温啦"而非"备孕提醒"）。
enum ConceptionReminderScheduler {

    static let notificationID = "conception.morningReminder"
    /// UserDefaults key：提醒时间（距午夜分钟数），默认 7:00 = 420
    static let timeDefaultsKey = "conception.reminderTimeMinutes"
    /// UserDefaults key：测温提醒开关（默认关，手动开启）
    static let enabledDefaultsKey = "conception.reminderEnabled"

    /// 备孕模式开启、近 3 天无腕温数据覆盖、且用户手动开启了测温提醒时才调度
    static func shouldSchedule(isTryingToConceive: Bool, hasWristCoverage: Bool, reminderEnabled: Bool) -> Bool {
        isTryingToConceive && !hasWristCoverage && reminderEnabled
    }

    /// 重排提醒：先清后排，条件不满足时只清不排
    static func refresh(isTryingToConceive: Bool, hasWristCoverage: Bool, reminderEnabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard shouldSchedule(
            isTryingToConceive: isTryingToConceive,
            hasWristCoverage: hasWristCoverage,
            reminderEnabled: reminderEnabled
        ) else { return }

        let minutes = UserDefaults.standard.object(forKey: timeDefaultsKey) as? Int ?? 420
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.body = String(localized: "conception.reminder.body")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(
            identifier: notificationID, content: content, trigger: trigger
        ))
    }

    // MARK: - 验孕提示通知

    /// 检测到 possible/likely 时发一条本地通知；iOS 默认把本地通知镜像到配对 Apple Watch，
    /// 因此手表端无需任何代码即可抬腕看到提示（与经期预测通知同一条路径）。
    static let promptNotificationID = "conception.pregnancy.prompt"
    /// UserDefaults key：上次已通知的「tier@周期起点时间戳」，用于去重
    static let promptLastNotifiedKey = "conception.prompt.lastNotified"

    static func promptNotificationKey(tier: String, cycleStart: Date?) -> String {
        "\(tier)@\(Int(cycleStart?.timeIntervalSince1970 ?? 0))"
    }

    /// 纯函数：同一 tier 同一周期只通知一次；possible→likely 升级或新周期会再次通知
    static func shouldNotify(insight: PregnancyInsight, lastNotified: String?, cycleStart: Date?) -> Bool {
        let tier: String
        switch insight {
        case .possible: tier = "possible"
        case .likely: tier = "likely"
        default: return false
        }
        return lastNotified != promptNotificationKey(tier: tier, cycleStart: cycleStart)
    }

    /// 在 ConceptionInsightManager.refresh() 算出 insight 后调用
    static func notifyInsightIfNeeded(_ insight: PregnancyInsight, cycleStart: Date?) {
        let defaults = UserDefaults.standard
        guard shouldNotify(
            insight: insight,
            lastNotified: defaults.string(forKey: promptLastNotifiedKey),
            cycleStart: cycleStart
        ) else { return }

        let tier: String
        let title: String
        let reasons: [InsightReason]
        switch insight {
        case .possible(let r):
            tier = "possible"
            title = String(localized: "notify.conception.possible")
            reasons = r
        case .likely(let r):
            tier = "likely"
            title = String(localized: "notify.conception.likely")
            reasons = r
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        let body = reasons.prefix(3).map(reasonText).joined(separator: ", ")
        if !body.isEmpty { content.body = body }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [promptNotificationID])
        center.add(UNNotificationRequest(
            identifier: promptNotificationID, content: content, trigger: trigger
        ))

        defaults.set(promptNotificationKey(tier: tier, cycleStart: cycleStart), forKey: promptLastNotifiedKey)
    }

    /// 与首页卡片的原因文案保持一致（复用 conception.reason.* 翻译）
    private static func reasonText(_ reason: InsightReason) -> String {
        switch reason {
        case .sustainedHighTemperature(let days):
            return String(format: String(localized: "conception.reason.high_temp"), Int64(days))
        case .periodLate(let days):
            return String(format: String(localized: "conception.reason.period_late"), Int64(days))
        case .elevatedRestingHeartRate(let delta):
            return String(format: String(localized: "conception.reason.rhr"), Int64(delta))
        case .suppressedHRV(let percent):
            return String(format: String(localized: "conception.reason.hrv"), Int64(percent))
        case .earlySymptoms(let count):
            return String(format: String(localized: "conception.reason.symptoms"), Int64(count))
        }
    }
}

/// 前台也展示通知横幅：验孕提示在 App 内 refresh 时触发（1 秒即发），
/// 没有 foreground 展示的话用户必须恰好锁屏才能看到。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
