import XCTest
@testable import CycleAdvisor

final class CyclePhaseEngineTests: XCTestCase {

    let engine = CyclePhaseEngine()

    // MARK: - Phase Duration Tests

    func testStandard28DayCycleDurations() {
        let durations = engine.phaseDurations(for: 28)
        XCTAssertEqual(durations.total, 28)
        XCTAssertEqual(durations.menstrual, 5)
        XCTAssertEqual(durations.ovulation, 3)
        XCTAssertGreaterThanOrEqual(durations.luteal, 10)
        XCTAssertLessThanOrEqual(durations.luteal, 16)
    }

    func testShortCycleDurations() {
        let durations = engine.phaseDurations(for: 21)
        XCTAssertEqual(durations.total, 21)
        XCTAssertGreaterThanOrEqual(durations.menstrual, 3)
        XCTAssertGreaterThanOrEqual(durations.follicular, 2)
        XCTAssertGreaterThanOrEqual(durations.ovulation, 2)
    }

    func testLongCycleDurations() {
        let durations = engine.phaseDurations(for: 35)
        XCTAssertEqual(durations.total, 35)
        XCTAssertGreaterThanOrEqual(durations.menstrual, 3)
        XCTAssertGreaterThanOrEqual(durations.follicular, 2)
    }

    // MARK: - Phase Determination Tests

    func testDay1IsMenstrual() {
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: Date.now
        )
        XCTAssertEqual(context.phase, .menstrual)
        XCTAssertEqual(context.cycleDay, 1)
        XCTAssertEqual(context.dayInPhase, 1)
    }

    func testDay3IsMenstrual() {
        let date = Calendar.current.date(byAdding: .day, value: 2, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertEqual(context.phase, .menstrual)
        XCTAssertEqual(context.cycleDay, 3)
    }

    func testDay8IsFollicular() {
        let date = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertEqual(context.phase, .follicular)
        XCTAssertEqual(context.cycleDay, 8)
    }

    func testDay14IsOvulation() {
        let date = Calendar.current.date(byAdding: .day, value: 13, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertTrue(context.phase == .ovulation || context.phase == .follicular)
        XCTAssertEqual(context.cycleDay, 14)
    }

    func testDay22IsLuteal() {
        let date = Calendar.current.date(byAdding: .day, value: 21, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertEqual(context.phase, .luteal)
        XCTAssertEqual(context.cycleDay, 22)
    }

    func testOverdueCycleStaysInLuteal() {
        let date = Calendar.current.date(byAdding: .day, value: 29, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertEqual(context.phase, .luteal, "超过周期后应停在黄体期，不自动进入经期")
        XCTAssertEqual(context.cycleDay, 28)
        XCTAssertTrue(context.isPredicted, "超过一个周期后应标记为待录入")
    }

    func testWithinFirstCycleIsNotPredicted() {
        let date = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let context = engine.determinePhase(
            lastPeriodStart: Date.now,
            cycleLength: 28,
            on: date
        )
        XCTAssertFalse(context.isPredicted, "第一个周期内不应标记为推算")
    }

    // MARK: - Cycle Progress

    func testCycleProgress() {
        let context = CycleContext(
            phase: .luteal,
            dayInPhase: 5,
            cycleDay: 22,
            avgCycleLength: 28,
            healthMetrics: .empty
        )
        let progress = context.cycleProgress
        XCTAssertEqual(progress, 22.0 / 28.0, accuracy: 0.001)
    }

    // MARK: - Next Period

    func testNextPeriodDate() {
        let start = Date.now
        let next = engine.nextPeriodDate(lastPeriodStart: start, cycleLength: 28)
        let days = Calendar.current.dateComponents([.day], from: start, to: next).day!
        XCTAssertEqual(days, 28)
    }

    func testDaysUntilNextPeriod() {
        let start = Date.now
        let days = engine.daysUntilNextPeriod(lastPeriodStart: start, cycleLength: 28, from: start)
        XCTAssertEqual(days, 28)
    }

    func testDaysUntilNextPeriodMidCycle() {
        let start = Date.now
        let midCycle = Calendar.current.date(byAdding: .day, value: 14, to: start)!
        let days = engine.daysUntilNextPeriod(lastPeriodStart: start, cycleLength: 28, from: midCycle)
        XCTAssertEqual(days, 14)
    }

    // MARK: - Phase Durations Helper

    func testPhaseDurationsStartDay() {
        let durations = PhaseDurations(menstrual: 5, follicular: 7, ovulation: 3, luteal: 13)
        XCTAssertEqual(durations.startDay(for: .menstrual), 1)
        XCTAssertEqual(durations.startDay(for: .follicular), 6)
        XCTAssertEqual(durations.startDay(for: .ovulation), 13)
        XCTAssertEqual(durations.startDay(for: .luteal), 16)
    }
}
