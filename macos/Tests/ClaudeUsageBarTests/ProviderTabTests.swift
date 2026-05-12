import XCTest
@testable import ClaudeUsageBar

final class ProviderTabTests: XCTestCase {
    func testAllCasesOrder() {
        XCTAssertEqual(ProviderTab.allCases, [.claude, .codex, .cursor, .copilot, .gemini])
    }

    func testDisplayNames() {
        XCTAssertEqual(ProviderTab.claude.displayName, "Claude")
        XCTAssertEqual(ProviderTab.codex.displayName, "Codex")
        XCTAssertEqual(ProviderTab.cursor.displayName, "Cursor")
        XCTAssertEqual(ProviderTab.copilot.displayName, "Copilot")
        XCTAssertEqual(ProviderTab.gemini.displayName, "Gemini")
    }

    func testOnlyClaudeAvailable() {
        XCTAssertTrue(ProviderTab.claude.isAvailable)
        for p in ProviderTab.allCases where p != .claude {
            XCTAssertFalse(p.isAvailable, "\(p) should not be available yet")
        }
    }
}
