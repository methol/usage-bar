# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

> 上面一行用 Claude Code 的 `@import` 语法把 [`AGENTS.md`](./AGENTS.md) 完整加载为上下文。
> 本文件只保留 Claude Code 高频用到的**技术坑与实操命令**；项目治理 / 版本路线 / review gate 等
> 全部在 `AGENTS.md`，避免两边维护漂移。

## Repo at a glance

A macOS menu bar app (SwiftUI + Swift Charts) that displays Claude API usage. The Swift package and all build scripts live under `macos/`; root-level `Makefile` is the canonical entry point and wraps `macos/scripts/build.sh` (bundle .app, embed Sparkle, ad-hoc codesign).

Targets macOS 14+, Swift 5.9. The only runtime third-party dependency is [Sparkle](https://sparkle-project.org) 2.8.1, pinned exact in `macos/Package.swift`.

## Common commands

All `make` targets are run from the repo root. Plain `swift` commands must be run from `macos/` because that is where `Package.swift` lives.

```sh
make build              # swift build -c release (cd macos)
make app                # build + bundle .app (Info.plist, assets, Sparkle, codesign)
make zip                # app + zip + verify-release
make dmg                # app + DMG (downloads create-dmg v1.2.3) + verify-release
make release-artifacts  # build once, produce both zip and dmg, verify both
make install            # build + copy bundle into /Applications
make clean              # swift package clean + delete bundle/zip/dmg

# Tests (must cd into macos/)
cd macos && swift test
cd macos && swift test --filter UsageServiceTests
cd macos && swift test --filter UsageServiceTests/testBackoffIntervalCapsAtSixtyMinutes
```

CI (`.github/workflows/build.yml`) runs `swift build -c release`, `swift test`, then `make release-artifacts` on every push/PR to `main`. Keep both `swift test` and `make release-artifacts` green.

## Architecture — what spans files

The big picture cannot be inferred from any single file. Key invariants:

- **`UsageService` is the single source of truth for API state.** It owns OAuth (PKCE + browser callback paste), token refresh, polling timer, and exponential backoff. Other types receive it via `@StateObject` injection from `UsageBarApp` and read published properties — do not duplicate fetch/auth logic elsewhere. See `UsageService.swift:1-100`.
- **Three injected services compose the app**, wired in `UsageBarApp.swift`: `UsageService` (API), `UsageHistoryService` (in-memory ring buffer flushed to disk every 5 min and on `willTerminate`; 30-day retention), `NotificationService` (threshold notifications), `AppUpdater` (Sparkle wrapper). `UsageService` holds weak-ish references to history/notification services so its polling loop can push samples and fire alerts.
- **Token & history live on disk under `~/.config/usage-bar/`**: `credentials.json` (0600, contains access+refresh+expiry+scopes; falls back to legacy plaintext `token` file if present — see `StoredCredentials.swift`) and `history.json`. The legacy `token` file is deleted on first save of the new format.
- **Bundle creation is custom, not stock SwiftPM.** `macos/scripts/build.sh` runs `swift build -c release`, then hand-assembles `.app/Contents/{MacOS,Resources,Frameworks}`, copies the SwiftPM resource bundle (`UsageBar_UsageBar.bundle`), compiles `Resources/Assets.xcassets` with `actool`, and embeds `Sparkle.framework`. Adding new bundled resources requires they land in the SwiftPM resource bundle (declared in `Package.swift` `resources: [.process("Resources")]`), and any new `.app/Contents/Resources/...` invariants must also be enforced in `macos/scripts/verify-release.sh`.
- **Sparkle is gated by `SU_FEED_URL` at build time.** If the env var is unset (the default for local builds), `build.sh` strips `SUFeedURL` from `Info.plist`, leaving the updater inert. Release CI injects the feed URL. Do not hardcode the feed URL in `Info.plist`.
- **Releases are tag-driven.** Pushing a `v*` tag triggers the release workflow which builds once, produces ZIP (Sparkle) + DMG (manual install), verifies both artifacts, generates a signed Sparkle `appcast.xml` from the ZIP, and deploys to GitHub Pages. Requires `SPARKLE_PRIVATE_KEY` repo secret. `Info.plist` 中的 `CFBundleShortVersionString` / `CFBundleVersion` 在 build 时由 `APP_VERSION` 环境变量或 git tag 注入；plist 里写死的 `1.0.0` 是历史占位，不要手改。

## Mock server gotcha

`scripts/mock-server.py` only mocks `GET /api/oauth/usage`. To point the app at it you must temporarily edit `UsageService.swift`'s `defaultUsageEndpoint` AND add `NSAppTransportSecurity > NSAllowsLocalNetworking` to `macos/Resources/Info.plist`. **Both edits must be reverted before committing** — they are not behind a debug flag. The mock server does not implement the OAuth flow, so an existing valid token in `~/.config/usage-bar/credentials.json` is required.

## Style & dependencies

- Keep third-party dependencies minimal — Sparkle is the only runtime dep, and adding another requires updating `Package.swift`, `verify-release.sh` (if it ships in the bundle), and the `build.sh` framework-bundling step.
- One primary SwiftUI view per file (existing convention: `PopoverView.swift`, `SettingsView.swift`, `UsageChartView.swift`).
- All UI-touching service classes are `@MainActor`; keep that annotation when extending them.
