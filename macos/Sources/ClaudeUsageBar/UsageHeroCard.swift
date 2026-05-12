import SwiftUI

/// pace 标记竖线的颜色（"深蓝色"）。light/dark 都够对比。
let paceMarkerColor = Color(red: 0.11, green: 0.24, blue: 0.60)

/// 单个用量窗口卡片：图标 + 标题 + 百分比 + 趋势；进度条（含 pace 标记竖线）；
/// "Resets in:" + "Pace: ±X%" 底行。
struct UsageHeroCard: View {
    let label: String
    let bucket: UsageBucket?
    var trend: TrendIndicator? = nil
    /// "此刻应该用到多少 %"（0...100）。nil = 不画标记线、不显示 Pace 偏差。
    var pacePct: Double? = nil
    var icon: String = "gauge"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(label, systemImage: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentageText)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pctColor)
                if let trend {
                    Text(trendText(for: trend))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(trend.direction == .up ? .red : .green)
                }
            }
            CapsuleProgressBar(value: pctValue, color: pctColor, marker: markerFraction)
                .frame(height: 8)
            if resetLine != nil || paceDeviation != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let resetLine {
                        Text("Resets in: \(resetLine)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let dev = paceDeviation {
                        Text("Pace: \(dev > 0 ? "+" : "")\(dev)%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(dev > 0 ? .red : .green)
                    }
                }
            }
        }
    }

    private var pctValue: Double { (bucket?.utilization ?? 0) / 100.0 }
    private var pctColor: Color { colorForPct(pctValue) }
    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }
    private var resetLine: String? { formatResetWithClock(date: bucket?.resetsAtDate, now: Date()) }

    /// pace 竖线在进度条上的位置（0...1）。pacePct 为 nil → 不画。
    private var markerFraction: Double? {
        guard let p = pacePct else { return nil }
        return min(max(p / 100.0, 0), 1)
    }

    /// 当前 % 相对 pace 的有符号偏差（四舍五入）。正 = 用超了。
    private var paceDeviation: Int? {
        guard let p = pacePct, let current = bucket?.utilization else { return nil }
        return Int((current - p).rounded())
    }

    private func trendText(for t: TrendIndicator) -> String {
        let arrow = t.direction == .up ? "▲" : "▼"
        return "\(arrow) \(t.deltaPct)%"
    }
}

struct CapsuleProgressBar: View {
    let value: Double            // 期望 0...1，越界自动 clamp
    let color: Color
    var marker: Double? = nil    // 0...1：pace 标记竖线位置；nil = 不画

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.15))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, min(1, value)) * geo.size.width)
                }
            }
            .overlay(alignment: .leading) {
                if let marker {
                    GeometryReader { geo in
                        let lineWidth: CGFloat = 2.5
                        let x = max(0, min(1, marker)) * geo.size.width - lineWidth / 2
                        RoundedRectangle(cornerRadius: 1)
                            .fill(paceMarkerColor)
                            .frame(width: lineWidth, height: geo.size.height + 4)
                            .offset(x: min(max(0, x), max(0, geo.size.width - lineWidth)), y: -2)
                    }
                }
            }
    }
}

#Preview("UsageHeroCard – Session / Weekly") {
    VStack(alignment: .leading, spacing: 10) {
        UsageHeroCard(label: "Session",
                      bucket: UsageBucket(utilization: 42, resetsAt: "2099-01-01T23:44:00Z"),
                      trend: TrendIndicator(direction: .down, deltaPct: 2),
                      pacePct: 55,   // pace 55% → 偏差 -13%（绿）
                      icon: "clock")
        UsageHeroCard(label: "Weekly",
                      bucket: UsageBucket(utilization: 73, resetsAt: "2099-01-08T00:00:00Z"),
                      trend: TrendIndicator(direction: .up, deltaPct: 11),
                      pacePct: 50,   // pace 50% → 偏差 +23%（红）
                      icon: "calendar")
        UsageHeroCard(label: "Session (no data)", bucket: nil, icon: "clock")
    }
    .padding()
    .frame(width: 360)
}
