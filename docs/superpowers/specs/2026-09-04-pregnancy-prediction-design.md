# CycleAdvisor 怀孕预测功能设计

日期：2026-09-04
状态：待评审

## 背景与目标

为 CycleAdvisor 增加"怀孕可能提示"功能。目标用户是**正在备孕**的用户。由于用户群体普遍没有 Apple Watch（无腕温、无 HRV 数据），方案以**手动基础体温（BBT）**为核心信号，融合月经推迟、症状打卡、AI 助手对话抽取的症状信号。

核心原则：**功能只做"提示验孕"，永不宣称"已怀孕"**。确诊只能通过 hCG 检测。

## 总体架构（方案 A）

判定逻辑全部在 App 本地（确定性规则引擎，可单测、可解释、隐私好）；LLM 仅用于从聊天消息中抽取结构化症状标签，走 BFF 独立端点，不侵入主聊天链路。

```
用户晨起测温 ──录入──▶ 本地症状/体温库 ──▶ PregnancyInsightEngine ──▶ 提示等级 ──▶ UI 提示卡
HealthKit 症状 ────────▶       ▲                 ▲
聊天消息 ──异步──▶ BFF /v1/extract/symptoms ──▶ 症状标签 ──┘
                      (deepseek-chat, JSON 输出)
经期记录（HealthKit）──────────────────────────┘
```

## 模块 1：数据模型与存储

### BasalTemperatureEntry

| 字段 | 类型 | 说明 |
|---|---|---|
| date | Date（日粒度） | 测量日，同一日只保留一条（后录入覆盖） |
| celsius | Double | 基础体温，合法范围 35.0–38.0，超出拒绝录入 |
| disturbances | Set<Disturbance> | 干扰标记：熬夜 / 饮酒 / 生病 / 失眠 |
| source | enum | manual（本期只有手动） |

- 有干扰标记的条目参与绘图，但在排卵定位中降权（见模块 3）

### SymptomRecord（统一症状库）

| 字段 | 类型 | 说明 |
|---|---|---|
| date | Date | 症状发生日 |
| type | SymptomType | 见下方枚举 |
| source | enum | healthKit / manual / chatExtracted |

- 去重键：(date, type)，同日同症状只保留一条，优先级 manual > healthKit > chatExtracted
- SymptomType 枚举（映射 HealthKit 类别）：nausea、vomiting、fatigue、breastTenderness、bloating、abdominalCramps、headache、spotting、appetiteChange、moodChange、dizziness

### 存储策略

- **本地为主**：BBT 与症状库各自存为 Documents 目录下的 JSON 文件（与 UserProfileManager 相同的持久化模式），HealthKit 写入为可选同步
- HealthKit 授权被拒绝时纯本地运行，功能不阻塞；仅失去与其他 App 的数据互通
- 读取侧仍走 HealthKitManager 已有的 `fetchMenstrualSymptoms` 拉取系统症状并入症状库

## 模块 2：备孕模式开关

- `UserProfile` 新增 `isTryingToConceive: Bool`（默认 false）
- 设置/Profile 页加入口开关，附一句说明："开启后将提醒你记录晨起体温，并在信号满足时提示验孕"
- 开关关闭时：不显示备孕卡片、不发测温提醒、不触发怀孕提示；已有数据保留

## 模块 3：判定引擎 PregnancyInsightEngine（本地纯逻辑）

输入：近 60 天 BBT 序列、经期记录（HealthKit menstrual flow，复用现有周期预测得出预期经期日）、症状库。

输出：`PregnancyInsight` 枚举 —— `insufficient` / `tracking(lutealDay: Int)` / `possible(reasons: [Reason])` / `likely(reasons: [Reason])`。reasons 用于 UI 展示解释（如"体温持续高位 16 天"）。

### 排卵定位（3-over-6 规则）

1. 取连续有效测温日序列（无干扰标记的条目为"有效"；有干扰标记的条目仅在无替代时使用且该次判定降一级置信）
2. 某日起连续 3 天 BBT ≥ 前 6 个有效日均值 + 0.2°C → 判定升温，**升温前最后一低温日为排卵日**
3. 数据不足 10 个有效日，或未检测到双相 → 无法定位排卵

### 提示等级规则

| 等级 | 条件（任一满足） | UI 动作 |
|---|---|---|
| tracking | 已定位排卵，高温相 < 12 天 | 显示"黄体期第 X 天"，不提示验孕 |
| possible | 高温相 ≥ 12 天且月经未至；或经期推迟 1–3 天 | 温和提示："现在可以用验孕棒检测了" |
| likely | 高温相 ≥ 16 天；或推迟 ≥ 4 天且当周期早孕症状（恶心/呕吐/疲倦/乳房胀痛/点滴出血）≥ 2 项 | 较强提示："建议尽快验孕确认" |

降级路径（无足够 BBT 无法定位排卵）：仅按"推迟天数 + 症状数"判定，且只出 possible 一档（推迟 ≥ 3 天且症状 ≥ 2），措辞更保守。

### 用户反馈闭环

提示卡附"记录验孕结果"：阳性 / 阴性 / 忽略。
- 阳性：停止提示，引导用户更新状态（本期只做记录与提示语变更，不做完整孕期模式）
- 阴性：本周期内不再提示；新周期（检测到新经期开始）后重置
- 忽略：7 天内不重复提示

## 模块 4：聊天症状抽取（BFF + LLM）

### BFF 新端点 `POST /v1/extract/symptoms`

- 鉴权、限流复用现有 proxy 机制
- 请求体：`{ "message": "<用户单条消息>", "language": "<locale>" }`
- BFF 转发 deepseek-chat，固定 system prompt 要求抽取症状，`temperature: 0`，`response_format: { type: "json_object" }`，`max_tokens: 300`
- 响应：`{ "symptoms": [{ "type": "nausea", "date_ref": "today" | "yesterday" | null }] }`，BFF 解析校验后透传；解析失败返回空数组

### App 侧 SymptomExtractor

- 时机：用户在 AI 助手发出消息后异步触发，只抽取**用户消息**，不抽取助手回复
- 客户端节流：消息长度 < 4 字跳过；同日已抽取过的消息不重复请求
- 失败静默，不影响聊天主链路，不重试（下条消息自然带来新机会）
- 抽取结果以 source = chatExtracted 写入症状库（参与去重）

**明确不做**：不把抽取塞进主聊天 prompt——会污染回复格式、增加主链路延迟和 max_tokens 压力。

## 模块 5：UI 与通知

- **首页备孕卡片**（仅备孕模式可见）：黄体期第 X 天 / 提示等级、BBT 近 14 天趋势迷你图、入口跳到录入页
- **BBT 录入页**：数字输入（一位小数）、干扰标记多选、"今早已测"状态
- **晨间提醒**：本地通知，用户可设时间（默认 7:00），文案避免在锁屏暴露敏感信息（用"该测体温啦"而非"备孕提醒"）
- **提示卡**：possible / likely 两档文案 + "记录验孕结果"按钮 + 免责声明"此功能不构成医疗诊断"

## 模块 6：合规与本地化

- 所有文案只出现"可能怀孕 / 建议验孕确认"，永不出现"你已怀孕"
- 首次开启备孕模式时展示一次性免责说明
- 7 语言文案走现有 lproj 流程（zh-Hans、zh-Hant、en、ja、ko、es、fr）

## 模块 7：错误处理

| 场景 | 行为 |
|---|---|
| BBT 数据不足（< 10 有效日） | insight = insufficient，UI 引导坚持测温，不出任何提示 |
| 缺测日 | 序列中标记 gap；3-over-6 窗口内 > 2 个 gap 则该窗口跳过 |
| 干扰标记日 | 绘图保留，定位时降权 |
| 抽取端点失败/超时 | 静默丢弃，不影响聊天 |
| HK 授权拒绝 | 纯本地模式，功能可用 |
| 用户关闭备孕模式 | 停止提醒与提示，数据保留 |

## 模块 8：测试

- **PregnancyInsightEngine 单测**（核心）：固定 BBT 序列构造场景 —— 正常未孕周期（高温相 12 天回落）、怀孕周期（高温相 ≥ 18 天）、黄体期短（< 10 天不出提示）、大量缺测、干扰标记日、无 BBT 降级路径、阴性反馈后本周期不再提示
- **SymptomExtractor 单测**：mock BFF 响应（正常 JSON / 空数组 / 畸形 JSON / 网络失败）
- **去重逻辑单测**：同日同症状多来源合并
- **BFF Go 单测**：端点鉴权、限流、DeepSeek 响应解析失败兜底

## 范围外（本期不做）

- Apple Watch 腕温 / 静息心率 / HRV 信号接入（用户群无手表，未来可作为信号增强）
- 完整孕期模式（阳性后的孕期追踪）
- 排卵预测窗口（本产品已有的周期预测不改动）
- 排卵试纸（LH）录入
