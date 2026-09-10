# Apple Watch 配套 + 周期/运动通知 设计文档

日期：2026-09-04
状态：待评审
范围版本：v3（经用户逐轮确认）

## 1. 背景与目标

CycleAdvisor 是经期健康建议 iOS 应用（SwiftUI，7 语言，HealthKit 只读，周期预测逻辑已有）。用户运动记录全部发生在 Apple Watch 原生"体能训练"app，本 app 不做任何运动记录功能。

本次目标：

1. 新增 watchOS 配套 app：周期速览 + 运动完成插图庆祝。
2. iPhone 端：经期预测本地通知（前 2 天 + 当天）；主页周期模块内显示月经预测（日期 + 倒计时）。

核心产品理念：**插图 = 奖励**。运动完成后、周期总结时，给用户对应运动的精美插图，形成正反馈闭环。所有素材（20 张 WorkoutPoster 插图）与"运动类型 → 插图"映射均已存在，本次零新增素材。

### 明确不做

- 不做每周/每月最爱运动通知（运动模块 dashboard 已有周/月统计与插图展示，不重复推送）
- 不做运动打卡/记录系统（记录归 Apple 体能训练）
- 不做 `HKWorkoutSession`（手表端不发起运动）
- 不做手表端 AI 聊天、文献引用、设置页
- 不做 WatchConnectivity 数据同步（理由见 §4.1；2026-09-10 起验孕提示状态除外，见 §4.1 例外说明）

## 2. 功能设计

### 2.1 Watch：周期速览主屏

**内容**（自上而下）：

- 简化版周期进度环：当前阶段着色（复用 `Theme.phase*` 色值），环中心显示周期第几天
- 预测经期信息区：
  - 「预计 9 月 12 日」——预测下次经期开始日期
  - 「还有 8 天」——倒计时
  - 经期进行中时切换为「经期第 2 天」进行态文案
- 今日运动建议一句话摘要（可选区，无数据时整块隐藏）

**交互**：单屏为主，建议摘要可下滑查看。无多层导航。

### 2.2 Watch：表盘 Complication

- 支持 corner / circular / rectangular 三种族位
- 内容：当前阶段色块/emoji + 「还有 X 天」
- 数据源：手表本地 HealthKit（见 §4.1），WidgetKit timeline，每日刷新 + 数据变化时 reload

### 2.3 Watch：运动完成插图庆祝（核心亮点）

**流程**：

1. 用户在手表"体能训练"（或任何写 HealthKit 的 app）结束一次运动
2. Watch 端 `HKObserverQuery`（`HKWorkoutType`，后台投递）发现新记录
3. 按 `workoutActivityType` 查共享映射表 → 对应 WorkoutPoster 插图
4. **错开 Apple 体能训练的结束总结**：检测到完成后**不立即弹出**，延迟约 1 分钟再触达——此刻用户通常已看完 Apple 的总结界面，庆祝才不与之抢屏
   - 到时后：发手表本地通知（带插图附件），点开通知进入全屏庆祝页（插图 + `WKHapticType.success` 震动 + 鼓励文案，如「你今天照顾好了自己」）
   - 若延迟期间用户主动打开了本 app：直接在前台展示庆祝页，并取消未发的通知
   - 1 分钟内连续完成多次运动：合并为最后一次的通知，避免轰炸
5. 映射表未覆盖的运动类型 → `WorkoutPosterPark` 兜底（与 iPhone 端现有逻辑一致）

**边界**：

- 启动时只监听"之后"的新记录，历史运动不补庆祝（`HKObserverQuery` 从 anchor 开始）
- 同一运动只庆祝一次（记录 UUID 去重，存 watch 端本地）
- 用户未授权 HealthKit 运动数据 → 庆祝功能静默关闭，周期速览不受影响（经期类型单独授权）

### 2.4 iPhone：主页周期模块显示月经预测

现状：`CycleRingView` 只显示阶段 emoji、阶段名、阶段持续天数、周期第几天，**没有预测信息**。

改动（只动主页周期模块，不加通知）：

- 周期环下方新增一行预测信息：
  - 「预计 9 月 12 日 · 还有 8 天」——预测开始日期 + 倒计时
  - 经期进行中显示「经期第 2 天」
  - 预测日期已过但 HealthKit 无新经期记录：「可能推迟了 X 天」
- 数据来源：`CyclePhaseEngine.nextPeriodDate` / `daysUntilNextPeriod`（现有），输入复用 `HomeViewModel` 已取的 `lastPeriodStart` 与 `avgCycleLength`，无新数据请求
- 与 Watch 速览（§2.1）共用同一套文案 key 与计算逻辑，两端显示一致
- 视觉遵循现有暖色纸质主题，样式对齐环内现有小字（`Theme.captionSize`、次要色），不抢阶段主信息

### 2.5 iPhone：经期预测通知

- 两条本地通知：预测经期**前 2 天**（「可以提前准备了」）、**当天**各一条，上午 9:00
- 预测日期来源：`CyclePhaseEngine.nextPeriodDate(lastPeriodStart:cycleLength:)`（现有）
- 每次 app 启动且周期数据变化时重算并重排通知；经期实际来临（HealthKit 出现新 menstrualFlow 记录）时取消当天未发的预测通知
- 预测日期是确定值，通知内容调度时生成即可，不会过期，**不需要后台刷新任务**
- iPhone 通知自动镜像到配对的手表，无需手表端单独实现

## 3. 本地化

所有新增文案（Watch UI、庆祝文案、主页预测行、经期预测通知）进现有 7 语言 lproj：zh-Hans、zh-Hant、en、ja、ko、es、fr。key 前缀约定：`watch.*`、`home.prediction.*`、`notify.period.*`。

## 4. 技术架构

### 4.1 数据流：不用 WatchConnectivity

关键事实：本 app 的周期数据**读自 HealthKit**（`menstrualFlow` 记录），而非自有数据库。Apple 的 HealthKit 数据自动同步到配对 Watch 的本地 store。因此：

- **Watch 端直接读本地 `HKHealthStore`**：经期记录（→ `fetchLastPeriodStart` / cycleLength 同款逻辑）、workout 记录，全部本地可得
- iPhone 与 Watch 之间零自建同步通道
- 限制：Watch 端首次使用需单独弹 HealthKit 授权（手表上弹授权 sheet 会引导到手机完成，系统行为）；若用户在手机上关了 iCloud 健康同步则手表数据可能滞后——接受此限制，界面按"无数据"兜底展示

**例外（2026-09-10 起）**：验孕提示状态（possible/likely）经 WatchConnectivity 由 iPhone 单向推送到 Watch（`ConceptionWatchSync`，payload 仅 tier + 原因 + 周期起点时间戳，手表不回传任何数据）。理由：提示依赖 iPhone 侧的备孕开关、手动 BBT 与验孕反馈状态，手表本地无法独立判定；用户明确不要通知镜像，要求手表原生通知。周期/运动数据仍坚持只读本地 HealthKit，此例外仅限验孕提示。

### 4.2 工程结构

- 新增 watchOS App target（SwiftUI 生命周期）+ Watch 端 WidgetKit extension（complication）
- 抽共享代码（放 `Sources/Shared/`，通过 target membership 同时编入 iPhone / Watch target，不新建 framework）：
  - `CyclePhaseEngine` 的 `nextPeriodDate` / `daysUntilNextPeriod` / `determinePhase`
  - `WorkoutPosterMapper`：**从 `WorkoutDashboardView`（约 1083–1180 行）抽出** `HKWorkoutActivityType → 插图 asset 名` 映射，两处调用改为同一实现
  - 经期记录查询（`fetchLastPeriodStart` 等纯查询函数）
- Target membership 调整最小化，不动现有模块边界

### 4.3 插图资产

- 20 张 PNG 源图在 `~/Desktop/运动配图`，18 张已进 iPhone 的 Assets.xcassets
- Watch target 复制一份 asset catalog，尺寸按 45mm 表盘 @2x（约 360×450 pt 内）压缩，单张 ≤ 100 KB，总体积 < 1 MB

### 4.4 权限与能力

- Watch target：HealthKit capability（读 workout、menstrualFlow）；无网络需求，不加 App Transport 例外
- iPhone：通知权限（首次启动时请求，拒绝则 §2.5 静默关闭）
- 隐私清单 `PrivacyInfo.xcprivacy`：HealthKit 读取与本地通知均为系统能力，无需新增声明条目（实现时按 Apple 当前要求核对一次）

### 4.5 错误处理

| 场景 | 行为 |
|---|---|
| Watch 无经期数据 | 速览页显示引导文案「在 iPhone 健康 app 记录经期后开始预测」 |
| 预测日期已过但无新经期记录 | 文案切换为「可能推迟了 X 天」，不报警 |
| 通知权限被拒 | 设置页显示入口状态，不再弹窗 |
| 插图 asset 缺失 | 兜底 `WorkoutPosterPark`，记日志 |

## 5. 测试

- **单元测试**（进现有 `CycleAdvisorTests`）：
  - `WorkoutPosterMapper`：覆盖全部映射 case + 兜底
  - 预测日期/倒计时边界：跨月、周期第 1 天、推迟场景
  - 经期预测通知调度：数据变化重排、经期来临取消未发通知、权限拒绝时不调度
  - 去重与合并：同一 workout UUID 不重复触发；1 分钟内多次完成只保留最后一次的通知
- **手动测试清单**（模拟器配对 iPhone + Watch）：
  - 健康 app 里手动录入一条 workout → 手表收到庆祝
  - 前台/后台两种触发路径
  - 7 种语言下通知文案与插图正确
  - 通知点击跳转目标正确
- watchOS 的 `HKObserverQuery` 后台行为模拟器不可信，**真机验证**列为发布前阻塞项

## 6. 工作量估算

| 项 | 估时 |
|---|---|
| 共享代码抽取（mapper、engine、查询）+ 单元测试 | 1–2 天 |
| Watch target：速览页 + complication | 3–4 天 |
| Watch：运动庆祝（observer + 前台/后台两路径） | 3–4 天 |
| iPhone：主页周期模块预测显示 | 1 天 |
| iPhone：经期预测通知 | 1 天 |
| 7 语言文案 + 插图资产处理 | 1–2 天 |
| 真机联调 + 修坑 | 2–3 天 |

合计约 **2 周**（12–17 个工作日）。

## 7. 里程碑顺序

1. 共享代码抽取（iPhone 行为不变，纯重构，先行合并）
2. iPhone 经期预测通知 + 主页周期模块预测显示（独立可发）
3. Watch target：速览 + complication
4. Watch：运动完成庆祝
