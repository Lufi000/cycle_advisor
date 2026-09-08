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
}
