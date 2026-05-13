import Foundation

/// "此刻按匀速消耗应该用到多少 %" —— 即当前窗口内 elapsed 比例 ×100。
/// 用于在进度条上画一根 pace 标记竖线，以及算"当前 % 相对 pace 的偏差"。
/// `resetDate` 为 nil、已过期、或窗口尚未开始 → nil；正常 → 0...100。
///
/// （v0.0.11 的 `computePaceState`/`PaceState` 三档状态机已于 v0.2.4 退役 —— popover
/// 改为"进度条标记竖线 + Pace ±X% 偏差"，不再需要 onPace/inDeficit/inReserve 区分。）
func expectedPacePct(resetDate: Date?,
                     windowDuration: TimeInterval,
                     now: Date = Date()) -> Double? {
    guard let reset = resetDate, windowDuration > 0 else { return nil }
    guard reset.timeIntervalSince(now) > 0 else { return nil }
    let windowStart = reset.addingTimeInterval(-windowDuration)
    let elapsed = now.timeIntervalSince(windowStart)
    guard elapsed > 0 else { return nil }
    return min(max(elapsed / windowDuration, 0), 1) * 100
}
