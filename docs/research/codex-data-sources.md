---
slug: codex-data-sources
title: Codex CLI 用量数据源调研（OAuth wham/usage 路径）
type: research
created: 2026-05-12
updated: 2026-05-12
sources:
  - https://github.com/steipete/CodexBar
  - https://github.com/openai/codex
  - https://chatgpt.com/backend-api/wham/usage
  - https://auth.openai.com/oauth/token
referenced_by:
  - 2026-05-12-codex-provider
---

# Codex CLI 用量数据源调研

> 调研日期：2026-05-12  
> 方法：直接读 [steipete/CodexBar](https://github.com/steipete/CodexBar)（MIT）`Sources/CodexBarCore/Providers/Codex/**` 源码，对照 OpenAI 官方 `codex` CLI 行为。

CodexBar 对 Codex 用量有三条回退路：**① OAuth API（`chatgpt.com/backend-api/wham/usage`）→ ② CLI RPC（`codex app-server`）→ ③ chatgpt.com Web（WKWebView 抓 dashboard）**。本调研只覆盖第 ① 条（最轻、最稳，本项目 v0.2.5 先做这条）；②③ 留作后续。

## 1. 凭证文件 `~/.codex/auth.json`

- 路径：`~/.codex/auth.json`；可被环境变量 `CODEX_HOME` 覆盖（→ `$CODEX_HOME/auth.json`）。
- 两种形态：
  1. **API key 模式**：顶层 `{ "OPENAI_API_KEY": "sk-..." }` —— 直接当 bearer 用，没有 refresh / accountId。
  2. **ChatGPT OAuth 模式**（常见，`codex login` 走 ChatGPT 登录）：
     ```jsonc
     {
       "tokens": {
         "access_token": "<JWT>",
         "refresh_token": "<opaque>",
         "id_token": "<JWT, 可选>",
         "account_id": "<ChatGPT account id, 可选>"
       },
       "last_refresh": "2026-05-10T12:34:56.789Z"   // ISO8601（可带或不带小数秒）
     }
     ```
  - key 可能是 snake_case 也可能 camelCase（CodexBar 两种都试）。
- CodexBar 的"是否该刷新"启发式：`last_refresh` 距今 > 8 天 → `needsRefresh`。注意这是**主动刷新阈值**，access_token JWT 自身的 `exp` 可能短得多 —— 实际过期以 API 返回 401 为准。

## 2. 用量接口 `GET /backend-api/wham/usage`

- 完整 URL：`https://chatgpt.com/backend-api/wham/usage`
  - base 可被 `~/.codex/config.toml` 里的 `chatgpt_base_url` 覆盖；若覆盖成非 `/backend-api` 的地址，CodexBar 改打 `/api/codex/usage`。本项目先只支持默认 base。
- Method：`GET`
- Headers：
  - `Authorization: Bearer <access_token>`（OAuth 模式）或 `Bearer <OPENAI_API_KEY>`（API key 模式）
  - `ChatGPT-Account-Id: <account_id>`（有才带）
  - `Accept: application/json`
  - `User-Agent: <任意非空>`（CodexBar 传 `"CodexBar"`）
- 状态码处理：`200..299` 解析 body；`401 / 403` → token 过期/无效；其它 → server error。
- 返回体（字段名确切，取自 CodexBar `CodexOAuthUsageFetcher.CodexUsageResponse`）：
  ```jsonc
  {
    "plan_type": "plus",          // guest|free|go|plus|pro|free_workspace|team|business|education|quorum|k12|enterprise|edu|...（未知值保留原串）
    "rate_limit": {
      "primary_window": {
        "used_percent": 37,            // Int，已用百分比（不是剩余）
        "reset_at": 1715900000,        // Int，**Unix 秒时间戳**（窗口重置时刻）
        "limit_window_seconds": 18000  // Int，窗口长度（秒）；5h 窗口 = 18000，7d 窗口 = 604800
      },
      "secondary_window": { /* 同结构 */ }
    },
    "credits": {                   // 可选，按量计费余额
      "has_credits": true,
      "unlimited": false,
      "balance": 12.34             // Double 或字符串数字
    }
  }
  ```
  - **窗口角色判定**：`limit_window_seconds / 60 == 300` → 5 小时滚动窗口（"session"）；`== 10080` → 7 天窗口（"weekly"）。CodexBar 有个 `CodexRateWindowNormalizer` 在 primary/secondary 顺序异常时按 windowMinutes 纠正成 (session, weekly)。
  - `reset_at` 用 `Date(timeIntervalSince1970:)` 直接转。

## 3. Token 刷新 `POST https://auth.openai.com/oauth/token`

- Headers：`Content-Type: application/json`
- Body（JSON）：
  ```json
  { "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
    "grant_type": "refresh_token",
    "refresh_token": "<refresh_token>",
    "scope": "openid profile email" }
  ```
- 成功 `200` → `{ "access_token": "...", "refresh_token": "...", "id_token": "..." }`（refresh_token 可能轮换）。
- 失败错误码（body `error` / `error.code` / `code`）：`refresh_token_expired` / `refresh_token_reused` / `invalid_grant` / `refresh_token_invalidated`；`401` 也按过期处理。
- ⚠️ **轮换副作用**：若服务端在刷新时轮换了 refresh_token，而调用方不把新 token 写回 `~/.codex/auth.json`，则下次 `codex` CLI 拿旧 refresh_token 会失败（`refresh_token_reused`）。CodexBar 选择**写回** auth.json（和 codex CLI 自己刷新时一样）。任何"只读不写"的实现都得接受这个风险，或干脆不做主动刷新（401 时提示用户跑 `codex` 重新登录）。

## 4. 其它路（本调研未细究，留给后续）

- **CLI RPC**：`codex app-server` 子进程的 JSON-RPC，含 rate-limit window（`RPCRateLimitWindow{ usedPercent, windowDurationMins, resetsAt }`）。
- **chatgpt.com Web**：WKWebView 登录态抓 dashboard，最重、最易碎，CodexBar 当最后兜底。
- **本地 session JSONL**：OpenAI codex CLI 在 `~/.codex/sessions/**` 写 rollout 文件，可像 Claude 的 `~/.claude/projects/**/*.jsonl` 那样扫 token/cost —— 但那是"成本"维度，不是"额度窗口"维度，单独一条数据源。
