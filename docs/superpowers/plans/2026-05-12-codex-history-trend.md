# Codex 历史采样 + 趋势箭头 + 额度折线图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 让 Codex tab 显示历史折线图与趋势箭头（朝「和 Claude tab 一致」），并把 `UsageHistoryService` 泛化成 per-provider —— 全程不动 Claude 既有行为、不动菜单栏。

**Architecture:** `UsageHistoryService` 加 `init(filename:directory:)`（Claude 默认路径零变化）。`CodexProvider` 自持一个 `UsageHistoryService(filename: "history-codex.json")` + 一个 5 分钟轻量 refresh timer（`startPolling()`，幂等、`[weak self]`），每次成功拉取记一个 `(session%, weekly%)` 点。`UsageChartSectionView` 加 `primaryLabel`/`secondaryLabel` 参数（默认 `5h`/`7d`）。`PopoverView` 抽出 `ProviderHistorySection`（趋势 + 折线图），Codex 分支挂上它。`supportsBackgroundPolling` 保持 `false`（Codex 暂不进 Settings primary 下拉）。

**Tech Stack:** Swift 5.9 / SwiftUI / Swift Charts / Combine（`Timer.publish`）/ XCTest。命令：`cd macos && swift build -c release`、`cd macos && swift test`、`make release-artifacts`（repo 根）。

> 对应 spec：[`../specs/2026-05-12-codex-history-trend.md`](../specs/2026-05-12-codex-history-trend.md)（G2 approved）。所有命令默认 CWD 用绝对路径（`cd /Users/methol/data/code-methol/usage-bar/macos` / repo 根），因为 Bash 调用间 CWD 会重置。

---

## File Structure

- `macos/Sources/ClaudeUsageBar/UsageHistoryService.swift` — 改 `init` 收 `filename`/`directory`，文件路径由 `static historyFileURL` 变实例 `let fileURL`/`backupURL`。
- `macos/Sources/ClaudeUsageBar/UsageProvider.swift` — 仅改 `supportsBackgroundPolling` 的文档注释。
- `macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift` — 仅改 `primaryEligibleIDs` 的文档注释。
- `macos/Sources/ClaudeUsageBar/CodexProvider.swift` — 加 `let history`、`init(history:)` + `loadHistory()`、`recordHistorySample(from:)`、`startPolling()` + `pollCancellable`。
- `macos/Sources/ClaudeUsageBar/UsageChartView.swift` — `UsageChartSectionView` / `UsageChartContentView` 加 `primaryLabel`/`secondaryLabel`。
- `macos/Sources/ClaudeUsageBar/PopoverView.swift` — 新增 `ProviderHistorySection`；`ProviderUsageArea` 可选挂它；`providerArea` Codex 分支传 history。
- `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` — `.task` 里 `(coordinator.provider(.codex) as? CodexProvider)?.startPolling()`。
- `macos/Tests/ClaudeUsageBarTests/UsageHistoryServiceTests.swift` — 新建。
- `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` — 追加用例。

---

## Task 1: `UsageHistoryService(filename:directory:)`

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageHistoryService.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/UsageHistoryServiceTests.swift` (create)

- [x] **Step 1: 写失败测试 `UsageHistoryServiceTests.swift`**

```swift
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class UsageHistoryServiceTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testInitDefaultPathUnchanged() {
        let h = UsageHistoryService()
        XCTAssertEqual(h.fileURL.lastPathComponent, "history.json")
        XCTAssertEqual(h.backupURL.lastPathComponent, "history.bak.json")
        let parent = h.fileURL.deletingLastPathComponent()
        XCTAssertEqual(parent.lastPathComponent, "claude-usage-bar")
        XCTAssertEqual(parent.deletingLastPathComponent().lastPathComponent, ".config")
    }

    func testRecordFlushReloadCustomFile() throws {
        let h = UsageHistoryService(filename: "history-codex.json", directory: tmpDir)
        h.recordDataPoint(pct5h: 0.5, pct7d: 0.2)
        h.flushToDisk()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("history-codex.json").path))
        let h2 = UsageHistoryService(filename: "history-codex.json", directory: tmpDir)
        h2.loadHistory()
        XCTAssertEqual(h2.history.dataPoints.count, 1)
        XCTAssertEqual(h2.history.dataPoints.first?.pct5h, 0.5)
        XCTAssertEqual(h2.history.dataPoints.first?.pct7d, 0.2)
    }

    func testTwoFilenamesNoCollision() {
        let a = UsageHistoryService(filename: "history.json", directory: tmpDir)
        let b = UsageHistoryService(filename: "history-codex.json", directory: tmpDir)
        a.recordDataPoint(pct5h: 0.1, pct7d: 0.1); a.flushToDisk()
        b.recordDataPoint(pct5h: 0.9, pct7d: 0.9); b.flushToDisk()
        let a2 = UsageHistoryService(filename: "history.json", directory: tmpDir); a2.loadHistory()
        let b2 = UsageHistoryService(filename: "history-codex.json", directory: tmpDir); b2.loadHistory()
        XCTAssertEqual(a2.history.dataPoints.count, 1)
        XCTAssertEqual(a2.history.dataPoints.first?.pct5h, 0.1)
        XCTAssertEqual(b2.history.dataPoints.count, 1)
        XCTAssertEqual(b2.history.dataPoints.first?.pct5h, 0.9)
    }

    func testLoadCorruptFileMovesToBak() throws {
        try Data("{ not json".utf8).write(to: tmpDir.appendingPathComponent("history-codex.json"))
        let h = UsageHistoryService(filename: "history-codex.json", directory: tmpDir)
        h.loadHistory()
        XCTAssertTrue(h.history.dataPoints.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("history-codex.bak.json").path))
    }
}
```

- [x] **Step 2: 跑测试确认失败**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift test --filter UsageHistoryServiceTests`
Expected: 编译失败（`fileURL`/`backupURL` 不存在、`init(filename:directory:)` 不存在）。

- [x] **Step 3: 改 `UsageHistoryService.swift`**

把 `private static var historyFileURL: URL { … }` 删除，改成：

```swift
    /// 写到哪个文件（默认 `~/.config/claude-usage-bar/history.json` —— Claude 历史；
    /// Codex 用 `history-codex.json`）。`internal` 而非 `private`：单测要断言默认路径未变。
    let fileURL: URL
    /// 解析失败时把坏文件挪走的备份名（`<base>.bak.json`），由 `fileURL` 派生。
    let backupURL: URL

    private static var defaultDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(filename: String = "history.json", directory: URL? = nil) {
        let dir: URL
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            dir = directory
        } else {
            dir = Self.defaultDirectory
        }
        self.fileURL = dir.appendingPathComponent(filename)
        self.backupURL = self.fileURL.deletingPathExtension().appendingPathExtension("bak.json")

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.flushToDisk() }
        }
    }
```

然后在 `loadHistory()` / `flushToDisk()` 里把 `Self.historyFileURL` → `fileURL`；`loadHistory()` 里把 `let backup = url.deletingPathExtension().appendingPathExtension("bak.json")` 那行删掉、直接用 `backupURL`（`url` 局部变量改成直接用 `fileURL`）。逻辑其余不动。注意 `init` 里原来的 `terminationObserver` 赋值要保留（上面已含）。

- [x] **Step 4: 跑测试确认通过**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift test --filter UsageHistoryServiceTests`
Expected: 4 tests PASS。

- [x] **Step 5: 全量 build + test（确认 Claude 路径零回归）**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS（既有 `UsageChartInterpolationTests` 等不受影响）。

- [x] **Step 6: Commit**

```bash
cd /Users/methol/data/code-methol/usage-bar
git add macos/Sources/ClaudeUsageBar/UsageHistoryService.swift macos/Tests/ClaudeUsageBarTests/UsageHistoryServiceTests.swift
git commit -m "feat: v0.2.8 — UsageHistoryService 改可指定 filename/directory（Claude 默认路径零变化）+ 补单测 [spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `CodexProvider` —— 自持 history + 记点 + startPolling

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/CodexProvider.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` (append)

- [x] **Step 1: 写失败测试（追加到 `CodexProviderTests.swift` 类内，`// MARK: - v0.2.8 history sampling` 段）**

复用文件里已有的 `makeCodexHome(authJSON:)` 与 `stubSession(_:)` helper。新建 history 用临时目录。

```swift
    // MARK: - v0.2.8 history sampling

    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 两个窗口的 wham/usage JSON：primary(5h) used X%、secondary(7d) used Y%。
    private func usageJSON(primaryPct: Int, secondaryPct: Int) -> String {
        """
        { "plan_type": "plus",
          "rate_limit": {
            "primary_window":   { "used_percent": \(primaryPct), "reset_at": 1, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": \(secondaryPct), "reset_at": 1, "limit_window_seconds": 604800 } } }
        """
    }

    @MainActor
    func testSupportsBackgroundPollingIsFalse() {
        XCTAssertFalse(CodexProvider().supportsBackgroundPolling)
    }

    @MainActor
    func testRefreshSuccessRecordsHistorySample() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(self.usageJSON(primaryPct: 40, secondaryPct: 60).utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let h = UsageHistoryService(filename: "t.json", directory: try makeTmpDir())
        let p = CodexProvider(environment: env, session: session, history: h)
        await p.refreshNow()
        XCTAssertEqual(h.history.dataPoints.count, 1)
        XCTAssertEqual(h.history.dataPoints.first?.pct5h ?? -1, 0.40, accuracy: 1e-9)
        XCTAssertEqual(h.history.dataPoints.first?.pct7d ?? -1, 0.60, accuracy: 1e-9)
    }

    @MainActor
    func testRefreshFreePlanRecordsZeroSession() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        // Free 计划：只有 weekly 窗口（limit_window_seconds 604800），无 5h —— normalizedWindows() 的 session 为 nil。
        let body = #"{ "plan_type": "free", "rate_limit": { "primary_window": { "used_percent": 55, "reset_at": 1, "limit_window_seconds": 604800 } } }"#
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let h = UsageHistoryService(filename: "t.json", directory: try makeTmpDir())
        let p = CodexProvider(environment: env, session: session, history: h)
        await p.refreshNow()
        // 前提自检：snapshot 里 session 窗口确实缺、weekly 在
        XCTAssertNil(p.runtime.snapshot?.primaryWindow?.utilizationPct)
        XCTAssertEqual(p.runtime.snapshot?.secondaryWindow?.utilizationPct, 55)
        XCTAssertEqual(h.history.dataPoints.count, 1)
        XCTAssertEqual(h.history.dataPoints.first?.pct5h ?? -1, 0.0, accuracy: 1e-9)
        XCTAssertEqual(h.history.dataPoints.first?.pct7d ?? -1, 0.55, accuracy: 1e-9)
    }

    @MainActor
    func testRefreshFailureRecordsNothing() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { CodexStubURLProtocol.handler = nil }
        let h = UsageHistoryService(filename: "t.json", directory: try makeTmpDir())
        let p = CodexProvider(environment: env, session: session, history: h)
        await p.refreshNow()
        XCTAssertTrue(h.history.dataPoints.isEmpty)
        XCTAssertNotNil(p.runtime.lastError)
    }

    @MainActor
    func testRefreshNoCredentialsRecordsNothing() async throws {
        let env = try makeCodexHome(authJSON: nil)   // 目录在、auth.json 不在
        let h = UsageHistoryService(filename: "t.json", directory: try makeTmpDir())
        let p = CodexProvider(environment: env, session: .shared, history: h)
        await p.refreshNow()
        XCTAssertTrue(h.history.dataPoints.isEmpty)
        XCTAssertNil(p.runtime.snapshot)
    }

    @MainActor
    func testStartPollingIsIdempotent() {
        let p = CodexProvider(environment: ["CODEX_HOME": "/nonexistent-\(UUID().uuidString)"], session: .shared)
        XCTAssertFalse(p.isPolling)
        p.startPolling()
        XCTAssertTrue(p.isPolling)
        p.startPolling()   // 第二次：无副作用、不崩
        XCTAssertTrue(p.isPolling)
    }
```

> 注意：`testRefreshFreePlanRecordsZeroSession` 假定「`limit_window_seconds == 604800` 的单窗口会被 `normalizedWindows()` 归到 weekly、session 为 nil」。实施时先看 `CodexUsageModel.normalizedWindows()` 的实际行为确认（spec §2 提到 v0.2.6 G5 加了「按 windowSeconds 升序兜底」）。若实际把单个 604800 窗口归到了 session，调整断言或换更明确的 fixture（如显式给一个 secondary_window）。

- [x] **Step 2: 跑测试确认失败**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift test --filter CodexProviderTests`
Expected: 编译失败（`CodexProvider.init(environment:session:history:)`、`.history`、`.isPolling`、`.startPolling()` 不存在）。

- [x] **Step 3: 改 `CodexProvider.swift`**

```swift
import Foundation
import Combine

@MainActor
final class CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let runtime = ProviderRuntime()
    /// 仍 false —— 见 spec §2/SC3：该 flag = 「菜单栏 primary 候选资格」；本版本菜单栏渲染尚未 provider-aware，
    /// Codex 暂不进 Settings primary 下拉。Codex 自己**有** refresh timer（`startPolling()`，下方），只是不靠它上菜单栏。
    let supportsBackgroundPolling = false

    /// 本 provider 的历史样本（与 Claude 的 `history.json` 同结构，不同文件）。
    let history: UsageHistoryService

    var isConfigured: Bool { runtime.isConfigured }

    private let environment: [String: String]
    private let session: URLSession

    /// 后台采样 timer（仿 `UsageHistoryService` 的 `Timer.publish().autoconnect().sink`）。
    /// `CodexProvider` 生命周期 = app 生命周期，与 `UsageHistoryService` 一样不在 deinit 显式 cancel。
    private var pollCancellable: AnyCancellable?
    static let pollIntervalSeconds: TimeInterval = 300
    /// 单测可见：`startPolling()` 是否已起 timer。
    var isPolling: Bool { pollCancellable != nil }

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         session: URLSession = .shared,
         history: UsageHistoryService = UsageHistoryService(filename: "history-codex.json")) {
        self.environment = environment
        self.session = session
        self.history = history
        let present = ((try? CodexCredentialStore.load(environment: environment)) ?? nil) != nil
        runtime.setConfigured(present)
        history.loadHistory()
    }

    /// 起 5 分钟的轻量后台采样（幂等）；调用即先拉一次。装配处（`ClaudeUsageBarApp`）显式调用。
    func startPolling() {
        guard pollCancellable == nil else { return }
        Task { [weak self] in await self?.refreshNow() }
        pollCancellable = Timer.publish(every: Self.pollIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.refreshNow() } }
    }

    func refreshNow() async {
        let creds: CodexCredentials?
        do {
            creds = try CodexCredentialStore.load(environment: environment)
        } catch {
            runtime.setConfigured(false)
            runtime.setError("未检测到有效的 Codex 凭证，请在终端运行 `codex` 登录", clearSnapshot: true)
            return
        }
        guard let creds else {
            runtime.setConfigured(false)
            runtime.clear()
            return
        }
        runtime.setConfigured(true)
        do {
            let response = try await CodexUsageClient.fetchUsage(credentials: creds, session: session)
            let snapshot = response.asProviderSnapshot()
            runtime.setSuccess(snapshot: snapshot)
            recordHistorySample(from: snapshot)
        } catch CodexUsageError.unauthorized {
            runtime.setError("Codex 凭证已过期，请在终端运行 `codex` 重新登录", clearSnapshot: true)
        } catch {
            runtime.setError("无法获取 Codex 用量（稍后重试）", clearSnapshot: false)
        }
    }

    /// 把一次成功拉取的 (session%, weekly%) 落进历史：`pct5h↔session`、`pct7d↔weekly`（沿用 `UsageDataPoint` 既有字段名）。
    /// 缺失的窗口按 0 记（如 Free 计划只有 weekly）；两个都缺则不记。百分比 0...100 → 0...1。
    private func recordHistorySample(from snap: ProviderUsageSnapshot) {
        let p = snap.primaryWindow?.utilizationPct
        let s = snap.secondaryWindow?.utilizationPct
        guard p != nil || s != nil else { return }
        history.recordDataPoint(pct5h: (p ?? 0) / 100.0, pct7d: (s ?? 0) / 100.0)
    }
}
```

- [x] **Step 4: 跑测试确认通过**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift test --filter CodexProviderTests`
Expected: 全部 PASS（含新增 6 个 + 既有的）。若 `testRefreshFreePlanRecordsZeroSession` 的前提自检失败 → 按 Step 1 末尾的说明调 fixture。（注：G3 review 已确认 `normalizedWindows()` 把单个 604800 窗口归到 weekly、primary 为 nil —— 断言正确，那段 hedge 多半用不上。）

- [x] **Step 5: 全量 build + test（G4 gate）**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS。

- [x] **Step 6: Commit**

```bash
cd /Users/methol/data/code-methol/usage-bar
git add macos/Sources/ClaudeUsageBar/CodexProvider.swift macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift
git commit -m "feat: v0.2.8 — CodexProvider 自持 history-codex.json + 成功拉取记 (session%,weekly%) 点 + startPolling 5 分钟轻量 timer（幂等、[weak self]）[spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `UsageChartSectionView` —— 可参数化的两条线 label

> 本 Task 无新增单测（纯 SwiftUI 参数化，repo 无 ViewInspector）—— 由 `swift build` + Task 6 的 `manual_checks`（SC5）覆盖；`UsageChartInterpolation` 静态函数的回归由既有 `UsageChartInterpolationTests` 守。

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageChartView.swift`

- [x] **Step 1: 改 `UsageChartView.swift`**

`UsageChartSectionView`：

```swift
struct UsageChartSectionView: View {
    @ObservedObject var historyService: UsageHistoryService
    let recentEvents: [StoredUsageEvent]
    var primaryLabel: String = "5h"
    var secondaryLabel: String = "7d"

    @State private var selectedRange: TimeRange = .day1
    // costSummary 不变 …

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PillPicker(items: TimeRange.allCases, selection: $selectedRange) { $0.rawValue }
            UsageChartContentView(historyService: historyService, selectedRange: selectedRange,
                                  primaryLabel: primaryLabel, secondaryLabel: secondaryLabel)
            if let cost = costSummary { LocalCostCard(summary: cost) }
        }
    }
}
```

`UsageChartContentView`：加 `let primaryLabel: String`、`let secondaryLabel: String`；在 `chartView(points:)` 里：
- 第一条 `LineMark` 的 `.foregroundStyle(by: .value("Window", "5h"))` → `.foregroundStyle(by: .value("Window", primaryLabel))`
- 第二条 `LineMark` 的 `.foregroundStyle(by: .value("Window", "7d"))` → `.foregroundStyle(by: .value("Window", secondaryLabel))`
- `.chartForegroundStyleScale(["5h": Color.blue, "7d": Color.orange])` → `.chartForegroundStyleScale([primaryLabel: Color.blue, secondaryLabel: Color.orange])`
- `tooltipView` 的两个 `Label`：文字本来就只是百分比（`"\(Int(round(pct5h*100)))%"`），不含 label 名 → **不改**（颜色蓝/橙保持）。`PointMark` 颜色也不改。

> 仅这几处字面量替换；颜色映射、插值、hover、轴、`frame(height:120)` 全不动。Claude 调用点（`PopoverView.claudeUsageArea` 里的 `UsageChartSectionView(historyService:recentEvents:)`）走默认参数 `"5h"`/`"7d"` —— 不变。

- [x] **Step 2: build**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release`
Expected: OK。

- [x] **Step 3: 全量 build + test（G4 gate）**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS（含 `UsageChartInterpolationTests` —— 本改动不碰其测的静态函数，回归确认）。

- [x] **Step 4: Commit**

```bash
cd /Users/methol/data/code-methol/usage-bar
git add macos/Sources/ClaudeUsageBar/UsageChartView.swift
git commit -m "feat: v0.2.8 — UsageChartSectionView 加 primaryLabel/secondaryLabel 参数（默认 5h/7d，Claude 调用点不变），为 Codex 折线图复用 [spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `PopoverView` —— `ProviderHistorySection` + Codex 分支挂上

> 本 Task 无新增单测（纯 SwiftUI 视图组合，repo 无 ViewInspector）—— 由 `swift build` + Task 6 的 `manual_checks`（SC4/SC5）覆盖；`computeTrend` 本身由既有 `TrendCalculatorTests` 守。

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/PopoverView.swift`

- [x] **Step 1: 加 `ProviderHistorySection`（放在 `PopoverView` 同文件、`ProviderUsageArea` 附近，`private struct`）**

```swift
    /// 「带历史的 provider 用量区」：在 ProviderUsageSection 上挂趋势箭头（从 history 算）+ 额度折线图。
    /// historyService 必须非 nil 才用本视图（SwiftUI 的 `@ObservedObject` 不能是 Optional）。
    private struct ProviderHistorySection: View {
        @ObservedObject var historyService: UsageHistoryService
        @ObservedObject var runtime: ProviderRuntime
        let primaryLabel: String
        let secondaryLabel: String

        var body: some View {
            let pts = historyService.history.dataPoints
            let snap = runtime.snapshot
            let t5 = computeTrend(currentPct: snap?.primaryWindow?.utilizationPct, points: pts, metric: \.pct5h)
            let t7 = computeTrend(currentPct: snap?.secondaryWindow?.utilizationPct, points: pts, metric: \.pct7d)
            ProviderUsageSection(runtime: runtime, trendPrimary: t5, trendSecondary: t7)
            UsageCard {
                UsageChartSectionView(historyService: historyService, recentEvents: [],
                                      primaryLabel: primaryLabel, secondaryLabel: secondaryLabel)
            }
        }
    }
```

- [x] **Step 2: 改 `ProviderUsageArea` 让它可选挂 history**

在 `ProviderUsageArea` 加：

```swift
        /// 该 provider 的历史（有则显示趋势箭头 + 折线图）。nil → 退化成只有 ProviderUsageSection（v0.2.6 现状）。
        var history: (service: UsageHistoryService, primaryLabel: String, secondaryLabel: String)? = nil
```

并把 `runtime.isConfigured` 分支里现在的 `ProviderUsageSection(runtime: runtime)` 这一句换成：

```swift
                if let h = history {
                    ProviderHistorySection(historyService: h.service, runtime: runtime,
                                           primaryLabel: h.primaryLabel, secondaryLabel: h.secondaryLabel)
                } else {
                    ProviderUsageSection(runtime: runtime)
                }
```

其余（`lastError` 卡 / `Updated … ago` / `bottomBar()`）不动；`else`（unconfigured）分支不动。

- [x] **Step 3: 改 `providerArea` 的非 Claude 分支传 history**

```swift
        } else if coordinator.isAvailable(selectedProvider),
                  let runtime = coordinator.runtime(for: selectedProvider) {
            let history: (UsageHistoryService, String, String)? = (selectedProvider == .codex
                ? (coordinator.provider(.codex) as? CodexProvider).map { ($0.history, "Session", "Weekly") }
                : nil)
            ProviderUsageArea(runtime: runtime,
                              providerID: selectedProvider,
                              onBackToClaude: { selectedProvider = .claude },
                              history: history,
                              bottomBar: { bottomBar })
        } else {
```

（注意 `history` 的 tuple 元组 label：`ProviderUsageArea.history` 的类型是 `(service:primaryLabel:secondaryLabel:)?`，传无 label 的 `($0.history, "Session", "Weekly")` 元组会自动适配；如编译器挑剔就写全 label。）

- [x] **Step 4: 全量 build + test（G4 gate）**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS。如有 tuple-label 不匹配的编译错误 → 把 `ProviderUsageArea.history` 改成具名结构体或在传值处补全 label。

- [x] **Step 5: Commit**

```bash
cd /Users/methol/data/code-methol/usage-bar
git add macos/Sources/ClaudeUsageBar/PopoverView.swift
git commit -m "feat: v0.2.8 — PopoverView 抽 ProviderHistorySection（趋势箭头 + 折线图），Codex tab 挂上（Session/Weekly 文案）[spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 文档注释 + app 启动调 `startPolling()`

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageProvider.swift`（注释）
- Modify: `macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift`（注释）
- Modify: `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`

- [x] **Step 1: `UsageProvider.swift` —— 改 `supportsBackgroundPolling` 文档注释**

把现在那行注释（`/// 是否有自己的后台轮询（Claude = true；Codex 第一版 = false…）`）换成：

```swift
    /// 该 provider 是否作为**菜单栏 primary 候选**（见 `ProviderCoordinator.primaryEligibleIDs`）——
    /// 要求：既有稳定后台数据源、又有 provider-aware 的菜单栏渲染（图标/前缀文案）。Claude = true。
    /// 注意：provider 可以为「popover 内历史采样」自持一个轻量 refresh timer（装配处显式 `startPolling()`）
    /// 而**不**必置此 flag —— Codex v0.2.8 即如此（菜单栏渲染尚未 provider-aware，故仍 false）。
    var supportsBackgroundPolling: Bool { get }
```

同时把该协议顶部那段「后台轮询的 timer 也由实现自己持有（`supportsBackgroundPolling == true` 的 provider 在装配处自行 `startPolling()`）」措辞微调成「持有 timer 的 provider 在装配处自行 `startPolling()`（是否同时是菜单栏 primary 候选由 `supportsBackgroundPolling` 决定）」。

- [x] **Step 2: `ProviderCoordinator.swift` —— `primaryEligibleIDs` 注释同步**

把它的 doc 注释改成提到「= `supportsBackgroundPolling == true` 的已注册 provider = 既有稳定后台数据 又能在菜单栏渲染；v0.2.6/v0.2.8 仍只 Claude（Codex 有后台 timer 但菜单栏渲染未 provider-aware）」。逻辑（`registry.availableIDs.filter { … }`）不动。

- [x] **Step 3: `ClaudeUsageBarApp.swift` —— `.task` 末尾起 Codex 采样**

在 `coordinator.claude.startPolling()` 那一行**之后**加：

```swift
                    if let codex = coordinator.provider(.codex) as? CodexProvider {
                        codex.startPolling()
                    }
```

- [x] **Step 4: build + 全量 test**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS。

- [x] **Step 5: Commit**

```bash
cd /Users/methol/data/code-methol/usage-bar
git add macos/Sources/ClaudeUsageBar/UsageProvider.swift macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift
git commit -m "feat: v0.2.8 — app 启动起 Codex 5 分钟采样；重定义 supportsBackgroundPolling 注释为「菜单栏 primary 候选资格」[spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 全量验收（G6 硬证据）

**Files:** none（只跑命令）

- [x] **Step 1: build + test**

Run: `cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release && swift test`
Expected: build OK；全部 tests PASS（含新增的 `UsageHistoryServiceTests` + `CodexProviderTests` 增量）。

- [x] **Step 2: release artifacts + verify**

Run: `cd /Users/methol/data/code-methol/usage-bar && make release-artifacts && bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip`
Expected: zip/dmg 产出；verify 输出 OK（"Codesign verified OK" 等）。

- [x] **Step 3: 手动 smoke（reinstall 看 UI）**

Run: `cd /Users/methol/data/code-methol/usage-bar && make install`
然后退掉旧实例、重开，切到 Codex tab：应看到 Session/Weekly 卡 + 折线图（首开「No history data yet.」，等几个周期 / 多按 Refresh 后出现点）；Settings → Primary Provider 下拉**不**含 Codex。把观察结果记到 spec 的 `spec_criteria` evidence + Verification log。

- [x] **Step 4: 回填 spec**

把 `docs/superpowers/specs/2026-05-12-codex-history-trend.md` 的每个 `spec_criteria[].done` 改 `true`、填 `evidence`；`Verification log` 勾上；`status: accepted` → `implemented`（G6 全勾后）。`docs/versions/v0.2.8-codex-history-trend.md`：`status: planned` → `in-progress`，填 `release_notes_zh`（新增：Codex tab 历史折线图 + 趋势箭头；内部：UsageHistoryService 泛化、Codex 5 分钟后台采样）+ G6 checklist 勾上。Commit（含 spec/version 回填 + plan 本文件勾选）。

```bash
cd /Users/methol/data/code-methol/usage-bar
git add docs/
git commit -m "docs: v0.2.8 — 回填 spec spec_criteria/Verification log + version 文件 release_notes_zh/状态 [spec:2026-05-12-codex-history-trend]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: G5 code-review → PR**

按 `superpowers:requesting-code-review` / AGENTS.md G5：独立 reviewer（codex `codex-rescue` 或 `general-purpose` subagent）做 code-review + security-review（敏感面：新增 5 分钟后台访问 chatgpt.com + 新建 `history-codex.json`）。verdict = approved 后 `gh pr create`（中文 title/body，含 spec id + version 链接），等 CI（"build" job）绿，`git checkout main && git merge --ff-only feat/v0.2.8-codex-history-trend && git push origin main`，删分支。把 G5 verdict append 进 spec `reviews:`。

---

## Self-Review

- **Spec coverage**：SC1→Task1；SC2→Task2；SC3→Task2（startPolling/记点）+Task5（app 调用 + 注释重定义）；SC4→Task4（ProviderHistorySection 的 computeTrend）；SC5→Task3（label 参数）+Task4（挂折线图）；SC6→Task6；SC7→贯穿（Claude 默认路径不变 = Task1 测试；Claude 折线图默认参数 = Task3；菜单栏/Settings 不动 = Task5 只改注释 + supportsBackgroundPolling 保持 false = Task2 测试 `testSupportsBackgroundPollingIsFalse`）。全覆盖。
- **Placeholder scan**：无 TBD；每个改代码的 step 都给了代码或精确到行的替换说明。
- **Type consistency**：`CodexProvider.init(environment:session:history:)`、`.history: UsageHistoryService`、`.isPolling: Bool`、`.startPolling()`、`pollCancellable: AnyCancellable?`、`pollIntervalSeconds: TimeInterval`、`recordHistorySample(from: ProviderUsageSnapshot)`、`UsageHistoryService.init(filename:directory:)` / `.fileURL` / `.backupURL`、`UsageChartSectionView`/`UsageChartContentView` 的 `primaryLabel`/`secondaryLabel: String`、`ProviderUsageArea.history: (service:primaryLabel:secondaryLabel:)?`、`ProviderHistorySection(historyService:runtime:primaryLabel:secondaryLabel:)` —— 各 Task 间一致。
- **风险点已在 plan 内标注**：`normalizedWindows()` 对单个 604800 窗口的归类（Task2 Step1 末尾 + Step4）；tuple-label 适配（Task4 Step3/4）。
