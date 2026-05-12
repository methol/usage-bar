# Claude Keychain Re-import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When Claude's token refresh permanently fails (and there's ≤1 account), try re-reading the Claude CLI Keychain before forcing "Session expired — please sign in again"; if it yields a fresh, different, non-expired credential, save it and stay signed in.

**Architecture:** `expireSession()` becomes `async`; at its entry it calls a new `attemptCLIKeychainRecovery() async -> Bool` (three gates: `accounts.count <= 1`, recovered access token ≠ the failing one, `!recovered.isExpired()`). The Keychain read is reused from v0.1.1's `ClaudeCLICredentialsStrategy`, which gains a `loadCredentials(allowInteraction:)` param so the recovery read uses `kSecUseAuthenticationUIFail` (won't pop an ACL dialog from background polling). A new `internal` injectable closure `cliKeychainLoader` on `UsageService` is the test seam (mirrors the existing `localProfileLoader:`).

**Tech Stack:** Swift 5.9, XCTest, SwiftPM (`cd macos && swift build -c release` / `swift test`). No new deps.

**Spec:** `docs/superpowers/specs/2026-05-12-claude-keychain-reimport.md` (status `accepted`, G2 approved-after-revisions — all revisions folded into §3). **Constraints:** read-only Keychain (no add/update/delete); no raw token in logs (SC7); don't break credential storage / multi-account file structure / `bootstrapFromCLIIfNeeded` / `refreshCredentials` / polling / backoff.

---

## File Structure

| File | Responsibility / change |
|---|---|
| `macos/Sources/UsageBar/ClaudeCLICredentialsStrategy.swift` (modify) | `loadCredentials()` → `loadCredentials(allowInteraction: Bool = true)`; when `!allowInteraction`, add `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail` to the query |
| `macos/Sources/UsageBar/UsageService.swift` (modify) | add `internal var cliKeychainLoader: () async -> StoredCredentials?` (default → real strategy with `allowInteraction: false`); `expireSession()` → `async`, entry calls new `attemptCLIKeychainRecovery()`; 4 call sites → `await expireSession()` |
| `macos/Tests/UsageBarTests/ClaudeKeychainReimportTests.swift` (new) | the new behaviour: recover / hard-expire-when-empty / no-loop-same-token / hard-expire-when-expired / no-recovery-multi-account / normal-refresh-unaffected |
| `macos/Tests/UsageBarTests/UsageServiceTests.swift` (modify) | the two hard-expire tests (`testFetchUsageSignsOutWhenRefreshFails`, `testExpiredTokenWithPermanentRefreshFailureSignsOut`) get `service.cliKeychainLoader = { nil }` so they still assert hard-expire after the async change |
| `docs/versions/v0.2.7-claude-keychain-reimport.md` (modify, Task 4) | status `planned` → `in-progress` then G6 checklist + release notes |

---

## Task 0: Branch + version in-progress

- [ ] **Step 1: Confirm clean tree on the v0.2.7 branch**

Run: `git status --short` (already on `feat/v0.2.7-claude-keychain-reimport`)
Expected: empty (spec/version commits already landed).

- [ ] **Step 2: Version status**

In `docs/versions/v0.2.7-claude-keychain-reimport.md` frontmatter: `status: planned` → `status: in-progress`.

- [ ] **Step 3: Commit**

```bash
git add docs/versions/v0.2.7-claude-keychain-reimport.md
git commit -m "docs: v0.2.7 进入实现阶段 (status planned→in-progress) [spec:2026-05-12-claude-keychain-reimport]"
```

---

## Task 1: `ClaudeCLICredentialsStrategy.loadCredentials(allowInteraction:)`

**Files:**
- Modify: `macos/Sources/UsageBar/ClaudeCLICredentialsStrategy.swift`
- Test: `macos/Tests/UsageBarTests/ClaudeCLICredentialsStrategyTests.swift` (add one signature/compile test; behaviour is hard to unit-test without a real Keychain — keep it minimal)

- [ ] **Step 1: Write a failing test** (append to `ClaudeCLICredentialsStrategyTests.swift`)

```swift
func testLoadCredentialsAcceptsAllowInteractionParam() async {
    // 纯签名/行为冒烟：不带 ACL 交互地读一次（机器上没装 Claude CLI 时返回 nil，不抛、不崩）。
    let result = try? await ClaudeCLICredentialsStrategy().loadCredentials(allowInteraction: false)
    // result 可能是 nil（CI 上没 Keychain 项）或一个 StoredCredentials；都不算失败。
    _ = result
}
```

- [ ] **Step 2: Run to verify it fails to compile**

Run: `cd macos && swift test --filter ClaudeCLICredentialsStrategyTests`
Expected: FAIL — `loadCredentials` has no `allowInteraction:` param.

- [ ] **Step 3: Add the param**

In `ClaudeCLICredentialsStrategy.swift`, change `func loadCredentials() async throws -> StoredCredentials?` to `func loadCredentials(allowInteraction: Bool = true) async throws -> StoredCredentials?`, and inside the `Task.detached` query dictionary add — only when `!allowInteraction` — `kSecUseAuthenticationUI: kSecUseAuthenticationUIFail`:

```swift
let queryResult: (status: OSStatus, item: AnyObject?) = await Task.detached {
    var query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: Self.serviceName,
        kSecAttrAccount: NSUserName(),
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne
    ]
    if !allowInteraction {
        query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
    }
    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (status, item)
}.value
```

(`kSecUseAuthenticationUIFail` makes `SecItemCopyMatching` return `errSecInteractionNotAllowed` instead of prompting — the existing `switch` already maps `errSecInteractionNotAllowed` → `return nil`. Note: `allowInteraction` is captured by the `Task.detached` closure — fine, it's a `let`/`Bool`.)

`ClaudeUsageStrategy` protocol declares `func loadCredentials() async throws -> StoredCredentials?` — adding a defaulted param to the concrete method still satisfies the protocol requirement (the protocol's no-arg form remains callable). Leave the protocol unchanged.

- [ ] **Step 4: Run to verify it passes**

Run: `cd macos && swift test --filter ClaudeCLICredentialsStrategyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add macos/Sources/UsageBar/ClaudeCLICredentialsStrategy.swift macos/Tests/UsageBarTests/ClaudeCLICredentialsStrategyTests.swift
git commit -m "feat: v0.2.7 ClaudeCLICredentialsStrategy.loadCredentials(allowInteraction:) — !allowInteraction 时用 kSecUseAuthenticationUIFail（后台读不弹 ACL）[spec:2026-05-12-claude-keychain-reimport]"
```

---

> **G3 corrections (ready-with-revisions, 2026-05-12) — read before doing Task 2:**
> - **The test snippets below use a fictional `makeService`/`tokenStub`/`.permanentFailureBody` API. There is NO such reusable harness.** `UsageServiceTests.swift` inlines per-test: a `private func makeStore()` + `private func makeSession()` + `private static func httpResponse(url:statusCode:body:)` + `MockURLProtocol.handler = { request in switch (method, path) { … } }`, and `MockURLProtocol` is `private` to that file. ⇒ **Put the new v0.2.7 tests INSIDE `UsageServiceTests.swift`** (append to the class) so they can use those helpers — don't create `ClaudeKeychainReimportTests.swift`. Model each new test on `testExpiredTokenWithPermanentRefreshFailureSignsOut` (line ~406): seed `store.save(StoredCredentials(accessToken: "expired-access", refreshToken: "refresh-old", expiresAt: Date().addingTimeInterval(-60), scopes: UsageService.defaultOAuthScopes))`, set `MockURLProtocol.handler` to return `400 {"error":"invalid_grant"}` for `POST /v1/oauth/token` (→ `.permanentFailure`), construct the `UsageService`, set `service.cliKeychainLoader = { … }`, `await service.fetchUsage()`, assert.
> - **`testNoRecoveryWhenMultipleAccounts`**: there is no `addAccount` API. Seed 2 accounts *before* `UsageService.init` via `store.saveAccounts(StoredAccountsFile(version: 2, activeIndex: 0, accounts: [a, b]))` + `store.save(a.credentials)` (v1 mirror), where `a.credentials` has `refreshToken: "refresh-old"` + a past `expiresAt`. See `UsageServiceMultiAccountTests.swift` lines ~37–48 for the exact pattern (`StoredAccount`/`StoredAccountsFile` shapes).
> - **`attemptCLIKeychainRecovery` on success must also `runtime.clear()` before `runtime.setConfigured(true)`** — otherwise a real multi-poll scenario leaves `runtime.lastError = "Session expired …"` stale (the previous round's `expireSession` set it with `clearSnapshot: true`, so `clear()` is safe — snapshot already nil). Plan §3.1(b) code below is updated accordingly. Add an assertion in `testRecoversFromKeychainOnPermanentRefreshFailure` that survives a prior hard-expire if practical (e.g. call `await service.fetchUsage()` twice with the loader returning nil first then a fresh cred — optional, but at minimum keep the `runtime.lastError == nil` assertion).
> - **SC2 "saveCredentials 失败 → 硬过期"**: no test exercises this; in Task 4 set its evidence honestly to "covered by the `do/catch { return false }` line + code-reading" (or add a test pointing `credentialsStore` at an unwritable dir — optional).
> - `cliKeychainLoader` default closure: drop the trailing `?? nil` (`try?` on a `T?` already flattens). Commit to a **stored property with a default closure**; don't thread through `init`.

## Task 2: `UsageService` — `cliKeychainLoader` seam + `attemptCLIKeychainRecovery()` + async `expireSession`

**Files:**
- Modify: `macos/Sources/UsageBar/UsageService.swift`
- Modify: `macos/Tests/UsageBarTests/UsageServiceTests.swift` (two hard-expire tests)
- Test: `macos/Tests/UsageBarTests/ClaudeKeychainReimportTests.swift` (new)

- [ ] **Step 1: Write the failing tests** (new file `ClaudeKeychainReimportTests.swift`)

Read `UsageServiceTests.swift` first to copy the existing test-harness style: how it builds a `UsageService` with a stub `URLSession` + temp `StoredCredentialsStore` + stub token/usage/userinfo endpoints, and how `testExpiredTokenWithPermanentRefreshFailureSignsOut` (line ~406) drives a permanent refresh failure. Reuse that harness.

```swift
import XCTest
@testable import UsageBar

final class ClaudeKeychainReimportTests: XCTestCase {

    // 复用 UsageServiceTests 的套路：临时凭证目录 + stub session/endpoints。
    // helper 见下方 makeService(...)；refresh stub 让 token endpoint 返回 invalid_grant → .permanentFailure。

    @MainActor
    func testRecoversFromKeychainOnPermanentRefreshFailure() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600))   // 已过期 → 走 refresh
        h.tokenStub = { (.permanentFailureBody, 400) }                                // refresh 永久失败
        let fresh = StoredCredentials(accessToken: "FRESH_KEYCHAIN", refreshToken: "kref",
                                      expiresAt: Date().addingTimeInterval(3600), scopes: UsageService.defaultOAuthScopes)
        h.service.cliKeychainLoader = { fresh }

        await h.service.fetchUsage()

        XCTAssertTrue(h.service.isAuthenticated)
        XCTAssertEqual(h.store.load(defaultScopes: UsageService.defaultOAuthScopes)?.accessToken, "FRESH_KEYCHAIN")
        XCTAssertNil(h.service.lastError)
        XCTAssertNil(h.service.runtime.lastError)
    }

    @MainActor
    func testHardExpiresWhenKeychainEmpty() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600))
        h.tokenStub = { (.permanentFailureBody, 400) }
        h.service.cliKeychainLoader = { nil }

        await h.service.fetchUsage()

        XCTAssertFalse(h.service.isAuthenticated)
        XCTAssertNil(h.store.load(defaultScopes: UsageService.defaultOAuthScopes))   // 已删
        XCTAssertEqual(h.service.lastError, "Session expired — please sign in again")
        XCTAssertEqual(h.service.runtime.lastError, "Session expired — please sign in again")
        XCTAssertNil(h.service.runtime.snapshot)
    }

    @MainActor
    func testNoRecoveryLoopWhenKeychainHasSameStaleToken() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600), storedAccessToken: "STALE")
        h.tokenStub = { (.permanentFailureBody, 400) }
        // Keychain 返回的 access token 与当前失败的相同
        h.service.cliKeychainLoader = { StoredCredentials(accessToken: "STALE", refreshToken: "x",
                                                          expiresAt: Date().addingTimeInterval(3600), scopes: UsageService.defaultOAuthScopes) }
        await h.service.fetchUsage()
        XCTAssertFalse(h.service.isAuthenticated)
        XCTAssertEqual(h.service.lastError, "Session expired — please sign in again")
    }

    @MainActor
    func testHardExpiresWhenKeychainTokenAlreadyExpired() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600))
        h.tokenStub = { (.permanentFailureBody, 400) }
        h.service.cliKeychainLoader = { StoredCredentials(accessToken: "DIFFERENT_BUT_DEAD", refreshToken: "x",
                                                          expiresAt: Date().addingTimeInterval(-10), scopes: UsageService.defaultOAuthScopes) }
        await h.service.fetchUsage()
        XCTAssertFalse(h.service.isAuthenticated)
        XCTAssertEqual(h.service.lastError, "Session expired — please sign in again")
    }

    @MainActor
    func testNoRecoveryWhenMultipleAccounts() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600))
        // 造出 2 个账号：用 UsageService 既有的「添加账号」路径（参考 UsageServiceTests / 多账号测试），
        // 或直接写 accounts.json（version 2，两条 account）到 h.store 再 reload。实现期挑现有最简方式。
        try h.makeSecondAccount()
        h.tokenStub = { (.permanentFailureBody, 400) }
        h.service.cliKeychainLoader = { StoredCredentials(accessToken: "FRESH", refreshToken: "x",
                                                          expiresAt: Date().addingTimeInterval(3600), scopes: UsageService.defaultOAuthScopes) }
        await h.service.fetchUsage()
        XCTAssertFalse(h.service.isAuthenticated)   // 多账号 → 不恢复
        XCTAssertEqual(h.service.lastError, "Session expired — please sign in again")
    }

    @MainActor
    func testNormalRefreshSuccessUnaffected() async throws {
        let h = try makeService(storedExpiresAt: Date().addingTimeInterval(-3600))
        h.tokenStub = { (.successRefreshBody(accessToken: "REFRESHED"), 200) }
        h.usageStub = { (.usageBody, 200) }
        h.service.cliKeychainLoader = { XCTFail("正常 refresh 成功路径不该读 Keychain"); return nil }
        await h.service.fetchUsage()
        XCTAssertTrue(h.service.isAuthenticated)
        XCTAssertNotNil(h.service.runtime.snapshot)
    }
}
```

> The `makeService(...)` helper + `tokenStub`/`usageStub`/`Data` fixtures (`.permanentFailureBody` = `{"error":"invalid_grant"}` etc.) should be built by copying the harness already present in `UsageServiceTests.swift` (it does exactly this). If that harness is `private` to `UsageServiceTests`, lift the reusable bits into a small `TestSupport`-style file or just inline a trimmed copy in `ClaudeKeychainReimportTests`. Don't over-engineer — match what `UsageServiceTests` already does.

- [ ] **Step 2: Run to verify they fail**

Run: `cd macos && swift test --filter ClaudeKeychainReimportTests`
Expected: FAIL — `cliKeychainLoader` not defined.

- [ ] **Step 3: Implement in `UsageService.swift`**

(a) Add the injectable closure as a stored property (near the other injected deps like `localProfileLoader`):

```swift
/// v0.2.7 测试接缝：refresh 永久失败时回退读 Claude CLI Keychain。默认接真实 strategy（fail-silent 读取）。
/// `try?` 作用于 `StoredCredentials?` 表达式本身就已拍平为 `StoredCredentials?`，无需额外 `?? nil`。
var cliKeychainLoader: () async -> StoredCredentials? = {
    try? await ClaudeCLICredentialsStrategy().loadCredentials(allowInteraction: false)
}
```

(Stored property with a default closure, `internal`. Don't thread through `init`.)

(b) Add the recovery method:

```swift
/// v0.2.7：refresh 永久失败时，试着从 Claude CLI Keychain 续上凭证。返回 true = 已恢复（调用方不要再硬过期）。
/// 三道门：单账号、Keychain token ≠ 刚失败的那个（防循环）、Keychain token 未过期。
private func attemptCLIKeychainRecovery() async -> Bool {
    guard accounts.count <= 1 else { return false }
    let current = loadCredentials()
    guard let recovered = await cliKeychainLoader() else { return false }
    guard recovered.accessToken != current?.accessToken else { return false }
    guard !recovered.isExpired() else { return false }
    do {
        try saveCredentials(recovered)
        isAuthenticated = true
        lastError = nil
        runtime.clear()                 // 抹掉上一轮 expireSession 留下的「Session expired」错误（snapshot 那时已被 clearSnapshot 清空，clear() 安全）
        runtime.setConfigured(true)     // 注：isAuthenticated = true 已经经 runtimeAuthSync sink 触发过一次 setConfigured(true)，这里幂等，写出来更显式
        return true
    } catch {
        return false
    }
}
```

(c) Make `expireSession` async and gate the hard-expire body on the recovery:

```swift
private func expireSession() async {
    if await attemptCLIKeychainRecovery() { return }   // 恢复成功 → 不硬过期，timer 不动，下一轮 polling 用新 token
    deleteCredentials()
    isAuthenticated = false
    usage = nil
    lastUpdated = nil
    accountEmail = nil
    timer?.invalidate()
    timer = nil
    refreshTask?.cancel()
    refreshTask = nil
    lastError = "Session expired — please sign in again"
    runtime.setError("Session expired — please sign in again", clearSnapshot: true)
}
```

(d) In `sendAuthorizedRequest`, change all 4 `expireSession()` calls to `await expireSession()`. (They're already inside `async throws` code — no other change needed. Double-check there are no other callers of `expireSession()` anywhere; `grep -n "expireSession" macos/Sources` — only the definition + those 4.)

- [ ] **Step 4: Run the new tests to verify they pass**

Run: `cd macos && swift test --filter ClaudeKeychainReimportTests`
Expected: PASS (all 6).

- [ ] **Step 5: Fix the two existing hard-expire tests in `UsageServiceTests.swift`**

`testFetchUsageSignsOutWhenRefreshFails` (line ~167) and `testExpiredTokenWithPermanentRefreshFailureSignsOut` (line ~406): after the `UsageService` is constructed, add `service.cliKeychainLoader = { nil }` (so they still hit the hard-expire branch). Keep all their existing assertions. (If those tests construct the service via a shared helper, add the line there or override per-test.) No other existing test reaches `expireSession` — `testServer500...` / `testNetworkErrorDuringRefresh...` are transient (`.transientFailure`, never expires); `testExpiredTokenWithTransientRefreshFailureDoesNotMakeAPICall` is transient too; `testFetchProfileDoesNotSignOutWhenUserinfoStillReturns401AfterRefresh` uses `expireSessionOnAuthFailure: false`.

- [ ] **Step 6: Run the full suite**

Run: `cd macos && swift build -c release && swift test`
Expected: builds; all tests pass (≈207 = 201 + 6 new; the one new strategy test from Task 1 too).

- [ ] **Step 7: SC7 grep**

Run: `grep -rnE 'accessToken|refreshToken' macos/Sources/UsageBar/UsageService.swift macos/Sources/UsageBar/ClaudeCLICredentialsStrategy.swift | grep -E 'NSLog|print|os_log|Logger|description|"\\\(' || echo "OK: no credential interpolation in logs/errors"`
Expected: `OK: ...` (eyeball-confirm the only `accessToken` interpolation in `UsageService` is the `Bearer` header in `performAuthorizedRequest`, not a log/error).

- [ ] **Step 8: Commit**

```bash
git add macos/Sources/UsageBar/UsageService.swift macos/Tests/UsageBarTests/ClaudeKeychainReimportTests.swift macos/Tests/UsageBarTests/UsageServiceTests.swift
git commit -m "feat: v0.2.7 expireSession 入口先试 Claude CLI Keychain 恢复（单账号 + token≠失败的 + !isExpired() 三道门）；expireSession 改 async；cliKeychainLoader 测试接缝；既有硬过期测试预注入 no-op loader [spec:2026-05-12-claude-keychain-reimport]"
```

---

## Task 3: Artifacts + install + manual smoke

- [ ] **Step 1: Release artifacts**

Run: `cd macos && swift test && cd .. && make release-artifacts && bash macos/scripts/verify-release.sh macos/UsageBar.zip`
Expected: all green.

- [ ] **Step 2: Install + manual smoke (SC1/SC2 — needs the human, hard to fully reproduce)**

Run: `make install`
Then: if the user's app currently shows "Session expired" while Claude Code still works → quit & relaunch the app → it should now silently re-import from Keychain and show usage instead of the expired banner. (If it can't be reproduced on demand, the unit tests are the primary evidence; note that.)

- [ ] **Step 3: If anything's wrong, fix + re-run from the relevant task. Otherwise → Task 4.**

---

## Task 4: Finalize spec + version + memory + PR + merge

- [ ] **Step 1: Fill `spec_criteria` evidence** in `docs/superpowers/specs/2026-05-12-claude-keychain-reimport.md` (SC1–SC5 → `done: true` + evidence: which tests / which code / grep output / manual smoke). Tick the `## Verification log` boxes. Set `status: implemented` (will land via the merge).

- [ ] **Step 2: Version file** `docs/versions/v0.2.7-claude-keychain-reimport.md`: fill `release_notes_zh` (中文，用户视角：「修了一个登录态误报：当 app 自己的 Claude 凭证过期、但你本机的 `claude` CLI 还在正常登录状态时，app 会自动从 `claude` 的钥匙串凭证续上，不再弹『Session expired — please sign in again』逼你重新登录（仅单账号时；只读你的钥匙串，不改动它）」). Tick the done G6 checklist items.

- [ ] **Step 3: specs README** — `2026-05-12-claude-keychain-reimport` row status `accepted` → `implemented`. **versions README** — v0.2.7 status `planned` → `in-progress`.

- [ ] **Step 4: Memory** — update `~/.claude/projects/-Users-methol-data-code-methol-usage-bar/memory/project_provider_abstraction.md` (or a small new memory): v0.2.7 done; next = v0.2.8 (Codex history+trend), v0.2.9 (Codex cost+heatmap).

- [ ] **Step 5: Commit docs + memory**

```bash
git add docs/ && git commit -m "docs: v0.2.7 spec_criteria 全勾 + version release notes + README index [spec:2026-05-12-claude-keychain-reimport]"
```

- [ ] **Step 6: G5 code-review** — dispatch an independent reviewer (codex via `codex:codex-rescue`, or `general-purpose` fallback) on the v0.2.7 diff. Sensitive surface (Keychain read + credential write) → also a security pass. Apply must-fixes, re-run `swift build && swift test`, append G5 verdict to spec `reviews:`.

- [ ] **Step 7: PR + merge** — `gh pr create` (title `feat: v0.2.7 Claude refresh 失败回退读 Claude CLI Keychain [spec:2026-05-12-claude-keychain-reimport]`; body links spec/version, lists SC table + G2/G5 verdicts). After CI (G6) green, `git checkout main && git merge --ff-only feat/v0.2.7-claude-keychain-reimport && git push origin main`; delete the branch.

---

## Self-review notes

- **Spec coverage:** SC1 → Task 2 (recovery path + `testRecoversFromKeychainOnPermanentRefreshFailure`); SC2 → Task 2 (the 3 reject gates + `testHardExpiresWhenKeychainEmpty` / `testNoRecoveryLoopWhenKeychainHasSameStaleToken` / `testHardExpiresWhenKeychainTokenAlreadyExpired` / `testNoRecoveryWhenMultipleAccounts`); SC3 → Task 1 (`allowInteraction:` + `kSecUseAuthenticationUIFail`) + Task 2 (reuse strategy, `accounts.count<=1` gate) + Task 2 step 7 (grep); SC4 → Task 2 step 1 (all 6 cases incl. expired-token & multi-account); SC5 → Task 2 step 5 (existing tests + `cliKeychainLoader = { nil }`) + Task 2 step 6 (full suite green). All covered.
- **Placeholder scan:** every code step has full code; the test-harness "copy from `UsageServiceTests`" notes give a concrete source, not a TODO.
- **Type consistency:** `ClaudeCLICredentialsStrategy.loadCredentials(allowInteraction:)`, `UsageService.cliKeychainLoader` (`() async -> StoredCredentials?`), `attemptCLIKeychainRecovery() async -> Bool`, `expireSession() async`, `StoredCredentials.isExpired()` (no-leeway, exists), `loadCredentials()` / `saveCredentials(_:)` / `deleteCredentials()` / `runtime.setConfigured(_:)` / `runtime.setError(_:clearSnapshot:)` — all match the actual codebase.
