---
id: 2026-05-11-pace-tracking
title: 5h 配速指示器（On pace / In deficit / In reserve + Runs out 估算）
status: implemented
created: 2026-05-11
updated: 2026-05-11
owner: claude-code
model: claude-opus-4-7
target_version: v0.0.11
related_adrs: [0001, 0002]
related_research: [competitive-analysis]
spec_criteria:
  - id: SC1
    criterion: "新增 macos/Sources/ClaudeUsageBar/PaceCalculator.swift：含 enum PaceState (.onPace / .inDeficit(percentOver:Int, runsOutIn:TimeInterval) / .inReserve(percentUnder:Int)) + 顶层纯函数 computePaceState(currentPct:resetDate:windowDuration:now:) -> PaceState?"
    done: true
    evidence: "see ## Verification log"
  - id: SC2
    criterion: "新增 macos/Tests/ClaudeUsageBarTests/PaceCalculatorTests.swift，≥6 case：onPace（小偏差 < 3pp）/ inDeficit（actual 远超 expected）/ inReserve（actual 远低 expected）/ early window（elapsed/total < 3% 返回 nil）/ resetDate nil 返回 nil / runsOut 不超过 reset 剩余时间"
    done: true
    evidence: "see ## Verification log"
  - id: SC3
    criterion: "UsageHeroCard 增加可选 pace 参数（默认 nil 不破坏 v0.0.8/9/10 现有 call site）"
    done: true
    evidence: "see ## Verification log"
  - id: SC4
    criterion: "hero 卡片在 progress bar 下方显示 pace 单行文本：.inDeficit → 'N% over pace · runs out in <countdown>'（红色）；.inReserve → 'N% under pace'（绿色）；.onPace 不显示（默认状态无需打扰）；nil 不显示"
    done: true
    evidence: "see ## Verification log"
  - id: SC5
    criterion: "PopoverView usageView 把 5h fiveHour bucket 传入 computePaceState 算 pace 给 5h hero card；7d 不显示 pace（windowDuration 7d 与即时 rate 外推无意义；spec §1 显式排除）"
    done: true
    evidence: "see ## Verification log"
  - id: SC6
    criterion: "early window 隐藏：elapsed / windowDuration < 0.03 时返回 nil（避免新窗口刚开 actual 接近 0、expected 也接近 0、噪声放大产生抖动）"
    done: true
    evidence: "see ## Verification log"
  - id: SC7
    criterion: "flat threshold：|actual_pct - expected_pct| < 3pp 视为 .onPace（与 v0.0.9 trend 1pp 不同：pace 比较的是预期偏差，3pp 才是有意义的'过快/过慢'信号）"
    done: true
    evidence: "see ## Verification log"
  - id: SC8
    criterion: "inDeficit 'runs out in' 估算：rate = currentPct / elapsed (pct/sec)；runsOutIn = (100 - currentPct) / rate；clamp 到 (resetDate - now) — 即如果按当前 rate 算下来比 reset 还远则其实不会用完，提示 .onPace"
    done: true
    evidence: "see ## Verification log"
  - id: SC9
    criterion: "cd macos && swift build -c release 输出 'Build complete!'"
    done: true
    evidence: "see ## Verification log"
  - id: SC10
    criterion: "cd macos && swift test 'Executed N tests, with 0 failures'（含新增 PaceCalculatorTests ≥6 case）"
    done: true
    evidence: "see ## Verification log"
  - id: SC11
    criterion: "git commit 中文、含变更主题 + spec id；spec.reviews 数组含 G2、G3、G5、G6 四条 verdict"
    done: true
    evidence: "see ## Verification log"
  - id: SC12
    criterion: "version v0.0.11 frontmatter status placeholder→planned→in-progress；CHANGELOG.md append v0.0.11 中文 entry"
    done: true
    evidence: "see ## Verification log"
automated_checks:
  - "SC_AUTO_BUILD: cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release 2>&1 | tail -3 | grep -q 'Build complete'"
  - "SC_AUTO_TEST: cd /Users/methol/data/code-methol/usage-bar/macos && swift test 2>&1 | tail -5 | grep -E 'Executed [0-9]+ test.*0 failures'"
manual_checks:
  - "登录 .app 累积一定使用后，目视确认 5h hero 卡片下方 pace 文本：消耗较快时显示 'X% over pace · runs out in 2h 30m'（红）；较慢时 'X% under pace'（绿）；持平/早期窗口不显示"
  - "P2 commit 后 git diff --stat 确认仅触：PaceCalculator.swift（新）/ PaceCalculatorTests.swift（新）/ UsageHeroCard.swift / PopoverView.swift；其他文件无改动（SC8 反向断言）"
  - "**视觉验证 fallback**（G3 R2 修订）：本地 token 多数处于 onPace 静默状态难以目视验证 inDeficit/inReserve 分支；改用 Xcode 打开 UsageHeroCard.swift 看 #Preview 中 pace 三档示例（onPace 不显示 / inDeficit 红色 + runs out in / inReserve 绿色）作为视觉证据"
  - "G5 时目视 popover 总高度无溢出（hero card +14pt for pace 行；估算总高度 ~470pt；与 §5#7 风险交叉验证）"
  - "已知精度限制（G5 R3）：runsOutIn < 60s 时 formatResetCountdown 返回 '<1m'，hero card 显示 'runs out in <1m'；语义略不同于 reset countdown，但属可接受精度取舍"
reviews:
  - gate: G2
    reviewer: codex:codex-rescue (general-purpose fallback, agentId a7e5f253896b78262)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（3 必要修改 + 多条 OK/WARN 注解）。
      作者按 superpowers:receiving-code-review 流程：
      - 必要修改 #1（reset 已过 + inReserve 路径误导）accepted — §3.2 把
        timeToReset > 0 早退提到 deviation 判断之前，避免 deviation<0 时误返回
        .inReserve；新增 testPastReset case 覆盖此分支。
      - 必要修改 #2（currentPct=100 → runsOutIn=0 → "—" edge case）accepted —
        §3.3 paceText 注释明示此降级显示 "runs out in —"，UX 略奇但可接受不引入
        特殊路径；P1 必含 testInDeficitWith100Pct case。
      - 必要修改 #3（hero+trend+pace 卡片高度增量）accepted — §5#7 新增风险条目
        估算 +14pt → ~470pt，远低于屏幕可用高度；G5 manual check 目视确认。
      - WARN/OK 注解全部 confirmed（算法路径 b/c/d/e/f/g 均自洽，单位约定与
        v0.0.9 trend 一致，3pp 阈值合理，formatResetCountdown 复用合规）。
      修订后 spec.status 升 accepted。
    artifacts: ["G2 review subagent output (agentId a7e5f253896b78262)"]
  - gate: G3
    reviewer: claude-code (general-purpose subagent, agentId a8f603c9071d33ae6)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（1 BLOCKING + 4 RECOMMENDED）。
      作者按 superpowers:receiving-code-review 流程：
      - B1（P1 success 漏边界 case 显式点名 testRunsOutBeyondReset / testPastReset
        / testNilCurrent）accepted — P1 success 显式列出 5 个必含边界 case，
        避免实施 AI 只写 happy path。
      - R1（P2 success 拆功能 SC vs 门禁 SC）accepted — §3.6 P2 success 重写为
        分组（功能 SC3/4/5 + 门禁 SC9/10）。
      - R2（manual_check 加 #Preview fallback）accepted — manual_checks 增加
        "改用 Xcode #Preview 看 pace 三档示例" 作为视觉验证可靠路径。
      - R3（P0 success 错把"G2 通过"作为 P0 完成判据）accepted — §3.6 P0 success
        改为 linkcheck/frontmatter/version status；G2 verdict 是 P0 commit 前的
        前置 gate，正交。
      - R4（G5 reviewer focus 显式点名 rate≤0 / timeToReset≤0 / currentPct=100）
        accepted — §3.6 G5 gate (a) 加 5 个具体 guard 路径点名。
      所有 NOTES confirmed ✅
    artifacts: ["G3 review subagent output (agentId a8f603c9071d33ae6)"]
  - gate: G5
    reviewer: codex:codex-rescue (general-purpose fallback, agentId a9a2a1af3ade9a173)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（1 BLOCKING + 3 RECOMMENDED + 3 NOTES）。
      作者按 superpowers:receiving-code-review 流程：
      - B1（UsageHeroCard.swift paceText 双 Date() 时钟竞争，可能让 secs<=0
        误降级 "—"）accepted — commit f19c943 用 `let now = Date()` 一次快照，
        `formatResetCountdown(date: now+runsOutIn, now: now)` 同源。
      - R1（PaceCalculator runsOutIn>=timeToReset defensive guard 缺 inline 注释）
        accepted — commit f19c943 加注释说明数学上 deviation>0+rate>0 时不可达，
        保留作浮点精度兜底。
      - R2（PopoverView pace5h 重渲染 perf TODO）accepted — commit f19c943
        usageView pace5h 前加 TODO(perf) 与 v0.0.9 trend 同款。
      - R3（spec manual_check 加 "<1m" 精度限制说明）accepted — manual_checks
        新增条目，本 G6 commit 落地。
      - N1~N3（commit 独立 revert / 无破坏性 / Preview 覆盖）confirmed ✅
    artifacts: ["G5 review subagent output (agentId a9a2a1af3ade9a173)", "commit f19c943"]
  - gate: G6
    reviewer: claude-code (main session, automated checks + manual UI verification deferred)
    date: 2026-05-11
    verdict: approved
    summary: |
      G6 merge 前验收：spec_criteria SC1~SC12 全部 done=true。
      - 自动化：SC_AUTO_BUILD `swift build -c release` ✅；SC_AUTO_TEST
        `swift test` 78/78（含 9 PaceCalculatorTests + 9 MenuBarDisplayModeTests
        + 10 TrendCalculatorTests + 6 ResetCountdownFormatterTests）✅
      - 视觉验证：UsageHeroCard.swift #Preview 含 4 张 pace 示例
        （inDeficit / inReserve / 7d nil / onPace）供 Xcode 看；菜单栏 popover
        pace 由用户累积 5h 窗口期间目视确认（manual_checks）
      - 治理流程：G2 / G3 / G5 三轮独立 reviewer 共 5 BLOCKING + 11 RECOMMENDED
        全数受理或 reasoned reject；G2 独立命中 reset 已过 + inReserve 误导路径
        与 currentPct=100 edge case；G5 命中双 Date() 时钟竞争
      G6 通过 → spec status: accepted → implemented。
    artifacts: ["scripts/linkcheck (inline python ✅)", "scripts/frontmatter-lint (inline python ✅)", "swift test 78/78 ✅"]
---

# 5h 配速指示器（On pace / In deficit / In reserve + Runs out 估算）

## 1. 背景与目标

竞品调研 §2.7 指出 CodexBar 的 *Pace tracking*：把"按均匀消耗预期的当前用量"与"实际用量"对比，分 On pace / In deficit / In reserve 三态，deficit 时给 *Runs out in N* 估算。这让用户在还没触阈值时就感知到"我用得太快了"。

我们当前 PopoverView 只显示静态百分比 + (v0.0.9) 6h 趋势。趋势答的是"涨还是落"；pace 答的是"现在的速率能不能撑到 reset"。两者互补。

本 spec 引入 5h 窗口的 pace 指示器，显示在 hero card 进度条下方。

**不在范围**：
- **不做 7d window 的 pace** — 7d 窗口太长，按"线性外推"假设过强；调研 §2.7 提到 CodexBar 也仅在 5h 用 pace 而非 7d。spec §3 算法仅接 5h
- **不做 ML / 历史驱动的非均匀 pace**（Codex 有但我们不做）— 调研明确避免 "ML / 95% accuracy" 营销话术
- **不做菜单栏 pace 显示** — 菜单栏空间已被 v0.0.10 percent+trend 占满；pace 留 popover 显示
- **不做通知**（"还有 30 分钟用完"） — 留后续 NotificationService 扩展
- **不做 Per-Model / Extra pace** — 数据语义不同（Per-Model 没有独立 reset 周期）
- **a11y `.accessibilityLabel`** — 留 v1.0 audit

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| Window | 仅 5h | 7d 线性外推假设过强；调研 §2.7 同款决策 |
| Flat threshold | 3pp（|actual - expected| < 3pp = onPace） | 比 trend 的 1pp 宽，因为 pace 是"超预期 / 不及预期"的判断，需要更明显的偏差才有意义 |
| Early window 隐藏 | elapsed/total < 3% | 与调研 §2.7 一致；新窗口刚开时 actual≈0 / expected≈0，噪声放大 |
| Runs out 估算 | rate = currentPct / elapsed；runsOutIn = (100 - currentPct) / rate | 简单线性外推；clamp 到 reset 剩余时间内 |
| 数据来源 | 实时 service.usage.fiveHour.utilization + resetsAtDate | 不依赖 history（与 trend 不同）— pace 是"瞬时速率推算" |
| Window 起点推断 | resetDate - 5h | resetsAtDate 是"窗口结束时刻"；起点 = end - 5h |
| 显示位置 | hero card progress bar 下方独立 .caption2 行 | 不与 label/trend/countdown 抢空间 |
| onPace 不显示 | 默认状态无需打扰用户 | 与 trend flat 静默同款心智 |
| 颜色 | inDeficit→.red / inReserve→.green | 与 trend 同向（红=用量风险高） |
| 文本格式 | inDeficit: 'N% over pace · runs out in HhMm'；inReserve: 'N% under pace' | inReserve 不需 "lasts until reset" 后缀（多余信息） |

## 3. 设计

### 3.1 数据流

```
service.usage?.fiveHour?.utilization (实时, 0-100)
service.usage?.fiveHour?.resetsAtDate (Date?)
                  │
                  ▼
PopoverView.usageView
  ├─ pace5h = computePaceState(currentPct:, resetDate:, windowDuration: 5*3600, now: Date())
  └─ UsageHeroCard(.hero, "5-Hour", bucket, trend: trend5h, pace: pace5h)
```

### 3.2 `PaceCalculator.swift`

```swift
import Foundation

enum PaceState: Equatable {
    case onPace
    case inDeficit(percentOver: Int, runsOutIn: TimeInterval)
    case inReserve(percentUnder: Int)
}

/// 计算 5h 窗口配速状态。
///
/// 算法：
/// 1. window_start = resetDate - windowDuration；elapsed = now - window_start
/// 2. elapsedFraction < 0.03 → 返回 nil（早期窗口噪声大，隐藏避免抖动）
/// 3. expected_pct = elapsedFraction * 100（均匀消耗预期）
/// 4. deviation = currentPct - expected_pct
/// 5. |deviation| < 3pp → .onPace
/// 6. deviation > 0：rate = currentPct / elapsed (pct/sec)；runsOutIn = (100 - currentPct) / rate
///    clamp runsOutIn 到 (resetDate - now)；若 runsOutIn ≥ resetDate-now 实际不会耗尽，降级 .onPace
/// 7. deviation < 0 → .inReserve
func computePaceState(
    currentPct: Double?,
    resetDate: Date?,
    windowDuration: TimeInterval = 5 * 3600,
    now: Date = Date()
) -> PaceState? {
    guard let current = currentPct, let reset = resetDate else { return nil }
    let timeToReset = reset.timeIntervalSince(now)
    // G2 修订：reset 已过统一早退为 .onPace，避免 deviation<0 时误返回 .inReserve
    guard timeToReset > 0 else { return .onPace }
    let windowStart = reset.addingTimeInterval(-windowDuration)
    let elapsed = now.timeIntervalSince(windowStart)
    guard elapsed > 0 else { return nil }
    let elapsedFraction = elapsed / windowDuration
    guard elapsedFraction >= 0.03 else { return nil }
    let expectedPct = elapsedFraction * 100.0
    let deviation = current - expectedPct
    let absDeviation = abs(deviation)
    if absDeviation < 3.0 { return .onPace }
    if deviation > 0 {
        let rate = current / elapsed   // pct/sec
        guard rate > 0 else { return .onPace }
        let remaining = 100.0 - current
        let runsOutIn = remaining / rate
        if runsOutIn >= timeToReset { return .onPace }  // 能撑到 reset
        return .inDeficit(percentOver: Int(absDeviation.rounded()), runsOutIn: runsOutIn)
    } else {
        return .inReserve(percentUnder: Int(absDeviation.rounded()))
    }
}
```

### 3.3 `UsageHeroCard` 接口扩展

```swift
struct UsageHeroCard: View {
    let size: UsageCardSize
    let label: String
    let bucket: UsageBucket?
    var trend: TrendIndicator? = nil
    var pace: PaceState? = nil   // 新增

    // body 在 CapsuleProgressBar 之后追加：
    if let paceText {
        Text(paceText.text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(paceText.color)
    }

    private var paceText: (text: String, color: Color)? {
        guard let pace else { return nil }
        switch pace {
        case .onPace: return nil  // 不显示
        case .inDeficit(let percentOver, let runsOutIn):
            let countdown = formatResetCountdown(date: Date().addingTimeInterval(runsOutIn), now: Date()) ?? "—"
            return ("\(percentOver)% over pace · runs out in \(countdown)", .red)
        case .inReserve(let percentUnder):
            return ("\(percentUnder)% under pace", .green)
        }
    }
}
```

> 复用 v0.0.8 `formatResetCountdown` 把 TimeInterval 转成 "1h 23m" 紧凑格式。
> **edge case**（G2 修订）：currentPct=100 时 remaining=0 → runsOutIn=0 → formatResetCountdown 返回 nil → 显示 "runs out in —"。语义为"已耗尽"，UX 略奇但可接受；不引入特殊路径避免代码复杂化。

### 3.4 `PopoverView.usageView` 改动

```swift
let pace5h = computePaceState(
    currentPct: service.usage?.fiveHour?.utilization,
    resetDate: service.usage?.fiveHour?.resetsAtDate
)

UsageHeroCard(size: .hero, label: "5-Hour", bucket: ..., trend: trend5h, pace: pace5h)
UsageHeroCard(size: .secondary, label: "7-Day", bucket: ..., trend: trend7d)  // 不传 pace
```

### 3.5 测试

`PaceCalculatorTests`（≥6 case）：
- `testOnPaceSmallDeviation`: elapsed=2.5h (50%), current=51% → |Δ|=1 < 3 → .onPace
- `testInDeficit`: elapsed=2.5h, current=70% → Δ=+20，rate=0.0078%/sec, remaining=30, runsOutIn ≈ 3846s ≈ 1h4m；clamp 检查（reset 剩 2.5h，runsOutIn < reset → .inDeficit）
- `testInReserve`: elapsed=2.5h, current=30% → Δ=-20 → .inReserve(percentUnder: 20)
- `testEarlyWindowHidden`: elapsed=5min (1.7%), current=10% → return nil
- `testNilResetDate`: resetDate=nil → return nil
- `testRunsOutBeyondReset`: 用量稍超预期但 rate 算下来仍能撑到 reset → 降级 .onPace
- `testNilCurrent`: currentPct=nil → return nil
- `testPastReset`: resetDate < now → .onPace（容错）

### 3.6 Implementation plan（G3 对象）

**Step P0** — spec + version + 索引（Commit A，仅文档）
- 升 v0.0.11 placeholder→planned；删 guardrail；填 includes_specs
- specs/README.md / versions/README.md 索引同步
- **Success**: linkcheck ✅；frontmatter ✅；version frontmatter status placeholder→planned（G3 R3 修订：G2 verdict 是 P0 commit 前的前置 gate，由 reviewer 落定，与 P0 step 完成判据正交，不写入 success criteria）
- **覆盖 SC**: 无

**Step P1** — 新增 PaceCalculator.swift + 单测（Commit B，pure logic）
- 新增 `PaceCalculator.swift`（PaceState + computePaceState）
- 新增 `PaceCalculatorTests.swift`（≥6 case）
- **必含边界 case**（G3 B1 修订，避免实施 AI 只写 happy path）：
  - `testRunsOutBeyondReset`（rate 算下来能撑到 reset 降级 .onPace）
  - `testPastReset`（reset 已过返回 .onPace，覆盖 G2 修订的统一早退路径）
  - `testNilCurrent` / `testNilResetDate`（任一 nil 返回 nil）
  - `testEarlyWindowHidden`（elapsedFraction < 0.03 返回 nil）
  - `testInDeficitWith100Pct`（currentPct=100 → runsOutIn=0 → .inDeficit；formatResetCountdown 接 0 返回 nil 由 UI 层处理 "—"）
- **Success**: `swift test` 全集（防命名冲突）全绿；上述边界 case 必须存在并通过；`swift build -c release` 绿
- **覆盖 SC**: SC1, SC2, SC6, SC7, SC8

**Step P2** — UsageHeroCard 加 pace + PopoverView 接入（Commit C，刻意合并）
- UsageHeroCard 加 `var pace: PaceState? = nil` + body 在 progress bar 后追加 paceText 行
- UsageHeroCard #Preview 升级含 pace 三档示例（onPace / inDeficit / inReserve）— 作为 manual_check 的视觉验证 fallback（G3 R2 修订：本地 token 默认处于 onPace 不显示，#Preview 是验证 inDeficit/inReserve 视觉的可靠路径）
- PopoverView usageView 计算 pace5h 传入 5h hero card
- **Success**:
  - 功能 SC（G3 R1 修订拆分）：SC3 hero card 加参数 + SC4 paceText 三态显示 + SC5 popover 接入 5h
  - 门禁 SC：SC9 `swift build -c release` 绿 + SC10 `swift test` 全绿
  - 启动 .app 进程不崩
- **覆盖 SC**: SC3, SC4, SC5, SC9, SC10

**G5 gate** — 独立 reviewer code-review（codex-rescue / general-purpose subagent fallback）
- **Reviewer focus**：
  - (a) computePaceState 算法正确性，**显式点名以下 guard 路径**（G3 R4 修订）：`rate <= 0` / `timeToReset <= 0` / `currentPct = 100` / `elapsed <= 0` / `elapsedFraction < 0.03`
  - (b) 单位约定与 v0.0.9 trend 一致（current 0-100 直接传 utilization）
  - (c) UsageHeroCard pace 行视觉与 trend 协调（不冲突 + 卡片高度增量 ~+14pt 在 popover 总高度可接受范围）
  - (d) commit B/C 独立 revert
  - (e) 无破坏性变更（trend 仍工作）

**Step P3** — G6 收尾（Commit D）
- spec.status accepted → implemented；reviews append G5 + G6
- spec_criteria SC 全 done；Verification log 全 [x]
- specs/README + versions/README 索引同步
- versions/v0.0.11 status planned → in-progress + G6 checklist + release_notes_zh
- CHANGELOG append v0.0.11 entry
- **覆盖 SC**: SC11, SC12

**Commit 拆分**：A（P0 文档）/ B（P1 Calculator + 测试，纯逻辑）/ C（P2 hero card + popover 接入，视觉变更集中）/ D（P3 G6 收尾，G5 verdict 落地后）

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🆕 | `macos/Sources/ClaudeUsageBar/PaceCalculator.swift` | PaceState enum + computePaceState func |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/PaceCalculatorTests.swift` | ≥6 case |
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageHeroCard.swift` | 加 var pace + body 追加 paceText 行 + #Preview 补 pace 示例 |
| 🔧 | `macos/Sources/ClaudeUsageBar/PopoverView.swift` | usageView 计算 pace5h 传入；7d hero 不传 |
| 🔧 | `docs/versions/v0.0.11-pace-tracking.md` / `docs/versions/README.md` / `docs/superpowers/specs/README.md` | 索引同步 |
| 🔧 | `CHANGELOG.md` | append v0.0.11 entry |
| ✅ 不动 | UsageService / UsageHistoryService / TrendCalculator / MenuBarLabel / Settings / 数据层 / OAuth | pace 完全本地计算，复用 v0.0.8 formatResetCountdown 与 v0.0.9 hero card 容器 |

## 5. 风险 / Open questions

1. **rate 线性外推假设过强**：用户可能短时高峰然后停止，pace 仍按当前 rate 外推会高估 deficit。可接受 — 调研明确避免"ML"路线；用户对"按当前速率"的解读是直觉的。
2. **runsOutIn clamp 后降级 .onPace 的边界**：如果 actual 超 expected 但 rate 算下来能撑到 reset，逻辑上是 .onPace（因为最终不会用完），与"deficit"的字面含义稍冲突。spec 选择 .onPace 是更友好的 UX（不必要的告警）。
3. **resetDate parsing 偶尔失败 → resetsAtDate nil**：v0.0.6 已有 reconcile 逻辑保留前一次有效 resetDate；本 spec 直接读 bucket?.resetsAtDate，如 nil 则 pace 静默 nil 不显示。
4. **窗口跨 reset 边界**：windowStart = resetDate - 5h，假设 reset 周期就是 5h。如果未来 Anthropic 改窗口长度，本算法过期。可接受 — UsageBucket.utilization 同样依赖此假设。
5. **pace 文本宽度**：'15% over pace · runs out in 1h 23m' ≈ 35 字符。在 360pt frame .caption2 字号下应能放下；如果某些极端文案超长会自动 truncate（SwiftUI Text 默认）。
6. **a11y 已知降级**：与 v0.0.9/10 noted；v1.0 audit 处理。
7. **hero card 高度增量**（G2 必要修改 #3）：v0.0.8 hero card 高度估 ~80pt（label / hero 数字 / progress bar）；v0.0.9 trend 仍在 label 行内不增高；v0.0.11 pace 在 progress bar 下方加一行 .caption2 ≈ +14pt → ~94pt。secondary 卡片高度不变（不显示 pace）。总 popover 高度估算 ~470pt（vs v0.0.10 ~450pt），仍远低于 macOS 屏幕可用高度。G5 manual check 目视确认无溢出。

## 6. 后续工作（不在本 spec 范围）

- 7d 窗口的 pace（需要不同算法假设） → 后续 spec
- 历史驱动的非均匀 pace（参考 ccusage block 概念） → 后续 spec（如做）
- pace 触发的通知（"还有 30 分钟用完"） → NotificationService 扩展 spec
- 菜单栏 pace 显示模式 → menubar-display-modes 扩展 spec
- a11y label → v1.0 audit

## 7. 引用

- 调研：[`docs/research/competitive-analysis.md`](../../research/competitive-analysis.md) §2.7
- 母法：[`2026-05-11-docs-governance.md`](./2026-05-11-docs-governance.md)
- 落地版本：[`docs/versions/v0.0.11-pace-tracking.md`](../../versions/v0.0.11-pace-tracking.md)
- 前置：v0.0.8 hero-popover（UsageHeroCard 容器）/ v0.0.9 trend-arrows（formatResetCountdown 复用）

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [x] SC1 — evidence: commit `b9021f5` 新增 PaceCalculator.swift（PaceState enum + computePaceState）
- [x] SC2 — evidence: commit `b9021f5` 新增 PaceCalculatorTests.swift 9 case（含 G3 B1 必含 testRunsOutBeyondReset / testPastReset / testNilCurrent / testNilResetDate / testEarlyWindowHidden / testInDeficitWith100Pct）
- [x] SC3 — evidence: commit `0a39f21` UsageHeroCard.swift 加 `var pace: PaceState? = nil`，default nil 不破坏现有 call site
- [x] SC4 — evidence: commit `0a39f21` paceText computed property 三态：onPace→nil / inDeficit→红色 + runs out in / inReserve→绿色；commit `f19c943` G5 B1 修双 Date() 竞争
- [x] SC5 — evidence: commit `0a39f21` PopoverView.usageView 计算 pace5h 传入 5h hero；7d 不传（默认 nil）
- [x] SC6 — evidence: PaceCalculator early window guard `elapsedFraction >= 0.03 else return nil`，testEarlyWindowHidden 验证
- [x] SC7 — evidence: PaceCalculator `if absDeviation < 3.0 { return .onPace }`，testOnPaceSmallDeviation 验证
- [x] SC8 — evidence: PaceCalculator runsOutIn = (100-current)/rate；defensive guard `runsOutIn >= timeToReset → onPace`（commit f19c943 加 inline 注释说明数学不可达）
- [x] SC9 — evidence: `cd macos && swift build -c release` 输出 `Build complete!`
- [x] SC10 — evidence: `cd macos && swift test` `Executed 78 tests, with 0 failures` ✅
- [x] SC11 — evidence: 5 个中文 commit 均含 spec id（62e310b / b9021f5 / 0a39f21 / f19c943 / 本 commit）；spec.reviews 含 G2 / G3 / G5 / G6 共 4 条 verdict
- [x] SC12 — evidence: version v0.0.11 frontmatter status placeholder→planned（commit 62e310b）→in-progress（本 commit）；CHANGELOG.md append v0.0.11 entry（本 commit）
