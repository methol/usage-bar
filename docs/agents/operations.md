---
slug: agents-operations
title: AI agent 实操命令与配置
type: guide
created: 2026-05-13
updated: 2026-05-13
---

# AI agent operations — 实操命令与配置

真正动手实施时的速查。**写文档时改看 [`conventions.md`](./conventions.md)；治理框架看 [`AGENTS.md`](../../AGENTS.md)**。

## 1. 构建 / 测试 / 打包命令

`make` targets 从仓库根目录跑；纯 `swift` 命令必须 `cd macos/`（`Package.swift` 在那里）。

```sh
# 构建与打包
make build              # swift build -c release（自动 cd macos）
make app                # build + 组装 .app（Info.plist / Sparkle / 资源 / 签名）
make zip                # app + zip + verify-release
make dmg                # app + DMG + verify-release
make release-artifacts  # 一次构建产出 zip + dmg + verify
make install            # build + 拷到 /Applications
make clean              # swift package clean + 删 bundle/zip/dmg

# 单测（必须 cd macos/）
cd macos && swift test
cd macos && swift test --filter UsageServiceTests
cd macos && swift test --filter UsageServiceTests/testBackoffIntervalCapsAtSixtyMinutes
```

**CI**（`.github/workflows/build.yml`）每个 push/PR 跑：`swift build -c release` → `swift test` → `make release-artifacts`。本地 commit 前要保证两者绿。

## 2. Issue 驱动开发配置

> 本节是 `methol-issue-driven-dev` skill 的项目配置单源。改动需配合 [`.github/labels.json`](../../.github/labels.json) 与 [`scripts/issues/`](../../scripts/issues/) 一起更新。
> 完整生命周期见 [`docs/workflow/issue-driven.md`](../workflow/issue-driven.md)。

### 适用范围

- **适用**：人工测试反馈的 bug、单个小功能点、脚本 / 文档微调
- **不适用**：跨模块架构级、需要 spec / ADR 支撑的大粒度任务 → 走 [`AGENTS.md`](../../AGENTS.md) §4 主回路（research → spec/ADR → plan → 实施）

### 模块清单 → scope 标签

| scope 标签 | 覆盖范围 |
|---|---|
| `scope:infra` | CI / `scripts/` / `Makefile` / `macos/scripts/` 构建链路 / 治理文档工具链 |

本仓库是单个 macOS app，业务代码改动默认不打 scope（只在涉及构建 / 工具链时打 `scope:infra`）。同步到 [`.github/labels.json`](../../.github/labels.json)。

### 评审者

- `reviewer`: `subagent` —— 用 Task 起评审 agent，prompt 见 skill `references/review-prompts.md`
- 与 [`AGENTS.md`](../../AGENTS.md) §5 fallback 一致：codex 可用时可临时改 `codex`（`codex:rescue` skill）

### 守护线 checklist（plan 阶段自检；任一触发 → `status:needs-human`）

- [ ] 不触碰凭证 / 密钥链路：OAuth token 刷新、`credentials.json` 格式、Sparkle 私钥、`SU_FEED_URL` 注入逻辑（见 [`AGENTS.md`](../../AGENTS.md) §6.1）
- [ ] 不引入新第三方依赖、不改 `LICENSE`、不改变开源 / 收费定位
- [ ] 不修改 `docs/adr/` 下已 `accepted` 的 ADR、不修改 `AGENTS.md` 或母法 spec（issue 明确要求除外）
- [ ] 不在 `UsageService` 之外重复 fetch / auth / 轮询逻辑（架构红线，见 [`CLAUDE.md`](../../CLAUDE.md) Architecture 节）
- [ ] 不手改 `Info.plist` 里的版本号（由 `APP_VERSION` / git tag 在 build 时注入）
- [ ] 单 issue 影响面不跨"app 代码 / 发版链路 / 治理文档"三大块，且改动文件数大致 ≤ 5

### 受保护文件（改了就 `status:needs-human`）

- `docs/adr/*`、`AGENTS.md`、`docs/superpowers/specs/2026-05-11-docs-governance.md`
- `.github/workflows/release.yml`、`macos/Package.swift` 的依赖 pin
- `macos/scripts/verify-release.sh` 的 invariant 检查

### 敏感写入链路（ship 阶段 diff 碰到就 `status:needs-human`）

- OAuth / token 刷新链路：`Providers/Claude/UsageService.swift`、`Models/StoredCredentials.swift`
- Sparkle 更新链路：`App/AppUpdater.swift`、`appcast.xml` 生成、release workflow
- codesign / `build.sh` 的 framework 嵌入步骤

### 本地验证命令矩阵（实施后、ship 前必跑相关项）

| 触发条件 | 命令 |
|---|---|
| 改 Swift 代码 | `cd macos && swift build -c release` + `cd macos && swift test` |
| 改 build / bundle / `scripts/` | `make release-artifacts` + `bash macos/scripts/verify-release.sh macos/UsageBar.zip` |
| 改 UI | `make app` 后手动起 app 回归金路径（尽量少跑 Xcode build） |
| 改纯文档 | 链接核对 + frontmatter lint（母法 spec `automated_checks`）；无脚本则人工核对 |

### CI / PR checks

- PR 必须等绿：`build`（`.github/workflows/build.yml`，跑 `swift build -c release` → `swift test` → `make release-artifacts`）
- `merge.sh` 用 `gh pr checks --watch` 等所有 check 绿

### artifacts 路径

- `docs/artifacts/issues/<num>/` — 本仓库把 skill 默认的 `artifacts/issues/<num>/` 挪到 `docs/` 下
- [`scripts/issues/{kickoff,ship,merge}.sh`](../../scripts/issues/) 已同步该路径
- 若日后从 skill 重新同步脚本，记得保留这个 override

## 3. 跨 runner 工具 preflight 详表

进入仓库后 AI 应先确认核心工具可用。任何一项不可用，**走 fallback 而不停下问用户**（除非所有路径都失败）。

| 角色 | Claude Code 工具 | 其他 runner 等价 | Fallback |
|---|---|---|---|
| brainstorming | `superpowers:brainstorming` | 手写本 spec _TEMPLATE.md + 对话 | 直接对话 + 模板 |
| 写 spec | `Write` / `Edit` | 等价文件操作 | 直接编辑 |
| writing-plans | `superpowers:writing-plans` | 手写 plan markdown + checklist | TODO.md 风格清单 |
| 实施 / verification | `superpowers:verification-before-completion` | 自检 checklist | 手动跑 `swift build && swift test` |
| 跨模型 design-review (G2) | `codex:codex-rescue` / `codex:rescue` | Codex CLI / API；换 Claude 子会话 | `general-purpose` subagent（prompt 显式要求独立判断） |
| 跨 session plan-review (G3) | `general-purpose` subagent | 新开会话 + 完整 prompt | 主会话 self-review + cool-down 后重读 |
| code-review (G5) | `superpowers:requesting-code-review` + `/review` | Codex / Cursor review | 跨模型 review + 自动化 lint |
| security-review | `/security-review` slash | 等价 prompt | 手写凭证 / 权限 checklist |
| fact-check | `Explore` subagent | 只读快速查找 | grep / find 手动 |
| integration-review (G7) | `/ultrareview` slash | 多 agent 并发抽样 | 多次独立 review + cross-check |

> **Claude Code runner 已记 memory**：codex 工具不可用时**不要停下问用户**，直接走 `general-purpose` subagent fallback。

## 4. Mock server 说明

`scripts/mock-server.py` 只 mock `GET /api/oauth/usage`。要把 app 指向它，必须临时改：
1. `Providers/Claude/UsageService.swift` 的 `defaultUsageEndpoint`
2. `macos/Resources/Info.plist` 加 `NSAppTransportSecurity > NSAllowsLocalNetworking`

**两处改动 commit 前必须还原** — 不在 debug flag 后面。Mock server 不实现 OAuth，所以本地需要已有有效 `~/.config/usage-bar/credentials.json`。

完整 scenario 列表见 [`CONTRIBUTING.md`](../../CONTRIBUTING.md) §Testing with the mock server。

## 5. CHANGELOG 维护

由 AI 在发版 runbook（[`docs/runbooks/release.md`](../runbooks/release.md) §5）自动生成。规则：

- **不要直接 copy PR 标题**（多为英文）
- 每条 PR / commit 翻译成中文 + 按"用户视角"重写
- 分类：新增 / 改进 / 修复 / 安全隐私 / 内部
- 引用对应 version 文件与 spec id

## 6. 自动化"硬证据"

下列命令产出绿色输出 = "我做完了"的硬证据（治理框架 G4）：

```sh
cd macos && swift build -c release
cd macos && swift test
make release-artifacts
bash macos/scripts/verify-release.sh macos/UsageBar.zip
```

纯文档版本：见母法 spec frontmatter `automated_checks` 中的 `SC_AUTO_LINKCHECK` / `SC_AUTO_FRONTMATTER`。

## 7. 项目架构红线（改代码前必读）

> 跨文件的"大图"无法从单个文件推断出来；本节列出实施时容易踩到的不变量。

- **`UsageService` 是 Claude provider API 状态的单源真相**。它拥有 OAuth（PKCE + 浏览器回调粘贴）、token 刷新、polling timer、指数退避。其他类型通过 `@StateObject` 从 `UsageBarApp` 注入并读 published 属性 — **不要在其他地方重复 fetch / auth 逻辑**。位置：`Providers/Claude/UsageService.swift`（v0.3.2 同文件 `// MARK:` 分为 OAuth / Polling / Backoff 三段 + UsageProvider conformance）

- **三个注入 service 组成 app**，在 `App/UsageBarApp.swift` 中 wire：
  - `UsageService` — API 状态
  - `UsageHistoryService` — 内存 ring buffer，每 5 min + `willTerminate` flush 到磁盘；30 天保留
  - `NotificationService` — 阈值通知
  - `AppUpdater` — Sparkle 包装
  - `UsageService` 持 history/notification service 的弱引用，polling loop 推 sample 并触发 alert

- **Token & history 存在 `~/.config/usage-bar/`**：
  - `credentials.json`（0600，含 access + refresh + expiry + scopes；回退读历史 plaintext `token` 文件 — 见 `Models/StoredCredentials.swift`）
  - `history.json`
  - 新格式首次写入时删除 legacy `token` 文件

- **模型价格数据走打包的 LiteLLM 快照**，不是手维护表。`ModelPricingCatalog` 加载 `litellm_model_prices.json`（upstream: `BerriAI/litellm` 的 `model_prices_and_context_window.json`），优先级：
  1. `~/.config/usage-bar/litellm_model_prices.json`（运行时缓存，3h 后台刷新 — 见 `ProviderCoordinator.onTickSideEffects`）
  2. 打包副本
  3. 空表（UI 降级为"定价数据未加载"）

  `build.sh` 在 `swift build` 前 `curl` 新快照到 `macos/Sources/UsageBar/Resources/litellm_model_prices.json`，组装 bundle 后 `git checkout` 回来（保持 `git status` 干净；fetch 失败就用 committed 副本）。`OpenAIPricing` / `ClaudePricing` 现在只保留 `normalize` / `displayName`；所有价格查询走 `ModelPricingCatalog`（含逐级回退 candidate chain 解析 codex CLI 别名）。`THIRD_PARTY_LICENSES.txt`（LiteLLM MIT）一并打包；两个新资源都被 `verify-release.sh` 检查。

- **Bundle 创建是自定义的，不是 stock SwiftPM**。`macos/scripts/build.sh` 跑 `swift build -c release`，然后手工组装 `.app/Contents/{MacOS,Resources,Frameworks}`，复制 SwiftPM 资源 bundle（`UsageBar_UsageBar.bundle`），用 `actool` 编译 `Resources/Assets.xcassets`，嵌入 `Sparkle.framework`。新增打包资源需要：
  1. 放进 SwiftPM 资源 bundle（在 `Package.swift` `resources: [.process("Resources")]` 声明）
  2. 任何新 `.app/Contents/Resources/...` 不变量也要在 `macos/scripts/verify-release.sh` 中强制检查

- **Sparkle 在 build 时由 `SU_FEED_URL` gate**。env 变量未设（本地构建默认），`build.sh` 从 `Info.plist` 剥掉 `SUFeedURL`，updater 失效。Release CI 注入 feed URL。**不要在 `Info.plist` 中硬写 feed URL**。

- **发版由 tag 驱动**。push `v*` tag 触发 release workflow：一次 build → 产 ZIP（Sparkle）+ DMG（手装）→ verify → 由 ZIP 生成签名 Sparkle `appcast.xml` → deploy 到 GitHub Pages。需要 `SPARKLE_PRIVATE_KEY` repo secret。`Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion` 在 build 时由 `APP_VERSION` 环境变量或 git tag 注入；plist 中写死的 `1.0.0` 是历史占位，**不要手改**。

## 8. 代码风格速记

- 第三方依赖最小化：Sparkle 是唯一运行时 dep。加新依赖要同步：`Package.swift` + `verify-release.sh`（若打包进 bundle）+ `build.sh` framework 嵌入步骤
- 一个文件一个主 SwiftUI view（约定：`Features/Popover/PopoverView.swift` / `Features/Settings/SettingsView.swift` / `Features/Popover/UsageChartView.swift`）
- 所有 UI-touching service 类是 `@MainActor`；扩展时保留这个 annotation
