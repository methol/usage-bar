# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Governance**: This repo is AI-led with strict review gates.
> Read [`AGENTS.md`](./AGENTS.md) first — it overrides this file when in conflict.
> Full governance contract: [`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md).

## Project state

- Current tag: forked from Blimp-Labs at `v0.0.6`, now independent — see [ADR 0004](./docs/adr/0004-fork-divergence-from-blimp-labs.md)
- Remote: `github.com/methol/usage-bar` (not the upstream `Blimp-Labs/...`)
- Roadmap & version planning: [`docs/versions/`](./docs/versions/)
- Active design specs: [`docs/superpowers/specs/`](./docs/superpowers/specs/)
- [`CHANGELOG.md`](./CHANGELOG.md) is AI-maintained at release time — don't hand-edit historical entries; the release runbook ([`docs/runbooks/release.md`](./docs/runbooks/release.md) §5) regenerates it
- Info.plist's `CFBundleShortVersionString=1.0.0` is a stale placeholder; the real version is injected from the git tag by `build.sh`

## Before claiming work done

- Run `superpowers:verification-before-completion` before declaring any task complete
- Before opening a PR, run `superpowers:requesting-code-review` (triggers cross-model review; falls back to a `general-purpose` subagent if codex tools are unavailable)
- Full review gate matrix is in [`AGENTS.md`](./AGENTS.md) §4.2 and [`docs/runbooks/release.md`](./docs/runbooks/release.md)

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

- **`UsageService` is the single source of truth for API state.** It owns OAuth (PKCE + browser callback paste), token refresh, polling timer, and exponential backoff. Other types receive it via `@StateObject` injection from `ClaudeUsageBarApp` and read published properties — do not duplicate fetch/auth logic elsewhere. See `UsageService.swift:1-100`.
- **Three injected services compose the app**, wired in `ClaudeUsageBarApp.swift`: `UsageService` (API), `UsageHistoryService` (in-memory ring buffer flushed to disk every 5 min and on `willTerminate`; 30-day retention), `NotificationService` (threshold notifications), `AppUpdater` (Sparkle wrapper). `UsageService` holds weak-ish references to history/notification services so its polling loop can push samples and fire alerts.
- **Token & history live on disk under `~/.config/claude-usage-bar/`**: `credentials.json` (0600, contains access+refresh+expiry+scopes; falls back to legacy plaintext `token` file if present — see `StoredCredentials.swift`) and `history.json`. The legacy `token` file is deleted on first save of the new format.
- **Bundle creation is custom, not stock SwiftPM.** `macos/scripts/build.sh` runs `swift build -c release`, then hand-assembles `.app/Contents/{MacOS,Resources,Frameworks}`, copies the SwiftPM resource bundle (`ClaudeUsageBar_ClaudeUsageBar.bundle`), compiles `Resources/Assets.xcassets` with `actool`, and embeds `Sparkle.framework`. Adding new bundled resources requires they land in the SwiftPM resource bundle (declared in `Package.swift` `resources: [.process("Resources")]`), and any new `.app/Contents/Resources/...` invariants must also be enforced in `macos/scripts/verify-release.sh`.
- **Sparkle is gated by `SU_FEED_URL` at build time.** If the env var is unset (the default for local builds), `build.sh` strips `SUFeedURL` from `Info.plist`, leaving the updater inert. Release CI injects the feed URL. Do not hardcode the feed URL in `Info.plist`.
- **Releases are tag-driven.** Pushing a `v*` tag triggers the release workflow which builds once, produces ZIP (Sparkle) + DMG (manual install), verifies both artifacts, generates a signed Sparkle `appcast.xml` from the ZIP, and deploys to GitHub Pages. Requires `SPARKLE_PRIVATE_KEY` repo secret. The version baked into `CFBundleShortVersionString` / `CFBundleVersion` comes from `APP_VERSION` env or falls back to whatever is in `Resources/Info.plist`.

## Mock server gotcha

`scripts/mock-server.py` only mocks `GET /api/oauth/usage`. To point the app at it you must temporarily edit `UsageService.swift`'s `defaultUsageEndpoint` AND add `NSAppTransportSecurity > NSAllowsLocalNetworking` to `macos/Resources/Info.plist`. **Both edits must be reverted before committing** — they are not behind a debug flag. The mock server does not implement the OAuth flow, so an existing valid token in `~/.config/claude-usage-bar/credentials.json` is required.

## Style & dependencies

- Keep third-party dependencies minimal — Sparkle is the only runtime dep, and adding another requires updating `Package.swift`, `verify-release.sh` (if it ships in the bundle), and the `build.sh` framework-bundling step.
- One primary SwiftUI view per file (existing convention: `PopoverView.swift`, `SettingsView.swift`, `UsageChartView.swift`).
- All UI-touching service classes are `@MainActor`; keep that annotation when extending them.
