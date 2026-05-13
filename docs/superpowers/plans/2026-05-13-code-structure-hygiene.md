# 代码结构治理 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `macos/Sources/UsageBar/` 平铺的 55 个 swift 文件治成 9 个职责子目录、把 Claude 的 `UsageService.swift` 移进 `Providers/Claude/` 并同文件章节化、删 `macos/Resources/demo.png` 死资源、把 `AppResources.swift` 改名 `BundleLocator.swift`、更新白名单文档 path 引用。

**Architecture:** 纯结构治理，**0 行业务代码语义改动**。每个 SC 切独立 commit；每个 commit 跑 `swift build -c release` + `swift test`。SC4（UsageService 章节化）单文件改动，diff 限定 1 file；通过 method signature `sort+diff` 比对验证"无新增/删除/改名"。

**Tech Stack:** macOS 14+ / Swift 5.9 / SwiftPM `path: "Sources/UsageBar"` 递归扫描子目录（不需改 `Package.swift`）。

**前置：** 已在 `feat/v0.3.2-code-hygiene-2` 分支。spec G2 v2 已 `approved-after-revisions`，frontmatter `reviews` 已 append。

---

## Task 1: 删除死资源 demo.png (SC2)

**Files:**
- Delete: `macos/Resources/demo.png`

**为什么先做：** 0 依赖，1 文件改动。立刻打开 happy path。

- [ ] **Step 1: 确认 demo.png 不在任何活跃引用里**

```bash
grep -rn "demo\.png" --include="*.md" --include="*.sh" --include="*.swift" .
```

期望：只在 `docs/artifacts/issues/11/` 历史记录、`docs/superpowers/specs/2026-05-13-code-structure-hygiene.md`、`docs/versions/v0.3.2-code-structure-hygiene.md` 出现；**README.md 不命中**（已切外链）；**verify-release.sh 不命中**。

- [ ] **Step 2: 删除文件**

```bash
git rm macos/Resources/demo.png
```

- [ ] **Step 3: 跑构建 + 测试 + verify-release**

```bash
cd macos && swift build -c release && swift test
cd .. && make release-artifacts
bash macos/scripts/verify-release.sh macos/UsageBar.zip
```

期望：3 个命令全绿。

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(v0.3.2): 删除死资源 macos/Resources/demo.png

README 自 v0.3.0 起已替换为外链截图（file1.tuzhihao.com），demo.png 不再被任何
活跃文件引用（仅 docs/artifacts/issues/11 历史记录提及）。issue #11 verification
已确认无引用断裂。[spec:2026-05-13-code-structure-hygiene SC2]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: AppResources → BundleLocator 改名 (SC3)

**Files:**
- Rename: `macos/Sources/UsageBar/AppResources.swift` → `macos/Sources/UsageBar/BundleLocator.swift`（**注意此刻还在顶层，下一 task 才进 App/**）
- Modify: 新文件内类型 `AppResourceBundleFinder` → `BundleLocator`
- Unchanged: 函数 `usageBarResourceBundle(...)` 名字不变；2 处调用方（`PollingOptionFormatter` / `MenuBarIconRenderer`）也不需改

**为什么这一步：** 改名独立做、单文件 + 内类型重命名，与目录重组解耦。

- [ ] **Step 1: git mv 改名**

```bash
git mv macos/Sources/UsageBar/AppResources.swift macos/Sources/UsageBar/BundleLocator.swift
```

- [ ] **Step 2: 改文件内的私有类名**

把 `BundleLocator.swift` 里：

```swift
private final class AppResourceBundleFinder {}

func usageBarResourceBundle(
    mainBundle: Bundle = .main,
    finderBundle: Bundle = Bundle(for: AppResourceBundleFinder.self)
) -> Bundle? {
```

改成：

```swift
private final class BundleLocator {}

func usageBarResourceBundle(
    mainBundle: Bundle = .main,
    finderBundle: Bundle = Bundle(for: BundleLocator.self)
) -> Bundle? {
```

（其余正文保持不变。）

- [ ] **Step 3: 验证 grep 残留 = 0**

```bash
grep -rn "AppResourceBundleFinder\|AppResources\.swift" macos/ docs/ CLAUDE.md AGENTS.md
```

期望：除 spec / version / plan 自身（文档引用旧名）外，**代码侧 0 命中**。

- [ ] **Step 4: 跑构建 + 测试**

```bash
cd macos && swift build -c release && swift test
```

期望：绿。

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor(v0.3.2): AppResources.swift → BundleLocator.swift（名实相符）

AppResources 实际职责是「找 SwiftPM resource bundle 的路径」，名字误导新人。
重命名：文件 AppResources.swift → BundleLocator.swift；私有类 AppResourceBundleFinder → BundleLocator。
外部函数 usageBarResourceBundle() 名字保留（2 处调用方 PollingOptionFormatter / MenuBarIconRenderer 不需改）。
[spec:2026-05-13-code-structure-hygiene SC3]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 创建 9 个职责子目录 + git mv 全部 swift 文件（不动 UsageService 章节化）(SC1)

**Files:**
- Create dirs: `App/` `Models/` `Services/` `Providers/Core/` `Providers/Claude/` `Providers/Codex/` `Pricing/` `LocalCost/` `MenuBar/` `Features/Popover/` `Features/Settings/` `Utilities/`
- Git-mv: 55 个 swift 文件按 spec §3.3 完整映射表移入对应子目录

**为什么这一步：** 大重构原子化 —— 一次性 git mv 完成；每个文件 SwiftPM 仍编译；不动单文件内容（章节化留下一 task）。

- [ ] **Step 1: 创建空目录（用 `.gitkeep` 占位防 git 丢空目录）**

```bash
cd macos/Sources/UsageBar
mkdir -p App Models Services Providers/Core Providers/Claude Providers/Codex Pricing LocalCost MenuBar Features/Popover Features/Settings Utilities
```

(无需 .gitkeep——下一步 git mv 会立刻填入文件。)

- [ ] **Step 2: 按 spec §3.3 全表 git-mv**

```bash
cd macos/Sources/UsageBar

# App/ (3)
git mv UsageBarApp.swift App/
git mv AppUpdater.swift App/
git mv BundleLocator.swift App/

# Models/ (10)
git mv UsageModel.swift Models/
git mv UsageHistoryModel.swift Models/
git mv UsageStoreTypes.swift Models/
git mv StoredAccount.swift Models/
git mv StoredCredentials.swift Models/
git mv ProviderID.swift Models/
git mv ProviderRuntime.swift Models/
git mv ProviderUsageSnapshot.swift Models/
git mv MenuBarDisplayMode.swift Models/
git mv UpdateChannel.swift Models/

# Services/ (5)
git mv UsageHistoryService.swift Services/
git mv UsageStatsService.swift Services/
git mv NotificationService.swift Services/
git mv ProviderCoordinator.swift Services/
git mv ProviderRegistry.swift Services/

# Providers/Core/ (1)
git mv UsageProvider.swift Providers/Core/

# Providers/Claude/ (4)
git mv UsageService.swift Providers/Claude/
git mv ClaudeUsageStrategy.swift Providers/Claude/
git mv ClaudeUsageCollector.swift Providers/Claude/
git mv ClaudeCLICredentialsStrategy.swift Providers/Claude/

# Providers/Codex/ (6)
git mv CodexProvider.swift Providers/Codex/
git mv CodexCredentials.swift Providers/Codex/
git mv CodexUsageClient.swift Providers/Codex/
git mv CodexUsageCollector.swift Providers/Codex/
git mv CodexUsageModel.swift Providers/Codex/
git mv CodexRolloutCostParser.swift Providers/Codex/

# Pricing/ (4)
git mv ModelPricing.swift Pricing/
git mv ModelPricingCatalog.swift Pricing/
git mv ClaudePricing.swift Pricing/
git mv OpenAIPricing.swift Pricing/

# LocalCost/ (4)
git mv UsageEventStore.swift LocalCost/
git mv UsageAggregator.swift LocalCost/
git mv ScanCursorStore.swift LocalCost/
git mv JSONLCostParser.swift LocalCost/

# MenuBar/ (3)
git mv MenuBarLabel.swift MenuBar/
git mv MultiMenuBarLabel.swift MenuBar/
git mv MenuBarIconRenderer.swift MenuBar/

# Features/Popover/ (10)
git mv PopoverView.swift Features/Popover/
git mv UsageHeroCard.swift Features/Popover/
git mv UsageCard.swift Features/Popover/
git mv UsageChartView.swift Features/Popover/
git mv UsageHeatmapView.swift Features/Popover/
git mv LocalCostCard.swift Features/Popover/
git mv ProviderTabBar.swift Features/Popover/
git mv ProviderUsageSection.swift Features/Popover/
git mv AccountSwitcherView.swift Features/Popover/
git mv PillPicker.swift Features/Popover/

# Features/Settings/ (1)
git mv SettingsView.swift Features/Settings/

# Utilities/ (4)
git mv PaceCalculator.swift Utilities/
git mv TrendCalculator.swift Utilities/
git mv ResetCountdownFormatter.swift Utilities/
git mv PollingOptionFormatter.swift Utilities/
```

- [ ] **Step 3: 验证布局**

```bash
cd /Users/methol/data/code-methol/usage-bar
find macos/Sources/UsageBar -name '*.swift' -not -path '*/Resources/*' | wc -l
# 期望：55

find macos/Sources/UsageBar -maxdepth 1 -name '*.swift' | wc -l
# 期望：0 （顶层不再有 swift 文件）

find macos/Sources/UsageBar -maxdepth 2 -type d | sort
# 期望：列出 9 个职责子目录 + Resources/ + Providers/Core,Claude,Codex + Features/Popover,Settings
```

- [ ] **Step 4: clean + 全量 build + test**

```bash
cd macos
swift package clean
swift build -c release
swift test
```

期望：3 个命令全绿。SwiftPM 应该顺利递归扫描子目录。

> **如果失败：** 看 build error。可能是 git mv 漏文件、或者打错路径（unlikely）。回滚 `git reset --hard HEAD` 后重做。

- [ ] **Step 5: 跑 release artifacts + verify-release**

```bash
cd /Users/methol/data/code-methol/usage-bar
make release-artifacts
bash macos/scripts/verify-release.sh macos/UsageBar.zip
```

期望：绿（bundle 内 invariants 不变，只是源码目录变了）。

- [ ] **Step 6: 验证 git history 追溯**

```bash
git log --follow --oneline macos/Sources/UsageBar/Providers/Claude/UsageService.swift | head -10
```

期望：能看到 v0.3.1（PR #25 squash）及更早的 commit —— rename detection 成功。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(v0.3.2): 源码目录按职责分 9 子目录（55 文件 git mv）

把 macos/Sources/UsageBar/ 平铺 55 个 swift 文件按职责治成 9 个子目录：
- App/         入口 + AppUpdater + BundleLocator
- Models/      纯数据 struct（10 项）
- Services/    跨 provider 业务编排（HistoryService/StatsService/Notification/Coordinator/Registry）
- Providers/Core,Claude,Codex/  provider 抽象 + 每个 provider 实现一目录
- Pricing/     跨 provider 共用定价（4 项）
- LocalCost/   本地 JSONL 扫描 / 聚合（4 项）
- MenuBar/     菜单栏渲染（3 项）
- Features/Popover,Settings/   主功能 UI 簇
- Utilities/   纯函数 / 格式化 / 计算

Claude 的 UsageService.swift 移进 Providers/Claude/ 与 Codex 范式对齐。
SwiftPM target path 'Sources/UsageBar' 递归扫描子目录，Package.swift 不需改。

未动 UsageService.swift 文件内容（章节化在下一 commit）。

[spec:2026-05-13-code-structure-hygiene SC1]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: UsageService 同文件章节化 (SC4)

**Files:**
- Modify: `macos/Sources/UsageBar/Providers/Claude/UsageService.swift` (886 行 → 章节化后行数 +/-10 注释抵消)

**关键约束：**
- 单文件改动
- 每个 method 保留原 access modifier（private 仍是 private、internal 仍是 internal、nonisolated static 仍 nonisolated static）
- 不改 method body、不改签名、不重命名 method
- 不改 stored property、不改 init/deinit
- diff 视感受是大段 method 块的位置重排序 + 几个 `// MARK:` 注释新增/合并

**为什么单独一个 task：** 这是触动 OAuth/token 链路的"敏感写入路径"，G5 reviewer 会单独核这个 commit。

- [ ] **Step 1: 在动手之前先抽取 method signature 列表（BEFORE baseline）**

```bash
cd /Users/methol/data/code-methol/usage-bar
grep -nE "^[[:space:]]*(@MainActor[[:space:]]+)?(nonisolated[[:space:]]+)?(static[[:space:]]+)?(private|fileprivate|internal|public)?[[:space:]]*(func|var|let)[[:space:]]" macos/Sources/UsageBar/Providers/Claude/UsageService.swift | sort > /tmp/usage-service-before.txt
wc -l /tmp/usage-service-before.txt
```

记下行数。

- [ ] **Step 2: 重新组织 UsageService.swift**

按 spec §3.2 模板重排。目标分区（按文件出现顺序）：

```
1. Type Declaration & Stored Properties
   final class UsageService: ObservableObject {
       // @Published 属性、所有 stored property、static let 常量
       // init / deinit（保留原位置）
   }

2. MARK: - UsageProvider conformance
   extension UsageService: UsageProvider {
       var id: ProviderID { .claude }
       var isConfigured: Bool { ... }
       var nextEligibleRefresh: Date? { backoffUntil }
       func refreshNow() async { ... }
   }

3. MARK: - OAuth & Credentials
   extension UsageService {
       // internal:
       func bootstrapFromCLIIfNeeded() async { ... }
       func startOAuthFlow() { ... }
       func submitOAuthCode(...) async { ... }
       func signOut() { ... }
       func switchAccount(to id: UUID) { ... }
       func beginAddAccount() { ... }

       // private:
       private func migrateStripCLIRefreshToken() async { ... }
       private func loadCredentials() -> StoredCredentials? { ... }
       private func saveCredentials(...) throws { ... }
       private func deleteCredentials() { ... }
       private func refreshCredentials(...) async { ... }
       private func performRefresh(...) async { ... }
       private func attemptCLIKeychainRecovery() async -> Bool { ... }
       private func expireSession() async { ... }
       private func generateCodeVerifier() -> String { ... }
       private func generateCodeChallenge(from:) -> String { ... }
       // ...其余 OAuth 相关 private helper
   }

4. MARK: - Polling & Fetch
   extension UsageService {
       // internal:
       func updatePollingInterval(_:) { ... }
       func fetchUsage() async { ... }
       func fetchProfile() async { ... }

       // private:
       private func sendAuthorizedRequest(...) async throws { ... }
       // ...
   }

5. MARK: - Backoff
   extension UsageService {
       // 注：nextEligibleRefresh 在 UsageProvider conformance 内
       nonisolated static func backoffInterval(...) -> TimeInterval { ... }
       private func recordRateLimitError() { ... }
       // ...
   }

// 文件末尾保留：
// MARK: - Base64URL
extension Data { ... }
```

**实施手段：** 用 Edit 工具按章节顺序把方法移动到对应 extension 块；保留原 access modifier；不改 body。

- [ ] **Step 3: 抽取 AFTER baseline 并对比**

```bash
grep -nE "^[[:space:]]*(@MainActor[[:space:]]+)?(nonisolated[[:space:]]+)?(static[[:space:]]+)?(private|fileprivate|internal|public)?[[:space:]]*(func|var|let)[[:space:]]" macos/Sources/UsageBar/Providers/Claude/UsageService.swift | sort > /tmp/usage-service-after.txt

diff /tmp/usage-service-before.txt /tmp/usage-service-after.txt
```

**期望：** diff 输出**为空**（行号差异因 grep -n 会导致 false positive，需用 `awk` 抹掉行号再 diff）：

```bash
awk -F: '{$1=""; print}' /tmp/usage-service-before.txt | sort > /tmp/before.txt
awk -F: '{$1=""; print}' /tmp/usage-service-after.txt | sort > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

**真正期望：** 空输出。任何不同 = 有 method 被改名 / 删除 / 新增 / 改了 access modifier，违反 SC4。

- [ ] **Step 4: 跑 swift test，重点核 UsageServiceTests / UsageServiceMultiAccountTests 全过**

```bash
cd macos
swift build -c release
swift test --filter UsageServiceTests
swift test --filter UsageServiceMultiAccountTests
swift test   # 全量
```

期望：全绿。

- [ ] **Step 5: 验证 git diff 是单文件**

```bash
cd /Users/methol/data/code-methol/usage-bar
git diff HEAD --stat
```

期望：`1 file changed, +X, -X`，只有 `macos/Sources/UsageBar/Providers/Claude/UsageService.swift`。

- [ ] **Step 6: Commit**

```bash
git add macos/Sources/UsageBar/Providers/Claude/UsageService.swift
git commit -m "refactor(v0.3.2): UsageService.swift 同文件 // MARK: 章节化（OAuth / Polling / Backoff）

把 886 行单文件按职责重组：
- UsageProvider conformance（id / isConfigured / nextEligibleRefresh / refreshNow）
- OAuth & Credentials（bootstrap / startOAuthFlow / submitOAuthCode / signOut / switchAccount + 全部 private helper）
- Polling & Fetch（updatePollingInterval / fetchUsage / fetchProfile + sendAuthorizedRequest 等）
- Backoff（backoffInterval / recordRateLimitError / ...）

实现方式：多个 extension UsageService 块，不带 private/fileprivate 前缀
（保护每个 method 原 access modifier 不变；private extension 会破坏 UsageProvider
协议要求与 internal API 调用方）。

零语义改动：method body / 签名 / access modifier 全部不变；method 顺序重排 +
新增/合并 // MARK: 章节标题。BEFORE/AFTER signature sort+diff 验证空输出。

[spec:2026-05-13-code-structure-hygiene SC4]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: specs/README.md 加 v0.3.2 路径映射表 (SC5 part 1)

**Files:**
- Modify: `docs/superpowers/specs/README.md`（末尾加新章节）

**为什么：** 让历史 spec / plan / artifacts 中失效的 `Sources/UsageBar/X.swift` 引用有反查入口。

- [ ] **Step 1: 在 specs/README.md 末尾追加新章节**

文件末尾（"命名规范"小节之后）追加：

```markdown

## 历史路径映射（v0.3.2 后）

v0.3.2 把 `macos/Sources/UsageBar/` 平铺改为 9 子目录。已 implemented 的 spec / plan / artifacts 中
形如 `Sources/UsageBar/<Name>.swift` 的旧引用，用下表查新位置。完整 spec 见
[`2026-05-13-code-structure-hygiene.md`](./2026-05-13-code-structure-hygiene.md) §3.3。

(此处复制 spec §3.3 中"完整旧→新路径映射（55 项）"全文，包含 9 个分组 + 合计行)
```

- [ ] **Step 2: 复制 spec §3.3 全表**

从 `docs/superpowers/specs/2026-05-13-code-structure-hygiene.md` §3.3 "完整旧→新路径映射（55 项）" 复制 9 个分组。

- [ ] **Step 3: Commit（与 Task 6 一起 commit，先暂存这一步）**

不单独 commit；与 Task 6 合并成 SC5 一个 commit。

---

## Task 6: 更新白名单文档 path 引用 (SC5 part 2)

**Files:**
- Modify: `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/versions/README.md`, 任何 draft/planned spec 中的失效引用

- [ ] **Step 1: 收集失效引用清单**

```bash
cd /Users/methol/data/code-methol/usage-bar
grep -rn "Sources/UsageBar/[A-Z][^/]*\.swift" CLAUDE.md AGENTS.md README.md docs/versions/README.md docs/superpowers/specs/2026-05-13-code-structure-hygiene.md docs/superpowers/specs/2026-05-13-provider-self-management.md
```

记录所有命中。

- [ ] **Step 2: 逐一替换**

按 spec §3.3 映射表，用 Edit 工具把每个命中改成新路径。例如：

- `Sources/UsageBar/UsageService.swift:1-100` → `Sources/UsageBar/Providers/Claude/UsageService.swift:1-100`
- `Sources/UsageBar/AppResources.swift` → `Sources/UsageBar/App/BundleLocator.swift`

CLAUDE.md 已知的命中位置：
- 第 "Architecture — what spans files" 节有 `UsageService.swift:1-100` 等

AGENTS.md 已知的命中位置：
- 暂未确认（实施时 grep）

- [ ] **Step 3: 验证 grep 结果 = 0**

```bash
grep -rn "Sources/UsageBar/[A-Z][^/]*\.swift" CLAUDE.md AGENTS.md README.md docs/versions/README.md
```

**期望：** 无命中。implemented spec / plans / artifacts 不动（不在 grep 范围）。

- [ ] **Step 4: 跑 swift test 确保文档改动没意外波及（这一步保险起见，跑下）**

```bash
cd macos && swift test
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md AGENTS.md README.md docs/
git commit -m "docs(v0.3.2): 白名单文档 path 引用同步到 9 子目录布局

按 spec §3.3 映射表更新失效的 file path 引用：
- CLAUDE.md / AGENTS.md / README.md / docs/versions/README.md / draft specs
- 在 specs/README.md 末尾新增「历史路径映射（v0.3.2 后）」章节，方便
  日后 reader 通过表反查 implemented spec / plans / artifacts 中失效的旧 path

母法 immutability：implemented specs / plans / docs/artifacts/** 不动。

evidence: grep -rn 'Sources/UsageBar/[A-Z][^/]*\.swift' (白名单文件) → 无命中

[spec:2026-05-13-code-structure-hygiene SC5]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 收尾 — Verification log 勾选 + spec status: accepted

**Files:**
- Modify: `docs/superpowers/specs/2026-05-13-code-structure-hygiene.md` (Verification log + frontmatter status)
- Modify: `docs/versions/v0.3.2-code-structure-hygiene.md` (status: in-progress 暂不动，留给 G6 merge 后再升 implemented)

- [ ] **Step 1: 跑全量自动化 evidence 命令收集证据**

```bash
cd /Users/methol/data/code-methol/usage-bar
echo "=== SC1 ===" && find macos/Sources/UsageBar -name '*.swift' -not -path '*/Resources/*' | wc -l && find macos/Sources/UsageBar -maxdepth 1 -name '*.swift' | wc -l
echo "=== SC2 ===" && [ ! -f macos/Resources/demo.png ] && echo "demo.png 已删除"
echo "=== SC3 ===" && [ -f macos/Sources/UsageBar/App/BundleLocator.swift ] && grep -c "AppResourceBundleFinder" macos/Sources/UsageBar/App/BundleLocator.swift && echo "BundleLocator 改名完成"
echo "=== SC4 ===" && git diff $(git log --oneline | grep "SC4" | head -1 | awk '{print $1}')^ --stat -- 'macos/Sources/UsageBar/Providers/Claude/UsageService.swift'
echo "=== SC5 ===" && grep -rn 'Sources/UsageBar/[A-Z][^/]*\.swift' CLAUDE.md AGENTS.md README.md docs/versions/README.md
echo "=== Build/Test/Release ===" && cd macos && swift build -c release && swift test && cd .. && make release-artifacts && bash macos/scripts/verify-release.sh macos/UsageBar.zip
```

期望：每条都符合 SC 验收。

- [ ] **Step 2: 在 spec 文件 Verification log 区把 5 条 SC 勾选并填 evidence**

把每条 `- [ ] SCx — pending` 改成 `- [x] SCx — done (commit <hash>): <evidence 摘要>`。

- [ ] **Step 3: spec frontmatter 改 status: accepted（G2 通过 + 所有 SC 完成）**

```yaml
status: accepted
updated: 2026-05-13
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-05-13-code-structure-hygiene.md
git commit -m "docs(v0.3.2): spec SC1-SC5 全部完成，frontmatter status: accepted

Verification log 全勾，evidence 字段填充各 commit 哈希 + 自动化命令输出摘要。
G6 merge 后由 PR squash commit 触发 implemented 升级。

[spec:2026-05-13-code-structure-hygiene]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: G5 review + PR + squash merge

- [ ] **Step 1: 起 G5 reviewer subagent**

prompt 要点：
- 角色 = 独立 code reviewer
- 重点核 SC4 commit（UsageService.swift 单文件改动）是否真"纯重排序"（method signature 无变化、access modifier 全等）
- 核 CLAUDE.md / AGENTS.md path 引用更新无遗漏
- 核未触动 verify-release.sh / Package.swift / Info.plist / OAuth 链路语义

- [ ] **Step 2: 按 reviewer verdict 处理 must-fix + 推回 nice-to-have**

按 superpowers:receiving-code-review 流程：技术评估，不盲从。

- [ ] **Step 3: gh pr create**

```bash
gh pr create --title "feat(v0.3.2): 代码结构治理 — 9 子目录 + UsageService 章节化 + 死资源清理" --body "...（含 spec 链接、SC 列表、CI 期望、verify-release 输出摘要）..."
```

- [ ] **Step 4: 等 CI（`build` check）绿**

```bash
gh pr checks --watch
```

- [ ] **Step 5: squash merge**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 6: 把 spec status 升 implemented + version 升 in-progress→shipped（等 G7 tag 推送时由 release runbook 处理）**

本步只升 spec status:
```yaml
status: implemented
```

并在 frontmatter `reviews` append G5 verdict。

---

## 自检（写 plan 后由作者跑一遍）

- ✅ 每个 task 一个独立 commit，含 commit message
- ✅ 每步可独立验证（命令 + 期望输出）
- ✅ 无 TBD / TODO / "类似 Task N"
- ✅ Task 顺序：低风险（demo.png 删）→ 改名 → 大重组 → 高敏感（UsageService 章节化）→ docs → 收尾
- ✅ 类型/函数名跨 task 一致（`BundleLocator` / `usageBarResourceBundle` / `// MARK:` 名）
- ✅ 每个 SC 都有至少一个 task 覆盖
- ✅ 自动化 evidence 命令都直接列出
