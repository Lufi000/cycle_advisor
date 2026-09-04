import XCTest
@testable import CycleAdvisor

/// 经期预测状态机：还有 X 天 / 今天 / 经期第 X 天 / 推迟 X 天
final class PeriodPredictionTests: XCTestCase {
    private var calendar = Calendar.current
    private func day(_ offset: Int, from base: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: base))!
    }

    func testUpcoming() {
        let today = Date()
        let p = PeriodPrediction.make(lastPeriodStart: day(-20, from: today), cycleLength: 28,
                                      isInPeriod: false, periodDay: 21, today: today)
        XCTAssertEqual(p.state, .upcoming(days: 8))
        XCTAssertEqual(p.predictedDate, day(8, from: today))
    }

    func testToday() {
        let today = Date()
        let p = PeriodPrediction.make(lastPeriodStart: day(-28, from: today), cycleLength: 28,
                                      isInPeriod: false, periodDay: 29, today: today)
        XCTAssertEqual(p.state, .today)
    }

    func testInPeriod() {
        let today = Date()
        let p = PeriodPrediction.make(lastPeriodStart: day(-1, from: today), cycleLength: 28,
                                      isInPeriod: true, periodDay: 2, today: today)
        XCTAssertEqual(p.state, .inPeriod(day: 2))
    }

    func testOverdue() {
        let today = Date()
        let p = PeriodPrediction.make(lastPeriodStart: day(-31, from: today), cycleLength: 28,
                                      isInPeriod: false, periodDay: 32, today: today)
        XCTAssertEqual(p.state, .overdue(days: 3))
    }

    func testCrossMonth() {
        // 1月30日 + 周期28天 → 预测落在2月27日，跨年/月不偏移
        var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 30
        let last = calendar.date(from: comps)!
        comps.day = 31
        let today = calendar.date(from: comps)!
        let p = PeriodPrediction.make(lastPeriodStart: last, cycleLength: 28,
                                      isInPeriod: false, periodDay: 2, today: today)
        XCTAssertEqual(p.state, .upcoming(days: 27))
        let predictedComps = calendar.dateComponents([.month, .day], from: p.predictedDate)
        XCTAssertEqual(predictedComps.month, 2)
        XCTAssertEqual(predictedComps.day, 27)
    }
}
