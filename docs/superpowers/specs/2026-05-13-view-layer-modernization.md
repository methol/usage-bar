---
id: 2026-05-13-view-layer-modernization
title: View 层现代化：GCD 清理 + chartXSelection + PopoverView helper 抽 struct
status: draft
created: 2026-05-13
updated: 2026-05-13
owner: claude-code
model: claude-sonnet-4-6
target_version: v0.4.0
related_adrs: []
related_research: []
spec_criteria:
  - id: SC1
    criterion: |
      GCD 清理（2 处）：
      (a) `UsageHeatmapView.swift`：`.onAppear { DispatchQueue.main.async { withAnimation(.none) { proxy.scrollTo(...) } } }` 改为 `.task { withAnimation(.none) { proxy.scrollTo(lastIndex, anchor: .trailing) } }`；
      (b) `SettingsView.swift:focusSettingsWindow()`：`DispatchQueue.main.async { ... }` 改为 `Task { @MainActor in ... }`；
      evidence：`grep -rn "DispatchQueue.main.async" macos/Sources/UsageBar/` 无命中（此两处是仅剩的 GCD 调用）。
    done: false
    evidence: null
  - id: SC2
    criterion: |
      `UsageChartView.swift`：`.chartOverlay { proxy in GeometryReader { geo in ... } }` 整段替换为 `.chartXSelection(value: $hoverDate)` 修饰符（macOS 14+）；
      `hoverDate: Date?` 仍为 `@State` 驱动 overlay 渲染逻辑不变；
      evidence：`grep -rn "GeometryReader" macos/Sources/UsageBar/Features/Popover/UsageChartView.swift` 无命中；`cd macos && swift build -c release` 绿。
    done: false
    evidence: null
  - id: SC3
    criterion: |
      `PopoverView.swift` 中 5 个 `@ViewBuilder private var` helpers 全部改为 private nested struct：
      `providerArea` → `ProviderAreaView`（`@Binding var selectedProvider`；generic `<BottomBar: View>`）、
      `claudeUsageArea` → `ClaudeUsageAreaView`（`@EnvironmentObject var usageStats`；generic `<BottomBar: View>`）、
      `bottomBar` → `BottomBarView`（`@Binding var selectedProvider`）、
      `noProvidersView` → `NoProvidersView`（无外部依赖）、
      `notAuthenticatedView` → `NotAuthenticatedView`；
      所有新 struct 作为 private nested type 留在 `PopoverView.swift`；
      evidence：`grep -n "@ViewBuilder" macos/Sources/UsageBar/Features/Popover/PopoverView.swift` 输出不含 `private var`（`@ViewBuilder` 只剩 `ProviderUsageArea` 的 `let bottomBar`）；`cd macos && swift test` 全绿。
    done: false
    evidence: null
  - id: SC4
    criterion: |
      `cd macos && swift build -c release` + `swift test` 全绿（现有 272+ 测试无回归）；
      `make app` 成功后手动目视检查：Claude tab / Codex tab / 未登录态 / 无 provider 态 / 折线图 hover / 热力图横向滚动 全路径无异常。
    done: false
    evidence: null
automated_checks:
  - "SC_AUTO_BUILD: cd macos && swift build -c release"
  - "SC_AUTO_TEST: cd macos && swift test"
  - "SC_AUTO_NO_GCD: grep -rn 'DispatchQueue.main.async' macos/Sources/UsageBar/  # 应无命中"
  - "SC_AUTO_NO_GEOMREADER_CHARTVIEW: grep -rn 'GeometryReader' macos/Sources/UsageBar/Features/Popover/UsageChartView.swift  # 应无命中"
  - "SC_AUTO_NO_VIEWBUILDER_VAR: grep -n '@ViewBuilder' macos/Sources/UsageBar/Features/Popover/PopoverView.swift  # 输出不含 'private var'"
manual_checks:
  - "make app 后手动起 app，逐一目视：Claude tab 正常加载、Codex tab 正常加载、折线图 hover 高亮正常、热力图末尾自动滚动正常、Settings 窗口可弹出聚焦"
  - "G5 code review（subagent 独立判断；重点：PopoverView @EnvironmentObject 流动是否正确、chartXSelection 在 hover 态下 hoverDate nil 判断是否正确、GCD → task 的 MainActor 语义是否等价）"
reviews: []
---

# View 层现代化：GCD 清理 + chartXSelection + PopoverView helper 抽 struct

## 1. 背景与目标

v0.3.2 代码结构治理完成目录分层后，v0.4.0 针对 view 层做三类局部现代化改造，全部源自 v0.3.1 SwiftUI audit 识别的 medium 风险项：

1. **GCD 残留**：`DispatchQueue.main.async` 在 Swift Concurrency 项目里是反模式（`swift.md` 明确禁用）。两处遗留：`UsageHeatmapView` 的 scrollTo + `SettingsView` 的 window focus。
2. **GeometryReader 双层套娃**：`UsageChartView` 的 hover 交互用 `chartOverlay { proxy in GeometryReader { geo in } }` 做坐标转换，macOS 14+ 的 `.chartXSelection(value:)` 可一行替代全部逻辑，消除坐标空间转换。
3. **`@ViewBuilder private var`**：PopoverView 里 5 个 `@ViewBuilder private var` helper 不参与 SwiftUI 的结构化 diff，行为上等同于内联展开。已有 `ProviderUsageArea` / `ProviderHistorySection` / `ProviderCostArea` 先例（同文件 private nested struct），本 spec 将剩余 5 个补全。

**不引入新功能，不动凭证 / Sparkle / UsageService OAuth 链路，不改用户可见行为。**

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| GCD → task | `.task {}` / `Task { @MainActor in }` | `@MainActor` 语义等价，Swift Concurrency 项目标准用法 |
| hover 坐标 | `.chartXSelection(value: $hoverDate)` | macOS 14+ 内置，消除 proxy+GeometryReader 二重套娃 |
| PopoverView helpers | private nested struct（同文件） | 与现有 `ProviderUsageArea` 模式一致；不拆文件（它们与 PopoverView 强耦合） |
| SettingsView `Binding(get:set:)` | **不改** | 5 处均属合法用途（类型桥接 / compound Boolean / 含错误处理的 setter），改写成 `@State + onChange` 增加同步复杂性，违背 YAGNI |

## 3. 设计

### SC1 — GCD 清理

**`UsageHeatmapView.swift`（原 127-131 行）**：

```swift
// Before
.onAppear {
    DispatchQueue.main.async {
        withAnimation(.none) { proxy.scrollTo(lastIndex, anchor: .trailing) }
    }
}

// After
.task {
    withAnimation(.none) { proxy.scrollTo(lastIndex, anchor: .trailing) }
}
```

`.task` 在 SwiftUI view 的 lifecycle 上触发时机与 `.onAppear` 等价，且默认继承父视图的 `@MainActor` 隔离（`ScrollViewReader` 中 `proxy.scrollTo` 需在主线程，`.task` 的 `@MainActor` 继承保证这一点）。`DispatchQueue.main.async` 的"下一 runloop 延迟"语义在 `@MainActor .task` 里自然成立（task 在当前 turn 之后调度）。

**`SettingsView.swift`（原 139-145 行，`focusSettingsWindow()`）**：

```swift
// Before
@MainActor
private func focusSettingsWindow() {
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)
        ...
    }
}

// After
@MainActor
private func focusSettingsWindow() {
    Task { @MainActor in
        NSApp.activate(ignoringOtherApps: true)
        ...
    }
}
```

`Task { @MainActor in }` 与 `DispatchQueue.main.async` 语义等价：均在下一 async 调度点（= 下一 run loop turn）在主线程执行。函数签名不变，调用方不受影响。

### SC2 — chartXSelection

**`UsageChartView.swift`（原 195-217 行）**：

```swift
// Before（删除这整段）
.chartOverlay { proxy in
    GeometryReader { geo in
        Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard let plot = proxy.plotFrame else { hoverDate = nil; return }
                    let plotOrigin = geo[plot].origin
                    let x = location.x - plotOrigin.x
                    if let date: Date = proxy.value(atX: x) { hoverDate = date }
                case .ended:
                    hoverDate = nil
                }
            }
    }
}

// After（一行）
.chartXSelection(value: $hoverDate)
```

`chartXSelection(value:)` (macOS 14+)：pointer hover 时将 X 轴对应的插值写入 `hoverDate`，hover 离开时写 `nil`。等效替换原有坐标变换逻辑。原有 `hoverDate` 驱动的 chart overlay（tooltip / 竖线等）不受影响。

### SC3 — PopoverView helpers → private nested structs

全部新 struct 留在 `PopoverView.swift` 同文件（与 `ProviderUsageArea` 等保持一致），作为 `PopoverView` 的 private nested type。

**依赖关系（init 参数）**：

| 新 struct | 关键 init 参数 | 特殊处理 |
|---|---|---|
| `BottomBarView` | `@Binding var selectedProvider`、`@ObservedObject var coordinator`、`@ObservedObject var appUpdater` | `settingsButton` 3 行内联（不再引用 `self.settingsButton`） |
| `NoProvidersView` | 无 | 静态内容 |
| `NotAuthenticatedView` | `@ObservedObject var coordinator`、`@ObservedObject var claude` | 内联 settingsButton 代码 |
| `ClaudeUsageAreaView<BottomBar: View>` | `@ObservedObject var coordinator`、`@ObservedObject var historyService`、`@EnvironmentObject var usageStats`、`@ObservedObject var appUpdater`、`@ViewBuilder let bottomBar: () -> BottomBar` | `usageStats` 走 `@EnvironmentObject`（与 PopoverView 一致，避免同类型 double init） |
| `ProviderAreaView<BottomBar: View>` | `@Binding var selectedProvider`、`@ObservedObject var coordinator`、`@ObservedObject var codexStats`、`@ViewBuilder let bottomBar: () -> BottomBar` | 调用 `ClaudeUsageAreaView` 时透传 `bottomBar` |

**PopoverView.body 简化后**：

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 10) {
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
                codexStats: codexStats
            ) {
                BottomBarView(selectedProvider: $selectedProvider,
                              coordinator: coordinator,
                              appUpdater: appUpdater)
            }
        }
    }
    // ... modifiers 不变
}
```

`claudeUsageArea` 内的 `bottomBar` 调用：`ClaudeUsageAreaView` 接收 `@ViewBuilder let bottomBar` 并在 body 末尾调 `bottomBar()`，与 `ProviderUsageArea` 现有模式完全一致。

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🔧 | `Features/Popover/UsageHeatmapView.swift` | SC1 `.onAppear { DispatchQueue }` → `.task {}` |
| 🔧 | `Features/Settings/SettingsView.swift` | SC1 `focusSettingsWindow` GCD → Task；Binding 不改 |
| 🔧 | `Features/Popover/UsageChartView.swift` | SC2 删 `chartOverlay+GeometryReader`，加 `.chartXSelection` |
| 🔧 | `Features/Popover/PopoverView.swift` | SC3 5 个 `@ViewBuilder private var` → private nested struct |
| ✅ 不动 | `Providers/Claude/UsageService.swift` | 不触碰凭证 / polling 链路 |
| ✅ 不动 | `App/UsageBarApp.swift` | 无新 StateObject / 服务注入 |
| ✅ 不动 | `macos/scripts/verify-release.sh` | 受保护文件，不触碰 |

## 5. 风险 / Open questions

1. **`ClaudeUsageAreaView` 的 `@EnvironmentObject`**：`usageStats` 必须由 `UsageBarApp` 注入进 env（现有代码已做）。如果测试环境缺 EnvironmentObject 注入，单测会 crash。解决：现有测试不测 PopoverView 完整渲染，风险可控。
2. **`chartXSelection` hover 与原有 `onContinuousHover` 的细微差异**：`chartXSelection` 在图表边界外会写 `nil`；原实现只在找不到 plot 时写 `nil`。行为在正常使用范围内等价；边界情况下 `chartXSelection` 更保守（更快置 nil），是改进。
3. **`ProviderAreaView` 内 `@Binding var selectedProvider`**：`selectedProvider` 状态由 PopoverView 的 `@State` 持有，`ProviderAreaView` 通过 `@Binding` 读写。若 `ProviderAreaView` 的某路径需要更新 `selectedProvider`（如 back-to-claude button），直接写 `$selectedProvider` 即可，与原 `@State` 写法语义一致。

## 6. 后续工作（不在本 spec 范围）

- SettingsView `Binding(get:set:)` 改写（5 处均有合理存在理由，见 §2 决策摘要；若未来切 `@Observable` 可一并处理）
- `@Observable` 迁移（v0.5.0）
- `UsageService` 跨文件拆分（v0.5.0）

## 7. 引用

- 落地版本：[`docs/versions/v0.4.0-view-layer-modernization.md`](../../versions/v0.4.0-view-layer-modernization.md)
- 先例 struct：`PopoverView.ProviderUsageArea`、`PopoverView.ProviderHistorySection`、`PopoverView.ProviderCostArea`
