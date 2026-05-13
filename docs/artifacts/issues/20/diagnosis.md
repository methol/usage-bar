# Issue #20 诊断

- 链接：https://github.com/methol/usage-bar/issues/20
- 标题：[feat] 移除 sign out 和 sign in 的功能

## 复现与定位

用户要求：数据来源只从本地已授权的 Claude CLI 凭证读取，不在 app 内提供 OAuth 登录/登出入口。

当前 UI 中存在以下需移除的入口：

1. **`PopoverView.signInView`**：未登录时显示"Sign in with Claude"按钮，调用 `claude.startOAuthFlow()`。
2. **`PopoverView` body 的 SetupView 路由**：首次启动且未登录时显示 `SetupView`（含通知配置 + 轮询间隔 + 让用户登录）。
3. **`PopoverView` body 的 CodeEntryView 路由**：`isAwaitingCode` 时显示 OAuth 授权码输入框。
4. **`PopoverView.bottomBar` 中的"Sign Out"按钮**：调用 `claude.signOut()`。
5. **`AccountSwitcherView` 中的"添加账号..."按钮**：调用 `service.beginAddAccount()`（触发 OAuth 多账号添加流程）。

## 根因

app 原来设计为支持 OAuth 自带登录，但用户现在希望只依赖本地凭证（Claude CLI 的 `~/.config/usage-bar/credentials.json`），不在 app 内管理登录态。

## 修复方案

### PopoverView.swift

- 移除 `@AppStorage("setupComplete")` 和相关路由逻辑（SetupView 路由、CodeEntryView 路由）。
- body 路由简化为：已认证 → 正常用量区；未认证 → 新建 `notAuthenticatedView`（只提示通过 CLI 授权，无 OAuth 按钮，有"重新检测"按钮调 `bootstrapFromCLIIfNeeded()`）。
- 移除 bottomBar 中的"Sign Out"按钮。
- 移除 `private var signInView`。
- 移除 `private struct SetupView`（包含 `SetupThresholdSlider`、首次配置 UI 等——Settings 里已有等价功能）。

### AccountSwitcherView.swift

- 移除"添加账号..."菜单项及其前的 `Divider()`。
- 保留账号切换功能（用于 Claude CLI 多配置文件场景，账号已在本地）。

## 影响范围

- 修改文件（2 个）：
  - `macos/Sources/UsageBar/PopoverView.swift`
  - `macos/Sources/UsageBar/AccountSwitcherView.swift`
- 风险点：
  - 底层 OAuth token 自动刷新逻辑（`UsageService.refreshToken()`）完全不受影响——只移除 UI 触点，不动 `UsageService` 本身。
  - 移除 `SetupView` 后首次用户体验变化：不再有首次引导页，直接显示"未认证"提示；Settings 提供等价配置。
  - 用户无法通过 app 登出，但可通过 Claude CLI 或直接删除凭证文件登出。
- 测试计划：`swift build -c release` + `swift test` + `make app` 后手动验证未认证状态 UI。

## 守护线自检

- [x] 不触碰凭证/密钥链路（OAuth token 刷新、credentials.json 格式、Sparkle 私钥、SU_FEED_URL）—— ✅ 只移除 UI 触点，`UsageService` 内部刷新链路不变
- [x] 不引入新第三方依赖，不改 LICENSE —— ✅ 无
- [x] 不修改 docs/adr/ 下已 accepted 的 ADR，不修改 AGENTS.md 或母法 spec —— ✅ 无
- [x] 不在 UsageService 之外重复 fetch/auth/轮询逻辑 —— ✅ 无（只删 UI）
- [x] 不手改 Info.plist 里的版本号 —— ✅ 无
- [x] 单 issue 影响面不跨"app 代码/发版链路/治理文档"三大块，改动文件数大致 ≤ 5 —— ✅ 2 个文件，纯 UI 层

## 是否需要人工介入

- 结论：NO
- 理由：守护线全部通过。虽然触及"OAuth token 刷新"相关文件（PopoverView），但改动仅为移除 UI 入口，底层 `UsageService` 刷新逻辑完全不变。
