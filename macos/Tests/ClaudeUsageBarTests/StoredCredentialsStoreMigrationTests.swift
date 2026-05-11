import XCTest
@testable import ClaudeUsageBar

final class StoredCredentialsStoreMigrationTests: XCTestCase {
    private var tempDir: URL!
    private var store: StoredCredentialsStore!
    private let scopes = ["user:profile"]

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("multi-account-mig-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = StoredCredentialsStore(directoryURL: tempDir)
    }

    override func tearDown() {
        // 恢复目录权限以便清理（chmod 测试可能改成 0o500）
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempDir.path)
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadAccountsPrefersV2File() throws {
        // 同时写 v1 + v2 → 应只读 v2
        let oldCreds = StoredCredentials(accessToken: "mock-old", refreshToken: nil, expiresAt: nil, scopes: scopes)
        try store.save(oldCreds)
        let v2 = StoredAccountsFile(version: 2, activeIndex: 0, accounts: [
            StoredAccount(id: UUID(), label: "v2", addedAt: Date(), lastUsed: Date(),
                         credentials: StoredCredentials(accessToken: "mock-new", refreshToken: nil, expiresAt: nil, scopes: scopes))
        ])
        try store.saveAccounts(v2)

        let loaded = store.loadAccounts(defaultScopes: scopes)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.accounts.first?.label, "v2")
        XCTAssertEqual(loaded?.activeAccount?.credentials.accessToken, "mock-new")
    }

    func testMigrateFromV1CredentialsJSON() throws {
        let oldCreds = StoredCredentials(accessToken: "mock-v1", refreshToken: "mock-refresh", expiresAt: Date(timeIntervalSince1970: 1_700_000_000), scopes: scopes)
        try store.save(oldCreds)

        let loaded = store.loadAccounts(defaultScopes: scopes)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.accounts.count, 1)
        XCTAssertEqual(loaded?.accounts.first?.label, "账号 1")
        XCTAssertEqual(loaded?.accounts.first?.credentials.accessToken, "mock-v1")
        XCTAssertEqual(loaded?.accounts.first?.credentials.refreshToken, "mock-refresh")
        // 迁移成功：旧文件已删
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.credentialsFileURL.path))
        // accounts.json 已落盘
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.accountsFileURL.path))
    }

    func testMigrateFromLegacyTokenFile() throws {
        // 写 legacy plaintext token file（无 credentials.json）
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "mock-legacy-token".write(to: store.legacyTokenFileURL, atomically: true, encoding: .utf8)

        let loaded = store.loadAccounts(defaultScopes: scopes)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.accounts.first?.credentials.accessToken, "mock-legacy-token")
        XCTAssertEqual(loaded?.accounts.first?.credentials.scopes, scopes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyTokenFileURL.path))
    }

    func testAccountsJSONFilePermissionsAre0600() throws {
        let file = StoredAccountsFile(version: 2, activeIndex: 0, accounts: [
            StoredAccount(id: UUID(), label: "x", addedAt: Date(), lastUsed: Date(),
                         credentials: StoredCredentials(accessToken: "mock", refreshToken: nil, expiresAt: nil, scopes: scopes))
        ])
        try store.saveAccounts(file)
        let attrs = try FileManager.default.attributesOfItem(atPath: store.accountsFileURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)
    }

    func testMigrationSaveFailureKeepsOldFile() throws {
        // G2-C/G3-B4: 用 mock FileManager 子类拦截 setAttributes 0600 抛错；
        // 不能用 chmod 路径因 ensureDirectoryExists 会主动 setAttributes 0o700 重置 dir 权限。
        let mockFM = SetAttributesFailureFileManager()
        let mockStore = StoredCredentialsStore(directoryURL: tempDir, fileManager: mockFM)

        // 先写 v1（mock 此时 failOnAccountsJSON=false，不影响 v1 save）
        let oldCreds = StoredCredentials(accessToken: "mock-keep", refreshToken: nil, expiresAt: nil, scopes: scopes)
        try mockStore.save(oldCreds)

        // 触发迁移阶段抛错
        mockFM.failOnAccountsJSON = true
        let loaded = mockStore.loadAccounts(defaultScopes: scopes)

        // 内存 migrated 对象返回（fail-safe：运行时不登出）
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.accounts.first?.credentials.accessToken, "mock-keep")

        // 旧 v1 credentials.json 文件**保留**（catch 块未到 remove）
        XCTAssertTrue(FileManager.default.fileExists(atPath: mockStore.credentialsFileURL.path))
        // 半成品 accounts.json 已 cleanup（G2-B2 修订）
        XCTAssertFalse(FileManager.default.fileExists(atPath: mockStore.accountsFileURL.path))
    }
}

/// 测试用 FileManager mock：setAttributes accounts.json 时抛错（模拟 setAttributes 失败）
private final class SetAttributesFailureFileManager: FileManager, @unchecked Sendable {
    var failOnAccountsJSON: Bool = false

    override func setAttributes(_ attributes: [FileAttributeKey : Any], ofItemAtPath path: String) throws {
        if failOnAccountsJSON && path.hasSuffix("accounts.json") {
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }
}
