import XCTest
@testable import UsageBar

final class ModelPriceTableFallbackTests: XCTestCase {

    func testCandidateChainSteps() {
        // ① 原名 → ② 去 reasoning-effort 后缀
        let c = ModelPricingCatalog.pricingCandidates(for: "GPT-5.4-xhigh")
        XCTAssertEqual(c.first, "gpt-5.4-xhigh")
        XCTAssertTrue(c.contains("gpt-5.4"))
        // ③ 去 codex 家族后缀退基座
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-5.3-codex").contains("gpt-5.3"))
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-5.1-codex-max").contains("gpt-5.1"))
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-5.3-codex-spark").contains("gpt-5.3"))
        // ④ 去 minor 版本号
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-5.3").contains("gpt-5"))
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-5.4-mini").contains("gpt-5-mini"))
        // ⑤ provider 前缀
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "gpt-4o").contains("openai/gpt-4o"))
        XCTAssertTrue(ModelPricingCatalog.pricingCandidates(for: "claude-opus-4").contains("anthropic/claude-opus-4"))
        // 去重
        let all = ModelPricingCatalog.pricingCandidates(for: "gpt-5")
        XCTAssertEqual(all.count, Set(all).count)
        // 组合：gpt-5.3-codex-xhigh 应能一路退到 gpt-5
        let combo = ModelPricingCatalog.pricingCandidates(for: "gpt-5.3-codex-xhigh")
        XCTAssertTrue(combo.contains("gpt-5.3-codex"))
        XCTAssertTrue(combo.contains("gpt-5.3"))
        XCTAssertTrue(combo.contains("gpt-5"))
    }

    private func frozenCatalog() -> ModelPricingCatalog {
        let url = Bundle.module.url(forResource: "litellm_snapshot_frozen", withExtension: "json")!
        return ModelPricingCatalog(cacheURL: url, bundledURL: nil, minBytesOverride: 0)
    }

    func testRealAliasesResolveToNonNilPricing() {
        let cat = frozenCatalog()
        XCTAssertTrue(cat.isLoaded)
        for model in ["gpt-5.3-codex", "gpt-5.2", "gpt-5.4", "gpt-5.1-codex-max",
                      "gpt-5.4-mini", "gpt-5.2-codex", "gpt-5.4-xhigh", "gpt-5.3-codex-spark",
                      "claude-opus-4-7", "claude-sonnet-4-6"] {
            XCTAssertNotNil(cat.unitPricing(rawModel: model), "expected non-nil pricing for \(model)")
        }
        XCTAssertNil(cat.unitPricing(rawModel: "foo-bar-9"))
    }

    func testTableAdaptersDelegateToCatalog() {
        // 适配器走的是 ModelPricingCatalog.shared（= bundle 内真实快照）。
        let openai: any ModelPriceTable = OpenAIModelPriceTable.shared
        XCTAssertEqual(openai.normalize("GPT-5.5"), "gpt-5.5")
        XCTAssertNotNil(openai.lookup("gpt-5"))
        XCTAssertNotNil(openai.lookup("gpt-5.3-codex"))
        XCTAssertEqual(openai.displayName("gpt-5-codex"), "GPT-5 Codex")
        XCTAssertNil(openai.lookup("definitely-not-a-real-model-zzz9"))

        let claude: any ModelPriceTable = ClaudeModelPriceTable.shared
        XCTAssertEqual(claude.normalize("Claude-Opus-4-7-20260101"), "claude-opus-4-7")
        XCTAssertNotNil(claude.lookup("claude-opus-4-7"))
        XCTAssertEqual(claude.displayName("claude-opus-4-7"), "Opus 4.7")
        XCTAssertNil(claude.lookup("claude-definitely-not-real-zzz9"))
    }
}
