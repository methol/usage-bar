---
id: 2026-05-11-trend-arrows
title: 趋势箭头 ▲▼ + 6h 增量百分点（基于现有 history.json）
status: accepted
created: 2026-05-11
updated: 2026-05-11
owner: claude-code
model: claude-opus-4-7
target_version: v0.0.9
related_adrs: [0001, 0002]
related_research: [competitive-analysis]
spec_criteria:
  - id: SC1
    criterion: "新增 macos/Sources/ClaudeUsageBar/TrendCalculator.swift，含 TrendDirection enum + TrendIndicator struct + 顶层纯函数 computeTrend(points:metric:lookback:now:) -> TrendIndicator?"
    done: false
    evidence: null
  - id: SC2
    criterion: "新增 macos/Tests/ClaudeUsageBarTests/TrendCalculatorTests.swift，≥4 case：up（current > baseline）/ down（current < baseline）/ flat（|Δ| < 1pp，return nil）/ 数据不足（history 中无 lookback 之前的点，return nil）；deltaPct 用 .rounded() 取整非截断（边界 case Δ=1.4→1 / Δ=0.9→nil）；每测构造 let now = Date() 显式传 now"
    done: false
    evidence: null
  - id: SC3
    criterion: "UsageHeroCard 增加可选 trend 参数（默认 nil 不破坏现有 call site）；trend 非 nil 时在 label 行内 label 文本之后、Spacer 之前显示 '▲ N%' / '▼ N%'，font .caption2 monospacedDigit，color = up→.red / down→.green"
    done: false
    evidence: null
  - id: SC4
    criterion: "PopoverView usageView 把 historyService.history.dataPoints 与 service.usage 传给 TrendCalculator，分别为 5h 与 7d 计算 trend；UsageHeroCard 调用从 (size, label, bucket) 升到 (size, label, bucket, trend)"
    done: false
    evidence: null
  - id: SC5
    criterion: "lookback 默认 6h（21600s）；TrendCalculator 找 baseline = points 中 timestamp ≤ (now - lookback) 的最新一点；若无（即所有 history 点都比 6h 更新），return nil"
    done: false
    evidence: null
  - id: SC6
    criterion: "|delta| < 1pp 视为 flat 返回 nil（不显示），避免抖动；**单位约定**：delta 计算的两侧统一为 0-100 百分点制 — currentPct 直接传 service.usage?.bucket?.utilization（API 原始 0-100），UsageDataPoint.pct5h/pct7d 在 UsageService.swift:72-73 是 utilization/100.0（0-1 unitless），computeTrend 内部对 baseline 自动 *100.0 与 currentPct 对齐"
    done: false
    evidence: null
  - id: SC7
    criterion: "UsageHeroCard #Preview 增加含 trend 的示例（≥1 个 up + 1 个 down）"
    done: false
    evidence: null
  - id: SC8
    criterion: "5h/7d 之外的其他视图（Per-Model UsageBucketRow / ExtraUsageRow / UsageChartView / Settings 等）不引入 trend；ExtraUsage 无 trend（数据语义不同，留待后续）"
    done: false
    evidence: null
  - id: SC9
    criterion: "cd macos && swift build -c release 输出 'Build complete!'"
    done: false
    evidence: null
  - id: SC10
    criterion: "cd macos && swift test 'Executed N tests, with 0 failures'（含新增 TrendCalculatorTests ≥4 case）"
    done: false
    evidence: null
  - id: SC11
    criterion: "git commit 中文、含变更主题 + spec id；spec.reviews 数组含 G2、G5、G6 三条 verdict"
    done: false
    evidence: null
  - id: SC12
    criterion: "version v0.0.9 frontmatter status placeholder→planned→in-progress；CHANGELOG.md append v0.0.9 中文 entry"
    done: false
    evidence: null
automated_checks:
  - "SC_AUTO_BUILD: cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release 2>&1 | tail -3 | grep -q 'Build complete'"
  - "SC_AUTO_TEST: cd /Users/methol/data/code-methol/usage-bar/macos && swift test 2>&1 | tail -5 | grep -E 'Executed [0-9]+ test.*0 failures'"
manual_checks:
  - "启动 .app 累积 ≥6h history 后，目视确认 5h/7d hero 卡片 label 行出现 ▲/▼ 箭头与百分点；卸载/无 history 时不显示；visual regression：trend 不挤压 reset countdown"
  - "P2 commit 后 grep 确认 UsageBucketRow / ExtraUsageRow / UsageChartView / Settings 等文件无 trend 引用（SC8 反向断言）"
reviews:
  - gate: G2
    reviewer: codex:codex-rescue (general-purpose fallback, agentId abbc647690ea14183)
    date: 2026-05-11
    verdict: changes-requested
    summary: |
      原始 verdict: changes-requested（1 BLOCKING + 4 RECOMMENDED + 3 NOTES）。
      作者按 superpowers:receiving-code-review 流程：
      - B1（单位 100x 误差：currentPct 用 utilization 0-100 但 baseline UsageDataPoint.pct5h 是 0-1）
        accepted — 这是真 bug 且 reviewer 通过实证 grep `UsageService.swift:72` 命中。
        修订 §3.2 函数注释加单位约定段、内部 `baselinePct100 = baseline[keyPath: metric] * 100.0`
        与 currentPct 对齐；SC6 措辞改为显式说明单位转换。
      - B2（max(by:) 注释易误）accepted — §3.2 加注释说明 Swift max(by:) 语义。
      - R1（a11y 故意排除需加风险声明）accepted — §5 风险新增 #7。
      - R2（flat threshold 1pp 无调研引用）accepted — §5 风险 #5 补 "调研未给具体数值，沿用经验值"。
      - R3（.rounded() 非截断决策未明确）accepted — SC2 + §3.2 注释加 ".rounded() 非截断"。
      - R4（ExtraUsage 不做 trend 原因不充分）accepted — §1 不在范围补 "UsageDataPoint 模型只存 pct5h/pct7d"。
      - N1 文化差异（noted-only）/ N2 冷启 / N3 reviews 数组 — 已处理。
      修订后 spec.status 直接升 accepted（与 v0.0.7/v0.0.8 同模式 — BLOCKING 为 spec 层修法、无需重跑 G2）。
    artifacts: ["G2 review subagent output (agentId abbc647690ea14183)"]
  - gate: G3
    reviewer: claude-code (general-purpose subagent, independent session, agentId a9e1517a5adc1fe37)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（1 BLOCKING + 3 RECOMMENDED + 5 NOTES）。
      reviewer 与 v0.0.8 G3 同款命中 P1 evidence 抓手过载，但**未独立发现** B1 单位 bug
      （仅检查类型 Double? 匹配，未追到 UsageService.swift:72 单位定义）— 该 bug 由 G2
      reviewer 与作者主会话独立同时发现并已在 B1 处理。
      作者按 superpowers:receiving-code-review 流程：
      - B1（P1 evidence 抓手与 v0.0.8 同款过载，SC5/SC6 提及 service.usage 接入侧但 P1 未接入）
        accepted — §3.6 P1 success 改为仅 SC1/SC2，SC5/SC6 推迟到 P2 一起收集。
      - R1（P2 SC8 反向断言拆 manual checklist）accepted — manual_checks 增加 grep 反向断言项。
      - R2（Commit C 不拆，加 intent 说明）accepted — §3.6 commit 拆分段加 "刻意合并" 说明。
      - R3（G5 reviewer focus 提示）accepted — §3.6 G5 gate 加 reviewer focus 4 点提示。
      - N1~N5（TrendDirection 自带 Equatable / colorForPct visibility / 类型一致性 / SC 数量 /
        相关文件路径）confirmed/noted-only — 不改 spec。
    artifacts: ["G3 review subagent output (agentId a9e1517a5adc1fe37)"]
---

# 趋势箭头 ▲▼ + 6h 增量百分点（基于现有 history.json）

## 1. 背景与目标

竞品调研 §1.3 指出 SessionWatcher 在菜单栏紧凑串里加了 `▼2%` / `▲5%` 趋势箭头（红绿配色），让用户"瞥一眼"就知道用量在涨还是在落。我们当前 PopoverView 5h/7d hero 卡片只显示静态百分比，看不出趋势。本 spec 引入趋势箭头：

- 基于现有 `~/.config/claude-usage-bar/history.json` 的 30 天 `UsageDataPoint(timestamp, pct5h, pct7d)`（30 天 retention 已 ship 至 v0.0.6 之前）
- 计算 *current vs 6h 前* 的百分点差值
- 在 hero / secondary 卡片 label 行右侧显示 `▲ N%` / `▼ N%`
- |Δ| < 1pp 视为持平不显示（防止抖动）
- 数据不足（history 没有 ≥6h 前的点）也不显示

**不在范围**：
- 不引入新存储（complete reuse 现有 history.json）
- 不显示 ExtraUsage / Per-Model 趋势（**`UsageDataPoint` 模型只存 `pct5h` / `pct7d` 两字段**，扩展到 ExtraUsage / Per-Model 需先改历史存储模型并伴随迁移；超出 v0.0.9 范围）
- 不显示菜单栏图标内的趋势（v0.0.10 spec 才做菜单栏紧凑模式）
- lookback 时间窗口暂用固定 6h；可配置交给后续版本（YAGNI）
- 不引入 a11y 标签（v1.0 a11y audit 统一处理）

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| Lookback 窗口 | 固定 6h | 与 SessionWatcher 调研直觉一致；6h 兼顾"足够新"与"足够多采样"；可配置交给后续 spec |
| Baseline 选取 | history 中 timestamp ≤ (now-lookback) 的最新一点 | 容忍 polling 间隔抖动 / app 关闭时段；不要求精确 6h |
| Flat threshold | \|Δ\| < 1pp 视为 nil（不显示） | polling 自身有 ±0.5pp 抖动；< 1pp 显示会闪烁 |
| Current 取值源 | `service.usage?.bucket?.utilization`（实时） | hero 卡片显示的就是这个数；trend 必须与 hero 数字同源 |
| 显示位置 | label 行 内 label 文本之后、Spacer 之前 | 视觉与 hero 数字解耦；不与 reset countdown 抢空间 |
| 配色 | up → .red、down → .green（与 colorForPct 直觉同方向：高用量为红） | 用户已建立"红=接近上限"心智；上升趋势 = 红箭头 |
| 不显示场景 | 数据不足 / flat / bucket nil | 静默优于错误信息 |
| TrendCalculator 注入 | 顶层纯函数 + 可注入 now（默认 Date()） | 与 v0.0.8 ResetCountdownFormatter 同款约定，便于单测 |

## 3. 设计

### 3.1 数据流

```
UsageHistoryService.history.dataPoints (@Published)
                  │
                  ▼
PopoverView.usageView
  ├─ trend5h = computeTrend(points, metric: \.pct5h, lookback: 6h, now: Date())
  ├─ trend7d = computeTrend(points, metric: \.pct7d, lookback: 6h, now: Date())
  ├─ UsageHeroCard(.hero, "5-Hour", bucket: usage?.fiveHour, trend: trend5h)
  └─ UsageHeroCard(.secondary, "7-Day", bucket: usage?.sevenDay, trend: trend7d)
```

### 3.2 `TrendCalculator.swift`

```swift
import Foundation

enum TrendDirection {
    case up
    case down
}

struct TrendIndicator: Equatable {
    let direction: TrendDirection
    let deltaPct: Int  // 绝对值，已 round 到整数百分点
}

/// 计算 current vs lookback 时间前 baseline 的趋势。
///
/// **单位约定**（G2 review B1 修订）：
/// - `currentPct` 期望 **0...100 百分制**（直接传 service.usage?.bucket?.utilization 原始 API 值）
/// - `points[*][metric]` 实际是 **0...1 unitless**（UsageService.swift:72-73 在 recordDataPoint
///   前已 / 100.0），函数内部对 baseline `* 100.0` 与 currentPct 对齐为同单位
/// - 输出 `deltaPct` 单位为**百分点**（Int，已 .rounded() 取整非截断）
///
/// - Parameters:
///   - currentPct: hero 数字显示的实时 utilization（百分制 0...100）
///   - points: history.dataPoints
///   - metric: KeyPath，\.pct5h 或 \.pct7d
///   - lookback: 默认 6h
///   - now: 默认 Date()，单测显式注入
/// - Returns: 数据不足 / flat (|Δ| < 1pp) / current 为 nil 时返回 nil
func computeTrend(
    currentPct: Double?,
    points: [UsageDataPoint],
    metric: KeyPath<UsageDataPoint, Double>,
    lookback: TimeInterval = 6 * 3600,
    now: Date = Date()
) -> TrendIndicator? {
    guard let current = currentPct else { return nil }
    let cutoff = now.addingTimeInterval(-lookback)
    let baselineCandidates = points.filter { $0.timestamp <= cutoff }
    // max(by: { $0.timestamp < $1.timestamp }) 返回 timestamp 最大者 = "≤ cutoff 中最新一点"
    // （Swift 语义：max(by:) 用比较谓词找"按谓词排序的最后一个"= 最大值）
    guard let baseline = baselineCandidates.max(by: { $0.timestamp < $1.timestamp }) else {
        return nil  // 数据不足
    }
    let baselinePct100 = baseline[keyPath: metric] * 100.0  // 0-1 → 0-100
    let delta = current - baselinePct100
    let absDelta = abs(delta)
    if absDelta < 1.0 { return nil }  // flat
    return TrendIndicator(
        direction: delta > 0 ? .up : .down,
        deltaPct: Int(absDelta.rounded())  // .rounded() 而非截断（边界 1.4→1, 1.5→2）
    )
}
```

### 3.3 `UsageHeroCard` 接口扩展

```swift
struct UsageHeroCard: View {
    let size: UsageCardSize
    let label: String
    let bucket: UsageBucket?
    var trend: TrendIndicator? = nil  // 默认 nil 不破坏现有 call site

    // body label 行：
    HStack(alignment: .firstTextBaseline) {
        Text(label).font(labelFont).foregroundStyle(.secondary)
        if let trend {
            Text(trendText(for: trend))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(trend.direction == .up ? .red : .green)
        }
        Spacer()
        if let countdown { ... }
    }

    private func trendText(for t: TrendIndicator) -> String {
        let arrow = t.direction == .up ? "▲" : "▼"
        return "\(arrow) \(t.deltaPct)%"
    }
}
```

### 3.4 `PopoverView.usageView` 改动

```swift
let trend5h = computeTrend(
    currentPct: service.usage?.fiveHour?.utilization,
    points: historyService.history.dataPoints,
    metric: \.pct5h
)
let trend7d = computeTrend(
    currentPct: service.usage?.sevenDay?.utilization,
    points: historyService.history.dataPoints,
    metric: \.pct7d
)

UsageHeroCard(size: .hero, label: "5-Hour", bucket: service.usage?.fiveHour, trend: trend5h)
UsageHeroCard(size: .secondary, label: "7-Day", bucket: service.usage?.sevenDay, trend: trend7d)
```

### 3.5 测试

`TrendCalculatorTests`（≥4 case）：
- `testUpTrend`: baseline 40%, current 50%, lookback 6h → `(.up, 10)`
- `testDownTrend`: baseline 60%, current 55%, lookback 6h → `(.down, 5)`
- `testFlat`: baseline 50%, current 50.4%, lookback 6h → nil
- `testInsufficientData`: history 只有 ≤1h 的点，lookback 6h → nil
- 可选 `testNilCurrent`: currentPct nil → nil
- 可选 `testRoundingBoundary`: delta = 1.4 → rounded 1（仍显示）；delta = 0.9 < 1 → nil

每测构造 `let now = Date()` 并显式两参传同一 now（与 v0.0.8 约定一致）。

### 3.6 Implementation plan（G3 对象）

**Step P0** — spec + version + 索引（Commit A，仅文档）
- 升 v0.0.9 placeholder→planned；includes_specs；删 guardrail
- specs/README.md / versions/README.md 索引同步
- **Success**: linkcheck ✅ frontmatter ✅；spec.status=accepted（G2 通过）
- **覆盖 SC**: 无

**Step P1** — 新增 TrendCalculator.swift + 单测（Commit B）
- 新增 `Sources/.../TrendCalculator.swift`（TrendDirection / TrendIndicator / computeTrend，含 G2 review B1 修订后的单位约定与 baseline *100 转换）
- 新增 `Tests/.../TrendCalculatorTests.swift`（≥4 case + 边界）
- **Success**: `swift test --filter TrendCalculatorTests` ≥4/≥4 ✅；`swift build -c release` 绿
- **覆盖 SC**: SC1, SC2（仅 Calculator + 测试；SC5/SC6 evidence 推迟到 P2 接入后统一收集，因 SC6 措辞含 service.usage 接入侧取值源 — G3 review B1 修订）

**Step P2** — UsageHeroCard 加 trend 参数 + PopoverView 接入（Commit C，刻意合并以便整体 revert）
- UsageHeroCard 接口加 `var trend: TrendIndicator? = nil`，body label 行加 trend Text
- UsageHeroCard #Preview 加含 trend 的示例（up + down 各 1）
- PopoverView usageView 计算 trend5h / trend7d 并传入
- **Success**: `swift build -c release && swift test` 全绿；启动 .app 进程不崩
- **覆盖 SC**: SC3, SC4, SC5, SC6, SC7, SC9, SC10
- **Manual checklist**（不计入 success criteria，但实施时勾选）：grep 确认 UsageBucketRow / ExtraUsageRow / UsageChartView / Settings 各文件无 trend 引用（SC8 反向断言，G3 review R1 修订）

**G5 gate** — 独立 reviewer code-review（codex-rescue / general-purpose subagent fallback）
- **Reviewer focus 提示**（G3 review R3 修订）：(a) trend 显示与 hero 容器视觉协调（不挤压 reset countdown）；(b) PopoverView 数据流接入正确性（trend5h 传给 5h bucket、trend7d 传给 7d bucket，无错位）；(c) 单位 100x bug 复检（B1 是否真的修了）；(d) commit B/C 独立可 revert
- verdict 落 spec.reviews

**Step P3** — G6 收尾（Commit D）
- spec.status accepted → implemented；reviews append G5 + G6
- spec_criteria SC 全 done；Verification log 全 [x]
- specs/README + versions/README 索引同步
- versions/v0.0.9 status planned → in-progress + G6 checklist + release_notes_zh
- CHANGELOG append v0.0.9 entry
- **覆盖 SC**: SC11, SC12

**Commit 拆分**：A（P0 文档）/ B（P1 Calculator + 测试，纯逻辑无视觉）/ C（P2 hero card + popover 接入，**刻意合并** — UsageHeroCard 加默认 nil 参数后理论上可单独编译，但视觉变更集中 commit 利于"trend 显示有问题"时整体 revert，G3 review R2 修订）/ D（P3 G6 收尾，G5 verdict 落地后）

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🆕 | `macos/Sources/ClaudeUsageBar/TrendCalculator.swift` | TrendDirection enum + TrendIndicator struct + computeTrend func |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/TrendCalculatorTests.swift` | ≥4 case |
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageHeroCard.swift` | 加 `var trend: TrendIndicator? = nil` 参数；label 行加 trend Text 显示；#Preview 补 trend 示例 |
| 🔧 | `macos/Sources/ClaudeUsageBar/PopoverView.swift` | usageView 计算 trend5h / trend7d 传入 UsageHeroCard |
| 🔧 | `docs/versions/v0.0.9-trend-arrows.md` | placeholder→planned→in-progress |
| 🔧 | `docs/versions/README.md` / `docs/superpowers/specs/README.md` | 索引同步 |
| 🔧 | `CHANGELOG.md` | append v0.0.9 entry |
| ✅ 不动 | UsageHistoryService / UsageHistoryModel / UsageService / OAuth / Settings / Notifications / UsageChartView / SetupView / CodeEntryView | trend 仅消费 history.dataPoints，不改写 |

## 5. 风险 / Open questions

1. **新用户首 6h 看不到 trend**：合理，spec §1 明示数据不足不显示。无对策。
2. **history.dataPoints @Published 触发频繁刷新**：每次 polling 会新增一个 point + flushTimer 5min 写盘。SwiftUI 视图重渲染本来就跟 service.usage 走，trend 重算 O(n) 在 30 天 history（最多约 30 \* 24 \* 60 / pollInterval ≈ 千条量级）下 < 1ms，无性能压力。
3. **lookback 6h 边界附近 baseline 抖动**：算法用 "≤ cutoff 的最新一点"，不会因为时间点恰好跨越 6h 而跳变（只会随时间推进逐渐替换 baseline）。
4. **app 离线超过 6h 后冷启**：history 仍有更老的点 → baseline 取最新的"≤ cutoff" 点，可能是 8h / 12h 前的，trend 仍能算但 lookback 实际 > 6h。**接受**：用户冷启时显示一个"久违的趋势"比不显示更有信息量；后续版本可加 max-age 阈值。
5. **flat threshold 1pp 是否合理**：经验值，无确切数据。竞品调研 `competitive-analysis.md` §1.3 仅记录 SessionWatcher 显示 `▼2%` 形态，未给出具体 threshold 数值。1pp 兼顾 polling ±0.5pp 抖动与"明显趋势"直觉；未来若用户反馈"太敏感"或"该显示却不显示"可调整或做 settings 项。
7. **a11y 已知降级**：trend 文本（▲▼ + 数字）是视觉专属信息，无 `.accessibilityLabel` → VoiceOver 用户感知不到趋势。v1.0 a11y audit（v1.0 硬清单 #12）前为已知可接受降级，与 ADR 0003 AI-led 节奏一致。
6. **trend 显示对 label 文本宽度的挤压**：hero 模式 label 用 .subheadline，trend 用 .caption2，两者窄；360pt 容器内宽度 OK。secondary 模式 label 已经 .caption，更窄。无回归。

## 6. 后续工作（不在本 spec 范围）

- 菜单栏紧凑模式中的趋势 → v0.0.10 spec
- 可配置 lookback（5min / 1h / 6h / 1d 切换）→ 后续 settings 增项
- ExtraUsage / Per-Model trend（需要扩展 UsageDataPoint 模型）→ 单独 spec
- "BestToolNow" / pace tracking 算法 → v0.0.11
- a11y label（"上升 5 个百分点"）→ v1.0 a11y audit

## 7. 引用

- 调研：[`docs/research/competitive-analysis.md`](../../research/competitive-analysis.md) §1.3
- 母法：[`2026-05-11-docs-governance.md`](./2026-05-11-docs-governance.md)
- 落地版本：[`docs/versions/v0.0.9-trend-arrows.md`](../../versions/v0.0.9-trend-arrows.md)
- 前置 spec：[`2026-05-11-hero-popover.md`](./2026-05-11-hero-popover.md)（v0.0.8 提供 UsageHeroCard 容器）

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [ ] SC1 — pending
- [ ] SC2 — pending
- [ ] SC3 — pending
- [ ] SC4 — pending
- [ ] SC5 — pending
- [ ] SC6 — pending
- [ ] SC7 — pending
- [ ] SC8 — pending
- [ ] SC9 — pending
- [ ] SC10 — pending
- [ ] SC11 — pending
- [ ] SC12 — pending
