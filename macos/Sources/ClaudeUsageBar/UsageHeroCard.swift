import SwiftUI

enum UsageCardSize {
    case hero       // 5h 主卡片，56pt 大字号
    case secondary  // 7d 次卡片，28pt 中字号
}

struct UsageHeroCard: View {
    let size: UsageCardSize
    let label: String
    let bucket: UsageBucket?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(labelFont)
                    .foregroundStyle(.secondary)
                Spacer()
                if let countdown {
                    Text(countdown)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(percentageText)
                    .font(.system(size: pctFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colorForPct(pctValue))
                Spacer()
            }
            CapsuleProgressBar(value: pctValue, color: colorForPct(pctValue))
                .frame(height: 8)
        }
    }

    private var pctFontSize: CGFloat {
        switch size {
        case .hero: return 56
        case .secondary: return 28
        }
    }

    private var labelFont: Font {
        switch size {
        case .hero: return .subheadline
        case .secondary: return .caption
        }
    }

    private var pctValue: Double {
        (bucket?.utilization ?? 0) / 100.0
    }

    private var percentageText: String {
        guard let pct = bucket?.utilization else { return "—" }
        return "\(Int(round(pct)))%"
    }

    private var countdown: String? {
        guard let resetDate = bucket?.resetsAtDate else { return nil }
        return formatResetCountdown(date: resetDate, now: Date())
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

#Preview("Hero card – three thresholds") {
    VStack(alignment: .leading, spacing: 12) {
        UsageHeroCard(
            size: .hero,
            label: "5-Hour",
            bucket: UsageBucket(utilization: 42, resetsAt: "2099-01-01T00:00:00Z")
        )
        UsageHeroCard(
            size: .secondary,
            label: "7-Day",
            bucket: UsageBucket(utilization: 73, resetsAt: "2099-01-08T00:00:00Z")
        )
        UsageHeroCard(
            size: .secondary,
            label: "Edge: 100%",
            bucket: UsageBucket(utilization: 100, resetsAt: "2099-01-01T00:30:00Z")
        )
    }
    .padding()
    .frame(width: 360)
}
