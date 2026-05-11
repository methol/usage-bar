import Foundation
import Security

struct ClaudeCLICredentialsStrategy: ClaudeUsageStrategy {
    static let serviceName = "Claude Code-credentials"

    /// Keychain JSON 顶层 schema (实测自 macOS 14 Claude CLI)：
    /// { "claudeAiOauth": { accessToken, refreshToken?, expiresAt(ms), scopes? },
    ///   "mcpOAuth": { ... } }  // mcpOAuth 不读
    /// `internal` 而非 `private` — 让 @testable import 单测能直接 decode 验证 schema
    /// 而无需 Keychain 实测。
    struct KeychainPayload: Decodable {
        let claudeAiOauth: ClaudeOauth

        struct ClaudeOauth: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Int64?  // ms timestamp
            let scopes: [String]?
        }
    }

    /// SC7 安全约束：CustomStringConvertible 仅输出 case 名，不带 OSStatus
    /// 数值（避免日志聚合工具二次解析数值码暴露异常类型分布）
    enum LoadError: Error, CustomStringConvertible {
        case keychainQueryFailed
        case payloadDecodeFailed

        var description: String {
            switch self {
            case .keychainQueryFailed: return "keychainQueryFailed"
            case .payloadDecodeFailed: return "payloadDecodeFailed"
            }
        }
    }

    func loadCredentials() async throws -> StoredCredentials? {
        // G3 B1 修订：SecItemCopyMatching 是同步 blocking C API；用 Task.detached
        // 把它挪到后台线程，避免主线程阻塞（首次 ACL 弹窗时尤其重要）
        let queryResult: (status: OSStatus, item: AnyObject?) = await Task.detached {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: Self.serviceName,
                kSecAttrAccount: NSUserName(),  // G2 E 修订：补 account 防 multi-account 顺序歧义
                kSecReturnData: true,
                kSecMatchLimit: kSecMatchLimitOne
            ]
            var item: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            return (status, item)
        }.value

        switch queryResult.status {
        case errSecSuccess:
            break
        case errSecItemNotFound,         // -25300 未装 Claude CLI 或无该 account 项
             errSecAuthFailed,            // -25293 ACL 验证失败
             errSecInteractionNotAllowed, // -25308 后台进程无法弹 ACL prompt
             errSecUserCanceled:          // -128 用户在 ACL prompt 上点取消
            return nil  // G2 F 修订：四种"权限/不存在"OSStatus 都静默降级
        default:
            throw LoadError.keychainQueryFailed
        }

        guard let data = queryResult.item as? Data else { return nil }
        guard let payload = try? JSONDecoder().decode(KeychainPayload.self, from: data) else {
            throw LoadError.payloadDecodeFailed
        }

        let oauth = payload.claudeAiOauth
        let expiry: Date? = oauth.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) }
        return StoredCredentials(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: expiry,
            scopes: oauth.scopes ?? []
        )
    }
}
