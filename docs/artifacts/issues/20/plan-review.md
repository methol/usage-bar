# AI 方案评审(Plan Review)

## 评审结论
- VERDICT: NEEDS_REVISION → 修订后 PASS
- 评审者：general-purpose subagent（独立会话）
- 评审日期：2026-05-13

## 关键反馈

1. `setupComplete` 写入在 UsageBarApp.swift 仍存在（孤儿写入），未在计划中提及清理。
2. notAuthenticatedView "重新检测"按钮直接 `await bootstrapFromCLIIfNeeded()`，可能短暂阻塞主线程（Keychain 读取）。
3. `isAwaitingCode` 分支为死代码（移除入口后不可达），应一并删除（包括 `CodeEntryView`）。
4. notAuthenticatedView 底部应加 SettingsLink，让用户在认证前也能进入设置。

## 应对

- **全部接受**：
  1. UsageBarApp.swift 删除 `setupComplete` 写入块（4 行）。
  2. "重新检测"使用 `Task { await coordinator.claude.bootstrapFromCLIIfNeeded() }` 模式（与 UsageBarApp .task 的现有调用模式一致；Keychain 阻塞为已知短暂 tradeoff，用户触发频率极低，接受）。
  3. 删除 `isAwaitingCode` 分支 + `CodeEntryView` 私有结构体。
  4. notAuthenticatedView 底部加 `settingsButton`（复用已有组件）。

## 是否需要人工介入
- 结论：NO
- 若 YES，阻塞原因：N/A
