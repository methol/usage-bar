# 用量统计与存储重设计 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本地 Claude CLI 用量从 v0.1.2 的一次性 30 天估算，升级为按 provider/UTC 年月分文件持久化 raw events + 按天/月/年聚合 + per-file 增量游标的存储层，并在 popover 加 GitHub 贡献图风格的消费热力图。

**Architecture:** 五个新 actor/服务（`UsageEventStore` 持磁盘 schema、`ScanCursorStore` 持扫描进度、`ClaudeUsageCollector` 增量采集、`UsageAggregator` 纯函数折算、`UsageStatsService` 是 @MainActor ObservableObject）+ 一个 SwiftUI 热力图 View。复用 v0.1.2 的 `JSONLCostParser`（schema 仍不读 `message.content`）和 `ClaudePricing`。退役 `LocalCostScanner`。USD 不落盘，前端按当前价格表实时折算。

**Tech Stack:** Swift 5.9 / SwiftUI / Foundation（`Codable` + `FileManager` + `JSONEncoder/Decoder`），SwiftPM（`cd macos && swift build/test`），XCTest。

**Spec:** [`docs/superpowers/specs/2026-05-12-usage-store-redesign.md`](../specs/2026-05-12-usage-store-redesign.md)（status: accepted；G2 通过）。任何与本 plan 不一致处以 spec 为准。

**关键约束（每个 commit 前必跑）:**
- `cd macos && swift build -c release` → `Build complete!`
- `cd macos && swift test` → `Executed N tests, with 0 failures`
- `! grep -nrI -E '(print|NSLog|os_log|os\.log|Logger)\s*[\(,].*([Aa]ccess[Tt]oken|[Rr]efresh[Tt]oken|rawJSON|claudeAiOauth|message\.content|jsonlLine|rawLine|lastPathComponent|sessionId|sessionUUID|fileURL|absJsonlPath|\.path\b|account\.credentials)' macos/Sources/UsageBar/` → 无输出
- `! grep -nrI -E 'sk-ant-(oat|ort|api)[0-9a-zA-Z]|sk-proj-[0-9a-zA-Z]|AKIA[0-9A-Z]{16}' macos/ docs/ CHANGELOG.md` → 无输出
- 测试 mock JSONL / fixture 全部手写，msgId 用 `msg_mock_...`、reqId 用 `req_mock_...`、sessionId 用 `00000000-mock-...`，绝不含真实 token 前缀。

---

## File Structure

| 文件 | 责任 |
|---|---|
| 🆕 `macos/Sources/UsageBar/UsageStoreTypes.swift` | 所有磁盘 schema 的 Codable 类型：`StoredUsageEvent`、`MonthDetailFile`、`TokenSums`、`AggregateFile`、`ScanCursorFile`、`UsageProvider` enum。无逻辑。 |
| 🆕 `macos/Sources/UsageBar/UsageEventStore.swift` | `actor UsageEventStore`：月明细 load / `mergeEvents`（UTC 月分组 + `(msgId,reqId)` 去重 union + atomic write 0600）；`rebuildAggregates(forDayKeys:)` / `rebuildAllAggregates()`；`queryEvents(from:to:)`；`readDayAggregates/readMonthAggregates/readYearAggregates`；目录创建 + 权限。 |
| 🆕 `macos/Sources/UsageBar/ScanCursorStore.swift` | `actor ScanCursorStore`：load/save `scan-cursor.json`；`nextReadOffset(for:currentSize:currentMTime:)`；`updateCursor` / `clearCursor`；损坏丢弃。 |
| 🆕 `macos/Sources/UsageBar/UsageAggregator.swift` | 纯函数（无状态、无 IO）：`foldByDay/foldByMonth/foldByYear(events:)`、`usdForBucket(_:)`、`rolling30dSummary(dayAggregates:now:)`、`dailySpend(from:)`、`monthlySpend(from:)`。 |
| 🆕 `macos/Sources/UsageBar/ClaudeUsageCollector.swift` | `actor ClaudeUsageCollector`：`collect() -> CollectResult`；`scanRoots`（沿用 v0.1.2 优先级）；增量读行 + 部分末行处理 + 空集跳过。 |
| 🆕 `macos/Sources/UsageBar/UsageStatsService.swift` | `@MainActor final class UsageStatsService: ObservableObject`：`@Published rolling30d / dailySpend / monthlySpend / isInitializing`；`refresh()`（Task.detached IO + MainActor.run 写回 + inFlight 节流）。 |
| 🆕 `macos/Sources/UsageBar/UsageHeatmapView.swift` | `struct UsageHeatmapModel`（纯数据：53 周整年网格 + USD→9 档映射）+ `struct UsageHeatmapView: View`。 |
| 🔧 `macos/Sources/UsageBar/UsageService.swift` | 删 `localCost30d` / `refreshLocalCostIfNeeded`；持 `usageStats` 单向强引用；polling tick `Task.detached { await usageStats.refresh() }`；`switchAccount` 删 `localCost30d = nil` 行不替换。 |
| 🔧 `macos/Sources/UsageBar/UsageBarApp.swift` | `@StateObject usageStats`；构造 `UsageService` 时注入；`.task` 串入 `await usageStats.refresh()`。 |
| 🔧 `macos/Sources/UsageBar/PopoverView.swift` | `LocalCostCard` 数据源改 `usageStats.rolling30d`；插 `UsageHeatmapView`。 |
| 🔧 `macos/Sources/UsageBar/LocalCostCard.swift` | 接收 `CostSummary?` 来自 `usageStats.rolling30d`；视觉不变。 |
| 🗑 `macos/Sources/UsageBar/LocalCostScanner.swift` + `macos/Tests/UsageBarTests/LocalCostScannerTests.swift` | 删除。 |
| ✅ 不动 | `JSONLCostParser.swift` `ClaudePricing.swift` `history.json` 及 OAuth/refresh/SetupView/CodeEntry/Settings/Notifications/Strategy/StoredAccount/hero/menubar/pace/trend/chart |
| 🆕 测试 | `UsageEventStoreTests` / `ScanCursorStoreTests` / `ClaudeUsageCollectorTests` / `UsageAggregatorTests` / `UsageStatsServiceTests` / `UsageHeatmapModelTests`（≥20 case 总计；净测试数 ≥144）|
| 🔧 文档 | `docs/superpowers/specs/2026-05-11-local-cost-scan.md`（status→superseded）、`docs/superpowers/specs/README.md`、`docs/versions/README.md`、`CHANGELOG.md`、`docs/versions/v0.2.3-usage-store-redesign.md`（status→in-progress）|

> 注：spec 与 version 文件已在 brainstorming 阶段创建并 commit（commit `44995e6` + G2 修订 `8aa9f16`）。Task 0 只补索引同步 + 旧 spec 标记 superseded。

---

## Task 0: 文档脚手架收尾（P0 — 仅文档）

**Files:**
- Modify: `docs/superpowers/specs/2026-05-11-local-cost-scan.md`（frontmatter）
- Modify: `docs/superpowers/specs/README.md`
- Modify: `docs/versions/README.md`

- [ ] **Step 1: 把旧 spec 标记 superseded**

编辑 `docs/superpowers/specs/2026-05-11-local-cost-scan.md` frontmatter：
- `status: implemented` → `status: superseded`
- `updated: 2026-05-11` → `updated: 2026-05-12`
- 在 `related_research:` 行下方加一行：`superseded_by: 2026-05-12-usage-store-redesign`

- [ ] **Step 2: 同步 specs 索引**

编辑 `docs/superpowers/specs/README.md` 索引表：
- 把 `2026-05-11-local-cost-scan` 那行的 `implemented` 改为 `superseded`
- 追加一行：`| \`2026-05-12-usage-store-redesign\` | 用量统计与存储重设计（按 provider 持久化 raw events + 聚合 + 消费热力图） | accepted | v0.2.3 | [文件](./2026-05-12-usage-store-redesign.md) |`

- [ ] **Step 3: 同步 versions 索引**

编辑 `docs/versions/README.md` "当前路线"表，在 `v0.2.2` 行下追加：
`| [v0.2.3](./v0.2.3-usage-store-redesign.md) | usage-store-redesign | planned | 2026-05-12 | 🔌 用量统计与存储重设计 |`
并把表下方"路线截止于 v0.2.2"那句改为"路线截止于 v0.2.3"。

- [ ] **Step 4: 验证文档 lint**

Run:
```bash
cd /Users/methol/data/code-methol/usage-bar
grep -A1 '^status:' docs/superpowers/specs/2026-05-11-local-cost-scan.md | head -2
grep -c 'usage-store-redesign' docs/superpowers/specs/README.md docs/versions/README.md
head -1 docs/superpowers/specs/2026-05-11-local-cost-scan.md
```
Expected: status 行显示 `status: superseded`；两个 README 各 ≥1 命中；首行是 `---`。

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-05-11-local-cost-scan.md docs/superpowers/specs/README.md docs/versions/README.md
git commit -m "$(cat <<'EOF'
docs: v0.2.3 P0 索引同步 + 旧 spec 标记 superseded [spec:2026-05-12-usage-store-redesign]

local-cost-scan spec status implemented→superseded（superseded_by 指向新 spec）；
specs/README + versions/README 索引同步；新版本路线项 v0.2.3 planned。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: 磁盘 schema 类型 + UsageEventStore（load / merge / atomic write）

**Files:**
- Create: `macos/Sources/UsageBar/UsageStoreTypes.swift`
- Create: `macos/Sources/UsageBar/UsageEventStore.swift`
- Test: `macos/Tests/UsageBarTests/UsageEventStoreTests.swift`

> 本任务只做 `mergeEvents` + 月明细 load/write + 目录/权限；`rebuildAggregates` 与 agg 类型留 Task 2。

- [ ] **Step 1: 写磁盘 schema 类型文件**

Create `macos/Sources/UsageBar/UsageStoreTypes.swift`:

```swift
import Foundation

enum UsageProvider: String, Codable, CaseIterable {
    case claude
}

/// 单次 assistant 调用的事实记录。**故意不含 content/text/contentBlocks**（隐私 schema 守护）。
struct StoredUsageEvent: Codable, Equatable {
    let ts: Date                        // ISO8601 UTC
    let msgId: String
    let reqId: String
    let sessionId: String               // 来自 jsonl 文件名的 UUID；仅供未来分账/调试，不展示给用户
    let model: String                   // 归一化前的原始 model 字符串
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
}

/// data/<provider>/<YYYY>-<MM>.json
struct MonthDetailFile: Codable, Equatable {
    var schemaVersion: Int = 1
    var provider: String
    var month: String                   // "YYYY-MM"，仅供人读；load 时以文件名为准
    var lastUpdated: Date
    var events: [StoredUsageEvent]
}

/// agg 文件桶里某个 model 的累积。
struct TokenSums: Codable, Equatable {
    var calls: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    mutating func add(_ e: StoredUsageEvent) {
        calls += 1
        inputTokens += e.inputTokens
        outputTokens += e.outputTokens
        cacheReadInputTokens += e.cacheReadInputTokens
        cacheCreationInputTokens += e.cacheCreationInputTokens
    }
}

/// data/<provider>/agg-{day,month,year}.json
/// buckets 键：day = "YYYY-MM-DD"（本地时区）/ month = "YYYY-MM"（UTC）/ year = "YYYY"（UTC）
/// 内层键 = ClaudePricing.normalize 后的 model 字符串
struct AggregateFile: Codable, Equatable {
    var schemaVersion: Int = 1
    var provider: String
    var lastUpdated: Date
    var buckets: [String: [String: TokenSums]]
}

/// data/scan-cursor.json
struct ScanCursorFile: Codable, Equatable {
    var schemaVersion: Int = 1
    var files: [String: FileCursor]     // 键 = jsonl 绝对路径

    struct FileCursor: Codable, Equatable {
        var size: Int
        var mtime: Date
        var lineOffset: Int             // 已处理行数（下次跳过前 lineOffset 行）
    }
}
```

- [ ] **Step 2: 写 UsageEventStore 的失败测试（mergeEvents 去重 + 跨月分组 + 0600）**

Create `macos/Tests/UsageBarTests/UsageEventStoreTests.swift`:

```swift
import XCTest
@testable import UsageBar

final class UsageEventStoreTests: XCTestCase {
    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("usagebar-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)!
    }
    private func event(ts: String, msg: String = "msg_mock_1", req: String = "req_mock_1",
                       model: String = "claude-opus-4-7", input: Int = 100, output: Int = 50) -> StoredUsageEvent {
        StoredUsageEvent(ts: iso(ts), msgId: msg, reqId: req, sessionId: "00000000-mock-0000-0000-000000000000",
                         model: model, inputTokens: input, outputTokens: output,
                         cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
    }

    func testMergeEventsDeduplicatesByMsgIdAndReqId() async throws {
        let store = UsageEventStore(dataDirOverride: tmpDir)
        let dup = Array(repeating: event(ts: "2026-05-11T10:00:00.000Z"), count: 5)
        _ = await store.mergeEvents(dup)
        let got = await store.queryEvents(from: iso("2026-05-01T00:00:00.000Z"), to: iso("2026-06-01T00:00:00.000Z"))
        XCTAssertEqual(got.count, 1)
    }

    func testMergeEventsSplitsAcrossUTCMonths() async throws {
        let store = UsageEventStore(dataDirOverride: tmpDir)
        _ = await store.mergeEvents([
            event(ts: "2026-04-30T23:00:00.000Z", msg: "msg_mock_apr", req: "req_mock_apr"),
            event(ts: "2026-05-01T01:00:00.000Z", msg: "msg_mock_may", req: "req_mock_may"),
        ])
        let aprPath = tmpDir.appendingPathComponent("claude/2026-04.json")
        let mayPath = tmpDir.appendingPathComponent("claude/2026-05.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aprPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mayPath.path))
    }

    func testMonthFilePermissionsAre0600() async throws {
        let store = UsageEventStore(dataDirOverride: tmpDir)
        _ = await store.mergeEvents([event(ts: "2026-05-11T10:00:00.000Z")])
        let path = tmpDir.appendingPathComponent("claude/2026-05.json").path
        let perms = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(perms.int16Value, 0o600)
    }

    func testMonthFileCodableRoundTripPreservesEvents() async throws {
        let store = UsageEventStore(dataDirOverride: tmpDir)
        let e1 = event(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a")
        let e2 = event(ts: "2026-05-12T11:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b", model: "claude-haiku-4-5")
        _ = await store.mergeEvents([e1, e2])
        // 二次 merge 一条已存在 + 一条新 → 仍只 3 条
        let e3 = event(ts: "2026-05-13T12:00:00.000Z", msg: "msg_mock_c", req: "req_mock_c")
        _ = await store.mergeEvents([e1, e3])
        let got = await store.queryEvents(from: iso("2026-05-01T00:00:00.000Z"), to: iso("2026-06-01T00:00:00.000Z"))
        XCTAssertEqual(Set(got.map(\.msgId)), ["msg_mock_a", "msg_mock_b", "msg_mock_c"])
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd macos && swift test --filter UsageEventStoreTests 2>&1 | tail -5`
Expected: 编译失败（`UsageEventStore` 未定义）。

- [ ] **Step 4: 实现 UsageEventStore（本任务范围：merge + load/write + 目录/权限）**

Create `macos/Sources/UsageBar/UsageEventStore.swift`:

```swift
import Foundation

actor UsageEventStore {
    private let dataDir: URL
    private let provider: UsageProvider
    private let fm = FileManager.default

    init(dataDirOverride: URL? = nil, provider: UsageProvider = .claude) {
        if let o = dataDirOverride {
            self.dataDir = o
        } else if let cfg = UsageEventStore.defaultConfigDir() {
            self.dataDir = cfg.appendingPathComponent("data", isDirectory: true)
        } else {
            self.dataDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("claude-usage-bar/data", isDirectory: true)
        }
        self.provider = provider
    }

    /// ~/.config/claude-usage-bar/
    static func defaultConfigDir() -> URL? {
        fm.default.homeDirectoryForCurrentUser  // placeholder; replaced below
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
    }

    private var providerDir: URL { dataDir.appendingPathComponent(provider.rawValue, isDirectory: true) }
    private func monthFileURL(_ key: String) -> URL { providerDir.appendingPathComponent("\(key).json") }

    // MARK: month key (UTC)
    private static let utcMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"; return f
    }()
    static func utcMonthKey(_ d: Date) -> String { utcMonthFormatter.string(from: d) }

    // MARK: codec
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func ensureDir(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    }
    private func writeAtomic0600(_ data: Data, to url: URL) {
        ensureDir(url.deletingLastPathComponent())
        do {
            try data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("[claude-usage-bar] store write: \(type(of: error))")
        }
    }

    private func loadMonth(_ key: String) -> MonthDetailFile? {
        guard let data = try? Data(contentsOf: monthFileURL(key)) else { return nil }
        do { return try Self.decoder.decode(MonthDetailFile.self, from: data) }
        catch { NSLog("[claude-usage-bar] store decode month: \(type(of: error))"); return nil }
    }
    private func saveMonth(_ file: MonthDetailFile, key: String) {
        guard let data = try? Self.encoder.encode(file) else { return }
        writeAtomic0600(data, to: monthFileURL(key))
    }

    // MARK: public — merge
    /// 返回 dirtyMonths（decode 失败被当空覆盖的月 key），collector 据此清相关游标。
    /// 注意：本任务实现先返回 []；Task 1 暂不处理"覆盖损坏月"细分（Task 2 收尾时已含 rebuild 不需要）。
    @discardableResult
    func mergeEvents(_ events: [StoredUsageEvent]) -> Set<String> {
        guard !events.isEmpty else { return [] }
        let grouped = Dictionary(grouping: events) { Self.utcMonthKey($0.ts) }
        for (monthKey, newEvents) in grouped {
            var existing = loadMonth(monthKey)?.events ?? []
            var seen = Set(existing.map { "\($0.msgId)|\($0.reqId)" })
            for e in newEvents {
                let k = "\(e.msgId)|\(e.reqId)"
                if seen.contains(k) { continue }
                seen.insert(k); existing.append(e)
            }
            existing.sort { $0.ts < $1.ts }
            saveMonth(MonthDetailFile(provider: provider.rawValue, month: monthKey,
                                      lastUpdated: Date(), events: existing), key: monthKey)
        }
        return []
    }

    // MARK: public — query
    func queryEvents(from: Date, to: Date) -> [StoredUsageEvent] {
        guard fm.fileExists(atPath: providerDir.path) else { return [] }
        let fromKey = Self.utcMonthKey(from), toKey = Self.utcMonthKey(to)
        guard let files = try? fm.contentsOfDirectory(at: providerDir, includingPropertiesForKeys: nil) else { return [] }
        var result: [StoredUsageEvent] = []
        for f in files where f.pathExtension == "json" {
            let name = f.deletingPathExtension().lastPathComponent  // "YYYY-MM" or "agg-day" ...
            // G3 R4：用 !hasPrefix("agg") 明确排除 agg-* 文件（"agg-day" 也是 7 字符，光靠 count 不够稳）
            guard !name.hasPrefix("agg"), name.count == 7, name <= toKey, name >= fromKey else { continue }
            if let mf = loadMonth(name) {
                result.append(contentsOf: mf.events.filter { $0.ts >= from && $0.ts < to })
            }
        }
        return result.sorted { $0.ts < $1.ts }
    }

    // MARK: 给 Task 2 用的内部访问器（先声明，Task 2 填实现）
    func allMonthKeys() -> [String] {
        guard let files = try? fm.contentsOfDirectory(at: providerDir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.count == 7 && $0.contains("-") && !$0.hasPrefix("agg") }
            .sorted()
    }
    func eventsForMonth(_ key: String) -> [StoredUsageEvent] { loadMonth(key)?.events ?? [] }
}
```

> ⚠️ 实现注意：上面 `defaultConfigDir()` 草稿里有一行 `fm.default.homeDirectoryForCurrentUser` 是笔误占位——实现时删掉，只保留 `return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/claude-usage-bar", isDirectory: true)`。`UsageEventStore` 是 actor，`fm` 用 `FileManager.default`（线程安全只读用法）。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd macos && swift test --filter UsageEventStoreTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: 全量构建 + 测试 + 隐私守护**

Run:
```bash
cd macos && swift build -c release 2>&1 | tail -2 && swift test 2>&1 | grep -E 'Executed [0-9]+ test' | tail -1
cd .. && grep -nrI -E '(print|NSLog|os_log)\s*[\(,].*(message\.content|sessionId|fileURL|\.path\b)' macos/Sources/UsageBar/ || echo "GUARD-OK"
```
Expected: `Build complete!`；测试全绿；`GUARD-OK`。

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/UsageBar/UsageStoreTypes.swift macos/Sources/UsageBar/UsageEventStore.swift macos/Tests/UsageBarTests/UsageEventStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: 用量存储层 schema 类型 + UsageEventStore 月明细 merge/query [spec:2026-05-12-usage-store-redesign]

新增 UsageStoreTypes（StoredUsageEvent/MonthDetailFile/TokenSums/AggregateFile/
ScanCursorFile/UsageProvider，schema 不含对话内容）；UsageEventStore actor 实现
按 ts UTC 月分组 + (msgId,reqId) 去重 union + atomic write 0600 + 跨月查询。
4 个单测覆盖去重 / 跨月分组 / 0600 权限 / round-trip。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: 聚合（UsageAggregator 折算 + UsageEventStore.rebuildAggregates）

**Files:**
- Create: `macos/Sources/UsageBar/UsageAggregator.swift`
- Modify: `macos/Sources/UsageBar/UsageEventStore.swift`（加 rebuildAggregates / readXxxAggregates）
- Test: `macos/Tests/UsageBarTests/UsageAggregatorTests.swift`
- Test: `macos/Tests/UsageBarTests/UsageEventStoreTests.swift`（加 rebuild 相关 case）

- [ ] **Step 1: 写 UsageAggregator 的失败测试**

Create `macos/Tests/UsageBarTests/UsageAggregatorTests.swift`:

```swift
import XCTest
@testable import UsageBar

final class UsageAggregatorTests: XCTestCase {
    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)!
    }
    private func ev(_ ts: String, model: String = "claude-opus-4-7", input: Int = 1, output: Int = 1,
                    cr: Int = 0, cc: Int = 0, msg: String = UUID().uuidString) -> StoredUsageEvent {
        StoredUsageEvent(ts: iso(ts), msgId: "msg_mock_\(msg)", reqId: "req_mock_\(msg)",
                         sessionId: "00000000-mock-0000-0000-000000000000", model: model,
                         inputTokens: input, outputTokens: output, cacheReadInputTokens: cr, cacheCreationInputTokens: cc)
    }

    func testFoldByDayKeysUseLocalTimeZone() {
        // G3 R2：两个 ts 取相邻 3 小时，确保在所有现实时区（UTC-12~UTC+14）都落同一本地日。
        let events = [ev("2026-05-11T10:00:00.000Z", msg: "a"), ev("2026-05-11T13:00:00.000Z", msg: "b")]
        let byDay = UsageAggregator.foldByDay(events: events)
        XCTAssertEqual(byDay.keys.count, 1)
        XCTAssertEqual(byDay.values.first?["claude-opus-4-7"]?.calls, 2)
    }

    func testFoldByMonthAndYearUseUTC() {
        let events = [ev("2026-04-30T23:30:00.000Z", msg: "x"), ev("2026-05-01T00:30:00.000Z", msg: "y")]
        XCTAssertEqual(Set(UsageAggregator.foldByMonth(events: events).keys), ["2026-04", "2026-05"])
        XCTAssertEqual(Set(UsageAggregator.foldByYear(events: events).keys), ["2026"])
    }

    func testUsdForBucketMatchesClaudePricingCost() {
        // 1M 各类 token 的 opus-4-7：input 15 + output 75 + cacheRead 1.5 + cacheWrite 18.75 = 110.25
        var sums = TokenSums()
        sums.calls = 1; sums.inputTokens = 1_000_000; sums.outputTokens = 1_000_000
        sums.cacheReadInputTokens = 1_000_000; sums.cacheCreationInputTokens = 1_000_000
        let bucket: [String: TokenSums] = ["claude-opus-4-7": sums]
        XCTAssertEqual(UsageAggregator.usdForBucket(bucket).usd, 110.25, accuracy: 1e-6)
        XCTAssertEqual(UsageAggregator.usdForBucket(bucket).unknownModelCalls, 0)
    }

    func testUnknownModelContributesZeroUSDAndCountsCalls() {
        var sums = TokenSums(); sums.calls = 3; sums.inputTokens = 1_000_000
        let bucket: [String: TokenSums] = ["fake-model-99": sums]
        let r = UsageAggregator.usdForBucket(bucket)
        XCTAssertEqual(r.usd, 0, accuracy: 1e-9)
        XCTAssertEqual(r.unknownModelCalls, 3)
    }

    func testRolling30dSummaryWindowBoundary() {
        // G3 B1：用明确在窗内 / 窗外的日期（不卡边界）。now - 30d ≈ 2026-04-12；
        // 04-20 明确在窗内，04-01 明确在窗外。dayKey 按本地 00:00 转 Date，所以不取恰好 30 天那天。
        let now = iso("2026-05-12T12:00:00.000Z")
        let dayAgg: [String: [String: TokenSums]] = [
            "2026-04-20": ["claude-opus-4-7": { var s = TokenSums(); s.calls = 1; s.inputTokens = 1_000_000; return s }()],
            "2026-04-01": ["claude-opus-4-7": { var s = TokenSums(); s.calls = 1; s.inputTokens = 1_000_000; return s }()],
        ]
        let summary = UsageAggregator.rolling30dSummary(dayAggregates: dayAgg, now: now)
        XCTAssertEqual(summary.windowDays, 30)
        XCTAssertGreaterThan(summary.totalUSD, 0)
        XCTAssertEqual(summary.perModel.reduce(0) { $0 + $1.calls }, 1)   // 只有 04-20 计入
    }
}
```

> 注：`CostSummary` / `ModelCost` 是 v0.1.2 既有类型（在 `LocalCostScanner.swift` 里定义）。本任务把它们**移动**到 `UsageStoreTypes.swift`（因为 `LocalCostScanner.swift` Task 7 要删除）。移动时保持字段不变：`CostSummary { generatedAt, windowDays, totalUSD, perModel:[ModelCost], unknownModelCount, parseErrorCount, scannedFileCount }`、`ModelCost { model, normalizedModel, calls, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens, usd, isUnknownPricing }`。

- [ ] **Step 2: 把 CostSummary/ModelCost 移到 UsageStoreTypes.swift**

从 `macos/Sources/UsageBar/LocalCostScanner.swift` 顶部剪切 `struct ModelCost` 和 `struct CostSummary` 两个定义，粘贴到 `UsageStoreTypes.swift` 末尾（保持完全一致）。`LocalCostScanner.swift` 此时编译会暂时引用同名类型——没问题，类型只是换了文件。运行 `cd macos && swift build` 确认仍编译。

- [ ] **Step 3: 实现 UsageAggregator**

Create `macos/Sources/UsageBar/UsageAggregator.swift`:

```swift
import Foundation

enum UsageAggregator {
    // MARK: day key — 本地时区
    private static let localDayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func localDayKey(_ d: Date) -> String { localDayFormatter.string(from: d) }

    // MARK: month/year key — UTC（与 UsageEventStore 一致）
    private static func utcKey(_ d: Date, format: String) -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format; return f.string(from: d)
    }
    static func utcMonthKey(_ d: Date) -> String { utcKey(d, format: "yyyy-MM") }
    static func utcYearKey(_ d: Date) -> String { utcKey(d, format: "yyyy") }

    // MARK: fold
    private static func fold(_ events: [StoredUsageEvent], key: (Date) -> String) -> [String: [String: TokenSums]] {
        var out: [String: [String: TokenSums]] = [:]
        for e in events {
            let bk = key(e.ts)
            let mk = ClaudePricing.normalize(e.model)
            var bucket = out[bk] ?? [:]
            var sums = bucket[mk] ?? TokenSums()
            sums.add(e)
            bucket[mk] = sums
            out[bk] = bucket
        }
        return out
    }
    static func foldByDay(events: [StoredUsageEvent]) -> [String: [String: TokenSums]] { fold(events, key: localDayKey) }
    static func foldByMonth(events: [StoredUsageEvent]) -> [String: [String: TokenSums]] { fold(events, key: utcMonthKey) }
    static func foldByYear(events: [StoredUsageEvent]) -> [String: [String: TokenSums]] { fold(events, key: utcYearKey) }

    // MARK: USD
    struct BucketCost { let usd: Double; let unknownModelCalls: Int; let perModel: [ModelCost] }
    static func usdForBucket(_ bucket: [String: TokenSums]) -> BucketCost {
        var total = 0.0, unknown = 0
        var per: [ModelCost] = []
        for (normalizedModel, s) in bucket {
            let pricing = ClaudePricing.lookup(model: normalizedModel)
            if pricing == nil { unknown += s.calls }
            let usd = ClaudePricing.cost(for: pricing, input: s.inputTokens, output: s.outputTokens,
                                         cacheRead: s.cacheReadInputTokens, cacheWrite: s.cacheCreationInputTokens)
            total += usd
            per.append(ModelCost(model: normalizedModel, normalizedModel: normalizedModel, calls: s.calls,
                                 inputTokens: s.inputTokens, outputTokens: s.outputTokens,
                                 cacheReadTokens: s.cacheReadInputTokens, cacheCreationTokens: s.cacheCreationInputTokens,
                                 usd: usd, isUnknownPricing: pricing == nil))
        }
        per.sort { $0.usd > $1.usd }
        return BucketCost(usd: total, unknownModelCalls: unknown, perModel: per)
    }

    // MARK: 派生展示结构
    static func dailySpend(from dayAggregates: [String: [String: TokenSums]]) -> [DaySpend] {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return dayAggregates.compactMap { (dayKey, bucket) -> DaySpend? in
            guard let date = f.date(from: dayKey) else { return nil }
            let c = usdForBucket(bucket)
            return DaySpend(dayKey: dayKey, date: date, usd: c.usd, calls: bucket.values.reduce(0) { $0 + $1.calls })
        }.sorted { $0.dayKey < $1.dayKey }
    }
    static func monthlySpend(from monthAggregates: [String: [String: TokenSums]]) -> [MonthSpend] {
        monthAggregates.map { (monthKey, bucket) in
            let c = usdForBucket(bucket)
            return MonthSpend(monthKey: monthKey, usd: c.usd, calls: bucket.values.reduce(0) { $0 + $1.calls })
        }.sorted { $0.monthKey < $1.monthKey }
    }

    /// 兼容 v0.1.2 LocalCostCard 的 CostSummary 形态。scannedFileCount/parseErrorCount 由调用方填。
    static func rolling30dSummary(dayAggregates: [String: [String: TokenSums]], now: Date,
                                  scannedFileCount: Int = 1, parseErrorCount: Int = 0) -> CostSummary {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        var merged: [String: TokenSums] = [:]
        for (dayKey, bucket) in dayAggregates {
            guard let date = f.date(from: dayKey), date >= cutoff else { continue }
            for (mk, s) in bucket {
                var acc = merged[mk] ?? TokenSums()
                acc.calls += s.calls; acc.inputTokens += s.inputTokens; acc.outputTokens += s.outputTokens
                acc.cacheReadInputTokens += s.cacheReadInputTokens; acc.cacheCreationInputTokens += s.cacheCreationInputTokens
                merged[mk] = acc
            }
        }
        let c = usdForBucket(merged)
        return CostSummary(generatedAt: now, windowDays: 30, totalUSD: c.usd, perModel: c.perModel,
                           unknownModelCount: c.unknownModelCalls, parseErrorCount: parseErrorCount,
                           scannedFileCount: scannedFileCount)
    }
}

struct DaySpend: Equatable { let dayKey: String; let date: Date; let usd: Double; let calls: Int }
struct MonthSpend: Equatable { let monthKey: String; let usd: Double; let calls: Int }
```

> 注（G3 B1）：`rolling30dSummary` 的窗口判定是 `localDay(00:00, 本地时区) >= now - 30*86400`。这意味着"恰好 30 天前那一天"会因为 `00:00 < now 的时刻` 而被排除——这不是 bug，是按整天聚合的自然结果。所以测试 fixture 必须用**明确在窗内 / 明确在窗外**的日期（如上 `2026-04-20` / `2026-04-01`），不要卡 30 天整边界。

- [ ] **Step 4: 运行 UsageAggregator 测试确认通过**

Run: `cd macos && swift test --filter UsageAggregatorTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 5 tests, with 0 failures`（若边界 case 因时区不稳，按 Step 3 注释调整日期后重跑）

- [ ] **Step 5: 在 UsageEventStore 加 rebuildAggregates / readXxxAggregates 的失败测试**

往 `UsageEventStoreTests.swift` 追加：

```swift
func testRebuildAggregatesFromDetailMatchesReadback() async throws {
    let store = UsageEventStore(dataDirOverride: tmpDir)
    _ = await store.mergeEvents([
        event(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        event(ts: "2026-05-12T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b", model: "claude-haiku-4-5"),
    ])
    await store.rebuildAllAggregates()
    let day = await store.readDayAggregates()
    XCTAssertGreaterThanOrEqual(day.keys.count, 1)   // 至少有数据
    let month = await store.readMonthAggregates()
    XCTAssertEqual(month["2026-05"]?.values.reduce(0) { $0 + $1.calls }, 2)
    let year = await store.readYearAggregates()
    XCTAssertEqual(year["2026"]?.values.reduce(0) { $0 + $1.calls }, 2)
    // agg 文件落盘 0600
    let aggPath = tmpDir.appendingPathComponent("claude/agg-day.json").path
    let perms = try FileManager.default.attributesOfItem(atPath: aggPath)[.posixPermissions] as! NSNumber
    XCTAssertEqual(perms.int16Value, 0o600)
}

func testRebuildAggregatesForDayKeysOnlyTouchesThoseBuckets() async throws {
    let store = UsageEventStore(dataDirOverride: tmpDir)
    _ = await store.mergeEvents([event(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a")])
    await store.rebuildAllAggregates()
    // 新增 5-12 的事件，只 rebuild 5-12
    _ = await store.mergeEvents([event(ts: "2026-05-12T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b")])
    await store.rebuildAggregates(forDayKeys: [UsageAggregator.localDayKey(iso("2026-05-12T10:00:00.000Z"))])
    let day = await store.readDayAggregates()
    // 两天的桶都在（5-11 来自上次 rebuild，5-12 来自这次）
    let totalCalls = day.values.flatMap { $0.values }.reduce(0) { $0 + $1.calls }
    XCTAssertEqual(totalCalls, 2)
}

func testCorruptedMonthFileTreatedAsEmpty() async throws {
    let store = UsageEventStore(dataDirOverride: tmpDir)
    let dir = tmpDir.appendingPathComponent("claude", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "{ not valid json".data(using: .utf8)!.write(to: dir.appendingPathComponent("2026-05.json"))
    // merge 一条新事件 → 损坏文件被当空覆盖
    _ = await store.mergeEvents([event(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a")])
    let got = await store.queryEvents(from: iso("2026-05-01T00:00:00.000Z"), to: iso("2026-06-01T00:00:00.000Z"))
    XCTAssertEqual(got.count, 1)
}
```

- [ ] **Step 6: 实现 rebuildAggregates / readXxxAggregates**

在 `UsageEventStore.swift` 末尾（class 内）追加：

```swift
    // MARK: aggregates
    private func aggFileURL(_ kind: String) -> URL { providerDir.appendingPathComponent("agg-\(kind).json") }

    private func loadAgg(_ kind: String) -> AggregateFile? {
        guard let data = try? Data(contentsOf: aggFileURL(kind)) else { return nil }
        do {
            let f = try Self.decoder.decode(AggregateFile.self, from: data)
            return f.schemaVersion == 1 ? f : nil
        } catch { NSLog("[claude-usage-bar] store decode agg: \(type(of: error))"); return nil }
    }
    private func saveAgg(_ kind: String, buckets: [String: [String: TokenSums]]) {
        let f = AggregateFile(provider: provider.rawValue, lastUpdated: Date(), buckets: buckets)
        guard let data = try? Self.encoder.encode(f) else { return }
        writeAtomic0600(data, to: aggFileURL(kind))
    }

    func readDayAggregates() -> [String: [String: TokenSums]] { resolvedAgg("day") }
    func readMonthAggregates() -> [String: [String: TokenSums]] { resolvedAgg("month") }
    func readYearAggregates() -> [String: [String: TokenSums]] { resolvedAgg("year") }
    private func resolvedAgg(_ kind: String) -> [String: [String: TokenSums]] {
        if let f = loadAgg(kind) { return f.buckets }
        rebuildAllAggregates()                              // 损坏/缺失 → 从明细重建
        return loadAgg(kind)?.buckets ?? [:]
    }

    /// 全量从明细重建三个 agg 文件。
    func rebuildAllAggregates() {
        let allEvents = allMonthKeys().flatMap { eventsForMonth($0) }
        saveAgg("day", buckets: UsageAggregator.foldByDay(events: allEvents))
        saveAgg("month", buckets: UsageAggregator.foldByMonth(events: allEvents))
        saveAgg("year", buckets: UsageAggregator.foldByYear(events: allEvents))
    }

    /// 增量重建：只读**受影响的月明细文件**（G3 B2：不全读所有月），重算受影响的 day/month/year 桶覆盖回去。
    func rebuildAggregates(forDayKeys dayKeys: Set<String>) {
        guard !dayKeys.isEmpty else { return }
        // 1. 由 dayKeys 推候选 UTC 月：一个本地日 [00:00 local, +24h) 的 UTC ts 范围最多跨 2 个 UTC 月。
        let dayFmt = DateFormatter(); dayFmt.calendar = Calendar(identifier: .gregorian)
        dayFmt.timeZone = TimeZone.current; dayFmt.locale = Locale(identifier: "en_US_POSIX"); dayFmt.dateFormat = "yyyy-MM-dd"
        var candidateMonths = Set<String>()
        for dk in dayKeys {
            guard let start = dayFmt.date(from: dk) else { continue }
            let end = start.addingTimeInterval(24 * 3600 - 1)
            candidateMonths.insert(Self.utcMonthKey(start))
            candidateMonths.insert(Self.utcMonthKey(end))
        }
        // 2. 重算 year 桶需要那一年的全部月 → 把候选年的所有已存在月文件纳入读取集。
        let candidateYears = Set(candidateMonths.map { String($0.prefix(4)) })
        let monthsToLoad = Set(allMonthKeys().filter { mk in
            candidateMonths.contains(mk) || candidateYears.contains(String(mk.prefix(4)))
        })
        let loadedEvents = monthsToLoad.flatMap { eventsForMonth($0) }   // 只读这些月，不是全部
        let touchedEvents = loadedEvents.filter { dayKeys.contains(UsageAggregator.localDayKey($0.ts)) }
        let touchedMonthKeys = Set(touchedEvents.map { UsageAggregator.utcMonthKey($0.ts) })
        let touchedYearKeys = Set(touchedEvents.map { UsageAggregator.utcYearKey($0.ts) })

        var day = loadAgg("day")?.buckets ?? [:]
        var month = loadAgg("month")?.buckets ?? [:]
        var year = loadAgg("year")?.buckets ?? [:]
        for k in dayKeys { day[k] = nil }
        for k in touchedMonthKeys { month[k] = nil }
        for k in touchedYearKeys { year[k] = nil }
        let monthEvents = loadedEvents.filter { touchedMonthKeys.contains(UsageAggregator.utcMonthKey($0.ts)) }
        let yearEvents = loadedEvents.filter { touchedYearKeys.contains(UsageAggregator.utcYearKey($0.ts)) }
        for (k, v) in UsageAggregator.foldByDay(events: touchedEvents) { day[k] = v }
        for (k, v) in UsageAggregator.foldByMonth(events: monthEvents) { month[k] = v }
        for (k, v) in UsageAggregator.foldByYear(events: yearEvents) { year[k] = v }
        saveAgg("day", buckets: day); saveAgg("month", buckets: month); saveAgg("year", buckets: year)
    }
```

> 注：`mergeEvents` 现在要返回 dirtyMonths（被覆盖的损坏月）以便 collector 清游标。把 `mergeEvents` 改成：load 月文件时若 `loadMonth` 返回 nil **且文件存在**（即 decode 失败而非首次创建），把该 monthKey 加进返回的 `dirty` 集合。实现：

```swift
@discardableResult
func mergeEvents(_ events: [StoredUsageEvent]) -> Set<String> {
    guard !events.isEmpty else { return [] }
    var dirty: Set<String> = []
    let grouped = Dictionary(grouping: events) { Self.utcMonthKey($0.ts) }
    for (monthKey, newEvents) in grouped {
        let url = monthFileURL(monthKey)
        let parsed = loadMonth(monthKey)
        if parsed == nil && fm.fileExists(atPath: url.path) { dirty.insert(monthKey) }   // 损坏月被当空覆盖
        var existing = parsed?.events ?? []
        var seen = Set(existing.map { "\($0.msgId)|\($0.reqId)" })
        for e in newEvents {
            let k = "\(e.msgId)|\(e.reqId)"
            if seen.contains(k) { continue }
            seen.insert(k); existing.append(e)
        }
        existing.sort { $0.ts < $1.ts }
        saveMonth(MonthDetailFile(provider: provider.rawValue, month: monthKey,
                                  lastUpdated: Date(), events: existing), key: monthKey)
    }
    return dirty
}
```

- [ ] **Step 7: 运行测试确认通过**

Run: `cd macos && swift test --filter UsageEventStoreTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 8: 全量构建 + 测试 + 隐私守护**

Run: `cd macos && swift build -c release 2>&1 | tail -2 && swift test 2>&1 | grep -E 'Executed [0-9]+ test' | tail -1`
Expected: `Build complete!`；测试全绿。再跑两条隐私 grep（同 Task 1 Step 6），均无输出。

- [ ] **Step 9: Commit**

```bash
git add macos/Sources/UsageBar/UsageAggregator.swift macos/Sources/UsageBar/UsageEventStore.swift macos/Sources/UsageBar/UsageStoreTypes.swift macos/Sources/UsageBar/LocalCostScanner.swift macos/Tests/UsageBarTests/
git commit -m "$(cat <<'EOF'
feat: UsageAggregator 折算 + UsageEventStore 聚合重建 [spec:2026-05-12-usage-store-redesign]

UsageAggregator 纯函数 foldByDay(本地时区)/Month/Year(UTC) + usdForBucket(套
ClaudePricing) + rolling30dSummary(兼容 v0.1.2 CostSummary) + dailySpend/
monthlySpend；UsageEventStore 加 rebuildAllAggregates/rebuildAggregates(forDayKeys:)
/readXxxAggregates（agg 损坏自动从明细重建）；mergeEvents 返回 dirtyMonths。
CostSummary/ModelCost 从 LocalCostScanner 移到 UsageStoreTypes。+5+3 单测。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ScanCursorStore

**Files:**
- Create: `macos/Sources/UsageBar/ScanCursorStore.swift`
- Test: `macos/Tests/UsageBarTests/ScanCursorStoreTests.swift`

- [ ] **Step 1: 写失败测试**

Create `macos/Tests/UsageBarTests/ScanCursorStoreTests.swift`:

```swift
import XCTest
@testable import UsageBar

final class ScanCursorStoreTests: XCTestCase {
    private var tmpDir: URL!
    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cursor-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpDir) }

    private func makeStore() -> ScanCursorStore { ScanCursorStore(dataDirOverride: tmpDir) }
    private let fakeURL = URL(fileURLWithPath: "/tmp/projects/foo/00000000-mock-0000-0000-000000000000.jsonl")

    func testFirstSeenFileReturnsZero() async {
        let s = makeStore()
        XCTAssertEqual(await s.nextReadOffset(for: fakeURL, currentSize: 100, currentMTime: Date()), 0)
    }
    func testUnchangedSizeAndMTimeReturnsNil() async {
        let s = makeStore()
        let m = Date(timeIntervalSince1970: 1_000_000)
        await s.updateCursor(for: fakeURL, size: 100, mtime: m, lineOffset: 5)
        XCTAssertNil(await s.nextReadOffset(for: fakeURL, currentSize: 100, currentMTime: m))
    }
    func testGrownSizeReturnsLastLineOffset() async {
        let s = makeStore()
        let m1 = Date(timeIntervalSince1970: 1_000_000), m2 = Date(timeIntervalSince1970: 1_000_500)
        await s.updateCursor(for: fakeURL, size: 100, mtime: m1, lineOffset: 5)
        XCTAssertEqual(await s.nextReadOffset(for: fakeURL, currentSize: 250, currentMTime: m2), 5)
    }
    func testShrunkSizeReturnsZero() async {
        let s = makeStore()
        let m1 = Date(timeIntervalSince1970: 1_000_000), m2 = Date(timeIntervalSince1970: 1_000_500)
        await s.updateCursor(for: fakeURL, size: 100, mtime: m1, lineOffset: 5)
        XCTAssertEqual(await s.nextReadOffset(for: fakeURL, currentSize: 30, currentMTime: m2), 0)
    }
    func testCorruptedCursorFileDegradesToFullScan() async throws {
        try "{ not json".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("scan-cursor.json"))
        let s = makeStore()
        XCTAssertEqual(await s.nextReadOffset(for: fakeURL, currentSize: 100, currentMTime: Date()), 0)
    }
    func testPersistAcrossInstances() async {
        let m = Date(timeIntervalSince1970: 1_000_000)
        await makeStore().updateCursor(for: fakeURL, size: 100, mtime: m, lineOffset: 7)
        XCTAssertNil(await makeStore().nextReadOffset(for: fakeURL, currentSize: 100, currentMTime: m))
    }
    func testCursorFilePermissionsAre0600() async throws {
        await makeStore().updateCursor(for: fakeURL, size: 100, mtime: Date(), lineOffset: 1)
        let perms = try FileManager.default.attributesOfItem(atPath: tmpDir.appendingPathComponent("scan-cursor.json").path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(perms.int16Value, 0o600)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd macos && swift test --filter ScanCursorStoreTests 2>&1 | tail -3`
Expected: 编译失败（`ScanCursorStore` 未定义）。

- [ ] **Step 3: 实现 ScanCursorStore**

Create `macos/Sources/UsageBar/ScanCursorStore.swift`:

```swift
import Foundation

actor ScanCursorStore {
    private let cursorURL: URL
    private let fm = FileManager.default
    private var cache: ScanCursorFile?

    init(dataDirOverride: URL? = nil) {
        let dir: URL
        if let o = dataDirOverride { dir = o }
        else if let cfg = UsageEventStore.defaultConfigDir() { dir = cfg.appendingPathComponent("data", isDirectory: true) }
        else { dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claude-usage-bar/data", isDirectory: true) }
        self.cursorURL = dir.appendingPathComponent("scan-cursor.json")
    }

    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    private func loaded() -> ScanCursorFile {
        if let c = cache { return c }
        if let data = try? Data(contentsOf: cursorURL),
           let f = try? Self.decoder.decode(ScanCursorFile.self, from: data), f.schemaVersion == 1 {
            cache = f; return f
        }
        let fresh = ScanCursorFile(files: [:]); cache = fresh; return fresh
    }
    private func persist(_ f: ScanCursorFile) {
        cache = f
        do {
            try fm.createDirectory(at: cursorURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try Self.encoder.encode(f)
            try data.write(to: cursorURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cursorURL.path)
        } catch { NSLog("[claude-usage-bar] cursor write: \(type(of: error))") }
    }

    /// nil = 文件无变化整跳过；0 = 需全读；N = 从第 N 行续读。
    func nextReadOffset(for fileURL: URL, currentSize: Int, currentMTime: Date) -> Int? {
        guard let c = loaded().files[fileURL.path] else { return 0 }   // 首见
        if c.size == currentSize && abs(c.mtime.timeIntervalSince(currentMTime)) < 1 { return nil }   // 没变（mtime 容 1s 抖动）
        if currentSize < c.size { return 0 }                            // 变小 → 全读
        if currentMTime < c.mtime.addingTimeInterval(-1) { return 0 }   // mtime 跳到更早 → 全读
        return c.lineOffset                                             // 变大 → 续读
    }

    func updateCursor(for fileURL: URL, size: Int, mtime: Date, lineOffset: Int) {
        var f = loaded()
        f.files[fileURL.path] = ScanCursorFile.FileCursor(size: size, mtime: mtime, lineOffset: lineOffset)
        persist(f)
    }
    func clearCursor(for fileURL: URL) {
        var f = loaded(); f.files[fileURL.path] = nil; persist(f)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd macos && swift test --filter ScanCursorStoreTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 7 tests, with 0 failures`

- [ ] **Step 5: 全量构建 + 测试 + 隐私守护**

Run: 同 Task 1 Step 6。Expected: 全绿；`GUARD-OK`。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/UsageBar/ScanCursorStore.swift macos/Tests/UsageBarTests/ScanCursorStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: ScanCursorStore per-file 增量游标 [spec:2026-05-12-usage-store-redesign]

actor 维护 scan-cursor.json（path→{size,mtime,lineOffset}）；nextReadOffset
返回 nil(无变化跳过)/0(全读:首见/变小/mtime回退)/N(续读)；损坏文件丢弃退化全扫；
0600。7 个单测覆盖首见 / 无变化 / 变大续读 / 变小重读 / 损坏退化 / 持久化 / 权限。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: ClaudeUsageCollector

**Files:**
- Create: `macos/Sources/UsageBar/ClaudeUsageCollector.swift`
- Test: `macos/Tests/UsageBarTests/ClaudeUsageCollectorTests.swift`

> 复用 `JSONLCostParser.parseLine`（v0.1.2，返回 `JSONLUsageEvent?`：含 `messageId/requestId/model/timestamp/inputTokens/outputTokens/cacheCreationInputTokens/cacheReadInputTokens`）。`scanRoots()` 沿用 v0.1.2 `LocalCostScanner.scanRoots()` 的逻辑——把那两个 static 方法（`scanRoots()` 与可注入 overload `scanRoots(env:home:fileExists:)`）**复制**进 `ClaudeUsageCollector`（因为 `LocalCostScanner.swift` Task 7 要删）。

- [ ] **Step 1: 写失败测试**

Create `macos/Tests/UsageBarTests/ClaudeUsageCollectorTests.swift`:

```swift
import XCTest
@testable import UsageBar

final class ClaudeUsageCollectorTests: XCTestCase {
    private var tmpRoot: URL!     // 模拟 ~/.claude/projects
    private var tmpData: URL!     // 模拟 ~/.config/claude-usage-bar/data
    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("collector-test-\(UUID().uuidString)", isDirectory: true)
        tmpRoot = base.appendingPathComponent("projects", isDirectory: true)
        tmpData = base.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpData, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpRoot.deletingLastPathComponent()) }

    /// 写一行合法 assistant JSONL（手写 schema，不含真实 token）。
    private func assistantLine(ts: String, msg: String, req: String, model: String = "claude-opus-4-7", input: Int = 100, output: Int = 50) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(msg)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }
    private func writeSession(_ dir: String, _ uuid: String, lines: [String], trailingNewline: Bool = true) throws -> URL {
        let projDir = tmpRoot.appendingPathComponent(dir, isDirectory: true)
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let f = projDir.appendingPathComponent("\(uuid).jsonl")
        try (lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).data(using: .utf8)!.write(to: f)
        return f
    }
    private func makeCollector() -> ClaudeUsageCollector {
        ClaudeUsageCollector(store: UsageEventStore(dataDirOverride: tmpData),
                             cursor: ScanCursorStore(dataDirOverride: tmpData),
                             scanRootsOverride: [tmpRoot])
    }

    func testFirstScanBackfillsAllHistoryAcrossMonths() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-04-15T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
            assistantLine(ts: "2026-05-15T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b"),
        ])
        let r = await makeCollector().collect()
        XCTAssertEqual(r.newEventCount, 2)
        XCTAssertEqual(r.scannedFileCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpData.appendingPathComponent("claude/2026-04.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpData.appendingPathComponent("claude/2026-05.json").path))
    }

    func testIncrementalSecondScanOnlyCountsNewLines() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData)
        let cursor = ScanCursorStore(dataDirOverride: tmpData)
        let f = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let c1 = ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot])
        XCTAssertEqual(await c1.collect().newEventCount, 1)
        // 追加一行
        var content = try String(contentsOf: f, encoding: .utf8)
        content += assistantLine(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b") + "\n"
        try content.data(using: .utf8)!.write(to: f)
        let c2 = ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot])
        XCTAssertEqual(await c2.collect().newEventCount, 1)   // 只读到新增那行
    }

    func testNoNewEventsReturnsZeroAndNoWrite() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        _ = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: tmpData.appendingPathComponent("claude/2026-05.json").path)[.modificationDate] as! Date
        // 文件没变 → 第二次 collect 不应重写月文件
        let r = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r.newEventCount, 0)
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: tmpData.appendingPathComponent("claude/2026-05.json").path)[.modificationDate] as! Date
        XCTAssertEqual(mtimeBefore, mtimeAfter)
    }

    func testPartialLastLineNotConsumed() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        let f = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
            #"{"type":"assistant","requestId":"req_mock_b","timestamp":"2026-05-11T10:"#,   // 半行，无 trailing \n
        ], trailingNewline: false)
        let r1 = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r1.newEventCount, 1)   // 只收第一行
        // CLI 补完半行
        try (assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a") + "\n"
            + assistantLine(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b") + "\n").data(using: .utf8)!.write(to: f)
        let r2 = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r2.newEventCount, 1)   // 这次收到补完的第二行
    }

    func testParseErrorDoesNotAbortScan() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            "{ garbage",
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let r = await makeCollector().collect()
        XCTAssertEqual(r.newEventCount, 1)
        XCTAssertGreaterThanOrEqual(r.parseErrorCount, 1)
    }

    func testDeduplicatesAcrossRepeatedCollect() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        // 同一 msg/req 重复 4 行（模拟流式块）
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: Array(repeating:
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"), count: 4))
        _ = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        let got = await store.queryEvents(from: ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!,
                                          to: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!)
        XCTAssertEqual(got.count, 1)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd macos && swift test --filter ClaudeUsageCollectorTests 2>&1 | tail -3`
Expected: 编译失败（`ClaudeUsageCollector` 未定义）。

- [ ] **Step 3: 实现 ClaudeUsageCollector**

Create `macos/Sources/UsageBar/ClaudeUsageCollector.swift`:

```swift
import Foundation

struct CollectResult {
    let newEventCount: Int
    let scannedFileCount: Int
    let parseErrorCount: Int
    let touchedDayKeys: Set<String>
}

actor ClaudeUsageCollector {
    private let store: UsageEventStore
    private let cursor: ScanCursorStore
    private let scanRootsOverride: [URL]?
    private let fm = FileManager.default
    private var inFlight = false
    private var lastResult = CollectResult(newEventCount: 0, scannedFileCount: 0, parseErrorCount: 0, touchedDayKeys: [])

    init(store: UsageEventStore, cursor: ScanCursorStore, scanRootsOverride: [URL]? = nil) {
        self.store = store; self.cursor = cursor; self.scanRootsOverride = scanRootsOverride
    }

    func collect() async -> CollectResult {
        if inFlight { return lastResult }
        inFlight = true
        defer { inFlight = false }

        let roots = scanRootsOverride ?? Self.scanRoots()
        var collected: [StoredUsageEvent] = []
        var scanned = 0, parseErrors = 0

        for root in roots {
            guard let projectDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for projectDir in projectDirs {
                let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let jsonls: [URL]
                if isDir { jsonls = ((try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "jsonl" } }
                else { jsonls = projectDir.pathExtension == "jsonl" ? [projectDir] : [] }
                for file in jsonls {
                    scanned += 1
                    let attrs = (try? fm.attributesOfItem(atPath: file.path)) ?? [:]
                    let size = (attrs[.size] as? Int) ?? 0
                    let mtime = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
                    guard let offset = await cursor.nextReadOffset(for: file, currentSize: size, currentMTime: mtime) else { continue }
                    guard let raw = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    let endsWithNL = raw.hasSuffix("\n")
                    let allLines = raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
                    // 部分末行：raw 不以 \n 结尾 → 剔出最后一个元素，不解析、不计入 offset
                    let usableCount = endsWithNL ? allLines.count : max(allLines.count - 1, offset)
                    let sessionId = file.deletingPathExtension().lastPathComponent
                    if offset < usableCount {
                        for i in offset..<usableCount {
                            do {
                                guard let ev = try JSONLCostParser.parseLine(allLines[i]) else { continue }
                                collected.append(StoredUsageEvent(
                                    ts: ev.timestamp, msgId: ev.messageId, reqId: ev.requestId, sessionId: sessionId,
                                    model: ev.model, inputTokens: ev.inputTokens, outputTokens: ev.outputTokens,
                                    cacheReadInputTokens: ev.cacheReadInputTokens, cacheCreationInputTokens: ev.cacheCreationInputTokens))
                            } catch {
                                parseErrors += 1
                                NSLog("[claude-usage-bar] usage collect: \(type(of: error))")   // 不 log 行/文件名/路径
                            }
                        }
                    }
                    await cursor.updateCursor(for: file, size: size, mtime: mtime, lineOffset: usableCount)
                }
            }
        }

        guard !collected.isEmpty else {
            lastResult = CollectResult(newEventCount: 0, scannedFileCount: scanned, parseErrorCount: parseErrors, touchedDayKeys: [])
            return lastResult
        }
        let dirty = await store.mergeEvents(collected)
        let touchedDays = Set(collected.map { UsageAggregator.localDayKey($0.ts) })
        if dirty.isEmpty {
            // 正常路径：只重算受影响的 day/month/year 桶（rebuildAggregates 内部只读受影响月明细）。
            await store.rebuildAggregates(forDayKeys: touchedDays)
        } else {
            // 罕见路径（损坏月被当空覆盖）：该月"原本有、现在丢了"的事件无源可找回；
            // 直接 rebuildAllAggregates 一次让所有 agg 桶回到与现存明细一致的状态（spec §3.3 已 accept）。
            // 不再额外调 rebuildAggregates（避免重复重建）。
            await store.rebuildAllAggregates()
        }
        lastResult = CollectResult(newEventCount: collected.count, scannedFileCount: scanned, parseErrorCount: parseErrors, touchedDayKeys: touchedDays)
        return lastResult
    }

    // MARK: scanRoots（从 v0.1.2 LocalCostScanner 复制；LocalCostScanner.swift Task 7 删除）
    static func scanRoots() -> [URL] {
        scanRoots(env: ProcessInfo.processInfo.environment,
                  home: FileManager.default.homeDirectoryForCurrentUser,
                  fileExists: { FileManager.default.fileExists(atPath: $0) })
    }
    static func scanRoots(env: [String: String], home: URL, fileExists: (String) -> Bool) -> [URL] {
        var roots: [URL] = []
        if let v = env["CLAUDE_CONFIG_DIR"], !v.isEmpty {
            for path in v.split(separator: ":") {
                let url = URL(fileURLWithPath: String(path)).appendingPathComponent("projects", isDirectory: true)
                if fileExists(url.path) { roots.append(url) }
            }
        }
        let xdg = home.appendingPathComponent(".config/claude/projects", isDirectory: true)
        if fileExists(xdg.path) { roots.append(xdg) }
        let legacy = home.appendingPathComponent(".claude/projects", isDirectory: true)
        if fileExists(legacy.path) { roots.append(legacy) }
        return roots
    }
}
```

> 注：dirty 月（明细文件损坏被当空覆盖）走 `rebuildAllAggregates` 兜底一次——与 spec §3.3"该月按空 + log type，accepted（罕见）"一致；spec 也允许"无可重读源 → 该月按空"。正常路径走 `rebuildAggregates(forDayKeys:)`（内部只读受影响月明细，见 Task 2 Step 6 的 G3 B2 实现）。`testCorruptedMonthFileTreatedAsEmpty`（Task 2）已覆盖 store 层；collector 层不需额外 case。`#"..."#` raw string literal 用于测试里含引号的半行。

- [ ] **Step 4: 运行确认通过**

Run: `cd macos && swift test --filter ClaudeUsageCollectorTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 6 tests, with 0 failures`（`testNoNewEventsReturnsZeroAndNoWrite` 依赖 mtime 不变——若文件系统 mtime 精度问题导致 flaky，改为断言 `queryEvents` 数量不变 + `newEventCount == 0`）

- [ ] **Step 5: 全量构建 + 测试 + 隐私守护**

Run: 同 Task 1 Step 6。注意 `! grep ... '\.path\b' macos/Sources/UsageBar/` 必须无输出——collector 里有 `file.path`（传给 `attributesOfItem`、`fileExists`），但**不在 NSLog/print 里**，所以 grep（只匹配 `(print|NSLog|...)\s*[\(,].*\.path`）不会命中。确认 `GUARD-OK`。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/UsageBar/ClaudeUsageCollector.swift macos/Tests/UsageBarTests/ClaudeUsageCollectorTests.swift
git commit -m "$(cat <<'EOF'
feat: ClaudeUsageCollector 增量采集 [spec:2026-05-12-usage-store-redesign]

actor collect()：枚举 scanRoots（沿用 v0.1.2 优先级）→ 问游标增量读 →
复用 JSONLCostParser.parseLine → 收 StoredUsageEvent → mergeEvents →
rebuildAggregates → 更新游标。无 trailing \n 的末行不消费（CLI 部分写入保护）；
无新事件直接返回不写盘；parseError 不中断；inFlight 节流；只 log error type。
6 个单测覆盖跨月首扫 / 增量 / 无新事件不写盘 / 部分末行 / parseError / 去重。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: UsageStatsService

**Files:**
- Create: `macos/Sources/UsageBar/UsageStatsService.swift`
- Test: `macos/Tests/UsageBarTests/UsageStatsServiceTests.swift`

- [ ] **Step 1: 写失败测试**

Create `macos/Tests/UsageBarTests/UsageStatsServiceTests.swift`:

```swift
import XCTest
@testable import UsageBar

@MainActor
final class UsageStatsServiceTests: XCTestCase {
    private var tmpRoot: URL!, tmpData: URL!
    override func setUp() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stats-test-\(UUID().uuidString)", isDirectory: true)
        tmpRoot = base.appendingPathComponent("projects", isDirectory: true)
        tmpData = base.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpData, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: tmpRoot.deletingLastPathComponent()) }

    private func line(ts: String, msg: String, req: String) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(msg)","model":"claude-opus-4-7","usage":{"input_tokens":1000000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }
    private func writeSession(_ lines: [String]) throws {
        let dir = tmpRoot.appendingPathComponent("p1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: dir.appendingPathComponent("00000000-mock-0000-0000-000000000001.jsonl"))
    }
    private func makeService() -> UsageStatsService {
        let store = UsageEventStore(dataDirOverride: tmpData)
        let cursor = ScanCursorStore(dataDirOverride: tmpData)
        return UsageStatsService(store: store, collector: ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]))
    }

    func testRefreshPublishesRolling30dAndDailyAndMonthly() async throws {
        try writeSession([
            line(ts: ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!, formatOptions: [.withInternetDateTime, .withFractionalSeconds]),
                 msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let s = makeService()
        await s.refresh()
        XCTAssertNotNil(s.rolling30d)
        XCTAssertGreaterThan(s.rolling30d!.totalUSD, 0)   // 1M input opus ≈ $15
        XCTAssertFalse(s.dailySpend.isEmpty)
        XCTAssertFalse(s.monthlySpend.isEmpty)
        XCTAssertFalse(s.isInitializing)
    }

    func testRefreshWithNoJSONLKeepsRolling30dNil() async throws {
        // 不写任何 session 文件
        let s = makeService()
        await s.refresh()
        XCTAssertNil(s.rolling30d)
        XCTAssertTrue(s.dailySpend.allSatisfy { $0.usd == 0 } || s.dailySpend.isEmpty)
        XCTAssertFalse(s.isInitializing)
    }

    func testIsInitializingTrueDuringFirstRefresh() async throws {
        let s = makeService()
        XCTAssertTrue(s.isInitializing)   // 构造后、首次 refresh 前
        await s.refresh()
        XCTAssertFalse(s.isInitializing)
    }

    func testConcurrentRefreshDoesNotCrash() async throws {
        try writeSession([line(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a")])
        let s = makeService()
        async let a: Void = s.refresh()
        async let b: Void = s.refresh()
        _ = await (a, b)
        // 不崩、状态一致即可
        XCTAssertFalse(s.isInitializing)
    }
}

private extension ISO8601DateFormatter {
    static func string(from date: Date, timeZone: TimeZone, formatOptions: ISO8601DateFormatter.Options) -> String {
        let f = ISO8601DateFormatter(); f.timeZone = timeZone; f.formatOptions = formatOptions; return f.string(from: date)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd macos && swift test --filter UsageStatsServiceTests 2>&1 | tail -3`
Expected: 编译失败（`UsageStatsService` 未定义）。

- [ ] **Step 3: 实现 UsageStatsService**

Create `macos/Sources/UsageBar/UsageStatsService.swift`:

```swift
import Foundation
import Combine

@MainActor
final class UsageStatsService: ObservableObject {
    @Published private(set) var rolling30d: CostSummary? = nil
    @Published private(set) var dailySpend: [DaySpend] = []
    @Published private(set) var monthlySpend: [MonthSpend] = []
    @Published private(set) var isInitializing: Bool = true

    private let store: UsageEventStore
    private let collector: ClaudeUsageCollector
    private var inFlight = false

    init(store: UsageEventStore, collector: ClaudeUsageCollector) {
        self.store = store; self.collector = collector
    }
    /// 生产环境便捷构造（默认 data 目录 + 默认 scanRoots）。
    convenience init() {
        let store = UsageEventStore()
        self.init(store: store, collector: ClaudeUsageCollector(store: store, cursor: ScanCursorStore()))
    }

    func refresh() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        let store = self.store
        let collector = self.collector
        // 为何 collector 已是 actor 还要 detached：沿用 v0.1.2 G3 #2 工艺——把整条 actor→actor→IO 链放到
        // cooperative pool，MainActor 只在最后写回 published 那一刻参与。
        let computed: (CostSummary?, [DaySpend], [MonthSpend]) = await Task.detached(priority: .utility) {
            let result = await collector.collect()
            let dayAgg = await store.readDayAggregates()
            let monthAgg = await store.readMonthAggregates()
            let daily = UsageAggregator.dailySpend(from: dayAgg)
            let monthly = UsageAggregator.monthlySpend(from: monthAgg)
            let hasData = result.scannedFileCount > 0 && !dayAgg.isEmpty
            let summary: CostSummary? = hasData
                ? UsageAggregator.rolling30dSummary(dayAggregates: dayAgg, now: Date(),
                                                    scannedFileCount: result.scannedFileCount, parseErrorCount: result.parseErrorCount)
                : nil
            return (summary, daily, monthly)
        }.value
        self.rolling30d = computed.0
        self.dailySpend = computed.1
        self.monthlySpend = computed.2
        self.isInitializing = false
    }
}
```

> 注：`rolling30d` 在"有 JSONL 但 30 天内没消费"时仍非 nil（`totalUSD == 0` 的 CostSummary）——但 v0.1.2 的 `LocalCostCard` 只在 `localCost30d == nil || scannedFileCount == 0` 时隐藏。这里 `hasData` 用 `scannedFileCount > 0 && !dayAgg.isEmpty` 判定；无 JSONL 时 `scannedFileCount == 0` → summary nil → 卡隐藏，符合 spec。

- [ ] **Step 4: 运行确认通过**

Run: `cd macos && swift test --filter UsageStatsServiceTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 5: 全量构建 + 测试 + 隐私守护**

Run: 同 Task 1 Step 6。Expected: 全绿；`GUARD-OK`。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/UsageBar/UsageStatsService.swift macos/Tests/UsageBarTests/UsageStatsServiceTests.swift
git commit -m "$(cat <<'EOF'
feat: UsageStatsService（@MainActor ObservableObject）[spec:2026-05-12-usage-store-redesign]

@Published rolling30d/dailySpend/monthlySpend/isInitializing；refresh() 内
Task.detached(.utility) 跑 collector.collect + 读 agg + UsageAggregator 折算，
MainActor.run 写回；inFlight 节流；无 JSONL 时 rolling30d 保持 nil。
4 个单测覆盖 publish / 无 JSONL / isInitializing / 并发 refresh。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: UsageHeatmapModel + UsageHeatmapView

**Files:**
- Create: `macos/Sources/UsageBar/UsageHeatmapView.swift`
- Test: `macos/Tests/UsageBarTests/UsageHeatmapModelTests.swift`

- [ ] **Step 1: 写 UsageHeatmapModel 失败测试**

Create `macos/Tests/UsageBarTests/UsageHeatmapModelTests.swift`:

```swift
import XCTest
@testable import UsageBar

final class UsageHeatmapModelTests: XCTestCase {
    private func day(_ s: String, usd: Double, calls: Int = 1) -> DaySpend {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return DaySpend(dayKey: s, date: f.date(from: s)!, usd: usd, calls: calls)
    }

    func testGridSpansAtLeast53Weeks() {
        let model = UsageHeatmapModel(daySpends: [day("2026-05-11", usd: 1)], referenceDate: day("2026-05-11", usd: 0).date)
        // 7 行 × ≥53 列
        XCTAssertEqual(model.weeks.count, 53)
        XCTAssertTrue(model.weeks.allSatisfy { $0.count == 7 })
    }

    func testZeroSpendDayIsBucketZero() {
        let model = UsageHeatmapModel(daySpends: [day("2026-05-11", usd: 0)], referenceDate: day("2026-05-11", usd: 0).date)
        let cell = model.cell(forDayKey: "2026-05-11")
        XCTAssertEqual(cell?.bucket, 0)
    }

    func testColorBucketsHaveContrastForLightUser() {
        // 全部小额（$0.01 ~ $0.5），应拉开 ≥3 个非零档（不被压成单色）
        let days = (1...20).map { day(String(format: "2026-05-%02d", $0), usd: Double($0) * 0.025) }
        let model = UsageHeatmapModel(daySpends: days, referenceDate: days.last!.date)
        let buckets = Set(days.compactMap { model.cell(forDayKey: $0.dayKey)?.bucket })
        XCTAssertGreaterThanOrEqual(buckets.subtracting([0]).count, 3)
    }

    func testNineBucketsMax() {
        let days = (1...28).map { day(String(format: "2026-05-%02d", $0), usd: pow(2.0, Double($0))) }   // 指数增长
        let model = UsageHeatmapModel(daySpends: days, referenceDate: days.last!.date)
        let buckets = Set(days.compactMap { model.cell(forDayKey: $0.dayKey)?.bucket })
        XCTAssertLessThanOrEqual(buckets.max() ?? 0, 8)   // 档位 0...8 共 9 档
    }

    func testCrossYearBoundaryIncludesBothYears() {
        let model = UsageHeatmapModel(daySpends: [day("2025-12-31", usd: 1), day("2026-01-01", usd: 2)], referenceDate: day("2026-01-15", usd: 0).date)
        XCTAssertNotNil(model.cell(forDayKey: "2025-12-31"))
        XCTAssertNotNil(model.cell(forDayKey: "2026-01-01"))
    }

    func testIsEmptyWhenAllZeroOrNoDays() {
        XCTAssertTrue(UsageHeatmapModel(daySpends: [], referenceDate: Date()).isEmpty)
        XCTAssertTrue(UsageHeatmapModel(daySpends: [day("2026-05-11", usd: 0)], referenceDate: day("2026-05-11", usd: 0).date).isEmpty)
        XCTAssertFalse(UsageHeatmapModel(daySpends: [day("2026-05-11", usd: 0.5)], referenceDate: day("2026-05-11", usd: 0).date).isEmpty)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd macos && swift test --filter UsageHeatmapModelTests 2>&1 | tail -3`
Expected: 编译失败。

- [ ] **Step 3: 实现 UsageHeatmapModel + UsageHeatmapView**

Create `macos/Sources/UsageBar/UsageHeatmapView.swift`:

```swift
import SwiftUI

/// 纯数据：把 [DaySpend] 折成 53 周 × 7 天的网格 + 每格 USD→0...8 档映射。
struct UsageHeatmapModel {
    struct Cell: Equatable {
        let dayKey: String?      // nil = 网格里超出范围的占位格
        let date: Date?
        let usd: Double
        let calls: Int
        let bucket: Int          // 0...8
    }
    /// weeks[w][d]：w = 第 w 列（最旧→最新），d = 0(周日)...6(周六)。共 53 列。
    let weeks: [[Cell]]
    let isEmpty: Bool
    private let byDayKey: [String: Cell]

    func cell(forDayKey key: String) -> Cell? { byDayKey[key] }

    init(daySpends: [DaySpend], referenceDate: Date = Date()) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 1   // G3 R3：固定周日为每周第一天（GitHub 贡献图惯例），不随 locale 变
        let dayFmt = DateFormatter(); dayFmt.calendar = cal; dayFmt.timeZone = TimeZone.current
        dayFmt.locale = Locale(identifier: "en_US_POSIX"); dayFmt.dateFormat = "yyyy-MM-dd"

        let spendByKey = Dictionary(uniqueKeysWithValues: daySpends.map { ($0.dayKey, $0) })
        let nonZero = daySpends.filter { $0.usd > 0 }.map { $0.usd }.sorted()
        self.isEmpty = nonZero.isEmpty

        // 分位数动态分档：8 个非零档（0 档专留 usd==0）。阈值 = nonZero 的 1/8...7/8 分位。
        func bucket(for usd: Double) -> Int {
            if usd <= 0 || nonZero.isEmpty { return 0 }
            if nonZero.count == 1 { return 4 }
            // q[i] = (i/8) 分位（i=1...7）
            func quantile(_ q: Double) -> Double {
                let pos = q * Double(nonZero.count - 1)
                let lo = Int(pos.rounded(.down)), hi = min(lo + 1, nonZero.count - 1)
                let frac = pos - Double(lo)
                return nonZero[lo] * (1 - frac) + nonZero[hi] * frac
            }
            let thresholds = (1...7).map { quantile(Double($0) / 8.0) }
            var b = 1
            for t in thresholds where usd > t { b += 1 }
            return min(b, 8)
        }

        // 网格末列 = 包含 referenceDate 的那一周；往前推 52 周 = 53 列。每列从周日开始。
        let startOfRefWeek = cal.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? referenceDate
        var cols: [[Cell]] = []
        var byKey: [String: Cell] = [:]
        for colBack in stride(from: 52, through: 0, by: -1) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -colBack, to: startOfRefWeek) else { continue }
            var col: [Cell] = []
            for d in 0..<7 {
                guard let date = cal.date(byAdding: .day, value: d, to: weekStart) else { col.append(Cell(dayKey: nil, date: nil, usd: 0, calls: 0, bucket: 0)); continue }
                if date > referenceDate { col.append(Cell(dayKey: nil, date: nil, usd: 0, calls: 0, bucket: 0)); continue }
                let key = dayFmt.string(from: date)
                let sp = spendByKey[key]
                let cell = Cell(dayKey: key, date: date, usd: sp?.usd ?? 0, calls: sp?.calls ?? 0, bucket: bucket(for: sp?.usd ?? 0))
                col.append(cell); byKey[key] = cell
            }
            cols.append(col)
        }
        self.weeks = cols
        self.byDayKey = byKey
    }
}

struct UsageHeatmapView: View {
    let daySpends: [DaySpend]
    let isInitializing: Bool

    private var model: UsageHeatmapModel { UsageHeatmapModel(daySpends: daySpends) }

    private func color(for bucket: Int) -> Color {
        if bucket == 0 { return Color.secondary.opacity(0.12) }
        // 1...8 → 由浅到深的绿（与 GitHub 类似但用 accentColor 系）
        return Color.green.opacity(0.18 + Double(bucket) * 0.10)   // 0.28 ... 0.98
    }
    private func tooltip(_ c: UsageHeatmapModel.Cell) -> String {
        guard let key = c.dayKey else { return "" }
        return "\(key) · ≈ \(ExtraUsage.formatUSD(c.usd)) · \(c.calls) calls"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("消费热力图（近一年）").font(.caption).foregroundStyle(.secondary)
            if isInitializing {
                HStack { ProgressView().controlSize(.small); Text("统计中…").font(.caption2).foregroundStyle(.secondary) }
            } else {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(Array(model.weeks.enumerated()), id: \.offset) { _, col in
                        VStack(spacing: 2) {
                            ForEach(Array(col.enumerated()), id: \.offset) { _, cell in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: cell.bucket))
                                    .frame(width: 9, height: 9)
                                    .help(tooltip(cell))
                                    .accessibilityLabel(cell.dayKey.map { "\($0)，约 \(ExtraUsage.formatUSD(cell.usd))" } ?? "")
                            }
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

> 注：`ExtraUsage.formatUSD` 是 v0.1.2 既有的格式化函数（`UsageModel.swift` 里）；继续复用。`.help(...)` 在 macOS 上即 tooltip。若 `ExtraUsage` 不在作用域，确认 import / 模块内可见（同 target，无需 import）。

- [ ] **Step 4: 运行确认通过**

Run: `cd macos && swift test --filter UsageHeatmapModelTests 2>&1 | grep -E 'Executed [0-9]+ test'`
Expected: `Executed 6 tests, with 0 failures`（分位数边界 case 若 flaky，按实际分布微调阈值断言——核心是 `testColorBucketsHaveContrastForLightUser` 必须过）

- [ ] **Step 5: 全量构建 + 测试 + 隐私守护**

Run: 同 Task 1 Step 6（注意 `UsageHeatmapView.swift` 也在 `SC_AUTO_NO_CONTENT_READ` 守护范围；它不读 jsonl，无 `message.content` 引用，自然过）。Expected: 全绿。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/UsageBar/UsageHeatmapView.swift macos/Tests/UsageBarTests/UsageHeatmapModelTests.swift
git commit -m "$(cat <<'EOF'
feat: 消费热力图 UsageHeatmapModel + UsageHeatmapView [spec:2026-05-12-usage-store-redesign]

UsageHeatmapModel 把 [DaySpend] 折成 53 周×7 天网格，USD→0..8 共 9 档（分位数
动态分档，保证轻度用户有对比度）；UsageHeatmapView GitHub 贡献图风格渲染 +
.help tooltip + accessibilityLabel + isInitializing 显"统计中…"。
6 个单测覆盖 53 周网格 / 0 档 / 轻度用户对比度 / 9 档上限 / 跨年 / 全 0 隐藏。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: 集成 — 接线 + 退役 LocalCostScanner

**Files:**
- Modify: `macos/Sources/UsageBar/UsageService.swift`
- Modify: `macos/Sources/UsageBar/UsageBarApp.swift`
- Modify: `macos/Sources/UsageBar/PopoverView.swift`
- Modify: `macos/Sources/UsageBar/LocalCostCard.swift`
- Delete: `macos/Sources/UsageBar/LocalCostScanner.swift`
- Delete: `macos/Tests/UsageBarTests/LocalCostScannerTests.swift`
- Modify: `macos/Sources/UsageBar/UsageServiceMultiAccountTests.swift`（若引用 `localCost30d` 需调整）

> 先看现状再改：`grep -n 'localCost30d\|refreshLocalCostIfNeeded\|LocalCostScanner\|LocalCostCard' macos/Sources/UsageBar/*.swift macos/Tests/UsageBarTests/*.swift`

- [ ] **Step 1: 删除 LocalCostScanner 及其测试**

```bash
git rm macos/Sources/UsageBar/LocalCostScanner.swift macos/Tests/UsageBarTests/LocalCostScannerTests.swift
```
（`CostSummary`/`ModelCost` 已在 Task 2 移到 `UsageStoreTypes.swift`，所以删 `LocalCostScanner.swift` 不会丢类型。`scanRoots` 已在 Task 4 复制进 collector。）

- [ ] **Step 2: 改 UsageService.swift**

- 删除 `@Published var localCost30d: CostSummary? = nil`（或类似声明）。
- 删除 `func refreshLocalCostIfNeeded() async { ... }` 整个方法。
- 在 `UsageService` 加一个属性 `private let usageStats: UsageStatsService`，构造器加参数 `usageStats: UsageStatsService` 并赋值（单向强引用，无环）。
- 在 polling tick 的回调里（`fetchUsage()` 调用之后），加：`Task.detached { [usageStats] in await usageStats.refresh() }`。
  - ⚠️ 必须确保 polling timer 内**只有这一处** `usageStats` 引用（grep 守护）；不要在 timer 里直接 new collector/store。
- `switchAccount(to:)` 里：找到 `localCost30d = nil`（或 `self.localCost30d = nil`）那一行，**删掉，不替换**。其余清状态（`usage`/`lastError`/`accountEmail`）保持。
  - 同步改一行注释：`// 本机 JSONL 统计是跨账号的，不随账号清/重算（spec 2026-05-12 §5 风险12）`

- [ ] **Step 3: 改 UsageBarApp.swift**

- 加 `@StateObject private var usageStats = UsageStatsService()`（用 Task 5 的 `convenience init()`）。
- 构造 `UsageService` 的地方（现有 `@StateObject private var service = UsageService(...)` 或在 `init` 里）改为把 `usageStats` 传进去：`UsageService(..., usageStats: usageStats)`。
  - ⚠️ `@StateObject` 不能在 `init` 里互相引用。若现有代码是 `@StateObject private var service = UsageService()`，改为：保留 `usageStats` 为 `@StateObject`，把 `service` 也保持 `@StateObject` 但用一个能拿到 `usageStats` 的方式——最简单：让 `UsageService` 的 `usageStats` 参数有默认值 `= UsageStatsService.shared`，并在 `UsageStatsService` 加 `static let shared = UsageStatsService()`；`UsageBarApp` 用 `@StateObject private var usageStats = UsageStatsService.shared` 和 `@StateObject private var service = UsageService(usageStats: .shared)`。（singleton 在本 app 是单窗口菜单栏 app，可接受；与 `LocalCostScanner.shared` 的旧模式一致。）
- 在 `.task { ... }` 里，于 `bootstrapFromCLIIfNeeded()` 之后、`startPolling()` 之前加：`await usageStats.refresh()`。
- 把 `usageStats` 通过 `.environmentObject(usageStats)` 注入到根视图（供 `PopoverView` 用），或作为参数传给 `PopoverView`。沿用项目现有注入风格。

> ⚠️ 决策点（执行者按现有代码选）：A 用 `UsageStatsService.shared` singleton（最省事，与旧 `LocalCostScanner.shared` 一致）；B 用 `@StateObject` + lazy 注入。**推荐 A**——本 app 单实例，且测试用的是 `init(store:collector:)` 不碰 singleton。在 spec 里没强制；选 A 并在 commit message 注明。

- [ ] **Step 4: 改 LocalCostCard.swift + PopoverView.swift**

- `LocalCostCard`：若它现在接收 `summary: CostSummary`（来自 `service.localCost30d`），改为从 `usageStats.rolling30d` 取。最简单：`PopoverView` 里 `if let cost = usageStats.rolling30d { LocalCostCard(summary: cost) }`（`LocalCostCard` 本身签名不变，视觉不变）。
- `PopoverView`：
  - 把原来 `if let cost = service.localCost30d { ... LocalCostCard(...) }` 改成 `if let cost = usageStats.rolling30d { ... LocalCostCard(summary: cost) }`。
  - 在 `LocalCostCard` 之后插入热力图：
    ```swift
    if !usageStats.dailySpend.isEmpty && !usageStats.dailySpend.allSatisfy({ $0.usd == 0 }) {
        Divider()
        UsageHeatmapView(daySpends: usageStats.dailySpend, isInitializing: usageStats.isInitializing)
    }
    ```
  - `PopoverView` 需要拿到 `usageStats`：加 `@EnvironmentObject var usageStats: UsageStatsService`（或构造参数），与 Step 3 的注入方式一致。
  - 不动 hero / secondary / pace / trend / chart / history / settings / AccountSwitcher 渲染。

- [ ] **Step 5: 改 UsageServiceMultiAccountTests.swift（若需要）**

`grep -n localCost30d macos/Tests/UsageBarTests/UsageServiceMultiAccountTests.swift`。该测试当前在 ~line 78 有 `service.localCost30d = CostSummary(...)`（写入）+ ~line 85 有 `XCTAssertNil(service.localCost30d)`（断言）。**两行都要删**（属性已从 `UsageService` 移除，写入行也编译不过；行为已改：切账号不再清本机统计）。该测试构造 `UsageService(credentialsStore:localProfileLoader:)` 传 2 个具名参数——给 `usageStats` 参数加默认值 `= .shared`（见 Step 3 决策 A）后该构造仍合法，无需改。

- [ ] **Step 6: 加 Caches 旧目录清理**

在 `UsageBarApp.task` 的最开头（或 `UsageStatsService.refresh()` 首次调用前），加一次 best-effort：
```swift
// 退役 v0.1.2 的 cost-usage cache（已被 ~/.config/claude-usage-bar/data/ 取代）
if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
    try? FileManager.default.removeItem(at: caches.appendingPathComponent("claude-usage-bar/cost-usage", isDirectory: true))
}
```
放在 `UsageBarApp.swift` 的 `.task` 里即可（一行 try?，失败无所谓）。

- [ ] **Step 7: 全量构建 + 测试**

Run: `cd macos && swift build -c release 2>&1 | tail -2 && swift test 2>&1 | grep -E 'Executed [0-9]+ test' | tail -1`
Expected: `Build complete!`；`Executed N tests, with 0 failures`，N ≥ 144（131 - 7 LocalCostScannerTests + 30 新增 ≈ 154）。

- [ ] **Step 8: 隐私 + 守护检查**

Run:
```bash
cd /Users/methol/data/code-methol/usage-bar
! test -e macos/Sources/UsageBar/LocalCostScanner.swift && ! test -e macos/Tests/UsageBarTests/LocalCostScannerTests.swift && echo "LCS-GONE-OK"
! grep -nrI -E '(print|NSLog|os_log|os\.log|Logger)\s*[\(,].*([Aa]ccess[Tt]oken|[Rr]efresh[Tt]oken|rawJSON|claudeAiOauth|message\.content|jsonlLine|rawLine|lastPathComponent|sessionId|sessionUUID|fileURL|absJsonlPath|\.path\b|account\.credentials)' macos/Sources/UsageBar/ && echo "NO-PRINT-OK"
! grep -nrI -E 'sk-ant-(oat|ort|api)[0-9a-zA-Z]|sk-proj-[0-9a-zA-Z]|AKIA[0-9A-Z]{16}' macos/ docs/ CHANGELOG.md && echo "NO-TOKEN-OK"
! grep -nrIE 'message\.content|StoredUsageEvent[^/]*\.content|Envelope\.Message[^/]*\bcontent\b\s*:' macos/Sources/UsageBar/JSONLCostParser.swift macos/Sources/UsageBar/UsageEventStore.swift macos/Sources/UsageBar/ClaudeUsageCollector.swift macos/Sources/UsageBar/UsageHeatmapView.swift && echo "NO-CONTENT-OK"
# polling timer 守护：UsageService 里 usageStats / collector / store 引用只在 polling 回调那一处
grep -n 'usageStats\|UsageEventStore\|ClaudeUsageCollector' macos/Sources/UsageBar/UsageService.swift
```
Expected: `LCS-GONE-OK` / `NO-PRINT-OK` / `NO-TOKEN-OK` / `NO-CONTENT-OK` 都打印；最后一条 grep 输出里 `usageStats` 只出现在属性声明、构造器、polling 回调三处，无 `UsageEventStore`/`ClaudeUsageCollector` 直接出现。

- [ ] **Step 9: Commit**

```bash
git add -A macos/
git commit -m "$(cat <<'EOF'
feat: 接线新用量存储层 + 退役 LocalCostScanner [spec:2026-05-12-usage-store-redesign]

UsageService 删 localCost30d/refreshLocalCostIfNeeded，持 usageStats 单向强引用，
polling tick 调 usageStats.refresh；switchAccount 不再清本机统计（跨账号无关）。
UsageBarApp 加 usageStats（singleton 注入）+ .task 串首次 refresh + 清 v0.1.2
旧 Caches。PopoverView/LocalCostCard 数据源改 usageStats.rolling30d + 插
UsageHeatmapView。删除 LocalCostScanner.swift + 其测试（被 store+collector 取代）。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: G6 收尾（spec/version/CHANGELOG）

**Files:**
- Modify: `docs/superpowers/specs/2026-05-12-usage-store-redesign.md`（status / reviews / Verification log / spec_criteria done）
- Modify: `docs/versions/v0.2.3-usage-store-redesign.md`（status → in-progress；release_notes_zh）
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/README.md`（status accepted → implemented）

> 本任务在 G5 code-review 通过后执行（G5 是独立流程，不在本 plan steps 内——执行 plan 的 agent 完成 Task 7 后应触发 G5，再回来做 Task 8）。

- [ ] **Step 1: 填 spec Verification log + spec_criteria done**

对 `2026-05-12-usage-store-redesign.md` 的 `## Verification log`，把每条 `- [ ] SCN — pending` 改成 `- [x] SCN — evidence: <commit hash + 具体证据>`（引用 Task 0~7 的 commit）。同步把 frontmatter `spec_criteria` 每条 `done: false` → `done: true`、`evidence: "see ## Verification log"`。

- [ ] **Step 2: spec status + reviews append G5/G6**

- frontmatter `status: accepted` → `status: implemented`；`updated:` 改当天。
- `reviews:` 数组 append G5（独立 reviewer code-review + security/privacy，verdict + summary）和 G6（main session 验收，automated checks 结果 + manual UI deferred）两条，格式同已有的 G2 条目。

- [ ] **Step 3: version → in-progress + release_notes_zh**

`docs/versions/v0.2.3-usage-store-redesign.md`：`status: planned` → `status: in-progress`；填 `release_notes_zh`（中文，用户视角，含本 spec 的可感知变化：消费热力图、本地用量持久化、价格表升级后历史自动重算等），并把"Release notes (zh)"小节同步。

- [ ] **Step 4: CHANGELOG append**

`CHANGELOG.md` 顶部 append 一条 `## [v0.2.3] - usage-store-redesign`（参照现有 entry 风格，分类：改进 / 新增 / 内部；引用 spec id 与 version 文件）。

- [ ] **Step 5: specs 索引 status 更新**

`docs/superpowers/specs/README.md`：把 `2026-05-12-usage-store-redesign` 那行的 `accepted` 改 `implemented`。

- [ ] **Step 6: 最终验证**

Run:
```bash
cd /Users/methol/data/code-methol/usage-bar
grep -c '^  - gate:' docs/superpowers/specs/2026-05-12-usage-store-redesign.md   # 期望 4（G2/G3/G5/G6）
grep -c '\- \[x\] SC' docs/superpowers/specs/2026-05-12-usage-store-redesign.md  # 期望 14
grep -c '^## \[v0.2.3\]' CHANGELOG.md   # 期望 1
grep -A1 '^status:' docs/versions/v0.2.3-usage-store-redesign.md | head -2       # in-progress
cd macos && swift build -c release 2>&1 | tail -2 && swift test 2>&1 | grep -E 'Executed [0-9]+ test' | tail -1
```
Expected: 4 / 14 / 1；`status: in-progress`；构建测试全绿。

- [ ] **Step 7: Commit**

```bash
git add docs/ CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: v0.2.3 G6 收尾 — spec implemented + CHANGELOG [spec:2026-05-12-usage-store-redesign]

spec_criteria SC1~SC14 全 done；Verification log 填 evidence；spec status
accepted→implemented；reviews append G5/G6 verdict；version v0.2.3 planned→
in-progress + release_notes_zh；CHANGELOG append v0.2.3 entry；specs 索引同步。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review 记录

- **Spec coverage**：SC1(Task1+2 schema/目录/权限) / SC2(Task1+2 UsageEventStore) / SC3(Task3 ScanCursorStore) / SC4(Task4 ClaudeUsageCollector) / SC5(Task2 UsageAggregator) / SC6(Task5 UsageStatsService) / SC7(Task6 UsageHeatmapView+Model) / SC8(Task7 UsageService) / SC9(Task7 App/Popover/LocalCostCard) / SC10(Task7 删 LocalCostScanner + Caches) / SC11(每 Task 的隐私守护 step + Task7 Step8) / SC12(各 Task 测试，≈30 case) / SC13(各 Task build/test step + Task7 Step7) / SC14(Task0 + Task8 文档) — 全覆盖。
- **G3 review 已完成**（独立 general-purpose subagent，verdict approved-after-revisions，2 BLOCKING + 4 RECOMMENDED + 8 NOTES，全数受理）：
  - B1 → `testRolling30dSummaryWindowBoundary` fixture 改用明确在窗内/外的日期（`2026-04-20` / `2026-04-01`），note 改正原因说明。
  - B2 → `rebuildAggregates(forDayKeys:)` 改为只读受影响月明细（由 dayKeys 推候选 UTC 月 + 候选年的全部月），不再全读所有月；collector 的 dirty 分支不再重复 rebuild（dirty 走 rebuildAll，正常走 rebuildAggregates，二选一）。
  - R1 → Task 7 Step 5 明确删 multi-account 测试的"写入行 + 断言行"两行。
  - R2 → `testFoldByDayKeysUseLocalTimeZone` 两个 ts 改相邻 3 小时（所有现实时区同本地日）。
  - R3 → `UsageHeatmapModel.init` 加 `cal.firstWeekday = 1`（固定周日起始）。
  - R4 → `queryEvents` 用 `!name.hasPrefix("agg")` 排除 agg 文件。
  - NOTES（N1~N8）多为确认 / 微调建议，已在对应处吸收（注入决策 A 明确推荐、测试数 ≈159 ≥144、注释更正等）；其余无需 plan 改动。
- 剩余已知薄弱点：(a) `UsageBarApp` 注入用决策 A（`UsageStatsService.shared` singleton + `usageStats:` 参数默认 `.shared`），与旧 `LocalCostScanner.shared` 一致；(b) 损坏月 + 无源的兜底是 `rebuildAllAggregates`（spec §3.3 已 accept）；(c) `JSONEncoder.iso8601` 丢亚秒——对按天聚合无影响。
- **Type consistency**：`StoredUsageEvent` 字段（`cacheReadInputTokens`/`cacheCreationInputTokens`）在 store/aggregator/collector 一致；`JSONLUsageEvent`（v0.1.2）字段名 `cacheReadInputTokens`/`cacheCreationInputTokens` —— ⚠️ 执行时核对 v0.1.2 `JSONLCostParser.swift` 里实际字段名，若是 `cacheReadInputTokens` 则直接用，若不同则在 Task 4 Step 3 的 `StoredUsageEvent(...)` 构造处映射。`CostSummary`/`ModelCost` 字段沿用 v0.1.2 原样（Task 2 只是移动文件）。`DaySpend`/`MonthSpend` 在 aggregator 定义、stats service 与 heatmap 复用，字段一致。
- **Placeholder scan**：无 "TBD/TODO/implement later"；每个 code step 都有完整代码；`UsageEventStore.defaultConfigDir()` 草稿里那行笔误已显式标注要删。
