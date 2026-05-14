import XCTest
@testable import UsageBar

/// v0.5.1 task 6/7 后：StoredCredentialsStore 已下线，
/// `hasRefreshToken` / `needsRefresh` / `strippingRefreshToken` 助手在 Sources 已无 caller 一并删除。
/// 本文件只剩 StoredCredentials 值类型的 isExpired 测试（struct 本身保留 — `ensureFreshCredentials` 依赖）。
final class StoredCredentialsTests: XCTestCase {

    // MARK: - isExpired

    func testIsExpiredReturnsFalseWhenExpiresAtIsNil() {
        let credentials = StoredCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: nil,
            scopes: ["user:profile"]
        )
        XCTAssertFalse(credentials.isExpired())
    }

    func testIsExpiredReturnsTrueWhenPastExpiry() {
        let credentials = StoredCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(-60),
            scopes: ["user:profile"]
        )
        XCTAssertTrue(credentials.isExpired())
    }

    func testIsExpiredReturnsFalseWhenBeforeExpiry() {
        let credentials = StoredCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600),
            scopes: ["user:profile"]
        )
        XCTAssertFalse(credentials.isExpired())
    }
}
