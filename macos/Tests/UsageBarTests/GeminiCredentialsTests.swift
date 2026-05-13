import XCTest
@testable import UsageBar

final class GeminiCredentialsTests: XCTestCase {

    private func makeGeminiHome(credsJSON: String?) throws -> [String: String] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let credsJSON {
            try Data(credsJSON.utf8).write(to: dir.appendingPathComponent("oauth_creds.json"))
        }
        return ["GEMINI_HOME": dir.path]
    }

    func testLoadAllFields() throws {
        let env = try makeGeminiHome(credsJSON: """
        { "access_token": "ACCESS_SENTINEL",
          "refresh_token": "REFRESH_SENTINEL",
          "token_type": "Bearer",
          "expiry_date": 1750000000000,
          "id_token": "ID_SENTINEL",
          "scope": "https://www.googleapis.com/auth/cloud-platform" }
        """)
        let creds = try XCTUnwrap(GeminiCredentialStore.load(environment: env))
        XCTAssertEqual(creds.accessToken, "ACCESS_SENTINEL")
        XCTAssertEqual(creds.refreshToken, "REFRESH_SENTINEL")
        XCTAssertEqual(creds.tokenType, "Bearer")
        XCTAssertEqual(creds.expiryDate, Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(creds.idToken, "ID_SENTINEL")
        XCTAssertEqual(creds.scope, "https://www.googleapis.com/auth/cloud-platform")
    }

    func testLoadMinimalFields() throws {
        let env = try makeGeminiHome(credsJSON: """
        { "access_token": "ACCESS_SENTINEL", "token_type": "Bearer" }
        """)
        let creds = try XCTUnwrap(GeminiCredentialStore.load(environment: env))
        XCTAssertEqual(creds.accessToken, "ACCESS_SENTINEL")
        XCTAssertNil(creds.refreshToken)
        XCTAssertNil(creds.expiryDate)
    }

    func testLoadMissingAccessTokenThrows() throws {
        let env = try makeGeminiHome(credsJSON: #"{ "refresh_token": "R" }"#)
        XCTAssertThrowsError(try GeminiCredentialStore.load(environment: env)) { error in
            XCTAssertTrue(error is GeminiCredentialError)
        }
    }

    func testLoadInvalidJSONThrows() throws {
        let env = try makeGeminiHome(credsJSON: "not json {{{")
        XCTAssertThrowsError(try GeminiCredentialStore.load(environment: env))
    }

    func testLoadFileAbsentReturnsNil() throws {
        let env = try makeGeminiHome(credsJSON: nil)
        XCTAssertNil(try GeminiCredentialStore.load(environment: env))
    }

    func testLoadRespectsGeminiHome() throws {
        let env = try makeGeminiHome(credsJSON: #"{ "access_token": "A", "token_type": "Bearer" }"#)
        XCTAssertNotNil(try GeminiCredentialStore.load(environment: env))
        XCTAssertEqual(GeminiCredentialStore.credsFileURL(environment: env).lastPathComponent, "oauth_creds.json")
        XCTAssertTrue(GeminiCredentialStore.credsFileURL(environment: env).path.hasPrefix(env["GEMINI_HOME"]!))
    }

    func testCredentialErrorDescriptionHasNoRawValues() {
        for e in [GeminiCredentialError.malformed, GeminiCredentialError.missingAccessToken] {
            let s = "\(e)"
            XCTAssertFalse(s.contains("SENTINEL"))
            XCTAssertFalse(s.contains("{"))
        }
    }
}
