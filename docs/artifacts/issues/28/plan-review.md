# AI 方案评审(Plan Review)

## 评审结论

- VERDICT: **NEEDS_REVISION → 修订后自评通过,进入实施**
- 评审者:`subagent`(`general-purpose`)
- 评审日期:2026-05-14
- 复审策略:本轮反馈无方案级争议,仅细化点 + 1 处 P0 修正,**修订完直接进入实施**,把第 2 轮评审压力让给 ship 阶段 PR diff review。若 ship 阶段发现 plan 修订未真正落地,再升级。

## 关键反馈

### P0(必改 — 已采纳)

1. **SettingsView L80 不能整行删除**。
   - 评审理由:Picker 选项只是 "Stable" / "Beta",新用户不知道 "Beta" = OTA 自动推送 pre-release 构建。这是发版安全相关 UX,不是噪音。
   - 修订:diagnosis §B 改为 `Text("Beta includes pre-release builds for testing.")` 保留+翻译。

### P1(必改 — 已采纳)

2. **测试硬编码 "账号 1" 4 处明列**:
   - `Tests/UsageBarTests/StoredCredentialsStoreMigrationTests.swift:47`
   - `Tests/UsageBarTests/UsageServiceMultiAccountTests.swift:56`
   - `Tests/UsageBarTests/UsageServiceTests.swift:930`
   - `Tests/UsageBarTests/UsageServiceTests.swift:968`
   - 修订:diagnosis 新增 §D 节,统一改 `"Account 1"`。

3. **`StoredAccount.swift:48` 描述错误**:评审指出这条是 v1→v2 静默迁移路径,不是"新创建账号"。
   - 修订:diagnosis §C 重写,区分三个入口(迁移路径英文化 / `UsageService.swift:352/474` 新签入英文化 / 已存在的 v2 状态中文 label 不动)。

4. **手动测试态列表细化**:13 行表格,覆盖所有新文案的触发路径与期望英文(Gemini/Codex 5+3 error 串允许"至少覆盖前两条最常见")。

5. **ProviderTabBar `← Back to Claude` 2 处**(L56/L83)+ Gemini errors 3 对重复字符串。
   - 修订:diagnosis §影响范围.修改文件 内注明,避免实施漏改。

### P2(nit — 部分采纳)

6. SettingsView L122 `.help` 可直接删 → **不采纳**(翻译保留;tooltip hover 才出现,成本低)
7. LocalCostCard 英文措辞优化:`"Pricing data not loaded; costs unavailable."` → 简化为 `"Pricing data unavailable."` → **采纳**;`call(s)` 写法 → **保留**(简洁)
8. `UsageCard.swift` #Preview 顺手清 → **不采纳**(不参与生产构建,留作以后专项清理 PR)

## 应对

### 接受的反馈与对应修改

- §B Beta 文案改为翻译保留(L80)
- §C 重写 "账号 N" 入口分类
- §D 新增,4 处测试 label 明列
- §影响范围.测试计划 改为逐态表格
- §影响范围.修改文件 注明 ProviderTabBar 双处 + Gemini 重复字符串

### 拒绝的反馈与理由

- L122 `.help` 删除 → tooltip 信息量虽低但成本极低,保留更稳
- `UsageCard.swift` #Preview 清理 → 不在 issue 范围,留作专项 chore

## 是否需要人工介入

- **结论**:NO
- **理由**:
  1. 不触发 AGENTS.md §6 hard gate(无凭证/依赖/法律/版本/ADR 冲突)
  2. 评审确认守护线未触碰、受保护文件未碰、敏感写入链路无逻辑改动
  3. 仅是产品文案细节,属 AI 自治范围(`feedback_autonomous_decisions` memory)
