import Foundation

struct StoredCredentials: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]

    func isExpired(at now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}
