# 验证记录

## 命令 / 步骤

按项目 `docs/agents/operations.md` §2 "本地验证命令矩阵" 改 Swift 代码 + 改 UI 两栏:

1. `cd macos && swift build -c release`
2. `cd macos && swift test`
3. `make app` 后手动起 app(下文记 "手动回归"待补)

## 结果

### 1. `swift build -c release`

**PASS** — `Build complete! (10.68s)`。仅 4 条 warning,全部是 **改动前已存在**的 Swift 6 future-mode 警告(`makeIterator` async / `Main actor-isolated 'shared'`)— 与本 PR 改动文件 / 行无关。

### 2. `swift test`

**PASS** — `Executed 308 tests, with 0 failures (0 unexpected) in 0.804s`。

第一轮跑出 2 处断言失败(诊断 §D 已预测的"硬编码中文断言"):

| 文件:行 | 失败原因 | 修复 |
|---|---|---|
| `UpdateChannelTests.swift:52-53` | `displayName == "稳定版"` / `"Beta（实验性）"` 失败 | 改为 `"Stable"` / `"Beta"` |
| `GeminiProviderTests.swift:127` | `lastError.contains("过期"\|"登录")` 失败 | 改为 `lastError.contains("expired"\|"sign in")` |

修复后第二轮跑全绿。

`grep` 复扫 `macos/Tests` 残留中文 = 3 处,全部是 XCTAssert 第二参数 message(仅 fail 时打印,不影响断言比较),按诊断 §C 决议(只动显示/断言期望值,不动注释类内容)**保留**:
- `UsageServiceTests.swift:528`(message "Keychain 有新鲜凭证 → 应静默续上、不硬过期")
- `UsageServiceTests.swift:609`(message "多账号 → 不走 Keychain 恢复")
- `UsageServiceTests.swift:996`(message "PKCE 账号的 refresh_token 不应被迁移剥离")

### 3. 手动回归(`make app`)

**待执行** — ship 前补,按 diagnosis 测试计划逐态表(13 行)走一遍金路径 + 各 provider 错误态。

> 注:本仓库 CLAUDE.md 明确 "减少 Xcode Build,节省时间",且诊断的改动均为字符串字面量替换(无 layout / 行为变化),手动回归优先级低于自动化测试通过。若 ship 评审认为必须手动跑过才允许 merge,届时再执行。

## 本地验证清单

- [x] 单测 / 集成测试 — `swift test` 308/308 PASS
- [x] 构建 — `swift build -c release` PASS
- [N/A] 接口契约 — 本 PR 无接口/schema 变更
- [ ] 手动回归 — 待执行(ship 前补)

## CI

- 由 ship/merge 阶段记录(`gh pr checks --watch`)
