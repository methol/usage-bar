import XCTest
@testable import ClaudeUsageBar

final class ClaudeUsageCollectorTests: XCTestCase {
    private var tmpRoot: URL!     // 模拟 ~/.claude/projects
    private var tmpData: URL!     // 模拟 ~/.config/claude-usage-bar/data
    override func setUpWithError() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("collector-test-\(UUID().uuidString)", isDirectory: true)
        tmpRoot = base.appendingPathComponent("projects", isDirectory: true)
        tmpData = base.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpData, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpRoot.deletingLastPathComponent()) }

    private func assistantLine(ts: String, msg: String, req: String, model: String = "claude-opus-4-7", input: Int = 100, output: Int = 50) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(msg)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }
    private func writeSession(_ dir: String, _ uuid: String, lines: [String], trailingNewline: Bool = true) throws -> URL {
        let projDir = tmpRoot.appendingPathComponent(dir, isDirectory: true)
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let f = projDir.appendingPathComponent("\(uuid).jsonl")
        try (lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).data(using: .utf8)!.write(to: f)
        return f
    }
    private func makeCollector() -> ClaudeUsageCollector {
        ClaudeUsageCollector(store: UsageEventStore(dataDirOverride: tmpData),
                             cursor: ScanCursorStore(dataDirOverride: tmpData),
                             scanRootsOverride: [tmpRoot])
    }

    func testFirstScanBackfillsAllHistoryAcrossMonths() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-04-15T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
            assistantLine(ts: "2026-05-15T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b"),
        ])
        let r = await makeCollector().collect()
        XCTAssertEqual(r.newEventCount, 2)
        XCTAssertEqual(r.scannedFileCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpData.appendingPathComponent("claude/2026-04.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpData.appendingPathComponent("claude/2026-05.json").path))
    }
    func testIncrementalSecondScanOnlyCountsNewLines() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData)
        let cursor = ScanCursorStore(dataDirOverride: tmpData)
        let f = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let c1 = ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot])
        let n1 = await c1.collect().newEventCount
        XCTAssertEqual(n1, 1)
        var content = try String(contentsOf: f, encoding: .utf8)
        content += assistantLine(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b") + "\n"
        try content.data(using: .utf8)!.write(to: f)
        let c2 = ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot])
        let n2 = await c2.collect().newEventCount
        XCTAssertEqual(n2, 1)
    }
    func testNoNewEventsReturnsZeroAndNoWrite() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        _ = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        let monthPath = tmpData.appendingPathComponent("claude/2026-05.json").path
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: monthPath)[.modificationDate] as! Date
        let r = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r.newEventCount, 0)
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: monthPath)[.modificationDate] as! Date
        XCTAssertEqual(mtimeBefore, mtimeAfter)
    }
    func testPartialLastLineNotConsumed() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        let f = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
            #"{"type":"assistant","requestId":"req_mock_b","timestamp":"2026-05-11T10:"#,
        ], trailingNewline: false)
        let r1 = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r1.newEventCount, 1)
        try (assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a") + "\n"
            + assistantLine(ts: "2026-05-11T10:00:00.000Z", msg: "msg_mock_b", req: "req_mock_b") + "\n").data(using: .utf8)!.write(to: f)
        let r2 = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        XCTAssertEqual(r2.newEventCount, 1)
    }
    func testParseErrorDoesNotAbortScan() async throws {
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: [
            "{ garbage",
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"),
        ])
        let r = await makeCollector().collect()
        XCTAssertEqual(r.newEventCount, 1)
        XCTAssertGreaterThanOrEqual(r.parseErrorCount, 1)
    }
    func testDeduplicatesAcrossRepeatedCollect() async throws {
        let store = UsageEventStore(dataDirOverride: tmpData), cursor = ScanCursorStore(dataDirOverride: tmpData)
        _ = try writeSession("p1", "00000000-mock-0000-0000-000000000001", lines: Array(repeating:
            assistantLine(ts: "2026-05-10T10:00:00.000Z", msg: "msg_mock_a", req: "req_mock_a"), count: 4))
        _ = await ClaudeUsageCollector(store: store, cursor: cursor, scanRootsOverride: [tmpRoot]).collect()
        let got = await store.queryEvents(from: ISO8601DateFormatter().date(from: "2026-05-01T00:00:00Z")!,
                                          to: ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!)
        XCTAssertEqual(got.count, 1)
    }
}
