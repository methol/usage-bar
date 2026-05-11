import XCTest
@testable import ClaudeUsageBar

final class LocalCostScannerTests: XCTestCase {
    private var tempDir: URL!
    private var cacheDir: URL!
    private var rootDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cost-scan-tests-\(UUID().uuidString)")
        cacheDir = tempDir.appendingPathComponent("cache")
        rootDir = tempDir.appendingPathComponent("projects-root")
        let projectDir = rootDir.appendingPathComponent("test-project")
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeFixture(_ name: String, lines: [String]) {
        let projectDir = rootDir.appendingPathComponent("test-project")
        let file = projectDir.appendingPathComponent(name)
        try? lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private func makeScanner() -> LocalCostScanner {
        LocalCostScanner(cacheDirOverride: cacheDir, scanRootsOverride: [rootDir])
    }

    private func makeAssistantLine(msgId: String, requestId: String, model: String, ts: String, input: Int = 0, output: Int = 0, cr: Int = 0, cc: Int = 0) -> String {
        return #"""
        {"type":"assistant","requestId":"\#(requestId)","timestamp":"\#(ts)","message":{"id":"\#(msgId)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":\#(cc),"cache_read_input_tokens":\#(cr)}}}
        """#
    }

    func testDeduplicationByMsgIdAndRequestId() async {
        // 5 行同 (msgId, requestId)，应仅算 1 次
        let line = makeAssistantLine(msgId: "m1", requestId: "r1", model: "claude-opus-4-7", ts: "2026-05-11T09:24:52Z", output: 1000)
        writeFixture("dup.jsonl", lines: Array(repeating: line, count: 5))

        let scanner = makeScanner()
        let summary = await scanner.scanForceRefresh(now: ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!)
        XCTAssertEqual(summary.perModel.count, 1)
        XCTAssertEqual(summary.perModel.first?.calls, 1)
        XCTAssertEqual(summary.perModel.first?.outputTokens, 1000)
    }

    func testWindowFilters30Days() async {
        let now = ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!
        let oldEvent = makeAssistantLine(msgId: "old", requestId: "rOld", model: "claude-opus-4-7", ts: "2026-04-10T10:00:00Z", output: 9999)  // 31 天前
        let recentEvent = makeAssistantLine(msgId: "new", requestId: "rNew", model: "claude-opus-4-7", ts: "2026-05-10T10:00:00Z", output: 100)  // 1 天前
        writeFixture("mixed.jsonl", lines: [oldEvent, recentEvent])

        let scanner = makeScanner()
        let summary = await scanner.scanForceRefresh(now: now)
        XCTAssertEqual(summary.perModel.first?.calls, 1)
        XCTAssertEqual(summary.perModel.first?.outputTokens, 100)
    }

    func testCacheHitWithin60s() async {
        let line = makeAssistantLine(msgId: "m", requestId: "r", model: "claude-opus-4-7", ts: "2026-05-11T09:24:52Z", output: 50)
        writeFixture("a.jsonl", lines: [line])

        let scanner = makeScanner()
        let now = ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!
        let first = await scanner.scan(now: now)
        XCTAssertGreaterThan(first.scannedFileCount, 0)

        // 写入新文件后 30s 内再 scan，应该命中 cache（不计新文件）
        writeFixture("b.jsonl", lines: [makeAssistantLine(msgId: "m2", requestId: "r2", model: "claude-opus-4-7", ts: "2026-05-11T09:30:00Z", output: 100)])
        let cached = await scanner.scan(now: now.addingTimeInterval(30))
        XCTAssertEqual(cached.generatedAt, first.generatedAt)
        XCTAssertEqual(cached.scannedFileCount, first.scannedFileCount)
    }

    func testCacheMissAfter60sCutoff() async {
        let line = makeAssistantLine(msgId: "m", requestId: "r", model: "claude-opus-4-7", ts: "2026-05-11T09:24:52Z", output: 50)
        writeFixture("a.jsonl", lines: [line])

        let scanner = makeScanner()
        let now = ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!
        let first = await scanner.scan(now: now)

        writeFixture("b.jsonl", lines: [makeAssistantLine(msgId: "m2", requestId: "r2", model: "claude-opus-4-7", ts: "2026-05-11T09:30:00Z", output: 100)])
        // 61s 后应 cache miss，重扫
        let refreshed = await scanner.scan(now: now.addingTimeInterval(61))
        XCTAssertNotEqual(refreshed.generatedAt, first.generatedAt)
        XCTAssertEqual(refreshed.scannedFileCount, 2)
    }

    func testUnknownModelFallback() async {
        let line = makeAssistantLine(msgId: "m", requestId: "r", model: "fake-model-99", ts: "2026-05-11T09:24:52Z", output: 9999)
        writeFixture("u.jsonl", lines: [line])

        let scanner = makeScanner()
        let summary = await scanner.scanForceRefresh(now: ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!)
        XCTAssertEqual(summary.totalUSD, 0)
        XCTAssertEqual(summary.unknownModelCount, 1)
        XCTAssertEqual(summary.perModel.first?.isUnknownPricing, true)
    }

    func testAggregationAccumulatesAcrossLines() async {
        let l1 = makeAssistantLine(msgId: "m1", requestId: "r1", model: "claude-opus-4-7", ts: "2026-05-11T09:24:00Z", input: 10, output: 100, cr: 1000, cc: 50)
        let l2 = makeAssistantLine(msgId: "m2", requestId: "r2", model: "claude-opus-4-7", ts: "2026-05-11T09:25:00Z", input: 20, output: 200, cr: 2000, cc: 100)
        writeFixture("agg.jsonl", lines: [l1, l2])

        let scanner = makeScanner()
        let summary = await scanner.scanForceRefresh(now: ISO8601DateFormatter().date(from: "2026-05-11T10:00:00Z")!)
        let row = summary.perModel.first
        XCTAssertEqual(row?.calls, 2)
        XCTAssertEqual(row?.inputTokens, 30)
        XCTAssertEqual(row?.outputTokens, 300)
        XCTAssertEqual(row?.cacheReadTokens, 3000)
        XCTAssertEqual(row?.cacheCreationTokens, 150)
    }

    func testScanRootsRespectsEnvOverride() {
        let home = URL(fileURLWithPath: "/fake/home")
        let envRoot = "/fake/env-config"
        let env = ["CLAUDE_CONFIG_DIR": envRoot]
        // fileExists 全 true：env、xdg、legacy 都返回
        let roots = LocalCostScanner.scanRoots(env: env, home: home, fileExists: { _ in true })
        XCTAssertEqual(roots.count, 3)
        XCTAssertEqual(roots[0].path, "/fake/env-config/projects")
        XCTAssertEqual(roots[1].path, "/fake/home/.config/claude/projects")
        XCTAssertEqual(roots[2].path, "/fake/home/.claude/projects")

        // 多路径 env：冒号分隔
        let envMulti = ["CLAUDE_CONFIG_DIR": "/r1:/r2"]
        let multi = LocalCostScanner.scanRoots(env: envMulti, home: home, fileExists: { _ in true })
        XCTAssertEqual(multi.prefix(2).map(\.path), ["/r1/projects", "/r2/projects"])

        // env 为空 + 仅 legacy 存在
        let onlyLegacy = LocalCostScanner.scanRoots(env: [:], home: home, fileExists: { $0.hasSuffix(".claude/projects") })
        XCTAssertEqual(onlyLegacy.count, 1)
        XCTAssertEqual(onlyLegacy[0].path, "/fake/home/.claude/projects")
    }
}
