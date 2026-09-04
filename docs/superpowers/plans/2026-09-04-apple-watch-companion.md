# Apple Watch 配套 + 经期预测 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CycleAdvisor 增加 watchOS 配套 app（周期速览 + 运动完成插图庆祝），并在 iPhone 端主页周期模块显示月经预测、新增经期预测本地通知。

**Architecture:** 所有健康数据从各端本地 HealthKit store 读取（iPhone 与 Watch 零自建同步通道）；运动类型→插图映射从 `WorkoutDashboardView` 抽为共享代码；预测逻辑复用现有 `CyclePhaseEngine`；通知全部为本地通知。

**Tech Stack:** SwiftUI、HealthKit（`HKObserverQuery`）、UserNotifications、WidgetKit（watchOS complication）、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-04-apple-watch-companion-design.md`

## Global Constraints

- 所有面向用户的文案必须进 7 个 lproj：zh-Hans、zh-Hant、en、ja、ko、es、fr（`Sources/Resources/*.lproj/Localizable.strings`，格式 `"key" = "value";`）
- App 锁定浅色模式（`.preferredColorScheme(.light)`），视觉遵循暖色纸质主题（`Theme.warmShell` / `Theme.textSecondary` / `Theme.captionSize`）
- 本机 xcode-select 指向 CommandLineTools，**所有 xcodebuild 命令必须加前缀** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- 项目路径：`/Users/lufi/Documents/Claude/Projects/cycle_advisor-main`
- 运动庆祝延迟固定为 **1 分钟**（spec §2.3）
- 不做 WatchConnectivity、不做 HKWorkoutSession、不做周/月最爱运动通知
- 测试进现有 `CycleAdvisorTests` target（XCTest，`@testable import CycleAdvisor`，注释用中文）
- 每个 Task 结束必须 build 通过 + commit；commit message 英文单行摘要

---

### Task 1: 抽取 WorkoutPosterMapper（纯重构，iPhone 行为不变）

**Files:**
- Create: `Sources/Shared/WorkoutPosterMapper.swift`
- Modify: `Sources/Features/Profile/WorkoutDashboardView.swift`（删除 fileprivate `WorkoutActivityKind`（1017–1030 行）、`workoutActivityKind(for:)`（928–971 行）、`WorkoutPosterArtView.posterAssetName`（1140–1184 行），改为调用共享实现）
- Modify: `Sources/Core/HealthKitManager.swift`（新增静态方法）
- Test: `CycleAdvisorTests/WorkoutPosterMapperTests.swift`

**Interfaces:**
- Produces（后续所有 Task 依赖这三个签名）:
  - `enum WorkoutActivityKind { climbing, walking, running, yoga, cycling, swimming, strength, flexibility, dance, ballSports, cardio, other }`
  - `WorkoutPosterMapper.kind(key: String, name: String) -> WorkoutActivityKind`
  - `WorkoutPosterMapper.posterAssetName(kind: WorkoutActivityKind, key: String?) -> String?`
  - `WorkoutPosterMapper.celebrationAssetName(key: String, name: String) -> String`（未覆盖时返回 `"WorkoutPosterPark"`）
  - `HealthKitManager.workoutKey(for: HKWorkoutActivityType) -> String`

- [ ] **Step 1: 写失败测试**

新建 `CycleAdvisorTests/WorkoutPosterMapperTests.swift`：

```swift
import XCTest
@testable import CycleAdvisor

/// 运动类型 → 插图映射：具体 key 优先，其次运动大类，庆祝场景必须有图（park 兜底）
final class WorkoutPosterMapperTests: XCTestCase {

    func testSpecificKeyWins() {
        // table_tennis 属于 ballSports 大类，但有专属网球插图时按 key 走
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .ballSports, key: "badminton"), "WorkoutPosterBadminton")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .ballSports, key: "pickleball"), "WorkoutPosterPickleball")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .yoga, key: "barre"), "WorkoutPosterBarre")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: "surfing_sports"), "WorkoutPosterSurfing")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: "underwater_diving"), "WorkoutPosterDiving")
    }

    func testKindFallback() {
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .running, key: nil), "WorkoutPosterRunning")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .walking, key: nil), "WorkoutPosterWalk")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .climbing, key: nil), "WorkoutPosterBouldering")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .yoga, key: nil), "WorkoutPosterYoga")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .strength, key: nil), "WorkoutPosterStrength")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .cycling, key: nil), "WorkoutPosterCycling")
        XCTAssertEqual(WorkoutPosterMapper.posterAssetName(kind: .swimming, key: nil), "WorkoutPosterSwimming")
        // 无专属图的大类返回 nil（iPhone 端走自绘插画兜底）
        XCTAssertNil(WorkoutPosterMapper.posterAssetName(kind: .cardio, key: nil))
        XCTAssertNil(WorkoutPosterMapper.posterAssetName(kind: .other, key: nil))
    }

    func testKindInference() {
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "hiking", name: "徒步"), .walking)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "mind_and_body", name: "身心"), .yoga)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "table_tennis", name: "乒乓球"), .ballSports)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "jump_rope", name: "跳绳"), .cardio)
        // 未知 key 走名称关键词
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "unknown_999", name: "攀岩"), .climbing)
        XCTAssertEqual(WorkoutPosterMapper.kind(key: "unknown_998", name: "Frisbee"), .other)
    }

    func testCelebrationAlwaysHasPoster() {
        XCTAssertEqual(WorkoutPosterMapper.celebrationAssetName(key: "running", name: "跑步"), "WorkoutPosterRunning")
        // 未覆盖类型兜底 park
        XCTAssertEqual(WorkoutPosterMapper.celebrationAssetName(key: "unknown_999", name: "Frisbee"), "WorkoutPosterPark")
    }

    func testWorkoutKeyFromActivityType() {
        XCTAssertEqual(HealthKitManager.workoutKey(for: .running), "running")
        XCTAssertEqual(HealthKitManager.workoutKey(for: .badminton), "badminton")
        XCTAssertEqual(HealthKitManager.workoutKey(for: .tableTennis), "table_tennis")
    }
}
```

- [ ] **Step 2: 确认编译失败**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/WorkoutPosterMapperTests 2>&1 | tail -5`
Expected: 编译错误，`WorkoutPosterMapper` 未定义

- [ ] **Step 3: 创建共享实现**

新建 `Sources/Shared/WorkoutPosterMapper.swift`。`WorkoutActivityKind` 的 case 与 `WorkoutDashboardView.swift` 1017–1030 行完全一致；`kind(key:name:)` 的 switch + 关键词 fallback 逻辑原样搬自 `workoutActivityKind(for:)`（928–971 行），签名改为：

```swift
import Foundation

/// 运动大类（从 WorkoutDashboardView 抽出，iPhone / Watch 共用）
enum WorkoutActivityKind {
    case climbing, walking, running, yoga, cycling, swimming
    case strength, flexibility, dance, ballSports, cardio, other
}

/// 运动类型 → 插图 asset 名映射（iPhone dashboard 与 Watch 庆祝共用）
enum WorkoutPosterMapper {
    static func kind(key: String, name: String) -> WorkoutActivityKind {
        // 原样搬运 WorkoutDashboardView.workoutActivityKind(for:) 的全部逻辑，
        // 其中 activity.key → 参数 key，activity.name → 参数 name
    }

    static func posterAssetName(kind: WorkoutActivityKind, key: String?) -> String? {
        // 原样搬运 WorkoutPosterArtView.posterAssetName(kind:key:) 的全部逻辑
    }

    /// 庆祝页必须出图：未覆盖类型用 park 兜底（spec §2.3）
    static func celebrationAssetName(key: String, name: String) -> String {
        posterAssetName(kind: self.kind(key: key, name: name), key: key) ?? "WorkoutPosterPark"
    }
}
```

在 `HealthKitManager.swift` 的 `workoutDescriptor(for:)` 附近新增：

```swift
/// 供 Watch 端使用：HKWorkoutActivityType → 内部运动 key（与统计同一映射表）
static func workoutKey(for type: HKWorkoutActivityType) -> String {
    if let known = knownWorkoutActivities[type.rawValue] { return known.key }
    return "unknown_\(type.rawValue)"
}
```

- [ ] **Step 4: 改造 WorkoutDashboardView 调用共享实现**

- 删除 fileprivate `WorkoutActivityKind` 枚举（1017–1030 行）
- 删除 `workoutActivityKind(for:)`（928–971 行），调用处改为 `WorkoutPosterMapper.kind(key: activity.key, name: activity.name)`
- 删除 `WorkoutPosterArtView.posterAssetName(kind:key:)`（1140–1184 行），`body` 内的 `Self.posterAssetName(kind:key:)` 改为 `WorkoutPosterMapper.posterAssetName(kind: key:)`
- 其余视图代码（自绘插画等）一律不动

- [ ] **Step 5: 测试通过 + 构建通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests 2>&1 | tail -5`
Expected: 全部 PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/Shared/WorkoutPosterMapper.swift Sources/Features/Profile/WorkoutDashboardView.swift Sources/Core/HealthKitManager.swift CycleAdvisorTests/WorkoutPosterMapperTests.swift
git commit -m "Extract workout-to-poster mapping into shared WorkoutPosterMapper"
```

---

### Task 2: PeriodPrediction 纯模型

**Files:**
- Create: `Sources/Core/Models/PeriodPrediction.swift`
- Test: `CycleAdvisorTests/PeriodPredictionTests.swift`

**Interfaces:**
- Consumes: 无（纯函数）
- Produces:
  - `struct PeriodPrediction: Equatable`，含 `enum State: Equatable { upcoming(days: Int), today, inPeriod(day: Int), overdue(days: Int) }`
  - `PeriodPrediction.make(lastPeriodStart: Date, cycleLength: Int, isInPeriod: Bool, periodDay: Int, today: Date = .now, calendar: Calendar = .current) -> PeriodPrediction`
  - `prediction.predictedDate: Date`、`prediction.state: State`
  - `prediction.text: String`（本地化一行文案）
  - `PeriodPrediction.dateText(_ date: Date) -> String`（按当前 Locale 的 "9月12日" 格式）

- [ ] **Step 1: 写失败测试**

```swift
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
        // 1月30日 + 周期28天 → 预测落在2月，跨年/月不偏移
        var comps = DateComponents(); comps.year = 2026; comps.month = 1; comps.day = 30
        let last = calendar.date(from: comps)!
        comps.day = 31
        let today = calendar.date(from: comps)!
        let p = PeriodPrediction.make(lastPeriodStart: last, cycleLength: 28,
                                      isInPeriod: false, periodDay: 2, today: today)
        XCTAssertEqual(p.state, .upcoming(days: 25))
        let predictedComps = calendar.dateComponents([.month, .day], from: p.predictedDate)
        XCTAssertEqual(predictedComps.month, 2)
        XCTAssertEqual(predictedComps.day, 25)
    }
}
```

- [ ] **Step 2: 确认编译失败**（同上 xcodebuild test，只跑 PeriodPredictionTests）

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 经期预测：上次经期开始日 + 平均周期长度推算。纯函数，无 HealthKit 依赖，iPhone / Watch 共用。
struct PeriodPrediction: Equatable {
    enum State: Equatable {
        case upcoming(days: Int)   // 还有 X 天
        case today                 // 预计今天来潮
        case inPeriod(day: Int)    // 经期第 X 天
        case overdue(days: Int)    // 可能推迟了 X 天
    }

    let predictedDate: Date
    let state: State

    static func make(lastPeriodStart: Date, cycleLength: Int, isInPeriod: Bool, periodDay: Int,
                     today: Date = .now, calendar: Calendar = .current) -> PeriodPrediction {
        let nextStart = calendar.date(byAdding: .day, value: cycleLength, to: lastPeriodStart)!
        let startToday = calendar.startOfDay(for: today)
        let startNext = calendar.startOfDay(for: nextStart)
        let diff = calendar.dateComponents([.day], from: startToday, to: startNext).day ?? 0

        let state: State
        if isInPeriod {
            state = .inPeriod(day: max(1, periodDay))
        } else if diff > 0 {
            state = .upcoming(days: diff)
        } else if diff == 0 {
            state = .today
        } else {
            state = .overdue(days: -diff)
        }
        return PeriodPrediction(predictedDate: startNext, state: state)
    }

    /// 按当前 Locale 格式化预测日期（如 "9月12日" / "Sep 12"）
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    /// 主页周期模块与 Watch 速览共用的一行文案
    var text: String {
        switch state {
        case .upcoming(let days):
            return String(format: String(localized: "home.prediction.upcoming %@ %lld"),
                          Self.dateText(predictedDate), Int64(days))
        case .today:
            return String(localized: "home.prediction.today")
        case .inPeriod(let day):
            return String(format: String(localized: "home.prediction.in_period %lld"), Int64(day))
        case .overdue(let days):
            return String(format: String(localized: "home.prediction.overdue %lld"), Int64(days))
        }
    }
}
```

- [ ] **Step 4: 测试通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/PeriodPredictionTests 2>&1 | tail -5`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/PeriodPrediction.swift CycleAdvisorTests/PeriodPredictionTests.swift
git commit -m "Add PeriodPrediction pure model for period forecast states"
```

---

### Task 3: 主页周期模块显示预测 + 7 语言文案

**Files:**
- Modify: `Sources/Features/Home/HomeViewModel.swift`（新增计算属性）
- Modify: `Sources/Features/Home/HomeView.swift:184-222`（`cycleStageHeader` 内加预测行）
- Modify: `Sources/Resources/*.lproj/Localizable.strings`（7 个文件都加同样 key）

**Interfaces:**
- Consumes: Task 2 的 `PeriodPrediction`
- Produces: `HomeViewModel.periodPrediction: PeriodPrediction?`；本地化 key `home.prediction.upcoming/today/in_period/overdue`

- [ ] **Step 1: HomeViewModel 新增计算属性**

`lastPeriodStart` / `lastCycleLength` 已是私有存储属性（35 行附近），新增：

```swift
/// 经期预测（主页周期模块与通知调度共用）
var periodPrediction: PeriodPrediction? {
    guard let lastPeriodStart, let lastCycleLength else { return nil }
    return PeriodPrediction.make(
        lastPeriodStart: lastPeriodStart,
        cycleLength: lastCycleLength,
        isInPeriod: context.phase == .menstrual && !context.isPredicted,
        periodDay: context.cycleDay
    )
}
```

- [ ] **Step 2: cycleStageHeader 加预测行**

`Sources/Features/Home/HomeView.swift` 的 `cycleStageHeader`（184–222 行），在阶段名 HStack（193–199 行）之后、`CycleTrackingTimelineView` 之前插入：

```swift
if inspectedPhase == nil, let prediction = viewModel.periodPrediction {
    Text(prediction.text)
        .font(Theme.itim(size: 14))
        .foregroundStyle(homeMutedText)
}
```

- [ ] **Step 3: 7 语言文案**

7 个 `Localizable.strings` 都追加（注意格式串参数顺序全部按 `%@ %lld`）：

```
/* Home prediction */
"home.prediction.upcoming %@ %lld" = "预计 %@ · 还有 %lld 天";          // zh-Hans
"home.prediction.today" = "预计今天来潮";
"home.prediction.in_period %lld" = "经期第 %lld 天";
"home.prediction.overdue %lld" = "可能推迟了 %lld 天";
```

其余 6 语言同一组 key：
- zh-Hant: `預計 %@ · 還有 %lld 天` / `預計今天來潮` / `經期第 %lld 天` / `可能推遲了 %lld 天`
- en: `Expected %@ · in %lld days` / `Expected today` / `Period day %lld` / `May be %lld days late`
- ja: `予定日 %@ · あと %lld 日` / `今日が予定日です` / `生理 %lld 日目` / `%lld 日遅れている可能性があります`
- ko: `예정일 %@ · %lld일 남음` / `오늘이 예정일입니다` / `생리 %lld일차` / `%lld일 늦어질 수 있습니다`
- es: `Previsto: %@ · faltan %lld días` / `Previsto para hoy` / `Día %lld del periodo` / `Podría retrasarse %lld días`
- fr: `Prévu le %@ · dans %lld jours` / `Prévu aujourd'hui` / `Jour %lld des règles` / `Retard possible de %lld jours`

- [ ] **Step 4: 构建通过**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Sources/Features/Home/HomeViewModel.swift Sources/Features/Home/HomeView.swift Sources/Resources/
git commit -m "Show period prediction (date and countdown) in home cycle module"
```

---

### Task 4: 经期预测本地通知

**Files:**
- Create: `Sources/Core/PeriodNotificationScheduler.swift`
- Modify: `Sources/Features/Home/HomeViewModel.swift`（`performHealthKitUpdate()` 内挂钩）
- Modify: `Sources/CycleAdvisorApp.swift`（init 里请求通知权限）
- Modify: `Sources/Resources/*.lproj/Localizable.strings`（7 个）
- Test: `CycleAdvisorTests/PeriodNotificationSchedulerTests.swift`

**Interfaces:**
- Consumes: Task 2 的 `PeriodPrediction.dateText(_:)`
- Produces:
  - `PeriodNotificationScheduler.reminderID / dayOfID: String`
  - `PeriodNotificationScheduler.scheduleDates(predictedDate: Date, now: Date, calendar: Calendar) -> [(id: String, date: Date)]`（纯函数）
  - `PeriodNotificationScheduler.requestAuthorization()`
  - `PeriodNotificationScheduler.reschedule(predictedDate: Date?) async`

- [ ] **Step 1: 写失败测试**

```swift
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
```

- [ ] **Step 2: 确认编译失败**

- [ ] **Step 3: 实现 PeriodNotificationScheduler**

```swift
import Foundation
import UserNotifications

/// 经期预测本地通知（spec §2.5）：预测日前 2 天 9:00「可以提前准备了」+ 当天 9:00。
/// 每次主页 HealthKit 刷新后调用 reschedule：预测日期是确定值，内容不会过期；
/// 经期实际来临后新的 periodStart 会让预测日移到下一周期，旧通知自然被重排掉。
enum PeriodNotificationScheduler {
    static let reminderID = "period.prediction.reminder"
    static let dayOfID = "period.prediction.dayof"

    static func scheduleDates(predictedDate: Date, now: Date = .now,
                              calendar: Calendar = .current) -> [(id: String, date: Date)] {
        func atNine(_ day: Date) -> Date? {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
        var result: [(id: String, date: Date)] = []
        if let twoDaysBefore = calendar.date(byAdding: .day, value: -2, to: predictedDate),
           let fire = atNine(twoDaysBefore), fire > now {
            result.append((reminderID, fire))
        }
        if let fire = atNine(predictedDate), fire > now {
            result.append((dayOfID, fire))
        }
        return result
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func reschedule(predictedDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID, dayOfID])
        guard let predictedDate else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return } // 拒绝则静默关闭

        for (id, date) in scheduleDates(predictedDate: predictedDate) {
            let content = UNMutableNotificationContent()
            if id == reminderID {
                content.title = String(localized: "notify.period.reminder.title")
                content.body = String(format: String(localized: "notify.period.reminder.body %@"),
                                      PeriodPrediction.dateText(predictedDate))
            } else {
                content.title = String(localized: "notify.period.dayof.title")
                content.body = String(localized: "notify.period.dayof.body")
            }
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
```

- [ ] **Step 4: 挂钩 HomeViewModel + App init**

`HomeViewModel.performHealthKitUpdate()` 在 `if let periodStart` 分支内、`context = ...` 之后加：

```swift
let prediction = PeriodPrediction.make(
    lastPeriodStart: periodStart,
    cycleLength: cycleLength,
    isInPeriod: base.phase == .menstrual && !base.isPredicted,
    periodDay: base.cycleDay
)
await PeriodNotificationScheduler.reschedule(predictedDate: prediction.predictedDate)
```

`else` 分支（无经期数据）加：`await PeriodNotificationScheduler.reschedule(predictedDate: nil)`

`CycleAdvisorApp.init()` 末尾加：`PeriodNotificationScheduler.requestAuthorization()`

- [ ] **Step 5: 7 语言通知文案**

```
/* Period prediction notification */
"notify.period.reminder.title" = "经期预告";                                   // zh-Hans
"notify.period.reminder.body %@" = "预计 %@ 来潮，可以提前准备啦";
"notify.period.dayof.title" = "今天可能是经期第一天";
"notify.period.dayof.body" = "留意身体信号，今天对自己温柔一点";
```

- zh-Hant: `經期預告` / `預計 %@ 來潮，可以提前準備啦` / `今天可能是經期第一天` / `留意身體信號，今天對自己溫柔一點`
- en: `Period coming up` / `Expected %@ — time to prepare` / `Your period may start today` / `Listen to your body and take it easy today`
- ja: `生理予定のお知らせ` / `%@ の予定です。早めに準備を` / `今日が生理予定日かもしれません` / `体のサインに気をつけて、今日はやさしく過ごしましょう`
- ko: `생리 예정 알림` / `%@ 예정입니다. 미리 준비하세요` / `오늘 생리가 시작될 수 있습니다` / `몸의 신호에 귀 기울이며 오늘은 편하게 보내세요`
- es: `Periodo próximo` / `Previsto para el %@ — prepárate con tiempo` / `Tu periodo podría empezar hoy` / `Escucha a tu cuerpo y tómate el día con calma`
- fr: `Règles à venir` / `Prévu le %@ — prépare-toi à l'avance` / `Tes règles pourraient arriver aujourd'hui` / `Écoute ton corps et ménage-toi aujourd'hui`

- [ ] **Step 6: 测试通过 + 构建通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests 2>&1 | tail -5
git add Sources/Core/PeriodNotificationScheduler.swift Sources/Features/Home/HomeViewModel.swift Sources/CycleAdvisorApp.swift Sources/Resources/ CycleAdvisorTests/PeriodNotificationSchedulerTests.swift
git commit -m "Add local period prediction notifications (2 days before and day-of)"
```

---

### Task 5: 创建 watchOS target（手动 Xcode 步骤 + 共享文件编入）

**这一步必须在 Xcode GUI 里做**（pbxproj 手术易出错），执行者严格按步骤来：

- [ ] **Step 1: Xcode 新建 target**

1. 打开 `CycleAdvisor.xcodeproj`
2. File → New → Target… → watchOS 标签 → **Watch App** → Next
3. Product Name: `CycleAdvisorWatch`；Language: Swift；**Include Complication: 勾选**（会同时建 WidgetKit extension target `CycleAdvisorWatchComplication`）；Embed in Companion App: `CycleAdvisor`
4. 若模板询问激活 scheme → Activate
5. 在 `CycleAdvisorWatch` target 的 Signing & Capabilities：+ Capability → **HealthKit**
6. General → Deployment Target: **watchOS 10.0**
7. 模板生成的 `ContentView.swift` 保留占位即可，Task 6 替换

- [ ] **Step 2: 共享文件编入 Watch target**

逐个文件在 File Inspector（右侧面板）的 Target Membership 勾选 `CycleAdvisorWatch`：

- `Sources/Shared/Theme.swift`
- `Sources/Core/Models/CyclePhase.swift`
- `Sources/Core/Models/PeriodPrediction.swift`
- `Sources/Core/CyclePhaseEngine.swift`
- `Sources/Shared/WorkoutPosterMapper.swift`
- `Sources/Core/HealthKitManager.swift`
- `Sources/Core/Models/UserProfile.swift`
- `Sources/Core/Models/MenstrualSymptoms.swift`

构建后若报缺类型，按编译错误提示把对应 Model 文件也勾上（`HealthKitManager` 依赖 `WorkoutStats`/`HealthMetrics` 等）。**不要**勾选任何 import UIKit / LLMService / StoreKit 的文件。

Complication extension target（`CycleAdvisorWatchComplication`）勾选：
- `Sources/Core/Models/CyclePhase.swift`、`Sources/Core/CyclePhaseEngine.swift`、`Sources/Core/HealthKitManager.swift` 及其编译依赖
- 该 target 也加 **HealthKit** capability

- [ ] **Step 3: 验证构建**

先查可用 watch 模拟器：
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -showdestinations 2>&1 | grep -i watch | head -5
```
然后构建（destination 用上一步看到的设备名）：
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add CycleAdvisor.xcodeproj CycleAdvisorWatch CycleAdvisorWatchComplication
git commit -m "Add watchOS app and complication targets with shared model files"
```

---

### Task 6: Watch 周期速览 UI

**Files:**
- Create: `CycleAdvisorWatch/WatchCycleViewModel.swift`
- Create: `CycleAdvisorWatch/WatchHomeView.swift`（替换模板 ContentView）
- Modify: `CycleAdvisorWatch/CycleAdvisorWatchApp.swift`（模板入口指向 WatchHomeView）
- Modify: `Sources/Resources/*.lproj/Localizable.strings`（7 个）

**Interfaces:**
- Consumes: `HealthKitManager.shared.fetchLastPeriodStart()/fetchAverageCycleLength()`、`CyclePhaseEngine().determinePhase(lastPeriodStart:cycleLength:)`（返回 `(phase, dayInPhase, cycleDay, avgCycleLength, isPredicted)` 命名元组）、Task 2 的 `PeriodPrediction`
- Produces: `WatchCycleViewModel`（`context: CycleContext?`、`prediction: PeriodPrediction?`、`load() async`）

- [ ] **Step 1: WatchCycleViewModel**

```swift
import Foundation
import SwiftUI

/// Watch 端周期数据：直接读手表本地 HealthKit（经期数据经 iCloud 健康同步到手表），
/// 无 WatchConnectivity（spec §4.1）。
@Observable
final class WatchCycleViewModel {
    private(set) var context: CycleContext?
    private(set) var prediction: PeriodPrediction?
    private(set) var hasNoData = false

    func load() async {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAvailable else { hasNoData = true; return }
        try? await healthKit.requestAuthorization()

        async let periodStartTask = healthKit.fetchLastPeriodStart()
        async let cycleLengthTask = healthKit.fetchAverageCycleLength()
        guard let lastPeriodStart = await periodStartTask else {
            hasNoData = true
            return
        }
        let cycleLength = await cycleLengthTask
        let base = CyclePhaseEngine().determinePhase(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        let isInPeriod = base.phase == .menstrual && !base.isPredicted
        context = CycleContext(
            phase: base.phase,
            dayInPhase: base.dayInPhase,
            cycleDay: base.cycleDay,
            avgCycleLength: base.avgCycleLength,
            healthMetrics: .empty,
            isPredicted: base.isPredicted
        )
        prediction = PeriodPrediction.make(
            lastPeriodStart: lastPeriodStart,
            cycleLength: cycleLength,
            isInPeriod: isInPeriod,
            periodDay: base.cycleDay
        )
    }
}
```

- [ ] **Step 2: WatchHomeView**

```swift
import SwiftUI

/// Watch 速览（spec §2.1）：周期进度环 + 当前阶段 + 预测经期日期/倒计时。
struct WatchHomeView: View {
    @State private var viewModel = WatchCycleViewModel()

    var body: some View {
        Group {
            if let context = viewModel.context {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(context.phase.color.opacity(0.25), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: min(1, context.cycleProgress))
                            .stroke(context.phase.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text(context.phase.emoji)
                                .font(.system(size: 20))
                            Text("\(context.cycleDay)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    Text(context.phase.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let prediction = viewModel.prediction {
                        Text(prediction.text)
                            .font(.system(size: Theme.captionSize))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            } else if viewModel.hasNoData {
                Text("watch.no_data")
                    .font(.system(size: Theme.captionSize))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .containerBackground(Theme.warmShell, for: .navigation)
        .task { await viewModel.load() }
    }
}
```

`CycleAdvisorWatchApp.swift` 入口 body 改为 `WindowGroup { WatchHomeView() }`。

- [ ] **Step 3: 7 语言 watch key**

```
/* Watch */
"watch.no_data" = "在 iPhone 健康 app 记录经期后开始预测";   // zh-Hans
```
- zh-Hant: `在 iPhone 健康 app 記錄經期後開始預測`
- en: `Log your period in the Health app on iPhone to start predictions`
- ja: `iPhone のヘルスケア app で生理を記録すると予測が始まります`
- ko: `iPhone의 건강 app에서 생리를 기록하면 예측이 시작됩니다`
- es: `Registra tu periodo en la app Salud del iPhone para ver predicciones`
- fr: `Enregistre tes règles dans l'app Santé de l'iPhone pour lancer les prédictions`

注意：watchOS target 的 `String(localized:)` 需要这 7 个 lproj 文件也编入 Watch target——在 File Inspector 给 `Sources/Resources` 下每个 `Localizable.strings` 勾选 `CycleAdvisorWatch` 和 `CycleAdvisorWatchComplication`。**注意 Localizable.strings 是分组资源**：若 Target Membership 面板不可勾选，检查 Project → Info → Localizations 已有 7 语言，strings 文件按本地化资源自动随 target；若构建后手表显示 key 而非文案，把 7 个 strings 文件显式加入 Watch target 的 Copy Bundle Resources。

- [ ] **Step 4: 构建通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
git add CycleAdvisorWatch Sources/Resources CycleAdvisor.xcodeproj
git commit -m "Add watch cycle glance: progress ring, phase, predicted period date"
```

---

### Task 7: Watch Complication

**Files:**
- Modify: `CycleAdvisorWatchComplication/` 模板生成的 Widget 文件（文件名以模板为准）

**Interfaces:**
- Consumes: `HealthKitManager`、`CyclePhaseEngine().daysUntilNextPeriod(lastPeriodStart:cycleLength:from:)`
- Produces: Widget `CycleAdvisorComplication`，支持 `accessoryCircular / accessoryRectangular / accessoryCorner`

- [ ] **Step 1: 实现 TimelineProvider + Widget**

模板文件内容替换为：

```swift
import WidgetKit
import SwiftUI

struct CycleComplicationEntry: TimelineEntry {
    let date: Date
    let phaseEmoji: String
    let phaseName: String
    let daysLeft: Int?
}

struct CycleComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> CycleComplicationEntry {
        CycleComplicationEntry(date: .now, phaseEmoji: "🌱", phaseName: "", daysLeft: 8)
    }
    func getSnapshot(in context: Context, completion: @escaping (CycleComplicationEntry) -> Void) {
        Task { completion(await loadEntry()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CycleComplicationEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            // 每日刷新：下一次 timeline 在明天 0 点后
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1,
                                                 to: Calendar.current.startOfDay(for: .now))!
            completion(Timeline(entries: [entry], policy: .after(tomorrow)))
        }
    }

    private func loadEntry() async -> CycleComplicationEntry {
        let healthKit = HealthKitManager.shared
        guard healthKit.isAvailable,
              let lastPeriodStart = await healthKit.fetchLastPeriodStart() else {
            return CycleComplicationEntry(date: .now, phaseEmoji: "🌙", phaseName: "", daysLeft: nil)
        }
        let cycleLength = await healthKit.fetchAverageCycleLength()
        let engine = CyclePhaseEngine()
        let base = engine.determinePhase(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        let daysLeft = engine.daysUntilNextPeriod(lastPeriodStart: lastPeriodStart, cycleLength: cycleLength)
        return CycleComplicationEntry(date: .now, phaseEmoji: base.phase.emoji,
                                      phaseName: base.phase.displayName, daysLeft: daysLeft)
    }
}

struct CycleComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: CycleComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(entry.phaseEmoji)
                    if let days = entry.daysLeft {
                        Text("\(days)").font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
            }
        case .accessoryCorner:
            Text(entry.phaseEmoji + (entry.daysLeft.map { " \($0)" } ?? ""))
        default: // accessoryRectangular
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.phaseEmoji + " " + entry.phaseName).font(.headline)
                if let days = entry.daysLeft {
                    Text(String(format: String(localized: "watch.complication.days_left %lld"), Int64(days)))
                        .font(.caption)
                }
            }
        }
    }
}

@main
struct CycleAdvisorComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CycleAdvisorComplication", provider: CycleComplicationProvider()) { entry in
            CycleComplicationView(entry: entry)
        }
        .configurationDisplayName("CycleAdvisor")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner])
    }
}
```

注意：模板可能已生成 `@main` App 于 watch app target——complication extension 的 `@main` 是 Widget，各自独立，不冲突。若模板已含别的 `@main` Widget 文件，删除模板示例 Widget。

- [ ] **Step 2: 7 语言 key**

```
"watch.complication.days_left %lld" = "还有 %lld 天";   // zh-Hans
```
- zh-Hant `還有 %lld 天` / en `in %lld days` / ja `あと %lld 日` / ko `%lld일 남음` / es `en %lld días` / fr `dans %lld jours`

- [ ] **Step 3: 构建通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
git add CycleAdvisorWatchComplication Sources/Resources CycleAdvisor.xcodeproj
git commit -m "Add watch complication showing cycle phase and days until period"
```

---

### Task 8: WorkoutCelebrationPlanner 纯逻辑（庆祝去重/合并/时机）

**Files:**
- Create: `Sources/Shared/WorkoutCelebrationPlanner.swift`（编入 iPhone target 以便单测；同时编入 Watch target）
- Test: `CycleAdvisorTests/WorkoutCelebrationPlannerTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `WorkoutPosterMapper.celebrationAssetName(key:name:)`
- Produces:
  - `struct PendingCelebration: Codable, Equatable { workoutUUID: UUID, activityKey: String, posterAssetName: String, fireDate: Date }`
  - `WorkoutCelebrationPlanner.delay: TimeInterval`（= 60）
  - `WorkoutCelebrationPlanner.plan(workoutUUID: UUID, activityKey: String, activityName: String, workoutEnd: Date, now: Date, celebratedUUIDs: Set<UUID>) -> PendingCelebration?`（nil = 重复不庆祝）
  - `PendingCelebration.notificationID: String`（`"workout.celebration.<uuid>"`）

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import CycleAdvisor

/// 庆祝计划（spec §2.3）：延迟 1 分钟、同一 workout 只庆祝一次、窗口内多次完成只留最后一次
final class WorkoutCelebrationPlannerTests: XCTestCase {

    func testFireDateIsOneMinuteAfterEnd() {
        let end = Date()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: UUID(), activityKey: "running", activityName: "跑步",
            workoutEnd: end, now: end, celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.fireDate.timeIntervalSince(end) ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(plan?.posterAssetName, "WorkoutPosterRunning")
    }

    func testDuplicateWorkoutNotCelebrated() {
        let uuid = UUID()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: uuid, activityKey: "yoga", activityName: "瑜伽",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: [uuid]
        )
        XCTAssertNil(plan)
    }

    func testUnknownActivityFallsBackToPark() {
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: UUID(), activityKey: "unknown_999", activityName: "Frisbee",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.posterAssetName, "WorkoutPosterPark")
    }

    func testNotificationIDContainsUUID() {
        let uuid = UUID()
        let plan = WorkoutCelebrationPlanner.plan(
            workoutUUID: uuid, activityKey: "running", activityName: "跑步",
            workoutEnd: Date(), now: Date(), celebratedUUIDs: []
        )
        XCTAssertEqual(plan?.notificationID, "workout.celebration.\(uuid.uuidString)")
    }
}
```

合并规则（1 分钟窗口内多次完成只留最后一次）由 Watch 端实现方式天然保证：新 celebration 调度前移除所有 `workout.celebration.*` pending 请求（Task 9 Step 3），此处不需要独立 merge 函数。

- [ ] **Step 2: 确认编译失败**

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 待触发的运动庆祝（spec §2.3）
struct PendingCelebration: Codable, Equatable {
    let workoutUUID: UUID
    let activityKey: String
    let posterAssetName: String
    let fireDate: Date

    var notificationID: String { "workout.celebration.\(workoutUUID.uuidString)" }
}

/// 庆祝计划器：纯逻辑，可单测。watchOS 触发流程见 Task 9。
enum WorkoutCelebrationPlanner {
    /// 与 Apple 体能训练总结页错开的固定延迟
    static let delay: TimeInterval = 60

    /// 返回 nil 表示该 workout 已庆祝过，不再重复
    static func plan(workoutUUID: UUID, activityKey: String, activityName: String,
                     workoutEnd: Date, now: Date, celebratedUUIDs: Set<UUID>) -> PendingCelebration? {
        guard !celebratedUUIDs.contains(workoutUUID) else { return nil }
        return PendingCelebration(
            workoutUUID: workoutUUID,
            activityKey: activityKey,
            posterAssetName: WorkoutPosterMapper.celebrationAssetName(key: activityKey, name: activityName),
            fireDate: max(workoutEnd, now) + delay
        )
    }
}
```

- [ ] **Step 4: 测试通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:CycleAdvisorTests/WorkoutCelebrationPlannerTests 2>&1 | tail -5
git add Sources/Shared/WorkoutCelebrationPlanner.swift CycleAdvisorTests/WorkoutCelebrationPlannerTests.swift CycleAdvisor.xcodeproj
git commit -m "Add WorkoutCelebrationPlanner with 1-minute delay and dedupe"
```

---

### Task 9: Watch 运动庆祝流程（observer + 通知 + 前台展示）

**Files:**
- Create: `CycleAdvisorWatch/WatchWorkoutObserver.swift`
- Create: `CycleAdvisorWatch/CelebrationView.swift`
- Modify: `CycleAdvisorWatch/CycleAdvisorWatchApp.swift`（启动 observer、scenePhase 检查 pending、通知 delegate）
- Modify: `Sources/Resources/*.lproj/Localizable.strings`（7 个）

**Interfaces:**
- Consumes: Task 8 全部、`HealthKitManager.workoutKey(for:)`
- Produces:
  - `WatchWorkoutObserver`（`start()`；内部 HKObserverQuery + anchored query + `enableBackgroundDelivery`）
  - `CelebrationStore`（UserDefaults 存 `PendingCelebration` + 已庆祝 UUID 集合，容量上限 50 个）
  - `CelebrationView(posterAssetName: String, onDismiss: () -> Void)`

- [ ] **Step 1: CelebrationStore**

```swift
import Foundation

/// 庆祝的本地状态：待展示的一条 + 已庆祝 UUID 去重集合（只留最近 50 个）
final class CelebrationStore {
    private let defaults = UserDefaults.standard
    private let pendingKey = "watch.pendingCelebration"
    private let celebratedKey = "watch.celebratedUUIDs"

    var pending: PendingCelebration? {
        get {
            guard let data = defaults.data(forKey: pendingKey) else { return nil }
            return try? JSONDecoder().decode(PendingCelebration.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: pendingKey)
            } else {
                defaults.removeObject(forKey: pendingKey)
            }
        }
    }

    var celebratedUUIDs: Set<UUID> {
        Set((defaults.stringArray(forKey: celebratedKey) ?? []).compactMap(UUID.init))
    }

    func markCelebrated(_ uuid: UUID) {
        var list = defaults.stringArray(forKey: celebratedKey) ?? []
        list.append(uuid.uuidString)
        if list.count > 50 { list = Array(list.suffix(50)) }
        defaults.set(list, forKey: celebratedKey)
    }
}
```

- [ ] **Step 2: WatchWorkoutObserver**

```swift
import Foundation
import HealthKit
import UserNotifications
import UIKit

/// 监听手表本地 HealthKit 的新 workout 记录（用户用 Apple 体能训练或任何写
/// HealthKit 的 app 结束运动后触发），规划 1 分钟后的插图庆祝（spec §2.3）。
final class WatchWorkoutObserver: NSObject {
    private let store = HKHealthStore()
    private let celebrationStore = CelebrationStore()
    private var anchor: HKQueryAnchor? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "watch.workoutAnchor") else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: "watch.workoutAnchor")
                return
            }
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
            UserDefaults.standard.set(data, forKey: "watch.workoutAnchor")
        }
    }

    func start() {
        let type = HKWorkoutType.workoutType()
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completionHandler, _ in
            self?.fetchNewWorkouts()
            completionHandler()
        }
        store.execute(query)
        // 冷启动也补一次（错过后台回调时兜底）
        fetchNewWorkouts()
    }

    private func fetchNewWorkouts() {
        let type = HKWorkoutType.workoutType()
        // 首次运行 anchor 为 nil 时查询会返回全部历史记录——只保存 anchor，
        // 历史运动不补庆祝（spec §2.3 边界）
        let isFirstRun = anchor == nil
        let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor,
                                          limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            self.anchor = newAnchor
            guard !isFirstRun else { return }
            for workout in (samples as? [HKWorkout]) ?? [] {
                self.planCelebration(for: workout)
            }
        }
        store.execute(query)
    }

    private func planCelebration(for workout: HKWorkout) {
        let key = HealthKitManager.workoutKey(for: workout.workoutActivityType)
        guard let pending = WorkoutCelebrationPlanner.plan(
            workoutUUID: workout.uuid,
            activityKey: key,
            activityName: key,            // 名称只用于关键词兜底，key 已覆盖绝大多数场景
            workoutEnd: workout.endDate,
            now: Date(),
            celebratedUUIDs: celebrationStore.celebratedUUIDs
        ) else { return }

        // 合并规则：新庆祝顶掉旧的 pending（1 分钟窗口内只留最后一次）
        celebrationStore.pending = pending
        scheduleNotification(for: pending)
    }

    private func scheduleNotification(for pending: PendingCelebration) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let stale = requests.map(\.identifier).filter { $0.hasPrefix("workout.celebration.") }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            let content = UNMutableNotificationContent()
            content.title = String(localized: "watch.celebration.title")
            content.body = String(localized: "watch.celebration.body")
            content.sound = .default
            if let url = Self.attachmentURL(assetName: pending.posterAssetName),
               let attachment = try? UNNotificationAttachment(identifier: "poster", url: url) {
                content.attachments = [attachment]
            }
            let interval = max(1, pending.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: pending.notificationID, content: content, trigger: trigger))
        }
    }

    /// UNNotificationAttachment 需要文件 URL：把 bundle 里的插图导出到临时目录
    static func attachmentURL(assetName: String) -> URL? {
        guard let image = UIImage(named: assetName),
              let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(assetName).jpg")
        try? data.write(to: url)
        return url
    }
}
```

- [ ] **Step 3: CelebrationView**

```swift
import SwiftUI
import WatchKit

/// 全屏庆祝页（spec §2.3）：插图 + 成功震动 + 鼓励文案
struct CelebrationView: View {
    let posterAssetName: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.warmShell.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(posterAssetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 8)
                Text("watch.celebration.message")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "watch.celebration.done")) { onDismiss() }
                    .font(.system(size: 13))
            }
        }
        .onAppear {
            WKInterfaceDevice.current().play(.success)
        }
    }
}
```

- [ ] **Step 4: App 入口接线**

`CycleAdvisorWatchApp.swift`：

```swift
import SwiftUI
import UserNotifications

@main
struct CycleAdvisorWatchApp: App {
    private let observer = WatchWorkoutObserver()
    private let celebrationStore = CelebrationStore()
    @State private var showCelebration = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .fullScreenCover(isPresented: $showCelebration) {
                    if let pending = celebrationStore.pending {
                        CelebrationView(posterAssetName: pending.posterAssetName) {
                            celebrationStore.markCelebrated(pending.workoutUUID)
                            celebrationStore.pending = nil
                            showCelebration = false
                        }
                    }
                }
                .onAppear { observer.start() }
                .onChange(of: scenePhase) { _, phase in
                    // 前台路径：延迟窗口内用户主动打开 app → 立即展示并取消未发通知
                    guard phase == .active, let pending = celebrationStore.pending else { return }
                    UNUserNotificationCenter.current()
                        .removePendingNotificationRequests(withIdentifiers: [pending.notificationID])
                    celebrationStore.markCelebrated(pending.workoutUUID)
                    showCelebration = true
                }
        }
    }
}
```

通知点按进入 app 时 scenePhase → .active 会走同一条前台路径，无需单独 delegate。

- [ ] **Step 5: 7 语言庆祝文案**

```
"watch.celebration.title" = "运动完成 👏";                       // zh-Hans
"watch.celebration.body" = "点开看看属于你的运动纪念";
"watch.celebration.message" = "你今天照顾好了自己";
"watch.celebration.done" = "收下";
```
- zh-Hant: `運動完成 👏` / `點開看看屬於你的運動紀念` / `你今天照顧好了自己` / `收下`
- en: `Workout complete 👏` / `Tap to see your workout keepsake` / `You took good care of yourself today` / `Keep it`
- ja: `ワークアウト完了 👏` / `タップして運動の記念を見る` / `今日の自分をいたわりましたね` / `受け取る`
- ko: `운동 완료 👏` / `탭해서 운동 기념을 확인하세요` / `오늘 스스로를 잘 돌봤어요` / `받기`
- es: `Entrenamiento completado 👏` / `Toca para ver tu recuerdo deportivo` / `Hoy te cuidaste bien` / `Quedármelo`
- fr: `Entraînement terminé 👏` / `Touche pour voir ton souvenir sportif` / `Tu as bien pris soin de toi aujourd'hui` / `Garder`

- [ ] **Step 6: 构建通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
git add CycleAdvisorWatch Sources/Resources
git commit -m "Add watch workout celebration: observer, delayed notification, full-screen poster"
```

---

### Task 10: Watch 插图资产

**Files:**
- Create: `CycleAdvisorWatch/WatchAssets.xcassets/WorkoutPoster*.imageset`（18 张）

- [ ] **Step 1: 生成压缩版插图**

iPhone 的 `Sources/Assets.xcassets` 里已有全部 WorkoutPoster 图，直接从源 imageset 复制压缩（45mm 表盘 @2x 宽约 400px，spec §4.3）：

```bash
cd /Users/lufi/Documents/Claude/Projects/cycle_advisor-main
mkdir -p CycleAdvisorWatch/WatchAssets.xcassets
cat > CycleAdvisorWatch/WatchAssets.xcassets/Contents.json <<'EOF'
{"info":{"author":"xcode","version":1}}
EOF
for d in Sources/Assets.xcassets/WorkoutPoster*.imageset; do
  name=$(basename "$d" .imageset)
  src=$(ls "$d"/*.png 2>/dev/null | head -1)
  [ -z "$src" ] && { echo "SKIP $name (no png)"; continue; }
  dest="CycleAdvisorWatch/WatchAssets.xcassets/$name.imageset"
  mkdir -p "$dest"
  sips -Z 400 "$src" --out "$dest/$name.png" >/dev/null
  cat > "$dest/Contents.json" <<EOF
{"images":[{"filename":"$name.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}
EOF
done
ls Sources/Assets.xcassets | grep -c "^WorkoutPoster.*imageset"                 # 记为 N（当前 17）
ls CycleAdvisorWatch/WatchAssets.xcassets | grep -c imageset                    # 必须等于 N
du -sh CycleAdvisorWatch/WatchAssets.xcassets                                   # 预期 < 1MB
```

- [ ] **Step 2: 把 WatchAssets.xcassets 加入 Xcode**

Xcode 里把 `CycleAdvisorWatch/WatchAssets.xcassets` 拖进 navigator 的 `CycleAdvisorWatch` 组（勾选 Copy if needed，target 勾 `CycleAdvisorWatch`）；确认它出现在 target 的 Copy Bundle Resources 里。

- [ ] **Step 3: 构建通过 + Commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
git add CycleAdvisorWatch CycleAdvisor.xcodeproj
git commit -m "Add compressed workout poster assets to watch target"
```

---

### Task 11: 收尾验证

- [ ] **Step 1: 全量回归**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -5
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CycleAdvisor.xcodeproj -scheme CycleAdvisorWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build 2>&1 | tail -3
```
Expected: iOS 测试全 PASS，两个 target BUILD SUCCEEDED

- [ ] **Step 2: 模拟器手动清单**

- [ ] iPhone 模拟器：健康 app 录入经期历史 → 主页周期模块显示「预计 X 月 X 日 · 还有 N 天」
- [ ] iPhone 模拟器：切换 zh-Hans / en / ja 三语言各看一遍主页预测行与通知文案
- [ ] Watch 模拟器（与 iPhone 模拟器配对）：速览页显示环 + 阶段 + 预测行
- [ ] 模拟器健康 app 手动录入一条 workout → 约 1 分钟后手表收到带图通知 → 点按进全屏庆祝页
- [ ] 录入 workout 后 30 秒内打开本 app → 前台直接展示庆祝且无后续通知

- [ ] **Step 3: 真机验证（发布前阻塞项，spec §5）**

- [ ] 真机配对验证 `HKObserverQuery` 后台触发与 `enableBackgroundDelivery`
- [ ] 真机验证 iPhone 通知自动镜像到手表
- [ ] Watch App Icon 补齐（模板占位图标不可上架）
- [ ] 7 语言通知文案真机过一遍

- [ ] **Step 4: Commit + push**

```bash
git commit -am "Final verification pass for watch companion and period prediction" --allow-empty
git push origin main
```
