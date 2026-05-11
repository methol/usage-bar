# AGENTS.md — AI 治理入口

> 任意 AI runner（Claude Code / Codex / Cursor / Cline / …）进入本仓库的**第一份**要读的文件。
> 中立 runner，不依赖任何特定厂商的 idiom。Claude Code 专属补充见 [`CLAUDE.md`](./CLAUDE.md)。

---

## 1. 项目快照

- **形态**：macOS 14+ 菜单栏 app（SwiftUI + Swift Charts + Sparkle）
- **当前 tag**：fork 自 Blimp-Labs 截止 `v0.0.6`；本仓库自 `v0.0.7` 起独立编号（[ADR 0004](./docs/adr/0004-fork-divergence-from-blimp-labs.md)）
- **Remote**：`github.com/methol/usage-bar`
- **AI 主导，人类辅助**（[ADR 0003](./docs/adr/0003-ai-led-development.md)）
- **Claude-only、不做多 provider**（[ADR 0002](./docs/adr/0002-claude-only-not-multi-provider.md)）
- **Swift 原生、不引入 Electron/Tauri**（[ADR 0001](./docs/adr/0001-swift-native-only.md)）

---

## 2. 5 分钟上手

1. 读完本文件（约 3 分钟）
2. 浏览 [`docs/README.md`](./docs/README.md) 目录索引
3. 看 [`docs/versions/README.md`](./docs/versions/README.md) 知道当前要做什么版本
4. 看 [`docs/superpowers/specs/README.md`](./docs/superpowers/specs/README.md) 找当前 spec
5. **如果你的任务是写 spec / ADR / version**：先看 §7.1 Frontmatter 速查 + 对应 `_TEMPLATE.md`；frontmatter 完整 schema 在 [母法 spec](./docs/superpowers/specs/2026-05-11-docs-governance.md) §3.3
6. **如果你的任务是写代码**：跳到 [`CLAUDE.md`](./CLAUDE.md) 看常用命令（`make build` / `swift test` 等）

---

## 3. 文档地图

```
docs/
├─ research/           长期事实性调研（业界 / 竞品 / 外部 API）
├─ superpowers/specs/  单次设计 spec（brainstorming 产出）
├─ adr/                架构决策记录（append-only，不可变）
├─ versions/           版本路线 + 验收 + release notes 草稿
├─ runbooks/           AI 可执行的标准操作流程
└─ user-guide/         面向用户中文文档（v1.0 前主要占位）

AGENTS.md      ← 本文件
CLAUDE.md      Claude Code 专用提示（高频命令、构建坑）
CHANGELOG.md   用户视角变更记录（AI 在发版 runbook 自动维护）
README.md      面向用户与 contributor 的产品介绍
```

> `superpowers/specs/`、`adr/`、`versions/` 三个目录各自含 `README.md`（索引）+ `_TEMPLATE.md`（模板）+ 实际文件。写新文档时**先复制模板**。

完整治理框架见母法 spec：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)。

---

## 4. 工作流

### 4.1 主回路

```
research/  ─G1─►  spec/ADR  ─G2─►  plan  ─G3─►  implementation
                                                       │
                                                       ▼
                                                     ─G4 (per commit)
                                                       │
                                                       ▼
                                                     PR  ─G5─►  merge  ─G6─►
                                                                           │
                                                                           ▼
                                                                   versions/vX.md
                                                                           │
                                                                           ▼
                                                                release runbook ─G7─► tag
```

### 4.2 7 个 Review Gate

每个产出在前进前必须通过一个 gate。gate 由独立 reviewer（跨模型 / 跨 session / 自动化）通过，**禁止 AI 自审自批**。

| Gate | 触发 | 必跑动作 | 通过条件 |
|---|---|---|---|
| **G1** | 调研报告写完 | 独立 reviewer design-review + 事实核对 | reviewer 无 "contradicted-by-evidence" 标记 |
| **G2** | spec / ADR 写完，或 ADR 状态变更 | 独立 reviewer；涉敏感面加 security review | verdict ∈ {approved, approved-after-revisions} |
| **G3** | plan（实施计划）写完 | 独立 reviewer plan-review | plan 每步可独立验证、有 success criteria |
| **G4** | 每个 commit-able 工作单元（**含纯文档 commit**） | 强制 verification-before-completion | 代码 commit：`swift build` 与 `swift test` 绿；纯文档 commit：linkcheck + frontmatter lint 输出 ✅ |
| **G5** | PR 创建前 | 独立 reviewer code-review；涉敏感面加 security review | reviewer verdict = approved |
| **G6** | merge 前 | CI 绿 + spec `## Verification log` 全勾完 | 所有 SC done=true |
| **G7** | 打 minor/major tag 前 | integration review；release runbook pre-flight | runbook checklist 全绿；24h health 回访 |

详见母法 §4.2~§4.5。

### 4.3 自动化"硬证据"

下列命令产出**绿色输出** = AI 标定"我做完了"的硬证据：

```bash
cd macos && swift build -c release
cd macos && swift test
make release-artifacts
bash macos/scripts/verify-release.sh macos/ClaudeUsageBar.zip
```

纯文档版本：见母法 spec frontmatter `automated_checks` 中的 `SC_AUTO_LINKCHECK` / `SC_AUTO_FRONTMATTER`。

---

## 5. 工具可用性 preflight（不同 runner 的等价物）

| 角色 | Claude Code 工具 | 其他 runner 等价物 | 不可用时 fallback |
|---|---|---|---|
| brainstorming | `superpowers:brainstorming` skill（输出形态：交互对话 → 写入 `docs/superpowers/specs/<id>.md`，基于 `_TEMPLATE.md`） | 手写本 spec _TEMPLATE.md 并交互对话 | 直接对话 + 模板 |
| 写 spec | `Write`/`Edit` tool | 等价文件操作工具 | 直接编辑 |
| writing-plans | `superpowers:writing-plans` skill | 手写 plan markdown + checklist | TODO.md 风格清单 |
| 实施 / verification | `superpowers:verification-before-completion` skill | 自检 checklist | 手动跑 `swift build && swift test` 后再提交 |
| 跨模型 design-review (G2) | `codex:codex-rescue` / `codex:rescue`（两者是同一 Codex skill 的不同别名） | 直接调用 Codex CLI / API；或换不同 Claude 子会话 | `general-purpose` subagent（prompt 显式要求独立判断） |
| 跨 session plan-review (G3) | `general-purpose` subagent | 新开会话 + 完整 prompt | 主会话 self-review + cool-down 后重读 |
| code-review (G5) | `superpowers:requesting-code-review` + `/review` | Codex / Cursor 的 review 能力 | 跨模型 review + 自动化 lint |
| security-review | `/security-review` slash | 等价 prompt | 手写凭证 / 权限 checklist |
| fact-check | `Explore` subagent | 只读快速查找 | grep / find 手动确认 |
| integration-review (G7) | `/ultrareview` slash | 多 agent 并发抽样 | 多次独立 review + cross-check |

**preflight 检测**：进入仓库后 AI 应先确认本仓库依赖的核心工具（design-reviewer / code-reviewer / verification）可用。任何一项不可用，**走 fallback 而不要停下问用户**（除非所有路径都失败）。

> **用户偏好**：codex 工具不可用时**不要停下问用户**，直接走 `general-purpose` subagent fallback（Claude Code runner 的此偏好已记入个人 memory，其他 runner 请按本表执行）。

---

## 6. 何时停下问人类（hard gates — minimum mandatory）

[ADR 0003](./docs/adr/0003-ai-led-development.md) 的默认是 *"完全自治"*。以下情形**必须**升级人类（不可自行决断）：

1. **凭证 / 密钥操作**：Apple Developer 账号、公证证书、Sparkle 私钥导出 / 重置、GitHub Personal Access Token 重置
2. **引入新第三方依赖** / 修改 LICENSE / 改变商业模式（开源 / 收费）
3. **同一 review gate ≥ 2 轮分歧** 且 reviewer 给出两个等价但语义不同的方案、无明显推荐项
4. **G7 发版后 24h 内 health check 报警**（Sparkle appcast 异常、用户反馈核心崩溃）
5. **spec / ADR 内部出现违反既有 ADR** 但作者认为 ADR 应被 supersede
6. **触发法律 / 合规风险信号**（用户隐私、第三方 API ToS、商标）

升级方式：用 `AskUserQuestion` 或等价交互工具，**给出 2~3 个具体选项 + 你推荐的项**，而非开放式提问。

---

## 7. 写作约定速查

- **日期**：ISO 8601 `YYYY-MM-DD`，以提交者本地日期为准
- **frontmatter**：spec / ADR / version 文档第一行必须是 `---`
- **中文优先**：技术术语、命令、API 名称、模型 ID 保留英文；不写 emoji 除非用户明确要求
- **commit message**：中文；包含变更主题 + 相关 spec id 引用（如 `docs: 立项 v0.0.7 文档治理 [spec:2026-05-11-docs-governance]`）
- **PR title**：与 commit 一致，中文；PR body 可中英混排，必含 spec id 与 version 链接
- **superpowers/ 目录**：是工艺名而非工具名 —— 未来即使 superpowers skill 改名或弃用，目录保持

### 7.1 Frontmatter 速查（最常用字段）

> 完整 schema 与字段语义见 [母法 §3.3](./docs/superpowers/specs/2026-05-11-docs-governance.md#33-统一-frontmatter生命周期与可变性约定)；本表只列写新文件时最常碰的字段。

**Spec**（`docs/superpowers/specs/_TEMPLATE.md`）：

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✅ | `YYYY-MM-DD-<slug>`，与文件名一致 |
| `title` | ✅ | 一句话主题 |
| `status` | ✅ | `draft` 起步，G2 过后改 `accepted`，G6 全勾后改 `implemented` |
| `created` / `updated` | ✅ | ISO 日期；`updated` 每次实质改动后同步 |
| `owner` | ✅ | `claude-code` / `human` / 其他 runner 名 |
| `model` | ✅ | 写作模型 ID，如 `claude-opus-4-7` |
| `target_version` | ✅ | 该 spec 计划落地的 `vX.Y.Z` |
| `related_adrs` / `related_research` | 可空 | ADR 编号数组 / research slug 数组 |
| `spec_criteria` | ✅ | 对象数组 `[{id, criterion, done, evidence}]`，G6 据此判定 |
| `automated_checks` / `manual_checks` | 可空 | 命令字符串 / 检查描述 |
| `reviews` | 初始 `[]` | 每过一次 review gate append 一条 verdict |

**ADR**（`docs/adr/_TEMPLATE.md`，[MADR 风格](https://adr.github.io/madr/)）：

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✅ | 4 位数字，严格递增 |
| `title` | ✅ | 决策总结 |
| `status` | ✅ | `proposed` / `accepted` / `superseded-by NNNN` / `deprecated` |
| `date` | ✅ | ISO 日期 |
| `deciders` | ✅ | 拍板人，通常 `claude-code, methol` |

**Version**（`docs/versions/_TEMPLATE.md`）：

| 字段 | 必填 | 说明 |
|---|---|---|
| `version` | ✅ | `vX.Y.Z` |
| `codename` | ✅ | 与文件名 slug 一致 |
| `status` | ✅ | `placeholder` → `planned` → `in-progress` → `shipped`（→ `yanked`） |
| `target_date` / `shipped_date` | 视状态填 | ISO 日期 或 null |
| `includes_specs` | placeholder 期为 `[]` | 当首个 spec 落地时填入 spec id 并把 status 升到 `planned` |
| `release_notes_zh` | 发版前填 | 中文 multi-line block；发版时复制到 CHANGELOG.md |

**Spec ↔ Version 双向链接惯例**：

- spec frontmatter `target_version: v0.0.8` 指向所属版本
- version frontmatter `includes_specs: [<spec-id>]` 反向引用 spec
- 触发 placeholder → planned：第一个真正 spec 落地时由作者 AI 在 **同一 commit / PR** 内更新 version 文件 frontmatter + 删除文件顶部的 `> ⚠️ Placeholder guardrail` 提示框

---

## 8. CHANGELOG 维护

由 AI 在发版 runbook（[`docs/runbooks/release.md`](./docs/runbooks/release.md) §5）自动生成。规则：

- **不要直接 copy PR 标题**（多为英文）
- 每条 PR / commit 翻译成中文 + 按"用户视角"重写
- 分类：新增 / 改进 / 修复 / 安全隐私 / 内部
- 引用对应 version 文件与 spec id

---

## 9. 引用

- 母法 spec：[`docs/superpowers/specs/2026-05-11-docs-governance.md`](./docs/superpowers/specs/2026-05-11-docs-governance.md)
- ADR 0001~0004：[`docs/adr/`](./docs/adr/)
- 当前版本路线：[`docs/versions/README.md`](./docs/versions/README.md)
- Claude Code 专用：[`CLAUDE.md`](./CLAUDE.md)
- 调研基线：[`docs/research/competitive-analysis.md`](./docs/research/competitive-analysis.md)
- 三大模板：[`spec`](./docs/superpowers/specs/_TEMPLATE.md) / [`ADR`](./docs/adr/_TEMPLATE.md) / [`version`](./docs/versions/_TEMPLATE.md)
