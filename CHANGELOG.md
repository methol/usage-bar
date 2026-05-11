# Changelog

本仓库的用户视角变更记录。由 AI 在发版 runbook 自动维护（详见 [`docs/runbooks/release.md`](./docs/runbooks/release.md) §5）。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

> 自 v0.0.7 起，本仓库与上游 `Blimp-Labs/claude-usage-bar` 独立编号 — 见 [ADR 0004](./docs/adr/0004-fork-divergence-from-blimp-labs.md)。
> v0.0.6 及之前的历史由上游维护，不在本 CHANGELOG 范围内。

---

## [v0.0.8] — 2026-05-11

### 改进（Changed）

- **Popover 视觉重做**：5h 窗口提升为 hero 卡片（56pt 大字号数字 + 紧凑 reset countdown），7d 窗口降级为 secondary 卡片（28pt 数字）；不再四个窗口平权显示，更易一眼看懂当前最关键的指标
- **进度条改 capsule**：5h / 7d 进度条从默认 SwiftUI ProgressView 改为 Capsule 形状（高度 8pt，圆角与高度匹配），视觉与 hero 字号协调
- **Reset 时间紧凑显示**：原 SwiftUI 默认 `in 1 hour` 风格改为紧凑 `1h 23m` / `12m` / `<1m`，节省 hero 卡片空间；nil 与已过期时不显示
- **Popover 宽度** 340 → 360pt，容纳 hero 数字与 reset 标签
- 配色阈值与现有保持一致：< 60% 绿 / 60-80% 黄 / ≥ 80% 红
- Per-Model（Opus / Sonnet）/ Extra Usage / 历史图表 / 控制行均保留不变；OAuth 与数据层未触

### 内部（Internal）

- 新增 `UsageHeroCard.swift`（含 hero/secondary 两档尺寸 + CapsuleProgressBar 子组件 + Xcode `#Preview` 三档示例）
- 新增 `ResetCountdownFormatter.swift` 纯逻辑函数 + `ResetCountdownFormatterTests`（6 case，覆盖 ≥1h / 仅分钟 / nil / 已过期 / 亚分钟 / 60s 整点边界）
- spec 走完 G2 / G3 / G5 / G6 共四轮独立 reviewer review，每轮 verdict 与作者响应均记入 spec.reviews
- commit 拆分原则：spec 立项 / 底层组件 / PopoverView 接入 / G5 修订 / G6 收尾分离，便于单独 revert

### 参考

- 版本计划：[`docs/versions/v0.0.8-hero-popover.md`](./docs/versions/v0.0.8-hero-popover.md)
- 含 spec：`2026-05-11-hero-popover`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.0.7] — 2026-05-11

### 新增（Added）

- **文档治理框架**落地：研究 / 设计 spec / ADR / 版本路线 / 运维 runbook / 用户文档六大目录建立，配套模板与索引
- **AGENTS.md** 治理入口：所有 AI runner 进仓库的中立指南；含 5 分钟上手、文档地图、工作流、工具可用性 preflight、hard gates
- **4 份 ADR**：Swift 原生（0001）、Claude-only 差异化（0002）、AI 主导 + 人类辅助（0003）、与 Blimp-Labs 上游独立分叉（0004）
- **7 个 review gate**：G1~G7 完整覆盖调研、spec、plan、实施、PR、merge、release；含跨模型 / 跨 subagent reviewer 矩阵与不可用时 fallback 路径
- **版本路线 v0.0.7 ~ v1.0.0**：每个版本占位文件含 frontmatter 与 placeholder guardrail
- **v1.0.0 "稳定可用"硬清单**：14 条门槛（性能 / 能源 / 隐私 / a11y / 公证 / Sparkle / 数据源路径 / 测试覆盖率等）
- **CHANGELOG.md** 本文件：从此存在，AI 维护

### 改进（Changed）

- `CLAUDE.md`：顶部新增 governance 跳板指向 AGENTS.md；新增 *Project state* 与 *Before claiming work done* 两节；原技术细节（commands / architecture / mock server gotcha / style）保留不变

### 修复（Fixed）

- *（无代码变更）*

### 安全 / 隐私（Security）

- *（无代码变更，但 ADR 0004 修正了 README 中的发版 URL 指向以避免本仓库发版意外推送到上游 GitHub Pages 的潜在事故）*

### 内部（Internal）

- 业界竞品调研报告归档至 `docs/research/competitive-analysis.md`（含 SessionWatcher / CodexBar / ccusage / Claude-Code-Usage-Monitor 详细分析）
- spec 母法引入 17 条机器可判定的 spec_criteria（SC1~SC17）+ `## Verification log` 区块作为 G6 验收形式
- spec 母法已通过 G2 跨 session 独立 reviewer 审查（5 BLOCKING + 8 RECOMMENDED 全数受理，详见 spec §10 review response）

### 参考

- 版本计划：[`docs/versions/v0.0.7-docs-governance.md`](./docs/versions/v0.0.7-docs-governance.md)
- 含 spec：`2026-05-11-docs-governance`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)
