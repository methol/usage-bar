import SwiftUI

/// 单个用量窗口卡片：图标 + 标题 + 百分比 + 趋势；进度条；"Resets in:" + "Pace:" 底行。
/// （v0.2.4 起去掉 v0.0.8 的 hero / secondary 双尺寸，5h 与 7d 等权。）
struct UsageHeroCard: View {
    let label: String
    let bucket: UsageBucket?
    var trend: TrendIndicator? = nil
    var pace: PaceState? = nil
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
            CapsuleProgressBar(value: pctValue, color: pctColor)
                .frame(height: 8)
            if resetLine != nil || paceWordValue != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let resetLine {
                        Text("Resets in: \(resetLine)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let pw = paceWordValue {
                        Text("Pace: \(pw.text)")
                            .font(.caption)
                            .foregroundStyle(pw.color)
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
    private var paceWordValue: (text: String, color: Color)? { paceWord(pace) }

    private func trendText(for t: TrendIndicator) -> String {
        let arrow = t.direction == .up ? "▲" : "▼"
        return "\(arrow) \(t.deltaPct)%"
    }
}

/// PaceState → 卡片底行短标签。inReserve / onPace → "safe" 绿；inDeficit → "fast" 红；nil → 不显示。
func paceWord(_ pace: PaceState?) -> (text: String, color: Color)? {
    switch pace {
    case nil: return nil
    case .onPace, .inReserve: return ("safe", .green)
    case .inDeficit: return ("fast", .red)
    }
}

struct CapsuleProgressBar: View {
    let value: Double  // 期望 0...1，越界自动 clamp
    let color: Color

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
    }
}

#Preview("UsageHeroCard – 5h / 7d") {
    VStack(alignment: .leading, spacing: 10) {
        UsageHeroCard(label: "5-Hour",
                      bucket: UsageBucket(utilization: 42, resetsAt: "2099-01-01T23:44:00Z"),
                      trend: TrendIndicator(direction: .down, deltaPct: 2),
                      pace: .inReserve(percentUnder: 5),
                      icon: "clock")
        UsageHeroCard(label: "Weekly",
                      bucket: UsageBucket(utilization: 73, resetsAt: "2099-01-08T00:00:00Z"),
                      trend: TrendIndicator(direction: .up, deltaPct: 11),
                      pace: .inDeficit(percentOver: 14, runsOutIn: 259_200),
                      icon: "calendar")
        UsageHeroCard(label: "5-Hour (no data)", bucket: nil, icon: "clock")
    }
    .padding()
    .frame(width: 360)
}
