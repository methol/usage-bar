import Foundation

/// 把 reset 目标时间格式化为 hero / secondary 卡片用的紧凑 countdown。
///
/// - 输出形如 `"1h 23m"`（≥1 小时）/ `"12m"`（仅分钟）/ `"<1m"`（不足 1 分钟）。
/// - `nil` 输入或已过期返回 `nil`，调用方据此隐藏 countdown UI。
func formatResetCountdown(date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let secs = Int(date.timeIntervalSince(now))
    if secs <= 0 { return nil }
    let h = secs / 3600
    let m = (secs % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "<1m"
}
