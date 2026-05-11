---
slug: competitive-analysis
title: 竞品调研报告 — SessionWatcher × CodexBar
type: research
created: 2026-05-11
updated: 2026-05-11
sources:
  - https://www.sessionwatcher.com/
  - https://codexbar.app/
  - https://github.com/steipete/CodexBar
  - https://github.com/ryoppippi/ccusage
  - https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor
referenced_by:
  - 2026-05-11-docs-governance
---

# 竞品调研报告：SessionWatcher × CodexBar

> 调研日期：2026-05-11  
> 调研对象：[sessionwatcher.com](https://www.sessionwatcher.com/)、[codexbar.app](https://codexbar.app/) (开源仓库 [steipete/CodexBar](https://github.com/steipete/CodexBar))  
> 调研目的：本项目（`claude-usage-bar`）下一阶段产品化方向 —— UI/交互参考 SessionWatcher，功能/实现参考 CodexBar，全栈坚持 Swift 原生。

---

## TL;DR

| 维度 | SessionWatcher（学 UI） | CodexBar（学功能） | 我们当前 `claude-usage-bar` |
|---|---|---|---|
| 形态 | macOS 14+ 菜单栏 App，Swift 原生 | macOS 14+ 菜单栏 App，Swift 原生（Swift 6.2 严格并发） | macOS 14+ 菜单栏 App，Swift 5.9 |
| 商业模式 | 一次性付费 $2.99 / $7.99 | 完全免费，MIT 开源 | 免费、BSD-2 |
| 支持厂商数 | 5 个（Claude、Codex、Copilot、Cursor、Gemini） | 30+ 个 provider | 1 个（Claude） |
| 数据源 | 仅文案"读取使用统计"，未公开机制 | OAuth API / 浏览器 cookie / CLI PTY / 本地 JSONL 日志多源回退 | Anthropic OAuth API 单路 |
| UI 卖点 | 干净的浅色风格、按厂商缩写显示在 menu bar、趋势箭头、$/天展示 | 多 status item、Merge Icons 切换器、Pace tracking、Widget | 5h+7d 双进度条 + 历史图表 |
| 通知 | 80%/90% 阈值通知 | session 配额通知 + 周重置 confetti | 阈值通知 |
| 历史图表 | 7 天使用率图 | 30 天本地 cost 扫描 + WidgetKit history 图 | 30 天 history，1h/6h/1d/7d/30d 多区间 |
| CLI | ❌ | ✅ 同款配置文件，macOS/Linux 双平台 tarball | ❌ |
| Widget | ❌（未提及） | ✅ Switcher / Usage / History / Compact 四种 | ❌ |
| 更新 | Sparkle | Sparkle 2.8.1 | Sparkle 2.8.1 ✅ 一致 |

**判断**：我们的"地基"（Swift + SwiftPM + Sparkle + OAuth + 30 天 history）已经和两个竞品同构。差距集中在 **产品广度（多 provider）、产品深度（pace tracking / 多账号 / CLI / Widget）、和 UI 精细度（菜单栏紧凑度、趋势、$ 显示）**。

---

## 1. SessionWatcher 详解（UI / 交互参考对象）

### 1.1 产品定位与商业模式

- 一句话：*"Never lose another coding session to rate limits."*
- 定价：
  - Claude Code 单工具版 **$2.99 一次性**
  - All Tools（5 个工具）**$7.99 一次性**，对比单买省 $6.96，标记为 "Best value"
  - 无订阅，30 天无理由退款（contact@soren-starck.com）
- 平台：macOS 14+，Apple Silicon + Intel，**Apple 签名 + 公证**（这点比 ad-hoc 强）
- 营销话术核心：
  - *"Glance up, keep coding"*
  - *"No guessing, no mental math"*
  - *"Setup in under 30 seconds"*
- 与 Anthropic 的关系：明确声明独立产品，不属于任何厂商。

### 1.2 支持的 5 个工具

```
CLA  Claude Code
CDX  OpenAI Codex
CUR  Cursor
COP  GitHub Copilot
GEM  Gemini CLI
```

### 1.3 菜单栏视觉（重点学习项）

通过其官网截图可以提取出以下 UI 规范：

- **多 status item 模式**：每个工具一个 status item，按 `CLA 42% ▼2%` 这样的紧凑字符串显示。
  - `CLA`：3 字母大写厂商缩写
  - `42%`：当前使用率
  - `▼2%` / `▲5%`：趋势箭头 + 增量（绿色上升、红色下降）
  - 后面还能拼时间戳，例如 `Mon Jan 1 12:00 AM`
- **配色**：
  - 整体浅色 / macOS Tahoe (15) 玻璃风
  - 红绿色作为趋势指示
- **popover 风格**：
  - 大字号居中数字 + 进度条 + reset countdown
  - 多工具版有可滚动的工具切换列表
- **菜单栏显示模式**（可配置）：
  - 百分比
  - Token 数
  - $ 成本
  - 仅图标紧凑模式
  - 多模式组合（同时显示百分比 + 趋势 + 时间戳）

### 1.4 功能清单

核心监控：
- 5h rolling 窗口 + weekly 周限
- 使用率图表 + 7 天历史
- Token + cost 明细
- macOS 原生通知
- 菜单栏显示模式可切换

高级特性：
- **"BestToolNow" 推荐引擎**：根据当前各工具用量推荐"现在该用哪个"
- 工具间切换（统一界面）
- 统一使用分析 / 总成本分解
- 自动检测已安装工具（仅显示在用的）
- 选项卡可重排序 / 隐藏

通知：
- 阈值告警，文案里提到 80%、90%

### 1.5 数据源（未公开 → 推测）

SessionWatcher **没有在官网披露**它怎么读 Claude 数据：
- 不提 OAuth
- 不提 `~/.claude/` 日志
- 仅声明 "reads usage statistics locally" / "no API key required"

我们通过对比可以推断它至少同时具备以下能力之一：
1. 用 Claude Code CLI 安装时存下的 OAuth credentials（`~/.claude/.credentials.json` 或 Keychain `Claude Code-credentials`）
2. 解析本地 JSONL 日志（`~/.claude/projects/**/*.jsonl`）算 cost
3. 不排除有 CLI PTY 回退

这与 CodexBar 的做法完全一致 —— 也是我们要学的部分。

### 1.6 我们能从 SessionWatcher 偷的"UI / 交互细节"

| 细节 | 现状 | 学完后目标 |
|---|---|---|
| menu bar 字符串 | 双进度条 icon | 支持 `CLA 42% ▼2%` 文本模式（可配置） |
| 趋势箭头 | 无 | 引入 ▲/▼ + 颜色 |
| 显示模式 | 单一图标 | 提供 percent / tokens / $ / icon-only 四套，外加组合 |
| popover 主视觉 | 紧凑数据表 | 大字号 hero 数字 + 副指标 + reset countdown |
| 阈值通知文案 | 已有阈值 | 文案打磨成 SessionWatcher 风格 |
| 落地页 | README | 写一个 marketing 风格的 docs 页（可选） |

---

## 2. CodexBar 详解（功能 / 实现参考对象）

### 2.1 仓库快照

- 仓库：`github.com/steipete/CodexBar` —— **MIT 协议**
- 主语言：Swift（占 99% 体量），少量 Shell / JS / Makefile
- 当前最新版：`v0.25.1`（2026-05-11，本调研当日刚发）
- ⭐ Star：约 11,988，📦 Fork：927
- 站点：`codexbar.app`（首页 403，但官方 README 与子文档可读）
- 作者：[@steipete](https://github.com/steipete)（PSPDFKit 前 CEO，长期 iOS 圈知名作者）
- 模块化（SwiftPM 多 target）：
  ```
  Sources/CodexBarCore           # fetch + parse 核心
  Sources/CodexBar               # state + UI
  Sources/CodexBarWidget         # WidgetKit
  Sources/CodexBarCLI            # 命令行
  Sources/CodexBarMacros         # SwiftSyntax 宏（provider 注册）
  Sources/CodexBarMacroSupport   # 宏共享支持
  Sources/CodexBarClaudeWatchdog # Claude CLI PTY 守护进程
  Sources/CodexBarClaudeWebProbe # Claude web 抓取诊断 CLI
  ```

### 2.2 支持的 Provider（30+，仅列出最相关）

| Provider | 数据源 / 实现机制 |
|---|---|
| **Codex** | OAuth (`~/.codex/auth.json`) → CLI RPC (`codex app-server`) → OpenAI Web (WKWebView 抓 chatgpt.com) |
| **Claude** | OAuth (`~/.claude/.credentials.json` 或 Keychain `Claude Code-credentials`) → claude.ai 浏览器 cookie → `claude` CLI PTY |
| Cursor | 浏览器 cookie |
| Copilot | GitHub device flow + Copilot 内部 usage API |
| Gemini | Gemini CLI 的 OAuth 凭证 |
| Vertex AI | gcloud OAuth + 本地 Claude 日志 token cost |
| z.ai / DeepSeek / Venice / Warp / OpenRouter / Perplexity / Mistral / ... | API key 或 cookie |

### 2.3 核心架构（与我们现有 `UsageService` 单源对比）

#### 模块分层

```
UI 层 (CodexBar)
   ↓ 订阅
UsageStore (ObservableObject) — 全局状态
   ↓ 调用
UsageFetcher / ProviderFetchStrategy[] — 多源回退
   ↓
ProviderDescriptor — 单一描述源（labels, URLs, capabilities, strategies）
   ↓
Host APIs（Keychain/Cookies/PTY/HTTP/WebView/TokenCost）— 横向能力
```

关键设计原则（值得抄）：
1. **Provider Descriptor 是 single source of truth**：每个 provider 一个文件夹，一个描述符 + 若干 fetch strategy，UI 自动 descriptor-driven 渲染（不写 provider-specific 分支）。
2. **Fetch Strategy 链式回退**：每个 provider 声明 `[strategy1, strategy2, ...]`，按顺序尝试，结果带 attempts + errors 用于调试。
3. **横向 Host API 协议化**：`KeychainAPI` / `BrowserCookieAPI` / `PTYAPI` / `HTTPAPI` / `WebViewScrapeAPI` / `TokenCostAPI` / `StatusAPI` 都是协议，provider 不直接碰 `FileManager` 或 `Security.framework`。
4. **SwiftSyntax 宏注册 provider**：`@ProviderDescriptorRegistration @ProviderDescriptorDefinition` 实现编译期自动注册，加新 provider"一个文件夹搞定"。
5. **Swift 6 严格并发**：`Sendable` state + 显式 `MainActor` hop。

#### 数据流（关键模仿对象）

```
Background timer  →  UsageFetcher
                     ├─ provider A descriptor → strategy chain
                     ├─ provider B descriptor → strategy chain
                     └─ ...
                  →  UsageStore（merged snapshot）
                  →  ① status item icon
                     ② popover 菜单卡
                     ③ Widget snapshot (写到 App Group 容器)
                     ④ 通知服务
```

### 2.4 Claude provider 的多路 fetch（与我们最相关）

这是我们要照搬的核心 —— 当前 `claude-usage-bar` 只有 **OAuth API 一条路**，CodexBar 是 **OAuth → 浏览器 cookie → CLI PTY → 本地 JSONL** 四条路：

#### Path 1：OAuth API（默认）
- 凭证来源（按优先级）：
  1. CodexBar 自己缓存的 OAuth token
  2. `~/.claude/.credentials.json`
  3. Claude CLI Keychain item `Claude Code-credentials`（首次启动可拉起，需要 `user:profile` scope）
- 端点：`GET https://api.anthropic.com/api/oauth/usage`
- Header：`Authorization: Bearer <token>` + `anthropic-beta: oauth-2025-04-20`
- 输出映射：
  - `five_hour` → session 窗口
  - `seven_day` → 周窗口
  - `seven_day_opus` / `seven_day_sonnet` → 模型分桶
  - `extra_usage` → Extra 用量（USD 月度限额）
- ✅ **这条路就是我们当前的实现**，字段映射也一致

#### Path 2：claude.ai 浏览器 cookie（Web API）
- 从 Safari / Chrome 系 / Firefox 抓 `claude.ai` 的 `sessionKey` cookie
  - Safari: `~/Library/Cookies/Cookies.binarycookies`
  - Chrome 系: `~/Library/Application Support/Google/Chrome/*/Cookies`
  - Firefox: `~/Library/Application Support/Firefox/Profiles/*/cookies.sqlite`
- 调 4 个 web 接口：
  - `GET /api/organizations` → 拿 orgId
  - `GET /api/organizations/{orgId}/usage` → session/weekly/opus 百分比
  - `GET /api/organizations/{orgId}/overage_spend_limit` → Extra usage
  - `GET /api/account` → email + plan
- 多账号通过 `~/.codexbar/config.json` 的 `tokenAccounts` 数组承载

#### Path 3：CLI PTY（claude `/usage`）
- 通过 PTY 启动 `claude --allowed-tools ""`
- 自动应答首启 prompts（trust files / workspace / telemetry）
- 发送 `/usage`、`/status`，解析渲染输出
  - 去 ANSI 后定位 "Current session" / "Current week" header
  - 提取百分比 + reset 文本
- 适合 OAuth/Cookie 都不可用时兜底
- 有一个 daemon 子进程 `CodexBarClaudeWatchdog` 维持稳定 PTY

#### Path 4：本地 JSONL 成本扫描
- 扫描以下根目录的 `**/*.jsonl`：
  - `$CLAUDE_CONFIG_DIR` 列表中每个根的 `<root>/projects`
  - 回退：`~/.config/claude/projects`、`~/.claude/projects`
  - 也支持 `~/.pi/agent/sessions/**/*.jsonl`
- 解析 `type: "assistant"` 行的 `message.usage`，per-model token 计数
- 用 `message.id + requestId` 去重流式块
- 缓存：`~/Library/Caches/CodexBar/cost-usage/claude-v2.json`
- 滚动 30 天窗口，60s 最短刷新间隔

### 2.5 配置与多账号

- **统一配置文件**：`~/.codexbar/config.json`（0600 权限）
- App 和 CLI 共享同一份配置
- 关键字段：
  ```jsonc
  {
    "version": 1,
    "providers": [
      {
        "id": "claude",
        "enabled": true,
        "source": "auto",           // auto/web/cli/oauth/api
        "cookieSource": "auto",     // auto/manual/off
        "cookieHeader": null,
        "apiKey": null,
        "tokenAccounts": {          // 多账号
          "version": 1,
          "activeIndex": 0,
          "accounts": [
            { "id": "...", "label": "user@example.com", "token": "sk-ant-...", "addedAt": 1735123456, "lastUsed": 1735220000 }
          ]
        }
      }
    ]
  }
  ```
- **Provider 顺序由数组顺序控制**（UI/CLI 共用）
- 命令 `codexbar config validate` / `codexbar config dump`

### 2.6 UI 与 icon 细节

- LSUIElement，无 Dock 图标
- Status item：**18×18 模板图**，bar 含 primary + secondary 窗口
- **填充**默认表示"剩余百分比"，可切换为"已用百分比"
- 失败时图标变暗；status 异常显示 incident overlay
- **Merge Icons 模式**：把多个 provider 合并成一个 status item + 切换器
- 全局快捷键打开菜单（先关已开的再开新的）
- 菜单卡内每行 reset 倒计时（可切换为绝对时间）
- 多账号 UI：账号切换 bar 或最多 6 个 stacked account cards
- 显示模式可选：critter bars / 品牌图标 + percent label

### 2.7 Pace tracking（重点抄）

CodexBar 有一个非常聪明的 **配速指示器**：

- 比较"当前用量"与"按均匀消耗预期的用量"
- 三态：
  - **On pace** — 与预期一致
  - **X% in deficit** — 消耗过快，按此速率会在 reset 前用完
  - **X% in reserve** — 消耗较慢，有余量
- 当处于 deficit 时，右侧显示估计 *"Runs out in …"*；处于 reserve 时显示 *"Lasts until reset"*
- 窗口经过 < 3% 时隐藏（避免抖动）
- Codex 还支持历史数据驱动的非均匀 pace

### 2.8 刷新策略

- 频率：Manual / 1m / 2m / 5m（默认）/ 15m / 30m
- 存于 `UserDefaults`
- 后台刷新跑在非主线程，更新 `UsageStore`
- 错误/陈旧状态 dim 菜单栏图标
- 可选 provider storage 扫描（默认关闭，开启后扫描已知 provider 本地路径并报大小）

### 2.9 Widget

- WidgetKit 扩展模块
- 写共享 JSON snapshot 到 App Group 容器，widget 读
- 四种 widget：
  - **Switcher**（small/medium/large）：provider 切换器
  - **Usage**（small/medium/large）：可配置 provider 的使用率
  - **History**（medium/large）：历史趋势图
  - **Metric**（small）：credits / today-cost / 30-day-cost

### 2.10 CLI

- 二进制名 `codexbar`，基于自家 fork 的 [Commander](https://github.com/steipete/Commander) 包
- 安装方式：
  - app 内 Preferences → Advanced → Install CLI（symlink 到 `/usr/local/bin/codexbar` + `/opt/homebrew/bin/codexbar`）
  - tarball：`CodexBarCLI-v<tag>-{macos-arm64,macos-x86_64,linux-aarch64,linux-x86_64}.tar.gz`
  - Linux Homebrew tap
- 命令：
  - `codexbar usage --provider claude --source oauth --format json --pretty`
  - `codexbar cost --provider both`（本地 token cost 扫描）
  - `codexbar cache clear --cookies --cost`
  - `codexbar config validate / dump`
- 与 app 共享 `~/.codexbar/config.json`

### 2.11 Sparkle 集成（与我们对比）

| 项 | CodexBar | 我们 |
|---|---|---|
| Sparkle 版本 | 2.8.1 | 2.8.1 ✅ |
| Feed | GitHub Releases appcast.xml | GitHub Pages appcast.xml ✅ |
| 公钥 | Info.plist `SUPublicEDKey` | 同 ✅ |
| Beta 通道 | 通过 `sparkle:channel="beta"` + `allowedChannels` 控制 | 未实现 |
| 安装方式 | Sparkle + Homebrew cask（Homebrew 渠道禁 Sparkle） | 仅 DMG + Sparkle |
| 公证 | 有 `sign-and-notarize.sh` | 无（ad-hoc） |

### 2.12 隐私模型

- 数据落地：`~/.codexbar/config.json`（0600，含 secrets）+ `~/Library/Caches/CodexBar/cost-usage/*.json`
- 不全盘扫描，只读"已知位置"：
  - 浏览器 cookies/local storage（按需 Full Disk Access）
  - provider 的 config 文件
  - 本地 JSONL 日志
- macOS 权限：
  - **Full Disk Access**（可选）：仅 Safari cookie 用
  - **Keychain access**：Chromium "Safe Storage" 解密 key、Claude OAuth bootstrap
  - **Files & Folders 提示**：CLI 启动时可能弹（视 helper 的工作目录）
  - 不申请 Screen Recording / Accessibility
- 不存密码（cookies 是用户授权"重用"）

---

## 3. 横向对比（我们 / SessionWatcher / CodexBar）

### 3.1 功能差距矩阵（粗粒度）

| 功能 | 我们 | SessionWatcher | CodexBar |
|---|---|---|---|
| 5h + 7d 双窗口 | ✅ | ✅ | ✅ |
| Opus / Sonnet 分桶 | ✅ | 未明确 | ✅ |
| Extra usage (USD) | ✅ | "cost breakdown" | ✅ |
| 30 天 history | ✅（自己生成） | 7d | 30d（扫本地 JSONL） |
| 历史图表（hover） | ✅ | ✅ | ✅（widget 也有） |
| **趋势箭头 ▲▼** | ❌ | ✅ | ❌（用 pace 替代） |
| **Pace tracking** | ❌ | ❌ | ✅ |
| **多 menu bar 显示模式** | ❌ | ✅（percent/tokens/$/icon） | ✅（critter bars / brand+%） |
| 多账号 | ❌ | 未明确 | ✅（tokenAccounts） |
| 阈值通知 | ✅ | ✅ | ✅ |
| **周重置 confetti** | ❌ | ❌ | ✅ |
| Widget | ❌ | ❌ | ✅（4 种） |
| CLI | ❌ | ❌ | ✅ |
| **多 provider** | ❌ | ✅ 5 个 | ✅ 30+ |
| 本地 cost 扫描 | ❌ | "cost"，机制未公开 | ✅ JSONL 解析 |
| OAuth 复用 Claude CLI 凭证 | ❌（自己跑 OAuth flow） | 推测 ✅ | ✅ |
| Browser cookie 回退 | ❌ | ❌ | ✅ |
| CLI PTY 回退 | ❌ | ❌ | ✅ |
| Sparkle 通道（beta） | ❌ | 未明确 | ✅ |
| Apple 公证 | ❌（ad-hoc） | ✅ | ✅ |

### 3.2 实现机制差距（我们 vs CodexBar）

| 维度 | 我们当前 | CodexBar | 抄过来的成本 |
|---|---|---|---|
| 全局状态 | 单个 `UsageService` `@MainActor` `ObservableObject` | `UsageStore` + descriptor + strategy chain | 中（需要抽象层重构） |
| 数据源 | 单 OAuth | 多 strategy 回退，带 attempts + errors | 中（先复用 Claude CLI Keychain → 加 cookie 回退） |
| 并发模型 | Swift 5.9，部分 `@MainActor` | Swift 6.2 严格并发，全 `Sendable` | 中 |
| 配置 | `UserDefaults` + `~/.config/claude-usage-bar/credentials.json` | `~/.codexbar/config.json` 统一 + Keychain 缓存 | 低 |
| Provider 抽象 | 无（只有 Claude） | descriptor + macro 自动注册 | 高（仅当我们计划扩展多 provider 才值得） |
| Widget | 无 | App Group + WidgetSnapshot | 中 |
| CLI | 无 | 同二进制 + Commander | 中 |
| 签名 | ad-hoc | Developer ID + notarize | 低（仅需 Apple Developer 账号） |

---

## 4. 我们的目标产品形态（结合两者）

**一句话定位**：*把 SessionWatcher 的"看一眼就懂"体验，叠加 CodexBar 的"读得到的本地数据 + 多路回退"健壮性，全部用 Swift 原生实现。*

### 4.1 必须有（Phase 1 / MVP+）

> 当前已具备 → 直接抄 UI 即可拿到产品级体验

1. **菜单栏显示模式**：在现有图标基础上加 4 种可选 —— `icon` / `percent` / `percent + 趋势` / `$/天 + 趋势`
2. **趋势 ▲▼ 计算**：基于已有的 30 天 `history.json` 计算近 6h 趋势
3. **大字号 hero popover**：重做 `PopoverView` 主视觉，参考 SessionWatcher 的紧凑大字 + reset countdown
4. **Pace tracking**：抄 CodexBar 的三态指示（On pace / In deficit / In reserve），UI 文案直译
5. **Apple 公证**：从 ad-hoc 切到 Developer ID + notarize（提升安装体验，去掉右键开启）

### 4.2 应该有（Phase 2 / 健壮性 + 深度）

> 当前没有，但抄 CodexBar 难度可控

6. **OAuth 凭证复用 Claude CLI**：除了自己 OAuth flow，加一条"读 `~/.claude/.credentials.json` 或 Keychain `Claude Code-credentials`"快路，让装了 Claude Code 的用户**零配置**
7. **本地 JSONL cost 扫描**：扫 `~/.claude/projects/**/*.jsonl`，per-model token / cost 30 天累积，作为 USD 维度补充
8. **多账号**：`credentials.json` → `tokenAccounts` 数组，UI 加账号切换器（CodexBar 风格的 account bar）
9. **菜单栏多显示模式中的 token / $ 模式**：来源就是上面的本地 cost 扫描
10. **Sparkle beta 通道**：给我们引入 nightly/beta 节奏

### 4.3 可以有（Phase 3 / 平台扩展）

> 完整模仿 CodexBar，工作量较大，需要决策

11. **Web cookie 回退**：抓 `claude.ai` 的 sessionKey，调 4 个 web 端点 —— 风险点是 Safari Full Disk Access 提示
12. **CLI PTY 回退**：跑 `claude /usage` 解析输出
13. **WidgetKit 扩展**：4 类 widget（Switcher 对我们没意义，可砍）
14. **CLI 工具**：`claude-usage-bar usage --json`，对 CI 用户友好
15. **多 provider 化**（决策点）：是继续做 *Claude-only*，还是变成 *Claude-first multi-provider*？
   - **建议保持 Claude-only**（差异化定位、UI 更简洁、维护负担低）
   - 如果未来要扩，先抄 ProviderDescriptor 抽象再加 Codex

### 4.4 明确不做

- ❌ 一次性付费墙（用户期望开源/免费）
- ❌ Electron / Tauri 等非原生方案
- ❌ 后端服务（保持纯本地）

---

## 5. Swift 化执行策略（与现有 codebase 对齐）

### 5.1 当前代码已经满足的前提

我们已经具备 CodexBar 同款的基础设施：

- ✅ Swift / SwiftUI / Swift Charts
- ✅ SwiftPM，platforms = macOS 14+
- ✅ Sparkle 2.8.1 SwiftPM 集成
- ✅ MenuBarExtra + LSUIElement
- ✅ `UsageService` 作为单一状态源（虽未抽 descriptor）
- ✅ `~/.config/claude-usage-bar/credentials.json`（0600，与 CodexBar 的 `~/.codexbar/config.json` 同模式）
- ✅ 30 天 history.json 持久化 + downsampling
- ✅ `MenuBarIconRenderer` 自渲染 NSImage
- ✅ tag-driven Release CI + appcast.xml + GitHub Pages

### 5.2 建议的重构路径（保持渐进，不一次性大改）

**Step A — UI 升级（最高 ROI，零架构变化）**

- `PopoverView.swift`：照搬 SessionWatcher 视觉风格，大字号 hero
- `MenuBarIconRenderer.swift`：增加 `text-only` 渲染分支，输出 `CLA 42% ▼2%` 字符串
- 新加 `TrendCalculator.swift`：基于 `UsageHistoryService` 算近 6h 趋势
- 新加 `PaceTracker.swift`：抄 CodexBar 算法（已知 window 长度 + 起点 + 已用 → On pace / deficit / reserve）
- `SettingsView.swift`：新增"菜单栏显示模式"四选一 + "Pace tracking"开关

**Step B — 数据源扩展（最大健壮性提升）**

- 抽象 `ClaudeUsageStrategy` 协议：`func fetch() async throws -> UsageResponse`
- 实现两个 strategy：
  - `BuiltinOAuthStrategy`（现有逻辑）
  - `ClaudeCLICredentialsStrategy`（读 Claude CLI 的 `~/.claude/.credentials.json` 与 Keychain item）
- `UsageService` 内部循环调用 strategy chain，记录 attempts + errors（debug 菜单露出）

**Step C — 本地 cost 扫描（产品深度）**

- 新加 `LocalCostScanner.swift`，扫 `~/.claude/projects/**/*.jsonl`
- 缓存到 `~/Library/Caches/claude-usage-bar/cost-usage/claude-v1.json`，60s 节流
- 计算结果加入 `UsageResponse`（新字段 `localCost30d`）
- UI 在 popover 加 cost 区块

**Step D — Apple 公证 + 多账号**

- 申请 Developer ID（如尚未），更新 `macos/scripts/build.sh` 加 notarize 步骤
- `StoredCredentials` 扩展为数组 + activeIndex（兼容旧文件迁移）

**Step E — Pace tracking 显示**

- 已在 Step A 准备好算法，Step E 接入"Runs out in X" / "Lasts until reset" 副文案

**Step F+ — WidgetKit / CLI / Cookie 回退**

- 单独评估，每项工作量较大，建议视用户反馈再排

### 5.3 不建议直接抄的部分

- CodexBar 的 SwiftSyntax macro（仅 multi-provider 才划算）
- CodexBar 的 30+ provider（我们差异化定位是 Claude-only）
- CodexBar 的 `CodexBarMacroSupport` / `CodexBarClaudeWatchdog` 等子进程模式（除非进入 CLI PTY 模式才需要）

---

## 6. 风险与开放问题

1. **OAuth scope 问题**：CodexBar 文档明确 *"Requires `user:profile` scope (CLI tokens with only `user:inference` cannot call usage)"*。我们当前 `defaultOAuthScopes = ["user:profile", "user:inference"]` ✅ 满足；但若复用 Claude CLI 的 token，要检查 scope 是否兼容。
2. **Anthropic 接口稳定性**：`api/oauth/usage` 不是公开 API。CodexBar 在 2026-05 还能用，但需关注未来变动。
3. **隐私边界**：本地 JSONL 扫描需要在隐私文案中明确"读取项目对话日志（仅用量行）"，避免误解。
4. **公证身份**：需要 Apple Developer 账号（$99/年）；如果保留 ad-hoc，则提升不到 SessionWatcher 等级。
5. **License 取舍**：CodexBar MIT，我们目前 BSD-2 一致，未来引用任何 CodexBar 代码片段也要标注 attribution。
6. **品牌**：项目名是 `claude-usage-bar`，要不要趁机改成更产品化的名字（如 `ClaudeBar` / `ClaudePulse`）？这是产品决策。

---

## 7. 行动建议（按优先级）

1. **立刻能做**（无依赖）：Step A 中的 UI 升级（hero popover + 趋势箭头 + 多显示模式）
2. **下一迭代**（数据深度）：Step B + Step C（Claude CLI 凭证复用 + 本地 cost 扫描）
3. **打磨期**（体验）：Step D（公证 + 多账号）+ Step E（Pace tracking 接入）
4. **远期评估**：Step F+（Widget / CLI / Cookie）

完整 Phase 1+2 工作量估计：2~3 周（一个工程师，Swift 熟手）。

---

## 引用

### 官方与产品页

- SessionWatcher 首页：<https://www.sessionwatcher.com/>
- SessionWatcher × Claude：<https://www.sessionwatcher.com/claude>
- SessionWatcher 对比文章：<https://www.sessionwatcher.com/guides/best-claude-code-usage-trackers>
- CodexBar 官网：<https://codexbar.app/>（403，需通过镜像访问）
- CodexBar 第三方介绍：<https://onmymenubar.app/codexbar/>

### CodexBar 源码与文档

- 仓库：<https://github.com/steipete/CodexBar>
- README：<https://github.com/steipete/CodexBar#readme>
- 架构：<https://github.com/steipete/CodexBar/blob/main/docs/architecture.md>
- 配置：<https://github.com/steipete/CodexBar/blob/main/docs/configuration.md>
- Claude provider：<https://github.com/steipete/CodexBar/blob/main/docs/claude.md>
- Codex provider：<https://github.com/steipete/CodexBar/blob/main/docs/codex.md>
- UI：<https://github.com/steipete/CodexBar/blob/main/docs/ui.md>
- Refresh loop：<https://github.com/steipete/CodexBar/blob/main/docs/refresh-loop.md>
- CLI：<https://github.com/steipete/CodexBar/blob/main/docs/cli.md>
- Widgets：<https://github.com/steipete/CodexBar/blob/main/docs/widgets.md>
- Sparkle：<https://github.com/steipete/CodexBar/blob/main/docs/sparkle.md>
- Provider authoring：<https://github.com/steipete/CodexBar/blob/main/docs/provider.md>
