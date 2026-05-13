# Issue #19 诊断

- 链接:https://github.com/methol/usage-bar/issues/19
- 标题:[feat] Settings Provider 列表交互 + 菜单栏多 provider + Pace 显示

## 复现与定位

4 个独立 UI 改进点，均在 Settings / 菜单栏显示层：

1. **Provider 顺序调整**：`SettingsView.swift` `ProviderRow` 目前用 ↑/↓ 按钮。用户要求改为原生拖拽排序。
2. **菜单栏多 provider**：`UsageBarApp.body` 目前只有一个 `MenuBarExtra`（由 `menuBarProviderID` 选定）。用户要求所有已启用且已注册的 provider 各自在菜单栏出现一个 status item。
3. **所有 provider 支持开关**：与 F2 联动——Toggle 控制的是「popover tab + 后台刷新 + 菜单栏显示」三合一开关。设置页说明文字需更新。
4. **percent + pace 替换 percent + trend**：`MenuBarDisplayMode.percentWithTrend` 依赖 `historyService` 历史数据，体感不稳定。改为用已在 `UsageWindow` 里的 `resetsAt`/`windowDuration` 直接算 pace 偏差（超前/滞后 N%），更即时、更准确。

## 根因

- F1：原设计注释显式记录 "List + .onMove 在 grouped Form 里不稳定" 而用 fallback buttons。macOS 14 目标版本可通过 `.environment(\.editMode, .constant(.active))` + ForEach `.onMove` 解决。
- F2：`UsageBarApp.body` 写死单个 `MenuBarExtra`；需在同一 App body 里根据 `coordinator.enabledProviderIDs` 条件性加入第二个（Codex）status item。
- F3：Toggle 已实现，描述文字需与 F2 联动更新。
- F4：`MenuBarDisplayMode.percentWithTrend` 实现依赖 `historyService` ring buffer（需历史样本才有趋势），冷启动 / 无历史时空；`PaceCalculator.expectedPacePct` 只需 `resetsAt`/`windowDuration`，数据实时可用。

## 修复方案

### F1 — SettingsView.swift
- `ProviderRow` 去掉 ↑/↓ 按钮（简化行结构）。
- `Section("Providers")` 的 `ForEach` 加 `.onMove { coordinator.moveProvider(from:to:) }`。
- Section 加 `.environment(\.editMode, .constant(.active))` 显示拖拽柄。

### F2 — UsageBarApp.swift
- 保留第一个 `MenuBarExtra`（Claude，始终显示）。
- 在 App body 用 `if coordinator.enabledProviderIDs.contains(.codex) && coordinator.isAvailable(.codex)` 条件性加第二个 `MenuBarExtra`（Codex runtime）。
- 两个 status item 共享同一个 `PopoverView`（点击任意项均可操作全局设置）。
- 第一个 label 保留 `.task {...}` setup 初始化逻辑；第二个只显示用量。

### F3 — SettingsView.swift（接 F2）
- 去掉 `ProviderRow` 中的 ✓（`menuBarProviderID`）单选按钮——所有 enabled provider 都上菜单栏，不再需要"选哪个"。
- `ProviderCoordinator.menuBarProviderID` 和 `menuBarRuntime` 保留（不改数据模型，`UsageBarApp` 第一个 label 仍用 `coordinator.claude.runtime`）。
- 更新 Section 底部说明文字。

### F4 — MenuBarDisplayMode.swift + MenuBarLabel.swift
- `MenuBarDisplayMode`：移除 `.percentWithTrend`，增加 `.percentWithPace`（displayName: "Percent + pace"）。
- `MenuBarLabel`：删去 `historyService`、`showTrend` 参数；新增 `paceIndicatorText` / `paceColor` 计算属性，使用 `expectedPacePct(resetDate:windowDuration:)` 算实际 vs 期望偏差。

## 影响范围

- 修改文件（4 个，均在 app 代码层）：
  - `macos/Sources/UsageBar/MenuBarDisplayMode.swift`
  - `macos/Sources/UsageBar/MenuBarLabel.swift`
  - `macos/Sources/UsageBar/SettingsView.swift`
  - `macos/Sources/UsageBar/UsageBarApp.swift`
- 风险点：
  - F1 drag handle 在 macOS 14 grouped Form 的实际稳定性 —— 可在本地 `make app` 后手动验。
  - F2 条件 `MenuBarExtra` 在 App body 变化时的 scene 生命周期 —— SwiftUI @StateObject 观察 @Published 变化应能正确重建。
  - F4 移除 `.percentWithTrend` 导致已存 UserDefaults 旧值（`"percentWithTrend"`）无法匹配 → 回退默认 `.icon`（可接受，用户重选即可）。
- 测试计划：`cd macos && swift build -c release && swift test`；`make app` 后手动验证拖拽 + 多菜单栏 + pace 显示。

## 守护线自检

- [x] 不触碰凭证/密钥链路（OAuth、credentials.json、Sparkle 私钥、SU_FEED_URL）—— ✅ 无
- [x] 不引入新第三方依赖，不改 LICENSE，不改变开源/收费定位 —— ✅ 无
- [x] 不修改 docs/adr/ 下已 accepted 的 ADR，不修改 AGENTS.md 或母法 spec —— ✅ 无
- [x] 不在 UsageService 之外重复 fetch/auth/轮询逻辑 —— ✅ 无（只改 UI 层）
- [x] 不手改 Info.plist 里的版本号 —— ✅ 无
- [x] 单 issue 影响面不跨"app 代码/发版链路/治理文档"三大块，改动文件数大致 ≤ 5 —— ✅ 仅 app 代码，4 个文件

## 是否需要人工介入

- 结论：NO
- 理由：守护线全部通过；改动范围纯 UI 层，不涉及凭证/架构红线/受保护文件。
