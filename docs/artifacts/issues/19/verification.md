# 验证记录

## 命令 / 步骤

```bash
cd macos && swift build -c release
cd macos && swift test
```

## 结果

- `swift build -c release`：✅ Build complete (10.54s)，0 errors，若干 Swift 6 future warnings（非本次引入）
- `swift test`：✅ 265 tests passed, 0 failures (0.722s)

## 本地验证清单

- [x] 构建：`swift build -c release` 绿
- [x] 单测：`swift test` 265/265 通过
- [ ] 手动回归（`make app` 后启动 app）：
  - [ ] 拖拽排序：macOS Form 内 .onMove 是否显示拖柄（待 make app 后验证）
  - [ ] 多 provider 菜单栏：Codex 启用时是否并排显示在菜单栏
  - [ ] percent + pace 模式：Settings → Menubar Display 切换后菜单栏显示 pace delta

## 变更文件

| 文件 | 变更 |
|------|------|
| `MenuBarDisplayMode.swift` | 移除 `percentWithTrend`，加 `percentWithPace` |
| `MenuBarLabel.swift` | 删 `historyService`/`showTrend`，加 pace delta 显示逻辑 |
| `MultiMenuBarLabel.swift` | 新建：所有已启用 provider 并排展示 |
| `SettingsView.swift` | 去掉 ↑/↓ 和 ✓ 按钮，加 `.onMove`，更新说明文字 |
| `UsageBarApp.swift` | 改用 `MultiMenuBarLabel`，加 "percentWithTrend" 一次性迁移 |

## CI
- (PR 的 checks 状态由 ship/merge 阶段记录)
