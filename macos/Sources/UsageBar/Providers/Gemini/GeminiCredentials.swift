import Foundation

/// 从本机 gemini-cli 已登录的 `~/.gemini/oauth_creds.json` 读出来的凭证。
/// 字段对齐 google-auth-library 的 `Credentials` 接口（见 gemini-cli `packages/core/src/code_assist/oauth2.ts`）。
/// 本 spec 阶段：**只读**；refresh 在 Task 3 实现。
struct GeminiCredentials: Equatable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String?
    /// `expiry_date` 上游用毫秒 epoch；此处统一转 Swift `Date`（秒）。
    var expiryDate: Date?
    var idToken: String?
    var scope: String?

    /// `expiryDate` 已过期（留 60s 缓冲），返回 true。`expiryDate` 缺失也算需刷新（谨慎）。
    func isExpired(now: Date = Date()) -> Bool {
        guard let exp = expiryDate else { return true }
        return exp.timeIntervalSince(now) < 60
    }
}

enum GeminiCredentialError: Error, CustomStringConvertible {
    case malformed
    case missingAccessToken

    var description: String {
        switch self {
        case .malformed:           return "malformed"
        case .missingAccessToken:  return "missingAccessToken"
        }
    }
}

enum GeminiCredentialStore {
    /// `~/.gemini/oauth_creds.json`；`GEMINI_HOME` 设了就用 `$GEMINI_HOME/oauth_creds.json`。
    static func credsFileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home: URL
        if let geminiHome = environment["GEMINI_HOME"], !geminiHome.isEmpty {
            home = URL(fileURLWithPath: geminiHome, isDirectory: true)
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true)
        }
        return home.appendingPathComponent("oauth_creds.json")
    }

    /// 文件不存在 → nil（静默）；存在但坏 → throw `GeminiCredentialError`。
    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> GeminiCredentials? {
        let url = credsFileURL(environment: environment)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> GeminiCredentials {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GeminiCredentialError.malformed
        }
        guard let accessToken = obj["access_token"] as? String, !accessToken.isEmpty else {
            throw GeminiCredentialError.missingAccessToken
        }
        let expiry: Date?
        if let ms = obj["expiry_date"] as? Double {
            expiry = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = obj["expiry_date"] as? Int {
            expiry = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else {
            expiry = nil
        }
        return GeminiCredentials(
            accessToken: accessToken,
            refreshToken: obj["refresh_token"] as? String,
            tokenType: obj["token_type"] as? String,
            expiryDate: expiry,
            idToken: obj["id_token"] as? String,
            scope: obj["scope"] as? String
        )
    }
}
