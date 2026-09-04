# Apple Watch 配套 + 周期/运动通知 设计文档

日期：2026-09-04
状态：待评审
范围版本：v3（经用户逐轮确认）

## 1. 背景与目标

CycleAdvisor 是经期健康建议 iOS 应用（SwiftUI，7 语言，HealthKit 只读，周期预测逻辑已有）。用户运动记录全部发生在 Apple Watch 原生"体能训练"app，本 app 不做任何运动记录功能。

本次目标：

1. 新增 watchOS 配套 app：周期速览 + 运动完成插图庆祝。
2. iPhone 端：主页周期模块内显示月经预测（日期 + 倒计时）；每周/每月最爱运动通知。

核心产品理念：**插图 = 奖励**。运动完成后、周期总结时，给用户对应运动的精美插图，形成正反馈闭环。所有素材（20 张 WorkoutPoster 插图）与"运动类型 → 插图"映射均已存在，本次零新增素材。

### 明确不做

- 不做 iPhone 端经期预测通知（系统"健康"app 已提供该能力，不重复造）
- 不做运动打卡/记录系统（记录归 Apple 体能训练）
- 不做 `HKWorkoutSession`（手表端不发起运动）
- 不做手表端 AI 聊天、文献引用、设置页
- 不做 WatchConnectivity 数据同步（理由见 §4.1）

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
4. 呈现庆祝：
   - **App 在前台**：全屏插图 + `WKHapticType.success` 震动 + 一句鼓励文案（如「你今天照顾好了自己」）
   - **App 在后台**：发手表本地通知（带插图附件），点开通知进入全屏庆祝页
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

### 2.5 iPhone：每周 / 每月最爱运动通知

- **每周**：每周日 20:00 ——「这周你做得最多的是 瑜伽」+ 该运动插图附件
- **每月**：每月 1 号 10:00 ——上月最爱运动，同样带插图
- 数据来源：HealthKit  workouts 统计（与 `WorkoutStats.topActivities` 同一套查询逻辑）
- 本周/月无运动记录 → 当周/当月不发，不打扰
- **内容时效**：通知文案在调度时生成。为避免"用户没开 app 导致内容过期"，用 `BGAppRefreshTask` 每日刷新一次通知内容；app 启动时也刷新。最坏情况内容滞后 1 天，可接受
- 插图走 `UNNotificationAttachment`（JPG/PNG < 1 MB，需为通知导出压缩版，见 §4.3）

## 3. 本地化

所有新增文案（Watch UI、庆祝文案、主页预测行、周/月通知）进现有 7 语言 lproj：zh-Hans、zh-Hant、en、ja、ko、es、fr。key 前缀约定：`watch.*`、`home.prediction.*`、`notify.workout.*`。

## 4. 技术架构

### 4.1 数据流：不用 WatchConnectivity

关键事实：本 app 的周期数据**读自 HealthKit**（`menstrualFlow` 记录），而非自有数据库。Apple 的 HealthKit 数据自动同步到配对 Watch 的本地 store。因此：

- **Watch 端直接读本地 `HKHealthStore`**：经期记录（→ `fetchLastPeriodStart` / cycleLength 同款逻辑）、workout 记录，全部本地可得
- iPhone 与 Watch 之间零自建同步通道
- 限制：Watch 端首次使用需单独弹 HealthKit 授权（手表上弹授权 sheet 会引导到手机完成，系统行为）；若用户在手机上关了 iCloud 健康同步则手表数据可能滞后——接受此限制，界面按"无数据"兜底展示

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
- 通知附件版：从同一源导出 ≤ 1 MB JPEG（iPhone 通知用，不打进 Watch target）

### 4.4 权限与能力

- Watch target：HealthKit capability（读 workout、menstrualFlow）；无网络需求，不加 App Transport 例外
- iPhone：通知权限（首次启动时请求，拒绝则 §2.5 静默关闭）；Background Modes 增加 App Refresh（供 §2.5 内容刷新）
- 隐私清单 `PrivacyInfo.xcprivacy`：HealthKit 读取与本地通知均为系统能力，无需新增声明条目（实现时按 Apple 当前要求核对一次）

### 4.5 错误处理

| 场景 | 行为 |
|---|---|
| Watch 无经期数据 | 速览页显示引导文案「在 iPhone 健康 app 记录经期后开始预测」 |
| 预测日期已过但无新经期记录 | 文案切换为「可能推迟了 X 天」，不报警 |
| 通知权限被拒 | 设置页显示入口状态，不再弹窗 |
| 插图 asset 缺失 | 兜底 `WorkoutPosterPark`，记日志 |
| BGAppRefresh 被系统抑制 | 通知内容滞后，接受 |

## 5. 测试

- **单元测试**（进现有 `CycleAdvisorTests`）：
  - `WorkoutPosterMapper`：覆盖全部映射 case + 兜底
  - 预测日期/倒计时边界：跨月、周期第 1 天、推迟场景
  - 通知调度逻辑：上周无运动 → 不调度；有运动 → 内容取 topActivity 第一名
  - 去重逻辑：同一 workout UUID 不重复触发庆祝
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
| iPhone：周/月最爱运动通知（含 BGAppRefresh） | 2 天 |
| 7 语言文案 + 插图资产处理 | 1–2 天 |
| 真机联调 + 修坑 | 2–3 天 |

合计约 **2–2.5 周**。

## 7. 里程碑顺序

1. 共享代码抽取（iPhone 行为不变，纯重构，先行合并）
2. iPhone 主页周期模块预测显示（独立可发）
3. Watch target：速览 + complication
4. Watch：运动完成庆祝
5. iPhone 周/月通知
