# Issue #28 诊断

- 链接:https://github.com/methol/usage-bar/issues/28
- 标题:调整app显示，不要显示中文

## 复现与定位

issue 提出两点产品诉求:

1. **不要显示中文** — 用户视角看到的 app 文案应全部英文化(与现有英文 UI 风格一致)
2. **减少提示性的文案** — 砍掉冗余的辅助说明,功能本身要直观易懂

`grep -rn '[一-龥]' macos/Sources/UsageBar --include='*.swift'` 后人工筛掉注释行,得到**面向用户显示**的中文字面量共 **约 30 处**,分布在 9 个文件:

| 文件 | 中文文案处数 | 类型 |
|---|---:|---|
| `Features/Settings/SettingsView.swift` | 5 | Section/Picker label + 提示行 + .help |
| `Features/Popover/PopoverView.swift` | 5 | 空/未登录态文案 + 按钮 |
| `Features/Popover/ProviderTabBar.swift` | 6 | 占位 tab/未配置 tab 文案 + 按钮 |
| `Features/Popover/LocalCostCard.swift` | 5 | footnote + accessibility |
| `Features/Popover/UsageHeatmapView.swift` | 2 | "统计中…" + accessibility |
| `Models/UpdateChannel.swift` | 2 | enum.displayName(显示在 Picker) |
| `Providers/Gemini/GeminiProvider.swift` | 6 | runtime.setError 错误串(显示在 UI) |
| `Providers/Codex/CodexProvider.swift` | 3 | runtime.setError 错误串 |
| `Providers/Claude/UsageService.swift` + `Models/StoredAccount.swift` | 3 | 新账号默认 label `"账号 N"` |

**不在改动范围:**

- 代码注释里的中文(`///` / `//`) — issue 明确说"显示",注释不显示给用户,保留以免噪音 diff
- `docs/` 下的中文(治理文档/spec/ADR) — 项目治理语言是中文(见 `docs/agents/conventions.md`),不动
- issue template / PR template — 内部 AI/contributor 流程,不在 app UI 中

## 根因

历史代码混用中英,新版菜单栏 app 面向全球用户,统一英文是合理走向。提示文案冗余的部分(如 SettingsView 的"Enable = … 拖动可调整顺序"长行、UpdateChannel 的"Beta 通道包含未稳定版本…"重复说明、PopoverView 的"请在终端完成 Claude 授权后,点击「重新检测」…"长句)在 UX 上属噪音 — UI 元素本身已自解释。

## 修复方案

### A. 全部 UI 字面量翻成英文(对照表)

| 位置 | 原中文 | 改为 |
|---|---|---|
| Settings §"更新通道" | "更新通道" | "Updates" |
| Settings §Picker | "通道" | "Channel" |
| Settings .help | "显示在菜单栏" | "Show in menu bar" |
| Popover 空态 | "没有启用的供应商" | "No providers enabled" |
| Popover 空态 | "打开设置" | "Open Settings" |
| Popover 未登录态 | "未检测到有效的授权凭证" | "Not signed in" |
| Popover 未登录态按钮 | "重新检测" | "Retry" |
| ProviderTabBar 占位 | "{name} 支持开发中,敬请期待" | "{name} coming soon" |
| ProviderTabBar 返回 | "← 回到 Claude" | "← Back to Claude" |
| ProviderTabBar 未配置标题 | "未检测到 {name} 凭证" | "{name} not signed in" |
| ProviderTabBar 未配置 hint(codex) | "请在终端运行 `codex` 登录后回到这里。" | "Run `codex` in your terminal, then come back." |
| ProviderTabBar 未配置 hint(其他) | "请先在对应的 CLI / app 里登录 {name}。" | "Sign in via the {name} CLI / app." |
| LocalCostCard footnote | "定价数据未加载,费用估算暂不可用" | "Pricing data not loaded; costs unavailable." |
| LocalCostCard footnote | "含 N 条无定价数据的调用" | "{N} call(s) without pricing data" |
| LocalCostCard 隐私声明 | "ⓘ 仅读用量字段,不读对话内容" | "ⓘ Usage fields only; conversations are not read." |
| LocalCostCard a11y label | "本机消费明细" | "Local cost breakdown" |
| LocalCostCard a11y hint | "收起" / "展开" | "Collapse" / "Expand" |
| Heatmap loading | "统计中…" | "Loading…" |
| Heatmap a11y label | "{day},约 {usd}" | "{day}, approx {usd}" |
| UpdateChannel | "稳定版" | "Stable" |
| UpdateChannel | "Beta(实验性)" | "Beta" |
| Gemini errors ×6 | "未检测到有效的 Gemini 凭证…" 等 | 见下 |
| Codex errors ×3 | "未检测到有效的 Codex 凭证…" 等 | 见下 |
| Account default label | "账号 N" / "账号 1" | "Account N" / "Account 1" |

Gemini errors:
- "未检测到有效的 Gemini 凭证,请运行 `gemini` 重新登录" → "Gemini not signed in. Run `gemini` to sign in."
- "未检测到 gemini-cli 安装,无法识别 OAuth 凭证" → "gemini-cli not installed; cannot resolve OAuth credentials."
- "Gemini 凭证已过期,请运行 `gemini` 重新登录" → "Gemini credentials expired. Run `gemini` to sign in again."
- "未检测到 Gemini Code Assist 项目" → "No Gemini Code Assist project found."
- "无法获取 Gemini 用量(稍后重试)" → "Could not fetch Gemini usage. Will retry."

Codex errors:
- "未检测到有效的 Codex 凭证,请在终端运行 `codex` 登录" → "Codex not signed in. Run `codex` to sign in."
- "Codex 凭证已过期,请在终端运行 `codex` 重新登录" → "Codex credentials expired. Run `codex` to sign in again."
- "无法获取 Codex 用量(稍后重试)" → "Could not fetch Codex usage. Will retry."

### B. 砍掉冗余提示文案

- **SettingsView L44**:`Text("Enable = 控制数据采集与 tab；菜单栏 = 是否在状态栏展示。拖动可调整顺序。")` → **整行删除**。Enable 拨片 + 菜单栏 toggle + 拖动手柄自解释,无需补丁注释。
- **SettingsView L80**:`Text("Beta 通道包含未稳定版本,仅建议测试用户启用")` → 简化并翻译为 `Text("Beta includes pre-release builds for testing.")` **保留**。理由(plan 评审反馈):OTA 推送 beta 是发版安全相关 UX,新用户需要知道 "Beta" channel 的含义,不能完全砍掉。
- **PopoverView L304**:`Text("请在设置中至少启用一个供应商。")` → 简化为 `Text("Enable at least one provider in Settings.")`(改英文不删,因为下面 Open Settings 按钮需要这条提示给出"为什么"上下文)
- **PopoverView L330**:`Text("请在终端完成 Claude 授权后,点击「重新检测」或重启本应用。")` → 简化为 `Text("Sign in with the Claude CLI, then tap Retry.")`(同上,Retry 按钮需要一句话上下文)
- **UpdateChannel "Beta(实验性)"** → "Beta" (砍掉括号后缀)

### C. 已有用户磁盘上的 "账号 N" label

`StoredAccount.label` 写入 `~/.config/usage-bar/accounts.json`。本 PR 改两类入口:

1. `Models/StoredAccount.swift:48` 是 **v1 → v2 静默迁移路径**的硬编码 label — 当 v1 老用户首次跑到本 PR 版本时,迁移代码会以**英文** `"Account 1"` 写新 accounts.json(用户从未在 UI 看到过这条 label,纯粹是迁移产物,无回归风险)。
2. `Providers/Claude/UsageService.swift:352/474` 是**首次签入 / 新增账号**时的默认 label — 此后新账号一律英文 `"Account N"`。

**已经处于 v2 状态且当前 label 是中文的用户**(已经在 UI 上用过、可能也手动改过):**不迁移**,保留磁盘上的字段不动。理由:
- label 是用户可编辑字段,自动覆盖反而是行为越界
- 不引入迁移代码 = 不增加额外复杂度 / 不动持久化数据

### D. 测试 fixture / 断言里硬编码的中文 label

`grep -rn '账号' macos/Tests` 共 4 处影响断言/fixture:

| 文件:行 | 类型 | 处理 |
|---|---|---|
| `Tests/UsageBarTests/StoredCredentialsStoreMigrationTests.swift:47` | 断言迁移后 label | **改成 `"Account 1"`**(对齐 §C.1 v1→v2 迁移路径英文化) |
| `Tests/UsageBarTests/UsageServiceMultiAccountTests.swift:56` | 断言首次签入后 label | **改成 `"Account 1"`**(对齐 `UsageService.swift:474`) |
| `Tests/UsageBarTests/UsageServiceTests.swift:930` | fixture 构造 `StoredAccount(label: "账号 1", ...)` | **统一改成 `"Account 1"`**(self-consistent fixture,不与生产代码耦合) |
| `Tests/UsageBarTests/UsageServiceTests.swift:968` | 同上 | **统一改成 `"Account 1"`** |

注释里的"账号"(`// 模拟前账号瞬态数据` 等)不动 — 与 issue 显示要求无关。

## 影响范围

- **修改文件**(10 个 source + 3 个 test):
  - `macos/Sources/UsageBar/Features/Settings/SettingsView.swift`
  - `macos/Sources/UsageBar/Features/Popover/PopoverView.swift`
  - `macos/Sources/UsageBar/Features/Popover/ProviderTabBar.swift`(`← Back to Claude` 出现 **2 处** L56+L83,确保两处都改)
  - `macos/Sources/UsageBar/Features/Popover/LocalCostCard.swift`
  - `macos/Sources/UsageBar/Features/Popover/UsageHeatmapView.swift`
  - `macos/Sources/UsageBar/Models/UpdateChannel.swift`
  - `macos/Sources/UsageBar/Models/StoredAccount.swift`
  - `macos/Sources/UsageBar/Providers/Gemini/GeminiProvider.swift`(L95+L101、L103+L108、L105+L110 三对重复字符串,确保全 replace 一致)
  - `macos/Sources/UsageBar/Providers/Codex/CodexProvider.swift`
  - `macos/Sources/UsageBar/Providers/Claude/UsageService.swift`(只改 2 处 label 字符串字面量,L352 / L474)
  - 测试 fixture / 断言 3 个文件(见 §D)

- **风险点**:
  - `UsageService.swift` 属于"敏感写入链路"(项目 CLAUDE.md 配置段),但本次只改 2 处 label 字符串字面量,**不动序列化结构 / 不动 OAuth / 不动 token 刷新逻辑**。语义零变化,运行时行为一致。
  - 单元测试若硬编码 "账号 1" 字符串会失败 — 实施前先 grep 测试断言。
  - i18n 后续若要支持多语言,本次纯字面量改动不阻碍后续接 NSLocalizedString。

- **测试计划**:
  - `cd macos && swift build -c release` 通过
  - `cd macos && swift test` 通过(同步改 §D 列出的 4 处测试 label 中文 → 英文)
  - `make app` 后手动起 app,按下表逐态回归(每条覆盖一条新文案的触发路径):

| 视图 / 状态 | 触发路径 | 期望看到的英文文案 |
|---|---|---|
| Menubar + 默认 popover | 启动 app,有 Claude 凭证 | (普通进入,无新文案,但确认主路径无中文残留) |
| Popover 空态 | 临时禁用所有 provider | "No providers enabled" / "Enable at least one provider in Settings." / "Open Settings" 按钮 |
| Popover Claude 未登录 | 删 `credentials.json` 重启 | "Not signed in" / "Sign in with the Claude CLI, then tap Retry." / "Retry" 按钮 |
| ProviderTabBar 占位 tab | 切到尚未注册的 provider(如 .codex 卡占位 — v0.2.5 路径) | "{name} coming soon" / "← Back to Claude" |
| ProviderTabBar 未配置 tab | 切到 Codex 但删 `~/.codex/auth.json` | "Codex not signed in" / "Run \`codex\` in your terminal, then come back." / "← Back to Claude" |
| ProviderTabBar 未配置 tab (其他) | Gemini tab + 删 `~/.gemini/oauth_creds.json` | "Gemini not signed in" / "Sign in via the Gemini CLI / app." |
| Settings | 打开 Settings | "Updates" section / "Channel" picker / picker options "Stable" "Beta" / "Beta includes pre-release builds for testing." / 移除 L44 原中文长行 |
| LocalCostCard footnote A | 删 `~/.config/usage-bar/pricing.json` / 触发 `isLoaded == false` | "Pricing data unavailable." |
| LocalCostCard footnote B | 跑出不在定价表的 model 调用 | "{N} call(s) without pricing data" + 隐私行 "ⓘ Usage fields only; conversations are not read." |
| Heatmap loading | 清 history cache 重启,trigger 初始化 | "Loading…" + spinner |
| UpdateChannel Picker 切 Beta | Settings → Updates Picker → Beta | Picker selected text "Beta",下方一句话 |
| Gemini 5 种 error | 5 种场景手工触发(无凭证/cli未装/token过期/无 project/拉取失败) | 5 条英文 error 串(若 5 种场景成本太高,至少覆盖"无凭证"+"凭证过期"两条最常见) |
| Codex 3 种 error | 同上(无凭证/凭证过期/拉取失败) | 3 条英文 error 串(至少覆盖前两条) |
| 新账号 label | Claude sign in 流程触发首次 sign-in 或新增第二账号 | accounts.json 里 label = "Account 1" / "Account 2" |

## 守护线自检

> 逐项对照 `docs/agents/operations.md` §2 "守护线 checklist"。

- [x] 不触碰凭证 / 密钥链路:OAuth token 刷新、`credentials.json` 格式、Sparkle 私钥、`SU_FEED_URL` 注入逻辑 — **本 PR 只改字符串字面量,不动序列化结构与 token/refresh 逻辑**;`UsageService.swift` 与 `StoredAccount.swift` 内的改动仅限 `label:` 默认值的英文化,属于展示层
- [x] 不引入新第三方依赖、不改 `LICENSE`、不改变开源 / 收费定位
- [x] 不修改已 `accepted` 的 ADR、不修改 `AGENTS.md` / 母法 spec
- [x] 不在 `UsageService` 之外重复 fetch / auth / 轮询逻辑
- [x] 不手改 `Info.plist` 里的版本号
- [ ] **单 issue 影响面 / 文件数 ≤ 5** — **触发**:本 PR 改动 9 个文件,超过 5 文件指引上限。**但**:
  - 9 个文件**全部在 app 代码一个大块内**(不跨"发版链路 / 治理文档")
  - 所有改动都是**同质化的字符串字面量替换**(找一个改一个),非逻辑/结构变更
  - 是"翻译全部 UI 文案"任务的天然性质 — 拆分会让一次完整的 UI 文案审阅被拆成多个 PR,反而增加碎片化噪音

> 该项虽超指标但属"同质改动天然多文件",请评审者特别审视:是否同意走单 PR(推荐)、还是要求按"Settings/Popover/Providers"拆 3 个 PR。

## 是否需要人工介入

- **结论**:**NO**
- **理由**:
  1. 不触发 AGENTS.md §6 任一 hard gate(无凭证/依赖/法律/版本/ADR 冲突)
  2. 守护线只有"文件数 > 5"这一项超指标,但同质化天然多文件,不算实质风险
  3. UI 文案翻译 + 简化是 AGENTS.md `feedback_autonomous_decisions` memory 明确记录的"AI 自决"范围
- 若评审 subagent 认为应拆 PR,听评审建议
