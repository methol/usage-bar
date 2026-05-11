# Runbook — Incident Response

> ⚠️ **Placeholder**：首次事故发生时填充实战经验。

## 触发条件

- 发版后 24h health check 失败（母法 §4.6 第 4 条）
- G7 失败导致 release 需 yank
- Anthropic OAuth usage endpoint 异常（500 / 401 持续）
- Sparkle appcast 5xx 或推送了错误 zip
- 用户报告核心崩溃 / 数据错乱

## 标准响应顺序

1. **确认范围**：是否所有用户受影响 / 仅某 macOS 版本 / 仅某 fetch 路径
2. **保留证据**：截图、日志、appcast 当前内容、Sparkle Diagnostics 输出
3. **决定动作**：
   - **回滚**：Sparkle appcast 撤回最新条目（在 GitHub Pages 上回退到上一个 commit）
   - **Yank tag**：GitHub Release 标 *pre-release* 或删除；version 文件 status → `yanked`
   - **HOTFIX**：紧急发 v0.X.Y+1，走简化 runbook
4. **写复盘**：在本 runbook append 一条 *Incident #N* 段落
5. **回到正常 cadence**：所有 incident 闭环后，恢复 v0.x 路线

## Hard gate

⚠️ 严重事故（数据泄露 / 错误更新推到生产 / 法律风险）**必须人类介入**（母法 §4.6 第 6 条）。

## Incident log

> AI 每次响应一次事故后 append 一条。

(尚无事故记录)

## 引用

- 母法 §4.6 hard gates
- [`release.md`](./release.md) §9 health check
