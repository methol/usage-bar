# Changelog

本仓库的用户视角变更记录。由 AI 在发版 runbook 自动维护（详见 [`docs/runbooks/release.md`](./docs/runbooks/release.md) §5）。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

> 自 v0.0.7 起，本仓库与上游 `Blimp-Labs/claude-usage-bar` 独立编号 — 见 [ADR 0004](./docs/adr/0004-fork-divergence-from-blimp-labs.md)。
> v0.0.6 及之前的历史由上游维护，不在本 CHANGELOG 范围内。

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
