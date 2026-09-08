import XCTest
@testable import CycleAdvisor

/// 备孕数据存储：体温校验与覆盖、来源优先级合并、症状去重、反馈状态
final class ConceptionStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConceptionStore!
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConceptionStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func day(_ offset: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: Date())!)
    }

    /// 体温合法范围 35.0–38.0，超出拒绝录入
    func testRejectsOutOfRangeTemperature() {
        XCTAssertFalse(store.upsertManualTemperature(date: day(0), celsius: 34.9, disturbances: []))
        XCTAssertFalse(store.upsertManualTemperature(date: day(0), celsius: 38.1, disturbances: []))
        // 注：两个边界值须落在不同日，否则同日覆盖语义下 count 为 1
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 35.0, disturbances: []))
        XCTAssertTrue(store.upsertManualTemperature(date: day(-1), celsius: 38.0, disturbances: []))
        XCTAssertEqual(store.manualTemperatures.count, 2)
    }

    /// 同日重复录入覆盖旧值
    func testSameDayManualEntryOverwrites() {
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 36.3, disturbances: []))
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 36.6, disturbances: [.alcohol]))
        XCTAssertEqual(store.manualTemperatures.count, 1)
        XCTAssertEqual(store.manualTemperatures[0].celsius, 36.6)
        XCTAssertEqual(store.manualTemperatures[0].disturbances, [.alcohol])
    }

    /// 同日同时存在手表与手动记录时以手表为准
    func testWristTemperatureWinsOverManualSameDay() {
        XCTAssertTrue(store.upsertManualTemperature(date: day(-1), celsius: 36.3, disturbances: []))
        XCTAssertTrue(store.upsertManualTemperature(date: day(-2), celsius: 36.4, disturbances: []))
        let wrist = [BasalTemperatureEntry(date: day(-1), celsius: 37.1, disturbances: [], source: .wristTemperature)]
        let merged = store.mergedTemperatures(wrist: wrist)
        XCTAssertEqual(merged.count, 2)
        let dayMinus1 = merged.first { calendar.isDate($0.date, inSameDayAs: day(-1)) }
        XCTAssertEqual(dayMinus1?.celsius, 37.1)
        XCTAssertEqual(dayMinus1?.source, .wristTemperature)
    }

    /// 腕温记录带时分秒时仍按日归并，同日以手表为准且不产生重复条目
    func testWristTemperatureWithTimeComponentStillWinsSameDay() {
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 36.3, disturbances: []))
        // 手表采样时间带时分秒（如早晨 6 点），归并前须归一化到 startOfDay
        let wristDate = calendar.date(byAdding: .hour, value: 6, to: day(0))!
        let wrist = [BasalTemperatureEntry(date: wristDate, celsius: 37.1, disturbances: [], source: .wristTemperature)]
        let merged = store.mergedTemperatures(wrist: wrist)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].celsius, 37.1)
        XCTAssertEqual(merged[0].source, .wristTemperature)
        XCTAssertTrue(calendar.isDate(merged[0].date, inSameDayAs: day(0)))
    }

    /// 症状按 (日, 类型) 去重，冲突时保留高优先级来源 manual > healthKit > chatExtracted
    func testSymptomDedupPriority() {
        store.addSymptoms([SymptomRecord(date: day(0), type: .nausea, source: .chatExtracted)])
        store.addSymptoms([SymptomRecord(date: day(0), type: .nausea, source: .healthKit)])
        XCTAssertEqual(store.symptomRecords.count, 1)
        XCTAssertEqual(store.symptomRecords[0].source, .healthKit)

        // 低优先级不覆盖高优先级
        store.addSymptoms([SymptomRecord(date: day(0), type: .nausea, source: .chatExtracted)])
        XCTAssertEqual(store.symptomRecords[0].source, .healthKit)

        // 高优先级覆盖低优先级
        store.addSymptoms([SymptomRecord(date: day(0), type: .nausea, source: .manual)])
        XCTAssertEqual(store.symptomRecords[0].source, .manual)

        // 不同类型不同日不去重
        store.addSymptoms([SymptomRecord(date: day(-1), type: .nausea, source: .manual)])
        store.addSymptoms([SymptomRecord(date: day(0), type: .fatigue, source: .manual)])
        XCTAssertEqual(store.symptomRecords.count, 3)
    }

    /// JSON 持久化往返
    func testPersistenceRoundTrip() {
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 36.5, disturbances: [.insomnia]))
        store.addSymptoms([SymptomRecord(date: day(0), type: .fatigue, source: .manual)])
        store.recordFeedback(.negative(date: day(0), cycleStart: day(-28)))
        store.dismissPrompt(forDays: 7, from: day(0))

        let reloaded = ConceptionStore(directory: tempDir)
        XCTAssertEqual(reloaded.manualTemperatures.count, 1)
        XCTAssertEqual(reloaded.manualTemperatures[0].celsius, 36.5)
        XCTAssertEqual(reloaded.symptomRecords.count, 1)
        XCTAssertEqual(reloaded.testFeedback, .negative(date: day(0), cycleStart: day(-28)))
        XCTAssertNotNil(reloaded.dismissedUntil)
    }

    /// 阴性反馈在检测到新经期开始后清除
    func testNegativeFeedbackClearsOnNewPeriod() {
        store.recordFeedback(.negative(date: day(-5), cycleStart: day(-33)))
        // 仍是同一周期 → 不清除
        store.clearFeedbackIfNewPeriod(lastPeriodStart: day(-33))
        XCTAssertNotNil(store.testFeedback)
        // 新经期开始 → 清除
        store.clearFeedbackIfNewPeriod(lastPeriodStart: day(-2))
        XCTAssertNil(store.testFeedback)
    }
}
