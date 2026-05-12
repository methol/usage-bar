---
id: 2026-05-12-codex-provider
title: Codex provider 对接（第一条数据源：~/.codex/auth.json OAuth → wham/usage）
status: draft
created: 2026-05-12
updated: 2026-05-12
owner: claude-code
model: claude-opus-4-7
target_version: v0.2.5
related_adrs: [0005]
related_research: [codex-data-sources, competitive-analysis]
spec_criteria:
  - id: SC1
    criterion: 装了 codex CLI 并 ChatGPT 登录后，popover Codex tab 展示 5h（session）与 weekly 两张用量卡（百分比 + 进度条 + pace 标记 + Resets in 倒计时），plan 徽章正确（Plus/Pro/…），有 credits 时显示余额行
    done: false
    evidence: null
  - id: SC2
    criterion: 没有 ~/.codex/auth.json（或 OPENAI_API_KEY 也没有）时，Codex tab 显示"未检测到 Codex 凭证，请运行 codex 登录"占位，不崩溃、不报噪声 error
    done: false
    evidence: null
  - id: SC3
    criterion: wham/usage 返回 401/403 时，Codex tab 显示"Codex 凭证已过期，请运行 codex 重新登录"，不崩溃；网络错误显示通用错误文案
    done: false
    evidence: null
  - id: SC4
    criterion: Codex 的凭证读取与请求是只读副作用——不创建/不修改 ~/.codex/auth.json，不发起浏览器 OAuth 登录流程；CODEX_HOME 环境变量被尊重
    done: false
    evidence: null
  - id: SC5
    criterion: 单测覆盖 auth.json 解析（OAuth 形态 / API key 形态 / 缺字段）、wham/usage 响应解码（含 primary/secondary 窗口角色归一化、缺窗口、credits 字符串/数字）、reset_at→Date 与窗口长度→pace 输入的换算
    done: false
    evidence: null
  - id: SC6
    criterion: 切到 Codex tab 时拉取一次用量；popover 里有 "Refresh" 能重拉；Claude tab 行为零回归（菜单栏 label、polling、通知都不受影响）
    done: false
    evidence: null
  - id: SC7
    criterion: 错误日志不打印 raw token / refresh_token / account_id 值（与既有 ClaudeCLICredentialsStrategy SC7 安全约束一致）
    done: false
    evidence: null
automated_checks:
  - "SC_AUTO_BUILD: cd macos && swift build -c release"
  - "SC_AUTO_TEST: cd macos && swift test"
  - "SC_AUTO_ARTIFACTS: make release-artifacts"
manual_checks:
  - "目测 popover Codex tab：有 codex 登录态时两张卡 + plan 徽章；无登录态占位文案；切 tab 触发拉取"
reviews: []
---

# Codex provider 对接（第一条数据源）

## 1. 背景与目标

[ADR 0005](../adr/0005-reopen-multi-provider-direction.md) 重新开放多 provider 方向，分两步：v0.2.4 已搭好 popover 顶部的 provider tab UI 外壳（Claude 可用，Codex/Cursor/Copilot/Gemini 是"敬请期待"占位）；本 spec 是第二步的第一刀 —— **把 Codex tab 从占位变成真的能看用量**，但只接 Codex 最稳的一条数据源（`~/.codex/auth.json` 里的 OAuth token → `https://chatgpt.com/backend-api/wham/usage`），CLI RPC / chatgpt.com Web / 本地 session JSONL 等其余路留作后续 patch 版本。

API 事实见调研 [`codex-data-sources.md`](../research/codex-data-sources.md)（直接读 CodexBar 源码整理）。

用户决策（2026-05-12）：① 本版本只打通一条数据源；② Codex tab 展示逻辑尽量和 Claude tab 一致；③ 凭证只读 `~/.codex/auth.json`，不做 app 内独立 OAuth 登录。

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| 数据源 | 仅 OAuth → `wham/usage` | 用户决策①；最轻最稳，CodexBar 也把它当首选路 |
| 凭证来源 | 只读 `~/.codex/auth.json`（尊重 `CODEX_HOME`），支持 `OPENAI_API_KEY` 与 `tokens.*` 两种形态 | 用户决策③；复用 codex CLI 已登录态，零配置 |
| Token 刷新 | **v0.2.5 不做主动刷新、不写回 auth.json**；401/403 → 提示用户跑 `codex` | "只读"硬约束；写回 auth.json 是另一回事（见 §5 风险 1），等用户反馈再决定 |
| Codex tab 展示 | 复用 `UsageHeroCard`：Session(5h) + Weekly(7d) 两卡 + pace 标记 + Resets in；外加 plan 徽章 + credits 行 | 用户决策②；pace 可由 `reset_at` + `limit_window_seconds` 直接算，**无需历史样本** |
| Codex 趋势箭头 / 成本 / 热力图 | 不做 | 趋势需持久化历史样本；成本/热力图是"本地 JSONL 扫描"那条数据源 —— 都不在本版本 |
| Codex 用量是否走 polling / 通知 / 多账号 | 不做后台 polling / 通知 / 多账号；切到 Codex tab 时拉一次 + Refresh 按钮重拉 | Codex tab 不驱动菜单栏 label，惰性拉取够用；范围收敛 |
| Codex 状态服务 | 新建独立 `CodexUsageService`（`@MainActor ObservableObject`），**不复用 `UsageService`** | `UsageService` 是 Claude 的 OAuth/refresh/polling/backoff 单一真相源；Codex 这条路完全不同，混进去会污染它 |

## 3. 设计

### 3.1 新增文件（全部 `macos/Sources/ClaudeUsageBar/`）

| 文件 | 职责 |
|---|---|
| `CodexCredentials.swift` | `struct CodexCredentials { accessToken; refreshToken?; idToken?; accountId? }` + `enum CodexCredentialStore { static func load(env:) throws -> CodexCredentials? }`：定位 `~/.codex/auth.json`（`CODEX_HOME` 优先），解析 `OPENAI_API_KEY`（→ accessToken-only）或 `tokens.{access_token|accessToken, refresh_token|refreshToken, id_token|idToken, account_id|accountId}`。文件不存在 → 返回 `nil`（静默）；存在但解析失败 → throw（error case 名不带 raw 值，SC7）。`internal`（非 private）让 `@testable import` 单测能直接 decode。 |
| `CodexUsageModel.swift` | `struct CodexUsageSnapshot: Decodable`（`plan_type` → `CodexPlan` 枚举带 `displayName`；`rate_limit.primary_window/secondary_window` → `CodexRateWindow { usedPercent: Double; resetAt: Date; windowSeconds: Int }`；`credits → CodexCredits { hasCredits; unlimited; balance: Double? }`）。再加 `normalizedWindows()` —— 按 `windowSeconds/60 == 300 / 10080` 把 (primary, secondary) 归一成 (session, weekly)（抄 CodexBar `CodexRateWindowNormalizer` 思路）。解码对每个子结构 try?-tolerant（坏字段不整体失败）。 |
| `CodexUsageClient.swift` | `enum CodexUsageClient { static func fetchUsage(credentials:) async throws -> CodexUsageSnapshot }`：`GET https://chatgpt.com/backend-api/wham/usage`，`Authorization: Bearer`、`ChatGPT-Account-Id`（有才带）、`Accept`、`User-Agent`。401/403 → `CodexUsageError.unauthorized`；其它非 2xx → `.server(status)`（**不带 body 进 error 文案**，避免泄漏）；网络异常 → `.network`。Endpoint 常量集中在此文件，方便 mock。 |
| `CodexUsageService.swift` | `@MainActor final class CodexUsageService: ObservableObject`：`@Published var snapshot: CodexUsageSnapshot?` / `lastError: String?` / `lastUpdated: Date?` / `isCredentialPresent: Bool`。`func refresh() async`：load 凭证 → 无 → set `isCredentialPresent=false`、清 snapshot；有 → fetch → 成功 set snapshot+lastUpdated、清 error；失败 set lastError（用户向文案）。`func refreshIfStale()`（>60s 才重拉，避免每次切 tab 都打网络）。无 Timer、无 backoff（范围收敛；后续版本要后台 polling 再说）。 |
| `CodexUsageView.swift` | popover Codex tab 内容。`@ObservedObject codex: CodexUsageService`。布局镜像 `PopoverView.usageView`（Claude）：①若 `!isCredentialPresent` → 占位（图标 + "未检测到 Codex 凭证，请在终端运行 `codex` 登录" + ← 回 Claude）；②否则两张 `UsageCard{ UsageHeroCard(...) }`（Session 用 session 窗口、icon `clock`；Weekly 用 weekly 窗口、icon `calendar`；`bucket` 由 `UsageBucket(utilization: usedPercent, resetsAt: ISO8601(resetAt))` 适配，`pacePct` 由 `expectedPacePct(resetDate: resetAt, windowDuration: windowSeconds)` 算，`trend: nil`）；③plan 徽章卡（`CodexPlan.displayName`）；④有 credits 时余额行卡；⑤`lastError` 卡；⑥底部 "Updated … ago" + Refresh 按钮（`Task { await codex.refresh() }`）。 |
| 单测 `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` | 见 §3.4。 |

### 3.2 改动现有文件

| 文件 | 改动 |
|---|---|
| `ProviderTabBar.swift` | `ProviderTab.isAvailable`：`self == .claude` → `self == .claude || self == .codex`。 |
| `ClaudeUsageBarApp.swift` | 加 `@StateObject private var codexService = CodexUsageService()`；传进 `PopoverView`。 |
| `PopoverView.swift` | 加 `@ObservedObject var codexService: CodexUsageService`；分支 `selectedProvider == .codex` 时渲染 `CodexUsageView(codex: codexService)` 而非 `ProviderComingSoonView`；在该分支 `.task(id: selectedProvider)` 里 `await codexService.refreshIfStale()`（切到 Codex tab 自动拉一次）。Claude 分支不变。 |

不动：`UsageService` / `UsageHistoryService` / `NotificationService` / `UsageEventStore` / `UsageStatsService` / 菜单栏 label / Settings —— Codex 这条路完全旁路它们。

### 3.3 数据流

```
切到 Codex tab
  → PopoverView .task(id:) → CodexUsageService.refreshIfStale()
     → CodexCredentialStore.load()  (读 ~/.codex/auth.json，CODEX_HOME 优先)
        ├ nil → isCredentialPresent=false → CodexUsageView 显示占位
        └ creds → CodexUsageClient.fetchUsage(creds)
                    GET chatgpt.com/backend-api/wham/usage  (Bearer + ChatGPT-Account-Id)
           ├ 200 → CodexUsageSnapshot → normalizedWindows() → @Published snapshot
           │        → CodexUsageView: Session/Weekly 卡（usedPercent + pace from reset_at & window_seconds）+ plan + credits
           ├ 401/403 → lastError = "Codex 凭证已过期，请运行 `codex` 重新登录"
           └ 其它/网络 → lastError = 通用文案
点 Refresh → CodexUsageService.refresh()（强制重拉）
```

### 3.4 测试方案

`CodexProviderTests`（纯单元，无网络、无 Keychain、无真实 `~/.codex`）：

- **凭证解析**：喂 fixture JSON Data —
  - OAuth 形态（snake_case）→ accessToken/refreshToken/idToken/accountId 全对
  - camelCase 形态 → 同上
  - 仅 `OPENAI_API_KEY` → accessToken=key，refreshToken/accountId 为 nil
  - 缺 `tokens` 且无 `OPENAI_API_KEY` → throw（断言是 missingTokens case）
  - 非法 JSON → throw（decodeFailed）
  - `CODEX_HOME` 注入 → `_authFileURLForTesting(env:)` 指向 `$CODEX_HOME/auth.json`（DEBUG-only 测试钩子，仿 `ClaudeCLICredentialsStrategy`）
- **响应解码**：
  - 全量 fixture（plan_type=plus、primary 18000s/secondary 604800s）→ 两窗口、usedPercent、resetAt（== `Date(timeIntervalSince1970:)`）、plan==.plus
  - primary/secondary 顺序颠倒（primary 是 604800s）→ `normalizedWindows()` 把 weekly/session 摆正
  - 只有一个窗口 → 另一个为 nil
  - `credits.balance` 是字符串 `"12.34"` → 解析成 12.34；是数字 → 同
  - 未知 `plan_type`（如 `"team"` 之外的怪值）→ `.unknown("…")`，`displayName` 不崩
  - 缺 `rate_limit` 整段 → snapshot 仍解码成功、两窗口 nil
- **pace 输入换算**：给定 resetAt（now + 1h）+ windowSeconds=18000 → `expectedPacePct` 输入合理（这条主要验适配层，不重测 PaceCalculator 本身）

CI 仍跑 `swift build -c release` + `swift test` + `make release-artifacts`，全绿。

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🆕 | `macos/Sources/ClaudeUsageBar/CodexCredentials.swift` | |
| 🆕 | `macos/Sources/ClaudeUsageBar/CodexUsageModel.swift` | |
| 🆕 | `macos/Sources/ClaudeUsageBar/CodexUsageClient.swift` | |
| 🆕 | `macos/Sources/ClaudeUsageBar/CodexUsageService.swift` | |
| 🆕 | `macos/Sources/ClaudeUsageBar/CodexUsageView.swift` | |
| 🆕 | `macos/Tests/ClaudeUsageBarTests/CodexProviderTests.swift` | |
| 🔧 | `macos/Sources/ClaudeUsageBar/ProviderTabBar.swift` | `isAvailable` 加 `.codex` |
| 🔧 | `macos/Sources/ClaudeUsageBar/ClaudeUsageBarApp.swift` | 注入 `CodexUsageService` |
| 🔧 | `macos/Sources/ClaudeUsageBar/PopoverView.swift` | Codex 分支渲染 `CodexUsageView` + 切 tab 拉取 |
| ✅ 不动 | `UsageService.swift` 等 Claude 链路全部 | Codex 旁路 |

## 5. 风险 / Open questions

1. **不刷新 token → Codex tab 可能频繁"过期"**。access_token JWT 的 `exp` 未知；若只有几小时，不常跑 `codex` 的用户会经常看到过期提示。缓解：v0.2.5 先这样，文案明确给出修复动作；若反馈差，后续版本加"401 时用 refresh_token 刷新 **并写回 auth.json**"（写回是必须的——否则轮换后的 refresh_token 会让 codex CLI 自己失效，见调研 §3）。**这一点请 G2 reviewer 重点判断：是否值得在本版本就做带写回的刷新。**
2. **`wham/usage` 接口未来漂移**：字段名/路径变了会静默坏。缓解：解码 try?-tolerant；坏了显示通用 error 而非崩溃。和 Claude `/api/oauth/usage` 同等脆弱性，可接受。
3. **`~/.codex/config.toml` 的 `chatgpt_base_url` 覆盖**：本版本不解析 config.toml，固定打 `chatgpt.com/backend-api`。极少数自托管/代理用户会拿不到——可接受，后续按需补。
4. **`UsageBucket` 适配**：复用 Claude 的 `UsageBucket(utilization:resetsAt:)` 把 Codex 窗口塞进 `UsageHeroCard`，靠 ISO8601 字符串round-trip resetAt。简单但有点绕；若觉得脏，可给 `UsageHeroCard` 加一个直接收 `Date` 的初始化器——留给实现期权衡，不强制。

## 6. 后续工作（不在本 spec 范围）

- Codex token 刷新 + 写回 `~/.codex/auth.json`（或独立缓存）
- Codex CLI RPC（`codex app-server`）/ chatgpt.com Web 兜底路
- Codex 本地 session JSONL 扫描 → 成本/token（喂 v0.2.3 的 per-provider `UsageEventStore` + 热力图）
- Codex 历史样本持久化 → 趋势箭头 + 后台 polling + 阈值通知
- Codex 多账号
- Cursor / Copilot / Gemini provider（仍是占位，按需求再排）

## 7. 引用

- 相关调研：[`../research/codex-data-sources.md`](../research/codex-data-sources.md)、[`../research/competitive-analysis.md`](../research/competitive-analysis.md)
- 相关 ADR：[`../adr/0005-reopen-multi-provider-direction.md`](../adr/0005-reopen-multi-provider-direction.md)
- 落地版本：[`../versions/v0.2.5-codex-provider.md`](../versions/v0.2.5-codex-provider.md)

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [ ] SC1 — pending
- [ ] SC2 — pending
- [ ] SC3 — pending
- [ ] SC4 — pending
- [ ] SC5 — pending
- [ ] SC6 — pending
- [ ] SC7 — pending
