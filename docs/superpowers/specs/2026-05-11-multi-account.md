---
id: 2026-05-11-multi-account
title: 多账号支持（accounts store + 迁移 + popover 切换器）
status: draft
created: 2026-05-11
updated: 2026-05-11
owner: claude-code
model: claude-opus-4-7
target_version: v0.1.3
related_adrs: [0001, 0002]
related_research: [competitive-analysis]
spec_criteria:
  - id: SC1
    criterion: "新增 macos/Sources/ClaudeUsageBar/StoredAccount.swift：struct StoredAccount { id: UUID, label: String, addedAt: Date, lastUsed: Date, credentials: StoredCredentials }；struct StoredAccountsFile { version: Int = 2, activeIndex: Int, accounts: [StoredAccount] }"
    done: false
    evidence: "see ## Verification log"
  - id: SC2
    criterion: "扩展 StoredCredentialsStore：新增 accountsFileURL = directoryURL/accounts.json；新增 loadAccounts()/saveAccounts(_:)/deleteAccounts() 方法；保持现有 save()/load()/delete() 单账号 API 兼容（内部委托到 accounts[activeIndex]）"
    done: false
    evidence: "see ## Verification log"
  - id: SC3
    criterion: "迁移逻辑：load(defaultScopes:) 优先读 accounts.json；若不存在则尝试旧 credentials.json，自动包装成 StoredAccountsFile{ activeIndex:0, accounts:[StoredAccount(label:\"账号 1\", credentials: <旧>)] } 并 saveAccounts() + 删除 credentials.json；旧 legacyTokenFileURL fallback 链同款迁移；迁移失败（IO 错误）时保持旧文件不删除（fail-safe）"
    done: false
    evidence: "see ## Verification log"
  - id: SC4
    criterion: "UsageService 加 @Published accounts: [StoredAccount] = [] + @Published activeAccountId: UUID? = nil；新增 switchAccount(to:) 方法（save activeIndex + reload credentials + 重新 startPolling + 重新 fetchProfile + 触发 refreshLocalCostIfNeeded）；adoptCredentials/loadCredentials/saveCredentials 内部映射到 active account"
    done: false
    evidence: "see ## Verification log"
  - id: SC5
    criterion: "新增 addAccount(_:) 流程：完成 OAuth 后（complete sign in 路径）若 accounts.count > 0 则 append 新 account 而非覆盖；若为空走原 sign-in 路径建第一个 account；activeIndex 切到新 account；label 默认 \"账号 \\(N)\" 或 fetchProfile 后用 email"
    done: false
    evidence: "see ## Verification log"
  - id: SC6
    criterion: "新增 macos/Sources/ClaudeUsageBar/AccountSwitcherView.swift：popover 顶部 Menu/Picker 显示当前账号 label，下拉列出所有 accounts（标 ✓ active）+ 底部 \"添加账号...\" 触发 service.beginAddAccount() 进 PKCE 流程；账号数 ≤ 1 时整个 switcher 隐藏（不打扰单账号用户）"
    done: false
    evidence: "see ## Verification log"
  - id: SC7
    criterion: "**安全约束（v0.1.1/v0.1.2 SC7 永久警示延续）**：accounts.json 文件权限 0600（同 credentials.json）；目录 0700；StoredAccount/StoredAccountsFile decode 失败错误日志只 log error type 不 log raw；测试 mock 不含 'sk-ant-' 真实前缀；账号 label 不暴露 token 任何字符；SC_AUTO_NO_PRINT_TOKENS / SC_AUTO_NO_REAL_TOKEN_PREFIX 守护范围扩到本 spec 新增文件"
    done: false
    evidence: "see ## Verification log"
  - id: SC8
    criterion: "切换账号时清空 service.usage / lastError / localCost30d / accountEmail（避免显示前一个账号的数据残留）；history 不清（v0.1.3 不做 per-account history 隔离，留 v0.2.x；显示 active 账号同名 history）"
    done: false
    evidence: "see ## Verification log"
  - id: SC9
    criterion: "PopoverView 顶部插入 AccountSwitcherView（HStack 内）；当 accounts.count <= 1 时隐藏；不动现有 hero / secondary / cost / history / chart / settings 渲染"
    done: false
    evidence: "see ## Verification log"
  - id: SC10
    criterion: "新增 StoredAccountTests / StoredAccountsStoreTests / UsageServiceMultiAccountTests：≥10 case（Codable round-trip / migration from v1 credentials.json / migration from legacy token / accounts.json 0600 权限 / addAccount append 行为 / switchAccount 清状态 / activeIndex 越界 fallback / Mock UsageService 切换流程）"
    done: false
    evidence: "see ## Verification log"
  - id: SC11
    criterion: "不动 OAuth / refresh / polling timer / SetupView / CodeEntry / Settings / Notifications / Strategy(v0.1.1) / LocalCost(v0.1.2) / hero/menubar/pace/trend 既有渲染（仅 PopoverView 顶部加 switcher + UsageService 加 multi-account 字段与方法 + StoredCredentialsStore 加 accounts API）"
    done: false
    evidence: "see ## Verification log"
  - id: SC12
    criterion: "cd macos && swift build -c release 输出 'Build complete!'；cd macos && swift test 'Executed N tests, with 0 failures' 含本 spec 新增 ≥10 case（基线 103 + ≥10 = ≥113）"
    done: false
    evidence: "see ## Verification log"
  - id: SC13
    criterion: "git commit 中文、含变更主题 + spec id；spec.reviews 数组含 G2、G3、G5、G6 四条 verdict；version v0.1.3 frontmatter status placeholder→planned→in-progress；CHANGELOG.md append v0.1.3 中文 entry"
    done: false
    evidence: "see ## Verification log"
automated_checks:
  - "SC_AUTO_BUILD: cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release 2>&1 | tail -3 | grep -q 'Build complete'"
  - "SC_AUTO_TEST: cd /Users/methol/data/code-methol/usage-bar/macos && swift test 2>&1 | tail -5 | grep -E 'Executed [0-9]+ test.*0 failures'"
  - "SC_AUTO_NO_PRINT_TOKENS: ! grep -nrI -E '(print|NSLog|os_log|os\\.log|Logger)\\s*[\\(,].*([Aa]ccess[Tt]oken|[Rr]efresh[Tt]oken|rawJSON|claudeAiOauth|message\\.content|jsonlLine|rawLine|lastPathComponent|account\\.credentials)' macos/Sources/ClaudeUsageBar/ 2>/dev/null"
  - "SC_AUTO_NO_REAL_TOKEN_PREFIX: ! grep -nrI -E 'sk-ant-(oat|ort|api)[0-9a-zA-Z]|sk-proj-[0-9a-zA-Z]|AKIA[0-9A-Z]{16}' macos/ docs/ CHANGELOG.md 2>/dev/null"
  - "SC_AUTO_ACCOUNTS_PERMS: stat -f '%OLp' ~/.config/claude-usage-bar/accounts.json 2>/dev/null | grep -qE '^600$|^644$' || true  # 仅在用户实跑后能验证；CI 跳过"
manual_checks:
  - "**单账号用户启动**：accounts.json 不存在，credentials.json 存在 → 自动迁移成 1 个 account；popover 顶部不显示 switcher（accounts.count == 1）"
  - "**添加第二个账号**：popover 顶部下拉 → 添加账号 → 走 PKCE → SetupView/CodeEntry → 完成后 accounts.count == 2，active 切到新账号；popover 顶部出现 switcher"
  - "**切换账号**：下拉选另一账号 → 立即清 usage 占位、重新 fetchUsage / fetchProfile / refreshLocalCostIfNeeded；菜单栏图标 percent 即时更新"
  - "**安全 manual check**：grep 'sk-ant-' 全仓 0 匹配；ls -la ~/.config/claude-usage-bar/accounts.json 显示 0600"
reviews: []
---

# 多账号支持

## 1. 背景与目标

调研 §2.5 / §5.2 Step D 指出 CodexBar 的差异化能力之一是 multi-account（一份 app 同时管理多个 Claude OAuth 账号）。我们当前 `StoredCredentialsStore` 仅支持单条 `StoredCredentials`，新账号会覆盖旧账号。

本 spec 引入：
- **数据 schema 升级**：`accounts.json` v2（含 `activeIndex` + `accounts: [StoredAccount]`）
- **自动迁移**：旧 `credentials.json` v1 → `accounts[0]`（label "账号 1"）；旧 `legacyTokenFileURL` 同款
- **UsageService 多账号感知**：published `accounts` + `activeAccountId`；`switchAccount(to:)` / `addAccount` 流程
- **popover 顶部切换器**：accounts ≤ 1 时隐藏；> 1 时显示当前账号 + 下拉

**不在范围（精简）**：
- **per-account history 隔离**（v0.1.4 留位；本 spec 共用 history）
- **Settings 账号管理 UI**（删除 / 重命名账号）→ v0.2.x
- **Merge icons / stacked cards**（同时显示多账号用量）→ v0.2.x
- **Keychain multi-account**（v0.1.1 ClaudeCLICredentialsStrategy 仍读单 account；本 spec 不动）
- **多账号 cost scan 分账**（v0.1.2 LocalCostScanner 不区分 account）
- ADR：multi-account 是 store 内部演进，未变更架构边界；不开 ADR

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| 文件路径 | 新文件 `accounts.json`（与旧 `credentials.json` 共存） | 迁移期可 fail-safe；新文件就位后删旧文件 |
| 数据 schema | v2 含 `version` int + `activeIndex` + `accounts: [StoredAccount]` | `version` 字段供未来 v3 升级时区分 |
| StoredAccount.id | UUID（自生成） | 持久切换 ID 不依赖 label / index（label 可重名、index 可变） |
| StoredAccount.label | 默认 `"账号 \(N)"` 或 `email`（fetchProfile 成功后） | 用户友好；不暴露 token |
| 迁移触发 | `load()` 时 accounts.json 不存在 → 自动迁移 | 用户无感知；无需 UI 介入 |
| 迁移失败 | 保留旧文件不删除（fail-safe），返回旧 credentials 当 active | 不让用户登出 |
| activeIndex 越界 | clamp 到 [0, accounts.count-1]；若 empty 视为未登录 | 防御 manual edit |
| 添加账号 UX | popover 顶部下拉 → "添加账号..." → 复用 SetupView/CodeEntry PKCE | 不引入新 UI flow |
| 切换账号 UX | popover 顶部下拉直接选 → 立即切换 + 清旧 usage 占位 | 与 macOS 系统 menu 选项一致 |
| 切换时清状态 | usage / lastError / localCost30d / accountEmail 清；history **不清**（共用） | 防止前账号数据残留误导；history 隔离留 v0.1.4 |
| 单账号用户体验 | accounts.count <= 1 时 switcher 完全隐藏 | 不打扰未用 multi-account 的用户 |
| 文件权限 | accounts.json 0600（同 credentials.json）；目录 0700 | SC7 安全约束 |
| **安全 SC7** | 与 v0.1.1/v0.1.2 同款：禁 print/log token；test mock 'mock-' 前缀；error log 仅 type | 永久警示延续 |
| Logger | NSLog "[claude-usage-bar] accounts <op>: <ErrorType>" | 与已有路径对齐 |

## 3. 设计

### 3.1 数据流

```
.app 启动 → ClaudeUsageBarApp.task
              ├─ historyService.loadHistory()
              ├─ service.bootstrapFromCLIIfNeeded() (v0.1.1)
              ├─ service.refreshLocalCostIfNeeded() (v0.1.2)
              └─ service.startPolling()

UsageService.init →
  let file = store.loadAccounts(defaultScopes:)
    ├─ accounts.json exists → decode StoredAccountsFile (v2)
    ├─ credentials.json exists → migrate to StoredAccountsFile{ activeIndex:0, accounts:[<旧>] }, saveAccounts, delete credentials.json
    └─ legacy token file exists → migrate same way
  self.accounts = file.accounts
  self.activeAccountId = file.accounts[file.activeIndex].id (clamp)
  self.isAuthenticated = !file.accounts.isEmpty

popover 顶部 → AccountSwitcherView
  accounts.count <= 1 → 隐藏
  > 1 → Menu(label: activeLabel) {
    ForEach(accounts) → Button(label) { service.switchAccount(to: id) }
    Divider
    Button("添加账号...") { service.beginAddAccount() }
  }

service.switchAccount(to: id) →
  guard accounts.contains(id) else return
  saveAccounts(activeIndex: <new>)
  self.usage = nil; self.lastError = nil; self.localCost30d = nil; self.accountEmail = nil
  Task { await fetchUsage(); await fetchProfile() }
  Task { await refreshLocalCostIfNeeded() }
  scheduleTimer (重启 polling 用新 token)

service.beginAddAccount() →
  // 不删 active；保持 isAuthenticated = true
  // 触发 PKCE flow（与原 sign in 同入口；UI 通过 isAwaitingCode 切到 CodeEntry）
  isAwaitingCode = true
  // 完成后 completeSignIn 内部判 accounts.count > 0 → append 而非 overwrite
```

### 3.2 `StoredAccount.swift`

```swift
import Foundation

struct StoredAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    let addedAt: Date
    var lastUsed: Date
    var credentials: StoredCredentials
}

struct StoredAccountsFile: Codable, Equatable {
    let version: Int        // 当前 = 2
    var activeIndex: Int
    var accounts: [StoredAccount]

    static let currentVersion = 2

    /// activeIndex clamp 到合法范围；空数组返回 nil
    var activeAccount: StoredAccount? {
        guard !accounts.isEmpty else { return nil }
        let idx = min(max(activeIndex, 0), accounts.count - 1)
        return accounts[idx]
    }
}
```

### 3.3 `StoredCredentialsStore` 扩展

```swift
extension StoredCredentialsStore {
    var accountsFileURL: URL { directoryURL.appendingPathComponent("accounts.json") }

    func loadAccounts(defaultScopes: [String]) -> StoredAccountsFile? {
        // v2 优先
        if let data = try? Data(contentsOf: accountsFileURL),
           let file = try? Self.decoder.decode(StoredAccountsFile.self, from: data) {
            return file
        }
        // v1 迁移
        guard let oldCreds = load(defaultScopes: defaultScopes) else { return nil }
        let migrated = StoredAccountsFile(
            version: StoredAccountsFile.currentVersion,
            activeIndex: 0,
            accounts: [StoredAccount(
                id: UUID(),
                label: "账号 1",
                addedAt: Date(),
                lastUsed: Date(),
                credentials: oldCreds
            )]
        )
        // fail-safe：迁移落盘失败保留旧文件
        do {
            try saveAccounts(migrated)
            try? fileManager.removeItem(at: credentialsFileURL)
            try? fileManager.removeItem(at: legacyTokenFileURL)
        } catch {
            NSLog("[claude-usage-bar] accounts migration save failed: \(type(of: error))")
        }
        return migrated
    }

    func saveAccounts(_ file: StoredAccountsFile) throws {
        try ensureDirectoryExists()
        let data = try Self.encoder.encode(file)
        try data.write(to: accountsFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsFileURL.path)
    }

    func deleteAccounts() {
        try? fileManager.removeItem(at: accountsFileURL)
    }
}
```

`fileManager` / `ensureDirectoryExists` / `encoder` / `decoder` 均提升为 internal 让 extension 可见（最少改动；不破坏现有 API）。

### 3.4 `UsageService` 改动

新增 published：
```swift
@Published private(set) var accounts: [StoredAccount] = []
@Published private(set) var activeAccountId: UUID?
```

`init` 调整：用 `loadAccounts` 替换 `loadCredentials` 路径；`accounts` / `activeAccountId` 设；`isAuthenticated` 由 `accounts.isEmpty == false` 决定。

新增方法：
```swift
func switchAccount(to id: UUID) {
    guard let idx = accounts.firstIndex(where: { $0.id == id }), idx != currentActiveIndex() else { return }
    var file = StoredAccountsFile(version: 2, activeIndex: idx, accounts: accounts)
    file.accounts[idx].lastUsed = Date()
    do { try credentialsStore.saveAccounts(file) } catch {
        NSLog("[claude-usage-bar] switchAccount save failed: \(type(of: error))")
        return
    }
    self.accounts = file.accounts
    self.activeAccountId = file.accounts[idx].id
    // 清前账号瞬态状态
    self.usage = nil; self.lastError = nil; self.localCost30d = nil; self.accountEmail = nil
    // 重启 polling + 重新 fetch
    timer?.invalidate()
    Task { await fetchUsage(); await fetchProfile() }
    Task { await refreshLocalCostIfNeeded() }
    scheduleTimer()
}

func beginAddAccount() {
    // 触发 PKCE flow；保持 active 不变
    isAwaitingCode = true
    startSignInFlow()  // 原有 PKCE 入口
}

private func currentActiveIndex() -> Int {
    accounts.firstIndex(where: { $0.id == activeAccountId }) ?? 0
}
```

`completeSignIn` 路径调整：完成 token 拿到后，若 `accounts.isEmpty` 则建第一个 account；否则 append + activeIndex 切到新；调用 saveAccounts 而非 save(credentials)。

`saveCredentials` / `loadCredentials` 私有 helper 改为内部映射到 active account 的 credentials 字段。

### 3.5 `AccountSwitcherView.swift`

```swift
import SwiftUI

struct AccountSwitcherView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        if service.accounts.count > 1, let active = service.accounts.first(where: { $0.id == service.activeAccountId }) {
            Menu {
                ForEach(service.accounts) { account in
                    Button {
                        service.switchAccount(to: account.id)
                    } label: {
                        HStack {
                            Text(account.label)
                            if account.id == service.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("添加账号...") { service.beginAddAccount() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle")
                    Text(active.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
```

### 3.6 PopoverView 改动

在最顶部 `usageView` 之上插入：
```swift
AccountSwitcherView(service: service)
```
单账号时 view body 返回 EmptyView 等价物（条件由 view 内部判断），无需 PopoverView 加 if。

### 3.7 测试

`StoredAccountsFileTests`（≥4 case）：
- testCodableRoundTrip
- testActiveAccountClampsToValidIndex
- testActiveAccountReturnsNilForEmpty
- testCurrentVersionConstant

`StoredCredentialsStoreMigrationTests`（≥4 case）：
- testLoadAccountsPrefersV2File
- testMigrateFromV1CredentialsJSON（先写 v1 → loadAccounts → 验证 accounts.count==1 + label "账号 1" + credentials 字段一致 + credentials.json 已删）
- testMigrateFromLegacyTokenFile（先写 token plaintext → loadAccounts → 验证迁移）
- testAccountsJSONFilePermissionsAre0600（实测 stat）
- testMigrationSaveFailureKeepsOldFile（mock fileManager 抛错 → 旧文件保留）

`UsageServiceMultiAccountTests`（≥3 case）：
- testInitLoadsAccounts
- testSwitchAccountClearsTransientState（usage / lastError / localCost30d / accountEmail 清）
- testSwitchAccountInvalidIdNoop
- testActiveIndexOutOfBoundClampedToLast

合计 ≥11 case。

### 3.8 Implementation plan（G3 对象）

**Step P0** — spec + version + 索引（Commit A，仅文档）
- 升 v0.1.3 placeholder→planned；删 guardrail
- specs/README.md / versions/README.md 索引同步
- **Success**:
  - `grep -A1 '^status:' docs/versions/v0.1.3-*.md` 输出 `status: planned`
  - `python3 -c "import yaml; yaml.safe_load(open('docs/superpowers/specs/2026-05-11-multi-account.md').read().split('---')[1])"` 退出 0
  - `grep -c '^- \[' docs/superpowers/specs/2026-05-11-multi-account.md` ≥ 13
- **覆盖 SC**: 无

**Step P1** — store 数据模型 + 迁移 + UsageService 多账号字段 + 测试（Commit B）
- 新增 StoredAccount.swift（StoredAccount + StoredAccountsFile）
- 扩展 StoredCredentialsStore：accountsFileURL / loadAccounts / saveAccounts / deleteAccounts；fileManager/encoder/decoder 提升 internal
- UsageService 加 @Published accounts + activeAccountId；init 用 loadAccounts；switchAccount + beginAddAccount + currentActiveIndex；completeSignIn 路径分支（append vs first）；saveCredentials/loadCredentials 映射到 active
- 新增 StoredAccountsFileTests / StoredCredentialsStoreMigrationTests / UsageServiceMultiAccountTests（≥11 case）
- **Success**:
  - `swift build -c release && swift test` 全绿
  - `swift test 2>&1 | grep -E 'Executed (11[3-9]|1[2-9][0-9]) tests.*0 failures'` 命中（基线 103 + ≥11 = ≥114）
  - SC_AUTO_NO_REAL_TOKEN_PREFIX / SC_AUTO_NO_PRINT_TOKENS 守护无匹配
- **覆盖 SC**: SC1, SC2, SC3, SC4, SC5, SC7（前置）, SC8, SC10, SC12（前半）

**Step P2** — AccountSwitcherView + PopoverView 接入（Commit C）
- 新增 AccountSwitcherView.swift
- PopoverView 顶部插入 AccountSwitcherView(service: service)
- **Success**:
  - `swift build -c release && swift test` 全绿
  - `git diff --stat HEAD~1..HEAD` 仅触白名单：PopoverView.swift + AccountSwitcherView.swift（新文件）
  - 三守护仍无匹配
- **覆盖 SC**: SC6, SC9, SC11, SC12（后半）

**G5 gate** — 独立 reviewer code-review 加 security/privacy review focus
- (a) accounts.json 0600 权限
- (b) 迁移 fail-safe 不删旧文件
- (c) activeIndex 越界 clamp
- (d) switchAccount 清状态完整（usage / cost / email / error）
- (e) addAccount 不覆盖 active
- (f) UI 单账号时不显示 switcher
- (g) commit B/C 独立可 revert
- (h) NSLog 不 leak token / account.credentials

**Step P3 — G6 收尾**（Commit D）
- spec status accepted → implemented；reviews append G5 + G6
- Verification log 全 [x]；索引同步；CHANGELOG entry；version → in-progress
- **Success**：
  - `grep -c '^  - gate:' docs/superpowers/specs/2026-05-11-multi-account.md` 输出 4
  - `grep -c '^## \[v0.1.3\]' CHANGELOG.md` 输出 1
- **覆盖 SC**: SC13

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🆕 | `macos/Sources/ClaudeUsageBar/StoredAccount.swift` | 数据模型 |
| 🆕 | `macos/Sources/ClaudeUsageBar/AccountSwitcherView.swift` | popover 切换器 |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/StoredAccountsFileTests.swift` | ≥4 case |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/StoredCredentialsStoreMigrationTests.swift` | ≥4 case |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/UsageServiceMultiAccountTests.swift` | ≥3 case |
| 🔧 | `macos/Sources/ClaudeUsageBar/StoredCredentials.swift` | 加 extension：accountsFileURL / loadAccounts / saveAccounts / deleteAccounts；提升 fileManager/encoder/decoder 为 internal |
| 🔧 | `macos/Sources/ClaudeUsageBar/UsageService.swift` | 加 @Published accounts + activeAccountId；switchAccount / beginAddAccount；init 用 loadAccounts；completeSignIn 分支 |
| 🔧 | `macos/Sources/ClaudeUsageBar/PopoverView.swift` | 顶部插入 AccountSwitcherView |
| 🔧 | `docs/versions/v0.1.3-multi-account.md` / 索引 / CHANGELOG | 标准收尾 |
| ✅ 不动 | OAuth PKCE / refresh / SetupView / CodeEntry / Settings / Notifications / Strategy(v0.1.1) / LocalCost(v0.1.2) / hero/menubar/pace/trend | 仅 store 加 accounts API + UsageService 多账号字段 + popover 顶部加 switcher |

## 5. 风险 / Open questions

1. **迁移失败**：accounts.json 写盘失败 → 保留 credentials.json 不删；下次启动重试。**对策**：fail-safe 已 spec；NSLog 仅 type 不 leak。
2. **activeIndex 持久化竞态**：多 .app 实例（用户同时开多个）写 accounts.json 互覆盖。**对策**：macOS 单实例 LSUIElement；不并发。可加 fcntl flock 但 YAGNI。
3. **同账号重复添加**：用户对同一 Claude account 走两次 PKCE → accounts 列表出现两个相同 token。**对策**：fetchProfile 后用 email 去重？**留 v0.2.x**（用户体验问题，不是数据正确性）。
4. **per-account history 不隔离**：切换账号 history 仍显示前账号。**已知**：v0.1.4 留位；切换提示文案"⚠️ History 显示所有账号合并"——本 spec 不加（避免 UX 噪音）。
5. **per-account cost scan 不分账**：v0.1.2 LocalCostScanner 扫所有 JSONL，不区分 account。**已知**：CLI JSONL 也无 account 标识；技术上无法分账。
6. **Keychain bootstrap 仅读单 account**：v0.1.1 ClaudeCLICredentialsStrategy 读 Keychain `Claude Code-credentials` 单条；不支持多 account 自动 bootstrap。**接受**：Claude CLI 本身单账号；用户多账号场景手动添加即可。
7. **删除账号 / 重命名账号**：本 spec 不做 UI；用户需手动编辑 accounts.json。**v0.2.x Settings 增量**。
8. **a11y**：Menu 默认有 keyboard 支持；label 用中文 OK。
9. **token 不在 label 暴露**：StoredAccount.label 仅 "账号 N" 或 email；UI 渲染只读 label。
10. **完成 sign in 后 active 切换时机**：用户 add 第二个账号完成 PKCE 时立即切到新；与系统 menu add option 一致。

## 6. 后续工作（不在本 spec 范围）

- per-account history 隔离 → v0.1.4
- Settings 账号管理（删除 / 重命名 / 重新 sign in） → v0.2.x
- Merge icons / stacked cards 同时显示多账号 → v0.2.x
- 同账号去重（fetchProfile email 比对） → v0.2.x
- Keychain multi-account bootstrap → v0.2.x（依赖 Claude CLI 本身支持）

## 7. 引用

- 调研：[`docs/research/competitive-analysis.md`](../../research/competitive-analysis.md) §2.5 / §5.2 Step D
- 母法：[`2026-05-11-docs-governance.md`](./2026-05-11-docs-governance.md)
- 前置 spec：[`2026-05-11-claude-cli-credentials.md`](./2026-05-11-claude-cli-credentials.md)（SC7 事故警示）
- 落地版本：[`docs/versions/v0.1.3-multi-account.md`](../../versions/v0.1.3-multi-account.md)

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [ ] SC1 — evidence: TBD
- [ ] SC2 — evidence: TBD
- [ ] SC3 — evidence: TBD
- [ ] SC4 — evidence: TBD
- [ ] SC5 — evidence: TBD
- [ ] SC6 — evidence: TBD
- [ ] SC7 — evidence: TBD
- [ ] SC8 — evidence: TBD
- [ ] SC9 — evidence: TBD
- [ ] SC10 — evidence: TBD
- [ ] SC11 — evidence: TBD
- [ ] SC12 — evidence: TBD
- [ ] SC13 — evidence: TBD
