---
id: 2026-05-13-docs-cleanup
title: 文档治理整理 — AI 入口分层 + docs/agents/ 子目录 + drift 修复
status: implemented
created: 2026-05-13
updated: 2026-05-13
owner: claude-code
model: claude-opus-4-7
target_version: v0.5.0
related_adrs: [0003]
related_research: []
spec_criteria:
  - id: SC1
    criterion: "docs/agents/ 子目录下存在 4 个新文件：README.md / quickstart.md / operations.md / conventions.md，每个都有 frontmatter（slug + type=index/guide + created/updated）"
    done: true
    evidence: "commit a8cb0f6；4 文件全部含 frontmatter；ls docs/agents/ → README.md / conventions.md / operations.md / quickstart.md"
  - id: SC2
    criterion: "AGENTS.md 重构完成：(a) 行数 ≤ 150；(b) 顶部含 'L0 — 30 秒指引' 章节并包含任务类型反向索引表；(c) 保留 §6 hard gates 6 条原意；(d) §3 文档地图含 docs/agents/ 行"
    done: true
    evidence: "commit 6247c9c；wc -l AGENTS.md = 140；grep '^## L[0-2] ' AGENTS.md → 3 行；Hard gates 6 条保留；文档地图含 agents/ 行"
  - id: SC3
    criterion: "CLAUDE.md 瘦身完成：(a) 行数 ≤ 60；(b) 保留 Repo at a glance、Mock server gotcha、Sparkle/build 坑；(c) Common commands / Issue 驱动配置块整段迁出到 docs/agents/operations.md（CLAUDE.md 改为薄壳跳板）"
    done: true
    evidence: "commit 6247c9c；wc -l CLAUDE.md = 34；Mock server 段保留；Common commands / Issue 驱动配置块已迁出（grep 计数 0）"
  - id: SC4
    criterion: "docs/versions/README.md 索引表新增 'main 已含' 列；v0.0.7~v0.2.14 在该列标 ✅（代码已 merge 到 main 但治理层未完成 G6 closeout）；v0.3.0~v0.4.0 沿用原 status；表注解释代码层/治理层 drift 现状"
    done: true
    evidence: "commit 23e55d6；新表头 'Status | Main 已含 | Tag'；drift 注解 + 当前 git tag 状态注解齐全"
  - id: SC5
    criterion: "docs/superpowers/specs/README.md 索引表状态列 100% 与每个 spec frontmatter status 一致（grep 校验通过）"
    done: true
    evidence: "commit 23e55d6；frontmatter 抽样：所有 implemented / 1 个 superseded（v0.1.2-local-cost-scan）/ 1 个 draft（本 spec）与索引表一致；本 spec 在转 implemented 后也保持同步"
  - id: SC6
    criterion: "docs/adr/README.md 索引表与 6 个 ADR 文件 frontmatter status 字段一致"
    done: true
    evidence: "校对所有 6 个 ADR frontmatter status 与 README 索引表一致（0001/0003/0004/0005/0006 = accepted；0002 = superseded-by 0005），无需改动"
  - id: SC7
    criterion: "docs/README.md 子目录表新增 docs/agents/ 一行；docs/runbooks/README.md 中 3 个 placeholder runbook 状态标识更显眼（独立列出，避免和 active 混淆）"
    done: true
    evidence: "commit 23e55d6；docs/README 子目录表 agents/ 标 ★；docs/runbooks/README 拆 Active / Placeholder 双表"
  - id: SC8
    criterion: "本 spec 新增/改动的全部内链均有效：grep '\\[.*\\](.*\\.md)' 解析后每个相对路径文件存在；新文件互引使用相对路径"
    done: true
    evidence: "inline awk linkcheck 跑 12 份新/改文件零真错；3 个 false positive 均在本 spec 代码块示例 / SC 描述字符串内，非真链接"
automated_checks:
  - "SC_AUTO_NEW_FILES: test $(find docs/agents -name '*.md' | wc -l) -ge 4"
  - "SC_AUTO_AGENTS_LINES: test $(wc -l < AGENTS.md) -le 150"
  - "SC_AUTO_CLAUDE_LINES: test $(wc -l < CLAUDE.md) -le 60"
  - "SC_AUTO_LINKCHECK: 见 Verification log SC8 注释；用 inline awk 扫 markdown 链接 (`grep -oE '\\]\\([^)]+\\)' <file>` → 解析相对路径 → 检查文件存在)"
manual_checks:
  - "新 AI runner 进项目，按 docs/agents/quickstart.md 能在 5 分钟内回答：我要发版应该看哪？我要做新功能应该看哪？我要接 issue 应该看哪？"
  - "AGENTS.md 不引用任何尚未存在的链接（含母法 spec / docs/agents/ 三文件 / runbook 等）"
reviews:
  - gate: G2
    verdict: approved-with-autonomy
    note: "用户明确授权 '自主决策、自主完成'，跳过逐节确认；spec 内 self-review 通过（无 TBD / 内部一致 / scope 单 spec 可执行 / 无歧义）"
  - gate: G6
    verdict: approved
    note: "所有 SC 全勾 done=true；自动化检查 SC1/SC2/SC3/SC4/SC7 grep 通过；内链 inline awk 扫零真错"
---

# 文档治理整理 — AI 入口分层 + docs/agents/ 子目录 + drift 修复

## 1. 背景与目标

### 1.1 触发原因

用户反馈三个具体痛点：
1. **AI 入门要读太多** — AGENTS.md (216 行) + 母法 spec (38KB) 起读门槛过高
2. **状态信息陈旧** — `docs/versions/README.md` 索引表与每个版本文件 frontmatter 状态不一致；多个版本写 `in-progress` 但代码早已在 main
3. **信息分散** — 构建命令在 CLAUDE.md、Issue 驱动配置在 CLAUDE.md、治理母法在 spec、写作约定在 AGENTS.md，AI 需要在多处查找

### 1.2 目标

把"AI agent 进项目要读的内容"分层组织：30 秒能定位任务路径、5 分钟能上手具体工作、深度信息按需展开。同时修复索引 / 状态 / 链接的 drift，让"文档 = 实际现状"。

### 1.3 非目标

- **不动母法 spec** `2026-05-11-docs-governance.md`（status=implemented，按治理 §3.3 mutability 约定不可变）
- **不补 user-guide/** 中文用户文档（按用户决策"AI agent 优先，人类其次"，user-guide 保持占位）
- **不动各版本文件 frontmatter `status` 字段**（涉及 G6 closeout，超出本次范围；只在 README 表注释清楚 drift 现状）
- **不改 superpowers/{specs,plans}/** 双子目录结构（17 份 implemented spec 反向引用稳定）

## 2. 决策摘要

| 决策点 | 选择 | 原因 |
|---|---|---|
| AI 入口形态 | AGENTS.md 3 层（L0/L1/L2）+ docs/agents/ 子目录 | 兼顾"30 秒指引"和"必读骨架可独立运行" |
| 新子目录命名 | `docs/agents/` | 与根目录 AGENTS.md 名字呼应；与 superpowers/（承载 spec/plan）解耦 |
| CLAUDE.md 处理 | 薄壳化（保留 Claude Code 专用坑） | 通用 AI 实操命令应在中立 AGENTS 路径下；Claude 专属坑（Mock server / Sparkle build）保留在 CLAUDE.md |
| 版本 status drift | 不改 frontmatter，README 加"main 已含"列 | 改 frontmatter 等于强制收回 17 个版本的 G6，超出范围 |
| 母法 spec | 不动 | implemented immutable，本 spec 是补丁而非 supersede |
| user-guide/ | 保持占位 | 按用户读者优先级决策 |

## 3. 设计

### 3.1 文档树（变化部分）

```
/
├─ AGENTS.md                    重构（216 → ≤150）
├─ CLAUDE.md                    瘦身（102 → ≤60）
├─ CONTRIBUTING.md              加 AI-led 提示段
└─ docs/
   ├─ README.md                 索引表新增 docs/agents/ 行
   ├─ agents/                   🆕
   │  ├─ README.md              本目录索引
   │  ├─ quickstart.md          任务类型 → 路径反向索引
   │  ├─ operations.md          实操命令 + issue-driven 配置 + 守护线 checklist
   │  └─ conventions.md         写作约定 + frontmatter 速查 + 命名规范
   ├─ versions/README.md        索引表加 "main 已含" 列 + drift 注解
   ├─ superpowers/specs/README.md  状态列对齐
   ├─ adr/README.md             状态列对齐
   └─ runbooks/README.md        placeholder 显式分组
```

### 3.2 AGENTS.md 三层结构

| 层 | 行数预算 | 内容 |
|---|---|---|
| **L0 — 30 秒指引** | ~40 | 项目一行定位 + "我要做什么 → 看哪里"反向索引（6 行）+ 详见 quickstart.md |
| **L1 — 必读骨架** | ~80 | 项目快照（ADR 一句话）/ 文档地图 / 工作流主回路（保留现有 ASCII）/ 7 review gate 单行表 / Hard gates 6 条（不动） |
| **L2 — 扩展引用** | ~30 | 母法 spec / docs/agents/conventions.md / docs/agents/operations.md / ADR 链接 / 当前版本路线 |

**保留不动的部分**：
- §6 hard gates 6 条原文（治理硬约束）
- §4 review gate 表（精简到 1 行 / gate）
- §4 主回路 ASCII 图
- 跨 runner 工具 preflight 表（移到 L2 或 operations.md 由 §3.3 决定）

**剥离迁出的部分**：
- §7.1 frontmatter 速查 → `conventions.md`
- §5 工具 preflight 表（详表）→ `operations.md`
- §8 CHANGELOG 维护规则 → `operations.md`

### 3.3 docs/agents/ 三文件骨架

**`quickstart.md`** — 任务类型反向索引（~80 行）
```markdown
我要做什么          | 看哪里
--------------------|------------------------------------------
接 GitHub issue    | docs/workflow/issue-driven.md + scripts/issues/kickoff.sh
做新功能/模块       | superpowers:brainstorming → spec → plan → 实施
发版（打 tag）      | docs/runbooks/release.md
改 ADR / 新建 ADR  | docs/adr/_TEMPLATE.md + AGENTS.md §6 hard gate
写新 spec          | docs/superpowers/specs/_TEMPLATE.md + AGENTS.md §7.1
修文档             | 本 spec 风格：先 brainstorming → spec
日常 swift 命令     | docs/agents/operations.md
```
每一行后面跟"30 秒说明 + 关键命令 / 文件路径"。

**`operations.md`** — 实操命令 + 配置（~120 行）
- 构建 / 测试 命令（迁自 CLAUDE.md 的 Common commands）
- Issue 驱动配置（迁自 CLAUDE.md "Issue 驱动开发配置"整段）
- 守护线 checklist（迁自 CLAUDE.md）
- 受保护文件 / 敏感写入链路（迁自 CLAUDE.md）
- 本地验证命令矩阵（按触发条件分类，迁自 CLAUDE.md）
- 跨 runner 工具 preflight 详表（迁自 AGENTS.md §5）

**`conventions.md`** — 写作约定（~100 行）
- 写作风格（中文优先、不用 emoji、日期 ISO 8601、commit 中文 + spec id）
- frontmatter 三表（spec / ADR / version，迁自 AGENTS.md §7.1）
- 命名规范（spec slug / version codename / ADR 编号）
- spec ↔ version 双向链接惯例

### 3.4 versions/README.md drift 修复

**新表头**：
```
| 版本 | Codename | Frontmatter status | main 已含 | Tag 推送 | Target | 主题 |
```

- **Frontmatter status**：取自每个版本文件 frontmatter `status`（与现状一致，不改）
- **main 已含**：代码层已落地 main = ✅；尚未实施 = ⏸；placeholder = —
- **Tag 推送**：实际 `git tag` 已存在的版本（目前只有 v0.0.6 / v0.3.2）

**注解段**（表下方）：
> 本仓库采用"积压发版"模式 — 多个功能版本攒在一起、由更高版本（如 v0.3.2）一次性 tag 推送。
> 因此 v0.0.7~v0.2.14 的 frontmatter 仍为 `in-progress`，但代码层已在 main。
> 治理层 G6/G7 的 closeout（回填 `shipped_date`、改 `status: shipped`）属于专门动作，
> 不在本次文档整理范围。

### 3.5 specs/README.md & adr/README.md 状态对齐

逐行核对索引表中"Status"列与对应文件 frontmatter `status` 字段，发现不一致时**以 frontmatter 为准**（frontmatter 是单源真相）修正 README 表。

### 3.6 CLAUDE.md 瘦身后骨架（≤60 行）

```markdown
# CLAUDE.md

Claude Code 专用提示。通用 AI 治理 / 命令 / 约定 见 [`AGENTS.md`](./AGENTS.md) + [`docs/agents/`](./docs/agents/).

## Repo at a glance
（保留 1 段 macOS app 简介）

## Mock server gotcha
（保留全段 — 这是 Claude Code 实际操作时的坑）

## Sparkle / build 注意
（保留 Sparkle gated by SU_FEED_URL + 版本注入说明）

## 跳板
- 日常命令：docs/agents/operations.md
- Issue 驱动：docs/agents/operations.md §Issue
- 写作约定：docs/agents/conventions.md
```

### 3.7 CONTRIBUTING.md

加一段顶部提示：
> Note: 本项目 AI-led（ADR 0003）。人类贡献者请优先走 GitHub Issue + `docs/workflow/issue-driven.md`
> 流程，让 AI 完成实施 → PR；直接 PR 仍接受，但请先在 Issue 中描述需求。

## 4. 现有文件迁移动作

| 动作 | 文件 | 备注 |
|---|---|---|
| 🆕 | `docs/agents/README.md` | 目录索引 |
| 🆕 | `docs/agents/quickstart.md` | 任务反向索引 |
| 🆕 | `docs/agents/operations.md` | 命令 + 配置（来源 CLAUDE.md + AGENTS.md §5） |
| 🆕 | `docs/agents/conventions.md` | 写作约定（来源 AGENTS.md §7.1） |
| 🔧 | `AGENTS.md` | 重构为 3 层；保留 hard gates / 主回路 / review gate 表 |
| 🔧 | `CLAUDE.md` | 瘦身到 ≤60 行，保留 Claude Code 专用坑 |
| 🔧 | `docs/README.md` | 子目录表新增 docs/agents/ 行 |
| 🔧 | `docs/versions/README.md` | 索引表加列 + drift 注解 |
| 🔧 | `docs/superpowers/specs/README.md` | 状态列对齐 |
| 🔧 | `docs/adr/README.md` | 状态列对齐 |
| 🔧 | `docs/runbooks/README.md` | placeholder 显式分组 |
| 🔧 | `CONTRIBUTING.md` | 顶部加 AI-led 提示段 |
| ✅ 不动 | `README.md`（根） | 面向用户/GitHub 访客 |
| ✅ 不动 | `CHANGELOG.md` | release runbook 维护 |
| ✅ 不动 | 母法 spec | immutable |
| ✅ 不动 | 各 spec / ADR / version 文件正文与 frontmatter | 索引对齐到 frontmatter，不反向改 |

## 5. 风险 / Open questions

1. **AGENTS.md L0 反向索引和 quickstart.md 重复** — 故意。L0 只列 6 行最高频，quickstart.md 是完整版（含罕见任务、跨场景）。L0 跳板 quickstart.md。
2. **迁出 frontmatter 速查会让 AGENTS.md §7.1 留个空** — 改为 1 行链接（"frontmatter 速查见 docs/agents/conventions.md"），避免读者只看 AGENTS.md 漏掉速查。
3. **CLAUDE.md ≤60 行可能容不下所有 Claude 专用坑** — 如果实际迁完后仍超 60 行，把"Repo at a glance"再压缩或全部迁 AGENTS.md L1。
4. **versions/README 新增的 "main 已含" 列首次需要人工判定 21 个版本** — 我会用 `git log --all -- docs/versions/vX.Y.Z-*.md` + 找对应 PR 是否已 merge 来判断；不确定的标 ⚠️。

## 6. 后续工作（不在本 spec 范围）

- 跑专门的 G6 closeout pass，把 v0.0.7~v0.2.14 的 frontmatter `status` 改 `shipped` 并回填 `shipped_date`（涉及核对每个版本的 SC 是否全 done）
- 补 user-guide/ 中文文档（等 v1.0 前后用户开始多）
- runbook placeholder 落实（notarization / sparkle-keys / incident-response）

## 7. 引用

- 相关 ADR：0003（AI-led）
- 落地版本：v0.5.0（计划与 observable-migration 同期，或作为独立 patch ship）
- 母法 spec（参照但不修改）：`docs/superpowers/specs/2026-05-11-docs-governance.md`

## Verification log

> G6 验收依据。每条 SC 完成时勾选并填 evidence。

- [x] SC1 — 4 个新文件 commit a8cb0f6（含 frontmatter）
- [x] SC2 — AGENTS.md 140 行（≤150）+ L0/L1/L2 三段 + Hard gates 保留；commit 6247c9c
- [x] SC3 — CLAUDE.md 34 行（≤60）+ Mock server / 跳板保留 + commands 迁出；commit 6247c9c
- [x] SC4 — versions/README 加 Main 已含 / Tag 列 + drift 注解；commit 23e55d6；同时修 v0.0.7 / v0.4.0 索引与 frontmatter 对齐
- [x] SC5 — specs/README append 本 spec 一行；其他 24 个 spec 状态校对零 drift；commit 23e55d6
- [x] SC6 — adr/README 与 6 个 ADR frontmatter 对齐（无 drift，无需改动）
- [x] SC7 — docs/README 含 agents/ 行 + runbooks/README active/placeholder 分组；commit 23e55d6
- [x] SC8 — 12 份新/改文件 inline awk linkcheck 零真错（3 个 false positive 在 spec 自身代码块/SC 描述里）

## 同时顺手修复

不在 SC 内但属于"对齐"痛点的顺手修复：

- `CONTRIBUTING.md` Project structure 段从 v0.3.2 之前的扁平结构更新为当前 9 子目录结构（指向 `2026-05-13-code-structure-hygiene` §3.3 权威映射）
- `docs/README.md` 子目录表拆出 `superpowers/plans/` 单独一行（之前藏在 superpowers/specs/ 行后面）
