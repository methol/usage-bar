# v0.4.0 View 层现代化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 GCD 残留（2 处）、用 `.chartXSelection` 替换 chartOverlay+GeometryReader、将 PopoverView 5 个 `@ViewBuilder private var` 提升为 private nested struct，使其参与 SwiftUI structural diff。

**Architecture:** 纯重构，无新功能。4 个文件修改（UsageHeatmapView / SettingsView / UsageChartView / PopoverView），全部留在各自原文件。PopoverView 新增 5 个 private nested struct，与现有 `ProviderUsageArea` / `ProviderHistorySection` 模式完全一致。

**Tech Stack:** SwiftUI (macOS 14+), Swift Charts `.chartXSelection(value:)`, Swift Concurrency (`Task`, `Task.yield()`)

---

## 文件变更一览

| 文件 | 变更 |
|---|---|
| `Features/Popover/UsageHeatmapView.swift` | SC1: `.onAppear { DispatchQueue.main.async }` → `.task { await Task.yield(); ... }` |
| `Features/Settings/SettingsView.swift` | SC1: `focusSettingsWindow()` 内 `DispatchQueue.main.async` → `Task { @MainActor in }` |
| `Features/Popover/UsageChartView.swift` | SC2: 删 `chartOverlay { GeometryReader { ... } }` 23 行，加 `.chartXSelection(value: $hoverDate)` 1 行 |
| `Features/Popover/PopoverView.swift` | SC3: 5 个 `@ViewBuilder private var` → private nested struct；`body` 同步更新 |

---

## Task 1 — SC1：GCD 清理

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/UsageHeatmapView.swift:127-131`
- Modify: `macos/Sources/UsageBar/Features/Settings/SettingsView.swift:138-146`

### 1a — UsageHeatmapView：`.onAppear { DispatchQueue }` → `.task { await Task.yield() }`

- [ ] **修改 UsageHeatmapView.swift**

  将第 127–131 行从：
  ```swift
  .onAppear {
      DispatchQueue.main.async {
          withAnimation(.none) { proxy.scrollTo(lastIndex, anchor: .trailing) }
      }
  }
  ```
  改为：
  ```swift
  .task {
      await Task.yield()
      withAnimation(.none) { proxy.scrollTo(lastIndex, anchor: .trailing) }
  }
  ```
  `await Task.yield()` 强制协作挂起，确保 ScrollView 布局完成后再 `scrollTo`，等价于 `DispatchQueue.main.async` 的 next-runloop 延迟。

### 1b — SettingsView：`focusSettingsWindow()` GCD → Task

- [ ] **修改 SettingsView.swift**

  将第 138–146 行从：
  ```swift
  @MainActor
  private func focusSettingsWindow() {
      DispatchQueue.main.async {
          NSApp.activate(ignoringOtherApps: true)
          if let window = NSApp.windows.last(where: { $0.isVisible && $0.canBecomeKey }) {
              window.makeKeyAndOrderFront(nil)
              window.orderFrontRegardless()
          }
      }
  }
  ```
  改为：
  ```swift
  @MainActor
  private func focusSettingsWindow() {
      Task { @MainActor in
          NSApp.activate(ignoringOtherApps: true)
          if let window = NSApp.windows.last(where: { $0.isVisible && $0.canBecomeKey }) {
              window.makeKeyAndOrderFront(nil)
              window.orderFrontRegardless()
          }
      }
  }
  ```

### 1c — 验证 & 提交

- [ ] **验证无 GCD 残留**
  ```bash
  grep -rn "DispatchQueue.main.async" macos/Sources/UsageBar/
  # 期望：无命中
  ```

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!
  ```

- [ ] **Test 验证**
  ```bash
  cd macos && swift test 2>&1 | tail -5
  # 期望：Test Suite 'All tests' passed
  ```

- [ ] **提交**
  ```bash
  git add macos/Sources/UsageBar/Features/Popover/UsageHeatmapView.swift \
          macos/Sources/UsageBar/Features/Settings/SettingsView.swift
  git commit -m "$(cat <<'EOF'
  refactor(v0.4.0): SC1 GCD 清理 — DispatchQueue.main.async → Task

  - UsageHeatmapView: .onAppear { DispatchQueue } → .task { await Task.yield(); scrollTo }
    （Task.yield() 保证 next-runloop 语义，等价原 GCD 延迟）
  - SettingsView.focusSettingsWindow: DispatchQueue → Task { @MainActor in }
  - grep 验证：Sources/UsageBar 下无 DispatchQueue.main.async 残留

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 2 — SC2：chartXSelection 替换 GeometryReader

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/UsageChartView.swift:195-217`

### 2a — 删 chartOverlay+GeometryReader，加 chartXSelection

- [ ] **修改 UsageChartView.swift**

  将第 195–217 行整段删除：
  ```swift
  .chartOverlay { proxy in
      GeometryReader { geo in
          Rectangle()
              .fill(.clear)
              .contentShape(Rectangle())
              .onContinuousHover { phase in
                  switch phase {
                  case .active(let location):
                      guard let plot = proxy.plotFrame else {
                          hoverDate = nil
                          return
                      }
                      let plotOrigin = geo[plot].origin
                      let x = location.x - plotOrigin.x
                      if let date: Date = proxy.value(atX: x) {
                          hoverDate = date
                      }
                  case .ended:
                      hoverDate = nil
                  }
              }
      }
  }
  ```
  替换为（紧接在 `.chartPlotStyle { ... }` 之后）：
  ```swift
  .chartXSelection(value: $hoverDate)
  ```
  `.chartXSelection(value:)` (macOS 14+) 在 pointer hover 时直接将 X 轴插值写入 `$hoverDate`，hover 离开时写 nil。原有 `.overlay(alignment: .top) { if let iv = interpolated { tooltipView(...) } }` 的 tooltip 渲染不受影响（`hoverDate` 仍驱动 `interpolated` 计算）。

### 2b — 验证 & 提交

- [ ] **验证 GeometryReader 已清除**
  ```bash
  grep -n "GeometryReader" macos/Sources/UsageBar/Features/Popover/UsageChartView.swift
  # 期望：无命中
  ```

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!
  ```

- [ ] **Test 验证**
  ```bash
  cd macos && swift test 2>&1 | tail -5
  # 期望：Test Suite 'All tests' passed
  ```

- [ ] **提交**
  ```bash
  git add macos/Sources/UsageBar/Features/Popover/UsageChartView.swift
  git commit -m "$(cat <<'EOF'
  refactor(v0.4.0): SC2 chartXSelection 替换 chartOverlay+GeometryReader

  - 删除 23 行 chartOverlay { GeometryReader { onContinuousHover + plotFrame 坐标变换 }
  - 替换为单行 .chartXSelection(value: $hoverDate)（macOS 14+）
  - hoverDate 语义不变；tooltip overlay 渲染逻辑不动

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 3 — SC3a：BottomBarView + NoProvidersView（无外部状态依赖）

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`（在文件末、`colorForPct` 函数之前添加新 private struct）

### 3a — 添加 BottomBarView

`bottomBar` private var（当前第 237–261 行）引用了 `selectedProvider`、`coordinator`、`appUpdater`。提取后需 `@Binding`、两个 `@ObservedObject`。`settingsButton` 改为内联。

- [ ] **在 PopoverView.swift 的 `private var settingsButton` 定义（第 313 行）之前插入 `BottomBarView`**

  定位 `private var settingsButton` 之前、`// MARK: - 共用底部栏` 替换整段：

  将当前第 235–261 行（MARK 注释 + bottomBar var）替换为 `BottomBarView` 的 nested struct：
  ```swift
  // MARK: - 共用底部栏

  private struct BottomBarView: View {
      @Binding var selectedProvider: ProviderID
      @ObservedObject var coordinator: ProviderCoordinator
      @ObservedObject var appUpdater: AppUpdater

      var body: some View {
          HStack(spacing: 12) {
              SettingsLink { Text("Settings…") }
                  .buttonStyle(.borderless)
                  .font(.caption)
              Spacer()
              Button("Refresh") {
                  let id = selectedProvider
                  Task { await coordinator.refreshNow(id) }
              }
              .buttonStyle(.borderless)
              .font(.caption)
              if appUpdater.isConfigured {
                  Button("Check for Updates…") {
                      appUpdater.checkForUpdates()
                  }
                  .buttonStyle(.borderless)
                  .font(.caption)
                  .disabled(!appUpdater.canCheckForUpdates)
              }
              Button("Quit") { NSApplication.shared.terminate(nil) }
                  .buttonStyle(.borderless)
                  .font(.caption)
                  .foregroundStyle(.secondary)
          }
      }
  }
  ```

### 3b — 添加 NoProvidersView

将当前第 263–284 行（`@ViewBuilder private var noProvidersView`）替换为 nested struct：

- [ ] **将 `@ViewBuilder private var noProvidersView` 替换为 `NoProvidersView`**
  ```swift
  private struct NoProvidersView: View {
      var body: some View {
          VStack(spacing: 12) {
              Text("没有启用的供应商")
                  .font(.headline)
              Text("请在设置中至少启用一个供应商。")
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
              SettingsLink { Text("打开设置") }
                  .buttonStyle(.borderedProminent)
          }
          .padding()
          .frame(maxWidth: .infinity)
          Divider()
          HStack {
              Spacer()
              Button("Quit") { NSApplication.shared.terminate(nil) }
                  .buttonStyle(.borderless)
                  .font(.caption)
                  .foregroundStyle(.secondary)
          }
      }
  }
  ```

### 3c — Build 验证（还不改 body，两个新 struct 只是定义，不影响编译）

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!（新 struct 定义合法；此时 body 仍用旧 private var）
  ```

---

## Task 4 — SC3b：NotAuthenticatedView

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`

### 4a — 将 `@ViewBuilder private var notAuthenticatedView` 替换为 NotAuthenticatedView

当前第 286–311 行引用 `coordinator`、`claude`，并调用 `settingsButton`（改为内联）。

- [ ] **将 `@ViewBuilder private var notAuthenticatedView` 替换为 `NotAuthenticatedView`**
  ```swift
  private struct NotAuthenticatedView: View {
      @ObservedObject var coordinator: ProviderCoordinator
      @ObservedObject var claude: UsageService

      var body: some View {
          Text("未检测到有效的授权凭证")
              .font(.headline)
          Text("请在终端完成 Claude 授权后，点击「重新检测」或重启本应用。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
          Button("重新检测") {
              Task { await coordinator.claude.bootstrapFromCLIIfNeeded() }
          }
          .buttonStyle(.borderedProminent)
          .frame(maxWidth: .infinity)
          if let error = claude.lastError {
              Label(error, systemImage: "exclamationmark.triangle")
                  .foregroundStyle(.red)
                  .font(.caption)
          }
          Divider()
          HStack {
              SettingsLink { Text("Settings…") }
                  .buttonStyle(.borderless)
                  .font(.caption)
              Spacer()
              Button("Quit") { NSApplication.shared.terminate(nil) }
                  .buttonStyle(.borderless)
          }
      }
  }
  ```

### 4b — Build 验证

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!
  ```

---

## Task 5 — SC3c：ClaudeUsageAreaView

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`

### 5a — 将 `@ViewBuilder private var claudeUsageArea` 替换为 ClaudeUsageAreaView

当前第 183–233 行。引用 `coordinator.claude.runtime`、`historyService`、`usageStats`（`@EnvironmentObject`）、`appUpdater`、`bottomBar`（需改为 `@ViewBuilder` 闭包参数）。`computeTrend` 是 `Utilities/TrendCalculator.swift` 的 module-level 函数，nested struct 可直接调用。

- [ ] **将 `// MARK: - Claude 已登录的用量区` + `@ViewBuilder private var claudeUsageArea` 整段替换为 `ClaudeUsageAreaView`**
  ```swift
  // MARK: - Claude 已登录的用量区（与重构前 claudeUsageArea 内容/顺序一致）

  private struct ClaudeUsageAreaView<BottomBar: View>: View {
      @ObservedObject var coordinator: ProviderCoordinator
      @ObservedObject var historyService: UsageHistoryService
      /// 从环境读取 Claude 的本机费用统计（UsageBarApp 只注入 Claude 的 usageStats；
      /// codexStats 走构造参数从不进 env，无同类型碰撞，见 UsageBarApp.swift:13-26）。
      @EnvironmentObject var usageStats: UsageStatsService
      @ObservedObject var appUpdater: AppUpdater
      @ViewBuilder let bottomBar: () -> BottomBar

      var body: some View {
          // TODO(perf): trend/pace 在 body 每次重渲染都 O(n) 重算（v0.0.9/v0.0.11 G5 R2 noted）。
          let runtime = coordinator.claude.runtime
          let points = historyService.history.dataPoints
          let snap = runtime.snapshot
          let trend5h = computeTrend(currentPct: snap?.primaryWindow?.utilizationPct, points: points, metric: \.pct5h)
          let trend7d = computeTrend(currentPct: snap?.secondaryWindow?.utilizationPct, points: points, metric: \.pct7d)

          ProviderUsageSection(runtime: runtime, trendPrimary: trend5h, trendSecondary: trend7d)

          UsageCard {
              UsageChartSectionView(historyService: historyService, recentEvents: usageStats.recentEvents)
          }

          if !usageStats.dailySpend.isEmpty && !usageStats.dailySpend.allSatisfy({ $0.usd == 0 }) {
              UsageCard {
                  UsageHeatmapView(daySpends: usageStats.dailySpend, isInitializing: usageStats.isInitializing)
              }
          }

          if let error = runtime.lastError {
              UsageCard {
                  Label(error, systemImage: "exclamationmark.triangle")
                      .foregroundStyle(.red)
                      .font(.caption)
              }
          }

          if let updaterError = appUpdater.lastError {
              UsageCard {
                  Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle")
                      .foregroundStyle(.red)
                      .font(.caption)
              }
          }

          if let updated = runtime.lastUpdated {
              HStack(spacing: 12) {
                  Text("Updated \(updated, style: .relative) ago")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  Spacer()
              }
          }

          bottomBar()
      }
  }
  ```

### 5b — Build 验证

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!
  ```

---

## Task 6 — SC3d：ProviderAreaView + 更新 PopoverView.body

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`

### 6a — 将 `@ViewBuilder private var providerArea` 替换为 ProviderAreaView

当前第 53–83 行。引用 `selectedProvider`（→ `@Binding`）、`coordinator`、`codexStats`、`historyService`（透传给 `ClaudeUsageAreaView`）、`appUpdater`（透传给 `ClaudeUsageAreaView`）、`bottomBar`（→ `@ViewBuilder` 闭包）。

- [ ] **将 `// MARK: - Provider 内容区路由` + `@ViewBuilder private var providerArea` 整段替换为 `ProviderAreaView`**
  ```swift
  // MARK: - Provider 内容区路由

  private struct ProviderAreaView<BottomBar: View>: View {
      @Binding var selectedProvider: ProviderID
      @ObservedObject var coordinator: ProviderCoordinator
      @ObservedObject var historyService: UsageHistoryService
      @ObservedObject var codexStats: UsageStatsService
      @ObservedObject var appUpdater: AppUpdater
      @ViewBuilder let bottomBar: () -> BottomBar

      var body: some View {
          if selectedProvider == .claude && coordinator.availableIDs.contains(.claude) {
              ClaudeUsageAreaView(coordinator: coordinator,
                                  historyService: historyService,
                                  appUpdater: appUpdater,
                                  bottomBar: bottomBar)
          } else if coordinator.availableIDs.contains(selectedProvider),
                    let runtime = coordinator.runtime(for: selectedProvider) {
              let history: (service: UsageHistoryService, primaryLabel: String, secondaryLabel: String)? =
                  (selectedProvider == .codex
                      ? (coordinator.provider(.codex) as? CodexProvider).map { ($0.history, "Session", "Weekly") }
                      : nil)
              let costStats: UsageStatsService? = (selectedProvider == .codex ? codexStats : nil)
              let costContext: ProviderCostContext? = (selectedProvider == .codex
                  ? ProviderCostContext(pricing: OpenAIModelPriceTable.shared, displayName: { OpenAIPricing.displayName($0) })
                  : nil)
              ProviderUsageArea(runtime: runtime,
                                providerID: selectedProvider,
                                onBackToClaude: { selectedProvider = coordinator.availableIDs.first ?? .claude },
                                history: history,
                                costStats: costStats,
                                costContext: costContext,
                                bottomBar: bottomBar)
          } else {
              ProviderComingSoonView(provider: selectedProvider,
                                     onBackToClaude: { selectedProvider = coordinator.availableIDs.first ?? .claude })
          }
      }
  }
  ```

### 6b — 更新 PopoverView.body

- [ ] **将 PopoverView.body 的 `else { ... providerArea ... }` 分支和 `notAuthenticatedView`、`noProvidersView` 调用更新为新 struct**

  将 `var body: some View` 的 `VStack` 内容从：
  ```swift
  let claudeEnabled = coordinator.enabledProviderIDs.contains(.claude)
  if claudeEnabled && !claude.isAuthenticated {
      notAuthenticatedView
  } else if coordinator.availableIDs.isEmpty {
      noProvidersView
  } else {
      if claudeEnabled { AccountSwitcherView(service: claude) }
      ProviderTabBar(selection: $selectedProvider, availableIDs: coordinator.availableIDs)
      providerArea
  }
  ```
  改为：
  ```swift
  let claudeEnabled = coordinator.enabledProviderIDs.contains(.claude)
  if claudeEnabled && !claude.isAuthenticated {
      NotAuthenticatedView(coordinator: coordinator, claude: claude)
  } else if coordinator.availableIDs.isEmpty {
      NoProvidersView()
  } else {
      if claudeEnabled { AccountSwitcherView(service: claude) }
      ProviderTabBar(selection: $selectedProvider, availableIDs: coordinator.availableIDs)
      ProviderAreaView(
          selectedProvider: $selectedProvider,
          coordinator: coordinator,
          historyService: historyService,
          codexStats: codexStats,
          appUpdater: appUpdater
      ) {
          BottomBarView(selectedProvider: $selectedProvider,
                        coordinator: coordinator,
                        appUpdater: appUpdater)
      }
  }
  ```

### 6c — 清理：删除 settingsButton private var

`settingsButton` 已内联到 `BottomBarView` 和 `NotAuthenticatedView`，原 PopoverView 的 `private var settingsButton`（当前第 313–319 行）可以删除：

- [ ] **删除 PopoverView 的 `private var settingsButton`**（第 313–319 行）：
  ```swift
  // 删除这整段（已内联到各 struct）：
  private var settingsButton: some View {
      SettingsLink {
          Text("Settings…")
      }
      .buttonStyle(.borderless)
      .font(.caption)
  }
  ```

### 6d — 验证 @ViewBuilder private var 已全部消除

- [ ] **验证无残留 @ViewBuilder private var**
  ```bash
  grep -n "@ViewBuilder" macos/Sources/UsageBar/Features/Popover/PopoverView.swift
  # 期望输出：只有 ProviderUsageArea（let bottomBar）和各 struct 的 @ViewBuilder let bottomBar 行，
  # 不含 "private var"
  ```

### 6e — Build + Test 验证 & 提交

- [ ] **Build 验证**
  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  # 期望：Build complete!
  ```

- [ ] **Test 验证**
  ```bash
  cd macos && swift test 2>&1 | tail -10
  # 期望：Test Suite 'All tests' passed，无回归
  ```

- [ ] **提交 SC3**
  ```bash
  git add macos/Sources/UsageBar/Features/Popover/PopoverView.swift
  git commit -m "$(cat <<'EOF'
  refactor(v0.4.0): SC3 PopoverView 5 個 @ViewBuilder private var → private nested struct

  - BottomBarView: @Binding selectedProvider + 2 @ObservedObject（settingsButton 内联）
  - NoProvidersView: 无外部依赖
  - NotAuthenticatedView: @ObservedObject coordinator + claude（settingsButton 内联）
  - ClaudeUsageAreaView<BottomBar>: @EnvironmentObject usageStats + @ViewBuilder bottomBar
  - ProviderAreaView<BottomBar>: @Binding selectedProvider + 4 @ObservedObject + @ViewBuilder bottomBar
  - PopoverView.body 更新为调用新 struct；删除 settingsButton private var
  - grep 验证：PopoverView 无 "@ViewBuilder private var" 残留

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 7 — 最终验证（SC4）、PR 创建

**Files:** 无新改动

### 7a — 全量自动化检查

- [ ] **SC1 GCD 验证**
  ```bash
  grep -rn "DispatchQueue.main.async" macos/Sources/UsageBar/
  # 期望：无命中
  ```

- [ ] **SC2 GeometryReader 验证**
  ```bash
  grep -rn "GeometryReader" macos/Sources/UsageBar/Features/Popover/UsageChartView.swift
  # 期望：无命中
  ```

- [ ] **SC3 @ViewBuilder private var 验证**
  ```bash
  grep -n "@ViewBuilder" macos/Sources/UsageBar/Features/Popover/PopoverView.swift
  # 期望：不含 "private var"
  ```

- [ ] **Full build + test**
  ```bash
  cd macos && swift build -c release && swift test
  # 期望：Build complete! + Test Suite 'All tests' passed
  ```

- [ ] **Release artifacts**
  ```bash
  make release-artifacts
  bash macos/scripts/verify-release.sh macos/UsageBar.zip
  # 期望：全绿
  ```

### 7b — 手动 UI 目视检查（SC4 manual check）

`make app` 打包后打开 app，依次验证：

- [ ] Claude tab 正常加载（用量卡 / 折线图 / 热力图）
- [ ] Codex tab 正常加载（额度卡 / 折线图）
- [ ] **折线图 hover**：鼠标移入折线图时 tooltip / 竖线出现；移出时消失 —— `chartXSelection` 行为确认
- [ ] **热力图末尾自动滚动**：热力图打开时自动滚到最新一周 —— `Task.yield()` 延迟确认
- [ ] 未登录态（kill credentials.json 测试）：「未检测到有效的授权凭证」页面正常
- [ ] Settings 窗口 → 弹出聚焦（`focusSettingsWindow` Task 替换确认）
- [ ] 底部栏 Refresh / Quit / Check for Updates 可点击

### 7c — 更新 spec 状态 + PR

- [ ] **更新 spec SC1-SC4 全部 done=true**
  编辑 `docs/superpowers/specs/2026-05-13-view-layer-modernization.md`：
  将 4 个 `done: false` + `evidence: null` 改为 `done: true` + evidence（命令输出摘要）

- [ ] **提交 spec 更新**
  ```bash
  git add docs/superpowers/specs/2026-05-13-view-layer-modernization.md
  git commit -m "$(cat <<'EOF'
  docs: v0.4.0 spec SC1-SC4 全部 done=true

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **创建 PR（G5 review 前）**
  ```bash
  # 推送到 remote
  git push origin main

  # 如已在 main 上直接开发，改用分支方式（或 pr 工具）
  # 此项目历史上 PR 从 feat/vX.Y.Z-* 分支发；若未建分支，可回溯 cherry-pick 到分支后发 PR
  # 本 plan 假设直接 push + 从 main 发 PR（与 v0.3.x 历史一致）
  gh pr create \
    --title "feat(v0.4.0): View 层现代化 — GCD 清理 + chartXSelection + PopoverView 抽 struct" \
    --body "$(cat <<'EOF'
  ## Summary
  - SC1: UsageHeatmapView + SettingsView GCD → Task（`await Task.yield()` 保证 next-runloop 语义）
  - SC2: UsageChartView chartOverlay+GeometryReader（23 行）→ `.chartXSelection(value: $hoverDate)`（1 行）
  - SC3: PopoverView 5 个 `@ViewBuilder private var` → private nested struct（BottomBarView / NoProvidersView / NotAuthenticatedView / ClaudeUsageAreaView / ProviderAreaView）

  ## Test plan
  - [x] `swift build -c release` 绿
  - [x] `swift test` 全绿（无回归）
  - [x] `make release-artifacts` + `verify-release.sh` 绿
  - [x] 手动 UI 目视：Claude/Codex tab / hover / 热力图滚动 / 未登录态 全路径正常
  - [ ] G5 code review

  spec: [2026-05-13-view-layer-modernization](docs/superpowers/specs/2026-05-13-view-layer-modernization.md)
  version: [v0.4.0](docs/versions/v0.4.0-view-layer-modernization.md)

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  EOF
  )"
  ```

- [ ] **G5 code review（subagent 独立评审）**
  发给 general-purpose subagent，重点检查：
  - `ClaudeUsageAreaView` 的 `@EnvironmentObject` 流动（env 只有 Claude 的 usageStats）
  - `chartXSelection` hover 边界行为（离开图表区 → hoverDate=nil）
  - `Task.yield()` 等价性
  - `ProviderAreaView` 对 `ProviderUsageArea` 的 `bottomBar` 透传正确性
  - `@Binding var selectedProvider` 在 nested struct 中的双向写回

- [ ] **CI 绿后 merge**
  ```bash
  gh pr merge --squash --delete-branch
  ```
