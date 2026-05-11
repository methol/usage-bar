# Runbook — Apple Notarization

> ⚠️ **Placeholder**：v0.2.1 落地时填充。当前仍为 ad-hoc 签名，详见 `macos/scripts/build.sh`。

## 适用范围

自 v0.2.1 起所有正式 release。

## 计划内容（v0.2.1 spec 落地时撰写）

- Apple Developer ID Application 证书获取与本地配置
- `codesign --sign "Developer ID Application: <id>"` + Hardened Runtime entitlements 锁定
- `notarytool submit --wait` 公证流程
- `stapler staple` 卡片附着
- CI 中 secrets 管理（`AC_USERNAME` / `AC_TEAM_ID` / `AC_PASSWORD` 或 `notarytool` API key JSON）
- 公证失败时常见原因与诊断（`spctl --assess` / `codesign -dv --entitlements -`）

## Hard gate

⚠️ 本 runbook 涉及人类持有的凭证（Apple Developer 账号、私钥），不可由 AI 单独完成。

## 引用

- 母法：[`../superpowers/specs/2026-05-11-docs-governance.md`](../superpowers/specs/2026-05-11-docs-governance.md) §4.6
- 版本：[`../versions/v0.2.1-apple-notarization.md`](../versions/v0.2.1-apple-notarization.md)
