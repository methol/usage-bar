# ObservableObject → @Observable Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将全仓 9 个 `ObservableObject` 类迁移到 `@Observable` macro，删除不必要的 Combine 依赖，同步更新视图层 property wrappers。

**Architecture:** 单 PR，先改 Model/Service 层（7 个独立类 + 1 个新建文件 + 1 个删除），再改视图层（7 个文件）；中间阶段 swift build 会有编译错误，最终 Task 12 之后恢复全绿。`UsageHistoryService` 和 `ProviderCoordinator` 保留 `import Combine`（各有内部 `AnyCancellable` 非 ObservableObject 相关）。

**Tech Stack:** Swift 5.9+, macOS 14+, SwiftUI, `@Observable` macro（Observation framework），Combine（仅 ProviderCoordinator / UsageHistoryService 内部 timer）。

---

## 文件变更总览

| 文件 | 动作 |
|---|---|
| `Models/ProviderRuntime.swift` | 改：`@Observable` |
| `Services/UsageHistoryService.swift` | 改：`@Observable`，保留 `import Combine` |
| `Services/NotificationService.swift` | 改：`@Observable` |
| `Services/UsageStatsService.swift` | 改：`@Observable` |
| `App/AppUpdater.swift` | 改：`@Observable` |
| `Models/LaunchAtLoginModel.swift` | **新建**（从 SettingsView 提取） |
| `Providers/Claude/UsageService.swift` | 改：`@Observable`，删 `runtimeAuthSync`，`isAuthenticated` 加 `didSet` |
| `Services/ProviderCoordinator.swift` | 改：`@Observable`，保留 `import Combine` |
| `MenuBar/MultiMenuBarLabel.swift` | 改：删 `RuntimeAggregator` + aggregator wiring |
| `MenuBar/MenuBarLabel.swift` | 改：`@ObservedObject` → `let` |
| `Features/Popover/ProviderUsageSection.swift` | 改：`@ObservedObject` → `let` |
| `Features/Popover/UsageChartView.swift` | 改：`@ObservedObject` → `let` |
| `Features/Settings/SettingsView.swift` | 改：删 `LaunchAtLoginModel` 定义，`@StateObject` → `@State`，`@ObservedObject` → `let` |
| `Features/Popover/PopoverView.swift` | 改：`@ObservedObject`/`@EnvironmentObject` → `let`，补 `usageStats` 参数 |
| `App/UsageBarApp.swift` | 改：`@StateObject` → `@State`，移除 `.environmentObject`，补 `usageStats` 参数 |

---

## Task 1: 迁移 ProviderRuntime

**Files:**
- Modify: `macos/Sources/UsageBar/Models/ProviderRuntime.swift`

> 注意：Task 1~8 执行完后视图层有编译错误，到 Task 9~15 修复。

- [ ] **Step 1: 修改 ProviderRuntime.swift**

  将文件改为：

  ```swift
  import Foundation
  import Observation

  /// 一个 provider 的 UI 状态容器 —— 视图（popover 用量区 / 菜单栏 label）直接持有它。
  /// 由所属 `UsageProvider` 写入（`setSuccess` / `setError` / `clear` / `setConfigured`）。
  ///
  /// 错误时的 snapshot 取舍统一为：凭证类失败（401-ish / session 过期）`clearSnapshot: true`——
  /// 不留「旧卡片 + 过期错误」并存的歧义 UI；网络 / 5xx 类失败保留旧 snapshot 但显示错误文案。
  @MainActor
  @Observable
  final class ProviderRuntime {
      private(set) var snapshot: ProviderUsageSnapshot?
      private(set) var lastUpdated: Date?
      private(set) var lastError: String?
      private(set) var isConfigured: Bool

      init(isConfigured: Bool = false) {
          self.isConfigured = isConfigured
      }

      func setConfigured(_ value: Bool) {
          if isConfigured != value { isConfigured = value }
      }

      /// 一次成功拉取：写 snapshot + 刷新 lastUpdated + 清 lastError。
      func setSuccess(snapshot: ProviderUsageSnapshot, at date: Date = Date()) {
          self.snapshot = snapshot
          self.lastUpdated = date
          self.lastError = nil
      }

      /// 一次失败：设 lastError；`clearSnapshot` 为 true 时清空旧 snapshot（凭证类失败）连同 lastUpdated，否则保留。
      func setError(_ message: String, clearSnapshot: Bool) {
          self.lastError = message
          if clearSnapshot {
              self.snapshot = nil
              self.lastUpdated = nil
          }
      }

      /// 清空全部（登出 / 切账号 / session 失效等）。
      func clear() {
          self.snapshot = nil
          self.lastUpdated = nil
          self.lastError = nil
      }
  }
  ```

---

## Task 2: 迁移 UsageHistoryService

**Files:**
- Modify: `macos/Sources/UsageBar/Services/UsageHistoryService.swift`

- [ ] **Step 1: 头部替换**

  将文件开头三行：
  ```swift
  import Foundation
  import Combine
  import AppKit

  @MainActor
  class UsageHistoryService: ObservableObject {
      @Published var history = UsageHistory()
  ```
  改为：
  ```swift
  import Foundation
  import Combine
  import AppKit
  import Observation

  @MainActor
  @Observable
  class UsageHistoryService {
      var history = UsageHistory()
  ```

  > `import Combine` 保留：内部 `flushTimer: AnyCancellable?` 还在用。

---

## Task 3: 迁移 NotificationService

**Files:**
- Modify: `macos/Sources/UsageBar/Services/NotificationService.swift`

- [ ] **Step 1: 修改 class 声明和属性**

  将：
  ```swift
  @MainActor
  class NotificationService: ObservableObject {
      /// 0 = off, 5–100 = alert when window reaches this %.
      @Published private(set) var threshold5h: Int
      @Published private(set) var threshold7d: Int
      @Published private(set) var thresholdExtra: Int
  ```
  改为：
  ```swift
  @MainActor
  @Observable
  class NotificationService {
      /// 0 = off, 5–100 = alert when window reaches this %.
      private(set) var threshold5h: Int
      private(set) var threshold7d: Int
      private(set) var thresholdExtra: Int
  ```

  文件开头加 `import Observation`（在 `import Foundation` 后）。

---

## Task 4: 迁移 UsageStatsService

**Files:**
- Modify: `macos/Sources/UsageBar/Services/UsageStatsService.swift`

- [ ] **Step 1: 修改头部 + class 声明**

  将：
  ```swift
  import Foundation
  import Combine
  ```
  改为：
  ```swift
  import Foundation
  import Observation
  ```

  将：
  ```swift
  @MainActor
  final class UsageStatsService: ObservableObject {
      static let shared = UsageStatsService()

      @Published private(set) var rolling30d: CostSummary? = nil
      @Published private(set) var dailySpend: [DaySpend] = []
      @Published private(set) var monthlySpend: [MonthSpend] = []
      @Published private(set) var recentEvents: [StoredUsageEvent] = []
      @Published private(set) var isInitializing: Bool = true
  ```
  改为：
  ```swift
  @MainActor
  @Observable
  final class UsageStatsService {
      static let shared = UsageStatsService()

      private(set) var rolling30d: CostSummary? = nil
      private(set) var dailySpend: [DaySpend] = []
      private(set) var monthlySpend: [MonthSpend] = []
      private(set) var recentEvents: [StoredUsageEvent] = []
      private(set) var isInitializing: Bool = true
  ```

---

## Task 5: 迁移 AppUpdater

**Files:**
- Modify: `macos/Sources/UsageBar/App/AppUpdater.swift`

- [ ] **Step 1: 修改 class 声明和 @Published 属性**

  在文件头加 `import Observation`（在 `import Foundation` 后，`import Sparkle` 前）。

  将：
  ```swift
  @MainActor
  final class AppUpdater: ObservableObject {
      @Published private(set) var canCheckForUpdates = false
      @Published private(set) var isConfigured: Bool
      @Published private(set) var lastError: String?
  ```
  改为：
  ```swift
  @MainActor
  @Observable
  final class AppUpdater {
      private(set) var canCheckForUpdates = false
      private(set) var isConfigured: Bool
      private(set) var lastError: String?
  ```

  KVO observation block（`canCheckObservation = ...`）无需改动，`MainActor` dispatch 后 `self?.canCheckForUpdates = canCheck` 直接赋值到 `@Observable` 属性，语义完全一致。

---

## Task 6: 提取并迁移 LaunchAtLoginModel

**Files:**
- Create: `macos/Sources/UsageBar/Models/LaunchAtLoginModel.swift`
- Modify: `macos/Sources/UsageBar/Features/Settings/SettingsView.swift`（删除 class 定义）

- [ ] **Step 1: 新建 LaunchAtLoginModel.swift**

  ```swift
  import Foundation
  import ServiceManagement
  import Observation

  @MainActor
  @Observable
  final class LaunchAtLoginModel {
      private(set) var isEnabled = false
      private(set) var isSupported: Bool
      private(set) var message: String?

      init(bundleURL: URL = Bundle.main.bundleURL) {
          isSupported = supportsLaunchAtLoginManagement(appURL: bundleURL)

          guard isSupported else {
              message = "Install the app in Applications to manage launch at login."
              return
          }

          isEnabled = SMAppService.mainApp.status == .enabled
      }

      func setEnabled(_ enabled: Bool) {
          guard isSupported else { return }

          do {
              if enabled {
                  try SMAppService.mainApp.register()
              } else {
                  try SMAppService.mainApp.unregister()
              }
              isEnabled = enabled
              message = nil
          } catch {
              message = error.localizedDescription
          }
      }
  }
  ```

  > `supportsLaunchAtLoginManagement` 是 SettingsView.swift 里的 free function，迁移后仍在 SettingsView.swift 中，可见性不变。

- [ ] **Step 2: 从 SettingsView.swift 删除 LaunchAtLoginModel 定义**

  找到并删除 `SettingsView.swift` 中 `@MainActor final class LaunchAtLoginModel: ObservableObject { ... }` 整个 class body（约 194~228 行）。

  > 该 class 的 `import ServiceManagement` 行也在 SettingsView.swift 顶部——如果 SettingsView.swift 里没有其他 ServiceManagement 用法，将其删除；否则保留。
  
  检查：`grep -n "ServiceManagement\|SMAppService" macos/Sources/UsageBar/Features/Settings/SettingsView.swift`
  
  若 `SMAppService` 只在 `LaunchAtLoginModel` 里，则删除 `import ServiceManagement`。

---

## Task 7: 迁移 UsageService（删除 runtimeAuthSync）

**Files:**
- Modify: `macos/Sources/UsageBar/Providers/Claude/UsageService.swift`

- [ ] **Step 1: 修改 import + class 声明**

  将：
  ```swift
  import Foundation
  import Combine
  ```
  改为：
  ```swift
  import Foundation
  import Observation
  ```

  将：
  ```swift
  final class UsageService: ObservableObject {
      @Published var usage: UsageResponse?
      @Published var lastError: String?
      @Published var lastUpdated: Date?
      @Published var isAuthenticated = false
  ```
  改为：
  ```swift
  @Observable
  final class UsageService {
      var usage: UsageResponse?
      var lastError: String?
      var lastUpdated: Date?
      var isAuthenticated = false {
          didSet { runtime.setConfigured(isAuthenticated) }
      }
  ```

- [ ] **Step 2: 删除 runtimeAuthSync 属性和 init 中的 sink**

  删除属性：
  ```swift
  private var runtimeAuthSync: AnyCancellable?
  ```

  删除 `init` 末尾两行：
  ```swift
  // 保持 runtime.isConfigured 与 isAuthenticated 同步（@Published 订阅时会立刻发当前值）
  self.runtimeAuthSync = self.$isAuthenticated.sink { [runtime] authed in
      runtime.setConfigured(authed)
  }
  ```

  替换为（在 init 末尾，在 `self.runtime = ProviderRuntime()` 之后）：
  ```swift
  runtime.setConfigured(isAuthenticated)
  ```

  > 这确保 init 时 runtime 状态与 isAuthenticated 初始值同步，等效于旧 sink 的 `.initial` 行为。

- [ ] **Step 3: 删除 @Published pollingMinutes**

  将：
  ```swift
  @Published private(set) var pollingMinutes: Int
  ```
  改为：
  ```swift
  private(set) var pollingMinutes: Int
  ```

---

## Task 8: 迁移 ProviderCoordinator

**Files:**
- Modify: `macos/Sources/UsageBar/Services/ProviderCoordinator.swift`

- [ ] **Step 1: 修改 import + class 声明**

  在文件头加 `import Observation`（保留 `import Combine` 和 `import Foundation`）：
  ```swift
  import Foundation
  import Combine
  import Observation
  ```

  将：
  ```swift
  final class ProviderCoordinator: ObservableObject {
  ```
  改为：
  ```swift
  @Observable
  final class ProviderCoordinator {
  ```

- [ ] **Step 2: 移除三个 @Published，保留 didSet**

  将：
  ```swift
  @Published var orderedProviderIDs: [ProviderID] {
      didSet { defaults.set(orderedProviderIDs.map(\.rawValue), forKey: Self.providerOrderKey) }
  }
  ```
  改为：
  ```swift
  var orderedProviderIDs: [ProviderID] {
      didSet { defaults.set(orderedProviderIDs.map(\.rawValue), forKey: Self.providerOrderKey) }
  }
  ```

  类似地：
  ```swift
  // 将 @Published private(set) var enabledProviderIDs: Set<ProviderID> { ...
  private(set) var enabledProviderIDs: Set<ProviderID> {
      didSet { defaults.set(enabledProviderIDs.map(\.rawValue), forKey: Self.enabledProvidersKey) }
  }

  // 将 @Published private(set) var menuBarVisibleProviderIDs: Set<ProviderID> { ...
  private(set) var menuBarVisibleProviderIDs: Set<ProviderID> {
      didSet { defaults.set(menuBarVisibleProviderIDs.map(\.rawValue), forKey: Self.menuBarVisibleProvidersKey) }
  }
  ```

---

## Task 9: 删除 RuntimeAggregator，更新 MultiMenuBarLabel

**Files:**
- Modify: `macos/Sources/UsageBar/MenuBar/MultiMenuBarLabel.swift`

- [ ] **Step 1: 删除 RuntimeAggregator class**

  删除文件末尾整个 class（约 71~84 行）：
  ```swift
  /// 聚合多个 ProviderRuntime 的变化通知，驱动 MultiMenuBarLabel 在 icon 模式下感知任一 provider 数据刷新。
  @MainActor
  private final class RuntimeAggregator: ObservableObject {
      private var subscriptions = Set<AnyCancellable>()

      func update(runtimes: [ProviderRuntime]) {
          subscriptions.removeAll()
          for rt in runtimes {
              rt.objectWillChange
                  .sink { [weak self] _ in self?.objectWillChange.send() }
                  .store(in: &subscriptions)
          }
      }
  }
  ```

- [ ] **Step 2: 更新 MultiMenuBarLabel struct**

  将：
  ```swift
  import SwiftUI
  import Combine

  struct MultiMenuBarLabel: View {
      @ObservedObject var coordinator: ProviderCoordinator
      @StateObject private var aggregator = RuntimeAggregator()
      @AppStorage(MenuBarDisplayMode.storageKey) private var mode: MenuBarDisplayMode = .icon

      var body: some View {
          let ids = coordinator.menuBarVisibleIDs
          content(for: ids)
              .onAppear {
                  aggregator.update(runtimes: ids.compactMap { coordinator.runtime(for: $0) })
              }
              .onChange(of: ids) { _, newIds in
                  aggregator.update(runtimes: newIds.compactMap { coordinator.runtime(for: $0) })
              }
      }
  ```
  改为：
  ```swift
  import SwiftUI

  struct MultiMenuBarLabel: View {
      let coordinator: ProviderCoordinator
      @AppStorage(MenuBarDisplayMode.storageKey) private var mode: MenuBarDisplayMode = .icon

      var body: some View {
          let ids = coordinator.menuBarVisibleIDs
          content(for: ids)
      }
  ```

---

## Task 10: 更新 MenuBarLabel

**Files:**
- Modify: `macos/Sources/UsageBar/MenuBar/MenuBarLabel.swift`

- [ ] **Step 1: 移除 @ObservedObject**

  将：
  ```swift
  struct MenuBarLabel: View {
      @ObservedObject var runtime: ProviderRuntime
  ```
  改为：
  ```swift
  struct MenuBarLabel: View {
      let runtime: ProviderRuntime
  ```

---

## Task 11: 更新 ProviderUsageSection

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/ProviderUsageSection.swift`

- [ ] **Step 1: 移除 @ObservedObject**

  将：
  ```swift
  struct ProviderUsageSection: View {
      @ObservedObject var runtime: ProviderRuntime
  ```
  改为：
  ```swift
  struct ProviderUsageSection: View {
      let runtime: ProviderRuntime
  ```

---

## Task 12: 更新 UsageChartView

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/UsageChartView.swift`

- [ ] **Step 1: 移除所有 @ObservedObject**

  `UsageChartView.swift` 有两处 `@ObservedObject var historyService: UsageHistoryService`（行 68 和 102）。全部改为 `let historyService: UsageHistoryService`。

  运行：`grep -n "@ObservedObject" macos/Sources/UsageBar/Features/Popover/UsageChartView.swift`
  确认改完后输出为空。

---

## Task 13: 更新 SettingsView

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Settings/SettingsView.swift`

- [ ] **Step 1: 移除 @ObservedObject，改 @StateObject**

  将顶层 `SettingsWindowContent` 的：
  ```swift
  @ObservedObject var coordinator: ProviderCoordinator
  @ObservedObject var service: UsageService
  @ObservedObject var notificationService: NotificationService
  ```
  改为：
  ```swift
  let coordinator: ProviderCoordinator
  let service: UsageService
  let notificationService: NotificationService
  ```

  找到所有其他嵌套 struct 中的 `@ObservedObject var coordinator: ProviderCoordinator`（行 95 附近），同样改为 `let coordinator: ProviderCoordinator`。

- [ ] **Step 2: 更新 LaunchAtLoginToggle 的 @StateObject → @State**

  将：
  ```swift
  struct LaunchAtLoginToggle: View {
      @StateObject private var model: LaunchAtLoginModel
      ...
      init(...) {
          _model = StateObject(
              wrappedValue: LaunchAtLoginModel(bundleURL: bundleURL)
          )
  ```
  改为：
  ```swift
  struct LaunchAtLoginToggle: View {
      @State private var model: LaunchAtLoginModel
      ...
      init(...) {
          _model = State(
              wrappedValue: LaunchAtLoginModel(bundleURL: bundleURL)
          )
  ```

---

## Task 14: 更新 PopoverView（最大文件，363 行）

**Files:**
- Modify: `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`

- [ ] **Step 1: 更新顶层 PopoverView struct 属性**

  找到顶层 `PopoverView` struct（文件开头，约第 1~15 行），将：
  ```swift
  @ObservedObject var coordinator: ProviderCoordinator
  /// 单独 `@ObservedObject` —— 这样 `isAuthenticated`/`lastError`/`runtime` 变化能驱动重渲染
  /// （`coordinator` 的 `menuBarVisibleProviderIDs`/`orderedProviderIDs`/`enabledProviderIDs` 是 `@Published`，不覆盖 `coordinator.claude` 的变化）。
  @ObservedObject var claude: UsageService
  @ObservedObject var historyService: UsageHistoryService
  @ObservedObject var notificationService: NotificationService
  @ObservedObject var appUpdater: AppUpdater
  @EnvironmentObject var usageStats: UsageStatsService
  /// Codex 本机用量/费用统计（与 Claude 的 `usageStats` 同型；`@EnvironmentObject` 一次只能注一个同型，故这里走构造参数）。
  @ObservedObject var codexStats: UsageStatsService
  ```
  改为：
  ```swift
  let coordinator: ProviderCoordinator
  let claude: UsageService
  let historyService: UsageHistoryService
  let notificationService: NotificationService
  let appUpdater: AppUpdater
  let usageStats: UsageStatsService
  let codexStats: UsageStatsService
  ```

  同时删除顶部注释中提到 `@ObservedObject`/`@EnvironmentObject` 的行内注释（约行 6~7、13）。

- [ ] **Step 2: 更新所有嵌套 struct 的 @ObservedObject**

  运行：
  ```bash
  grep -n "@ObservedObject\|@EnvironmentObject" macos/Sources/UsageBar/Features/Popover/PopoverView.swift
  ```

  对每一处（包含行 66~69、106、156~157、185~186、205~206、267~268、323~324）：
  - `@ObservedObject var x: T` → `let x: T`

- [ ] **Step 3: 处理 @EnvironmentObject usageStats 传递链（3 层）**

  `usageStats` 原本通过 environment 跨三层传递：`PopoverView → ProviderAreaView → ClaudeUsageAreaView`。迁移后改为 init 参数逐层传递。

  **3a. `ClaudeUsageAreaView`（约行 204）：**
  将 `@EnvironmentObject var usageStats: UsageStatsService` 改为 `let usageStats: UsageStatsService`。

  **3b. `ProviderAreaView`（约行 64）：**
  添加 `let usageStats: UsageStatsService` 属性（位于现有属性列表末尾），并更新调用 `ClaudeUsageAreaView`（约行 74）补传：
  ```swift
  ClaudeUsageAreaView(coordinator: coordinator,
                      historyService: historyService,
                      usageStats: usageStats,
                      appUpdater: appUpdater,
                      bottomBar: bottomBar)
  ```

  **3c. `ProviderAreaView` 调用点（约行 26）：**
  补传 `usageStats: usageStats`：
  ```swift
  ProviderAreaView(
      selectedProvider: $selectedProvider,
      coordinator: coordinator,
      historyService: historyService,
      codexStats: codexStats,
      appUpdater: appUpdater,
      usageStats: usageStats
  ) { ... }
  ```

---

## Task 15: 更新 UsageBarApp（入口）

**Files:**
- Modify: `macos/Sources/UsageBar/App/UsageBarApp.swift`

- [ ] **Step 1: @StateObject → @State**

  将所有 `@StateObject private var` 改为 `@State private var`：
  ```swift
  @State private var coordinator = ProviderCoordinator(claude: UsageService(),
                                                        additionalProviders: [
                                                            CodexProvider(),
                                                            GeminiProvider()
                                                        ])
  @State private var historyService = UsageHistoryService()
  @State private var notificationService = NotificationService()
  @State private var appUpdater = AppUpdater()
  @State private var usageStats = UsageStatsService.shared
  @State private var codexStats = UsageStatsService(provider: .codex)
  ```

  > 注意：`UsageStatsService.shared` 是单例——`@State private var usageStats = UsageStatsService.shared` 将 App 级 `@State` 的引用指向同一个单例实例，语义不变。

- [ ] **Step 2: 移除 .environmentObject，补 usageStats 参数**

  将：
  ```swift
  PopoverView(
      coordinator: coordinator,
      claude: coordinator.claude,
      historyService: historyService,
      notificationService: notificationService,
      appUpdater: appUpdater,
      codexStats: codexStats
  )
  .environmentObject(usageStats)
  ```
  改为：
  ```swift
  PopoverView(
      coordinator: coordinator,
      claude: coordinator.claude,
      historyService: historyService,
      notificationService: notificationService,
      appUpdater: appUpdater,
      usageStats: usageStats,
      codexStats: codexStats
  )
  ```

---

## Task 16: 全量验证 + 自动化 grep 检查 + 提交

**Files:** 所有已修改文件

- [ ] **Step 1: swift build**

  ```bash
  cd macos && swift build -c release 2>&1 | tail -5
  ```
  预期：`Build complete!`

- [ ] **Step 2: 自动化 grep 检查（SC1~SC6）**

  ```bash
  # SC1 — 无 ObservableObject / @Published 残留
  ! grep -rn 'ObservableObject\|@Published' macos/Sources/UsageBar/ --include='*.swift' \
    && echo "SC1 PASS" || echo "SC1 FAIL"

  # SC2 — 无 @StateObject / @ObservedObject / @EnvironmentObject 残留
  ! grep -rn '@StateObject\|@ObservedObject\|@EnvironmentObject' macos/Sources/UsageBar/ --include='*.swift' \
    && echo "SC2 PASS" || echo "SC2 FAIL"

  # SC3 — RuntimeAggregator 已删
  ! grep -rn 'RuntimeAggregator' macos/Sources/UsageBar/ --include='*.swift' \
    && echo "SC3 PASS" || echo "SC3 FAIL"

  # SC4 — LaunchAtLoginModel 在新文件
  test -f macos/Sources/UsageBar/Models/LaunchAtLoginModel.swift \
    && echo "SC4 PASS" || echo "SC4 FAIL"

  # SC5 — UsageService 无 import Combine
  ! grep -n 'import Combine' macos/Sources/UsageBar/Providers/Claude/UsageService.swift \
    && echo "SC5a PASS" || echo "SC5a FAIL"

  # SC5 — MultiMenuBarLabel 无 import Combine
  ! grep -n 'import Combine' macos/Sources/UsageBar/MenuBar/MultiMenuBarLabel.swift \
    && echo "SC5b PASS" || echo "SC5b FAIL"

  # SC6 — runtimeAuthSync 已删
  ! grep -rn 'runtimeAuthSync' macos/Sources/UsageBar/ --include='*.swift' \
    && echo "SC6 PASS" || echo "SC6 FAIL"
  ```

- [ ] **Step 3: swift test**

  ```bash
  cd macos && swift test 2>&1 | tail -5
  ```
  预期：`Test Suite 'All tests' passed` 且 `0 failures`。

  若有 `@MainActor` 相关编译错误（测试类未标注但访问了 `@MainActor @Observable` 类），在对应测试 class 声明前加 `@MainActor`。

- [ ] **Step 4: make release-artifacts + verify**

  ```bash
  cd macos && make release-artifacts && bash scripts/verify-release.sh UsageBar.zip 2>&1 | tail -5
  ```
  预期：`Release archive looks good`。

- [ ] **Step 5: 提交**

  ```bash
  git add macos/Sources/UsageBar/ macos/Tests/
  git commit -m "$(cat <<'EOF'
  feat(v0.5.0): ObservableObject → @Observable 全仓迁移

  - 9 个类迁移到 @Observable macro，移除 ObservableObject + @Published
  - 视图层：@StateObject → @State，@ObservedObject → let，@EnvironmentObject → init 注入
  - RuntimeAggregator 整体删除（@Observable 原生追踪替代手动 Combine 聚合）
  - LaunchAtLoginModel 提取到 Models/LaunchAtLoginModel.swift 独立文件
  - UsageService.runtimeAuthSync 删除，改 isAuthenticated.didSet 同步 runtime
  - import Combine 从 UsageService / MultiMenuBarLabel 移除

  兑现 spec 2026-05-14-observable-migration SC1~SC8
  EOF
  )"
  ```

---

## 附录：编译顺序说明

Task 1~8 执行后，视图层（`@ObservedObject` / `@StateObject` / `@EnvironmentObject`）会有编译错误，这是预期状态。Task 9~15 修复视图层后恢复全绿。**不要在 Task 8 之后、Task 15 之前运行 `swift build`**，避免混淆错误信息。

若想中途验证进度，可运行：
```bash
cd macos && swift build 2>&1 | grep "error:" | wc -l
```
随 Task 推进，错误数应单调递减至 0。
