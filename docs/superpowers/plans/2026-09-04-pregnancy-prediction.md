# 怀孕预测功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CycleAdvisor 增加备孕模式下的怀孕可能提示功能——手表腕温/RHR/HRV 为主信号，手动 BBT 兜底，本地规则引擎输出"提示验孕"档位。

**Architecture:** 判定逻辑全部在 App 本地（`PregnancyInsightEngine` 纯逻辑可单测）；手表数据以 HealthKit 为唯一数据源现读现算；手动 BBT 与统一症状库各存 Documents 目录 JSON 文件；症状抽取走客户端固定 prompt + 现有代理（见下方偏离说明）；晨间提醒为本地通知。

**Tech Stack:** SwiftUI、HealthKit、UserNotifications、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-04-pregnancy-prediction-design.md`

**对 spec 的一处偏离（与架构现实对齐）：** spec 模块 4 写的是"BFF 新端点 `POST /v1/extract/symptoms`"。实际 BFF（`bff/handler.go`）是多个 App 共用的**纯转发代理**，不含任何业务端点；本项目既有抽取功能（`LLMService.extractProfileFields`）均为客户端固定 prompt + 经同一代理转发。因此本计划的症状抽取实现为**客户端 `LLMService.extractSymptoms`**（同样的 deepseek-chat / `temperature: 0` / `json_object` / `max_tokens: 300` / 鉴权与限流复用现有代理机制），不改动 BFF。spec 模块 8 的"BFF Go 单测"相应取消，改为 `SymptomExtractor` 解析单测。

## Global Constraints

- 所有面向用户的文案必须进 7 个 lproj：zh-Hans、zh-Hant、en、ja、ko、es、fr（`Sources/Resources/*.lproj/Localizable.strings`，格式 `"key" = "value";`）
- App 锁定浅色模式，视觉遵循暖色纸质主题（`Theme.background` / `Theme.cardBackgroundSolid` / `Theme.textPrimary` / `Theme.textSecondary` / `Theme.captionSize` / `.grainCardStyle(seed:)`）
- 本机 xcode-select 指向 CommandLineTools，**所有 xcodebuild 命令必须加前缀** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- 项目路径：`/Users/lufi/Documents/Claude/Projects/cycle_advisor-main`
- 部署目标 iOS 17.0（`appleSleepingWristTemperature` 等类型均可用，无需 availability 判断）
- **文案合规红线：永不出现"你已怀孕"，只出现"可能怀孕 / 建议验孕确认 / 提示验孕"**；提示卡必须带"此功能不构成医疗诊断"免责声明
- 备孕功能的所有 UI/通知/抽取入口，都以 `UserProfileManager.shared.profile.isTryingToConceive == true` 为门
- 测试进现有 `CycleAdvisorTests` target（XCTest，`@testable import CycleAdvisor`，注释用中文）
- 每个 Task 结束必须 build（或有测试则 test）通过 + commit；commit message 英文单行摘要

---

### Task 1: 数据模型 + ConceptionStore（本地存储）

**Files:**
- Create: `Sources/Core/Models/ConceptionModels.swift`
- Create: `Sources/Core/ConceptionStore.swift`
- Test: `CycleAdvisorTests/ConceptionStoreTests.swift`

**Interfaces:**
- Produces（后续 Task 全部依赖这些签名）:
  - `enum Disturbance: String, Codable, CaseIterable, Identifiable { lateNight, alcohol, illness, insomnia }`，含 `var id: String`、`var displayName: String`
  - `enum TemperatureSource: String, Codable { wristTemperature, manual }`
  - `struct BasalTemperatureEntry: Codable, Equatable { date: Date; celsius: Double; disturbances: Set<Disturbance>; source: TemperatureSource }`，含 `static let validRange: ClosedRange<Double> = 35.0...38.0`
  - `struct DailyVitals: Codable, Equatable { date: Date; restingHeartRate: Double?; hrvSDNN: Double? }`
  - `enum SymptomSource: String, Codable { healthKit, manual, chatExtracted }`，含 `var priority: Int`（manual 3 > healthKit 2 > chatExtracted 1）
  - `enum PregnancySymptomType: String, Codable, CaseIterable { nausea, vomiting, fatigue, breastTenderness, bloating, abdominalCramps, headache, spotting, appetiteChange, moodChange, dizziness }`，含 `static let earlyPregnancySignals: Set<PregnancySymptomType>`
  - `struct SymptomRecord: Codable, Equatable { date: Date; type: PregnancySymptomType; source: SymptomSource }`
  - `enum PregnancyTestFeedback: Codable, Equatable { case positive(date: Date); case negative(date: Date, cycleStart: Date?) }`
  - `final class ConceptionStore: ObservableObject 风格 @Observable`，`static let shared`，`init(directory: URL = Documents)`
  - `@discardableResult func upsertManualTemperature(date: Date, celsius: Double, disturbances: Set<Disturbance>) -> Bool`
  - `func manualEntry(for date: Date) -> BasalTemperatureEntry?`
  - `func mergedTemperatures(wrist: [BasalTemperatureEntry]) -> [BasalTemperatureEntry]`
  - `func addSymptoms(_ records: [SymptomRecord])`
  - `func symptoms(since start: Date) -> [SymptomRecord]`
  - `func recordFeedback(_ feedback: PregnancyTestFeedback)` / `func dismissPrompt(forDays days: Int, from now: Date)` / `func clearFeedbackIfNewPeriod(lastPeriodStart: Date?)`
  - `private(set) var manualTemperatures / symptomRecords / testFeedback / dismissedUntil`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/ConceptionStoreTests.swift`：

```swift
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
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 35.0, disturbances: []))
        XCTAssertTrue(store.upsertManualTemperature(date: day(0), celsius: 38.0, disturbances: []))
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
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/ConceptionStoreTests 2>&1 | tail -5`
Expected: FAIL（编译错误，`ConceptionStore` 不存在）

- [ ] **Step 3: 实现数据模型**

新建 `Sources/Core/Models/ConceptionModels.swift`：

```swift
import Foundation

// MARK: - 干扰标记（仅手动录入可标记）

enum Disturbance: String, Codable, CaseIterable, Identifiable {
    case lateNight
    case alcohol
    case illness
    case insomnia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lateNight: return String(localized: "conception.bbt.disturbance.late_night")
        case .alcohol:   return String(localized: "conception.bbt.disturbance.alcohol")
        case .illness:   return String(localized: "conception.bbt.disturbance.illness")
        case .insomnia:  return String(localized: "conception.bbt.disturbance.insomnia")
        }
    }
}

// MARK: - 基础体温

enum TemperatureSource: String, Codable {
    case wristTemperature   // 手表自动（HealthKit 腕温）
    case manual             // 手动录入兜底
}

struct BasalTemperatureEntry: Codable, Equatable {
    /// 测量日（日粒度，startOfDay）
    var date: Date
    var celsius: Double
    var disturbances: Set<Disturbance>
    var source: TemperatureSource

    /// 合法录入范围，超出拒绝
    static let validRange: ClosedRange<Double> = 35.0...38.0
}

// MARK: - 手表每日生命体征

struct DailyVitals: Codable, Equatable {
    var date: Date
    /// bpm，当日均值
    var restingHeartRate: Double?
    /// ms，当日均值
    var hrvSDNN: Double?
}

// MARK: - 统一症状库

enum SymptomSource: String, Codable {
    case healthKit
    case manual
    case chatExtracted

    /// 去重冲突时保留高优先级来源
    var priority: Int {
        switch self {
        case .manual:        return 3
        case .healthKit:     return 2
        case .chatExtracted: return 1
        }
    }
}

enum PregnancySymptomType: String, Codable, CaseIterable {
    case nausea
    case vomiting
    case fatigue
    case breastTenderness
    case bloating
    case abdominalCramps
    case headache
    case spotting
    case appetiteChange
    case moodChange
    case dizziness

    /// 早孕佐证症状子集（当周期去重计数 ≥ 2 构成一项佐证信号）
    static let earlyPregnancySignals: Set<PregnancySymptomType> = [
        .nausea, .vomiting, .fatigue, .breastTenderness, .spotting
    ]
}

struct SymptomRecord: Codable, Equatable {
    /// 症状发生日（日粒度）
    var date: Date
    var type: PregnancySymptomType
    var source: SymptomSource
}

// MARK: - 验孕结果反馈

enum PregnancyTestFeedback: Codable, Equatable {
    /// 阳性：停止提示
    case positive(date: Date)
    /// 阴性：本周期内不再提示；cycleStart 为反馈时的当周期经期开始日（可能为 nil）
    case negative(date: Date, cycleStart: Date?)
}
```

- [ ] **Step 4: 实现 ConceptionStore**

新建 `Sources/Core/ConceptionStore.swift`：

```swift
import Foundation

/// 备孕数据本地存储：手动 BBT、统一症状库、验孕反馈。
/// 手表腕温 / RHR / HRV 不落本地，每次判定时从 HealthKit 现读。
/// 持久化模式与 UserProfileManager 相同（Documents 目录 JSON 文件）。
@Observable
final class ConceptionStore {

    static let shared = ConceptionStore()

    private(set) var manualTemperatures: [BasalTemperatureEntry] = []
    private(set) var symptomRecords: [SymptomRecord] = []
    private(set) var testFeedback: PregnancyTestFeedback?
    private(set) var dismissedUntil: Date?

    private let temperaturesURL: URL
    private let symptomsURL: URL
    private let feedbackURL: URL

    init(directory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        temperaturesURL = directory.appendingPathComponent("conception_temperatures.json")
        symptomsURL = directory.appendingPathComponent("conception_symptoms.json")
        feedbackURL = directory.appendingPathComponent("conception_feedback.json")
        load()
    }

    // MARK: - Temperature

    /// 录入手动 BBT。体温超出 35.0–38.0 拒绝（返回 false）；同日重复录入覆盖。
    @discardableResult
    func upsertManualTemperature(date: Date, celsius: Double, disturbances: Set<Disturbance>) -> Bool {
        guard BasalTemperatureEntry.validRange.contains(celsius) else { return false }
        let day = Calendar.current.startOfDay(for: date)
        manualTemperatures.removeAll { Calendar.current.isDate($0.date, inSameDayAs: day) }
        manualTemperatures.append(BasalTemperatureEntry(
            date: day, celsius: celsius, disturbances: disturbances, source: .manual
        ))
        manualTemperatures.sort { $0.date < $1.date }
        saveTemperatures()
        return true
    }

    func manualEntry(for date: Date) -> BasalTemperatureEntry? {
        manualTemperatures.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// 合并手表腕温与手动 BBT：同日以手表为准（夜间多次采样取均值，稳定性优于单次口温）。
    func mergedTemperatures(wrist: [BasalTemperatureEntry]) -> [BasalTemperatureEntry] {
        var byDay: [Date: BasalTemperatureEntry] = [:]
        for entry in manualTemperatures { byDay[entry.date] = entry }
        for entry in wrist { byDay[entry.date] = entry }
        return byDay.values.sorted { $0.date < $1.date }
    }

    // MARK: - Symptoms

    /// 写入症状，按 (日, 类型) 去重；冲突时保留高优先级来源。
    func addSymptoms(_ records: [SymptomRecord]) {
        guard !records.isEmpty else { return }
        for record in records {
            let normalized = SymptomRecord(
                date: Calendar.current.startOfDay(for: record.date),
                type: record.type,
                source: record.source
            )
            if let idx = symptomRecords.firstIndex(where: {
                Calendar.current.isDate($0.date, inSameDayAs: normalized.date) && $0.type == normalized.type
            }) {
                if normalized.source.priority > symptomRecords[idx].source.priority {
                    symptomRecords[idx] = normalized
                }
            } else {
                symptomRecords.append(normalized)
            }
        }
        symptomRecords.sort { $0.date < $1.date }
        saveSymptoms()
    }

    /// 某日起（含当日）的症状记录
    func symptoms(since start: Date) -> [SymptomRecord] {
        let day = Calendar.current.startOfDay(for: start)
        return symptomRecords.filter { $0.date >= day }
    }

    // MARK: - Feedback

    func recordFeedback(_ feedback: PregnancyTestFeedback) {
        testFeedback = feedback
        saveFeedback()
    }

    /// 忽略提示：days 天内不重复提示
    func dismissPrompt(forDays days: Int, from now: Date = .now) {
        dismissedUntil = Calendar.current.date(byAdding: .day, value: days, to: now)
        saveFeedback()
    }

    /// 检测到新经期开始后重置阴性反馈（新周期恢复提示）
    func clearFeedbackIfNewPeriod(lastPeriodStart: Date?) {
        guard let feedback = testFeedback,
              case .negative(_, let cycleStart) = feedback,
              let last = lastPeriodStart,
              let start = cycleStart,
              Calendar.current.startOfDay(for: last) > Calendar.current.startOfDay(for: start)
        else { return }
        testFeedback = nil
        dismissedUntil = nil
        saveFeedback()
    }

    // MARK: - Persistence

    private struct FeedbackState: Codable {
        var testFeedback: PregnancyTestFeedback?
        var dismissedUntil: Date?
    }

    private func saveTemperatures() {
        guard let data = try? JSONEncoder().encode(manualTemperatures) else { return }
        try? data.write(to: temperaturesURL, options: .atomic)
    }

    private func saveSymptoms() {
        guard let data = try? JSONEncoder().encode(symptomRecords) else { return }
        try? data.write(to: symptomsURL, options: .atomic)
    }

    private func saveFeedback() {
        let state = FeedbackState(testFeedback: testFeedback, dismissedUntil: dismissedUntil)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: feedbackURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: temperaturesURL),
           let saved = try? JSONDecoder().decode([BasalTemperatureEntry].self, from: data) {
            manualTemperatures = saved
        }
        if let data = try? Data(contentsOf: symptomsURL),
           let saved = try? JSONDecoder().decode([SymptomRecord].self, from: data) {
            symptomRecords = saved
        }
        if let data = try? Data(contentsOf: feedbackURL),
           let saved = try? JSONDecoder().decode(FeedbackState.self, from: data) {
            testFeedback = saved.testFeedback
            dismissedUntil = saved.dismissedUntil
        }
    }
}
```

注意：`PregnancyTestFeedback` 是带关联值的枚举，Swift 自动合成的 `Codable` 可直接处理，无需手写。

- [ ] **Step 5: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/ConceptionStoreTests 2>&1 | tail -5`
Expected: PASS（6 个测试）

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Models/ConceptionModels.swift Sources/Core/ConceptionStore.swift CycleAdvisorTests/ConceptionStoreTests.swift
git commit -m "Add conception data models and local store with dedup and feedback state"
```

---

### Task 2: OvulationLocator（3-over-6 排卵定位）

**Files:**
- Create: `Sources/Core/OvulationLocator.swift`
- Test: `CycleAdvisorTests/OvulationLocatorTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `BasalTemperatureEntry`、`Disturbance`、`TemperatureSource`
- Produces:
  - `struct OvulationLocator`，`func locate(temperatures: [BasalTemperatureEntry], referenceDate: Date) -> Result?`
  - `OvulationLocator.Result: Equatable { ovulationDay: Date; highTemperatureDays: Int; isStillElevated: Bool; usedDisturbedEntries: Bool }`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/OvulationLocatorTests.swift`：

```swift
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
        XCTAssertEqual(result?.highTemperatureDays, 12)
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
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/OvulationLocatorTests 2>&1 | tail -5`
Expected: FAIL（编译错误，`OvulationLocator` 不存在）

- [ ] **Step 3: 实现 OvulationLocator**

新建 `Sources/Core/OvulationLocator.swift`：

```swift
import Foundation

/// 排卵定位：3-over-6 规则。
/// 某日起连续 3 天温度 ≥ 前 6 个有效日均值 + 0.2°C → 判定升温，升温前最后一低温日为排卵日。
/// 腕温绝对值比口温高约 1°C，但规则看的是相对位移，阈值通用。
struct OvulationLocator {

    struct Result: Equatable {
        /// 排卵日 = 升温前最后一个有读数的低温日
        var ovulationDay: Date
        /// 截至参考日的高温相天数（缺测日照常计数，遇降温停止）
        var highTemperatureDays: Int
        /// 高温是否持续中（最新读数仍在高温线以上）
        var isStillElevated: Bool
        /// 定位是否使用了带干扰标记的补位条目（判定置信降一级）
        var usedDisturbedEntries: Bool
    }

    /// - Parameters:
    ///   - temperatures: 已合并的体温序列（任意顺序，同日只应有一条）
    ///   - referenceDate: 判定基准日（通常今天）
    /// - Returns: 定位结果；有效日 < 10 或未检测到双相时返回 nil
    func locate(temperatures: [BasalTemperatureEntry], referenceDate: Date) -> Result? {
        let calendar = Calendar.current
        let refDay = calendar.startOfDay(for: referenceDate)
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: refDay) else { return nil }

        // 有效性：手表条目全部有效；手动条目仅无干扰标记的有效。
        let valid = temperatures.filter { $0.source == .wristTemperature || $0.disturbances.isEmpty }
        // 降权补位：有干扰标记的手动条目仅在该日无有效读数时参与
        var usedDisturbed = false
        var series = valid
        for entry in temperatures where entry.source == .manual && !entry.disturbances.isEmpty {
            if !valid.contains(where: { calendar.isDate($0.date, inSameDayAs: entry.date) }) {
                series.append(entry)
                usedDisturbed = true
            }
        }

        var byDay: [Date: Double] = [:]
        for entry in series {
            let day = calendar.startOfDay(for: entry.date)
            guard day >= cutoff, day <= refDay else { continue }
            byDay[day] = entry.celsius
        }
        guard byDay.count >= 10 else { return nil }

        // 候选升温起点 d：d, d+1, d+2 三天均有读数且都 ≥ [d-6, d-1] 读数均值 + 0.2；
        // [d-6, d+2] 共 9 天窗口内缺测 > 2 天则跳过。取最早一次升温。
        guard let firstDay = byDay.keys.min() else { return nil }
        var shiftStart: Date?
        var shiftThreshold = 0.0
        var day = firstDay

        while day <= refDay, shiftStart == nil {
            if let d1 = calendar.date(byAdding: .day, value: 1, to: day),
               let d2 = calendar.date(byAdding: .day, value: 2, to: day),
               let t0 = byDay[day], let t1 = byDay[d1], let t2 = byDay[d2] {
                var baseline: [Double] = []
                var presentCount = 3 // d, d+1, d+2 已确认有读数
                for offset in -6...(-1) {
                    if let dd = calendar.date(byAdding: .day, value: offset, to: day),
                       let value = byDay[dd] {
                        baseline.append(value)
                        presentCount += 1
                    }
                }
                if 9 - presentCount <= 2, !baseline.isEmpty {
                    let threshold = baseline.reduce(0, +) / Double(baseline.count) + 0.2
                    if t0 >= threshold, t1 >= threshold, t2 >= threshold {
                        shiftStart = day
                        shiftThreshold = threshold
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        guard let shift = shiftStart else { return nil }

        // 排卵日 = 升温前最后一个有读数的低温日
        let ovulationDay = byDay.keys.filter { $0 < shift }.max()
            ?? calendar.date(byAdding: .day, value: -1, to: shift)!

        // 高温相计数：从升温起点走到参考日，遇低于阈值的读数停止
        var highDays = 0
        var stillElevated = true
        var cursor = shift
        while cursor <= refDay {
            if let value = byDay[cursor] {
                if value >= shiftThreshold {
                    highDays += 1
                } else {
                    stillElevated = false
                    break
                }
            } else {
                highDays += 1 // 缺测日不中断高温相
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return Result(
            ovulationDay: ovulationDay,
            highTemperatureDays: highDays,
            isStillElevated: stillElevated,
            usedDisturbedEntries: usedDisturbed
        )
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/OvulationLocatorTests 2>&1 | tail -5`
Expected: PASS（8 个测试）。若 `testTemperatureDropEndsHighPhase` 天数断言差 1，检查高温计数起点是 shift 当天（含）还是次日——以"升温当天算高温第 1 天"为准调整测试或实现，保持二者一致。

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/OvulationLocator.swift CycleAdvisorTests/OvulationLocatorTests.swift
git commit -m "Add 3-over-6 ovulation locator with gap and disturbance handling"
```

---
### Task 3: PregnancyInsightEngine（判定引擎，核心）

**Files:**
- Create: `Sources/Core/PregnancyInsightEngine.swift`
- Test: `CycleAdvisorTests/PregnancyInsightEngineTests.swift`

**Interfaces:**
- Consumes: Task 1 的模型；Task 2 的 `OvulationLocator`
- Produces:
  - `enum PregnancyInsight: Equatable { case insufficient; case tracking(lutealDay: Int); case possible(reasons: [InsightReason]); case likely(reasons: [InsightReason]) }`
  - `enum InsightReason: Equatable { case sustainedHighTemperature(days: Int); case periodLate(days: Int); case elevatedRestingHeartRate(deltaBPM: Int); case suppressedHRV(percent: Int); case earlySymptoms(count: Int) }`
  - `struct PregnancyInsightEngine`，含 `struct Input` 与 `func evaluate(_ input: Input) -> PregnancyInsight`
  - `PregnancyInsightEngine.Input { temperatures: [BasalTemperatureEntry]; vitals: [DailyVitals]; symptoms: [SymptomRecord]; lastPeriodStart: Date?; expectedPeriodStart: Date?; referenceDate: Date; testFeedback: PregnancyTestFeedback?; dismissedUntil: Date? }`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/PregnancyInsightEngineTests.swift`：

```swift
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
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/PregnancyInsightEngineTests 2>&1 | tail -5`
Expected: FAIL（编译错误）

- [ ] **Step 3: 实现 PregnancyInsightEngine**

新建 `Sources/Core/PregnancyInsightEngine.swift`：

```swift
import Foundation

// MARK: - 提示等级

enum PregnancyInsight: Equatable {
    /// 数据不足，不出任何提示
    case insufficient
    /// 已定位排卵，高温相 < 12 天（展示黄体期第 X 天）
    case tracking(lutealDay: Int)
    /// 温和提示：现在可以用验孕棒检测了
    case possible(reasons: [InsightReason])
    /// 较强提示：建议尽快验孕确认（必须有温度主信号）
    case likely(reasons: [InsightReason])
}

/// 提示触发原因（用于 UI 解释展示）
enum InsightReason: Equatable {
    case sustainedHighTemperature(days: Int)
    case periodLate(days: Int)
    case elevatedRestingHeartRate(deltaBPM: Int)
    case suppressedHRV(percent: Int)
    case earlySymptoms(count: Int)
}

// MARK: - 判定引擎（本地纯逻辑）

/// 信号分层：温度主信号独立触发；RHR/HRV/症状为佐证只升档；经期推迟为基础信号。
struct PregnancyInsightEngine {

    struct Input {
        /// 已合并的体温序列（手表优先）
        var temperatures: [BasalTemperatureEntry]
        var vitals: [DailyVitals]
        var symptoms: [SymptomRecord]
        var lastPeriodStart: Date?
        /// 预期经期日（由 CyclePhaseEngine.nextPeriodDate 得出）
        var expectedPeriodStart: Date?
        var referenceDate: Date
        var testFeedback: PregnancyTestFeedback?
        var dismissedUntil: Date?
    }

    /// 佐证信号集合（全部相对个人卵泡期基线，不设绝对阈值）
    struct CorroboratingSignals: Equatable {
        var rhrDeltaBPM: Int?
        var hrvDropPercent: Int?
        var earlySymptomCount: Int

        var count: Int {
            (rhrDeltaBPM != nil ? 1 : 0)
                + (hrvDropPercent != nil ? 1 : 0)
                + (earlySymptomCount >= 2 ? 1 : 0)
        }
    }

    private let locator = OvulationLocator()

    init() {}

    func evaluate(_ input: Input) -> PregnancyInsight {
        // 阳性反馈：停止一切提示
        if let feedback = input.testFeedback, case .positive = feedback {
            return .insufficient
        }

        let calendar = Calendar.current
        let refDay = calendar.startOfDay(for: input.referenceDate)
        let located = locator.locate(temperatures: input.temperatures, referenceDate: refDay)

        // 排卵若发生在本次经期之前，属于上一周期，不用来判定
        let usable: OvulationLocator.Result? = located.flatMap { result in
            if let period = input.lastPeriodStart,
               calendar.startOfDay(for: period) > result.ovulationDay {
                return nil
            }
            return result
        }

        let lateDays = periodLateDays(
            expected: input.expectedPeriodStart,
            lastPeriodStart: input.lastPeriodStart,
            referenceDay: refDay
        )
        let symptomWindowStart = usable?.ovulationDay
            ?? input.lastPeriodStart.map { calendar.startOfDay(for: $0) }
        let signals = corroboratingSignals(
            vitals: input.vitals,
            symptoms: input.symptoms,
            lastPeriodStart: input.lastPeriodStart,
            symptomWindowStart: symptomWindowStart,
            referenceDay: refDay
        )

        var insight: PregnancyInsight
        if let result = usable, result.isStillElevated {
            let lutealDay = calendar.dateComponents([.day], from: result.ovulationDay, to: refDay).day ?? 0
            var reasons: [InsightReason] = [.sustainedHighTemperature(days: result.highTemperatureDays)]
            if lateDays > 0 { reasons.append(.periodLate(days: lateDays)) }
            reasons.append(contentsOf: signalReasons(signals))

            if result.highTemperatureDays >= 16
                || (result.highTemperatureDays >= 14 && signals.count >= 2) {
                // 使用降权（干扰标记）数据时置信降一级
                insight = result.usedDisturbedEntries
                    ? .possible(reasons: reasons)
                    : .likely(reasons: reasons)
            } else if result.highTemperatureDays >= 12
                || (lateDays >= 1 && lateDays <= 3 && signals.count >= 1) {
                insight = .possible(reasons: reasons)
            } else {
                insight = .tracking(lutealDay: lutealDay)
            }
        } else if usable == nil, located == nil {
            // 降级路径：完全无温度数据，无法定位排卵
            if lateDays >= 3 && signals.count >= 2 {
                var reasons: [InsightReason] = [.periodLate(days: lateDays)]
                reasons.append(contentsOf: signalReasons(signals))
                insight = .possible(reasons: reasons)
            } else {
                insight = .insufficient
            }
        } else {
            // 高温相已回落（月经将至/新周期已开始）
            insight = .insufficient
        }

        return applyFeedbackGating(insight, input: input, usable: usable, refDay: refDay)
    }

    // MARK: - 基础信号

    /// 月经推迟天数（经期已至则为 0）
    private func periodLateDays(expected: Date?, lastPeriodStart: Date?, referenceDay: Date) -> Int {
        guard let expected else { return 0 }
        let calendar = Calendar.current
        let expectedDay = calendar.startOfDay(for: expected)
        if let last = lastPeriodStart, calendar.startOfDay(for: last) >= expectedDay { return 0 }
        return max(0, calendar.dateComponents([.day], from: expectedDay, to: referenceDay).day ?? 0)
    }

    // MARK: - 佐证信号

    private func corroboratingSignals(
        vitals: [DailyVitals],
        symptoms: [SymptomRecord],
        lastPeriodStart: Date?,
        symptomWindowStart: Date?,
        referenceDay: Date
    ) -> CorroboratingSignals {
        let calendar = Calendar.current

        // 卵泡期基线：本周期前 7 天滚动均值
        var rhrBaseline: Double?
        var hrvBaseline: Double?
        if let start = lastPeriodStart.map({ calendar.startOfDay(for: $0) }),
           let end = calendar.date(byAdding: .day, value: 7, to: start) {
            let window = vitals.filter { $0.date >= start && $0.date < end }
            let rhrs = window.compactMap(\.restingHeartRate)
            let hrvs = window.compactMap(\.hrvSDNN)
            if !rhrs.isEmpty { rhrBaseline = rhrs.reduce(0, +) / Double(rhrs.count) }
            if !hrvs.isEmpty { hrvBaseline = hrvs.reduce(0, +) / Double(hrvs.count) }
        }

        // RHR 升高：最近 5 个有读数的日均 ≥ 基线 + 2（未孕周期 RHR 经前回落，怀孕则持续爬升）
        var rhrDelta: Int?
        if let baseline = rhrBaseline {
            let recent = vitals
                .filter { $0.date <= referenceDay }
                .compactMap { $0.restingHeartRate }
                .suffix(5)
            if recent.count >= 5, recent.allSatisfy({ $0 >= baseline + 2 }) {
                rhrDelta = Int((recent.reduce(0, +) / 5.0 - baseline).rounded())
            }
        }

        // HRV 抑制：最近 5 个有读数的日均 ≤ 基线 × 0.9
        var hrvDrop: Int?
        if let baseline = hrvBaseline, baseline > 0 {
            let recent = vitals
                .filter { $0.date <= referenceDay }
                .compactMap { $0.hrvSDNN }
                .suffix(5)
            if recent.count >= 5, recent.allSatisfy({ $0 <= baseline * 0.9 }) {
                let average = recent.reduce(0, +) / 5.0
                hrvDrop = Int(((baseline - average) / baseline * 100).rounded())
            }
        }

        // 早孕症状：窗口内去重计数（恶心/呕吐/疲倦/乳房胀痛/点滴出血）
        var symptomCount = 0
        if let windowStart = symptomWindowStart {
            symptomCount = Set(
                symptoms
                    .filter { $0.date >= windowStart
                        && PregnancySymptomType.earlyPregnancySignals.contains($0.type) }
                    .map(\.type)
            ).count
        }

        return CorroboratingSignals(
            rhrDeltaBPM: rhrDelta,
            hrvDropPercent: hrvDrop,
            earlySymptomCount: symptomCount
        )
    }

    private func signalReasons(_ signals: CorroboratingSignals) -> [InsightReason] {
        var reasons: [InsightReason] = []
        if let delta = signals.rhrDeltaBPM { reasons.append(.elevatedRestingHeartRate(deltaBPM: delta)) }
        if let percent = signals.hrvDropPercent { reasons.append(.suppressedHRV(percent: percent)) }
        if signals.earlySymptomCount >= 2 { reasons.append(.earlySymptoms(count: signals.earlySymptomCount)) }
        return reasons
    }

    // MARK: - 反馈门控

    /// 阴性（本周期内）与忽略（7 天内）把 possible/likely 降回 tracking/insufficient
    private func applyFeedbackGating(
        _ insight: PregnancyInsight,
        input: Input,
        usable: OvulationLocator.Result?,
        refDay: Date
    ) -> PregnancyInsight {
        let calendar = Calendar.current
        var suppressed = false

        if let feedback = input.testFeedback, case .negative(_, let cycleStart) = feedback {
            let currentCycle = input.lastPeriodStart.map { calendar.startOfDay(for: $0) }
            let feedbackCycle = cycleStart.map { calendar.startOfDay(for: $0) }
            // 无新经期数据，或经期日未超过反馈时的周期起点 → 仍在同一周期
            if let current = currentCycle {
                suppressed = current <= (feedbackCycle ?? .distantPast)
            } else {
                suppressed = feedbackCycle == nil
            }
        }
        if let until = input.dismissedUntil, refDay < calendar.startOfDay(for: until) {
            suppressed = true
        }

        guard suppressed else { return insight }
        switch insight {
        case .possible, .likely:
            if let usable {
                let lutealDay = calendar.dateComponents([.day], from: usable.ovulationDay, to: refDay).day ?? 0
                return .tracking(lutealDay: lutealDay)
            }
            return .insufficient
        default:
            return insight
        }
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/PregnancyInsightEngineTests 2>&1 | tail -5`
Expected: PASS（14 个测试）

- [ ] **Step 5: 跑全部已有测试确认无回归**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/PregnancyInsightEngine.swift CycleAdvisorTests/PregnancyInsightEngineTests.swift
git commit -m "Add pregnancy insight engine with tiered signals and feedback gating"
```

---

### Task 4: HealthKitManager 扩展（腕温 / RHR / HRV 日序列 + 早孕症状）

**Files:**
- Modify: `Sources/Core/HealthKitManager.swift`（readTypes 追加 5 个类型；文件末尾追加三个 fetch 方法）

**Interfaces:**
- Produces:
  - `HealthKitManager.fetchWristTemperatureSeries(daysBack: Int = 60) async -> [BasalTemperatureEntry]`（source 固定 `.wristTemperature`，同日多样本取均值）
  - `HealthKitManager.fetchDailyVitals(daysBack: Int = 60) async -> [DailyVitals]`
  - `HealthKitManager.fetchPregnancySymptoms(daysBack: Int = 60) async -> [SymptomRecord]`（source 固定 `.healthKit`）

HealthKit 查询依赖真机/模拟器授权数据，无法单测；本 Task 以 build 通过为验收，聚合逻辑（按日分组取均值）保持直白。

- [ ] **Step 1: 扩展 readTypes**

在 `Sources/Core/HealthKitManager.swift` 的 `readTypes` 集合中（`HKQuantityType(.heartRateVariabilitySDNN)` 一行之前）追加：

```swift
        HKQuantityType(.appleSleepingWristTemperature),
```

在症状类别区域（`HKCategoryType(.appetiteChanges),` 一行之后）追加：

```swift
        HKCategoryType(.nausea),
        HKCategoryType(.vomiting),
        HKCategoryType(.dizziness),
        HKCategoryType(.intermenstrualBleeding),
```

- [ ] **Step 2: 追加三个 fetch 方法**

在 `HealthKitManager` 的 `// MARK: - Historical Cycle Data (Profile)` 一节之前插入：

```swift
    // MARK: - Conception Tracking (Wrist Temperature / Vitals / Early Symptoms)

    /// 最近 daysBack 天的腕温日序列（同日多样本取均值）。样本本身就是摄氏度绝对值。
    /// 需要 Series 8+/Ultra 佩戴睡眠约 2 周建立基线；数据不足时返回的数组较短，由调用方判定。
    func fetchWristTemperatureSeries(daysBack: Int = 60) async -> [BasalTemperatureEntry] {
        let type = HKQuantityType(.appleSleepingWristTemperature)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysBack, to: Date())!
        let samples = await fetchQuantitySamples(type: type, start: start, end: Date())

        var byDay: [Date: (sum: Double, count: Int)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            let value = sample.quantity.doubleValue(for: .degreeCelsius())
            var bucket = byDay[day] ?? (0, 0)
            bucket.sum += value
            bucket.count += 1
            byDay[day] = bucket
        }
        return byDay.map { day, bucket in
            BasalTemperatureEntry(
                date: day,
                celsius: bucket.sum / Double(bucket.count),
                disturbances: [],
                source: .wristTemperature
            )
        }.sorted { $0.date < $1.date }
    }

    /// 最近 daysBack 天的每日生命体征（RHR / HRV 当日均值）
    func fetchDailyVitals(daysBack: Int = 60) async -> [DailyVitals] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysBack, to: Date())!
        let now = Date()

        async let rhrSamples = fetchQuantitySamples(
            type: HKQuantityType(.restingHeartRate), start: start, end: now
        )
        async let hrvSamples = fetchQuantitySamples(
            type: HKQuantityType(.heartRateVariabilitySDNN), start: start, end: now
        )
        let (rhr, hrv) = await (rhrSamples, hrvSamples)

        let rhrUnit = HKUnit.count().unitDivided(by: .minute())
        let hrvUnit = HKUnit.secondUnit(with: .milli)

        var rhrByDay: [Date: (sum: Double, count: Int)] = [:]
        for sample in rhr {
            let day = calendar.startOfDay(for: sample.startDate)
            var bucket = rhrByDay[day] ?? (0, 0)
            bucket.sum += sample.quantity.doubleValue(for: rhrUnit)
            bucket.count += 1
            rhrByDay[day] = bucket
        }
        var hrvByDay: [Date: (sum: Double, count: Int)] = [:]
        for sample in hrv {
            let day = calendar.startOfDay(for: sample.startDate)
            var bucket = hrvByDay[day] ?? (0, 0)
            bucket.sum += sample.quantity.doubleValue(for: hrvUnit)
            bucket.count += 1
            hrvByDay[day] = bucket
        }

        let allDays = Set(rhrByDay.keys).union(hrvByDay.keys)
        return allDays.map { day in
            DailyVitals(
                date: day,
                restingHeartRate: rhrByDay[day].map { $0.sum / Double($0.count) },
                hrvSDNN: hrvByDay[day].map { $0.sum / Double($0.count) }
            )
        }.sorted { $0.date < $1.date }
    }

    /// 最近 daysBack 天的早孕相关症状（含已有经期症状类型的全量样本）
    func fetchPregnancySymptoms(daysBack: Int = 60) async -> [SymptomRecord] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -daysBack, to: Date())!
        let now = Date()

        let mapping: [(HKCategoryType, PregnancySymptomType)] = [
            (HKCategoryType(.nausea),                .nausea),
            (HKCategoryType(.vomiting),              .vomiting),
            (HKCategoryType(.fatigue),               .fatigue),
            (HKCategoryType(.breastPain),            .breastTenderness),
            (HKCategoryType(.bloating),              .bloating),
            (HKCategoryType(.abdominalCramps),       .abdominalCramps),
            (HKCategoryType(.headache),              .headache),
            (HKCategoryType(.intermenstrualBleeding), .spotting),
            (HKCategoryType(.appetiteChanges),       .appetiteChange),
            (HKCategoryType(.moodChanges),           .moodChange),
            (HKCategoryType(.dizziness),             .dizziness),
        ]

        var records: [SymptomRecord] = []
        for (hkType, type) in mapping {
            let samples = await fetchCategorySamples(
                type: hkType, start: start, end: now,
                limit: HKObjectQueryNoLimit, ascending: true
            )
            records += samples.map {
                SymptomRecord(
                    date: calendar.startOfDay(for: $0.startDate),
                    type: type,
                    source: .healthKit
                )
            }
        }
        return records
    }
```

- [ ] **Step 3: Build 确认编译通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/HealthKitManager.swift
git commit -m "Add wrist temperature, daily vitals, and pregnancy symptom HealthKit fetchers"
```

---
### Task 5: 本地化（7 语言全量文案）

**Files:**
- Modify: `Sources/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/Resources/zh-Hant.lproj/Localizable.strings`
- Modify: `Sources/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/Resources/ja.lproj/Localizable.strings`
- Modify: `Sources/Resources/ko.lproj/Localizable.strings`
- Modify: `Sources/Resources/es.lproj/Localizable.strings`
- Modify: `Sources/Resources/fr.lproj/Localizable.strings`

本任务先行，后续所有 UI 任务直接引用这些 key。每个文件末尾追加对应语言的段落（注意 strings 文件中 `%lld` 对应 Swift `String(format:)` 的 Int 参数，`%%` 是字面百分号）。

- [ ] **Step 1: zh-Hans 追加**

```strings
/* Conception (备孕) */
"settings.section.conception" = "备孕";
"settings.conception.title" = "备孕模式";
"settings.conception.hint" = "开启后将基于你的健康数据追踪周期信号，并在合适时机提示验孕";
"conception.onboarding.title" = "备孕模式说明";
"conception.onboarding.body" = "此功能通过体温等周期信号提示合适的验孕时机，不构成医疗诊断。确认怀孕请以验孕棒检测或就医为准。";
"conception.onboarding.ok" = "我知道了";
"conception.card.title" = "备孕追踪";
"conception.card.luteal_day" = "黄体期第 %lld 天";
"conception.card.insufficient" = "数据还不足——坚持每日测温（或佩戴手表睡眠）会让判断更准";
"conception.card.possible" = "现在可以用验孕棒检测了";
"conception.card.likely" = "建议尽快验孕确认";
"conception.card.disclaimer" = "此功能不构成医疗诊断";
"conception.card.record_result" = "记录验孕结果";
"conception.card.positive_recorded" = "已记录阳性结果，建议就医确认";
"conception.feedback.positive" = "阳性";
"conception.feedback.negative" = "阴性";
"conception.feedback.dismiss" = "7 天内不再提示";
"conception.bbt.title" = "记录基础体温";
"conception.bbt.celsius" = "体温（°C）";
"conception.bbt.disturbances" = "干扰因素（可选）";
"conception.bbt.disturbance.late_night" = "熬夜";
"conception.bbt.disturbance.alcohol" = "饮酒";
"conception.bbt.disturbance.illness" = "生病";
"conception.bbt.disturbance.insomnia" = "失眠";
"conception.bbt.measured_today" = "今早已测 ✓";
"conception.bbt.invalid" = "请输入 35.0–38.0 之间的体温";
"conception.bbt.entry" = "手动录入体温";
"conception.bbt.save" = "保存";
"conception.reminder.time" = "晨间测温提醒";
"conception.reminder.body" = "该测体温啦";
"conception.reason.high_temp" = "体温持续高位 %lld 天";
"conception.reason.period_late" = "月经推迟 %lld 天";
"conception.reason.rhr" = "静息心率较基线上升 %lld bpm";
"conception.reason.hrv" = "HRV 较基线下降 %lld%%";
"conception.reason.symptoms" = "出现 %lld 项早孕相关症状";
```

- [ ] **Step 2: zh-Hant 追加**

```strings
/* Conception (備孕) */
"settings.section.conception" = "備孕";
"settings.conception.title" = "備孕模式";
"settings.conception.hint" = "開啟後將基於你的健康資料追蹤週期訊號，並在合適時機提示驗孕";
"conception.onboarding.title" = "備孕模式說明";
"conception.onboarding.body" = "此功能透過體溫等週期訊號提示合適的驗孕時機，不構成醫療診斷。確認懷孕請以驗孕棒檢測或就醫為準。";
"conception.onboarding.ok" = "我知道了";
"conception.card.title" = "備孕追蹤";
"conception.card.luteal_day" = "黃體期第 %lld 天";
"conception.card.insufficient" = "資料還不足——堅持每日測溫（或佩戴手錶睡眠）會讓判斷更準";
"conception.card.possible" = "現在可以用驗孕棒檢測了";
"conception.card.likely" = "建議盡快驗孕確認";
"conception.card.disclaimer" = "此功能不構成醫療診斷";
"conception.card.record_result" = "記錄驗孕結果";
"conception.card.positive_recorded" = "已記錄陽性結果，建議就醫確認";
"conception.feedback.positive" = "陽性";
"conception.feedback.negative" = "陰性";
"conception.feedback.dismiss" = "7 天內不再提示";
"conception.bbt.title" = "記錄基礎體溫";
"conception.bbt.celsius" = "體溫（°C）";
"conception.bbt.disturbances" = "干擾因素（可選）";
"conception.bbt.disturbance.late_night" = "熬夜";
"conception.bbt.disturbance.alcohol" = "飲酒";
"conception.bbt.disturbance.illness" = "生病";
"conception.bbt.disturbance.insomnia" = "失眠";
"conception.bbt.measured_today" = "今早已測 ✓";
"conception.bbt.invalid" = "請輸入 35.0–38.0 之間的體溫";
"conception.bbt.entry" = "手動錄入體溫";
"conception.bbt.save" = "儲存";
"conception.reminder.time" = "晨間測溫提醒";
"conception.reminder.body" = "該測體溫啦";
"conception.reason.high_temp" = "體溫持續高位 %lld 天";
"conception.reason.period_late" = "月經推遲 %lld 天";
"conception.reason.rhr" = "靜息心率較基線上升 %lld bpm";
"conception.reason.hrv" = "HRV 較基線下降 %lld%%";
"conception.reason.symptoms" = "出現 %lld 項早孕相關症狀";
```

- [ ] **Step 3: en 追加**

```strings
/* Conception */
"settings.section.conception" = "Conception";
"settings.conception.title" = "Trying to Conceive";
"settings.conception.hint" = "When on, CycleAdvisor tracks cycle signals from your health data and suggests when to take a pregnancy test";
"conception.onboarding.title" = "About Trying to Conceive";
"conception.onboarding.body" = "This feature uses signals like body temperature to suggest when to take a pregnancy test. It is not a medical diagnosis — confirm pregnancy with a test or your doctor.";
"conception.onboarding.ok" = "Got it";
"conception.card.title" = "Conception Tracking";
"conception.card.luteal_day" = "Luteal phase day %lld";
"conception.card.insufficient" = "Not enough data yet — daily temperature readings (or wearing your watch to sleep) improve accuracy";
"conception.card.possible" = "You can take a pregnancy test now";
"conception.card.likely" = "Take a pregnancy test soon to confirm";
"conception.card.disclaimer" = "This feature is not a medical diagnosis";
"conception.card.record_result" = "Record Test Result";
"conception.card.positive_recorded" = "Positive result recorded — consider confirming with your doctor";
"conception.feedback.positive" = "Positive";
"conception.feedback.negative" = "Negative";
"conception.feedback.dismiss" = "Dismiss for 7 days";
"conception.bbt.title" = "Log Basal Temperature";
"conception.bbt.celsius" = "Temperature (°C)";
"conception.bbt.disturbances" = "Disturbances (optional)";
"conception.bbt.disturbance.late_night" = "Late night";
"conception.bbt.disturbance.alcohol" = "Alcohol";
"conception.bbt.disturbance.illness" = "Illness";
"conception.bbt.disturbance.insomnia" = "Insomnia";
"conception.bbt.measured_today" = "Measured this morning ✓";
"conception.bbt.invalid" = "Enter a temperature between 35.0 and 38.0";
"conception.bbt.entry" = "Log temperature manually";
"conception.bbt.save" = "Save";
"conception.reminder.time" = "Morning temperature reminder";
"conception.reminder.body" = "Time to take your temperature";
"conception.reason.high_temp" = "Temperature elevated for %lld days";
"conception.reason.period_late" = "Period %lld days late";
"conception.reason.rhr" = "Resting heart rate %lld bpm above baseline";
"conception.reason.hrv" = "HRV %lld%% below baseline";
"conception.reason.symptoms" = "%lld early-pregnancy symptoms";
```

- [ ] **Step 4: ja 追加**

```strings
/* Conception (妊娠準備) */
"settings.section.conception" = "妊娠準備";
"settings.conception.title" = "妊娠準備モード";
"settings.conception.hint" = "オンにすると、健康データから周期のサインを追跡し、適切なタイミングで妊娠検査を提案します";
"conception.onboarding.title" = "妊娠準備モードについて";
"conception.onboarding.body" = "この機能は体温などの周期サインから検査の適切な時期を提案するもので、医療診断ではありません。妊娠の確認は検査薬または医師にご相談ください。";
"conception.onboarding.ok" = "了解しました";
"conception.card.title" = "妊娠準備トラッキング";
"conception.card.luteal_day" = "黄体期 %lld 日目";
"conception.card.insufficient" = "データがまだ不足しています——毎日の計測（または睡眠時の腕時計着用）で精度が上がります";
"conception.card.possible" = "妊娠検査薬で確認できます";
"conception.card.likely" = "早めの妊娠検査をおすすめします";
"conception.card.disclaimer" = "この機能は医療診断ではありません";
"conception.card.record_result" = "検査結果を記録";
"conception.card.positive_recorded" = "陽性を記録しました。医療機関での確認をおすすめします";
"conception.feedback.positive" = "陽性";
"conception.feedback.negative" = "陰性";
"conception.feedback.dismiss" = "7日間表示しない";
"conception.bbt.title" = "基礎体温を記録";
"conception.bbt.celsius" = "体温（°C）";
"conception.bbt.disturbances" = "影響要因（任意）";
"conception.bbt.disturbance.late_night" = "夜更かし";
"conception.bbt.disturbance.alcohol" = "飲酒";
"conception.bbt.disturbance.illness" = "体調不良";
"conception.bbt.disturbance.insomnia" = "不眠";
"conception.bbt.measured_today" = "今朝計測済み ✓";
"conception.bbt.invalid" = "35.0〜38.0 の体温を入力してください";
"conception.bbt.entry" = "手動で体温を記録";
"conception.bbt.save" = "保存";
"conception.reminder.time" = "朝の計測リマインダー";
"conception.reminder.body" = "体温を測りましょう";
"conception.reason.high_temp" = "高温期 %lld 日継続";
"conception.reason.period_late" = "生理が %lld 日遅れています";
"conception.reason.rhr" = "安静時心拍数がベースラインより %lld bpm 上昇";
"conception.reason.hrv" = "HRV がベースラインより %lld%% 低下";
"conception.reason.symptoms" = "妊娠初期症状が %lld 件";
```

- [ ] **Step 5: ko 追加**

```strings
/* Conception (임신 준비) */
"settings.section.conception" = "임신 준비";
"settings.conception.title" = "임신 준비 모드";
"settings.conception.hint" = "켜면 건강 데이터를 기반으로 주기 신호를 추적하고 적절한 시기에 임신 테스트를 제안합니다";
"conception.onboarding.title" = "임신 준비 모드 안내";
"conception.onboarding.body" = "이 기능은 체온 등의 주기 신호로 임신 테스트 적기를 제안하며 의료 진단이 아닙니다. 임신 확인은 테스트기 또는 병원에서 하세요.";
"conception.onboarding.ok" = "확인";
"conception.card.title" = "임신 준비 추적";
"conception.card.luteal_day" = "황체기 %lld일차";
"conception.card.insufficient" = "데이터가 아직 부족합니다——매일 체온 측정(또는 수면 시 워치 착용)으로 정확도를 높이세요";
"conception.card.possible" = "지금 임신 테스트기로 확인할 수 있어요";
"conception.card.likely" = "빠른 임신 테스트를 권장합니다";
"conception.card.disclaimer" = "이 기능은 의료 진단이 아닙니다";
"conception.card.record_result" = "테스트 결과 기록";
"conception.card.positive_recorded" = "양성 결과가 기록되었습니다. 병원에서 확인해 보세요";
"conception.feedback.positive" = "양성";
"conception.feedback.negative" = "음성";
"conception.feedback.dismiss" = "7일간 표시 안 함";
"conception.bbt.title" = "기초 체온 기록";
"conception.bbt.celsius" = "체온(°C)";
"conception.bbt.disturbances" = "영향 요인(선택)";
"conception.bbt.disturbance.late_night" = "늦게 잠듦";
"conception.bbt.disturbance.alcohol" = "음주";
"conception.bbt.disturbance.illness" = "아픔";
"conception.bbt.disturbance.insomnia" = "불면";
"conception.bbt.measured_today" = "오늘 아침 측정 완료 ✓";
"conception.bbt.invalid" = "35.0–38.0 사이의 체온을 입력하세요";
"conception.bbt.entry" = "수동으로 체온 입력";
"conception.bbt.save" = "저장";
"conception.reminder.time" = "아침 체온 알림";
"conception.reminder.body" = "체온을 측정할 시간이에요";
"conception.reason.high_temp" = "고온 상태 %lld일 지속";
"conception.reason.period_late" = "생리가 %lld일 늦어졌어요";
"conception.reason.rhr" = "안정 시 심박수가 기준보다 %lld bpm 상승";
"conception.reason.hrv" = "HRV가 기준보다 %lld%% 하강";
"conception.reason.symptoms" = "임신 초기 증상 %lld개";
```

- [ ] **Step 6: es 追加**

```strings
/* Conception (concepción) */
"settings.section.conception" = "Concepción";
"settings.conception.title" = "Modo concepción";
"settings.conception.hint" = "Al activarlo, se rastrean señales del ciclo con tus datos de salud y se sugiere cuándo hacer una prueba de embarazo";
"conception.onboarding.title" = "Acerca del modo concepción";
"conception.onboarding.body" = "Esta función usa señales como la temperatura para sugerir cuándo hacerte una prueba. No es un diagnóstico médico: confirma con una prueba o tu médico.";
"conception.onboarding.ok" = "Entendido";
"conception.card.title" = "Seguimiento de concepción";
"conception.card.luteal_day" = "Día %lld de fase lútea";
"conception.card.insufficient" = "Datos insuficientes: mide tu temperatura a diario (o duerme con el reloj) para más precisión";
"conception.card.possible" = "Ya puedes hacerte una prueba de embarazo";
"conception.card.likely" = "Hazte una prueba de embarazo pronto para confirmar";
"conception.card.disclaimer" = "Esta función no es un diagnóstico médico";
"conception.card.record_result" = "Registrar resultado";
"conception.card.positive_recorded" = "Resultado positivo registrado; confírmalo con tu médico";
"conception.feedback.positive" = "Positivo";
"conception.feedback.negative" = "Negativo";
"conception.feedback.dismiss" = "Ocultar 7 días";
"conception.bbt.title" = "Registrar temperatura basal";
"conception.bbt.celsius" = "Temperatura (°C)";
"conception.bbt.disturbances" = "Factores de alteración (opcional)";
"conception.bbt.disturbance.late_night" = "Trasnochar";
"conception.bbt.disturbance.alcohol" = "Alcohol";
"conception.bbt.disturbance.illness" = "Enfermedad";
"conception.bbt.disturbance.insomnia" = "Insomnio";
"conception.bbt.measured_today" = "Medida esta mañana ✓";
"conception.bbt.invalid" = "Introduce una temperatura entre 35,0 y 38,0";
"conception.bbt.entry" = "Registrar temperatura manualmente";
"conception.bbt.save" = "Guardar";
"conception.reminder.time" = "Recordatorio matutino";
"conception.reminder.body" = "Es hora de medir tu temperatura";
"conception.reason.high_temp" = "Temperatura alta desde hace %lld días";
"conception.reason.period_late" = "Regla con %lld días de retraso";
"conception.reason.rhr" = "Frecuencia en reposo %lld bpm sobre la base";
"conception.reason.hrv" = "HRV %lld%% por debajo de la base";
"conception.reason.symptoms" = "%lld síntomas de embarazo temprano";
```

- [ ] **Step 7: fr 追加**

```strings
/* Conception */
"settings.section.conception" = "Conception";
"settings.conception.title" = "Mode conception";
"settings.conception.hint" = "Une fois activé, les signaux du cycle sont suivis à partir de vos données de santé pour suggérer le bon moment pour un test de grossesse";
"conception.onboarding.title" = "À propos du mode conception";
"conception.onboarding.body" = "Cette fonction utilise des signaux comme la température pour suggérer quand faire un test. Ce n'est pas un diagnostic médical : confirmez avec un test ou votre médecin.";
"conception.onboarding.ok" = "J'ai compris";
"conception.card.title" = "Suivi de conception";
"conception.card.luteal_day" = "Jour %lld de phase lutéale";
"conception.card.insufficient" = "Données insuffisantes — mesurez votre température chaque jour (ou portez votre montre la nuit) pour plus de précision";
"conception.card.possible" = "Vous pouvez faire un test de grossesse";
"conception.card.likely" = "Faites bientôt un test de grossesse pour confirmer";
"conception.card.disclaimer" = "Cette fonction ne constitue pas un diagnostic médical";
"conception.card.record_result" = "Enregistrer le résultat";
"conception.card.positive_recorded" = "Résultat positif enregistré — confirmez avec votre médecin";
"conception.feedback.positive" = "Positif";
"conception.feedback.negative" = "Négatif";
"conception.feedback.dismiss" = "Masquer 7 jours";
"conception.bbt.title" = "Relever la température basale";
"conception.bbt.celsius" = "Température (°C)";
"conception.bbt.disturbances" = "Facteurs perturbateurs (optionnel)";
"conception.bbt.disturbance.late_night" = "Coucher tardif";
"conception.bbt.disturbance.alcohol" = "Alcool";
"conception.bbt.disturbance.illness" = "Maladie";
"conception.bbt.disturbance.insomnia" = "Insomnie";
"conception.bbt.measured_today" = "Mesurée ce matin ✓";
"conception.bbt.invalid" = "Saisissez une température entre 35,0 et 38,0";
"conception.bbt.entry" = "Saisir la température manuellement";
"conception.bbt.save" = "Enregistrer";
"conception.reminder.time" = "Rappel de prise de température";
"conception.reminder.body" = "C'est l'heure de prendre votre température";
"conception.reason.high_temp" = "Température élevée depuis %lld jours";
"conception.reason.period_late" = "Règles en retard de %lld jours";
"conception.reason.rhr" = "Fréquence au repos %lld bpm au-dessus de la base";
"conception.reason.hrv" = "HRV %lld%% sous la base";
"conception.reason.symptoms" = "%lld symptômes de début de grossesse";
```

- [ ] **Step 8: Build 确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```bash
git add Sources/Resources/
git commit -m "Add conception tracking localization strings for 7 languages"
```

---

### Task 6: 备孕模式开关（UserProfile 字段 + Settings 入口 + 一次性免责）

**Files:**
- Modify: `Sources/Core/Models/UserProfile.swift`（`UserProfile` 增加字段 + 自定义解码保持旧 JSON 兼容）
- Modify: `Sources/Core/UserProfileManager.swift`（追加 `setTryingToConceive`）
- Modify: `Sources/Features/Settings/SettingsView.swift`（新增备孕 Section）
- Test: `CycleAdvisorTests/ConceptionStoreTests.swift` 不动；新增 `CycleAdvisorTests/UserProfileConceptionTests.swift`

**Interfaces:**
- Produces:
  - `UserProfile.isTryingToConceive: Bool`（默认 false）
  - `UserProfileManager.setTryingToConceive(_ value: Bool)`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/UserProfileConceptionTests.swift`：

```swift
import XCTest
@testable import CycleAdvisor

/// 备孕模式开关：默认关闭；旧版 JSON（无该字段）解码兼容
final class UserProfileConceptionTests: XCTestCase {

    /// 默认关闭
    func testDefaultIsFalse() {
        XCTAssertFalse(UserProfile.empty.isTryingToConceive)
    }

    /// 旧版档案 JSON（无 isTryingToConceive 字段）解码不丢数据、默认 false
    func testLegacyJSONDecodesWithDefaultFalse() throws {
        let legacyJSON = """
        {
          "bodyInfo": {},
          "accumulatedStats": {
            "cycleLengths": [28, 29],
            "periodDurations": [5],
            "flowPatternByDay": {},
            "symptomFrequencies": {},
            "cyclesRecorded": 2,
            "version": 0
          },
          "workoutStats": {
            "topActivities": [],
            "weeklyFrequency": 0,
            "avgDurationMinutes": 0
          },
          "lifestyle": {
            "dietaryPreferences": [],
            "knownSensitivities": []
          },
          "knownConditions": [],
          "lastUpdated": 700000000,
          "version": 1
        }
        """
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(legacyJSON.utf8))
        XCTAssertFalse(profile.isTryingToConceive)
        XCTAssertEqual(profile.accumulatedStats.cycleLengths, [28, 29])
    }

    /// 开启后编码往返保留
    func testRoundTripPreservesFlag() throws {
        var profile = UserProfile.empty
        profile.isTryingToConceive = true
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertTrue(decoded.isTryingToConceive)
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/UserProfileConceptionTests 2>&1 | tail -5`
Expected: FAIL（编译错误，`isTryingToConceive` 不存在）

- [ ] **Step 3: UserProfile 增加字段 + 兼容解码**

`Sources/Core/Models/UserProfile.swift` 中 `UserProfile` 结构体：
1. 在 `var version: Int` 之前加字段：`var isTryingToConceive: Bool`（注释 `/// 备孕模式开关（默认 false）`）
2. `static let empty` 的构造调用中 `lastUpdated:` 之前加 `isTryingToConceive: false,`
3. 结构体内追加自定义解码（旧 JSON 无此字段时默认 false）：

```swift
    private enum CodingKeys: String, CodingKey {
        case bodyInfo, accumulatedStats, workoutStats, lifestyle
        case knownConditions, lastUpdated, version, isTryingToConceive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bodyInfo = try container.decode(BodyInfo.self, forKey: .bodyInfo)
        accumulatedStats = try container.decode(AccumulatedCycleStats.self, forKey: .accumulatedStats)
        workoutStats = try container.decode(WorkoutStats.self, forKey: .workoutStats)
        lifestyle = try container.decode(Lifestyle.self, forKey: .lifestyle)
        knownConditions = try container.decode([String].self, forKey: .knownConditions)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        version = try container.decode(Int.self, forKey: .version)
        isTryingToConceive = try container.decodeIfPresent(Bool.self, forKey: .isTryingToConceive) ?? false
    }
```

注意：自定义 `init(from:)` 后 `encode(to:)` 仍由编译器合成（有 CodingKeys 即可），成员wise init 保留不动。

- [ ] **Step 4: UserProfileManager 追加开关方法**

`Sources/Core/UserProfileManager.swift` 的 `// MARK: - Persistence` 一节中（`resetAll()` 之后）追加：

```swift
    /// 备孕模式开关；关闭时已有数据保留，仅停止提醒与提示
    func setTryingToConceive(_ value: Bool) {
        profile.isTryingToConceive = value
        save()
    }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/UserProfileConceptionTests 2>&1 | tail -5`
Expected: PASS（3 个测试）

- [ ] **Step 6: Settings 加入口**

`Sources/Features/Settings/SettingsView.swift`：

1. 顶部状态区追加：

```swift
    @AppStorage("hasShownConceptionOnboarding") private var hasShownConceptionOnboarding = false
    @AppStorage("conception.reminderTimeMinutes") private var reminderTimeMinutes = 420
    @State private var showConceptionOnboarding = false
    private var profileManager = UserProfileManager.shared
```

2. 追加两个 binding 计算属性：

```swift
    private var conceptionBinding: Binding<Bool> {
        Binding(
            get: { profileManager.profile.isTryingToConceive },
            set: { newValue in
                profileManager.setTryingToConceive(newValue)
                if newValue && !hasShownConceptionOnboarding {
                    showConceptionOnboarding = true
                }
            }
        )
    }

    /// 晨间提醒时间（UserDefaults 存"距午夜分钟数"，默认 7:00 = 420）
    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderTimeMinutes / 60,
                    minute: reminderTimeMinutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderTimeMinutes = (comps.hour ?? 7) * 60 + (comps.minute ?? 0)
            }
        )
    }
```

3. 在 AI Section（`} header: { Text("settings.section.ai") }` 整个 Section）之后追加：

```swift
            Section {
                Toggle(String(localized: "settings.conception.title"), isOn: conceptionBinding)
                    .tint(Theme.accent)

                if profileManager.profile.isTryingToConceive {
                    DatePicker(
                        String(localized: "conception.reminder.time"),
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }

                Text("settings.conception.hint")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .listRowSeparator(.hidden)
            } header: {
                Text("settings.section.conception")
            }
```

4. `body` 的 List 修饰符区域（`.navigationTitle(...)` 之前）追加一次性免责弹窗：

```swift
        .alert(String(localized: "conception.onboarding.title"), isPresented: $showConceptionOnboarding) {
            Button(String(localized: "conception.onboarding.ok")) {
                hasShownConceptionOnboarding = true
            }
        } message: {
            Text("conception.onboarding.body")
        }
```

提醒时间的实际重调度由 Task 8 的 `ConceptionInsightManager.refresh()` 触发；开关变更后下次进入首页即生效，本任务不直接调通知。

- [ ] **Step 7: Build 确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/Models/UserProfile.swift Sources/Core/UserProfileManager.swift Sources/Features/Settings/SettingsView.swift CycleAdvisorTests/UserProfileConceptionTests.swift
git commit -m "Add trying-to-conceive mode toggle with first-launch disclaimer"
```

---
### Task 7: 晨间提醒 ConceptionReminderScheduler

**Files:**
- Create: `Sources/Core/ConceptionReminderScheduler.swift`
- Test: `CycleAdvisorTests/ConceptionReminderSchedulerTests.swift`

**Interfaces:**
- Produces:
  - `enum ConceptionReminderScheduler`，`static let notificationID = "conception.morningReminder"`，`static let timeDefaultsKey = "conception.reminderTimeMinutes"`
  - `static func shouldSchedule(isTryingToConceive: Bool, hasWristCoverage: Bool) -> Bool`
  - `static func refresh(isTryingToConceive: Bool, hasWristCoverage: Bool)`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/ConceptionReminderSchedulerTests.swift`：

```swift
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
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/ConceptionReminderSchedulerTests 2>&1 | tail -5`
Expected: FAIL（编译错误）

- [ ] **Step 3: 实现 ConceptionReminderScheduler**

新建 `Sources/Core/ConceptionReminderScheduler.swift`：

```swift
import Foundation
import UserNotifications

/// 晨间测温提醒：仅对无手表腕温覆盖的备孕用户调度每日本地通知。
/// 文案避免在锁屏暴露敏感信息（"该测体温啦"而非"备孕提醒"）。
enum ConceptionReminderScheduler {

    static let notificationID = "conception.morningReminder"
    /// UserDefaults key：提醒时间（距午夜分钟数），默认 7:00 = 420
    static let timeDefaultsKey = "conception.reminderTimeMinutes"

    /// 备孕模式开启且近 3 天无腕温数据覆盖时才需要手动测温提醒
    static func shouldSchedule(isTryingToConceive: Bool, hasWristCoverage: Bool) -> Bool {
        isTryingToConceive && !hasWristCoverage
    }

    /// 重排提醒：先清后排，条件不满足时只清不排
    static func refresh(isTryingToConceive: Bool, hasWristCoverage: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard shouldSchedule(
            isTryingToConceive: isTryingToConceive,
            hasWristCoverage: hasWristCoverage
        ) else { return }

        let minutes = UserDefaults.standard.object(forKey: timeDefaultsKey) as? Int ?? 420
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60

        let content = UNMutableNotificationContent()
        content.body = String(localized: "conception.reminder.body")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(
            identifier: notificationID, content: content, trigger: trigger
        ))
    }
}
```

通知授权复用 App 启动时 `PeriodNotificationScheduler.requestAuthorization()`（`CycleAdvisorApp.swift:19` 已请求 `.alert, .sound`），本调度器不重复请求。

- [ ] **Step 4: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/ConceptionReminderSchedulerTests 2>&1 | tail -5`
Expected: PASS（3 个测试）

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ConceptionReminderScheduler.swift CycleAdvisorTests/ConceptionReminderSchedulerTests.swift
git commit -m "Add morning temperature reminder scheduler for manual-tracking users"
```

---

### Task 8: ConceptionInsightManager（协调器）

**Files:**
- Create: `Sources/Core/ConceptionInsightManager.swift`
- Modify: `Sources/Features/Home/HomeViewModel.swift`（`load()` 末尾挂刷新）

**Interfaces:**
- Consumes: 前面所有 Task 的 Store / Engine / HK fetchers / Scheduler
- Produces:
  - `@Observable final class ConceptionInsightManager`，`static let shared`
  - `private(set) var insight: PregnancyInsight`
  - `private(set) var recentTemperatures: [BasalTemperatureEntry]`（近 14 天，供迷你图）
  - `private(set) var hasWristCoverage: Bool`（近 3 天有腕温）
  - `private(set) var wristBaselineReady: Bool`（腕温 ≥ 14 天）
  - `@MainActor func refresh() async`
  - `@MainActor func recordPositive()` / `@MainActor func recordNegative()` / `@MainActor func dismissPrompt()`

协调器是胶水层（组装输入 → 跑引擎 → 发布状态），引擎逻辑已在 Task 3 覆盖单测；本 Task 以 build 通过为验收。

- [ ] **Step 1: 实现 ConceptionInsightManager**

新建 `Sources/Core/ConceptionInsightManager.swift`：

```swift
import Foundation

/// 备孕洞察协调器：汇集手表腕温 / 手动 BBT / 生命体征 / 症状 / 经期数据，
/// 运行 PregnancyInsightEngine 并发布结果给 UI。手表数据以 HealthKit 为唯一数据源，现读现算。
@Observable
final class ConceptionInsightManager {

    static let shared = ConceptionInsightManager()

    private(set) var insight: PregnancyInsight = .insufficient
    /// 近 14 天合并体温（供首页迷你趋势图）
    private(set) var recentTemperatures: [BasalTemperatureEntry] = []
    /// 近 3 天有手表腕温数据（决定是否需要晨间测温提醒）
    private(set) var hasWristCoverage = false
    /// 手表基线是否已建立（腕温数据 ≥ 14 天才参与判定）
    private(set) var wristBaselineReady = false

    private let healthKit = HealthKitManager.shared
    private let store = ConceptionStore.shared
    private let engine = PregnancyInsightEngine()
    private let phaseEngine = CyclePhaseEngine()
    private var lastPeriodStart: Date?

    private init() {}

    @MainActor
    func refresh() async {
        let isTryingToConceive = UserProfileManager.shared.profile.isTryingToConceive
        guard isTryingToConceive else {
            insight = .insufficient
            recentTemperatures = []
            hasWristCoverage = false
            ConceptionReminderScheduler.refresh(isTryingToConceive: false, hasWristCoverage: false)
            return
        }

        async let wristTask = healthKit.fetchWristTemperatureSeries(daysBack: 60)
        async let vitalsTask = healthKit.fetchDailyVitals(daysBack: 60)
        async let periodTask = healthKit.fetchLastPeriodStart()
        async let lengthTask = healthKit.fetchAverageCycleLength()
        async let hkSymptomsTask = healthKit.fetchPregnancySymptoms(daysBack: 60)

        let (wrist, vitals, periodStart, cycleLength, hkSymptoms) = await (
            wristTask, vitalsTask, periodTask, lengthTask, hkSymptomsTask
        )

        // HealthKit 症状并入统一症状库（去重由 store 保证）
        if !hkSymptoms.isEmpty {
            store.addSymptoms(hkSymptoms)
        }
        store.clearFeedbackIfNewPeriod(lastPeriodStart: periodStart)
        lastPeriodStart = periodStart

        // 手表基线未建立（佩戴 < 14 天）→ 腕温暂不参与判定，走手动 BBT 过渡
        wristBaselineReady = wrist.count >= 14
        let merged = store.mergedTemperatures(wrist: wristBaselineReady ? wrist : [])

        let expectedPeriod = periodStart.map {
            phaseEngine.nextPeriodDate(lastPeriodStart: $0, cycleLength: cycleLength)
        }

        insight = engine.evaluate(PregnancyInsightEngine.Input(
            temperatures: merged,
            vitals: vitals,
            symptoms: store.symptomRecords,
            lastPeriodStart: periodStart,
            expectedPeriodStart: expectedPeriod,
            referenceDate: Date(),
            testFeedback: store.testFeedback,
            dismissedUntil: store.dismissedUntil
        ))

        let calendar = Calendar.current
        let chartCutoff = calendar.date(byAdding: .day, value: -14, to: Date())!
        recentTemperatures = merged.filter { $0.date >= chartCutoff }

        let coverageCutoff = calendar.date(byAdding: .day, value: -3, to: Date())!
        hasWristCoverage = wrist.contains { $0.date >= coverageCutoff }
        ConceptionReminderScheduler.refresh(
            isTryingToConceive: true,
            hasWristCoverage: hasWristCoverage
        )
    }

    // MARK: - 验孕结果反馈

    @MainActor
    func recordPositive() {
        store.recordFeedback(.positive(date: Date()))
        Task { await refresh() }
    }

    @MainActor
    func recordNegative() {
        store.recordFeedback(.negative(date: Date(), cycleStart: lastPeriodStart))
        Task { await refresh() }
    }

    @MainActor
    func dismissPrompt() {
        store.dismissPrompt(forDays: 7)
        Task { await refresh() }
    }
}
```

- [ ] **Step 2: 挂到 HomeViewModel.load()**

`Sources/Features/Home/HomeViewModel.swift` 的 `load(force:)` 中，`loadSolarTerms()` 之后、`hasLoaded = true` 之前插入：

```swift
        // 备孕洞察刷新（未开启备孕模式时内部直接短路，代价极低）
        await ConceptionInsightManager.shared.refresh()
```

注意放在 `performHealthKitUpdate()` 之后：HealthKit 授权已完成，腕温/生命体征拉取才能拿到数据；授权被拒时各 fetcher 返回空数组，引擎自动走本地降级路径，不阻塞。

- [ ] **Step 3: Build 确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/ConceptionInsightManager.swift Sources/Features/Home/HomeViewModel.swift
git commit -m "Add conception insight coordinator wiring HealthKit, store, and engine"
```

---
### Task 9: 手动 BBT 录入页 BBTEntryView

**Files:**
- Create: `Sources/Features/Conception/BBTEntryView.swift`

**Interfaces:**
- Consumes: `ConceptionStore.upsertManualTemperature` / `manualEntry(for:)`；`Disturbance.displayName`
- Produces: `struct BBTEntryView: View`（Task 10 以 sheet 形式弹出）

UI 无单测，build 通过为验收。

- [ ] **Step 1: 实现 BBTEntryView**

新建 `Sources/Features/Conception/BBTEntryView.swift`：

```swift
import SwiftUI

/// 手动基础体温录入（无手表用户的主路径）：数字输入 + 干扰标记多选 + 今日已测状态
struct BBTEntryView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var celsiusText: String
    @State private var disturbances: Set<Disturbance>
    @State private var showInvalidAlert = false

    private let store = ConceptionStore.shared

    init() {
        // 已录过今日体温时预填，便于修改
        if let existing = ConceptionStore.shared.manualEntry(for: Date()) {
            _celsiusText = State(initialValue: String(format: "%.1f", existing.celsius))
            _disturbances = State(initialValue: existing.disturbances)
        } else {
            _celsiusText = State(initialValue: "")
            _disturbances = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("36.5", text: $celsiusText)
                        .keyboardType(.decimalPad)

                    if store.manualEntry(for: Date()) != nil {
                        Label(
                            String(localized: "conception.bbt.measured_today"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .font(.system(size: Theme.captionSize))
                        .foregroundStyle(Theme.accent)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("conception.bbt.celsius")
                }

                Section {
                    ForEach(Disturbance.allCases) { disturbance in
                        Toggle(disturbance.displayName, isOn: binding(for: disturbance))
                            .tint(Theme.accent)
                    }
                } header: {
                    Text("conception.bbt.disturbances")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(String(localized: "conception.bbt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "conception.bbt.save")) { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert(String(localized: "conception.bbt.invalid"), isPresented: $showInvalidAlert) {
                Button(String(localized: "conception.onboarding.ok")) {}
            }
        }
    }

    private func binding(for disturbance: Disturbance) -> Binding<Bool> {
        Binding(
            get: { disturbances.contains(disturbance) },
            set: { isOn in
                if isOn { disturbances.insert(disturbance) }
                else { disturbances.remove(disturbance) }
            }
        )
    }

    private func save() {
        // 兼容逗号小数点（部分语言键盘）
        let normalized = celsiusText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized),
              store.upsertManualTemperature(date: Date(), celsius: value, disturbances: disturbances)
        else {
            showInvalidAlert = true
            return
        }
        Task { await ConceptionInsightManager.shared.refresh() }
        dismiss()
    }
}

#Preview {
    BBTEntryView()
}
```

- [ ] **Step 2: Build 确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/Conception/BBTEntryView.swift
git commit -m "Add manual basal temperature entry view"
```

---

### Task 10: 首页备孕卡片 + HomeView 接入

**Files:**
- Create: `Sources/Features/Conception/TemperatureSparkline.swift`
- Create: `Sources/Features/Conception/ConceptionCardView.swift`
- Modify: `Sources/Features/Home/HomeView.swift`（VStack 中插入卡片 + 计算属性）

**Interfaces:**
- Consumes: `ConceptionInsightManager.shared`（insight / recentTemperatures / hasWristCoverage）、`ConceptionStore.shared.testFeedback`、`BBTEntryView`
- Produces: `struct ConceptionCardView: View`、`struct TemperatureSparkline: View`

- [ ] **Step 1: 实现 TemperatureSparkline**

新建 `Sources/Features/Conception/TemperatureSparkline.swift`：

```swift
import SwiftUI

/// 近 14 天体温迷你趋势图（纯线条，无坐标轴）
struct TemperatureSparkline: View {
    let entries: [BasalTemperatureEntry]

    var body: some View {
        GeometryReader { geo in
            let values = entries.map(\.celsius)
            let minValue = (values.min() ?? 36.0) - 0.05
            let maxValue = (values.max() ?? 37.0) + 0.05
            let range = max(maxValue - minValue, 0.01)

            Path { path in
                for (index, entry) in entries.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(entries.count - 1, 1))
                    let ratio = (entry.celsius - minValue) / range
                    let y = geo.size.height * (1 - CGFloat(ratio))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 2: 实现 ConceptionCardView**

新建 `Sources/Features/Conception/ConceptionCardView.swift`：

```swift
import SwiftUI

/// 首页备孕卡片：黄体期进度 / 验孕提示（possible / likely）+ 触发原因 + 反馈闭环。
/// 合规红线：文案只出现"可能怀孕 / 建议验孕确认"，永不出现"你已怀孕"。
struct ConceptionCardView: View {

    private var manager = ConceptionInsightManager.shared
    private var store = ConceptionStore.shared
    @State private var isBBTEntryPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if manager.recentTemperatures.count >= 2 {
                TemperatureSparkline(entries: manager.recentTemperatures)
                    .frame(height: 44)
            }

            content

            Text("conception.card.disclaimer")
                .font(.system(size: Theme.captionSize))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Theme.cardPadding)
        .grainCardStyle(seed: 701)
        .sheet(isPresented: $isBBTEntryPresented) {
            BBTEntryView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Label(String(localized: "conception.card.title"), systemImage: "heart.circle")
                .font(.system(size: Theme.cardTitleSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(String(localized: "conception.bbt.entry")) {
                isBBTEntryPresented = true
            }
            .font(.system(size: Theme.captionSize))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch manager.insight {
        case .insufficient:
            if case .positive = store.testFeedback {
                Text("conception.card.positive_recorded")
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("conception.card.insufficient")
                    .font(.system(size: Theme.bodySize))
                    .foregroundStyle(Theme.textSecondary)
            }

        case .tracking(let lutealDay):
            Text(String(format: String(localized: "conception.card.luteal_day"), lutealDay))
                .font(.system(size: Theme.bodySize, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

        case .possible(let reasons):
            promptBody(
                title: String(localized: "conception.card.possible"),
                reasons: reasons
            )

        case .likely(let reasons):
            promptBody(
                title: String(localized: "conception.card.likely"),
                reasons: reasons
            )
        }
    }

    private func promptBody(title: String, reasons: [InsightReason]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: Theme.bodySize, weight: .semibold))
                .foregroundStyle(Theme.accent)

            ForEach(reasons, id: \.self) { reason in
                Text("· \(reasonText(reason))")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 12) {
                Button(String(localized: "conception.feedback.positive")) {
                    manager.recordPositive()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button(String(localized: "conception.feedback.negative")) {
                    manager.recordNegative()
                }
                .buttonStyle(.bordered)

                Button(String(localized: "conception.feedback.dismiss")) {
                    manager.dismissPrompt()
                }
                .buttonStyle(.borderless)
                .font(.system(size: Theme.captionSize))
            }
            .font(.system(size: Theme.bodySize))
        }
    }

    private func reasonText(_ reason: InsightReason) -> String {
        switch reason {
        case .sustainedHighTemperature(let days):
            return String(format: String(localized: "conception.reason.high_temp"), days)
        case .periodLate(let days):
            return String(format: String(localized: "conception.reason.period_late"), days)
        case .elevatedRestingHeartRate(let delta):
            return String(format: String(localized: "conception.reason.rhr"), delta)
        case .suppressedHRV(let percent):
            return String(format: String(localized: "conception.reason.hrv"), percent)
        case .earlySymptoms(let count):
            return String(format: String(localized: "conception.reason.symptoms"), count)
        }
    }
}

#Preview {
    ConceptionCardView()
        .padding()
        .background(Theme.background)
}
```

- [ ] **Step 3: HomeView 接入**

`Sources/Features/Home/HomeView.swift`：

1. body 的 VStack 中，`periodSymptomsEntry` 之后插入一行：

```swift
                        conceptionEntry
```

2. `// MARK: - Period Symptoms Entry` 一节之前追加：

```swift
    // MARK: - Conception Tracking Entry

    /// 备孕卡片：仅备孕模式可见；关闭时不占布局
    @ViewBuilder
    private var conceptionEntry: some View {
        if UserProfileManager.shared.profile.isTryingToConceive {
            ConceptionCardView()
        }
    }
```

`UserProfileManager` 是 `@Observable`，body 中读取 `profile.isTryingToConceive` 即可让开关切换驱动卡片显隐，无需额外注入。

- [ ] **Step 4: Build 确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/Features/Conception/TemperatureSparkline.swift Sources/Features/Conception/ConceptionCardView.swift Sources/Features/Home/HomeView.swift
git commit -m "Add conception tracking card to home with prompt feedback loop"
```

---

### Task 11: SymptomExtractor（聊天症状抽取 + 挂钩）

**Files:**
- Modify: `Sources/Core/LLMService.swift`（追加 `extractSymptoms` + 解析函数 + 响应模型）
- Create: `Sources/Core/SymptomExtractor.swift`
- Modify: `Sources/Features/Assistant/AssistantViewModel.swift`（发送消息后异步触发）
- Test: `CycleAdvisorTests/SymptomExtractorTests.swift`

**Interfaces:**
- Produces:
  - `struct ExtractedSymptom: Equatable { type: PregnancySymptomType; dateRef: String? }`，含 `func record(now: Date = .now) -> SymptomRecord`
  - `LLMService.extractSymptoms(from message: String) async throws -> [ExtractedSymptom]`
  - `LLMService.parseExtractedSymptoms(from content: String) -> [ExtractedSymptom]`（nonisolated static，纯解析可单测）
  - `actor SymptomExtractor`，`static let shared`，`func extractAndStore(message: String) async`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/SymptomExtractorTests.swift`：

```swift
import XCTest
@testable import CycleAdvisor

/// 聊天症状抽取的响应解析：正常 JSON / 空数组 / 畸形 JSON / 未知类型过滤
final class SymptomExtractorTests: XCTestCase {

    /// 正常 JSON 解析
    func testParsesValidResponse() {
        let content = """
        {"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "fatigue", "date_ref": "yesterday"}]}
        """
        let result = LLMService.parseExtractedSymptoms(from: content)
        XCTAssertEqual(result, [
            ExtractedSymptom(type: .nausea, dateRef: "today"),
            ExtractedSymptom(type: .fatigue, dateRef: "yesterday"),
        ])
    }

    /// 空数组
    func testParsesEmptyArray() {
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: #"{"symptoms": []}"#), [])
    }

    /// 畸形 JSON → 空数组（不抛错）
    func testMalformedJSONYieldsEmpty() {
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: "not json at all"), [])
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: #"{"symptoms": "nope"}"#), [])
    }

    /// markdown 围栏与 think 块被清理
    func testCleansMarkdownFence() {
        let content = "```json\n{\"symptoms\": [{\"type\": \"headache\", \"date_ref\": null}]}\n```"
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: content),
                       [ExtractedSymptom(type: .headache, dateRef: nil)])
    }

    /// 未知症状类型被过滤，合法条目保留
    func testUnknownTypesFiltered() {
        let content = """
        {"symptoms": [{"type": "nausea", "date_ref": "today"}, {"type": "teleportation", "date_ref": null}]}
        """
        XCTAssertEqual(LLMService.parseExtractedSymptoms(from: content),
                       [ExtractedSymptom(type: .nausea, dateRef: "today")])
    }

    /// date_ref 映射：yesterday → 昨天；today/null → 今天；来源固定 chatExtracted
    func testDateRefMapping() {
        let now = Date()
        let today = ExtractedSymptom(type: .nausea, dateRef: "today").record(now: now)
        let yesterday = ExtractedSymptom(type: .nausea, dateRef: "yesterday").record(now: now)
        let nullRef = ExtractedSymptom(type: .nausea, dateRef: nil).record(now: now)

        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInToday(today.date))
        XCTAssertTrue(calendar.isDateInYesterday(yesterday.date))
        XCTAssertTrue(calendar.isDateInToday(nullRef.date))
        XCTAssertEqual(today.source, .chatExtracted)
    }
}
```

- [ ] **Step 2: 运行测试确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/SymptomExtractorTests 2>&1 | tail -5`
Expected: FAIL（编译错误）

- [ ] **Step 3: LLMService 追加 extractSymptoms**

`Sources/Core/LLMService.swift` 的 `extractProfileFields` 方法之后（`// MARK: - Token Estimation` 之前）追加：

```swift
    // MARK: - Symptom Extraction (备孕模式)

    private static let symptomExtractionMaxTokens = 300

    /// 从用户单条消息抽取早孕相关症状。独立请求，不侵入主聊天链路。
    func extractSymptoms(from message: String) async throws -> [ExtractedSymptom] {
        let request = LLMRequest(
            model: Self.utilityModelName,
            messages: [
                LLMMessage(role: "system", content: """
                从用户消息中抽取早孕相关症状。只抽取用户明确提到的症状，不要推测。
                输出 JSON：{"symptoms": [{"type": "<症状>", "date_ref": "today" | "yesterday" | null}]}
                type 只能是：nausea, vomiting, fatigue, breastTenderness, bloating, abdominalCramps, headache, spotting, appetiteChange, moodChange, dizziness
                没有提到任何症状时输出 {"symptoms": []}
                """),
                LLMMessage(role: "user", content: message)
            ],
            stream: false,
            temperature: 0,
            maxTokens: Self.symptomExtractionMaxTokens,
            responseFormat: .init(type: "json_object")
        )

        let response: LLMResponse = try await sendRequest(request, timeout: 15)
        guard let content = response.choices.first?.message?.content else {
            throw LLMError.emptyResponse
        }
        return Self.parseExtractedSymptoms(from: content)
    }

    /// 解析抽取响应；畸形 JSON / 未知类型一律容错为空数组
    nonisolated static func parseExtractedSymptoms(from content: String) -> [ExtractedSymptom] {
        let cleaned = cleanContent(content)
        guard let data = cleaned.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(SymptomExtractionResponse.self, from: data)
        else { return [] }
        return parsed.symptoms.compactMap { item in
            guard let type = PregnancySymptomType(rawValue: item.type) else { return nil }
            return ExtractedSymptom(type: type, dateRef: item.dateRef)
        }
    }
```

文件顶部 API Types 区域（`struct LLMTokenUsage` 之前）追加：

```swift
/// 聊天症状抽取结果（备孕模式）
struct ExtractedSymptom: Equatable {
    let type: PregnancySymptomType
    /// "today" / "yesterday" / nil（视为 today）
    let dateRef: String?

    /// 转换为症状库记录，来源固定 chatExtracted
    func record(now: Date = .now) -> SymptomRecord {
        let day: Date
        if dateRef == "yesterday" {
            day = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        } else {
            day = now
        }
        return SymptomRecord(
            date: Calendar.current.startOfDay(for: day),
            type: type,
            source: .chatExtracted
        )
    }
}

private struct SymptomExtractionResponse: Decodable {
    struct Item: Decodable {
        let type: String
        let dateRef: String?

        enum CodingKeys: String, CodingKey {
            case type
            case dateRef = "date_ref"
        }
    }
    let symptoms: [Item]
}
```

- [ ] **Step 4: 实现 SymptomExtractor（节流 + 写入）**

新建 `Sources/Core/SymptomExtractor.swift`：

```swift
import Foundation

/// 聊天症状抽取协调：节流 → 调 LLMService → 写入症状库。
/// 失败静默，不影响聊天主链路，不重试（下条消息自然带来新机会）。
actor SymptomExtractor {

    static let shared = SymptomExtractor()

    private let defaultsKeyPrefix = "conception.extracted."

    private init() {}

    func extractAndStore(message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4 else { return }

        // 同日已抽取过的消息不重复请求
        let dayKey = Self.dayKey(for: Date())
        let defaultsKey = defaultsKeyPrefix + dayKey
        var extracted = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        guard !extracted.contains(trimmed) else { return }
        extracted.append(trimmed)
        UserDefaults.standard.set(extracted, forKey: defaultsKey)

        do {
            let symptoms = try await LLMService.shared.extractSymptoms(from: trimmed)
            let records = symptoms.map { $0.record() }
            if !records.isEmpty {
                ConceptionStore.shared.addSymptoms(records)
            }
        } catch {
            // 静默丢弃：网络失败 / 解析失败都不影响聊天
        }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/SymptomExtractorTests 2>&1 | tail -5`
Expected: PASS（6 个测试）

- [ ] **Step 6: AssistantViewModel 挂钩**

`Sources/Features/Assistant/AssistantViewModel.swift` 的 `sendMessage` 中，用户消息入列（`messages.append(ChatMessage(role: .user, ...))`，约 98 行）之后插入：

```swift
        // 备孕模式：异步抽取用户消息中的早孕症状（fire-and-forget，静默失败，不阻塞对话）
        if UserProfileManager.shared.profile.isTryingToConceive {
            let capturedMessage = trimmed
            Task {
                await SymptomExtractor.shared.extractAndStore(message: capturedMessage)
            }
        }
```

注意放在流式调用之前：只依赖用户消息本身，不等助手回复；只抽取用户消息，不抽取助手回复。

- [ ] **Step 7: 全量测试 + Build 确认无回归**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests 2>&1 | tail -5`
Expected: PASS（全部测试）

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/LLMService.swift Sources/Core/SymptomExtractor.swift Sources/Features/Assistant/AssistantViewModel.swift CycleAdvisorTests/SymptomExtractorTests.swift
git commit -m "Add chat symptom extraction for conception tracking"
```

---

## 完成后人工验证清单（模拟器/真机）

- [ ] 设置页开启备孕模式 → 首次弹出免责说明；首页出现备孕卡片
- [ ] 卡片点击"手动录入体温" → 录入 36.5 保存；再次打开显示"今早已测 ✓"
- [ ] 录入 34.0 → 弹出范围错误提示
- [ ] 关闭备孕模式 → 卡片消失；重开 → 数据保留
- [ ] 无手表数据时 → 晨间提醒按设置时间触发（可在设置里改时间验证）
- [ ] 切换系统语言（如 English）→ 卡片/录入页文案跟随
