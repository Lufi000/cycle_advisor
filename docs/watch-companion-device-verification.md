# Apple Watch 配套 · 真机验证清单

> 状态：发布前阻塞项。模拟器不可信，必须 iPhone（真机）+ 配对 Apple Watch 执行。
> 对应实现：`CycleAdvisorWatch/WatchWorkoutObserver.swift`、`Sources/Shared/WorkoutCelebrationPlanner.swift`、`CycleAdvisorWatch/CycleAdvisorWatchApp.swift`。

## 前置

1. iPhone 真机 + 已配对 Apple Watch，均登录同一 iCloud（健康数据同步开）。
2. 用 Xcode 把 `CycleAdvisor` scheme 装到 iPhone，watch app 会随装到手表。
3. 首次打开 watch app：确认 HealthKit 授权弹窗（手表会引导到手机完成）。允许读取「运动」与「经期」。

## 关键实现事实（判断预期时对照）

- 庆祝延迟固定 **60 秒**（`WorkoutCelebrationPlanner.delay`），与 Apple 体能训练总结页错开。
- 去重：已庆祝 UUID 存在 `watch.celebratedUUIDs`（只留最近 50 个）；待触发的存在 `watch.pendingCelebration`。
- 锚点：`watch.workoutAnchor`。**首次运行只存锚点、不补庆祝历史记录**。
- 通知 identifier：`workout.celebration.<workoutUUID>`，带插图附件。
- 前台路径：app 进入 `.active` 时若存在 pending，取消通知、标记已庆祝；若 `pending.fireDate` 已超过 5 分钟则静默清掉（不再全屏）。

## 验证项

### 1. 后台投递（核心阻塞项）

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1.1 | 关掉 watch app，在手表「体能训练」结束一次运动（或手机健康 app 手动录入一条 workout） | 观察是否在 **约 1 分钟** 后收到本地通知（带插图） |
| 1.2 | 收到通知 → 点开 | 进入全屏庆祝页（插图 + 震动 + 鼓励文案） |
| 1.3 | 结束运动后**不打开 app、锁屏**等 1 分钟 | 判定后台投递是否按时触发 |

**已知风险**：watchOS 对 `HKObserverQuery` 的 `.immediate` 后台投递限频约 **每小时一次**。大概率表现是：结束运动后 1 分钟通知**不按时到**，而是「下次打开 app」时补触发（`onAppear`/`scenePhase` 路径 + 冷启动 `fetchNewWorkouts()` 兜底）。**这是 spec 已接受的降级**，判定时只需确认：
- 不崩溃、不重复轰炸；
- 最终能看到庆祝（无论 1 分钟通知还是下次打开 app）。

### 2. 前台路径

| 步骤 | 操作 | 预期 |
|---|---|---|
| 2.1 | 结束运动后 **1 分钟内** 主动打开 watch app | 直接全屏展示庆祝页，且**不会**再收到那条通知（已取消） |
| 2.2 | 结束运动后 **>5 分钟** 才打开 app | 不弹全屏（静默清掉 pending） |

### 3. 去重与合并

| 步骤 | 操作 | 预期 |
|---|---|---|
| 3.1 | 结束同一条 workout（可重复查看） | 只庆祝一次，不重复 |
| 3.2 | 1 分钟内连续结束多次运动 | 只留最后一次的通知/庆祝，不轰炸 |

### 4. 周期速览（watch 主屏）

| 步骤 | 操作 | 预期 |
|---|---|---|
| 4.1 | 手机健康 app 有经期记录时打开 watch app | 显示进度环 + 阶段 + 预测经期日期/倒计时 |
| 4.2 | 手机健康 app 无经期记录 | 显示引导文案「在 iPhone 健康 app 记录经期后开始预测」，不崩溃 |

### 5. 本地化（7 语言抽查）

| 步骤 | 操作 | 预期 |
|---|---|---|
| 5.1 | 手机系统语言切成 zh-Hans / en / ja 各测一次 | 通知文案、庆祝文案、速览文案正确，插图正常 |

### 6. 无崩溃回归

| 步骤 | 操作 | 预期 |
|---|---|---|
| 6.1 | 冷启动 watch app、反复开关、锁屏解锁 | 全程无崩溃（尤其 HealthKit 授权前的首次启动） |

## 判定

- ✅ 通过：1.x（按降级预期）、2–6 全部符合。
- ❌ 阻塞发布：任一项崩溃，或 1.1 后台投递行为与「每小时限频」解释不符且需要提前到 1 分钟（需改方案，见 spec §2.3）。

## 已知未完成项

- Watch AppIcon 已替换为真实图标（复用 iOS 1024×1024），如需 watch 专用圆形留白版可后续补。
- watch target 版本号仍为 1.0.6（iOS app 已 1.0.7），发布前需对齐。
