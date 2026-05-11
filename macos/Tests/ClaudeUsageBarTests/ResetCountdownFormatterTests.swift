import XCTest
@testable import ClaudeUsageBar

final class ResetCountdownFormatterTests: XCTestCase {
    func testHourMinute() {
        let now = Date()
        let target = now.addingTimeInterval(3600 + 23 * 60)  // 1h 23m
        XCTAssertEqual(formatResetCountdown(date: target, now: now), "1h 23m")
    }

    func testMinuteOnly() {
        let now = Date()
        let target = now.addingTimeInterval(12 * 60)  // 12m
        XCTAssertEqual(formatResetCountdown(date: target, now: now), "12m")
    }

    func testNilDate() {
        XCTAssertNil(formatResetCountdown(date: nil, now: Date()))
    }

    func testPastDate() {
        let now = Date()
        let target = now.addingTimeInterval(-5 * 60)  // 5m ago
        XCTAssertNil(formatResetCountdown(date: target, now: now))
    }

    func testSubMinute() {
        let now = Date()
        let target = now.addingTimeInterval(30)  // 30s
        XCTAssertEqual(formatResetCountdown(date: target, now: now), "<1m")
    }

    func testExactHour() {
        let now = Date()
        let target = now.addingTimeInterval(3600)  // 60s 边界：1h 0m
        XCTAssertEqual(formatResetCountdown(date: target, now: now), "1h 0m")
    }
}
