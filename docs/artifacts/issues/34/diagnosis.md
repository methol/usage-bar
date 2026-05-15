# Issue #34 诊断（修订版 v2）

- 链接: https://github.com/methol/usage-bar/issues/34
- 标题: [feat] 首次启动，自动检测当前用户安装的AI工具

## 复现与定位

`ProviderCoordinator.init()` 在 `enabledProvidersKey` 从未写过时（= 首次启动）直接默认
`enabled = Set(ProviderID.allCases)`，且 `menuBarVisibleProviderIDs` 的 fallback 同样为
`Set(ProviderID.allCases)`。两处均未感知"工具是否已安装"，导致首次启动全部 provider 都
开启并出现在菜单栏。

## 根因

首次启动两处 fallback 默认值未区分"用户已安装工具"与"未安装"。

## 修复方案（修订 v2）

**文件清单：**
- 新建 `Services/AIToolDetector.swift`
- 修改 `Services/ProviderCoordinator.swift`
- 修改 `Tests/UsageBarTests/ProviderCoordinatorTests.swift`（更新受影响断言）
- 新建 `Tests/UsageBarTests/AIToolDetectorTests.swift`

### AIToolDetector 设计

纯文件系统检测（同步，无网络/进程），注入 `fileManager` 和 `environment` 以便测试。

> 为何不用 `provider.isConfigured`：该属性是**运行时状态**（ProviderRuntime 默认
> `isConfigured = false`，只有 `refreshNow()` 成功后才变 `true`），在 `init()` 时始终
> 为 `false`，不适合作为安装检测信号。

| ProviderID | 检测信号 |
|---|---|
| claude | `~/.claude/` 存在 OR `/Applications/Claude.app` 存在 |
| codex | `$CODEX_HOME/` 或 `~/.codex/` 目录存在（与 `CodexCredentialStore` 路径一致）|
| gemini | `$GEMINI_HOME/` 或 `~/.gemini/` 目录存在（与 `GeminiCredentialStore` 路径一致）|
| cursor | `/Applications/Cursor.app` 存在 |
| copilot | `~/.config/github-copilot/` 目录存在 |

API: `static func detect(fileManager:environment:) -> Set<ProviderID>`

### ProviderCoordinator 修改

在 `init()` 里，两处 fallback（`enabled` 和 `menuBarVisible`）统一改为：

```swift
// 首次启动检测（key 未写过时才用；结果为空 fallback 全启用防 UI 空白）
let detectedOnFirstLaunch: Set<ProviderID> = {
    let d = AIToolDetector.detect()
    return d.isEmpty ? Set(ProviderID.allCases) : d
}()
```

`enabled` 和 `menuBarVisible` 的 else 分支都使用 `detectedOnFirstLaunch`。
`detectedOnFirstLaunch` 在 init 时始终计算（5 次 stat 调用，忽略不计），避免条件分支复杂度。

### 测试更新

1. `AIToolDetectorTests.swift`：
   - 每个 provider 的检测信号正向测试（创建临时目录/文件 → 验证 detect() 包含该 ID）
   - 空检测结果（无任何工具目录）→ `detect()` 返回空集
   - 注入 `CODEX_HOME` / `GEMINI_HOME` environment override

2. `ProviderCoordinatorTests.swift` 更新：
   - `testDefaultOrderAndEnabled`：当 key 未存盘时，enabled 取决于检测结果而非全集；
     改用 mock defaults（key 已存盘）测试读盘路径，或注入不含任何工具目录的
     fileManager 验证 fallback
   - `testMenuBarVisibleDefaultsToAllCases`：同上处理
   - 新增：`testFirstLaunchDetectsInstalledProviders`——注入含 codex 目录的环境，
     验证 `enabledProviderIDs` 和 `menuBarVisibleProviderIDs` 均只含 `.codex`

## 影响范围

- 修改文件数: 4（≤ 5 限制内）
- 风险: 极低。现有用户 `enabledProvidersKey` 已存盘，不受影响；新用户首次启动行为改善
- 守护线: 全通过（下方自检）

## 守护线自检

- [x] 不触碰凭证 / 密钥链路：仅文件存在检测，不读取凭证内容
- [x] 不引入新第三方依赖：纯 Foundation/FileManager
- [x] 不修改 `docs/adr/` / `AGENTS.md` / 母法 spec
- [x] 不在 `UsageService` 之外重复 fetch / auth / 轮询逻辑
- [x] 不手改 `Info.plist` 版本号
- [x] 影响面 ≤ 5 文件，不跨三大块

## 是否需要人工介入

- 结论: NO
- 理由: 守护线全通过，方案简单，影响面小
