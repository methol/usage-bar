---
slug: research-index
title: 长期事实性调研索引
type: research-index
created: 2026-05-11
updated: 2026-05-11
---

# Research Notes

长期事实性调研。回答"业界怎么做"，不规定本项目要做什么。新增 spec 前若需引用某项调研，先看本目录是否已有。

| 文档 | 主题 | 状态 |
|---|---|---|
| [competitive-analysis.md](./competitive-analysis.md) | SessionWatcher × CodexBar 详细调研 + Swift 化产品路线 | 2026-05-11 完成 |

## 调研结论速览

**产品定位**：将 [SessionWatcher](https://www.sessionwatcher.com/) 的 UI/交互精致度 与 [CodexBar](https://github.com/steipete/CodexBar) 的功能广度/数据源健壮性 融合，全栈 Swift 原生。

**Phase 1（UI 升级，零架构变化）**
- 大字号 hero popover
- 菜单栏多显示模式（icon / percent / percent+趋势 / $+趋势）
- ▲▼ 趋势箭头（基于现有 30d history 计算）
- Pace tracking（On pace / In deficit / In reserve）

**Phase 2（数据深度）**
- 复用 Claude CLI 的 `~/.claude/.credentials.json` 与 Keychain `Claude Code-credentials`（零配置）
- 本地 JSONL 扫描算 30d cost（`~/.claude/projects/**/*.jsonl`）
- 多账号 `tokenAccounts`
- Apple Developer ID 公证

**Phase 3+（按反馈推进）**
- claude.ai 浏览器 cookie 回退
- `claude /usage` CLI PTY 兜底
- WidgetKit / CLI 工具
- 是否多 provider 化（建议保持 Claude-only 差异化定位）

详见 [competitive-analysis.md](./competitive-analysis.md) §4~§7。
