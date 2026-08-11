import XCTest
@testable import CycleAdvisor

final class SolarTermEngineTests: XCTestCase {

    let engine = SolarTermEngine()

    // MARK: - Helper

    /// 从 UTC 年月日创建 Date
    private func utcDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    /// 断言节气日期的 day 在期望范围内（UTC 日期可能差一天）
    private func assertTermDay(_ info: SolarTermInfo, expectedMonth: Int, expectedDayRange: ClosedRange<Int>,
                               file: StaticString = #filePath, line: UInt = #line) {
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: info.date)
        XCTAssertEqual(components.month, expectedMonth,
                       "\(info.term.key) month mismatch: got \(components.month!)",
                       file: file, line: line)
        XCTAssertTrue(expectedDayRange.contains(components.day!),
                      "\(info.term.key) day \(components.day!) not in \(expectedDayRange)",
                      file: file, line: line)
    }

    // MARK: - Known Date Tests (2025)

    func testChunfen2025() {
        // 2025 春分 = 3月20日 (UTC)
        let terms = engine.termsForYear(2025)
        let chunfen = terms.first { $0.term == .chunfen }!
        assertTermDay(chunfen, expectedMonth: 3, expectedDayRange: 19...21)
    }

    func testXiazhi2025() {
        // 2025 夏至 = 6月21日 (UTC)
        let terms = engine.termsForYear(2025)
        let xiazhi = terms.first { $0.term == .xiazhi }!
        assertTermDay(xiazhi, expectedMonth: 6, expectedDayRange: 20...22)
    }

    func testQiufen2025() {
        // 2025 秋分 = 9月22日 (UTC)
        let terms = engine.termsForYear(2025)
        let qiufen = terms.first { $0.term == .qiufen }!
        assertTermDay(qiufen, expectedMonth: 9, expectedDayRange: 22...23)
    }

    func testDongzhi2025() {
        // 2025 冬至 = 12月21日 (UTC)
        let terms = engine.termsForYear(2025)
        let dongzhi = terms.first { $0.term == .dongzhi }!
        assertTermDay(dongzhi, expectedMonth: 12, expectedDayRange: 21...22)
    }

    func testLichun2026() {
        // 2026 立春 = 2月4日
        let terms = engine.termsForYear(2026)
        let lichun = terms.first { $0.term == .lichun }!
        assertTermDay(lichun, expectedMonth: 2, expectedDayRange: 3...5)
    }

    // MARK: - Full Year Sanity Checks

    func testAllTermsPresent() {
        let terms = engine.termsForYear(2025)
        XCTAssertEqual(terms.count, 24)
        // 每个节气都应出现恰好一次
        let keys = Set(terms.map(\.term))
        XCTAssertEqual(keys.count, 24)
    }

    func testTermsAreChronological() {
        let terms = engine.termsForYear(2025).sorted { $0.date < $1.date }
        for i in 1..<terms.count {
            XCTAssertTrue(terms[i].date > terms[i - 1].date,
                          "\(terms[i].term.key) should be after \(terms[i - 1].term.key)")
        }
    }

    func testAdjacentTermInterval() {
        // 相邻节气间隔应在 14~17 天之间
        let terms = engine.termsForYear(2025).sorted { $0.date < $1.date }
        for i in 1..<terms.count {
            let days = Calendar.current.dateComponents([.day], from: terms[i - 1].date, to: terms[i].date).day!
            XCTAssertTrue((13...18).contains(days),
                          "\(terms[i - 1].term.key) → \(terms[i].term.key): \(days) days")
        }
    }

    // MARK: - currentAndNext Tests

    func testCurrentAndNextMidYear() {
        // 2025年6月1日 — 应在小满之后、芒种之前
        let date = utcDate(year: 2025, month: 6, day: 1)
        let (current, next) = engine.currentAndNext(on: date)
        XCTAssertEqual(current.term, .xiaoman)
        XCTAssertEqual(next.term, .mangzhong)
    }

    func testCurrentAndNextYearEnd() {
        // 2025年12月31日 — 应在冬至之后、小寒之前
        let date = utcDate(year: 2025, month: 12, day: 31)
        let (current, next) = engine.currentAndNext(on: date)
        XCTAssertEqual(current.term, .dongzhi)
        XCTAssertEqual(next.term, .xiaohan)
    }

    func testDaysUntilNext() {
        let date = utcDate(year: 2025, month: 3, day: 15)
        let days = engine.daysUntilNext(from: date)
        // 春分在 3 月 20 日左右，所以应该还有 4-6 天
        XCTAssertTrue((3...7).contains(days), "days until next: \(days)")
    }
}
