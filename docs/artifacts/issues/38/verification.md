# 验证记录

## 命令 / 步骤
- 纯文档改动(README.md 新增 `## Known limitations` 一节)。按 `docs/agents/operations.md` §2 验证矩阵"改纯文档"项:链接核对 + 人工核对措辞。
- 不触 Swift 代码,不跑 `swift build` / `swift test`。

## 结果 / 截图
- 新增段落不含任何超链接(`Claude Code-credentials` 为行内 code,非链接)→ 无死链风险。
- 措辞与 README 现有英文风格一致;未与既有 "Third-party credentials & APIs" 节冲突(那节描述 Claude 走 Keychain fallback,本节补充 ad-hoc 签名下授权框反复出现的已知限制)。
- `git diff` 仅 1 个文件、6 行新增。

## 本地验证清单
- 单测 / 集成测试:不适用(无代码改动)
- 构建:不适用(无代码改动)
- 接口契约(如适用):不适用
- 手动回归(如适用):README 在 GitHub Markdown 下渲染正常(标题层级 `##`,与相邻节一致)

## CI
- (PR 的 checks 状态由 ship/merge 阶段记录)
