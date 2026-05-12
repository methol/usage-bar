import XCTest
@testable import UsageBar

final class StoredAccountsFileTests: XCTestCase {
    private func makeAccount(label: String = "test", token: String = "mock-access") -> StoredAccount {
        StoredAccount(
            id: UUID(),
            label: label,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsed: Date(timeIntervalSince1970: 1_700_000_000),
            credentials: StoredCredentials(accessToken: token, refreshToken: nil, expiresAt: nil, scopes: [])
        )
    }

    func testCodableRoundTrip() throws {
        let file = StoredAccountsFile(version: 2, activeIndex: 0, accounts: [makeAccount(label: "a"), makeAccount(label: "b")])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(StoredAccountsFile.self, from: data)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.activeIndex, 0)
        XCTAssertEqual(decoded.accounts.count, 2)
        XCTAssertEqual(decoded.accounts[0].label, "a")
        XCTAssertEqual(decoded.accounts[1].label, "b")
    }

    func testActiveAccountClampsToValidIndex() {
        let file = StoredAccountsFile(version: 2, activeIndex: 99, accounts: [makeAccount(label: "x"), makeAccount(label: "y")])
        XCTAssertEqual(file.activeAccount?.label, "y")  // clamp to last

        let neg = StoredAccountsFile(version: 2, activeIndex: -5, accounts: [makeAccount(label: "x")])
        XCTAssertEqual(neg.activeAccount?.label, "x")  // clamp to 0
    }

    func testActiveAccountReturnsNilForEmpty() {
        let file = StoredAccountsFile(version: 2, activeIndex: 0, accounts: [])
        XCTAssertNil(file.activeAccount)
        XCTAssertNil(file.clampedActiveIndex)
    }

    func testCurrentVersionConstant() {
        XCTAssertEqual(StoredAccountsFile.currentVersion, 2)
    }
}
