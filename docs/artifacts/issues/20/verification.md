# 验证记录

## 命令 / 步骤

```bash
cd macos && swift build -c release
cd macos && swift test
```

## 结果

- `swift build -c release`：✅ Build complete (10.37s)，0 errors
- `swift test`：✅ 265 tests passed, 0 failures

## 本地验证清单

- [x] 构建：`swift build -c release` 绿
- [x] 单测：`swift test` 265/265 通过
- [ ] 手动回归（待 `make app` 后验证）：
  - [ ] 未认证状态：显示「未检测到有效的授权凭证」提示 + 重新检测按钮 + Settings 入口
  - [ ] 已认证状态：正常用量区，无 Sign Out 按钮
  - [ ] AccountSwitcherView：移除「添加账号...」后多账号用户仍可切换

## 变更文件

| 文件 | 变更 |
|------|------|
| `PopoverView.swift` | 移除 SetupView/signInView/CodeEntryView 路由；新增 notAuthenticatedView；删 Sign Out 按钮；删 SetupView/CodeEntryView/SetupThresholdSlider 私有结构体 |
| `AccountSwitcherView.swift` | 移除「添加账号...」菜单项及 Divider |
| `UsageBarApp.swift` | 删除 setupComplete 孤儿写入块 |

## CI
- (PR 的 checks 状态由 ship/merge 阶段记录)
