import XCTest
@testable import ClaudeUsageBar

final class PaceCalculatorTests: XCTestCase {
    private func reset(after secs: TimeInterval, from now: Date) -> Date {
        now.addingTimeInterval(secs)
    }

    // MARK: - expectedPacePct

    func testExpectedPace_nilResetOrPast() {
        let now = Date()
        XCTAssertNil(expectedPacePct(resetDate: nil, windowDuration: 5 * 3600, now: now))
        XCTAssertNil(expectedPacePct(resetDate: now.addingTimeInterval(-60), windowDuration: 5 * 3600, now: now))
    }

    func testExpectedPace_midWindow() {
        let now = Date()
        // 5h 窗口，reset 在 now+1h → windowStart = now-4h → elapsed 4h/5h = 80%
        let p = expectedPacePct(resetDate: reset(after: 3600, from: now), windowDuration: 5 * 3600, now: now)
        XCTAssertEqual(p ?? -1, 80, accuracy: 0.01)
    }

    func testExpectedPace_sevenDay() {
        let now = Date()
        // 7d 窗口，reset 在 now+2d → windowStart = now-5d → elapsed 5d/7d
        let p = expectedPacePct(resetDate: now.addingTimeInterval(2 * 86400), windowDuration: 7 * 86400, now: now)
        XCTAssertEqual(p ?? -1, 5.0 / 7.0 * 100, accuracy: 0.01)
    }

    func testExpectedPace_clampedToHundred() {
        let now = Date()
        // reset 仅 1 秒后、窗口 5h → elapsed ≈ 5h → 100%（且不超过 100）
        let p = expectedPacePct(resetDate: now.addingTimeInterval(1), windowDuration: 5 * 3600, now: now)
        XCTAssertNotNil(p)
        XCTAssertEqual(p ?? -1, 100, accuracy: 0.1)
        XCTAssertLessThanOrEqual(p ?? 999, 100)
    }
}
