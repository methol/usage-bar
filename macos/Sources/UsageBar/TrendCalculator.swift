import Foundation

enum TrendDirection {
    case up
    case down
}

struct TrendIndicator: Equatable {
    let direction: TrendDirection
    let deltaPct: Int  // 绝对值，已 .rounded() 到整数百分点（非截断）
}

/// 计算 current vs lookback 时间前 baseline 的趋势。
///
/// 单位约定（spec §3.2 / G2 review B1）：
/// - currentPct 期望 0...100 百分制（直接传 `service.usage?.bucket?.utilization` 原始 API 值）
/// - points[*][metric] 实际是 0...1 unitless（UsageService 在 recordDataPoint 前已 / 100）
/// - 函数内部对 baseline `* 100.0` 与 currentPct 对齐
/// - 输出 deltaPct 单位为百分点（Int，已 .rounded() 非截断）
///
/// 返回 nil 的情形：currentPct nil / history 中无 ≤ (now-lookback) 的点 / |Δ| < 1pp (flat)
func computeTrend(
    currentPct: Double?,
    points: [UsageDataPoint],
    metric: KeyPath<UsageDataPoint, Double>,
    lookback: TimeInterval = 6 * 3600,
    now: Date = Date()
) -> TrendIndicator? {
    guard let current = currentPct else { return nil }
    let cutoff = now.addingTimeInterval(-lookback)
    let baselineCandidates = points.filter { $0.timestamp <= cutoff }
    // max(by: { $0.timestamp < $1.timestamp }) → timestamp 最大者 = "≤ cutoff 中最新一点"
    guard let baseline = baselineCandidates.max(by: { $0.timestamp < $1.timestamp }) else {
        return nil
    }
    let baselinePct100 = baseline[keyPath: metric] * 100.0
    let delta = current - baselinePct100
    let absDelta = abs(delta)
    if absDelta < 1.0 { return nil }
    return TrendIndicator(
        direction: delta > 0 ? .up : .down,
        deltaPct: Int(absDelta.rounded())
    )
}
