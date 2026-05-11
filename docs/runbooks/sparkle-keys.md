# Runbook — Sparkle Keys

> ⚠️ **Placeholder**：当前 Sparkle 私钥状态见 README.md 的 *Publishing updates* 段。本 runbook 在密钥首次轮换 / 升级 / 异常时填充。

## 适用范围

Sparkle 2.x Ed25519 密钥的：
- 首次生成
- 轮换
- 导出 / 导入
- 异常恢复

## 当前状态

- Sparkle 版本：`2.8.1`（pinned exact in `macos/Package.swift`）
- 公钥位置：`macos/Resources/Info.plist` 的 `SUPublicEDKey`
- 私钥位置：本地 Keychain account `claude-usage-bar`；CI 中以 `SPARKLE_PRIVATE_KEY` secret 注入
- Feed URL（v0.0.7 后）：`https://methol.github.io/usage-bar/appcast.xml`

## Hard gate

⚠️ 本 runbook 涉及私钥操作，**必须人类介入**。AI 仅生成命令模板与 checklist，不可执行密钥导出 / 导入。

## 计划内容

- 首次启用 GitHub Pages + secrets 设置（v0.0.7 发首版前）
- 私钥导出：`macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys --account claude-usage-bar -x /tmp/...key`
- `gh secret set SPARKLE_PRIVATE_KEY < /tmp/...key`
- 失败诊断：appcast 签名验证错误、`Sparkle Updater` 报错

## 引用

- 母法 §8 第 5 条（Sparkle 漏洞 / 升级路径）
- 现有 README.md *Publishing updates* 段（迁移到本 runbook 后该段可删）
