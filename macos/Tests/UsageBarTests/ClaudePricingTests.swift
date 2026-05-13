import XCTest
@testable import UsageBar

final class ClaudePricingTests: XCTestCase {
    func testNormalizeStripsDateSuffix() {
        XCTAssertEqual(ClaudePricing.normalize("claude-opus-4-7-20260420"), "claude-opus-4-7")
        XCTAssertEqual(ClaudePricing.normalize("Claude-Sonnet-4-5-20260101"), "claude-sonnet-4-5")
        XCTAssertEqual(ClaudePricing.normalize("claude-haiku-4-5"), "claude-haiku-4-5")
    }

    func testLookupUnknownReturnsNil() {
        // 价格查表走 ModelPricingCatalog（bundle 内真实快照）；造一个绝不可能前缀匹配上的名。
        XCTAssertNil(ClaudeModelPriceTable.shared.lookup("claude-definitely-not-a-real-model-zzz9"))
        XCTAssertNil(ClaudeModelPriceTable.shared.lookup(""))
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
