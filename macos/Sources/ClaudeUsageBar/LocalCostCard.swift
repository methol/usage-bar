import SwiftUI

struct LocalCostCard: View {
    let summary: CostSummary
    var periodLabel: String = "30 天"
    @State private var expanded = false

    private var totalCalls: Int { summary.perModel.reduce(0) { $0 + $1.calls } }
    private var totalTokens: Int {
        summary.perModel.reduce(0) {
            $0 + $1.inputTokens + $1.outputTokens + $1.cacheReadTokens + $1.cacheCreationTokens
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Collapsed header (always shown) ──────────────────────────
            HStack(spacing: 4) {
                Text("本地 \(periodLabel)估算")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "dollarsign.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(ExtraUsage.formatUSDCompact(summary.totalUSD))
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "number")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(ExtraUsage.formatTokens(totalCalls))
                    }
                    HStack(spacing: 2) {
                        Image(systemName: "cube.fill")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                        Text(ExtraUsage.formatTokens(totalTokens))
                    }
                }
                .font(.caption)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }

            // ── Expanded section ──────────────────────────────────────────
            if expanded {
                Divider().padding(.vertical, 1)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary.perModel.sorted(by: { $0.usd > $1.usd }), id: \.normalizedModel) { row in
                        let rowTokens = row.inputTokens + row.outputTokens + row.cacheReadTokens + row.cacheCreationTokens
                        HStack(spacing: 0) {
                            Text(row.normalizedModel)
                                .font(.caption2)
                                .foregroundStyle(row.isUnknownPricing ? Color.orange.opacity(0.8) : .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            HStack(spacing: 10) {
                                Text(ExtraUsage.formatTokens(row.calls))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(ExtraUsage.formatTokens(rowTokens))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(row.isUnknownPricing ? "—" : ExtraUsage.formatUSDCompact(row.usd))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                if summary.unknownModelCount > 0 {
                    Text("含 \(summary.unknownModelCount) 条未知模型调用（价格表过时？）")
                        .font(.caption2)
                        .foregroundStyle(Color.orange.opacity(0.8))
                }
                Text("ⓘ 仅读用量字段，不读对话内容")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
    }
}
