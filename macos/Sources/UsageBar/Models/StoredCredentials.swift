import Foundation

struct StoredCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]

    var hasRefreshToken: Bool {
        guard let refreshToken else { return false }
        return refreshToken.isEmpty == false
    }

    func needsRefresh(at now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        guard hasRefreshToken, let expiresAt else { return false }
        return expiresAt <= now.addingTimeInterval(leeway)
    }

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

extension StoredCredentials {
    /// CLI 只读路径专用：返回不含 refreshToken 的副本，避免持有 CLI 的 refresh token
    /// 导致 OAuth Token Rotation 使 Claude Code 被迫退出登录（issue #22）。
    func strippingRefreshToken() -> StoredCredentials {
        StoredCredentials(accessToken: accessToken, refreshToken: nil, expiresAt: expiresAt, scopes: scopes)
    }
}
