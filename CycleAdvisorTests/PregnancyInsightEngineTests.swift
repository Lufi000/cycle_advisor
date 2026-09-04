import XCTest
@testable import CycleAdvisor

/// 怀孕提示判定引擎：信号分层、档位规则、降级路径、反馈闭环
final class PregnancyInsightEngineTests: XCTestCase {

    private let engine = PregnancyInsightEngine()
    private let calendar = Calendar.current

    private var referenceDay: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 4))!)
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: referenceDay)!
    }

    /// 体温序列：fromOffset...0，shiftAtOffset 起高温（排卵日 = shiftAtOffset - 1）
    private func makeTemps(fromOffset: Int = -30, shiftAtOffset: Int,
                           disturbedDays: Set<Int> = []) -> [BasalTemperatureEntry] {
        (fromOffset...0).map { offset in
            BasalTemperatureEntry(
                date: day(offset),
                celsius: offset >= shiftAtOffset ? 36.75 : 36.3,
                disturbances: disturbedDays.contains(offset) ? [.illness] : [],
                source: .manual
            )
        }
    }

    /// 生命体征序列：基线窗口（周期前 7 天）与最近 5 天可分别控制
    private func makeVitals(cycleStartOffset: Int, baselineRHR: Double, recentRHR: Double,
                            baselineHRV: Double, recentHRV: Double) -> [DailyVitals] {
        var vitals: [DailyVitals] = []
        for offset in cycleStartOffset...(cycleStartOffset + 6) {
            vitals.append(DailyVitals(date: day(offset), restingHeartRate: baselineRHR, hrvSDNN: baselineHRV))
        }
        for offset in -4...0 {
            vitals.append(DailyVitals(date: day(offset), restingHeartRate: recentRHR, hrvSDNN: recentHRV))
        }
        return vitals
    }

    private func makeInput(temperatures: [BasalTemperatureEntry] = [],
                           vitals: [DailyVitals] = [],
                           symptoms: [SymptomRecord] = [],
                           lastPeriodStart: Date? = nil,
                           expectedPeriodStart: Date? = nil,
                           testFeedback: PregnancyTestFeedback? = nil,
                           dismissedUntil: Date? = nil) -> PregnancyInsightEngine.Input {
        PregnancyInsightEngine.Input(
            temperatures: temperatures,
            vitals: vitals,
            symptoms: symptoms,
            lastPeriodStart: lastPeriodStart,
            expectedPeriodStart: expectedPeriodStart,
            referenceDate: referenceDay,
            testFeedback: testFeedback,
            dismissedUntil: dismissedUntil
        )
    }

    /// 怀孕周期：高温相 ≥ 16 天 → likely
    func testHighTemp18DaysYieldsLikely() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17), // 高温 18 天
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17)
        ))
        guard case .likely(let reasons) = insight else {
            return XCTFail("期望 likely，得到 \(insight)")
        }
        XCTAssertTrue(reasons.contains(.sustainedHighTemperature(days: 18)))
    }

    /// 正常未孕周期：高温 12 天后回落 → 不出提示
    func testNormalCycleWithDropYieldsNoPrompt() {
        var temps = makeTemps(shiftAtOffset: -12) // 高温 13 天
        temps.removeAll { calendar.isDate($0.date, inSameDayAs: day(0)) }
        temps.append(BasalTemperatureEntry(date: day(0), celsius: 36.3,
                                           disturbances: [], source: .manual))
        let insight = engine.evaluate(makeInput(
            temperatures: temps,
            lastPeriodStart: day(-40),
            expectedPeriodStart: day(-12)
        ))
        XCTAssertEqual(insight, .insufficient)
    }

    /// 黄体期短（高温 < 12 天）→ tracking，不出提示
    func testShortLutealPhaseYieldsTracking() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -8), // 高温 9 天
            lastPeriodStart: day(-30),
            expectedPeriodStart: day(-2)
        ))
        XCTAssertEqual(insight, .tracking(lutealDay: 9))
    }

    /// 高温 ≥ 12 天且月经未至 → possible
    func testHighTemp12DaysYieldsPossible() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -11), // 高温 12 天
            lastPeriodStart: day(-39),
            expectedPeriodStart: day(-11)
        ))
        guard case .possible = insight else {
            return XCTFail("期望 possible，得到 \(insight)")
        }
    }

    /// 佐证升档：高温 14 天 + RHR 高 + 早孕症状 ≥ 2 → likely
    func testCorroboratingSignalsUpgradeToLikely() {
        let symptoms = [
            SymptomRecord(date: day(-5), type: .nausea, source: .manual),
            SymptomRecord(date: day(-3), type: .fatigue, source: .chatExtracted),
        ]
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -13), // 高温 14 天
            vitals: makeVitals(cycleStartOffset: -41, baselineRHR: 60, recentRHR: 63,
                               baselineHRV: 50, recentHRV: 50),
            symptoms: symptoms,
            lastPeriodStart: day(-41),
            expectedPeriodStart: day(-13)
        ))
        guard case .likely(let reasons) = insight else {
            return XCTFail("期望 likely，得到 \(insight)")
        }
        XCTAssertTrue(reasons.contains(.elevatedRestingHeartRate(deltaBPM: 3)))
        XCTAssertTrue(reasons.contains(.earlySymptoms(count: 2)))
    }

    /// HRV 抑制佐证：近 5 天 ≤ 基线 × 0.9
    func testHRVSuppressionSignal() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -13),
            vitals: makeVitals(cycleStartOffset: -41, baselineRHR: 60, recentRHR: 60,
                               baselineHRV: 50, recentHRV: 44),
            lastPeriodStart: day(-41),
            expectedPeriodStart: day(-13)
        ))
        // 高温 14 天 + 1 项佐证 → possible（不到 2 项佐证，不升 likely）
        guard case .possible(let reasons) = insight else {
            return XCTFail("期望 possible，得到 \(insight)")
        }
        XCTAssertTrue(reasons.contains(.suppressedHRV(percent: 12)))
    }

    /// RHR 未达 +2 bpm 阈值 → 不构成佐证
    func testRHRBelowThresholdNoSignal() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -13),
            vitals: makeVitals(cycleStartOffset: -41, baselineRHR: 60, recentRHR: 61.5,
                               baselineHRV: 50, recentHRV: 50),
            lastPeriodStart: day(-41),
            expectedPeriodStart: day(-13)
        ))
        guard case .possible(let reasons) = insight else {
            return XCTFail("期望 possible，得到 \(insight)")
        }
        XCTAssertFalse(reasons.contains { if case .elevatedRestingHeartRate = $0 { return true }; return false })
    }

    /// 干扰标记数据参与定位 → likely 降一级为 possible
    func testDisturbedEntriesDowngradeLikelyToPossible() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17, disturbedDays: [-25]),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17)
        ))
        guard case .possible = insight else {
            return XCTFail("期望 possible（降一级），得到 \(insight)")
        }
    }

    /// 降级路径：完全无温度数据，推迟 ≥ 3 天 + 佐证 ≥ 2 → possible（永不 likely）
    func testDegradedPathWithoutTemperature() {
        let symptoms = [
            SymptomRecord(date: day(-4), type: .nausea, source: .manual),
            SymptomRecord(date: day(-2), type: .breastTenderness, source: .manual),
        ]
        let insight = engine.evaluate(makeInput(
            vitals: makeVitals(cycleStartOffset: -31, baselineRHR: 60, recentRHR: 63,
                               baselineHRV: 50, recentHRV: 50),
            symptoms: symptoms,
            lastPeriodStart: day(-31),
            expectedPeriodStart: day(-3)
        ))
        guard case .possible(let reasons) = insight else {
            return XCTFail("期望 possible，得到 \(insight)")
        }
        XCTAssertTrue(reasons.contains(.periodLate(days: 3)))
    }

    /// 降级路径佐证不足 → insufficient
    func testDegradedPathInsufficientSignals() {
        let insight = engine.evaluate(makeInput(
            lastPeriodStart: day(-31),
            expectedPeriodStart: day(-3)
        ))
        XCTAssertEqual(insight, .insufficient)
    }

    /// 阴性反馈：本周期内不再提示（降级为 tracking / insufficient）
    func testNegativeFeedbackSuppressesPrompt() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17),
            testFeedback: .negative(date: day(-2), cycleStart: day(-45))
        ))
        XCTAssertEqual(insight, .tracking(lutealDay: 18))
    }

    /// 阴性反馈后检测到新经期 → 恢复提示
    func testNegativeFeedbackResetAfterNewPeriod() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17),
            testFeedback: .negative(date: day(-40), cycleStart: day(-70)) // 上一周期的反馈
        ))
        guard case .likely = insight else {
            return XCTFail("新周期应恢复提示，得到 \(insight)")
        }
    }

    /// 忽略：7 天内不重复提示
    func testDismissedSuppressesPromptFor7Days() {
        let active = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17),
            dismissedUntil: day(3)
        ))
        XCTAssertEqual(active, .tracking(lutealDay: 18))

        let expired = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17),
            dismissedUntil: day(-1)
        ))
        guard case .likely = expired else {
            return XCTFail("忽略期过后应恢复 likely，得到 \(expired)")
        }
    }

    /// 阳性反馈：停止一切提示
    func testPositiveFeedbackStopsAllPrompts() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(shiftAtOffset: -17),
            lastPeriodStart: day(-45),
            expectedPeriodStart: day(-17),
            testFeedback: .positive(date: day(-1))
        ))
        XCTAssertEqual(insight, .insufficient)
    }

    /// 排卵发生在本次经期之前（上一周期）→ 不用来判定
    func testStaleOvulationFromPreviousCycleIgnored() {
        let insight = engine.evaluate(makeInput(
            temperatures: makeTemps(fromOffset: -50, shiftAtOffset: -35), // 排卵在 -36，高温早已回落区间外
            lastPeriodStart: day(-20),
            expectedPeriodStart: day(8)
        ))
        XCTAssertEqual(insight, .insufficient)
    }
}
