import XCTest
@testable import ClaudeUsageBar

final class UsagePaceAreaTests: XCTestCase {
    func testNilResetReturnsEmpty() {
        let now = Date()
        let s = UsagePaceArea.series(reset: nil, windowDuration: 5 * 3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now)
        XCTAssertTrue(s.isEmpty)
    }

    func testSampleCount() {
        let now = Date()
        let s = UsagePaceArea.series(reset: now.addingTimeInterval(3600), windowDuration: 5 * 3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now,
                                     sampleCount: 10)
        XCTAssertEqual(s.count, 11)  // sampleCount + 1
    }

    func testWithinSingleWindowMonotonicAndApproachesFull() {
        // domain 完全落在最后一个 5h 窗口内：reset = now+1h，windowStart = now+1h-5h = now-4h
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let s = UsagePaceArea.series(reset: reset, windowDuration: 5 * 3600,
                                     domainStart: now.addingTimeInterval(-3600), domainEnd: now,
                                     sampleCount: 50)
        let pcts = s.map(\.pct)
        for i in 1..<pcts.count { XCTAssertGreaterThanOrEqual(pcts[i], pcts[i - 1] - 1e-6) }
        XCTAssertEqual(pcts.last!, 80, accuracy: 0.5)   // domainEnd = now → elapsed 4h/5h
        XCTAssertEqual(pcts.first!, 60, accuracy: 0.5)  // domainStart = now-1h → elapsed 3h/5h
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    func testCrossesWindowBoundarySawtooth() {
        // reset = now+1h，5h 窗口边界在 now-4h；让 domain 从 now-6h 跨过它
        let now = Date()
        let reset = now.addingTimeInterval(3600)
        let s = UsagePaceArea.series(reset: reset, windowDuration: 5 * 3600,
                                     domainStart: now.addingTimeInterval(-6 * 3600),
                                     domainEnd: now, sampleCount: 600)
        let pcts = s.map(\.pct)
        XCTAssertTrue(pcts.contains { $0 > 95 }, "expected a near-100 sample before boundary")
        XCTAssertTrue(pcts.contains { $0 < 5 }, "expected a near-0 sample after boundary")
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }

    func testSevenDaySingleRamp() {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 86400)  // 2 天后 reset，7d 窗口 → windowStart = now-5d
        let s = UsagePaceArea.series(reset: reset, windowDuration: 7 * 86400,
                                     domainStart: now.addingTimeInterval(-30 * 86400), domainEnd: now,
                                     sampleCount: 100)
        let pcts = s.map(\.pct)
        XCTAssertEqual(pcts.count, 101)
        XCTAssertEqual(pcts.last!, 5.0 / 7.0 * 100, accuracy: 0.5)  // now: elapsed 5d/7d
        XCTAssertTrue(pcts.allSatisfy { $0 >= 0 && $0 <= 100 })
    }
}
