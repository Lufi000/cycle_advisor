import XCTest
@testable import CycleAdvisor

/// 晨间测温提醒：仅对无手表数据覆盖、且手动开启提醒的备孕用户调度
final class ConceptionReminderSchedulerTests: XCTestCase {

    /// 备孕 + 无腕温覆盖 + 提醒开启 → 调度
    func testSchedulesForManualOnlyUser() {
        XCTAssertTrue(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: true, hasWristCoverage: false, reminderEnabled: true
        ))
    }

    /// 有手表腕温覆盖 → 不需要手动测温提醒
    func testSkipsWhenWristDataCovers() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: true, hasWristCoverage: true, reminderEnabled: true
        ))
    }

    /// 未开启备孕模式 → 不调度
    func testSkipsWhenModeOff() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: false, hasWristCoverage: false, reminderEnabled: true
        ))
    }

    /// 未开启测温提醒（默认关）→ 不调度
    func testSkipsWhenReminderDisabled() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: true, hasWristCoverage: false, reminderEnabled: false
        ))
    }

    // MARK: - 验孕提示通知去重

    private let cycleStart = Date(timeIntervalSince1970: 1_700_000_000)
    private var possibleKey: String {
        ConceptionReminderScheduler.promptNotificationKey(tier: "possible", cycleStart: cycleStart)
    }

    /// possible/likely → 通知；tracking/insufficient → 不通知
    func testNotifiesOnlyForPromptTiers() {
        XCTAssertTrue(ConceptionReminderScheduler.shouldNotify(
            insight: .possible(reasons: [.periodLate(days: 2)]), lastNotified: nil, cycleStart: cycleStart
        ))
        XCTAssertTrue(ConceptionReminderScheduler.shouldNotify(
            insight: .likely(reasons: [.sustainedHighTemperature(days: 16)]), lastNotified: nil, cycleStart: cycleStart
        ))
        XCTAssertFalse(ConceptionReminderScheduler.shouldNotify(
            insight: .tracking(lutealDay: 10), lastNotified: nil, cycleStart: cycleStart
        ))
        XCTAssertFalse(ConceptionReminderScheduler.shouldNotify(
            insight: .insufficient, lastNotified: nil, cycleStart: cycleStart
        ))
    }

    /// 同 tier 同周期 → 不重复通知
    func testSkipsDuplicateTierSameCycle() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldNotify(
            insight: .possible(reasons: [.periodLate(days: 2)]),
            lastNotified: possibleKey,
            cycleStart: cycleStart
        ))
    }

    /// possible → likely 升级 → 再通知一次
    func testNotifiesOnTierEscalation() {
        XCTAssertTrue(ConceptionReminderScheduler.shouldNotify(
            insight: .likely(reasons: [.sustainedHighTemperature(days: 16)]),
            lastNotified: possibleKey,
            cycleStart: cycleStart
        ))
    }

    /// 新周期（cycleStart 变化）→ 重新允许通知
    func testNotifiesAgainForNewCycle() {
        let newCycle = Date(timeIntervalSince1970: 1_700_500_000)
        XCTAssertTrue(ConceptionReminderScheduler.shouldNotify(
            insight: .possible(reasons: [.periodLate(days: 2)]),
            lastNotified: possibleKey,
            cycleStart: newCycle
        ))
    }

    /// 无经期数据（cycleStart 为 nil）也能去重
    func testDedupesWithoutCycleStart() {
        let key = ConceptionReminderScheduler.promptNotificationKey(tier: "likely", cycleStart: nil)
        XCTAssertFalse(ConceptionReminderScheduler.shouldNotify(
            insight: .likely(reasons: [.sustainedHighTemperature(days: 16)]),
            lastNotified: key,
            cycleStart: nil
        ))
    }
}
