import XCTest
@testable import UsageBar

final class ClaudePricingTests: XCTestCase {
    func testNormalizeStripsDateSuffix() {
        XCTAssertEqual(ClaudePricing.normalize("claude-opus-4-7-20260420"), "claude-opus-4-7")
        XCTAssertEqual(ClaudePricing.normalize("Claude-Sonnet-4-5-20260101"), "claude-sonnet-4-5")
        XCTAssertEqual(ClaudePricing.normalize("claude-haiku-4-5"), "claude-haiku-4-5")
    }

    func testLookupKnownModelReturnsPrice() {
        let p = ClaudePricing.lookup(model: "claude-opus-4-7")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.inputUSDPerMTok, 15.0)
        XCTAssertEqual(p?.outputUSDPerMTok, 75.0)
        XCTAssertEqual(p?.cacheReadUSDPerMTok, 1.50)
        XCTAssertEqual(p?.cacheWriteUSDPerMTok, 18.75)
    }

    func testLookupUnknownReturnsNil() {
        XCTAssertNil(ClaudePricing.lookup(model: "fake-model-99"))
        XCTAssertNil(ClaudePricing.lookup(model: ""))
    }

    func testCostFormulaMatchesExpected() {
        let p = ClaudeModelPricing(
            inputUSDPerMTok: 10.0,
            outputUSDPerMTok: 20.0,
            cacheReadUSDPerMTok: 1.0,
            cacheWriteUSDPerMTok: 5.0
        )
        // 1M of each token type: input=10 + output=20 + cr=1 + cw=5 = $36
        let usd = ClaudePricing.cost(for: p, input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        XCTAssertEqual(usd, 36.0, accuracy: 1e-9)
        // nil pricing → 0
        XCTAssertEqual(ClaudePricing.cost(for: nil, input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0), 0.0)
    }

    func testDisplayName() {
        XCTAssertEqual(ClaudePricing.displayName("claude-opus-4-7"), "Opus 4.7")
        XCTAssertEqual(ClaudePricing.displayName("claude-sonnet-4-6"), "Sonnet 4.6")
        XCTAssertEqual(ClaudePricing.displayName("claude-haiku-4-5"), "Haiku 4.5")
        XCTAssertEqual(ClaudePricing.displayName("claude-3-5-sonnet"), "Sonnet 3.5")
        XCTAssertEqual(ClaudePricing.displayName("claude-3-opus"), "Opus 3")
        XCTAssertEqual(ClaudePricing.displayName("claude-opus-4"), "Opus 4")
        XCTAssertEqual(ClaudePricing.displayName("<synthetic>"), "<synthetic>")
        XCTAssertEqual(ClaudePricing.displayName("some-future-model"), "some-future-model")
        XCTAssertEqual(ClaudePricing.displayName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
    }
}
