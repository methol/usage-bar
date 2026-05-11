import Foundation

struct StoredAccount: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    let addedAt: Date
    var lastUsed: Date
    var credentials: StoredCredentials
}

struct StoredAccountsFile: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    var activeIndex: Int
    var accounts: [StoredAccount]

    /// activeIndex clamp 到合法范围；空数组返回 nil（防御 manual edit 越界）
    var activeAccount: StoredAccount? {
        guard !accounts.isEmpty else { return nil }
        let idx = min(max(activeIndex, 0), accounts.count - 1)
        return accounts[idx]
    }

    var clampedActiveIndex: Int? {
        guard !accounts.isEmpty else { return nil }
        return min(max(activeIndex, 0), accounts.count - 1)
    }
}

extension StoredCredentialsStore {
    /// v0.1.3: multi-account 主入口。
    /// - 优先 accounts.json (v2 schema)
    /// - 回退 v1 credentials.json + legacyTokenFileURL（复用 load() 的 fallback 链，不重复实现 G3-R5）
    /// - 迁移 fail-safe：saveAccounts 失败保留旧文件不删，返回内存 migrated 对象供本会话继续运行（G2-B2 修订：catch 块清理半成品 accounts.json）
    func loadAccounts(defaultScopes: [String]) -> StoredAccountsFile? {
        if let data = try? Data(contentsOf: accountsFileURL),
           let file = try? Self.decoder.decode(StoredAccountsFile.self, from: data) {
            return file
        }
        guard let oldCreds = load(defaultScopes: defaultScopes) else { return nil }
        let now = Date()
        let migrated = StoredAccountsFile(
            version: StoredAccountsFile.currentVersion,
            activeIndex: 0,
            accounts: [StoredAccount(
                id: UUID(),
                label: "账号 1",
                addedAt: now,
                lastUsed: now,
                credentials: oldCreds
            )]
        )
        do {
            try saveAccounts(migrated)
            try? fileManager.removeItem(at: credentialsFileURL)
            try? fileManager.removeItem(at: legacyTokenFileURL)
        } catch {
            // G2-B2: 写半成品时清理；setAttributes 失败也走此路径
            try? fileManager.removeItem(at: accountsFileURL)
            NSLog("[claude-usage-bar] accounts migration save: \(type(of: error))")
        }
        return migrated
    }

    func saveAccounts(_ file: StoredAccountsFile) throws {
        try ensureDirectoryExists()
        let data = try Self.encoder.encode(file)
        try data.write(to: accountsFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: accountsFileURL.path)
    }

    /// 仅删 accounts.json，不动 history.json / cost cache（G2 ADVISORY）
    func deleteAccounts() {
        try? fileManager.removeItem(at: accountsFileURL)
    }
}
