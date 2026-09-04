import XCTest
@testable import CycleAdvisor

/// 排卵定位：3-over-6 规则（连续 3 天 ≥ 前 6 个有效日均值 + 0.2°C）
final class OvulationLocatorTests: XCTestCase {

    private let locator = OvulationLocator()
    private let calendar = Calendar.current

    private var referenceDay: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    /// 构造体温序列：从 fromOffset 到 0（参考日），shiftAtOffset 起升温到高温
    private func makeSeries(fromOffset: Int, shiftAtOffset: Int,
                            low: Double = 36.3, high: Double = 36.75,
                            disturbedDays: Set<Int> = [],
                            missingDays: Set<Int> = []) -> [BasalTemperatureEntry] {
        var entries: [BasalTemperatureEntry] = []
        for offset in fromOffset...0 {
            if missingDays.contains(offset) { continue }
            let disturbances: Set<Disturbance> = disturbedDays.contains(offset) ? [.alcohol] : []
            entries.append(BasalTemperatureEntry(
                date: day(offset),
                celsius: offset >= shiftAtOffset ? high : low,
                disturbances: disturbances,
                source: .manual
            ))
        }
        return entries
    }

    /// 正常双相：排卵日 = 升温前最后一低温日，高温相天数持续累计
    func testLocatesOvulationOnBiphasicSeries() {
        // 升温起点 -15（高温 16 天），排卵日应为 -16
        let result = locator.locate(temperatures: makeSeries(fromOffset: -25, shiftAtOffset: -15),
                                    referenceDate: referenceDay)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ovulationDay, day(-16))
        XCTAssertEqual(result?.highTemperatureDays, 16)
        XCTAssertEqual(result?.isStillElevated, true)
        XCTAssertEqual(result?.usedDisturbedEntries, false)
    }

    /// 有效日不足 10 天 → 无法定位
    func testInsufficientValidDaysReturnsNil() {
        let result = locator.locate(temperatures: makeSeries(fromOffset: -8, shiftAtOffset: -3),
                                    referenceDate: referenceDay)
        XCTAssertNil(result)
    }

    /// 无升温（单相）→ 无法定位
    func testMonophasicSeriesReturnsNil() {
        var entries: [BasalTemperatureEntry] = []
        for offset in -20...0 {
            entries.append(BasalTemperatureEntry(date: day(offset), celsius: 36.3,
                                                 disturbances: [], source: .manual))
        }
        XCTAssertNil(locator.locate(temperatures: entries, referenceDate: referenceDay))
    }

    /// 9 天窗口内缺测 > 2 天 → 该窗口跳过，不误判升温
    func testWindowWithMoreThanTwoGapsIsSkipped() {
        // 全部低温 31 天，但在 [-5, -3, -2] 放三条偏高读数（36.6）。
        // 候选窗口内缺测 -8、-6、-4 共 3 天 > 2 → 假升温窗口被跳过 → 单相 → nil
        var entries = makeSeries(fromOffset: -30, shiftAtOffset: 1, missingDays: [-8, -6, -4])
        for offset in [-5, -3, -2] {
            entries.removeAll { calendar.isDate($0.date, inSameDayAs: day(offset)) }
            entries.append(BasalTemperatureEntry(date: day(offset), celsius: 36.6,
                                                 disturbances: [], source: .manual))
        }
        XCTAssertNil(locator.locate(temperatures: entries, referenceDate: referenceDay))
    }

    /// 缺测日不中断高温相计数
    func testMissingDaysDoNotBreakHighPhase() {
        let result = locator.locate(
            temperatures: makeSeries(fromOffset: -25, shiftAtOffset: -10, missingDays: [-7, -4]),
            referenceDate: referenceDay
        )
        XCTAssertEqual(result?.highTemperatureDays, 11)
        XCTAssertEqual(result?.isStillElevated, true)
    }

    /// 高温回落（月经将至）→ isStillElevated = false，天数停在回落前
    func testTemperatureDropEndsHighPhase() {
        var entries = makeSeries(fromOffset: -25, shiftAtOffset: -13) // 高温 13 天
        // 最后一天回落到低温
        entries.removeAll { calendar.isDate($0.date, inSameDayAs: day(0)) }
        entries.append(BasalTemperatureEntry(date: day(0), celsius: 36.3,
                                             disturbances: [], source: .manual))
        let result = locator.locate(temperatures: entries, referenceDate: referenceDay)
        XCTAssertEqual(result?.isStillElevated, false)
        // 升温当天算高温第 1 天：-13...-1 共 13 天，第 0 天回落停止计数
        XCTAssertEqual(result?.highTemperatureDays, 13)
    }

    /// 有干扰标记的手动条目在无替代时补位，并标记 usedDisturbedEntries
    func testDisturbedEntryUsedAsFallbackWithDowngrade() {
        let result = locator.locate(
            temperatures: makeSeries(fromOffset: -25, shiftAtOffset: -15, disturbedDays: [-20]),
            referenceDate: referenceDay
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.usedDisturbedEntries, true)
        XCTAssertEqual(result?.ovulationDay, day(-16))
    }

    /// 手表来源条目即使有干扰标记也全部有效（不会触发降权标记）
    func testWristEntriesAlwaysValid() {
        var entries = makeSeries(fromOffset: -25, shiftAtOffset: -15)
        entries = entries.map {
            BasalTemperatureEntry(date: $0.date, celsius: $0.celsius,
                                  disturbances: $0.disturbances, source: .wristTemperature)
        }
        let result = locator.locate(temperatures: entries, referenceDate: referenceDay)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.usedDisturbedEntries, false)
    }
}
