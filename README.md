# Cycle Life Advisor

基于 Apple 健康（经期等）数据，用 AI 生成**生活向建议**（饮食、运动、情绪等）的产品仓库。  
**非医疗产品**：不提供诊断或治疗；上架 App Store 时需配套免责声明与隐私说明。

## 状态

- **项目路径**：`~/Desktop/cycle_advisor`（在 Cursor 中用 **Open Folder** 打开此目录以便 `.cursor/rules` 生效）。
- **MVP 形态（已锁定）**：形式 **B** — iOS App + **HealthKit** 直读；决策与实施规格见 [`docs/PRODUCT_DECISIONS.md`](docs/PRODUCT_DECISIONS.md)、[`docs/MVP_TECH.md`](docs/MVP_TECH.md)。
- 历史形态对比（Web / 混合等）仍以 Cursor 计划文档为准。
- 产品方案（详细）：`~/.cursor/plans/经期数据_ai_分析产品方案_dff06c02.plan.md`（若路径不同，以本机 Cursor 计划为准）。

## 目录（规划）

| 路径 | 说明 |
|------|------|
| `docs/` | PRD、数据流、竞品与合规备忘 |
| `.cursor/rules/` | 项目级 Cursor 规则（文案与 HealthKit 纪律） |

## 本地开发

- **v0.1 技术栈**：Swift + SwiftUI + HealthKit（详见 [`docs/MVP_TECH.md`](docs/MVP_TECH.md)）。
- Xcode 工程可在后续迭代中加入本仓库或独立子目录；以 `MVP_TECH.md` 中的模块边界为准。

## 合规提醒（摘要）

- 用户界面与营销文案：避免「诊断 / 治疗 / 处方」；使用「建议 / 参考 / 生活小贴士」。
- 建议页需可见「重大健康决定请咨询医生」类提示。
- 若使用 HealthKit：在 App 内清楚展示读取的数据类型及用途；隐私政策与 App Store 声明一致。
