# Codex Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `CodexProvider: UsageProvider` that reads the local `codex` CLI's ChatGPT credentials (`~/.codex/auth.json`, read-only) and `GET https://chatgpt.com/backend-api/wham/usage`, surfacing it in the popover's Codex tab via the v0.2.5 generalized view layer.

**Architecture:** Three plain support files (`CodexCredentials` = read auth.json; `CodexUsageModel` = decode wire shape + normalize windows + map to `ProviderUsageSnapshot`; `CodexUsageClient` = the HTTP GET) + one `@MainActor final class CodexProvider: UsageProvider` that owns a `ProviderRuntime` and orchestrates them in `refreshNow()`. Wired into `ProviderCoordinator(claude:additionalProviders:)`. View layer is reused; touch-ups needed: `CreditLine` gains `remainingAmount`/`isUnlimited`; `CreditLineRow` gains rendering branches; `PopoverView` extracts a `ProviderUsageArea` subview that `@ObservedObject`s the runtime (also closes v0.2.5 G5 nit ②); `ProviderCoordinator` gains `primaryEligibleIDs` (only `supportsBackgroundPolling` providers can drive the menu bar); `SettingsView` Picker uses it.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, SwiftPM (`cd macos && swift build -c release` / `swift test`). No new third-party deps.

**Spec:** `docs/superpowers/specs/2026-05-12-codex-provider.md` (status `accepted`, G2 approved-after-revisions — revisions already folded into §3). **Constraints:** read-only `~/.codex/auth.json` (never create/write), respect `CODEX_HOME`, no browser OAuth, no token refresh (401/403 → tell the user to run `codex`), SC7 = no raw `access_token`/`refresh_token`/`id_token`/`account_id` in logs / error descriptions / error case names / test failure output.

---

## File Structure

| File | Responsibility |
|---|---|
| `macos/Sources/ClaudeUsageBar/CodexCredentials.swift` (new) | `CodexCredentials` struct + `CodexCredentialStore.load(environment:)` — locate & parse auth.json; never write it |
| `macos/Sources/ClaudeUsageBar/CodexUsageModel.swift` (new) | `CodexUsageResponse: Decodable` (wire shape) + `CodexPlan` + `CodexRateWindow` + `CodexCredits` + `normalizedWindows()` + `asProviderSnapshot()` |
| `macos/Sources/ClaudeUsageBar/CodexUsageClient.swift` (new) | `CodexUsageClient.fetchUsage(credentials:session:)` — `GET wham/usage`; errors carry no credentials/body |
| `macos/Sources/ClaudeUsageBar/CodexProvider.swift` (new) | `@MainActor final class CodexProvider: UsageProvider` — owns `ProviderRuntime`, orchestrates load→fetch→map in `refreshNow()` |
| `macos/Sources/ClaudeUsageBar/ProviderUsageSnapshot.swift` (modify) | `CreditLine` += `remainingAmount: Double?`, `isUnlimited: Bool = false` |
| `macos/Sources/ClaudeUsageBar/ProviderUsageSection.swift` (modify) | `CreditLineRow` += unlimited / remaining branches + non-hardcoded title |
| `macos/Sources/ClaudeUsageBar/ProviderTabBar.swift` (modify) | `ProviderUnconfiguredView` Codex-specific copy ("运行 `codex` 登录") |
| `macos/Sources/ClaudeUsageBar/PopoverView.swift` (modify) | extract `ProviderUsageArea` subview (`@ObservedObject runtime`); configured/unconfigured decided from `runtime.isConfigured` |
| `macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift` (modify) | `primaryEligibleIDs`; constructor + setter reject non-eligible `primaryProviderID` |
| `macos/Sources/ClaudeUsageBar/SettingsView.swift` (modify) | Primary Provider Picker data source → `primaryEligibleIDs` |
| `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` (modify) | `ProviderCoordinator(claude: UsageService(), additionalProviders: [CodexProvider()])` |
| `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` (new) | credential parsing, response decode + mapping, `refreshNow()` behaviour, SC7 redaction |
| `docs/versions/v0.2.6-codex-provider.md` (modify) | status `planned` → `in-progress` (do in Task 0) |

---

## Task 0: Mark version in-progress + branch

- [ ] **Step 1: Confirm clean tree on `main`**

Run: `git status --short`
Expected: empty (the spec commit `b89f6ac` already landed).

- [ ] **Step 2: Set version status**

In `docs/versions/v0.2.6-codex-provider.md` frontmatter change `status: planned` → `status: in-progress`.

- [ ] **Step 3: Commit**

```bash
git add docs/versions/v0.2.6-codex-provider.md
git commit -m "docs: v0.2.6 进入实现阶段 (status planned→in-progress) [spec:2026-05-12-codex-provider]"
```

---

## Task 1: `CodexCredentials.swift` — read `~/.codex/auth.json`

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/CodexCredentials.swift`
- Test: `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` (new file in this task)

- [ ] **Step 1: Write the failing tests**

Create `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift`:

```swift
import XCTest
@testable import ClaudeUsageBar

final class CodexProviderTests: XCTestCase {

    // MARK: - helpers

    /// 在临时目录里写一个 auth.json，返回模拟的 environment dict（CODEX_HOME 指向它）。
    private func makeCodexHome(authJSON: String?) throws -> [String: String] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let authJSON {
            try Data(authJSON.utf8).write(to: dir.appendingPathComponent("auth.json"))
        }
        return ["CODEX_HOME": dir.path]
    }

    /// SC7：用明显的哨兵值而非像真凭证的串；如需失败 message 也只暴露掩码。
    private func mask(_ s: String?) -> String { s == nil ? "<nil>" : "<\(s!.count)chars>" }

    // MARK: - 凭证解析

    func testLoadOAuthSnakeCase() throws {
        let env = try makeCodexHome(authJSON: """
        { "tokens": { "access_token": "ACCESS_SENTINEL", "refresh_token": "REFRESH_SENTINEL",
                      "id_token": "ID_SENTINEL", "account_id": "ACCT_SENTINEL" },
          "last_refresh": "2026-05-10T12:34:56.789Z" }
        """)
        let creds = try XCTUnwrap(CodexCredentialStore.load(environment: env))
        XCTAssertEqual(creds.accessToken, "ACCESS_SENTINEL", "accessToken mismatch: \(mask(creds.accessToken))")
        XCTAssertEqual(creds.refreshToken, "REFRESH_SENTINEL")
        XCTAssertEqual(creds.idToken, "ID_SENTINEL")
        XCTAssertEqual(creds.accountId, "ACCT_SENTINEL")
    }

    func testLoadOAuthCamelCase() throws {
        let env = try makeCodexHome(authJSON: """
        { "tokens": { "accessToken": "ACCESS_SENTINEL", "refreshToken": "REFRESH_SENTINEL",
                      "idToken": "ID_SENTINEL", "accountId": "ACCT_SENTINEL" } }
        """)
        let creds = try XCTUnwrap(CodexCredentialStore.load(environment: env))
        XCTAssertEqual(creds.accessToken, "ACCESS_SENTINEL")
        XCTAssertEqual(creds.accountId, "ACCT_SENTINEL")
    }

    func testLoadAPIKeyForm() throws {
        let env = try makeCodexHome(authJSON: #"{ "OPENAI_API_KEY": "KEY_SENTINEL" }"#)
        let creds = try XCTUnwrap(CodexCredentialStore.load(environment: env))
        XCTAssertEqual(creds.accessToken, "KEY_SENTINEL")
        XCTAssertNil(creds.refreshToken)
        XCTAssertNil(creds.idToken)
        XCTAssertNil(creds.accountId)
    }

    func testLoadMissingTokensThrows() throws {
        let env = try makeCodexHome(authJSON: #"{ "something_else": true }"#)
        XCTAssertThrowsError(try CodexCredentialStore.load(environment: env)) { error in
            XCTAssertTrue(error is CodexCredentialError)
        }
    }

    func testLoadInvalidJSONThrows() throws {
        let env = try makeCodexHome(authJSON: "not json {{{")
        XCTAssertThrowsError(try CodexCredentialStore.load(environment: env))
    }

    func testLoadFileAbsentReturnsNil() throws {
        let env = try makeCodexHome(authJSON: nil)   // 目录存在，auth.json 不存在
        XCTAssertNil(try CodexCredentialStore.load(environment: env))
    }

    func testLoadRespectsCodexHome() throws {
        // makeCodexHome 已经把文件写进 $CODEX_HOME/auth.json；这里只是显式确认路径来源。
        let env = try makeCodexHome(authJSON: #"{ "OPENAI_API_KEY": "KEY_SENTINEL" }"#)
        XCTAssertNotNil(try CodexCredentialStore.load(environment: env))
        XCTAssertEqual(CodexCredentialStore.authFileURL(environment: env).lastPathComponent, "auth.json")
        XCTAssertTrue(CodexCredentialStore.authFileURL(environment: env).path.hasPrefix(env["CODEX_HOME"]!))
    }

    func testCodexCredentialErrorDescriptionHasNoRawValues() {
        // SC7：error 的字符串化不含可二次解析的凭证/数值码。
        for e in [CodexCredentialError.malformed, CodexCredentialError.missingTokens] {
            let s = "\(e)"
            XCTAssertFalse(s.contains("SENTINEL"))
            XCTAssertFalse(s.contains("{"))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: FAIL — `CodexCredentialStore` / `CodexCredentials` / `CodexCredentialError` not defined.

- [ ] **Step 3: Write `CodexCredentials.swift`**

```swift
import Foundation

/// 从本机 `codex` CLI 已登录的 `~/.codex/auth.json` 读出来的凭证（**只读**——本类型永不创建/写回该文件）。
/// 两种形态：① 顶层 `OPENAI_API_KEY` → 直接当 bearer，无 refresh/account；② `tokens.{access_token,…}` OAuth。
struct CodexCredentials: Equatable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let accountId: String?
}

/// SC7：case 名只描述「形态问题」，不带 raw 值 / 不带可二次解析的码。
enum CodexCredentialError: Error, CustomStringConvertible {
    case malformed        // 文件存在但 JSON 解析失败
    case missingTokens    // JSON 合法但既无 OPENAI_API_KEY 又无 tokens.access_token

    var description: String {
        switch self {
        case .malformed:     return "malformed"
        case .missingTokens: return "missingTokens"
        }
    }
}

enum CodexCredentialStore {
    /// `~/.codex/auth.json`；`CODEX_HOME` 设了就用 `$CODEX_HOME/auth.json`。`environment` 注入以便测试。
    static func authFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home: URL
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            home = URL(fileURLWithPath: codexHome, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        return home.appendingPathComponent("auth.json")
    }

    /// 文件不存在 → `nil`（静默，非错误）；存在但坏 → throw `CodexCredentialError`。
    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexCredentials? {
        let url = authFileURL(environment: environment)
        guard let data = try? Data(contentsOf: url) else { return nil }   // 不存在 / 读不动 → nil
        return try parse(data)
    }

    /// `internal` 让 @testable 单测能直接喂 Data。
    static func parse(_ data: Data) throws -> CodexCredentials {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CodexCredentialError.malformed
        }
        if let apiKey = obj["OPENAI_API_KEY"] as? String, !apiKey.isEmpty {
            return CodexCredentials(accessToken: apiKey, refreshToken: nil, idToken: nil, accountId: nil)
        }
        guard let tokens = obj["tokens"] as? [String: Any] else { throw CodexCredentialError.missingTokens }
        func str(_ a: String, _ b: String) -> String? { (tokens[a] as? String) ?? (tokens[b] as? String) }
        guard let access = str("access_token", "accessToken"), !access.isEmpty else {
            throw CodexCredentialError.missingTokens
        }
        return CodexCredentials(
            accessToken: access,
            refreshToken: str("refresh_token", "refreshToken"),
            idToken: str("id_token", "idToken"),
            accountId: str("account_id", "accountId")
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: PASS (all credential tests).

- [ ] **Step 5: Build whole package**

Run: `cd macos && swift build -c release`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/CodexCredentials.swift macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift
git commit -m "feat: v0.2.6 CodexCredentials — 只读解析 ~/.codex/auth.json（OAuth/API key 两形态，尊重 CODEX_HOME）[spec:2026-05-12-codex-provider]"
```

---

## Task 2: extend `CreditLine` (groundwork for Codex credit balance)

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/ProviderUsageSnapshot.swift`

- [ ] **Step 1: Add fields**

In `CreditLine`, add `var remainingAmount: Double?` and `var isUnlimited: Bool` (both after the existing fields). Update the memberwise init so the new params default (`remainingAmount: Double? = nil`, `isUnlimited: Bool = false`) — so Claude's existing call site in `UsageModel.swift` (`CreditLine(isEnabled:utilizationPct:usedAmount:limitAmount:currencyCode:)`) still compiles unchanged. If `CreditLine` uses the synthesized memberwise init, write an explicit one with defaults.

Resulting shape:
```swift
struct CreditLine: Equatable {
    var isEnabled: Bool
    var utilizationPct: Double?      // Claude extra_usage 已用百分比
    var usedAmount: Double?          // Claude
    var limitAmount: Double?         // Claude
    var remainingAmount: Double?     // Codex credits.balance — 剩余余额（与「已用/上限」语义不同，单列）
    var isUnlimited: Bool            // Codex credits.unlimited
    var currencyCode: String?

    init(isEnabled: Bool, utilizationPct: Double? = nil, usedAmount: Double? = nil,
         limitAmount: Double? = nil, remainingAmount: Double? = nil, isUnlimited: Bool = false,
         currencyCode: String? = nil) {
        self.isEnabled = isEnabled
        self.utilizationPct = utilizationPct
        self.usedAmount = usedAmount
        self.limitAmount = limitAmount
        self.remainingAmount = remainingAmount
        self.isUnlimited = isUnlimited
        self.currencyCode = currencyCode
    }
}
```

- [ ] **Step 2: Build + run full test suite**

Run: `cd macos && swift build -c release && swift test`
Expected: builds; all existing tests still pass (Claude `asProviderSnapshot` mapping unaffected — it doesn't pass the new params).

- [ ] **Step 3: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/ProviderUsageSnapshot.swift
git commit -m "refactor: v0.2.6 CreditLine += remainingAmount/isUnlimited（为 Codex 余额铺垫，Claude 路径不变）[spec:2026-05-12-codex-provider]"
```

---

## Task 3: `CodexUsageModel.swift` — decode + normalize + map

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/CodexUsageModel.swift`
- Test: append to `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `CodexProviderTests`)

```swift
    // MARK: - wham/usage 解码 + 映射

    private func decodeCodex(_ json: String) throws -> CodexUsageResponse {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
    }

    func testDecodeFullFixtureAndMap() throws {
        let resetSession = 1_750_000_000        // 任意 Unix 秒
        let resetWeekly = 1_750_500_000
        let json = """
        { "plan_type": "plus",
          "rate_limit": {
            "primary_window":   { "used_percent": 37, "reset_at": \(resetSession), "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 12, "reset_at": \(resetWeekly),  "limit_window_seconds": 604800 } },
          "credits": { "has_credits": true, "unlimited": false, "balance": 12.34 } }
        """
        let resp = try decodeCodex(json)
        XCTAssertEqual(resp.plan, .plus)
        let (s, w) = resp.normalizedWindows()
        XCTAssertEqual(s?.windowSeconds, 18000)
        XCTAssertEqual(s?.usedPercent, 37)
        XCTAssertEqual(s?.resetAt, Date(timeIntervalSince1970: TimeInterval(resetSession)))
        XCTAssertEqual(w?.windowSeconds, 604800)

        let snap = resp.asProviderSnapshot()
        XCTAssertEqual(snap.primaryWindow?.label, "Session")
        XCTAssertEqual(snap.primaryWindow?.utilizationPct, 37)
        XCTAssertEqual(snap.primaryWindow?.windowDuration, 18000)
        XCTAssertEqual(snap.primaryWindow?.resetsAt, Date(timeIntervalSince1970: TimeInterval(resetSession)))
        XCTAssertEqual(snap.secondaryWindow?.label, "Weekly")
        XCTAssertEqual(snap.secondaryWindow?.windowDuration, 604800)
        XCTAssertTrue(snap.extraWindows.isEmpty)
        XCTAssertEqual(snap.planLabel, "Plus")
        XCTAssertEqual(snap.creditLine?.isEnabled, true)
        XCTAssertEqual(try XCTUnwrap(snap.creditLine?.remainingAmount), 12.34, accuracy: 1e-9)
        XCTAssertEqual(snap.creditLine?.isUnlimited, false)
    }

    func testNormalizeSwappedWindows() throws {
        // primary 是 7d，secondary 是 5h —— normalizedWindows 要摆正
        let json = """
        { "rate_limit": {
            "primary_window":   { "used_percent": 50, "reset_at": 1, "limit_window_seconds": 604800 },
            "secondary_window": { "used_percent": 20, "reset_at": 2, "limit_window_seconds": 18000 } } }
        """
        let snap = try decodeCodex(json).asProviderSnapshot()
        XCTAssertEqual(snap.primaryWindow?.windowDuration, 18000)   // Session = 5h
        XCTAssertEqual(snap.primaryWindow?.utilizationPct, 20)
        XCTAssertEqual(snap.secondaryWindow?.windowDuration, 604800) // Weekly = 7d
        XCTAssertEqual(snap.secondaryWindow?.utilizationPct, 50)
    }

    func testDecodeSingleWindow() throws {
        let json = #"{ "rate_limit": { "primary_window": { "used_percent": 5, "reset_at": 9, "limit_window_seconds": 18000 } } }"#
        let snap = try decodeCodex(json).asProviderSnapshot()
        XCTAssertEqual(snap.primaryWindow?.windowDuration, 18000)
        XCTAssertNil(snap.secondaryWindow)
    }

    func testDecodeCreditsBalanceAsString() throws {
        let json = #"{ "credits": { "has_credits": true, "unlimited": false, "balance": "8.5" } }"#
        let snap = try decodeCodex(json).asProviderSnapshot()
        XCTAssertEqual(try XCTUnwrap(snap.creditLine?.remainingAmount), 8.5, accuracy: 1e-9)
    }

    func testDecodeCreditsUnlimited() throws {
        let json = #"{ "credits": { "has_credits": true, "unlimited": true } }"#
        let snap = try decodeCodex(json).asProviderSnapshot()
        XCTAssertEqual(snap.creditLine?.isUnlimited, true)
        XCTAssertNil(snap.creditLine?.remainingAmount)
    }

    func testDecodeUnknownPlan() throws {
        let json = #"{ "plan_type": "galaxy_brain" }"#
        let resp = try decodeCodex(json)
        XCTAssertEqual(resp.plan, .unknown("galaxy_brain"))
        XCTAssertFalse(resp.plan.displayName.isEmpty)
        XCTAssertEqual(resp.asProviderSnapshot().planLabel, resp.plan.displayName)
    }

    func testDecodeEmpty() throws {
        let snap = try decodeCodex("{}").asProviderSnapshot()
        XCTAssertNil(snap.primaryWindow)
        XCTAssertNil(snap.secondaryWindow)
        XCTAssertNil(snap.creditLine)
        XCTAssertNil(snap.planLabel)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: FAIL — `CodexUsageResponse` not defined.

- [ ] **Step 3: Write `CodexUsageModel.swift`**

```swift
import Foundation

// MARK: - wham/usage 线缆形状（字段名取自调研 docs/research/codex-data-sources.md §2）

/// Codex ChatGPT 套餐。已知值映射成 case，未知保留原串（不崩）。
enum CodexPlan: Equatable {
    case free, plus, pro, team, business, education, enterprise
    case unknown(String)          // 已知列表外的任意串（空串也走这里）

    init(rawValue: String?) {
        switch rawValue?.lowercased() {
        case "free", "free_workspace": self = .free
        case "plus":       self = .plus
        case "pro":        self = .pro
        case "team":       self = .team
        case "business":   self = .business
        case "education", "edu", "k12": self = .education
        case "enterprise": self = .enterprise
        default:           self = .unknown(rawValue ?? "")   // 注意：保留原始大小写
        }
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        case .team: return "Team"
        case .business: return "Business"
        case .education: return "Education"
        case .enterprise: return "Enterprise"
        case .unknown(let s): return s.isEmpty ? "Codex" : s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// 一个额度窗口（5h "session" / 7d "weekly"，由 windowSeconds 区分）。
struct CodexRateWindow: Equatable {
    let usedPercent: Double
    let resetAt: Date
    let windowSeconds: Int

    /// windowSeconds/60 == 300 → 5h；== 10080 → 7d。
    var windowMinutes: Int { windowSeconds / 60 }
    var isSessionWindow: Bool { windowMinutes == 300 }
    var isWeeklyWindow: Bool { windowMinutes == 10080 }
}

struct CodexCredits: Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?
}

/// `GET /backend-api/wham/usage` 的响应。子结构解码 try?-tolerant —— 坏一处不整段失败。
struct CodexUsageResponse: Decodable {
    let plan: CodexPlan
    let primaryWindow: CodexRateWindow?
    let secondaryWindow: CodexRateWindow?
    let credits: CodexCredits?

    private enum CodingKeys: String, CodingKey { case planType = "plan_type", rateLimit = "rate_limit", credits }
    private enum RateKeys: String, CodingKey { case primary = "primary_window", secondary = "secondary_window" }
    private enum WindowKeys: String, CodingKey { case usedPercent = "used_percent", resetAt = "reset_at", limitWindowSeconds = "limit_window_seconds" }
    private enum CreditKeys: String, CodingKey { case hasCredits = "has_credits", unlimited, balance }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.plan = CodexPlan(rawValue: (try? c.decodeIfPresent(String.self, forKey: .planType)) ?? nil)

        if let rl = try? c.nestedContainer(keyedBy: RateKeys.self, forKey: .rateLimit) {
            self.primaryWindow = Self.decodeWindow(rl, .primary)
            self.secondaryWindow = Self.decodeWindow(rl, .secondary)
        } else {
            self.primaryWindow = nil; self.secondaryWindow = nil
        }

        if let cc = try? c.nestedContainer(keyedBy: CreditKeys.self, forKey: .credits) {
            let balNum: Double? = (try? cc.decodeIfPresent(Double.self, forKey: .balance)) ?? nil
            let balStr: Double? = ((try? cc.decodeIfPresent(String.self, forKey: .balance)) ?? nil).flatMap { Double($0) }
            self.credits = CodexCredits(
                hasCredits: ((try? cc.decodeIfPresent(Bool.self, forKey: .hasCredits)) ?? nil) ?? false,
                unlimited:  ((try? cc.decodeIfPresent(Bool.self, forKey: .unlimited))  ?? nil) ?? false,
                balance: balNum ?? balStr
            )
        } else {
            self.credits = nil
        }
    }

    private static func decodeWindow(_ container: KeyedDecodingContainer<RateKeys>, _ key: RateKeys) -> CodexRateWindow? {
        guard let w = try? container.nestedContainer(keyedBy: WindowKeys.self, forKey: key) else { return nil }
        guard let used = try? w.decodeIfPresent(Double.self, forKey: .usedPercent),
              let resetUnix = try? w.decodeIfPresent(Double.self, forKey: .resetAt),
              let secs = try? w.decodeIfPresent(Int.self, forKey: .limitWindowSeconds),
              let used, let resetUnix, let secs else { return nil }
        return CodexRateWindow(usedPercent: used, resetAt: Date(timeIntervalSince1970: resetUnix), windowSeconds: secs)
    }
}

// MARK: - 归一 + 映射到统一 snapshot

extension CodexUsageResponse {
    /// 按 windowSeconds 把 (primary, secondary) 摆正成 (session=5h, weekly=7d)；都不匹配时按出现顺序兜底。
    func normalizedWindows() -> (session: CodexRateWindow?, weekly: CodexRateWindow?) {
        let all = [primaryWindow, secondaryWindow].compactMap { $0 }
        let session = all.first(where: { $0.isSessionWindow })
        let weekly  = all.first(where: { $0.isWeeklyWindow })
        if session != nil || weekly != nil {
            return (session, weekly)
        }
        return (all.first, all.dropFirst().first)   // 兜底：原顺序
    }

    func asProviderSnapshot() -> ProviderUsageSnapshot {
        let (session, weekly) = normalizedWindows()
        func win(_ w: CodexRateWindow?, _ label: String) -> UsageWindow? {
            guard let w else { return nil }
            return UsageWindow(label: label, utilizationPct: w.usedPercent,
                               resetsAt: w.resetAt, windowDuration: TimeInterval(w.windowSeconds))
        }
        var credit: CreditLine?
        if let c = credits {
            // 只在「有具体余额」或「unlimited」时显示卡片——避免 has_credits=true 但 balance 缺失时出现空卡。
            let enabled = (c.hasCredits && c.balance != nil) || c.unlimited
            credit = CreditLine(isEnabled: enabled,
                                remainingAmount: c.unlimited ? nil : c.balance,
                                isUnlimited: c.unlimited,
                                currencyCode: "USD")
        }
        return ProviderUsageSnapshot(
            primaryWindow: win(session, "Session"),
            secondaryWindow: win(weekly, "Weekly"),
            extraWindows: [],
            creditLine: credit,
            planLabel: planLabel
        )
    }

    var planLabel: String? {
        if case .unknown(let s) = plan, s.isEmpty { return nil }
        return plan.displayName
    }
}
```

> Note on double-optionals: `try?` applied to `decodeIfPresent(_:forKey:)` (which itself returns `T?`) yields `T??`. Every such expression here is flattened with a single `?? nil` before further use (`?? nil` then `.flatMap`/`?? false`/passing to `CodexPlan.init(rawValue:)`). If you see a "`T??` is not `T?`" error, you missed a `?? nil` — add it. The behaviour is uniformly "key missing or wrong type → treat as absent".

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: PASS.

- [ ] **Step 5: Build**

Run: `cd macos && swift build -c release`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/CodexUsageModel.swift macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift
git commit -m "feat: v0.2.6 CodexUsageModel — wham/usage 解码 + 窗口归一(5h/7d) + 映射 ProviderUsageSnapshot [spec:2026-05-12-codex-provider]"
```

---

## Task 4: `CodexUsageClient.swift` — the HTTP GET

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/CodexUsageClient.swift`
- Test: append to `CodexProviderTests.swift` (reuse a `URLProtocol` stub)

- [ ] **Step 1: Write the failing tests** (append inside `CodexProviderTests`)

```swift
    // MARK: - CodexUsageClient

    private func stubSession(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        CodexStubURLProtocol.handler = handler
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [CodexStubURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    func testClientSuccess() async throws {
        let creds = CodexCredentials(accessToken: "ACCESS_SENTINEL", refreshToken: nil, idToken: nil, accountId: "ACCT_SENTINEL")
        let session = stubSession { req in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer ACCESS_SENTINEL")
            XCTAssertEqual(req.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "ACCT_SENTINEL")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{ "plan_type": "pro", "rate_limit": { "primary_window": { "used_percent": 10, "reset_at": 5, "limit_window_seconds": 18000 } } }"#.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let r = try await CodexUsageClient.fetchUsage(credentials: creds, session: session)
        XCTAssertEqual(r.plan, .pro)
        XCTAssertEqual(r.primaryWindow?.usedPercent, 10)
    }

    func testClientUnauthorized() async {
        let creds = CodexCredentials(accessToken: "ACCESS_SENTINEL", refreshToken: nil, idToken: nil, accountId: nil)
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { CodexStubURLProtocol.handler = nil }
        do {
            _ = try await CodexUsageClient.fetchUsage(credentials: creds, session: session)
            XCTFail("expected unauthorized")
        } catch let e as CodexUsageError {
            XCTAssertEqual(e, .unauthorized)
            XCTAssertFalse("\(e)".contains("SENTINEL"))
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testClientServerErrorOmitsBody() async {
        let creds = CodexCredentials(accessToken: "ACCESS_SENTINEL", refreshToken: nil, idToken: nil, accountId: nil)
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!, Data("SECRET_BODY".utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        do {
            _ = try await CodexUsageClient.fetchUsage(credentials: creds, session: session)
            XCTFail("expected server error")
        } catch let e as CodexUsageError {
            if case .server(let code) = e { XCTAssertEqual(code, 503) } else { XCTFail("expected .server") }
            XCTAssertFalse("\(e)".contains("SECRET_BODY"))
        } catch { XCTFail("wrong error: \(error)") }
    }
```

And at file scope (bottom of the test file, alongside `CodexProviderTests`):

```swift
private final class CodexStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = CodexStubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: FAIL — `CodexUsageClient` / `CodexUsageError` not defined.

- [ ] **Step 3: Write `CodexUsageClient.swift`**

```swift
import Foundation

/// SC7：error 携带的信息只到「类别 + HTTP 状态码」，绝不带 response body / 凭证 / URLError userInfo 原文。
enum CodexUsageError: Error, Equatable, CustomStringConvertible {
    case unauthorized        // 401 / 403
    case server(status: Int) // 其它非 2xx
    case network             // URLError 等传输层失败
    case decode              // body 解码失败

    var description: String {
        switch self {
        case .unauthorized:        return "unauthorized"
        case .server(let status):  return "server(\(status))"   // 状态码本身不是凭证
        case .network:             return "network"
        case .decode:              return "decode"
        }
    }
}

enum CodexUsageClient {
    /// `~/.codex/config.toml` 的 `chatgpt_base_url` 覆盖本版本不支持（见 spec §5 风险 3）。
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func fetchUsage(credentials: CodexCredentials, session: URLSession = .shared) async throws -> CodexUsageResponse {
        var req = URLRequest(url: usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            req.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("usage-bar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw CodexUsageError.network   // 不透传 error（可能含 URL/凭证片段）
        }
        guard let http = response as? HTTPURLResponse else { throw CodexUsageError.network }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403:  throw CodexUsageError.unauthorized
        default:        throw CodexUsageError.server(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexUsageError.decode   // 不透传 DecodingError（其 context 可能含 body 片段）
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/CodexUsageClient.swift macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift
git commit -m "feat: v0.2.6 CodexUsageClient — GET chatgpt.com/backend-api/wham/usage（错误不含凭证/ body，SC7）[spec:2026-05-12-codex-provider]"
```

---

## Task 5: `CodexProvider.swift` — the `UsageProvider`

**Files:**
- Create: `macos/Sources/ClaudeUsageBar/CodexProvider.swift`
- Test: append to `CodexProviderTests.swift`

- [ ] **Step 1: Write the failing tests** (append inside `CodexProviderTests`)

`CodexProvider.refreshNow()` needs injectable seams so tests don't touch the real `~/.codex` or network. Design: `init(environment:session:)` — `environment` flows into `CodexCredentialStore.load(environment:)`, `session` into `CodexUsageClient.fetchUsage(credentials:session:)`.

```swift
    // MARK: - CodexProvider.refreshNow()

    @MainActor
    func testProviderNoCredentials() async {
        let env = (try? makeCodexHome(authJSON: nil)) ?? ["CODEX_HOME": NSTemporaryDirectory()]
        let p = CodexProvider(environment: env, session: .shared)
        await p.refreshNow()
        XCTAssertFalse(p.runtime.isConfigured)
        XCTAssertNil(p.runtime.snapshot)
        XCTAssertNil(p.runtime.lastError)
        XCTAssertFalse(p.isConfigured)
        XCTAssertEqual(p.id, .codex)
        XCTAssertFalse(p.supportsBackgroundPolling)
    }

    @MainActor
    func testProviderSuccess() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        let session = stubSession { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{ "plan_type": "plus", "rate_limit": { "primary_window": { "used_percent": 25, "reset_at": 7, "limit_window_seconds": 18000 } } }"#.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let p = CodexProvider(environment: env, session: session)
        await p.refreshNow()
        XCTAssertTrue(p.runtime.isConfigured)
        XCTAssertNil(p.runtime.lastError)
        XCTAssertNotNil(p.runtime.lastUpdated)
        XCTAssertEqual(p.runtime.snapshot?.primaryWindow?.utilizationPct, 25)
        XCTAssertEqual(p.runtime.snapshot?.planLabel, "Plus")
    }

    @MainActor
    func testProviderUnauthorizedClearsSnapshot() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        var status = 200
        let session = stubSession { req in
            let body = #"{ "rate_limit": { "primary_window": { "used_percent": 9, "reset_at": 1, "limit_window_seconds": 18000 } } }"#
            return (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let p = CodexProvider(environment: env, session: session)
        await p.refreshNow()                       // 先成功一次
        XCTAssertNotNil(p.runtime.snapshot)
        status = 401
        await p.refreshNow()                       // 再 401
        XCTAssertNotNil(p.runtime.lastError)
        XCTAssertFalse((p.runtime.lastError ?? "").contains("SENTINEL"))
        XCTAssertNil(p.runtime.snapshot)           // clearSnapshot: true
    }

    @MainActor
    func testProviderServerErrorKeepsSnapshot() async throws {
        let env = try makeCodexHome(authJSON: #"{ "tokens": { "access_token": "ACCESS_SENTINEL" } }"#)
        var status = 200
        let session = stubSession { req in
            let body = #"{ "rate_limit": { "primary_window": { "used_percent": 9, "reset_at": 1, "limit_window_seconds": 18000 } } }"#
            return (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let p = CodexProvider(environment: env, session: session)
        await p.refreshNow()
        status = 500
        await p.refreshNow()
        XCTAssertNotNil(p.runtime.lastError)
        XCTAssertEqual(p.runtime.snapshot?.primaryWindow?.utilizationPct, 9)   // 保留旧 snapshot
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: FAIL — `CodexProvider` not defined.

- [ ] **Step 3: Write `CodexProvider.swift`**

```swift
import Foundation

/// Codex provider —— 复用本机 `codex` CLI 已登录的 ChatGPT 凭证（`~/.codex/auth.json`，**只读**）
/// 拉 `chatgpt.com/backend-api/wham/usage`。无后台轮询 / 通知 / 多账号（范围收敛，见 spec §2）。
/// 不主动刷新 / 不写回 auth.json：401/403 → 提示用户跑 `codex`。
@MainActor
final class CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let runtime = ProviderRuntime()
    let supportsBackgroundPolling = false
    var isConfigured: Bool { runtime.isConfigured }

    private let environment: [String: String]
    private let session: URLSession

    init(environment: [String: String] = ProcessInfo.processInfo.environment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
        // 轻量同步探测：auth.json 在不在 —— 让 tab 一打开就显示对的「未配置 / 待拉取」态（不发网络）。
        // `load` 返回 CodexCredentials?，`try?` 再包一层 → CodexCredentials??；`?? nil` 拍平后判 != nil。
        let present = ((try? CodexCredentialStore.load(environment: environment)) ?? nil) != nil
        runtime.setConfigured(present)
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
            runtime.setSuccess(snapshot: response.asProviderSnapshot())
        } catch CodexUsageError.unauthorized {
            runtime.setError("Codex 凭证已过期，请在终端运行 `codex` 重新登录", clearSnapshot: true)
        } catch {
            runtime.setError("无法获取 Codex 用量（稍后重试）", clearSnapshot: false)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && swift test --filter CodexProviderTests`
Expected: PASS.

- [ ] **Step 5: Build + full suite**

Run: `cd macos && swift build -c release && swift test`
Expected: builds; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/CodexProvider.swift macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift
git commit -m "feat: v0.2.6 CodexProvider: UsageProvider — load→fetch→map，401 清 snapshot/网络错误留 snapshot [spec:2026-05-12-codex-provider]"
```

---

## Task 6: View-layer touch-ups (`CreditLineRow`, `PopoverView.ProviderUsageArea`)

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/ProviderUsageSection.swift`
- Modify: `macos/Sources/ClaudeUsageBar/PopoverView.swift`

These are SwiftUI view changes — verified by `swift build` (compile) + later by `make install` manual review (Task 8). No unit tests.

- [ ] **Step 1: `CreditLineRow` — add unlimited / remaining branches + non-hardcoded title**

Read `ProviderUsageSection.swift` first. `CreditLineRow`'s stored property and call site are named `credit` (`CreditLineRow(credit: credit)`) — use `credit.…` (not `line.…`):
- The header/title currently hardcodes `"Extra Usage"`. Change so: if `credit.remainingAmount != nil || credit.isUnlimited` → title `"Credits"`; else → `"Extra Usage"` (Claude).
- Body rendering: if `credit.isUnlimited` → show `"Unlimited"`; else if `credit.remainingAmount != nil` → show `"\(ExtraUsage.formatUSD(credit.remainingAmount!)) remaining"` (no progress bar — there's no limit); else keep the existing `usedAmount`/`limitAmount` + `utilizationPct` progress-bar rendering (Claude).
- Guard the whole row on `credit.isEnabled` as it does today.

- [ ] **Step 2: `ProviderUnconfiguredView` — Codex-specific copy (SC2)**

Read `ProviderTabBar.swift` (`ProviderUnconfiguredView` lives there). It currently shows generic copy. Make the message provider-specific so `.codex` reads roughly "未检测到 Codex 凭证 — 请在终端运行 `codex` 登录后回到这里"。 Simplest: a `switch provider` for the body text (other providers keep the generic line). This satisfies SC2's "请运行 codex 登录" wording.

- [ ] **Step 3: Build**

Run: `cd macos && swift build -c release`
Expected: builds.

- [ ] **Step 4: `PopoverView` — extract `ProviderUsageArea`**

Read `PopoverView.swift:55-92` (`providerArea`). Currently the `else if coordinator.isAvailable(selectedProvider), let runtime = coordinator.runtime(for: selectedProvider)` branch inlines: `if coordinator.provider(selectedProvider)?.isConfigured == true { ProviderUsageSection + lastError card + "Updated … ago" + bottomBar } else { ProviderUnconfiguredView + bottomBar }`.

Replace that inner block with `ProviderUsageArea(runtime: runtime, providerID: selectedProvider, onBackToClaude: { selectedProvider = .claude }, onRefresh: { let id = selectedProvider; Task { await coordinator.refreshNow(id) } }, settingsButton: { settingsButton }, appUpdater: appUpdater)` — pass whatever the bottom bar needs (settings link, refresh, check-for-updates, quit). Simplest: keep `bottomBar` in `PopoverView` and pass it as a `@ViewBuilder` closure, or duplicate the tiny bottom bar inside `ProviderUsageArea`. Pick the form that compiles cleanly with the least churn.

Add the subview (in `PopoverView.swift`, `private struct`):

```swift
private struct ProviderUsageArea<BottomBar: View>: View {
    @ObservedObject var runtime: ProviderRuntime
    let providerID: ProviderID
    let onBackToClaude: () -> Void
    @ViewBuilder let bottomBar: () -> BottomBar

    var body: some View {
        if runtime.isConfigured {
            ProviderUsageSection(runtime: runtime)
            if let error = runtime.lastError {
                UsageCard {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).font(.caption)
                }
            }
            if let updated = runtime.lastUpdated {
                HStack {
                    Text("Updated \(updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            bottomBar()
        } else {
            ProviderUnconfiguredView(provider: providerID, onBackToClaude: onBackToClaude)
            bottomBar()
        }
    }
}
```

And the call site in `providerArea`:

```swift
} else if coordinator.isAvailable(selectedProvider),
          let runtime = coordinator.runtime(for: selectedProvider) {
    ProviderUsageArea(runtime: runtime,
                      providerID: selectedProvider,
                      onBackToClaude: { selectedProvider = .claude },
                      bottomBar: { bottomBar })
} else {
    ProviderComingSoonView(provider: selectedProvider, onBackToClaude: { selectedProvider = .claude })
}
```

(`bottomBar` is `PopoverView`'s existing `@ViewBuilder private var bottomBar` — passing `{ bottomBar }` works since it captures `self`. If the generic-over-`BottomBar` form fights the compiler, fall back to making `ProviderUsageArea` non-generic and reconstruct a minimal bottom bar inside it from passed closures `onRefresh`/`onQuit`/etc. Either way: the key invariant is the `@ObservedObject var runtime` + `if runtime.isConfigured` decision living *inside* the observed subview.)

- [ ] **Step 5: Build**

Run: `cd macos && swift build -c release`
Expected: builds.

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/ProviderUsageSection.swift macos/Sources/ClaudeUsageBar/PopoverView.swift macos/Sources/ClaudeUsageBar/ProviderTabBar.swift
git commit -m "refactor: v0.2.6 CreditLineRow 加 unlimited/remaining 分支 + ProviderUnconfiguredView Codex 文案 + PopoverView 抽 ProviderUsageArea(@ObservedObject runtime，顺带清 v0.2.5 G5 nit ②)[spec:2026-05-12-codex-provider]"
```

---

## Task 7: Wire `CodexProvider` in + `primaryEligibleIDs`

**Files:**
- Modify: `macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift`
- Modify: `macos/Sources/ClaudeUsageBar/SettingsView.swift`
- Modify: `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift`
- Test: append to `ProviderAbstractionTests.swift` (or `CodexProviderTests.swift`) — coordinator behaviour

- [ ] **Step 1: Write the failing tests** (append; pick whichever test file — `ProviderAbstractionTests` already has coordinator tests, put it there)

```swift
    @MainActor
    func testCoordinatorPrimaryEligibleExcludesNonPollingProvider() throws {
        UserDefaults.standard.removeObject(forKey: ProviderCoordinator.primaryProviderKey)
        defer { UserDefaults.standard.removeObject(forKey: ProviderCoordinator.primaryProviderKey) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let claude = UsageService(credentialsStore: StoredCredentialsStore(directoryURL: dir))
        let codex = CodexProvider(environment: ["CODEX_HOME": dir.path], session: .shared)   // no auth.json → unconfigured
        let coord = ProviderCoordinator(claude: claude, additionalProviders: [codex])
        XCTAssertEqual(coord.availableIDs, [.claude, .codex])          // tab 里有 codex
        XCTAssertEqual(coord.primaryEligibleIDs, [.claude])           // 但不能驱动菜单栏
        coord.primaryProviderID = .codex                              // 试图设非 eligible
        XCTAssertEqual(coord.primaryProviderID, .claude, "非 eligible 的 primaryProviderID 应被拒绝/回退")
        XCTAssertNotEqual(UserDefaults.standard.string(forKey: ProviderCoordinator.primaryProviderKey), ProviderID.codex.rawValue)
    }
```

(Mirror the existing coordinator tests in `ProviderAbstractionTests.swift` — they also bracket `primaryProviderKey` cleanup; keep it order-independent.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd macos && swift test --filter testCoordinatorPrimaryEligibleExcludesNonPollingProvider`
Expected: FAIL — `primaryEligibleIDs` not defined / setting `.codex` is accepted.

- [ ] **Step 3: `ProviderCoordinator` changes**

In `ProviderCoordinator.swift`:
- Add: `var primaryEligibleIDs: [ProviderID] { availableIDs.filter { registry.provider($0)?.supportsBackgroundPolling == true } }`
- Change the `primaryProviderID` `didSet` to reject non-eligible values. Use a re-entrancy flag so the revert assignment doesn't re-run the body (relying on `== oldValue` is wrong here — on the revert, `oldValue` is the *rejected* value, not the restored one):
  ```swift
  private var isRevertingPrimary = false
  @Published var primaryProviderID: ProviderID {
      didSet {
          guard !isRevertingPrimary else { return }
          guard primaryProviderID != oldValue else { return }
          guard primaryEligibleIDs.contains(primaryProviderID) else {
              isRevertingPrimary = true
              primaryProviderID = oldValue   // 拒绝非 eligible：恢复旧值（不写 UserDefaults）
              isRevertingPrimary = false
              return
          }
          UserDefaults.standard.set(primaryProviderID.rawValue, forKey: Self.primaryProviderKey)
      }
  }
  ```
- In `init`, change the stored-value validation from `registry.isAvailable(stored)` to `primaryEligibleIDs.contains(stored)` — note `primaryEligibleIDs` reads `registry`, so it must be computed *after* `self.registry = registry`. Reorder if needed: assign `registry` first, then compute eligible, then decide `primaryProviderID`. Since `primaryEligibleIDs` is a computed property on `self`, you can't call it before all stored props are init'd — instead inline the filter against the local `registry`:
  ```swift
  self.registry = registry
  let eligible = registry.availableIDs.filter { registry.provider($0)?.supportsBackgroundPolling == true }
  if let stored, eligible.contains(stored) { self.primaryProviderID = stored } else { self.primaryProviderID = .claude }
  ```

- [ ] **Step 4: `SettingsView` change**

Read `SettingsView.swift` (the `SettingsWindowContent` General section with the "Primary Provider" Picker). Change the `ForEach` data source from `coordinator.availableIDs` to `coordinator.primaryEligibleIDs`. Change the `.disabled(...)` condition and the "More providers coming soon…" caption condition from `coordinator.availableIDs.count <= 1` to `coordinator.primaryEligibleIDs.count <= 1`. (Result this version: still only Claude → Picker still disabled with the caption. That's correct — Codex can't drive the menu bar yet.)

- [ ] **Step 5: `ClaudeUsageBarApp` change**

In `ClaudeUsageBarApp.swift`, change `@StateObject private var coordinator = ProviderCoordinator(claude: UsageService())` to `@StateObject private var coordinator = ProviderCoordinator(claude: UsageService(), additionalProviders: [CodexProvider()])`. Nothing else — `MenuBarLabel(runtime: coordinator.primaryRuntime, …)` still resolves to Claude's runtime since `primaryProviderID` can only be `.claude`.

- [ ] **Step 6: Run tests + build**

Run: `cd macos && swift build -c release && swift test`
Expected: builds; all tests pass.

- [ ] **Step 7: Commit**

```bash
git add macos/Sources/ClaudeUsageBar/ProviderCoordinator.swift macos/Sources/ClaudeUsageBar/SettingsView.swift macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift macos/Tests/ClaudeUsageBarTests/ProviderAbstractionTests.swift
git commit -m "feat: v0.2.6 注册 CodexProvider 进 coordinator + primaryEligibleIDs（只有 supportsBackgroundPolling 的 provider 能驱动菜单栏）[spec:2026-05-12-codex-provider]"
```

---

## Task 8: SC7 grep verification + artifacts + manual review

**Files:** none (verification only) — except possibly `docs/superpowers/specs/2026-05-12-codex-provider.md` (fill `spec_criteria` evidence) in Task 9.

- [ ] **Step 1: SC7 grep — no credential field interpolated into log/print/error text**

Run:
```bash
grep -rnE 'accessToken|refreshToken|idToken|accountId' macos/Sources/ClaudeUsageBar/Codex*.swift | grep -E 'print|os_log|Logger|description|"\\\(' || echo "OK: no credential interpolation found"
```
Expected: `OK: …` (the only `accessToken` use is `"Bearer \(credentials.accessToken)"` in the **header value** in `CodexUsageClient`, which is required and never logged — eyeball-confirm that line is a `setValue(forHTTPHeaderField:)`, not a log/print/error).

- [ ] **Step 2: Full test suite + release artifacts**

Run: `cd macos && swift test && cd .. && make release-artifacts && bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip`
Expected: all green.

- [ ] **Step 3: Install + manual smoke (SC1/SC2/SC3/SC6 — needs the human)**

Run: `make install`
Then: quit any running instance, relaunch, open the popover, click the **Codex** tab:
- If `codex` is logged in (`~/.codex/auth.json` exists): two cards (Session 5h + Weekly 7d) with %, progress bar, pace marker, "Resets in …"; a plan badge; a credits row if the account has credits → **SC1**. Click "Refresh" → re-fetches → **SC6**.
- If not: temporarily `mv ~/.codex/auth.json ~/.codex/auth.json.bak` (or test on a machine without codex) → Codex tab shows "未检测到… 请运行 `codex` 登录" placeholder, no error noise → **SC2**. Restore the file after.
- Switch back to the Claude tab → unchanged (menu bar label, polling, notifications all still Claude) → **SC6 regression check**. Check Settings → "Primary Provider" Picker still disabled (only Claude eligible).
- (SC3 — 401 expired — hard to force manually; covered by `testProviderUnauthorizedClearsSnapshot`. Note in evidence.)

- [ ] **Step 4: If anything's wrong, fix + re-run from the relevant task. Otherwise proceed to Task 9.**

---

## Task 9: Finalize spec + version + memory + PR

- [ ] **Step 1: Fill `spec_criteria` evidence in `docs/superpowers/specs/2026-05-12-codex-provider.md`**

For each SC1–SC7 set `done: true` and `evidence:` to the concrete proof:
- SC1/SC6 → manual smoke (Task 8 step 3) + commit hashes
- SC2 → manual smoke + `testProviderNoCredentials`
- SC3 → `testProviderUnauthorizedClearsSnapshot` / `testProviderServerErrorKeepsSnapshot`
- SC4 → code: `CodexCredentialStore` only ever `Data(contentsOf:)`, never writes; `CodexProvider` has no OAuth/refresh path; `authFileURL` reads `CODEX_HOME` (+ `testLoadRespectsCodexHome`)
- SC5 → `CodexProviderTests` decode/normalize/map cases
- SC7 → `testCodexCredentialErrorDescriptionHasNoRawValues`, `testClientUnauthorized`/`testClientServerErrorOmitsBody` (assert `"\(error)"` has no sentinel/body) + Task 8 step 1 grep output

Also check the box list under `## Verification log`. Set `status: implemented` once all done.

- [ ] **Step 2: Update version file**

`docs/versions/v0.2.6-codex-provider.md`: status `in-progress` → keep `in-progress` until merged (G6); fill `release_notes_zh` (中文，用户视角：「新增 Codex 用量标签页：自动读取本机 codex CLI 的 ChatGPT 登录态，显示 5 小时 / 7 天额度窗口、套餐、按量计费余额；只读、不改你的 codex 凭证」). Tick the G6 checklist items that are done.

- [ ] **Step 3: Update specs README index**

`docs/superpowers/specs/README.md`: change the `2026-05-12-codex-provider` row status `accepted` → `implemented`.

- [ ] **Step 4: Update memory**

Update `~/.claude/projects/-Users-methol-data-code-methol-usage-bar/memory/project_provider_abstraction.md`: v0.2.6 Codex provider 已实现；下一步 = (v0.2.7 候选：Codex 后台 polling / 历史 / 多账号，或 Cursor/Copilot/Gemini provider，按用户排期)。

- [ ] **Step 5: Commit docs + memory**

```bash
git add docs/ && git commit -m "docs: v0.2.6 spec_criteria 全勾 + version release notes + README index [spec:2026-05-12-codex-provider]"
```

- [ ] **Step 6: G5 code-review**

Dispatch an independent reviewer (codex via `codex:codex-rescue`, or `general-purpose` subagent fallback per AGENTS.md §5) to code-review the v0.2.6 diff (`git diff main...HEAD` or the range of commits from Task 0). Sensitive surface (reads OAuth tokens) → also ask for a security pass on SC7/SC4. Apply must-fixes, re-run `swift build && swift test`, append the G5 verdict to the spec `reviews:`.

- [ ] **Step 7: PR**

`gh pr create` — title `feat: v0.2.6 Codex provider — 读 ~/.codex/auth.json → wham/usage，复用泛化视图层 [spec:2026-05-12-codex-provider]`; body links the spec + version file, lists the SC table, notes G2 + G5 verdicts. Then CI (G6 gate) + merge once green and all `spec_criteria` done.

---

## Self-review notes

- **Spec coverage:** SC1 → Task 6 (CreditLineRow) + Task 8 manual; SC2 → Task 5 (`refreshNow` no-creds path) + Task 8; SC3 → Task 5 (401/server branches) + tests; SC4 → Task 1 (read-only `CodexCredentialStore`, `CODEX_HOME`) + Task 5 (no refresh/OAuth); SC5 → Task 3 tests; SC6 → existing `PopoverView.task(id:)` + `bottomBar` Refresh (no code change needed) + Task 7 (Claude regression) + Task 8 manual; SC7 → Tasks 1/4 (error case names, no body/creds in errors) + Task 8 grep. All covered.
- **Placeholder scan:** every code step has full code; the two "if the compiler fights you" notes give a concrete fallback, not a TODO.
- **Type consistency:** `CodexCredentials(accessToken:refreshToken:idToken:accountId:)`, `CodexCredentialStore.load(environment:)` / `.parse(_:)` / `.authFileURL(environment:)`, `CodexCredentialError.{malformed,missingTokens}`, `CodexUsageResponse` with `.plan/.primaryWindow/.secondaryWindow/.credits` + `.normalizedWindows()` + `.asProviderSnapshot()` + `.planLabel`, `CodexRateWindow(usedPercent:resetAt:windowSeconds:)`, `CodexUsageClient.fetchUsage(credentials:session:)` + `.usageURL`, `CodexUsageError.{unauthorized,server(status:),network,decode}`, `CodexProvider(environment:session:)` with `.id/.runtime/.supportsBackgroundPolling/.isConfigured/.refreshNow()`, `ProviderCoordinator.primaryEligibleIDs` — names are used consistently across tasks and tests.
