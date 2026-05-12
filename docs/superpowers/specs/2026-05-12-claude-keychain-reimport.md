---
id: 2026-05-12-claude-keychain-reimport
title: Claude refresh 失败时回退读 Claude CLI Keychain（修「Session expired」误报）
status: draft
created: 2026-05-12
updated: 2026-05-12
owner: claude-code
model: claude-opus-4-7
target_version: v0.2.7
related_adrs: []
related_research: []
related_specs: [2026-05-11-claude-cli-credentials, 2026-05-11-multi-account, 2026-05-12-multi-provider-refactor]
spec_criteria:
  - id: SC1
    criterion: 当 Claude 的 token refresh 永久失败（refresh token 失效）或 refresh 后请求仍 401 时，先尝试从 Claude CLI Keychain（`ClaudeCLICredentialsStrategy`）读一次凭证；读到、且与当前失败的 access token 不同 → 把它存进 active account（`saveCredentials`）、`isAuthenticated` 保持 true、清 `lastError`、不弹「Session expired」；下一轮 polling 用新 token 正常拉取
    done: false
    evidence: null
  - id: SC2
    criterion: Keychain 读不到 / 解析失败 / 读到的就是同一个失效 token / `saveCredentials` 失败 → 走原来的硬过期路径（删凭证、`isAuthenticated=false`、`lastError = "Session expired — please sign in again"`、`runtime.setError(clearSnapshot:true)`）。即新逻辑只「在能恢复时恢复」，不引入新的卡死状态
    done: false
    evidence: null
  - id: SC3
    criterion: Keychain 读取是只读副作用（复用 v0.1.1 的 `ClaudeCLICredentialsStrategy.loadCredentials()`，不创建/不修改 Keychain）；不打印 raw token（沿用既有 SC7 约束）；恢复路径不破坏多账号文件结构（只更新 active account 的 credentials 镜像，和 `saveCredentials` 一贯行为一致）
    done: false
    evidence: null
  - id: SC4
    criterion: 单测覆盖：(a) refresh 永久失败 + Keychain 有新鲜凭证 → service 仍 authenticated、credentials 已被新值替换、lastError 清空、未删除凭证；(b) refresh 永久失败 + Keychain 返回 nil → 走硬过期（authenticated=false、credentials 已删、lastError 为过期文案）；(c) refresh 永久失败 + Keychain 返回的 access token 与失败的相同 → 走硬过期（不陷入恢复循环）
    done: false
    evidence: null
  - id: SC5
    criterion: Claude 既有行为零回归 —— 正常 refresh 成功路径、多账号切换、首启 `bootstrapFromCLIIfNeeded`、backoff、polling 都不受影响；`swift test` 既有用例全绿
    done: false
    evidence: null
automated_checks:
  - "SC_AUTO_BUILD: cd macos && swift build -c release"
  - "SC_AUTO_TEST: cd macos && swift test"
  - "SC_AUTO_ARTIFACTS: make release-artifacts"
manual_checks:
  - "在 app token 已过期（弹 Session expired）但 Claude Code 仍能用的机器上：重启 app（或等下一轮 polling）→ 不再弹 Session expired，正常显示用量"
reviews: []
---

# Claude refresh 失败时回退读 Claude CLI Keychain

## 1. 背景与目标

菜单栏 app 用的是它**自己**的 OAuth 凭证（`~/.config/claude-usage-bar/credentials.json`），跟 Claude Code 用的 Keychain 凭证（`Claude Code-credentials`）是两套。v0.1.1（[spec](./2026-05-11-claude-cli-credentials.md)）加了一个**首启**时从 Keychain 自动导入的 `bootstrapFromCLIIfNeeded`，但它只在「还没有任何账号」时跑一次。用户一旦手动登录过、有了账号，app 的 token 过期、且其 refresh token 也失效后，就直接 `expireSession()` 弹「Session expired — please sign in again」逼用户重登 —— 而此时 Claude Code 自己往往还在正常用（Keychain 里有新鲜 token）。用户实测就遇到了这个（2026-05-12）。

**目标**：在 `expireSession()` 真正生效前，先复用 v0.1.1 那套 Keychain 读取逻辑试着续上凭证；能续上就静默续、不打扰；续不上才走原硬过期路径。改动小、不引入新依赖、不改凭证存储格式。

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| 在哪儿插入恢复 | `expireSession()` 函数入口（所有 4 处调用点自动受益），而非每个 call site 各加一遍 | 单点改动，DRY；`expireSession` 全部调用点都在 `sendAuthorizedRequest`（已 `async`），把它改 `async` 无副作用 |
| 用什么读 Keychain | 复用现成的 `ClaudeCLICredentialsStrategy().loadCredentials()`（v0.1.1，已脱敏、已 `Task.detached` 后台读、四种「不存在/权限」OSStatus 都静默降级返回 nil） | 不重写，行为一致；SC3 只读约束直接继承 |
| 恢复后存哪 | `saveCredentials(recovered)` —— 更新 active account 的 credentials 镜像（和正常登录/refresh 一贯行为一致） | 同一人时就是「续期」；多账号下假设 active account == Claude CLI 当前登录人（常见情形成立，见 §5） |
| 防恢复循环 | 若 Keychain 读到的 access token == 当前失败的那个 → 不当作恢复，走硬过期 | 否则若 Keychain 自己也是那个失效 token，会陷入「永远 authenticated 但永远拉不到数据」的静默卡死 |
| 恢复后是否立刻重拉 | 不在 `expireSession` 里主动 `fetchUsage`（避免重入）；timer 在恢复分支不 invalidate，下一轮 polling 自然用新 token 拉 | 简单、无重入风险；用户至多等一个 polling 周期 |
| 是否限制只在单账号时恢复 | 不限制 —— 任意账号数都尝试，恢复的是 active account | 多账号用户也常是「active = 正在用的那个 = Keychain 那个」；若不是，下次 `fetchUsage` 刷新 `accountEmail` 时用户会看到邮箱变化，可自行重加，可接受 |

## 3. 设计

### 3.1 改动文件

| 文件 | 改动 |
|---|---|
| `macos/Sources/ClaudeUsageBar/UsageService.swift` | (a) `expireSession()` → `private func expireSession() async`：入口先调新私有方法 `attemptCLIKeychainRecovery()`，返回 true（已恢复）则直接 return，不执行原来的「删凭证 + 清状态 + setError」那段；返回 false 才执行原段。(b) 新增 `private func attemptCLIKeychainRecovery() async -> Bool`：`let current = loadCredentials()`；`guard let recovered = try? await ClaudeCLICredentialsStrategy().loadCredentials(), let recovered else { return false }`；`guard recovered.accessToken != current?.accessToken else { return false }`（防循环）；`do { try saveCredentials(recovered); isAuthenticated = true; runtime.setConfigured(true); lastError = nil; return true } catch { return false }`。(c) `sendAuthorizedRequest` 里 4 处 `expireSession()` 调用改 `await expireSession()`（函数已 `async`）。其余逻辑（refresh 流程、return nil 的位置）全不动。 |
| `macos/Tests/ClaudeUsageBarTests/UsageServiceTests.swift`（或新建 `ClaudeKeychainReimportTests.swift`） | 见 §3.3。需要让测试能注入「Keychain 返回什么」—— 见 §3.2。 |

### 3.2 测试接缝（不污染生产 API 的前提下）

`expireSession` 内部直接 `ClaudeCLICredentialsStrategy()` 是个具体类型，单测不好替换。两个低侵入选项，spec 倾向 **A**：

- **A（倾向）**：给 `UsageService` 加一个 `internal var cliKeychainLoader: () async -> StoredCredentials?`，默认 `{ try? await ClaudeCLICredentialsStrategy().loadCredentials() ?? nil }`，`attemptCLIKeychainRecovery` 调它。测试里替换这个闭包即可（仿 `UsageService` 已有的 `localProfileLoader` 注入风格 —— 见 init 签名里已有的 `localProfileLoader:` 参数）。是 `internal` 不是 `public`，不进对外 API 面。
- B：把 `ClaudeUsageStrategy` 协议实例做成可注入参数。比 A 重，且 `ClaudeUsageStrategy` 目前只有一个实现，YAGNI。

采 A。

### 3.3 测试方案

新增（用上面的 `cliKeychainLoader` 注入）：

- **testRecoversFromKeychainOnPermanentRefreshFailure**：构造 `UsageService`（临时 `StoredCredentialsStore`，已存一个 token、`expiresAt` 在过去 → `needsRefresh`/`isExpired`），`tokenEndpoint` 的 stub 让 refresh 返回 `invalid_grant`/401（→ `.permanentFailure`），`cliKeychainLoader` 返回一个**不同的** `StoredCredentials`（fresh `expiresAt`）。`await service.fetchUsage()`。断言：`service.isAuthenticated == true`；`loadCredentials()?.accessToken` == 注入的新 token；`service.lastError == nil`；凭证文件未被删（store 里还在）；`runtime.lastError == nil`。
- **testHardExpiresWhenKeychainEmpty**：同上但 `cliKeychainLoader` 返回 `nil`。断言：`isAuthenticated == false`；`loadCredentials() == nil`（已删）；`lastError == "Session expired — please sign in again"`；`runtime.lastError` 同上、`runtime.snapshot == nil`。
- **testNoRecoveryLoopWhenKeychainHasSameStaleToken**：`cliKeychainLoader` 返回的 `accessToken` 与当前失败的相同。断言走硬过期（同上一条）。
- **testNormalRefreshSuccessUnaffected**：refresh stub 返回成功的新 token；`cliKeychainLoader` 设成一个会让测试失败的 fatalError 闭包（确保根本没被调用）。断言正常拉到 usage、`isAuthenticated == true`。
- 既有 `UsageServiceTests` 全绿（尤其多账号、backoff、`testNetworkErrorDuringRefreshStaysAuthenticated`、`testServer500DuringRefreshStaysAuthenticated` —— 这些是 transient 失败，根本不到 `expireSession`）。

CI 仍跑 `swift build -c release` + `swift test` + `make release-artifacts`，全绿。

## 4. 文件迁移动作汇总

| 动作 | 文件 |
|---|---|
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageService.swift` —— `expireSession` 改 async + 入口加恢复尝试；新增 `attemptCLIKeychainRecovery()`；加 `cliKeychainLoader` 注入点；4 处 `expireSession()` → `await expireSession()` |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/ClaudeKeychainReimportTests.swift`（或并入 `UsageServiceTests.swift`） |
| ✅ 不动 | `ClaudeCLICredentialsStrategy.swift`（原样复用）、凭证存储、多账号文件、`bootstrapFromCLIIfNeeded`、`refreshCredentials`、polling/backoff、所有 Codex/provider 文件 |

## 5. 风险 / Open questions

1. **多账号下「active account ≠ Keychain 登录人」**：恢复会把 active account 的 token 换成 Keychain 那个人的。常见情形（active = 正在用的 = Keychain 那个）不会出问题；不一致时用户下次刷新会看到 `accountEmail` 变化，可自行重加账号。可接受。若 G2 reviewer 认为应更保守，可改成「仅当 `accounts.count <= 1` 时尝试恢复」—— spec 默认不限制，留 reviewer 判断。
2. **Keychain ACL 弹窗**：`ClaudeCLICredentialsStrategy.loadCredentials` 已经把 `SecItemCopyMatching` 放 `Task.detached` 后台线程，且 `errSecInteractionNotAllowed` 等会静默降级返回 nil。本改动是在「token 已失效、本来就要弹 Session expired」时多读一次 Keychain，不会比现状更吵。可接受。
3. **`expireSession` 改 async 的传播面**：已确认所有调用点都在 `sendAuthorizedRequest`（`async throws`）内；`runtime` mirroring 也在那里。无同步调用点。低风险。

## 6. 后续工作（不在本 spec 范围）

- 把 Keychain 当**第一优先**凭证源（每次启动都优先读 Keychain，credentials.json 退为缓存）—— 更激进，改 `bootstrapFromCLIIfNeeded` 的「已有账号就跳过」语义，单独评估
- `ClaudeUsageStrategy` 真正多实现（如 `~/.claude.json` 明文回退）—— 当前只有一个实现，YAGNI

## 7. 引用

- 前置 spec：[`2026-05-11-claude-cli-credentials.md`](./2026-05-11-claude-cli-credentials.md)（v0.1.1 Keychain bootstrap + `ClaudeCLICredentialsStrategy`）、[`2026-05-11-multi-account.md`](./2026-05-11-multi-account.md)、[`2026-05-12-multi-provider-refactor.md`](./2026-05-12-multi-provider-refactor.md)（`runtime` mirroring）
- 落地版本：[`../versions/v0.2.7-claude-keychain-reimport.md`](../versions/v0.2.7-claude-keychain-reimport.md)

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [ ] SC1 — pending
- [ ] SC2 — pending
- [ ] SC3 — pending
- [ ] SC4 — pending
- [ ] SC5 — pending
