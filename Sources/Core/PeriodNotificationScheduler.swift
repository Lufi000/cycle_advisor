import Foundation
import UserNotifications

/// 经期预测本地通知（spec §2.5）：预测日前 2 天 9:00「可以提前准备了」+ 当天 9:00。
/// 每次主页 HealthKit 刷新后调用 reschedule：预测日期是确定值，内容不会过期；
/// 经期实际来临后新的 periodStart 会让预测日移到下一周期，旧通知自然被重排掉。
enum PeriodNotificationScheduler {
    static let reminderID = "period.prediction.reminder"
    static let dayOfID = "period.prediction.dayof"

    static func scheduleDates(predictedDate: Date, now: Date = .now,
                              calendar: Calendar = .current) -> [(id: String, date: Date)] {
        func atNine(_ day: Date) -> Date? {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
        var result: [(id: String, date: Date)] = []
        if let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: predictedDate),
           let fire = atNine(twoDaysBefore), fire > now {
            result.append((reminderID, fire))
        }
        if let fire = atNine(predictedDate), fire > now {
            result.append((dayOfID, fire))
        }
        return result
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func reschedule(predictedDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID, dayOfID])
        guard let predictedDate else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return } // 拒绝则静默关闭

        for (id, date) in scheduleDates(predictedDate: predictedDate) {
            let content = UNMutableNotificationContent()
            if id == reminderID {
                content.title = String(localized: "notify.period.reminder.title")
                content.body = String(format: String(localized: "notify.period.reminder.body %@"),
                                      PeriodPrediction.dateText(predictedDate))
            } else {
                content.title = String(localized: "notify.period.dayof.title")
                content.body = String(localized: "notify.period.dayof.body")
            }
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
