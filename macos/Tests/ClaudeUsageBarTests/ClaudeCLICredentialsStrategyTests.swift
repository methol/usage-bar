import XCTest
@testable import ClaudeUsageBar

/// SC7 安全约束：所有 mock JSON 用 'mock-' 前缀，不出现 'sk-ant-' 真实前缀；
/// 断言用 hasPrefix / count / nil-ness，不字面比较 token 字段（避免 framework
/// 失败时打印 raw value 至 test log）。
final class ClaudeCLICredentialsStrategyTests: XCTestCase {

    private func decode(_ json: String) throws -> ClaudeCLICredentialsStrategy.KeychainPayload {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(ClaudeCLICredentialsStrategy.KeychainPayload.self, from: data)
    }

    func testValidPayloadDecodes() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"mock-access-1","refreshToken":"mock-refresh-1",\
        "expiresAt":1778520574000,"scopes":["user:profile","user:inference"]}}
        """
        let payload = try decode(json)
        XCTAssertTrue(payload.claudeAiOauth.accessToken.hasPrefix("mock-"))
        XCTAssertEqual(payload.claudeAiOauth.accessToken.count, 13)  // "mock-access-1"
        XCTAssertNotNil(payload.claudeAiOauth.refreshToken)
        XCTAssertEqual(payload.claudeAiOauth.scopes?.count, 2)
        XCTAssertEqual(payload.claudeAiOauth.expiresAt, 1778520574000)
    }

    func testMissingClaudeOauth() {
        let json = "{}"
        XCTAssertThrowsError(try decode(json))
    }

    func testMissingAccessToken() {
        let json = """
        {"claudeAiOauth":{"refreshToken":"mock-refresh-1","expiresAt":1778520574000}}
        """
        XCTAssertThrowsError(try decode(json))
    }

    func testNilExpiresAtAndRefresh() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"mock-access-2"}}
        """
        let payload = try decode(json)
        XCTAssertTrue(payload.claudeAiOauth.accessToken.hasPrefix("mock-"))
        XCTAssertNil(payload.claudeAiOauth.refreshToken)
        XCTAssertNil(payload.claudeAiOauth.expiresAt)
        XCTAssertNil(payload.claudeAiOauth.scopes)
    }

    func testMillisecondToDateConversion() throws {
        // SC5 显式覆盖：1778520574000 ms → Date(timeIntervalSince1970: 1778520574.0)
        let json = """
        {"claudeAiOauth":{"accessToken":"mock-access-3","expiresAt":1778520574000}}
        """
        let payload = try decode(json)
        let expectedSeconds: TimeInterval = 1778520574.0
        let actual = payload.claudeAiOauth.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) }
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual!.timeIntervalSince1970, expectedSeconds, accuracy: 0.001)
    }

    func testLoadErrorDescriptionDoesNotLeakRawValue() {
        // SC7 验证：LoadError 的 description 只输出 case 名，不带 OSStatus 数值
        XCTAssertEqual("\(ClaudeCLICredentialsStrategy.LoadError.keychainQueryFailed)", "keychainQueryFailed")
        XCTAssertEqual("\(ClaudeCLICredentialsStrategy.LoadError.payloadDecodeFailed)", "payloadDecodeFailed")
    }
}
