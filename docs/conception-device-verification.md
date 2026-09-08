# 备孕（验孕提示）功能 · 验收清单

> 状态：代码已完成（分支 `feature/pregnancy-prediction-impl`，构建 + 98 测试全绿），以下为发布前人工验收项。
> 对应实现：`Sources/Core/ConceptionInsightManager.swift`、`Sources/Features/Conception/*`、`Sources/Core/SymptomExtractor.swift`、`bff/handler.go`（`/v1/extract/symptoms`）。

## 前置

1. **BFF 端点上线**：聊天症状抽取走 BFF 新端点 `POST /v1/extract/symptoms`（`bff/handler.go`）。该端点需先部署到生产，否则症状抽取静默失败（fire-and-forget，不崩、不影响对话）。
   部署命令：`bff/deploy.sh`（见 `docs/superpowers/specs/2026-09-04-pregnancy-prediction-design.md` 模块 4）。
2. 真机/模拟器均可验证 UI 项；晨间提醒与腕温相关项需真机（腕温需 Apple Watch Series 8+，佩戴约 2 周建立基线）。

## 关键实现事实（判断预期时对照）

- 备孕开关存在 `UserProfile.isTryingToConceive`，关闭时卡片/提醒/抽取全部停、数据保留。
- 晨间测温提醒只对**近 3 天无腕温覆盖**的备孕用户调度（`ConceptionReminderScheduler.shouldSchedule`），时间存在 `conception.reminderTimeMinutes`（默认 7:00）。
- 手表基线未建立（腕温 < 14 天）时腕温不参与判定，走手动 BBT 过渡（`ConceptionInsightManager.refresh`）。
- 症状抽取节流：消息 < 4 字跳过；同日同消息只请求一次（`SymptomExtractor`）。
- 合规红线：文案只出现「可能怀孕 / 建议验孕确认」，永不出现「你已怀孕」。

## 验证项

### 1. 备孕模式开关与免责

| 步骤 | 操作 | 预期 |
|---|---|---|
| 1.1 | 设置页打开「备孕模式」开关 | 首次弹出免责说明（`conception.onboarding.*`） |
| 1.2 | 点「知道了」后回首页 | 首页出现「备孕追踪」卡片 |
| 1.3 | 关闭开关 | 卡片消失；重新打开 → 卡片恢复，之前录入的数据仍在 |

### 2. 手动 BBT 录入

| 步骤 | 操作 | 预期 |
|---|---|---|
| 2.1 | 卡片点「手动录入体温」→ 输入 36.5 → 保存 | 保存成功；再次打开显示「今早已测 ✓」 |
| 2.2 | 输入 34.0（或 39.0）→ 保存 | 弹出范围错误提示（35.0–38.0） |
| 2.3 | 勾选一个干扰标记（如「熬夜」）保存 | 成功保存，标记随条目持久化 |

### 3. 晨间提醒

| 步骤 | 操作 | 预期 |
|---|---|---|
| 3.1 | 无手表腕温数据 + 备孕模式开，设置里把提醒时间改成 1 分钟后的时刻 | 到点收到本地通知，文案为「该测体温啦」而非「备孕提醒」（锁屏不暴露敏感信息） |
| 3.2 | 有腕温覆盖（真机）或关闭备孕模式 | 通知被撤销，不再触发 |

### 4. 本地化（7 语言抽查）

| 步骤 | 操作 | 预期 |
|---|---|---|
| 4.1 | 系统语言切 zh-Hans / en / ja 各测一次 | 卡片、录入页、免责弹窗、提醒文案均跟随 |

### 5. 聊天症状抽取（依赖 BFF 端点已上线）

| 步骤 | 操作 | 预期 |
|---|---|---|
| 5.1 | 备孕模式下，在 AI 助手发「最近有点恶心，还吐了一次」 | 对话正常（抽取不阻塞）；服务端 `journalctl -u cycle-advisor-bff` 出现 extract 相关日志 |
| 5.2 | 观察本地症状库 | app Documents 目录 `conception_symptoms.json` 出现 `nausea`/`vomiting`（source=chatExtracted） |
| 5.3 | 短消息（< 4 字）或不含症状的消息 | 不发起抽取请求（无多余 token 消耗） |

### 6. 无崩溃回归

| 步骤 | 操作 | 预期 |
|---|---|---|
| 6.1 | 冷启动、反复开关备孕模式、录入体温、锁屏解锁 | 全程无崩溃（尤其 HealthKit 授权前 / 拒绝授权的纯本地模式） |

## 判定

- ✅ 通过：1–4、6 全部符合；5.x 在 BFF 上线后符合（上线前 5 允许「静默失败」）。
- ❌ 阻塞：任一项崩溃，或 2.2 范围校验未拦住非法体温，或 1.x 卡片显隐/数据保留不符。

## 已知未完成项

- BFF `/v1/extract/symptoms` 端点代码已提交，**未部署**（`bff/deploy.sh` 待执行）。
- 症状抽取是 BFF 计费/限流之外的一条独立调用；当前客户端不通过 `BillingManager` 计费（按 spec 设计为 fire-and-forget 的小额调用）。
- 真机腕温主信号需 Series 8+ 且佩戴约 2 周建立基线，模拟器无法验证。
