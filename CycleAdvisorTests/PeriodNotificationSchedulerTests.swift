import XCTest
@testable import CycleAdvisor

/// 经期预测通知：前 2 天 9:00 + 当天 9:00；已过时间点不调度
final class PeriodNotificationSchedulerTests: XCTestCase {
    private let calendar = Calendar.current

    func testBothNotificationsScheduled() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 10))!
        let predicted = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let dates = PeriodNotificationScheduler.scheduleDates(predictedDate: predicted, now: now)
        XCTAssertEqual(dates.map { $0.id }, [PeriodNotificationScheduler.reminderID, PeriodNotificationScheduler.dayOfID])
        XCTAssertEqual(calendar.component(.day, from: dates[0].date), 8)
        XCTAssertEqual(calendar.component(.hour, from: dates[0].date), 9)
        XCTAssertEqual(calendar.component(.day, from: dates[1].date), 10)
    }

    func testPastReminderSkipped() {
        // 现在是 9 号下午，前 2 天（8 号）的通知已过，只留当天
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 15))!
        let predicted = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let dates = PeriodNotificationScheduler.scheduleDates(predictedDate: predicted, now: now)
        XCTAssertTrue(dates.isEmpty) // 当天 9:00 也过了
    }

    func testReminderSkippedButDayOfKept() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 10))!
        let predicted = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let dates = PeriodNotificationScheduler.scheduleDates(predictedDate: predicted, now: now)
        XCTAssertEqual(dates.map { $0.id }, [PeriodNotificationScheduler.dayOfID])
    }
}
