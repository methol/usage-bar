# Popover Redesign 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Popover 卡片化重做（圆角卡 + 渐变背景 + 图标 + "Resets in: X at TIME" + "Pace: safe/fast"），加多 provider tab 外壳（仅 Claude 可用），折线图叠极浅 5h/7d pace 面积。

**Architecture:** 纯 UI 层改动 + 两个新纯函数（reset 文案格式化、pace 序列计算）+ 一个新枚举（`UsageProvider`）+ 两个新容器/视图（`UsageCard`、`ProviderTabBar`）。数据/服务层（`UsageService` / `UsageHistoryService` / `PaceCalculator` 等）完全不动；`PaceCalculator.computePaceState` 以不同 `windowDuration` 复用算 7d pace。每个 Task 结束 `swift build` + `swift test` 必须绿；带逻辑的 Task 走 TDD。

**Tech Stack:** Swift 5.9, SwiftUI, Swift Charts (`AreaMark`/`LineMark`), XCTest。所有 `swift` 命令在 `macos/` 目录下跑。

**Spec:** [`../specs/2026-05-12-popover-redesign.md`](../specs/2026-05-12-popover-redesign.md) — 实施完成后回填 frontmatter `spec_criteria[].done` / `evidence` 与 `## Verification log`。

**前置事实（实施时无需再查）：**
- `formatResetCountdown(date:now:)`（`ResetCountdownFormatter.swift`）只输出 `"1h 23m"` / `"12m"` / `"<1m"`，**不含 days** —— 所以 `formatResetWithClock` 的 "≥24h" 分支要自己算 days，不能直接复用。
- `enum TimeRange`（`UsageHistoryModel.swift`）有 `.interval: TimeInterval`；折线图 x 轴 domain = `Date.now.addingTimeInterval(-selectedRange.interval)...Date.now`。
- `struct UsageBucket`（`UsageModel.swift`）有 `var utilization: Double?` 和 `var resetsAtDate: Date?`。
- `func computePaceState(currentPct:resetDate:windowDuration:now:) -> PaceState?`（`PaceCalculator.swift`），`PaceState` ∈ `.onPace | .inDeficit(percentOver:runsOutIn:) | .inReserve(percentUnder:)`。
- `func colorForPct(_ pct: Double) -> Color`（`PopoverView.swift` 文件作用域，pct 入参是 0...1）。
- `struct CapsuleProgressBar { let value: Double; let color: Color }`（`UsageHeroCard.swift`，value 期望 0...1）。
- 折线图 `UsageChartView.swift` 里 `struct UsageChartView` 是死代码（grep 确认仅其定义 + 一句注释提到名字，无引用）；活的是 `UsageChartSectionView` → 私有 `UsageChartContentView`。
- 测试文件均在 `macos/Tests/ClaudeUsageBarTests/`；`ResetCountdownFormatterTests.swift` 已存在（追加），`UsagePaceAreaTests.swift` / `UsageProviderTests.swift` 需新建。
- commit message 用中文，结尾带 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`，并在 subject 带 `[spec:2026-05-12-popover-redesign]`。

---

## File Structure

| 动作 | 文件 | 职责 |
|---|---|---|
| 🔧 | `macos/Sources/ClaudeUsageBar/ResetCountdownFormatter.swift` | 加 `formatResetWithClock(date:now:)` |
| 🔧 | `macos/Tests/ClaudeUsageBarTests/ResetCountdownFormatterTests.swift` | 追加 `formatResetWithClock` 测试 |
| 🆕 | `macos/Sources/ClaudeUsageBar/ProviderTabBar.swift` | `enum UsageProvider` + `struct ProviderTabBar` + `struct ProviderComingSoonView`（私有） |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/UsageProviderTests.swift` | `UsageProvider` 枚举逻辑测试 |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/UsagePaceAreaTests.swift` | `UsagePaceArea.series` 测试 |
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageChartView.swift` | 删死代码 `struct UsageChartView`；加 `struct PacePoint` + `enum UsagePaceArea`；`UsageChartSectionView`/`UsageChartContentView` 加 `fiveHourResetDate`/`sevenDayResetDate` 参数（默认 nil）；`chartView` 在最前面加两组 `AreaMark` |
| 🆕 | `macos/Sources/ClaudeUsageBar/UsageCard.swift` | `struct UsageCard<Content: View>` 圆角卡片容器 |
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageHeroCard.swift` | 删 `enum UsageCardSize`；`UsageHeroCard` 去 `size` 参、加 `icon: String`、改 3 行布局、加 `paceWord(_:)`；更新 `#Preview` |
| 🔧 | `macos/Sources/ClaudeUsageBar/PopoverView.swift` | 渐变背景；`ProviderTabBar` + `@State selectedProvider` + ComingSoon 路由；删 `Text("Claude Usage")`；各内容区块换 `UsageCard` 并删区块间 `Divider()`；算 `pace7d` 传 7d 卡；给 `UsageChartSectionView` 传 reset 日期；两处 `UsageHeroCard` 调用更新（去 `size:`、加 `icon:`） |
| ✅ 不动 | `UsageService.swift` / `UsageHistoryService.swift` / `UsageStatsService.swift` / `PaceCalculator.swift` / `UsageModel.swift` / `UsageChartInterpolation*` / `chartOverlay`/`tooltipView`/`chartForegroundStyleScale`/图例 | 本计划不碰 |

---

## Task 1: `formatResetWithClock` 文案格式化函数（TDD）

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/ResetCountdownFormatter.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/ResetCountdownFormatterTests.swift`

- [ ] **Step 1: 写失败测试**

追加到 `ResetCountdownFormatterTests.swift`（class 内）。注意时钟时间用固定 `Calendar(identifier: .gregorian)` + 固定 `TimeZone` 构造，断言用子串以避开 locale 差异。

```swift
func testResetWithClock_nil() {
    XCTAssertNil(formatResetWithClock(date: nil, now: Date()))
}

func testResetWithClock_expired() {
    let now = Date()
    XCTAssertNil(formatResetWithClock(date: now.addingTimeInterval(-60), now: now))
}

func testResetWithClock_underOneDay_appendsClockTime() {
    let now = Date()
    let reset = now.addingTimeInterval(2 * 3600 + 44 * 60)  // 2h 44m
    let s = formatResetWithClock(date: reset, now: now)
    XCTAssertNotNil(s)
    // 距离 2h 44m，且文案含 " at " + 本地化时钟时间（en: "11:44 PM" / 24h locale: "23:44"，用子串放宽）
    XCTAssertTrue(s!.hasPrefix("2h 44m at "), "got: \(s!)")
    XCTAssertTrue(s!.contains("44"), "got: \(s!)")
}

func testResetWithClock_overOneDay_showsDays_noClockTime() {
    let now = Date()
    let reset = now.addingTimeInterval(4 * 86400 + 5 * 3600 + 59 * 60 + 30)  // 4d 5h 59m (30s 余)
    let s = formatResetWithClock(date: reset, now: now)
    XCTAssertEqual(s, "4 days 5h 59m")
    XCTAssertFalse(s!.contains(" at "))
}

func testResetWithClock_exactlyOneDay_singularVsPlural() {
    let now = Date()
    let s = formatResetWithClock(date: now.addingTimeInterval(86400 + 3600), now: now)  // 1d 1h
    XCTAssertEqual(s, "1 day 1h 0m")
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd macos && swift test --filter ResetCountdownFormatterTests`
Expected: FAIL（`formatResetWithClock` 未定义 / 参数 `calendar:` 不存在）

- [ ] **Step 3: 实现**

追加到 `ResetCountdownFormatter.swift`：

```swift
/// 把 reset 目标时间格式化为卡片底行的 "Resets in:" 文案。
/// - `nil` 或已过期 → `nil`（调用方据此隐藏左半）。
/// - < 24h → `"2h 44m at 11:44 PM"`（复用 `formatResetCountdown` + " at " + 本地化时钟时间）。
/// - ≥ 24h → `"4 days 5h 59m"` / `"1 day 1h 0m"`（自带 days，因为 `formatResetCountdown` 不含 days）。
func formatResetWithClock(date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let secs = Int(date.timeIntervalSince(now))
    guard secs > 0 else { return nil }
    if secs < 86400 {
        guard let countdown = formatResetCountdown(date: date, now: now) else { return nil }
        let timeStr = date.formatted(.dateTime.hour().minute())
        return "\(countdown) at \(timeStr)"
    }
    let days = secs / 86400
    let h = (secs % 86400) / 3600
    let m = (secs % 3600) / 60
    let dayWord = days == 1 ? "day" : "days"
    return "\(days) \(dayWord) \(h)h \(m)m"
}
```

> 注：`date.formatted(.dateTime.hour().minute())` 用系统 locale（en → "11:44 PM"，24h locale → "23:44"），测试里已用子串断言规避 locale 差异。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd macos && swift test --filter ResetCountdownFormatterTests`
Expected: PASS

- [ ] **Step 5: 跑全量构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 6: commit**

```bash
git add macos/Sources/ClaudeUsageBar/ResetCountdownFormatter.swift macos/Tests/ClaudeUsageBarTests/ResetCountdownFormatterTests.swift
git commit -m "$(cat <<'EOF'
feat: formatResetWithClock — 卡片底行 "Resets in: 2h 44m at 11:44 PM" / "4 days 5h 59m" [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `UsageProvider` 枚举 + `ProviderTabBar` 视图

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/ProviderTabBar.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/UsageProviderTests.swift`

- [ ] **Step 1: 写失败测试**

新建 `macos/Tests/ClaudeUsageBarTests/UsageProviderTests.swift`：

```swift
import XCTest
@testable import ClaudeUsageBar

final class UsageProviderTests: XCTestCase {
    func testAllCasesOrder() {
        XCTAssertEqual(UsageProvider.allCases, [.claude, .codex, .cursor, .copilot, .gemini])
    }

    func testDisplayNames() {
        XCTAssertEqual(UsageProvider.claude.displayName, "Claude")
        XCTAssertEqual(UsageProvider.codex.displayName, "Codex")
        XCTAssertEqual(UsageProvider.gemini.displayName, "Gemini")
    }

    func testOnlyClaudeAvailable() {
        XCTAssertTrue(UsageProvider.claude.isAvailable)
        for p in UsageProvider.allCases where p != .claude {
            XCTAssertFalse(p.isAvailable, "\(p) should not be available yet")
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd macos && swift test --filter UsageProviderTests`
Expected: FAIL（`UsageProvider` 未定义）

- [ ] **Step 3: 实现 `ProviderTabBar.swift`**

新建 `macos/Sources/ClaudeUsageBar/ProviderTabBar.swift`：

```swift
import SwiftUI

enum UsageProvider: String, CaseIterable, Identifiable {
    case claude, codex, cursor, copilot, gemini

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }   // "claude" → "Claude"
    /// 本版本只有 Claude 拉通了数据层；其余是 UI 占位。
    var isAvailable: Bool { self == .claude }
}

/// popover 顶部的多 provider 药丸 tab。不可用的 provider 仍可点选，
/// 由调用方在 selection 非 Claude 时展示 `ProviderComingSoonView`。
struct ProviderTabBar: View {
    @Binding var selection: UsageProvider

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsageProvider.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    Text(provider.displayName)
                        .font(.caption.weight(provider == selection ? .semibold : .regular))
                        .foregroundStyle(pillForeground(for: provider))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(provider == selection ? Color(nsColor: .controlBackgroundColor) : .clear)
                                .shadow(color: provider == selection ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func pillForeground(for provider: UsageProvider) -> Color {
        if provider == selection { return .primary }
        return provider.isAvailable ? .secondary : .secondary.opacity(0.5)
    }
}

/// 选中一个尚未拉通数据层的 provider 时显示。
struct ProviderComingSoonView: View {
    let provider: UsageProvider
    var onBackToClaude: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("\(provider.displayName) 支持开发中，敬请期待")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("← 回到 Claude", action: onBackToClaude)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview("ProviderTabBar") {
    struct Wrap: View {
        @State var sel: UsageProvider = .claude
        var body: some View {
            VStack(spacing: 12) {
                ProviderTabBar(selection: $sel)
                if sel != .claude {
                    ProviderComingSoonView(provider: sel, onBackToClaude: { sel = .claude })
                }
            }
            .padding()
            .frame(width: 360)
        }
    }
    return Wrap()
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd macos && swift test --filter UsageProviderTests`
Expected: PASS

- [ ] **Step 5: 跑全量构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 6: commit**

```bash
git add macos/Sources/ClaudeUsageBar/ProviderTabBar.swift macos/Tests/ClaudeUsageBarTests/UsageProviderTests.swift
git commit -m "$(cat <<'EOF'
feat: UsageProvider 枚举 + ProviderTabBar / ProviderComingSoonView 视图（仅 Claude 可用）[spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `PacePoint` + `UsagePaceArea.series`（TDD）

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageChartView.swift`（在文件末尾、`UsageChartInterpolation` 之后追加）
- Test: `macos/Tests/ClaudeUsageBarTests/UsagePaceAreaTests.swift`

- [ ] **Step 1: 写失败测试**

新建 `macos/Tests/ClaudeUsageBarTests/UsagePaceAreaTests.swift`：

```swift
import XCTest
@testable import ClaudeUsageBar

final class UsagePaceAreaTests: XCTestCase {
    func testNilResetReturnsEmpty() {
        let now = Date()
        let s = UsagePaceArea.series(reset: nil, windowDuration: 5*3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now)
        XCTAssertTrue(s.isEmpty)
    }

    func testSampleCount() {
        let now = Date()
        let s = UsagePaceArea.series(reset: now.addingTimeInterval(3600), windowDuration: 5*3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now,
                                     sampleCount: 10)
        XCTAssertEqual(s.count, 11)  // sampleCount + 1
    }

    func testWithinSingleWindowMonotonicAndApproachesFull() {
        // domain 完全落在最后一个 5h 窗口内：reset = now+1h，windowStart = now+1h-5h = now-4h
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let s = UsagePaceArea.series(reset: reset, windowDuration: 5*3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now,
                                     sampleCount: 50)
        let pcts = s.map(\.pct)
        // 单调不降
        for i in 1..<pcts.count { XCTAssertGreaterThanOrEqual(pcts[i], pcts[i-1] - 1e-6) }
        // domainEnd = now 时 elapsed = 4h / 5h = 80%
        XCTAssertEqual(pcts.last!, 80, accuracy: 0.5)
        // domainStart = now-1h 时 elapsed = 3h / 5h = 60%
        XCTAssertEqual(pcts.first!, 60, accuracy: 0.5)
        // 都在 [0,100]
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    func testCrossesWindowBoundarySawtooth() {
        // reset = now+1h，5h 窗口边界在 now-4h、now-9h…；让 domain 跨过 now-4h 这个边界
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let s = UsagePaceArea.series(reset: reset, windowDuration: 5*3600,
                                     domainStart: now.addingTimeInterval(-6*3600),  // now-6h，在边界 now-4h 之前
                                     domainEnd: now, sampleCount: 600)
        let pcts = s.map(\.pct)
        // 序列里应同时出现"接近 100"（边界前）和"接近 0"（边界后）
        XCTAssertTrue(pcts.contains { $0 > 95 }, "expected a near-100 sample before boundary")
        XCTAssertTrue(pcts.contains { $0 < 5 }, "expected a near-0 sample after boundary")
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    func testSevenDaySingleRamp() {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 86400)  // 2 天后 reset，7d 窗口 → windowStart = now-5d
        let s = UsagePaceArea.series(reset: reset, windowDuration: 7*86400,
                                     domainStart: now.addingTimeInterval(-30*86400), domainEnd: now,
                                     sampleCount: 100)
        let pcts = s.map(\.pct)
        XCTAssertEqual(pcts.count, 101)
        XCTAssertEqual(pcts.last!, 5.0/7.0 * 100, accuracy: 0.5)  // now: elapsed 5d/7d
        // domainStart = now-30d 远早于 windowStart(now-5d) → 落在更早的窗口，pct 仍 ∈ [0,100]
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd macos && swift test --filter UsagePaceAreaTests`
Expected: FAIL（`UsagePaceArea` / `PacePoint` 未定义）

- [ ] **Step 3: 实现**

在 `macos/Sources/ClaudeUsageBar/UsageChartView.swift` 文件末尾（`UsageChartInterpolation` 之后）追加：

```swift
// MARK: - Pace area

struct PacePoint: Identifiable {
    let id = UUID()
    let date: Date
    let pct: Double   // 0...100
}

/// 计算 pace 面积序列：在 [domainStart, domainEnd] 上等距采样 sampleCount+1 个点，
/// 每点求其所在 windowDuration 窗口内 elapsed 比例 ×100。
/// 窗口序列由当前 `reset` 按 windowDuration 步长向过去回推得到（Claude 的 5h 窗口非固定网格、
/// 无历史 reset 记录，回推是可接受近似——pace 面积只作参考线）。
enum UsagePaceArea {
    static func series(reset: Date?,
                       windowDuration: TimeInterval,
                       domainStart: Date,
                       domainEnd: Date,
                       sampleCount: Int = 240) -> [PacePoint] {
        guard let reset, windowDuration > 0, sampleCount > 0, domainEnd > domainStart else { return [] }
        let span = domainEnd.timeIntervalSince(domainStart)
        var out: [PacePoint] = []
        out.reserveCapacity(sampleCount + 1)
        for i in 0...sampleCount {
            let t = domainStart.addingTimeInterval(span * Double(i) / Double(sampleCount))
            // k = 距离 reset 还有几个完整窗口；clamp ≥ 0（t 理论上 < reset）
            let kRaw = floor(reset.timeIntervalSince(t) / windowDuration)
            let k = max(0.0, kRaw)
            let windowStart = reset.addingTimeInterval(-windowDuration * (k + 1))
            let frac = (t.timeIntervalSince(windowStart) / windowDuration)
            let clamped = min(max(frac, 0), 1)
            out.append(PacePoint(date: t, pct: clamped * 100))
        }
        return out
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd macos && swift test --filter UsagePaceAreaTests`
Expected: PASS

- [ ] **Step 5: 跑全量构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 6: commit**

```bash
git add macos/Sources/ClaudeUsageBar/UsageChartView.swift macos/Tests/ClaudeUsageBarTests/UsagePaceAreaTests.swift
git commit -m "$(cat <<'EOF'
feat: UsagePaceArea.series — 折线图 pace 面积序列（窗口回推近似 + 跨窗口锯齿）[spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: 折线图 — 删死代码 + 接 reset 日期参数 + 叠 pace AreaMark

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageChartView.swift`

> 目标：删 `struct UsageChartView`（死代码）；`UsageChartSectionView` 和私有 `UsageChartContentView` 各加两个**带默认值 `= nil`** 的参数 `fiveHourResetDate: Date?` / `sevenDayResetDate: Date?`（这样 `PopoverView` 现有调用先不改也能编译）；`UsageChartContentView.chartView` 在 `Chart { }` 最前面叠两组 `AreaMark`。

- [ ] **Step 1: 删除死代码 `struct UsageChartView`**

`grep -n "UsageChartView" macos/Sources macos/Tests -r` 复核：除 `UsageChartView.swift` 里 `struct UsageChartView: View { ... }`（约第 4–178 行）和一句注释 `/// 拆出原 UsageChartView 的内容部分...` 外应无其他引用。删掉整个 `struct UsageChartView: View { ... }`（连同它的 `body`、`chartView`、`tooltipView`、`xAxisFormat`、`tooltipDateFormat` 私有成员）。保留 `struct UsageChartInterpolatedValues`、`enum UsageChartInterpolation`、新加的 `PacePoint`/`UsagePaceArea`、以及 `UsageChartSectionView` 与 `UsageChartContentView`。

- [ ] **Step 2: 给 `UsageChartSectionView` 加参数并下传**

```swift
struct UsageChartSectionView: View {
    @ObservedObject var historyService: UsageHistoryService
    let recentEvents: [StoredUsageEvent]
    var fiveHourResetDate: Date? = nil
    var sevenDayResetDate: Date? = nil

    @State private var selectedRange: TimeRange = .day1
    // ... costSummary / periodLabel 不变 ...

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker( ... ) { ... }  // 不变
            UsageChartContentView(historyService: historyService,
                                  selectedRange: selectedRange,
                                  fiveHourResetDate: fiveHourResetDate,
                                  sevenDayResetDate: sevenDayResetDate)
            if let cost = costSummary {
                LocalCostCard(summary: cost, periodLabel: periodLabel)
            }
        }
    }
}
```

- [ ] **Step 3: 给 `UsageChartContentView` 加参数并在 `chartView` 叠 AreaMark**

```swift
private struct UsageChartContentView: View {
    @ObservedObject var historyService: UsageHistoryService
    let selectedRange: TimeRange
    var fiveHourResetDate: Date? = nil
    var sevenDayResetDate: Date? = nil
    @State private var hoverDate: Date?

    var body: some View {
        let points = historyService.downsampledPoints(for: selectedRange)
        if points.isEmpty {
            Text("No history data yet.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            chartView(points: points)
        }
    }

    @ViewBuilder
    private func chartView(points: [UsageDataPoint]) -> some View {
        let now = Date()
        let domainStart = now.addingTimeInterval(-selectedRange.interval)
        let pace5h = UsagePaceArea.series(reset: fiveHourResetDate, windowDuration: 5 * 3600,
                                          domainStart: domainStart, domainEnd: now)
        let pace7d = UsagePaceArea.series(reset: sevenDayResetDate, windowDuration: 7 * 24 * 3600,
                                          domainStart: domainStart, domainEnd: now)
        let interpolated = hoverDate.flatMap {
            UsageChartInterpolation.interpolateValues(at: $0, in: points)
        }

        Chart {
            // pace 面积（先画 = 在底层；不进图例，因为用直接 foregroundStyle 而非 by:）
            ForEach(pace7d) { p in
                AreaMark(x: .value("Time", p.date), y: .value("Pace 7d", p.pct))
            }
            .foregroundStyle(Color.orange.opacity(0.08))
            .interpolationMethod(.linear)

            ForEach(pace5h) { p in
                AreaMark(x: .value("Time", p.date), y: .value("Pace 5h", p.pct))
            }
            .foregroundStyle(Color.blue.opacity(0.10))
            .interpolationMethod(.linear)

            // —— 以下原样保留 ——
            ForEach(points) { point in
                LineMark(x: .value("Time", point.timestamp), y: .value("Usage", point.pct5h * 100))
                    .foregroundStyle(by: .value("Window", "5h"))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(points) { point in
                LineMark(x: .value("Time", point.timestamp), y: .value("Usage", point.pct7d * 100))
                    .foregroundStyle(by: .value("Window", "7d"))
                    .interpolationMethod(.catmullRom)
            }
            if let iv = interpolated {
                RuleMark(x: .value("Selected", iv.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", iv.date), y: .value("Usage", iv.pct5h * 100))
                    .foregroundStyle(.blue).symbolSize(24)
                PointMark(x: .value("Time", iv.date), y: .value("Usage", iv.pct7d * 100))
                    .foregroundStyle(.orange).symbolSize(24)
            }
        }
        .chartXScale(domain: domainStart...now)
        // 其余 modifier（chartYScale / chartYAxis / chartXAxis / chartForegroundStyleScale /
        // chartLegend / chartPlotStyle / chartOverlay / overlay tooltip / frame / padding）原样保留不动
        // ... （把现有那一长串 .chart* 与 .overlay 照搬）
    }

    // tooltipView / xAxisFormat / tooltipDateFormat 原样保留
}
```

> 关键点：① pace 两组 `ForEach` 必须在 `Chart {}` 体内**最前**（Swift Charts 后画的在上层，line 要盖住 area）；② `chartXScale` 现在用上面定义的 `domainStart...now`（与原来 `Date.now.addingTimeInterval(-selectedRange.interval)...Date.now` 等价，只是复用变量）；③ 不要动 `chartForegroundStyleScale` / `chartLegend` —— pace area 用 `.foregroundStyle(Color…)` 不带 `by:`，不会出现在图例里。

- [ ] **Step 4: 构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS（`PopoverView` 现有 `UsageChartSectionView(historyService:recentEvents:)` 调用因新参数有默认值仍编译）

- [ ] **Step 5: commit**

```bash
git add macos/Sources/ClaudeUsageBar/UsageChartView.swift
git commit -m "$(cat <<'EOF'
feat: 折线图叠极浅 5h/7d pace 面积 + 删死代码 UsageChartView struct [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `UsageCard` 圆角卡片容器

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/UsageCard.swift`

- [ ] **Step 1: 实现**

```swift
import SwiftUI

/// popover 内容区块的统一圆角卡片容器（圆角 14 + 轻微提亮材质 + 细描边/浅阴影）。
struct UsageCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview("UsageCard") {
    VStack(spacing: 10) {
        UsageCard { Text("卡片 A").font(.headline); Text("正文").foregroundStyle(.secondary) }
        UsageCard { Text("卡片 B") }
    }
    .padding()
    .frame(width: 360)
    .background(LinearGradient(colors: [Color.blue.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom))
}
```

- [ ] **Step 2: 构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 3: commit**

```bash
git add macos/Sources/ClaudeUsageBar/UsageCard.swift
git commit -m "$(cat <<'EOF'
feat: UsageCard — popover 区块统一圆角卡片容器 [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: 重做 `UsageHeroCard`（去 size、加 icon、新 3 行布局、paceWord）

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/UsageHeroCard.swift`
- Modify: `macos/Sources/ClaudeUsageBar/PopoverView.swift`（仅最小改两处 `UsageHeroCard(...)` 调用使其编译；完整重排留到 Task 7）

- [ ] **Step 1: 重写 `UsageHeroCard.swift`**

把整个文件替换为（保留 `CapsuleProgressBar`，删 `enum UsageCardSize`）：

```swift
import SwiftUI

/// 单个用量窗口卡片：图标 + 标题 + 百分比 + 趋势；进度条；"Resets in:" + "Pace:" 底行。
/// （v0.2.4 起去掉 v0.0.8 的 56pt hero / secondary 双尺寸，5h 与 7d 等权。）
struct UsageHeroCard: View {
    let label: String
    let bucket: UsageBucket?
    var trend: TrendIndicator? = nil
    var pace: PaceState? = nil
    var icon: String = "gauge"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(label, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentageText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pctColor)
                if let trend {
                    Text(trendText(for: trend))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(trend.direction == .up ? .red : .green)
                }
            }
            CapsuleProgressBar(value: pctValue, color: pctColor)
                .frame(height: 8)
            if resetLine != nil || paceWordValue != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let resetLine {
                        Text("Resets in: \(resetLine)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pw = paceWordValue {
                        Text("Pace: \(pw.text)")
                            .font(.caption)
                            .foregroundStyle(pw.color)
                    }
                }
            }
        }
    }

    private var pctValue: Double { (bucket?.utilization ?? 0) / 100.0 }
    private var pctColor: Color { colorForPct(pctValue) }
    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
    private var resetLine: String? { formatResetWithClock(date: bucket?.resetsAtDate, now: Date()) }

    private func trendText(for t: TrendIndicator) -> String {
        let arrow = t.direction == .up ? "▲" : "▼"
        return "\(arrow) \(t.deltaPct)%"
    }

    private var paceWordValue: (text: String, color: Color)? { paceWord(pace) }
}

/// PaceState → 卡片底行短标签。inReserve / onPace → "safe" 绿；inDeficit → "fast" 红；nil → 不显示。
func paceWord(_ pace: PaceState?) -> (text: String, color: Color)? {
    switch pace {
    case nil: return nil
    case .onPace, .inReserve: return ("safe", .green)
    case .inDeficit: return ("fast", .red)
    }
}

struct CapsuleProgressBar: View {
    let value: Double  // 期望 0...1，越界自动 clamp
    let color: Color

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, value)) * geo.size.width)
                }
            }
    }
}

#Preview("UsageHeroCard – 5h / 7d") {
    VStack(alignment: .leading, spacing: 10) {
        UsageHeroCard(label: "5-Hour",
                      bucket: UsageBucket(utilization: 42, resetsAt: "2099-01-01T23:44:00Z"),
                      trend: TrendIndicator(direction: .down, deltaPct: 2),
                      pace: .inReserve(percentUnder: 5),
                      icon: "clock")
        UsageHeroCard(label: "Weekly",
                      bucket: UsageBucket(utilization: 73, resetsAt: "2099-01-08T00:00:00Z"),
                      trend: TrendIndicator(direction: .up, deltaPct: 11),
                      pace: .inDeficit(percentOver: 14, runsOutIn: 3 * 86400),
                      icon: "calendar")
        UsageHeroCard(label: "5-Hour (no data)", bucket: nil, icon: "clock")
    }
    .padding()
    .frame(width: 360)
}
```

> 检查 `UsageBucket(utilization:resetsAt:)` 这个构造器签名是否与现有一致（旧 `#Preview` 里用的就是 `UsageBucket(utilization: 70, resetsAt: "2099-01-01T00:00:00Z")`，照抄即可）。`TrendIndicator(direction:deltaPct:)` 同理沿用旧 Preview 的写法。

- [ ] **Step 2: 最小修 `PopoverView.swift` 两处调用 + 加 pace7d**

在 `PopoverView.usageView` 里：原来已有 `let pace5h = computePaceState(currentPct: ..., resetDate: ...)`；在它下面加：

```swift
let pace7d = computePaceState(
    currentPct: service.usage?.sevenDay?.utilization,
    resetDate: service.usage?.sevenDay?.resetsAtDate,
    windowDuration: 7 * 24 * 3600
)
```

把两处 `UsageHeroCard(...)` 调用改成：

```swift
UsageHeroCard(label: "5-Hour", bucket: service.usage?.fiveHour, trend: trend5h, pace: pace5h, icon: "clock")
UsageHeroCard(label: "7-Day", bucket: service.usage?.sevenDay, trend: trend7d, pace: pace7d, icon: "calendar")
```

（其余 `PopoverView` 暂不动 —— 卡片化排版、tab、渐变在 Task 7。）

- [ ] **Step 3: 构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 4: commit**

```bash
git add macos/Sources/ClaudeUsageBar/UsageHeroCard.swift macos/Sources/ClaudeUsageBar/PopoverView.swift
git commit -m "$(cat <<'EOF'
feat: UsageHeroCard 重做 — 去双尺寸/加 icon/三行布局（Resets in: X at TIME + Pace: safe-fast）+ 7d 也算 pace [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `PopoverView` 完整重排（tab + 渐变背景 + 卡片化 + 接图 reset 日期）

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/PopoverView.swift`

- [ ] **Step 1: 加 `selectedProvider` 状态 + 渐变背景 + tab 路由**

在 `PopoverView` 加 `@State private var selectedProvider: UsageProvider = .claude`。

`body` 改成（保留 setup / isAwaitingCode 两个分支不变，只改最后那个已登录的 `else` 分支，并整体加渐变背景）：

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 10) {
        if !setupComplete && !service.isAuthenticated {
            SetupView( ... )                // 不变
        } else if service.isAwaitingCode {
            // 不变（Text + CodeEntryView + error）
            ...
        } else {
            AccountSwitcherView(service: service)         // 自隐藏，不变
            ProviderTabBar(selection: $selectedProvider)
            if !service.isAuthenticated {
                signInView
            } else if selectedProvider == .claude {
                usageView
            } else {
                ProviderComingSoonView(provider: selectedProvider,
                                       onBackToClaude: { selectedProvider = .claude })
            }
        }
    }
    .padding()
    .frame(width: 360)
    .background(
        LinearGradient(
            colors: [Color.accentColor.opacity(0.06), Color.clear],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    )
}
```

> 删掉原 `else` 分支里的 `Text("Claude Usage").font(.headline)`（tab 里的 "Claude" 药丸已起标识作用）。`signInView` 内部不变。渐变用 `Color.accentColor.opacity(0.06)`→`clear`：浅色下淡蓝、深色下几乎不可见；若深色下仍偏重，把 0.06 调到 0.03。

- [ ] **Step 2: `usageView` 内容区块卡片化**

把 `usageView` 里那串 `Divider()`-分隔的内容区块改成 `UsageCard { ... }` 包裹、区块间靠 `VStack` 的 spacing（已是 10）分隔，去掉这些 `Divider()`。结构变为：

```swift
@ViewBuilder
private var usageView: some View {
    // trend5h / trend7d / pace5h / pace7d 计算不变（pace7d 已在 Task 6 加好）

    UsageCard {
        UsageHeroCard(label: "5-Hour", bucket: service.usage?.fiveHour, trend: trend5h, pace: pace5h, icon: "clock")
    }
    UsageCard {
        UsageHeroCard(label: "7-Day", bucket: service.usage?.sevenDay, trend: trend7d, pace: pace7d, icon: "calendar")
    }

    if let opus = service.usage?.sevenDayOpus, opus.utilization != nil {
        UsageCard {
            Text("Per-Model (7 day)").font(.subheadline).foregroundStyle(.secondary)
            UsageBucketRow(label: "Opus", bucket: opus)
            if let sonnet = service.usage?.sevenDaySonnet {
                UsageBucketRow(label: "Sonnet", bucket: sonnet)
            }
        }
    }

    if let extra = service.usage?.extraUsage, extra.isEnabled {
        UsageCard { ExtraUsageRow(extra: extra) }
    }

    UsageCard {
        UsageChartSectionView(
            historyService: historyService,
            recentEvents: usageStats.recentEvents,
            fiveHourResetDate: service.usage?.fiveHour?.resetsAtDate,
            sevenDayResetDate: service.usage?.sevenDay?.resetsAtDate
        )
    }

    if !usageStats.dailySpend.isEmpty && !usageStats.dailySpend.allSatisfy({ $0.usd == 0 }) {
        UsageCard {
            UsageHeatmapView(daySpends: usageStats.dailySpend, isInitializing: usageStats.isInitializing)
        }
    }

    if let error = service.lastError {
        UsageCard {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.caption)
        }
    }
    if let updaterError = appUpdater.lastError {
        UsageCard {
            Label(updaterError, systemImage: "arrow.triangle.2.circlepath.circle").foregroundStyle(.red).font(.caption)
        }
    }

    // —— footer 保持裸样式（不进卡片）——
    HStack(spacing: 12) {
        if let updated = service.lastUpdated {
            Text("Updated \(updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
    }
    HStack(spacing: 12) {
        settingsButton
        Spacer()
        Button("Refresh") { Task { await service.fetchUsage() } }.buttonStyle(.borderless).font(.caption)
        if appUpdater.isConfigured {
            Button("Check for Updates…") { appUpdater.checkForUpdates() }
                .buttonStyle(.borderless).font(.caption).disabled(!appUpdater.canCheckForUpdates)
        }
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
    }
}
```

> 保留 `usageView` 顶部那段 `// TODO(perf): ...` 注释和 `let points = ... ; let trend5h = ... ; let trend7d = ... ; let pace5h = ... ; let pace7d = ...` 计算逻辑，原样不动，只改下面的视图树。`UsageBucketRow` / `ExtraUsageRow` 这两个私有子视图本身不动（它们现在被塞进 `UsageCard` 里）。

- [ ] **Step 3: 构建 + 测试**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

- [ ] **Step 4: 目测（人工 / 截图）**

`make app && open macos/ClaudeUsageBar.app`（或既有的本地运行方式）。检查：① 顶部 5 个 provider 药丸，Claude 选中（白底+轻阴影），其余 dimmed；点 Codex → 显示「Codex 支持开发中，敬请期待」+「← 回到 Claude」，点回来正常。② 两个用量卡是圆角卡片，左上 clock/calendar 图标 + 标题，右上 大一号百分比（颜色随档位）+ 趋势箭头；进度条；底行「Resets in: Xh Ym at H:MM AM/PM」（5h，<24h）/「X days Yh Zm」（7d），右侧「Pace: safe/fast」。③ popover 背景有极淡渐变（不刺眼）。④ 折线图区在卡片里，原两条折线 + 悬停明细不变，下方有极浅蓝（5h，跨 5h 边界呈锯齿）/极浅黄（7d）面积，图例仍只有 5h/7d。⑤ dark mode 切换看背景与卡片对比度。

- [ ] **Step 5: commit**

```bash
git add macos/Sources/ClaudeUsageBar/PopoverView.swift
git commit -m "$(cat <<'EOF'
feat: PopoverView 重排 — provider tab + 渐变背景 + 内容区块卡片化 + 折线图接 reset 日期 [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: 收尾 — release-artifacts 验证 + 回填 spec

**Files:**
- Modify: `docs/superpowers/specs/2026-05-12-popover-redesign.md`

- [ ] **Step 1: 全量硬证据**

Run: `cd macos && swift build -c release && swift test`
Expected: PASS

Run: `make release-artifacts`（在 repo 根）
Expected: 成功产出 zip + dmg 且 verify-release 通过（UI-only 改动不影响 bundle 结构；若失败先排查再继续）

- [ ] **Step 2: 回填 spec frontmatter + Verification log**

把 `docs/superpowers/specs/2026-05-12-popover-redesign.md` frontmatter 里 `spec_criteria` 的 SC1–SC5 `done: false` → `true`，`evidence` 填对应 commit hash / 测试名 / 手测结论（例：`SC2 → commit <hash>；popover 目测通过`）；`updated:` 改实际日期；`status:` 仍保持 `draft`（G2 review 通过后才改 `accepted`，G6 全勾后改 `implemented` —— 这两步由后续 review gate 负责，不在本计划内）。`## Verification log` 五条 `- [ ] SCx — pending` 改成 `- [x] SCx — <evidence 一句话>`。

> 注意：本计划只负责"实现 + 自验"。G2（spec design-review）、G3（plan-review）、G5（code-review）、G6/G7 由 reviewer / 后续流程负责；实施者不要自己把 `status` 改 `implemented`、也不要自己 append `reviews:` 条目。

- [ ] **Step 3: commit**

```bash
git add docs/superpowers/specs/2026-05-12-popover-redesign.md
git commit -m "$(cat <<'EOF'
docs: v0.2.4 popover-redesign 实施完成 — 回填 spec_criteria 与 Verification log [spec:2026-05-12-popover-redesign]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review（计划作者已跑）

- **Spec 覆盖**：SC1 → Task 2+7；SC2 → Task 1+5+6+7；SC3 → Task 3+4；SC4 → 已在立项 commit 完成（计划开头说明），Task 8 回填 spec；SC5 → Task 4(删死代码) + Task 1/3(单测) + 各 Task 的 `swift build`/`swift test` + Task 8 全量。无缺口。
- **Placeholder 扫描**：无 "TBD/TODO 待填"；`UsageHeroCard.swift` 顶部那条 `// TODO(perf)` 是**既有代码注释**（在 `PopoverView`），不是本计划新增的占位。每个改代码的 step 都给了完整代码或精确改动描述。
- **类型一致性**：`formatResetWithClock(date:now:calendar:)` 在 Task 1 定义、Task 6 调用（只传 `date:now:`，靠默认 `calendar:`）✓；`UsageProvider` / `ProviderTabBar(selection:)` / `ProviderComingSoonView(provider:onBackToClaude:)` Task 2 定义、Task 7 用 ✓；`PacePoint` / `UsagePaceArea.series(reset:windowDuration:domainStart:domainEnd:sampleCount:)` Task 3 定义、Task 4 用 ✓；`UsageHeroCard(label:bucket:trend:pace:icon:)` Task 6 定义、Task 6 Step2 + Task 7 用 ✓；`UsageCard { }` Task 5 定义、Task 7 用 ✓；`paceWord(_:)` Task 6 定义并在同文件用 ✓；`UsageChartSectionView(historyService:recentEvents:fiveHourResetDate:sevenDayResetDate:)` Task 4 定义、Task 7 用 ✓。
