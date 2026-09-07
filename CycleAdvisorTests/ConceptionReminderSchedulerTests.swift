import XCTest
@testable import CycleAdvisor

/// 晨间测温提醒：仅对无手表数据覆盖的备孕用户调度
final class ConceptionReminderSchedulerTests: XCTestCase {

    /// 备孕 + 无腕温覆盖 → 调度
    func testSchedulesForManualOnlyUser() {
        XCTAssertTrue(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: true, hasWristCoverage: false
        ))
    }

    /// 有手表腕温覆盖 → 不需要手动测温提醒
    func testSkipsWhenWristDataCovers() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: true, hasWristCoverage: true
        ))
    }

    /// 未开启备孕模式 → 不调度
    func testSkipsWhenModeOff() {
        XCTAssertFalse(ConceptionReminderScheduler.shouldSchedule(
            isTryingToConceive: false, hasWristCoverage: false
        ))
    }
}
