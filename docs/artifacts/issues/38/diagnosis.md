# Issue #38 诊断

- 链接:https://github.com/methol/usage-bar/issues/38
- 标题:[bug] 每次都弹出keychain的授权

## 复现与定位

现象:用户已在 Keychain 授权框点过 "Always Allow",但后续仍每次弹出"UsageBar 想要访问钥匙串"授权框。

定位到的事实链:

1. UsageBar 读取的是 **Claude CLI 拥有的** Keychain 条目 `Claude Code-credentials`(`kSecClassGenericPassword`),见 `macos/Sources/UsageBar/Providers/Claude/ClaudeCLICredentialsStrategy.swift:6,52-56`。跨 app 读取**自己不拥有**的条目,macOS 必弹 ACL 授权框,除非请求方已在该条目的 ACL 信任列表里。

2. UsageBar 当前是 **ad-hoc 签名**(`macos/scripts/build.sh:174-182` 全部 `codesign --force --sign -`)。实测已安装 app:

   ```
   $ codesign -dvvv /Applications/UsageBar.app
   Signature=adhoc
   CodeDirectory ... flags=0x2(adhoc)
   TeamIdentifier=not set
   Internal requirements count=0 size=12
   ```

   `Internal requirements count=0` —— 没有内嵌 designated requirement。

3. v0.5.1 起 Claude 凭证改 **in-memory only**(`UsageService.swift:24` 注释、`docs/versions/v0.5.1-claude-credentials-in-memory.md`),不再落盘。启动期 `UsageBarApp.swift:50` 每次都调 `retrySignIn()` → `ensureFreshCredentials(allowInteraction: true)` → 走可弹框的 Keychain 读取路径(`ClaudeCLICredentialsStrategy.loadCredentials(allowInteraction:true)`)。

## 根因

Keychain 的 "Always Allow" 把请求方 app 写进条目 ACL 的"受信任应用"列表,而这条记录是**绑定到 app 的代码签名身份**的。UsageBar 是 ad-hoc 签名、`TeamIdentifier=not set`、无 designated requirement,身份不稳定:

- **每次 Sparkle 自动更新都换二进制 → cdhash 变 → ACL 记录失配 → 重新弹框。** 本项目发版频繁(近期 v0.5.1→v0.7.0)且默认开自动更新,这是确定性触发路径。
- ad-hoc 签名的 app 在 macOS Keychain 里**无法形成稳定可持久化的信任身份**,"Always Allow" 难以可靠生效。

v0.5.1 的 in-memory-only 改动把"读 Keychain"从"偶发"放大成"每次启动 + 每次 token 过期",于是这个本就不稳的 ACL 授权被高频暴露 —— 但**它不是根因,根因是 ad-hoc 签名**。v0.5.1 文档 `升级路径` 一节本身就假设了"点 Always Allow 即可",而该假设对 ad-hoc 签名不成立。

## 修复方案

无法在"issue 驱动小修"范围内根治。三个候选(详见"是否需要人工介入"):

- **A. 正式签名 + 公证**:申请 Apple Developer 账号,用 Developer ID Application 证书签名并公证。designated requirement 稳定后,"Always Allow" 可跨更新持久生效。—— 根治方案,但需付费 + 凭证操作。
- **B. UsageBar 自缓存 access token 到自己拥有的 Keychain 条目**:把弹框频率从"每次启动"降到"token 轮换时"。—— 缓解,非根治;且与 v0.5.1 spec"不持久化 Claude 凭证"冲突,需修订 spec。
- **C. 接受现状**:文档化为 ad-hoc 分发的已知限制,issue 记为 known-limitation。

## 决策(人工)

经 hard gate 升级,用户(2026-05-16)选择 **方案 C — 接受现状**:不改代码、不根治,将其文档化为 ad-hoc 分发的已知限制。后续若要根治(方案 A 正式签名公证)另起流程。

## 影响范围

- 修改文件:`README.md` —— 新增 `## Known limitations` 一节,说明 ad-hoc 签名导致 Keychain 授权框反复出现。仅 1 个文件、纯文档。
- 风险点:无(纯文档)。
- 测试计划:G4 文档 commit —— linkcheck + 人工核对措辞;无代码改动,不跑 `swift build` / `swift test`。

## 守护线自检
> 逐项对照 `docs/agents/operations.md` §2 "守护线 checklist"。

- [x] **触碰凭证 / 密钥链路** —— 命中。根治方案 A 需 Apple Developer 账号 / 签名证书(AGENTS.md §6.1 hard gate #1);方案 B 触碰凭证存储链路。
- [ ] 不引入新第三方依赖、不改 LICENSE、不改开源/收费定位 —— 未命中。
- [x] **不修改已 accepted 的 spec** —— 方案 B 需修订 v0.5.1 spec `2026-05-14-claude-credentials-in-memory`,命中。
- [ ] 不在 UsageService 之外重复 fetch/auth/轮询 —— 未命中。
- [ ] 不手改 Info.plist 版本号 —— 未命中。
- [x] **单 issue 影响面不跨三大块且文件数 ≤ 5** —— 方案 A 跨"app 代码 / 发版链路",命中(超出 issue 驱动小修边界)。

## 是否需要人工介入

- 结论:**YES**
- 理由:
  1. 根治方案 A 需申请并配置 **Apple Developer 账号 / 签名证书**,属 AGENTS.md §6.1 hard gate #1(凭证/密钥操作),且涉及付费决策,必须人类拍板。
  2. 缓解方案 B 需**修订已 accepted 的 v0.5.1 spec**,超出 issue 驱动流程范围,应走 spec/ADR gate。
  3. 三个方案是"付费根治 / 改架构缓解 / 接受现状"三类语义不同的取舍,无明显唯一推荐项,需人类选择方向后再决定后续走 issue 驱动还是 spec 流程。
