import XCTest
@testable import ClaudeUsageBar

final class CodexUsageCollectorTests: XCTestCase {
    private var tmp: URL!
    private var sessionsDir: URL!
    private var rolloutFile: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        sessionsDir = tmp.appendingPathComponent("sessions/2026/05/12", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        rolloutFile = sessionsDir.appendingPathComponent("rollout-2026-05-12T07-00-00-019e1bee-0948-75c3-ae1a-bab380a1ffa9.jsonl")
        let lines = [
            #"{"timestamp":"2026-05-12T07:00:00.000Z","type":"turn_context","payload":{"model":"gpt-5.5"}}"#,
            #"{"timestamp":"2026-05-12T07:00:01.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":300,"reasoning_output_tokens":0,"total_tokens":1300},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":300,"reasoning_output_tokens":0,"total_tokens":1300}}}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").data(using: .utf8)!.write(to: rolloutFile)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeCollector() -> (CodexUsageCollector, UsageEventStore) {
        let store = UsageEventStore(dataDirOverride: tmp, provider: .codex)
        let cursor = ScanCursorStore(dataDirOverride: tmp, provider: .codex)
        return (CodexUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmp.appendingPathComponent("sessions")]), store)
    }

    func testCollectFindsEventsAndAggregates() async throws {
        let (c, store) = makeCollector()
        let r1 = await c.collect()
        XCTAssertGreaterThan(r1.newEventCount, 0)
        let day = await store.readDayAggregates()
        XCTAssertFalse(day.isEmpty)
    }
    func testSecondCollectSkipsUnchangedFile() async throws {
        let (c, _) = makeCollector()
        _ = await c.collect()
        let r2 = await c.collect()
        XCTAssertEqual(r2.newEventCount, 0)
    }
    func testAppendedLineReParsesAndDedups() async throws {
        let (c, store) = makeCollector()
        _ = await c.collect()
        let far = Date(timeIntervalSince1970: 0); let future = Date().addingTimeInterval(86400 * 3650)
        let beforeCount = await store.queryEvents(from: far, to: future).count
        XCTAssertEqual(beforeCount, 1)
        let extra = #"{"timestamp":"2026-05-12T07:05:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":0,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":600},"total_token_usage":{"input_tokens":1500,"cached_input_tokens":200,"output_tokens":400,"reasoning_output_tokens":0,"total_tokens":1900}}}}"# + "\n"
        let fh = try FileHandle(forWritingTo: rolloutFile); fh.seekToEndOfFile(); fh.write(extra.data(using: .utf8)!); fh.closeFile()
        let r = await c.collect()
        // 整文件 re-parse → 解析出 2 个 token_count event（与 Claude collector 一致：newEventCount = 本次解析数）
        XCTAssertEqual(r.newEventCount, 2)
        // (msgId,reqId)=sessionId:lineIndex 去重 → store 里只净增 1 个 → 共 2 个
        let afterCount = await store.queryEvents(from: far, to: future).count
        XCTAssertEqual(afterCount, 2)
    }
    func testScanRootsParsesCodexHome() {
        let roots = CodexUsageCollector.scanRoots(env: ["CODEX_HOME": tmp.path], home: URL(fileURLWithPath: "/nonexistent"), fileExists: { _ in true })
        XCTAssertEqual(roots.first, tmp.appendingPathComponent("sessions"))
    }
    func testScanRootsFallsBackToHomeCodex() {
        let expected = tmp.appendingPathComponent(".codex/sessions", isDirectory: true)
        let roots = CodexUsageCollector.scanRoots(env: [:], home: tmp, fileExists: { $0 == expected.path })
        XCTAssertEqual(roots, [expected])
    }
}
