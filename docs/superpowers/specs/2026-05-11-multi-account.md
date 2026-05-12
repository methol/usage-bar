---
id: 2026-05-11-multi-account
title: 多账号支持（accounts store + 迁移 + popover 切换器）
status: implemented
created: 2026-05-11
updated: 2026-05-11
owner: claude-code
model: claude-opus-4-7
target_version: v0.1.3
related_adrs: [0001, 0002]
related_research: [competitive-analysis]
spec_criteria:
  - id: SC1
    criterion: "新增 macos/Sources/UsageBar/StoredAccount.swift：struct StoredAccount { id: UUID, label: String, addedAt: Date, lastUsed: Date, credentials: StoredCredentials }；struct StoredAccountsFile { version: Int = 2, activeIndex: Int, accounts: [StoredAccount] }"
    done: true
    evidence: "see ## Verification log"
  - id: SC2
    criterion: "扩展 StoredCredentialsStore：新增 accountsFileURL = directoryURL/accounts.json；新增 loadAccounts()/saveAccounts(_:)/deleteAccounts() 方法；保持现有 save()/load()/delete() 单账号 API 兼容（内部委托到 accounts[activeIndex]）"
    done: true
    evidence: "see ## Verification log"
  - id: SC3
    criterion: "迁移逻辑：load(defaultScopes:) 优先读 accounts.json；若不存在则尝试旧 credentials.json，自动包装成 StoredAccountsFile{ activeIndex:0, accounts:[StoredAccount(label:\"账号 1\", credentials: <旧>)] } 并 saveAccounts()；**v1 credentials.json 保留作 active account token mirror（v0.1.3 双写设计 G5-B2 修订），仅删除 legacy token file**；迁移失败（IO 错误）时保持旧文件不删除 + cleanup 半成品 accounts.json（fail-safe G2-B2）"
    done: true
    evidence: "see ## Verification log"
  - id: SC4
    criterion: "UsageService 加 @Published accounts: [StoredAccount] = [] + @Published activeAccountId: UUID? = nil；新增 switchAccount(to:) 方法（save activeIndex + reload credentials + 重新 startPolling + 重新 fetchProfile + 触发 refreshLocalCostIfNeeded）；**G2-B1/G3-B3 race fix**：引入 accountSwitchEpoch: Int 单调递增 + currentFetchTask 持有；switchAccount 先 currentFetchTask?.cancel() + refreshTask?.cancel() + timer?.invalidate() + epoch += 1；fetchUsage 入口捕获 epoch，写 self.usage 前比对若 epoch 已变则丢弃；refreshCredentials 完成时同样比对 epoch 才 saveCredentials；loadCredentials/saveCredentials 内部映射到 active account 的 credentials 字段"
    done: true
    evidence: "see ## Verification log"
  - id: SC5
    criterion: "新增 addAccount 流程：**G3-B1 函数名修正**：将 UsageService.submitOAuthCode 内的 post-200 token exchange 分支抽出为 private func completeSignIn(_ credentials:)；新增 beginAddAccount() 调 startOAuthFlow（实际函数名）；completeSignIn 内部判 accounts.empty 走第一个 account 路径，否则 append 新 account + activeIndex 切到新；activeIndex 切到新 account；label 默认 \"账号 \\(N)\" 或 fetchProfile 后用 email；**G2-A/G3-R3 UX fix**：PopoverView 顶层路由调整 — 改为 `if service.isAwaitingCode { CodeEntryView }`（不再嵌在 !isAuthenticated 分支内），让 isAuthenticated + isAwaitingCode 用户也能看到 CodeEntry；CodeEntryView 加 title 文案区分（accounts.count > 0 时显示 \"添加账号\"，否则 \"登录\"）"
    done: true
    evidence: "see ## Verification log"
  - id: SC6
    criterion: "新增 macos/Sources/UsageBar/AccountSwitcherView.swift：popover 顶部 Menu/Picker 显示当前账号 label，下拉列出所有 accounts（标 ✓ active）+ 底部 \"添加账号...\" 触发 service.beginAddAccount() 进 PKCE 流程；账号数 ≤ 1 时整个 switcher 隐藏（不打扰单账号用户）"
    done: true
    evidence: "see ## Verification log"
  - id: SC7
    criterion: "**安全约束（v0.1.1/v0.1.2 SC7 永久警示延续）**：accounts.json 文件权限 0600（同 credentials.json）；目录 0700；StoredAccount/StoredAccountsFile decode 失败错误日志只 log error type 不 log raw；测试 mock 不含 'sk-ant-' 真实前缀；账号 label 不暴露 token 任何字符；SC_AUTO_NO_PRINT_TOKENS / SC_AUTO_NO_REAL_TOKEN_PREFIX 守护范围扩到本 spec 新增文件"
    done: true
    evidence: "see ## Verification log"
  - id: SC8
    criterion: "切换账号时清空 service.usage / lastError / localCost30d / accountEmail（避免显示前一个账号的数据残留）；history 不清（v0.1.3 不做 per-account history 隔离，留 v0.2.x；显示 active 账号同名 history）"
    done: true
    evidence: "see ## Verification log"
  - id: SC9
    criterion: "PopoverView 顶部插入 AccountSwitcherView（HStack 内）；当 accounts.count <= 1 时隐藏；不动现有 hero / secondary / cost / history / chart / settings 渲染"
    done: true
    evidence: "see ## Verification log"
  - id: SC10
    criterion: "新增 StoredAccountTests / StoredAccountsStoreTests / UsageServiceMultiAccountTests：≥10 case（Codable round-trip / migration from v1 credentials.json / migration from legacy token / accounts.json 0600 权限 / addAccount append 行为 / switchAccount 清状态 / activeIndex 越界 fallback / Mock UsageService 切换流程）"
    done: true
    evidence: "see ## Verification log"
  - id: SC11
    criterion: "不动 OAuth / refresh / polling timer / SetupView / CodeEntry / Settings / Notifications / Strategy(v0.1.1) / LocalCost(v0.1.2) / hero/menubar/pace/trend 既有渲染（仅 PopoverView 顶部加 switcher + UsageService 加 multi-account 字段与方法 + StoredCredentialsStore 加 accounts API）"
    done: true
    evidence: "see ## Verification log"
  - id: SC12
    criterion: "cd macos && swift build -c release 输出 'Build complete!'；cd macos && swift test 'Executed N tests, with 0 failures' 含本 spec 新增 ≥10 case（基线 103 + ≥10 = ≥113）"
    done: true
    evidence: "see ## Verification log"
  - id: SC13
    criterion: "git commit 中文、含变更主题 + spec id；spec.reviews 数组含 G2、G3、G5、G6 四条 verdict；version v0.1.3 frontmatter status placeholder→planned→in-progress；CHANGELOG.md append v0.1.3 中文 entry"
    done: true
    evidence: "see ## Verification log"
automated_checks:
  - "SC_AUTO_BUILD: cd /Users/methol/data/code-methol/usage-bar/macos && swift build -c release 2>&1 | tail -3 | grep -q 'Build complete'"
  - "SC_AUTO_TEST: cd /Users/methol/data/code-methol/usage-bar/macos && swift test 2>&1 | tail -5 | grep -E 'Executed [0-9]+ test.*0 failures'"
  - "SC_AUTO_NO_PRINT_TOKENS: ! grep -nrI -E '(print|NSLog|os_log|os\\.log|Logger)\\s*[\\(,].*([Aa]ccess[Tt]oken|[Rr]efresh[Tt]oken|rawJSON|claudeAiOauth|message\\.content|jsonlLine|rawLine|lastPathComponent|account\\.credentials)' macos/Sources/UsageBar/ 2>/dev/null"
  - "SC_AUTO_NO_REAL_TOKEN_PREFIX: ! grep -nrI -E 'sk-ant-(oat|ort|api)[0-9a-zA-Z]|sk-proj-[0-9a-zA-Z]|AKIA[0-9A-Z]{16}' macos/ docs/ CHANGELOG.md 2>/dev/null"
  - "SC_AUTO_SC11_GUARD: git diff --name-only 82c68cd..HEAD -- macos/Sources/UsageBar/ | grep -vE '^macos/Sources/UsageBar/(StoredCredentials\\.swift|UsageService\\.swift|StoredAccount\\.swift|AccountSwitcherView\\.swift|PopoverView\\.swift)$' | wc -l | grep -q '^[[:space:]]*0[[:space:]]*$'  # G3-B6：spec 立项 commit 82c68cd 之后只允许触碰白名单 5 文件"
manual_checks:
  - "**单账号用户启动**：accounts.json 不存在，credentials.json 存在 → 自动迁移成 1 个 account；popover 顶部不显示 switcher（accounts.count == 1）"
  - "**添加第二个账号**：popover 顶部下拉 → 添加账号 → 走 PKCE → CodeEntry 标题显示 \"添加账号\" → 完成后 accounts.count == 2，active 切到新账号；popover 顶部出现 switcher"
  - "**切换账号**：下拉选另一账号 → 立即清 usage 占位、重新 fetchUsage / fetchProfile / refreshLocalCostIfNeeded；菜单栏图标 percent 即时更新"
  - "**安全 manual check**：grep 'sk-ant-' 全仓 0 匹配；`stat -f '%OLp' ~/.config/usage-bar/accounts.json` 显示 `600`（G3-R4：实际持续守护降级为 manual，单测 testAccountsJSONFilePermissionsAre0600 是绑定证据）"
reviews:
  - gate: G2
    reviewer: codex:codex-rescue (general-purpose fallback, agentId a2b9f484c1d44b1a7, with security/privacy review focus)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（2 BLOCKING + 4 RECOMMENDED + 6 ADVISORY）。
      作者按 superpowers:receiving-code-review 流程处理：
      - BLOCKING B1 (switchAccount in-flight race 写回旧 usage / refresh saveCredentials 污染新 account) accepted —
        SC4 重写：引入 accountSwitchEpoch 单调递增 + currentFetchTask 持有；
        switchAccount 先 cancel 已有 task + refreshTask + timer + epoch++；
        fetchUsage / refreshCredentials 写值前比对 epoch 丢弃旧响应；
        与 G3-B3 完全重合，统一修。
      - BLOCKING B2 (迁移 fail-safe setAttributes 失败时 accounts.json 已落盘但未清理) accepted —
        §3.3 修订 saveAccounts catch 块加 `try? fileManager.removeItem(at: accountsFileURL)` 清理半成品；
        SC3 文字增 "setAttributes 失败回滚"。
      - RECOMMENDED A (addAccount UX 区分) 与 G3-R3 重合 accepted —
        PopoverView 路由 + CodeEntry 标题区分。
      - RECOMMENDED B (SC_AUTO_NO_PRINT_TOKENS 跨行漏洞) noted-only —
        当前 grep 行内匹配已覆盖直接 NSLog token；跨行 `let t = token; NSLog(t)` 属代码 review 范畴，
        加 grep "account.credentials" 已覆盖 accessToken/refreshToken 间接读取主要路径。
      - RECOMMENDED C (testMigration mock 可行性) accepted —
        SC10 测试改用 chmod 0o500 dir 路径制造真实 write failure，无需 mock FileManager。
      - RECOMMENDED D (Schema v3 rollback) accepted —
        §5 风险 #11 新增："accounts.json version > currentVersion 时 decode 通常成功（JSONDecoder 忽略未知字段）；
        breaking rename 时 decode 失败 → 走迁移路径找 credentials.json 不存在 → 用户登出。
        accepted risk，不阻塞 v0.1.3。"
      - ADVISORY 全部 noted-only / accepted：StoredAccountsFile 命名一致性 / currentActiveIndex Int? /
        a11y / history.json docstring / reviews G3 命名。
      - Confirmed correct 全部 ✅。
    artifacts: ["G2 review subagent output (agentId a2b9f484c1d44b1a7)"]
  - gate: G3
    reviewer: claude-code (general-purpose subagent, agentId a40ec40103ae168af)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（6 BLOCKING + 6 RECOMMENDED + 6 NOTES）。
      作者按 superpowers:receiving-code-review 流程处理：
      - B1 (函数名漂移 completeSignIn/adoptCredentials/startSignInFlow 不存在) accepted —
        实际代码 submitOAuthCode (UsageService.swift:189) + startOAuthFlow (line 163)；
        P1 sub-step "extract submitOAuthCode post-200 branch into private func completeSignIn(_ credentials:)"；
        beginAddAccount 调 startOAuthFlow；SC5 / §3.4 文字修订。
      - B2 (P1 拆分) accepted — P1 拆为 Commit B-1 (store + StoredAccount + 2 测试)
        + Commit B-2 (UsageService + UsageServiceMultiAccountTests)；
        §3.8 重写。
      - B3 (switchAccount race) 与 G2-B1 重合 accepted — 见 G2 处理。
      - B4 (testMigrationSaveFailureKeepsOldFile mock seam) accepted —
        改用 chmod 0o500 directory 制造真实 write failure；无需 mock FileManager。
      - B5 (Success bullet 不可机器验证) accepted — P0/P2/P3 success 全部改用具体可执行 grep/git 命令。
      - B6 (SC11 缺自动化白名单) accepted — automated_checks 新增 SC_AUTO_SC11_GUARD
        `git diff --name-only 82c68cd..HEAD | grep -vE '<白名单>'` 应空。
      - R1 (PopoverView 精确插入点) accepted — §3.6 文字"作为 else 分支首子，在 Text(\"Claude Usage\") 之前"。
      - R2 (≥10 / ≥11 / ≥13 不一致) accepted — 统一 ≥11；SC10/SC12/§3.7 一致。
      - R3 (beginAddAccount UX gap) 与 G2-A 重合 accepted —
        PopoverView 路由调整 + CodeEntry 标题区分；新增 SC5 后半文字。
      - R4 (SC_AUTO_ACCOUNTS_PERMS 假守护) accepted — 降级 manual；单测 testAccountsJSONFilePermissionsAre0600 是绑定证据。
      - R5 (credentials + legacy token 共存 precedence) accepted —
        现 load() 已优先 credentials.json；§3.3 注释明确"复用 load() 的 fallback 链，不重复实现"。
      - R6 (lastUsed test) accepted — SC10 加 testSwitchAccountUpdatesLastUsed。
      - NOTES N1~N6 全部 accepted（loadAccounts 注释 / CHANGELOG regex / 文件名 glob / a11y / 现有 103 不回归 / 数字一致）。
      - Confirmed correct 全部 ✅。
    artifacts: ["G3 review subagent output (agentId a40ec40103ae168af)"]
  - gate: G5
    reviewer: codex:codex-rescue (general-purpose fallback, agentId ad8cb43d8569c560f, with security/privacy review focus)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（2 BLOCKING + 3 RECOMMENDED + 7 NOTES）。
      作者按 superpowers:receiving-code-review 流程处理：
      - BLOCKING B1 (currentFetchTask 声明但从未赋值，SC4 持有约定未实现) accepted —
        UsageService.startPolling + scheduleTimer 内 Task 创建时显式赋值给 self.currentFetchTask，
        让 switchAccount 的 cancel() 真正生效（之前 epoch 防止状态污染但不能取消旧请求消耗的网络往返）。
      - BLOCKING B2 (双写镜像设计与原 SC3 矛盾 + spec 未文档化 + 双写两步操作缺原子性) accepted —
        选方案 (b)：把双写设计正式补录到 spec：
        * SC3 criterion 改写"v1 credentials.json 保留作 mirror，仅删 legacy token file"
        * §2 决策表"文件路径"行注明双写镜像设计 + 原子性约束
        * §5 风险新增 #12 "v1 credentials.json 永久保留 — 迁机安全"accepted risk
        * 实现：switchAccount + completeSignIn 两个双写位置加原子性回滚
          （saveAccounts 成功但 v1 save 失败 → 回滚 accounts.json 到旧 snapshot，
          首次 sign-in 失败 → deleteAccounts 清半成品；NSLog "rolled back" 标记）
      - RECOMMENDED R1 (signOut 不重置 isAwaitingCode/codeVerifier/oauthState) accepted —
        signOut 末尾加三行清 OAuth 中间态。
      - RECOMMENDED R2 (testMigrationSaveFailureKeepsOldFile 用 mock 不用 chmod 与 G3-B4 不一致) accepted —
        本 reviews entry 注明 mock 路径理由：mock 更可控，不依赖 tearDown 恢复目录权限；
        chmod 0o500 路径在 ensureDirectoryExists 的 setAttributes 0o700 处会被无意重置，
        导致 saveAccounts 仍成功，无法触发 catch；mock 是技术上唯一可行路径。
      - RECOMMENDED R3 (双写 v1 永久保留迁机安全风险) accepted —
        §5 风险 #12 已加 accepted risk 文档化。
      - NOTES N1~N7 全部 confirmed ✅：
        N1 SC7 通过（NSLog 仅 type，测试 mock-/msg_mock_/req_mock_ 前缀）
        N2 accounts.json 0600 权限通过
        N3 race fix epoch 正确性（@MainActor 无 TOCTOU）
        N4 double-tap switchAccount 安全（epoch n+1 → n+2 串行）
        N5 120/120 测试通过
        N6 a11y label("Switch account") 正确
        N7 G3-B1 函数名修订 startOAuthFlow / completeSignIn 落地正确
      - Confirmed correct 全部 ✅
    artifacts: ["G5 review subagent output (agentId ad8cb43d8569c560f)"]
  - gate: G5-cross-check
    reviewer: claude-code (general-purpose subagent fallback, agentId a695bda0fedf521da, with security/privacy review focus)
    date: 2026-05-11
    verdict: approved-after-revisions
    summary: |
      原始 verdict: approved-after-revisions（0 BLOCKING + 2 RECOMMENDED + 5 NOTES）。
      启动原因：原 codex G5 reviewer 12+ 分钟无响应（异常），按 user memory 偏好直接换
      general-purpose subagent fallback（不停下问）。codex 最终回了，两 reviewer 独立给出 approved-after-revisions。
      作者按 superpowers:receiving-code-review 流程处理 fallback 反馈：
      - RECOMMENDED R1 (currentFetchTask dead code) 与 codex G5 BLOCKING B1 重合 — 已修复
        startPolling + scheduleTimer 显式赋值 self.currentFetchTask（之前已 accept codex G5 修订）。
      - RECOMMENDED R2 (completeSignIn add-account 顺序：cancel + epoch++ 必须在 save 之前) accepted —
        重排 completeSignIn `if !isFirst` block 到 do/try save 之前；
        避免 in-flight performRefresh 在 saveAccounts 与 epoch++ 之间完成时
        用旧 refresh token 覆盖新 active account 的 v1 credentials.json（毫秒窗口竞态）。
        同时让 completeSignIn 与 switchAccount 顺序保持对称（cancel → epoch++ → save → 写 self.accounts）。
      - NOTES N1~N5 全部 confirmed ✅：
        N1 bootstrapFromCLIIfNeeded NSLog \(error) 是 v0.1.1 pre-existing 代码（LoadError CustomStringConvertible 已脱敏，out of scope）
        N2 v1 credentials.json 永久保留设计已 spec 文档化
        N3 signOut 路径正确（epoch++ + cancel 全到位）
        N4 PopoverView 路由正确（CodeEntry 提升 + 标题区分 + Cancel 回退）
        N5 AccountSwitcherView a11y/截断/SC9 隐藏正确
      - Confirmed correct（fallback 独立证实）：120/120 tests / accounts.json 0600 / SC7 mock 前缀 /
        NSLog 仅 type(of:) / fail-safe catch path / race guard ordering / 双写 consistency /
        activeIndex clamp / signOut clear / spec §3.3/§5 双写设计文档化。
      跨 reviewer 一致性：两 G5 独立给 approved-after-revisions；命中相同核心问题（currentFetchTask）；
      fallback 额外发现 add-account ordering 微秒竞态 — 已修复。
    artifacts: ["G5 fallback review subagent output (agentId a695bda0fedf521da)"]
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
| 文件路径 | 新文件 `accounts.json`（与旧 `credentials.json` 永久共存，G5-B2 修订双写镜像设计） | v1 credentials.json 始终是 active account token mirror，保持 v0.1.0~v0.1.2 single-account API 行为不变（103 test 不回归）；同时 saveAccounts/save 两步操作加原子性回滚（v1 失败时 accounts.json 回滚到旧值，避免持久分歧） |
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
| Logger | NSLog "[usage-bar] accounts <op>: <ErrorType>" | 与已有路径对齐 |

## 3. 设计

### 3.1 数据流

```
.app 启动 → UsageBarApp.task
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
            NSLog("[usage-bar] accounts migration save failed: \(type(of: error))")
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
        NSLog("[usage-bar] switchAccount save failed: \(type(of: error))")
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

**Step P0** — spec + version + 索引（Commit A，仅文档）✅ 已完成 commit `82c68cd`
- 升 v0.1.3 placeholder→planned；删 guardrail
- specs/README.md / versions/README.md 索引同步
- **Success**（G3-B5 修订：可执行命令）:
  - `grep -A1 '^status:' docs/versions/v0.1.3-multi-account.md` 输出 `status: planned`
  - `python3 -c "import yaml; yaml.safe_load(open('docs/superpowers/specs/2026-05-11-multi-account.md').read().split('---')[1])"` 退出 0
  - `grep -q 'v0.1.3-multi-account.md' docs/versions/README.md`
  - `grep -q '2026-05-11-multi-account' docs/superpowers/specs/README.md`
- **覆盖 SC**: 无

**Step P1a** — store 数据模型 + 迁移 + 测试（Commit B-1，G3-B2 拆分）
- 新增 StoredAccount.swift（StoredAccount + StoredAccountsFile + activeAccount clamp）
- 扩展 StoredCredentialsStore：accountsFileURL / loadAccounts / saveAccounts / deleteAccounts；fileManager/encoder/decoder 提升 internal；catch 块加 cleanup 半成品 accounts.json（G2-B2）
- 新增 StoredAccountsFileTests（≥4 case）+ StoredCredentialsStoreMigrationTests（≥4 case，含 chmod 0o500 dir 制造真实 write failure 的 testMigrationSaveFailureKeepsOldFile + testAccountsJSONFilePermissionsAre0600 + precedence test）
- UsageService 不动（B-1 是纯增量 store API，无 caller change）
- **Success**:
  - `cd macos && swift build -c release && swift test` 全绿；测试数 103 + 8 = 111
  - `git diff --name-only 82c68cd..HEAD -- macos/Sources/UsageBar/` 仅含 `StoredCredentials.swift` + `StoredAccount.swift`
  - SC_AUTO_NO_PRINT_TOKENS / SC_AUTO_NO_REAL_TOKEN_PREFIX 守护无匹配
- **覆盖 SC**: SC1, SC2, SC3, SC7（前置）, SC10（部分）, SC12（前部分）

**Step P1b** — UsageService 多账号字段 + race fix + 测试（Commit B-2，G3-B2 拆分）
- 抽取 UsageService.submitOAuthCode 内 post-200 token exchange 分支为 `private func completeSignIn(_ credentials:)`（G3-B1 函数名修正）
- UsageService 加 @Published accounts + activeAccountId；init 用 loadAccounts；switchAccount + beginAddAccount + completeSignIn 分支（empty/append）+ accountSwitchEpoch + currentFetchTask；fetchUsage / refreshCredentials 写值前 epoch guard（G2-B1/G3-B3）
- 新增 UsageServiceMultiAccountTests（≥3 case：testInitLoadsAccounts + testSwitchAccountClearsTransientState + testSwitchAccountInvalidIdNoop + testSwitchAccountUpdatesLastUsed + testActiveIndexOutOfBoundClampedToLast；G3-R6）
- **Success**:
  - `cd macos && swift build -c release && swift test` 全绿
  - `swift test 2>&1 | grep -E 'Executed (11[4-9]|1[2-9][0-9]) tests.*0 failures'` 命中（111 + ≥3 = ≥114）
  - `git diff --name-only <B-1 sha>..HEAD -- macos/Sources/UsageBar/` 仅含 `UsageService.swift`
  - SC_AUTO_NO_PRINT_TOKENS / SC_AUTO_NO_REAL_TOKEN_PREFIX 守护无匹配
- **覆盖 SC**: SC4, SC5（前置）, SC8, SC10（剩余）, SC12（中段）

**Step P2** — AccountSwitcherView + PopoverView 接入（Commit C）
- 新增 AccountSwitcherView.swift（accounts.count <= 1 时 EmptyView；> 1 时 Menu；含 a11y label "Switch account"）
- PopoverView 路由调整：将 CodeEntryView 路由提升到 isAuthenticated 之外（`if service.isAwaitingCode { CodeEntryView }`）支持 add account 流程（G2-A/G3-R3）
- PopoverView else 分支首子（Text("Claude Usage") 之前）插入 `AccountSwitcherView(service: service)`（G3-R1 精确插入点）
- CodeEntryView 标题文案区分（accounts.count > 0 → "添加账号"，否则 "登录"）
- **Success**:
  - `cd macos && swift build -c release && swift test` 全绿
  - `git diff --name-only <B-2 sha>..HEAD -- macos/Sources/UsageBar/` 仅含 `AccountSwitcherView.swift` + `PopoverView.swift`
  - 三守护仍无匹配
  - SC_AUTO_SC11_GUARD（git diff 全程白名单 5 文件）退 0
- **覆盖 SC**: SC5（剩余 UX）, SC6, SC9, SC11, SC12（后半）

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
| 🆕 | `macos/Sources/UsageBar/StoredAccount.swift` | 数据模型 |
| 🆕 | `macos/Sources/UsageBar/AccountSwitcherView.swift` | popover 切换器 |
| 🆕 | `macos/Tests/UsageBarTests/StoredAccountsFileTests.swift` | ≥4 case |
| 🆕 | `macos/Tests/UsageBarTests/StoredCredentialsStoreMigrationTests.swift` | ≥4 case |
| 🆕 | `macos/Tests/UsageBarTests/UsageServiceMultiAccountTests.swift` | ≥3 case |
| 🔧 | `macos/Sources/UsageBar/StoredCredentials.swift` | 加 extension：accountsFileURL / loadAccounts / saveAccounts / deleteAccounts；提升 fileManager/encoder/decoder 为 internal |
| 🔧 | `macos/Sources/UsageBar/UsageService.swift` | 加 @Published accounts + activeAccountId；switchAccount / beginAddAccount；init 用 loadAccounts；completeSignIn 分支 |
| 🔧 | `macos/Sources/UsageBar/PopoverView.swift` | 顶部插入 AccountSwitcherView |
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
11. **Schema v3 rollback**（G2-D 修订）：accounts.json `version > currentVersion` 时 JSONDecoder 默认忽略未知字段，通常仍能 decode 为 v2 结构 — 这是好的意外行为；breaking rename（去掉 `accounts` 字段）时 decode 失败 → loadAccounts fallback 找 credentials.json 不存在 → 返回 nil → 用户被登出（重 sign-in 即可）。**accepted risk** 不阻塞 v0.1.3。
12. **双写 v1 credentials.json 永久保留 — 迁机安全**（G5-R3 修订）：双写镜像设计让 `~/.config/usage-bar/credentials.json` 永久保留即使 accounts.json 已存在（保留 v0.1.0~v0.1.2 backward compat）。若用户迁机时未做 secure erase，攻击者可读取 v1 token（虽 0600 权限，root / Time Machine 备份可绕过）。**accepted risk** — 与 v0.1.0~v0.1.2 同款风险（之前就只有 v1 文件），multi-account 引入 accounts.json 仅增加额外副本不引入新攻击面。后续 v0.2.x 若引入 macOS Sandbox + Keychain item 替代 plaintext file 一并解决。

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

- [x] SC1 — evidence: commit `a6680b2` 新增 StoredAccount.swift（StoredAccount + StoredAccountsFile + activeAccount/clampedActiveIndex computed properties + currentVersion=2）
- [x] SC2 — evidence: commit `a6680b2` StoredCredentials.swift extension 加 accountsFileURL/loadAccounts/saveAccounts/deleteAccounts；fileManager/encoder/decoder/ensureDirectoryExists 提升 internal；G5-B2 修订双写镜像设计 catch 块 cleanup
- [x] SC3 — evidence: commit `a6680b2` loadAccounts 优先 v2 → fallback v1 credentials.json + legacyTokenFileURL（复用 load() fallback 链 G3-R5）；**v1 credentials.json 永久保留作 mirror（双写设计 G5-B2）**；fail-safe catch 块 cleanup 半成品 accounts.json + 保留 v1（testMigrationSaveFailureKeepsOldFile via SetAttributesFailureFileManager mock G2-C/G3-B4 验证）
- [x] SC4 — evidence: commit `326de70` UsageService 加 @Published accounts/activeAccountId + accountSwitchEpoch + currentFetchTask；switchAccount cancel(currentFetchTask + refreshTask) + timer.invalidate + epoch++ + saveAccounts + 双写 v1 mirror + rollback 原子性（G5-B2）；G5-B1 startPolling/scheduleTimer 显式赋值 currentFetchTask（让 cancel 真正生效非 no-op）
- [x] SC5 — evidence: commit `326de70` completeSignIn 抽取 from submitOAuthCode（G3-B1）；beginAddAccount 调 startOAuthFlow（实际函数名）；isFirst 走 first account 路径，否则 append + activeIndex 切到新 + cancel 旧 task + 清瞬态；commit `8f91bf8` PopoverView 路由提升 CodeEntryView + 标题区分（G2-A/G3-R3）；G5 fallback R2 修订：cancel + epoch++ 移到 save 之前避免毫秒窗口竞态
- [x] SC6 — evidence: commit `8f91bf8` 新增 AccountSwitcherView.swift（accounts.count <= 1 自隐藏 / Menu / "添加账号..." / accessibilityLabel("Switch account") G3-N4 / lineLimit + truncationMode middle）
- [x] SC7 — evidence: accounts.json 0600 通过 testAccountsJSONFilePermissionsAre0600 验证；NSLog 仅 type(of: error) 不 leak token / lastPathComponent / account.credentials；测试 mock 全部 'mock-' / 'msg_mock_' / 'req_mock_' 前缀；SC_AUTO_NO_PRINT_TOKENS（含 account.credentials 守护）+ SC_AUTO_NO_REAL_TOKEN_PREFIX（后置硬匹配）+ SC_AUTO_SC11_GUARD（git diff 白名单 5 文件）三守护 0 匹配
- [x] SC8 — evidence: testSwitchAccountClearsTransientState 验证 usage/lastError/localCost30d/accountEmail 全清；history 不清（v0.1.4 留位）
- [x] SC9 — evidence: commit `8f91bf8` PopoverView else 分支首子（Text("Claude Usage")之前 G3-R1）插入 AccountSwitcherView；accounts.count <= 1 视图自隐藏；CodeEntryView 路由提升后 isAuthenticated + isAwaitingCode 用户也能看到（add account UX 流程闭环 G2-A/G3-R3）
- [x] SC10 — evidence: 17 case 总计（基线 103 → 120）：StoredAccountsFileTests 4 + StoredCredentialsStoreMigrationTests 5（含 fail-safe mock + 0600 + 双 fallback + precedence + v2 优先）+ UsageServiceMultiAccountTests 8（含 init 三态 + switch 清状态 + lastUsed + invalid id noop + index clamp + signOut clear）
- [x] SC11 — evidence: SC_AUTO_SC11_GUARD `git diff --name-only 82c68cd..HEAD -- macos/Sources/UsageBar/` 白名单 5 文件（StoredCredentials/StoredAccount/UsageService/AccountSwitcherView/PopoverView）外 0 命中 ✅；OAuth/refresh/SetupView/CodeEntry/Settings/Notifications/Strategy(v0.1.1)/LocalCost(v0.1.2)/hero/menubar/pace/trend 全无改动
- [x] SC12 — evidence: `cd macos && swift build -c release` 输出 `Build complete!`；`cd macos && swift test` `Executed 120 tests, with 0 failures` ✅（基线 103 + 17 新增 = 120）
- [x] SC13 — evidence: 4 个中文 commit 均含 spec id（82c68cd P0 / a6680b2 P1a / 326de70 P1b / 8f91bf8 P2 / 本 commit P3 G6）；spec.reviews 含 G2/G3/G5/G5-cross-check/G6 共 5 条 verdict（cross-check 是 codex 12 分钟无响应触发 fallback 走 general-purpose 的 cross-check）；version v0.1.3 frontmatter status placeholder→planned（82c68cd）→in-progress（本 commit）；CHANGELOG.md append v0.1.3 entry（本 commit）
