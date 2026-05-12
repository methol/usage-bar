import SwiftUI

/// Three icon+value badges: $ amount · # calls · cube tokens.
/// Used both in the cost card total header AND the heatmap hover line.
struct UsageMetricBadges: View {
    let usd: Double
    let calls: Int
    let tokens: Int

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: "dollarsign.circle.fill")
                Text(ExtraUsage.formatUSDCompact(usd))
            }
            HStack(spacing: 2) {
                Image(systemName: "number")
                Text(ExtraUsage.formatTokens(calls))
            }
            HStack(spacing: 2) {
                Image(systemName: "cube.fill")
                Text(ExtraUsage.formatTokens(tokens))
            }
        }
        .imageScale(.small)
        .foregroundStyle(.secondary)
    }
}

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
            // ── Header + rows in one Grid ──────────────────────────────────
            HStack(alignment: .center, spacing: 4) {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                    // Header row (always shown)
                    GridRow {
                        Text("本地 \(periodLabel)估算")
                            .gridColumnAlignment(.leading)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "number").imageScale(.small)
                            Text(ExtraUsage.formatTokens(totalCalls))
                        }
                        .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "cube.fill").imageScale(.small)
                            Text(ExtraUsage.formatTokens(totalTokens))
                        }
                        .foregroundStyle(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "dollarsign.circle.fill").imageScale(.small)
                            Text(ExtraUsage.formatUSDCompact(summary.totalUSD))
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    // Divider spanning all 4 columns (only when expanded)
                    if expanded {
                        GridRow {
                            Divider()
                                .gridCellColumns(4)
                                .gridCellUnsizedAxes(.horizontal)
                                .padding(.vertical, 1)
                        }

                        // Per-model rows
                        ForEach(summary.perModel.sorted(by: { $0.usd > $1.usd }), id: \.normalizedModel) { row in
                            let rowTokens = row.inputTokens + row.outputTokens + row.cacheReadTokens + row.cacheCreationTokens
                            GridRow {
                                Text(row.normalizedModel)
                                    .gridColumnAlignment(.leading)
                                    .foregroundStyle(row.isUnknownPricing ? Color.orange.opacity(0.8) : .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(ExtraUsage.formatTokens(row.calls))
                                    .foregroundStyle(.secondary)
                                Text(ExtraUsage.formatTokens(rowTokens))
                                    .foregroundStyle(.tertiary)
                                Text(row.isUnknownPricing ? "—" : ExtraUsage.formatUSDCompact(row.usd))
                            }
                            .font(.caption2)
                        }
                    }
                }

                // Chevron outside the Grid
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }

            // ── Footnotes (only when expanded) ───────────────────────────
            if expanded {
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
