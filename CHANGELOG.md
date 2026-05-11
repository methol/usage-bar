# Changelog

本仓库的用户视角变更记录。由 AI 在发版 runbook 自动维护（详见 [`docs/runbooks/release.md`](./docs/runbooks/release.md) §5）。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

> 自 v0.0.7 起，本仓库与上游 `Blimp-Labs/claude-usage-bar` 独立编号 — 见 [ADR 0004](./docs/adr/0004-fork-divergence-from-blimp-labs.md)。
> v0.0.6 及之前的历史由上游维护，不在本 CHANGELOG 范围内。

---

## [v0.1.1] — 2026-05-11

### 新增（Added）

- **Claude CLI 凭证零配置登录**：已装 Claude Code CLI 的用户首次启动 app 自动复用 OAuth 凭证（macOS Keychain `Claude Code-credentials`），无需走 PKCE 浏览器流程
- 首次启动会弹出"允许 ClaudeUsageBar 访问 Claude Code-credentials"提示；选"始终允许"后续启动免提示
- 拒绝 / 取消 / 未装 Claude CLI 时静默降级走原 sign-in 流程，行为与 v0.1.0 一致
- 已 sign-in 用户不受影响（不覆盖已有 credentials.json）

### 内部（Internal）

- 新增 `ClaudeUsageStrategy` protocol 骨架（单方法 `loadCredentials() async throws -> StoredCredentials?`），为后续 v0.1.2 本地 cost 扫描 / v0.1.3 多账号 / v0.2.3 cookie 回退 / v0.2.4 CLI PTY 兜底等多数据源 spec 预留扩展点
- 新增 `ClaudeCLICredentialsStrategy` 实现：`SecItemCopyMatching` 读 Keychain（kSecAttrService + kSecAttrAccount=NSUserName()）+ Task.detached 避免主线程阻塞 + 4 种"权限/不存在" OSStatus 静默降级 + JSON schema decode
- `UsageService.bootstrapFromCLIIfNeeded()` @MainActor async：启动期一次性尝试，不破坏现有 OAuth / refresh / polling 流程
- `ClaudeUsageBarApp.task` 启动序列调整：bootstrap 后再判 setupComplete，bootstrap 成功用户跳过 SetupView
- 新增 6 case 单测：valid decode / missing oauth / missing accessToken / nil 字段 / ms→s 转换 / LoadError 脱敏；总数 78 → 84

### 安全 / 隐私（Security）

- **永久安全约束 SC7**（事故警示，源自 v0.1.1 设计阶段真实 token 泄漏事故，已立即轮换）：
  - 源代码与测试中**禁止 print / NSLog / os_log / Logger 输出 credentials 任何字段**
  - 错误日志只记录 "credentials parse failed: <error type>" 不带 raw value
  - LoadError 实现 CustomStringConvertible 仅输出 case 名（不带 OSStatus 数值）
  - Swift Testing 断言禁止对 token 字段做字面比较（用 hasPrefix / count / nil-ness）
  - 测试 mock 用 'mock-' 前缀，禁止 'sk-ant-' 真实前缀
- 自动化双守护：`SC_AUTO_NO_PRINT_TOKENS`（Sources/ grep print/log×token 字段）+ `SC_AUTO_NO_REAL_TOKEN_PREFIX`（全仓 grep `sk-ant-(oat|ort|api)[0-9]` 真 token 前缀）

### 参考

- 版本计划：[`docs/versions/v0.1.1-claude-cli-credentials.md`](./docs/versions/v0.1.1-claude-cli-credentials.md)
- 含 spec：`2026-05-11-claude-cli-credentials`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.1.0] — 2026-05-11 — Phase 1 milestone（逻辑标记）

> **注**：本版本无新功能、无新代码、无 binary release、无 Sparkle 自动更新。
> 仅作为 "Phase 1 完成"的逻辑里程碑标记，由用户决策"不打 tag"。完整 G7 发版（Apple 公证 + Sparkle 推送）留待后续 v0.x 阶段处理。

### 聚合（aggregated from v0.0.7~v0.0.11）

Phase 1 阶段性体验目标"看起来像 SessionWatcher 了"已达成：

- 📚 **v0.0.7**：文档治理框架立项（ADR / spec / version / runbook / user-guide 六大目录 + AGENTS.md / 7 review gate / 跨模型 reviewer 矩阵）
- 🎨 **v0.0.8**：PopoverView hero 重做（5h hero 56pt 大字号 + 7d secondary 28pt + capsule 进度条 + reset countdown 紧凑格式）
- 🎨 **v0.0.9**：6h 趋势箭头 ▲▼ + 增量百分点（基于现有 history.json）
- 🎨 **v0.0.10**：菜单栏多显示模式（icon / percent / percent+trend）可在 Settings 切换
- 🎨 **v0.0.11**：5h 配速指示器（On pace / In deficit + Runs out / In reserve）

### 工程指标

- 累计 78 个 swift test，全 0 failures
- 5 个 spec 共 60 个 spec_criteria 全数 done，每版本走完 G2 / G3 / G5 / G6 四轮独立 reviewer review
- 21 个原子 commit（见 `git log`），所有视觉变更独立可 revert
- 仅 Sparkle 一个第三方运行时依赖，无新增

### 后续

Phase 2（v0.1.x）将引入数据源多路径（Claude CLI 凭证复用 / 本地 JSONL cost 扫描 / 多账号），追上 CodexBar 的功能广度。

### 参考

- 版本计划：[`docs/versions/v0.1.0-phase1-milestone.md`](./docs/versions/v0.1.0-phase1-milestone.md)
- 含 spec：聚合 v0.0.7~v0.0.11

---

## [v0.0.11] — 2026-05-11

### 新增（Added）

- **5h 配速指示器**：参考 CodexBar，hero card 进度条下方现可显示当前 5 小时窗口的配速状态
  - **N% over pace · runs out in 1h 23m**（红）— 当前速率会在 reset 前用完，给出预计耗尽时间
  - **N% under pace**（绿）— 用量比预期慢，有余量
  - **On pace** 默认不显示，避免打扰
- 早期窗口（开窗 < 3%）静默不显示，避免噪声抖动
- reset 已过容错降级为 on pace（避免显示历史窗口的"in reserve"误导）
- 7d 窗口不显示 pace（线性外推假设过强；调研 §2.7 同款决策）
- 不引入 ML 等营销话术；纯线性外推（current_rate × remaining_pct）

### 内部（Internal）

- 新增 `PaceCalculator.swift`：`enum PaceState { onPace / inDeficit / inReserve }` + 顶层 `computePaceState(currentPct:resetDate:windowDuration:now:)` 纯函数
- 新增 `PaceCalculatorTests` 9 case：happy 三态 + 边界（早期窗口隐藏 / nil 容错 / reset 已过 / currentPct=100 / runs out 数学边界附数学推导注释）
- `UsageHeroCard` 接口加可选 `pace` 参数（默认 nil，不破坏 v0.0.8/9/10 现有 call site），#Preview 升级 4 张示例覆盖 4 种 pace 状态
- `PopoverView` usageView 计算 pace5h 传入 5h hero card；7d 不传 pace
- spec 走完 G2 / G3 / G5 / G6 共四轮独立 reviewer review；G2 独立命中 reset 已过路径误导 bug + currentPct=100 edge case；G5 命中 paceText 双 Date() 时钟竞争
- commit 拆分（spec / Calculator+测试 / hero card+popover / G5 修订 / G6 收尾）

### 参考

- 版本计划：[`docs/versions/v0.0.11-pace-tracking.md`](./docs/versions/v0.0.11-pace-tracking.md)
- 含 spec：`2026-05-11-pace-tracking`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.0.10] — 2026-05-11

### 新增（Added）

- **菜单栏多显示模式**：Settings → General → Menubar Display 可切换 3 种显示风格
  - `Icon`（默认）：双窗口进度条图标（保持现状）
  - `Percent text`：紧凑文本如 `5h 42%`
  - `Percent + trend`：在百分比旁叠加 ▲/▼ 趋势（如 `5h 42% ▼5`，需 ≥6h history）
- 切换模式实时生效（@AppStorage 跨视图同步），不需重启 app
- 默认仍是 Icon 模式 — 升级用户菜单栏视觉无变化

### 改进（Changed）

- 复用 v0.0.9 趋势算法（`computeTrend`）：trend mode 与 hero card 同源、单位约定一致

### 内部（Internal）

- 新增 `MenuBarDisplayMode.swift`：enum + `formatMenuBarPercent` helper，9 case 单测覆盖（nil / 边界 / round / roundtrip / 默认值防御 / case 数量防御）
- 新增 `MenuBarLabel.swift`：SwiftUI View 三分支（icon / percent / percent+trend），未登录走 fallback 显示 `5h —`
- `ClaudeUsageBarApp` MenuBarExtra label 替换为 MenuBarLabel；.task 闭包保留（startPolling→scheduleTimer 自带 timer?.invalidate 已幂等，重复执行安全）
- `SettingsView` 加 General section displayMode Picker，与 polling interval 同列
- @AppStorage 直接绑定 enum（SwiftUI 原生 RawRepresentable + RawValue==String 支持），消除 String<->enum 中间映射；G5 review 触发了从 Binding(get:set:) 到直接 $menubarMode 的简化重构
- spec 走完 G2 / G3 / G5 / G6 共四轮独立 reviewer review；commit 拆分（spec / enum+测试 / View+接入 / G5 修订 / G6 收尾）；不动数据层 / OAuth / Notifications / 现有 popover 视觉

### 参考

- 版本计划：[`docs/versions/v0.0.10-menubar-display-modes.md`](./docs/versions/v0.0.10-menubar-display-modes.md)
- 含 spec：`2026-05-11-menubar-display-modes`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.0.9] — 2026-05-11

### 新增（Added）

- **趋势箭头 ▲▼**：5h / 7d hero 卡片 label 旁显示近 6h 趋势，如 `5-Hour ▲ 12%` 表示当前比 6 小时前高 12 个百分点；可一眼看出用量在涨还是在落
- 上升趋势用红色（与现有"高用量为红"心智一致），下降趋势用绿色
- 微小波动（|Δ| < 1 个百分点）视为持平不显示，避免视觉抖动
- 数据不足时不显示（首次启动 / 清缓存后约需 6 小时累积 history）

### 改进（Changed）

- 完全复用既有 30 天 `history.json`（`~/.config/claude-usage-bar/`），不引入新存储

### 内部（Internal）

- 新增 `TrendCalculator.swift` 顶层纯函数 `computeTrend(currentPct:points:metric:lookback:now:)`，含明确的单位约定：currentPct 0-100 / UsageDataPoint.pct5h 0-1，函数内部自动对齐
- 新增 `TrendCalculatorTests` 10 case：方向 / flat / 数据不足 / nil current / .rounded() 边界（1.4→1, 0.9→nil）/ 多 baseline 取最新 / pct7d KeyPath / **显式命名 testUnitConversion**（防御未来 baseline*100 误删）
- `UsageHeroCard` 接口加可选 `trend: TrendIndicator?` 参数（默认 nil，不破坏 v0.0.8 现有 call site），#Preview 升级为含 trend 三档示例
- spec 走完 G2 / G3 / G5 / G6 共四轮独立 reviewer review；G2 review 独立命中并修复了 currentPct 与 pct5h 单位 100x 误差 bug；commit 拆分（spec / Calculator / 接入 / G5 修订 / G6 收尾）

### 参考

- 版本计划：[`docs/versions/v0.0.9-trend-arrows.md`](./docs/versions/v0.0.9-trend-arrows.md)
- 含 spec：`2026-05-11-trend-arrows`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.0.8] — 2026-05-11

### 改进（Changed）

- **Popover 视觉重做**：5h 窗口提升为 hero 卡片（56pt 大字号数字 + 紧凑 reset countdown），7d 窗口降级为 secondary 卡片（28pt 数字）；不再四个窗口平权显示，更易一眼看懂当前最关键的指标
- **进度条改 capsule**：5h / 7d 进度条从默认 SwiftUI ProgressView 改为 Capsule 形状（高度 8pt，圆角与高度匹配），视觉与 hero 字号协调
- **Reset 时间紧凑显示**：原 SwiftUI 默认 `in 1 hour` 风格改为紧凑 `1h 23m` / `12m` / `<1m`，节省 hero 卡片空间；nil 与已过期时不显示
- **Popover 宽度** 340 → 360pt，容纳 hero 数字与 reset 标签
- 配色阈值与现有保持一致：< 60% 绿 / 60-80% 黄 / ≥ 80% 红
- Per-Model（Opus / Sonnet）/ Extra Usage / 历史图表 / 控制行均保留不变；OAuth 与数据层未触

### 内部（Internal）

- 新增 `UsageHeroCard.swift`（含 hero/secondary 两档尺寸 + CapsuleProgressBar 子组件 + Xcode `#Preview` 三档示例）
- 新增 `ResetCountdownFormatter.swift` 纯逻辑函数 + `ResetCountdownFormatterTests`（6 case，覆盖 ≥1h / 仅分钟 / nil / 已过期 / 亚分钟 / 60s 整点边界）
- spec 走完 G2 / G3 / G5 / G6 共四轮独立 reviewer review，每轮 verdict 与作者响应均记入 spec.reviews
- commit 拆分原则：spec 立项 / 底层组件 / PopoverView 接入 / G5 修订 / G6 收尾分离，便于单独 revert

### 参考

- 版本计划：[`docs/versions/v0.0.8-hero-popover.md`](./docs/versions/v0.0.8-hero-popover.md)
- 含 spec：`2026-05-11-hero-popover`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)

---

## [v0.0.7] — 2026-05-11

### 新增（Added）

- **文档治理框架**落地：研究 / 设计 spec / ADR / 版本路线 / 运维 runbook / 用户文档六大目录建立，配套模板与索引
- **AGENTS.md** 治理入口：所有 AI runner 进仓库的中立指南；含 5 分钟上手、文档地图、工作流、工具可用性 preflight、hard gates
- **4 份 ADR**：Swift 原生（0001）、Claude-only 差异化（0002）、AI 主导 + 人类辅助（0003）、与 Blimp-Labs 上游独立分叉（0004）
- **7 个 review gate**：G1~G7 完整覆盖调研、spec、plan、实施、PR、merge、release；含跨模型 / 跨 subagent reviewer 矩阵与不可用时 fallback 路径
- **版本路线 v0.0.7 ~ v1.0.0**：每个版本占位文件含 frontmatter 与 placeholder guardrail
- **v1.0.0 "稳定可用"硬清单**：14 条门槛（性能 / 能源 / 隐私 / a11y / 公证 / Sparkle / 数据源路径 / 测试覆盖率等）
- **CHANGELOG.md** 本文件：从此存在，AI 维护

### 改进（Changed）

- `CLAUDE.md`：顶部新增 governance 跳板指向 AGENTS.md；新增 *Project state* 与 *Before claiming work done* 两节；原技术细节（commands / architecture / mock server gotcha / style）保留不变

### 修复（Fixed）

- *（无代码变更）*

### 安全 / 隐私（Security）

- *（无代码变更，但 ADR 0004 修正了 README 中的发版 URL 指向以避免本仓库发版意外推送到上游 GitHub Pages 的潜在事故）*

### 内部（Internal）

- 业界竞品调研报告归档至 `docs/research/competitive-analysis.md`（含 SessionWatcher / CodexBar / ccusage / Claude-Code-Usage-Monitor 详细分析）
- spec 母法引入 17 条机器可判定的 spec_criteria（SC1~SC17）+ `## Verification log` 区块作为 G6 验收形式
- spec 母法已通过 G2 跨 session 独立 reviewer 审查（5 BLOCKING + 8 RECOMMENDED 全数受理，详见 spec §10 review response）

### 参考

- 版本计划：[`docs/versions/v0.0.7-docs-governance.md`](./docs/versions/v0.0.7-docs-governance.md)
- 含 spec：`2026-05-11-docs-governance`
- 母法：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)
