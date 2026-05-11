import XCTest
@testable import ClaudeUsageBar

final class TrendCalculatorTests: XCTestCase {
    private func makePoint(secondsAgo: TimeInterval, pct5h: Double, pct7d: Double = 0, now: Date) -> UsageDataPoint {
        UsageDataPoint(
            timestamp: now.addingTimeInterval(-secondsAgo),
            pct5h: pct5h,
            pct7d: pct7d
        )
    }

    func testUpTrend() {
        let now = Date()
        // baseline 6.5h 前 pct5h=0.40 (40%)，current 50% → Δ=+10 → ▲ 10
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.40, now: now)]
        let trend = computeTrend(
            currentPct: 50,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .up, deltaPct: 10))
    }

    func testDownTrend() {
        let now = Date()
        // baseline 6.5h 前 pct5h=0.60 (60%)，current 55% → Δ=-5 → ▼ 5
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.60, now: now)]
        let trend = computeTrend(
            currentPct: 55,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .down, deltaPct: 5))
    }

    func testFlat() {
        let now = Date()
        // baseline 6.5h 前 pct5h=0.50 (50%)，current 50.4% → |Δ|=0.4 < 1 → nil
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.50, now: now)]
        let trend = computeTrend(
            currentPct: 50.4,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertNil(trend)
    }

    func testInsufficientData() {
        let now = Date()
        // 只有 1h 前的点，lookback 6h → 找不到 baseline → nil
        let points = [makePoint(secondsAgo: 3600, pct5h: 0.30, now: now)]
        let trend = computeTrend(
            currentPct: 50,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertNil(trend)
    }

    func testNilCurrent() {
        let now = Date()
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.40, now: now)]
        let trend = computeTrend(
            currentPct: nil,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertNil(trend)
    }

    func testRoundingBoundaryDown() {
        let now = Date()
        // baseline pct5h=0.50 (50%)，current 50.9% → |Δ|=0.9 < 1 → nil（边界外）
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.50, now: now)]
        let trend = computeTrend(
            currentPct: 50.9,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertNil(trend)
    }

    func testRoundingBoundaryUp() {
        let now = Date()
        // baseline pct5h=0.50 (50%)，current 51.4% → |Δ|=1.4 → .rounded()→1（不截断为 1）
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.50, now: now)]
        let trend = computeTrend(
            currentPct: 51.4,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .up, deltaPct: 1))
    }

    func testBaselineLatestBeforeCutoff() {
        let now = Date()
        // 多个 ≤ 6h 前的点，应取最新（接近 cutoff）的那个
        let points = [
            makePoint(secondsAgo: 24 * 3600, pct5h: 0.10, now: now),  // 24h 前
            makePoint(secondsAgo: 12 * 3600, pct5h: 0.30, now: now),  // 12h 前
            makePoint(secondsAgo: 7 * 3600, pct5h: 0.45, now: now),   // 7h 前（应被选为 baseline）
            makePoint(secondsAgo: 1 * 3600, pct5h: 0.80, now: now),   // 1h 前（< 6h 不算）
        ]
        // current 50%，baseline 0.45 (45%) → Δ=+5
        let trend = computeTrend(
            currentPct: 50,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .up, deltaPct: 5))
    }

    /// 显式覆盖 G2 review B1 修订点：UsageDataPoint.pct5h 是 0-1 unitless，
    /// currentPct 是 0-100 百分制；computeTrend 内部 baseline*100 与 currentPct
    /// 对齐。若未来有人把 `* 100.0` 误删，本 case 会失败。
    func testUnitConversion_baselineIsZeroToOne() {
        let now = Date()
        // pct5h=0.30 (即 30%) ←→ currentPct=80 (80%) → Δ=+50 ▲
        // 若 *100 被删，delta = 80 - 0.30 = 79.7 → ▲ 80（明显异常）
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.30, now: now)]
        let trend = computeTrend(
            currentPct: 80,
            points: points,
            metric: \.pct5h,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .up, deltaPct: 50))
    }

    func testPct7dMetric() {
        let now = Date()
        // 测试 KeyPath 切换到 pct7d
        let points = [makePoint(secondsAgo: 6.5 * 3600, pct5h: 0.99, pct7d: 0.20, now: now)]
        let trend = computeTrend(
            currentPct: 30,
            points: points,
            metric: \.pct7d,
            now: now
        )
        XCTAssertEqual(trend, TrendIndicator(direction: .up, deltaPct: 10))
    }
}
