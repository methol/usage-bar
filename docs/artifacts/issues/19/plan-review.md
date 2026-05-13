# AI 方案评审(Plan Review)

## 评审结论
- VERDICT: NEEDS_REVISION → 修订后 PASS
- 评审者: general-purpose subagent（独立会话）
- 评审日期: 2026-05-13

## 关键反馈

1. **F1 拖拽**：Form+List+.onMove 已知不稳定（旧代码 fallback 记录），建议拒绝。
2. **F2 条件 MenuBarExtra**：App.body 反应性 + .task 重复触发风险。
3. **F3 menuBarProviderID**：移除 UI 按钮但不清理数据模型会留下死代码。
4. **F4 rawValue 迁移**：percentWithTrend → percentWithPace 会让旧 UserDefaults 值回退 .icon。
5. **F4 Codex 字段**：担心 Codex 未填 resetsAt/windowDuration。

## 应对

- **接受并修订**：
  - F1：改用 `ForEach + .onMove` 直接在 Section 上（不嵌套 List），加 `.environment(\.editMode, .constant(.active))`；用户明确要求拖拽，此方案绕开已知 Form+List bug。
  - F4 rawValue：在 UsageBarApp .task 加一次性迁移（"percentWithTrend" → "percentWithPace"）。
- **接受说明**：
  - F2：SwiftUI @StateObject 变化确实触发 App.body 重算；.task 只放 Claude label，Codex label 无 task；安全解包用 `if let codexRuntime`。
  - F3：本次只移除 UI 按钮，不清理 ProviderCoordinator 数据模型（范围控制），待后续 issue 清理。
  - F4 Codex：已确认 CodexUsageModel.swift:121-122 明确填了两字段，有效。

## 是否需要人工介入
- 结论: NO
- 若 YES,阻塞原因: N/A
