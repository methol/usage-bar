import SwiftUI

/// 菜单栏 label —— 显示「主 provider」（`ProviderCoordinator.primaryProviderID`）的用量。
/// v0.2.5：从读 `UsageService.usage` 改成读传入的 `ProviderRuntime.snapshot`（主 provider 的 runtime）。
struct MenuBarLabel: View {
    @ObservedObject var runtime: ProviderRuntime
    @ObservedObject var historyService: UsageHistoryService
    /// 是否对主 provider 显示趋势箭头 —— 趋势依赖历史样本，目前只有 Claude 有历史
    /// （= `coordinator.primaryProviderID == .claude`，由调用方算好传入）。
    var showTrend: Bool
    // @AppStorage 直接绑定 enum（SwiftUI 原生支持 RawRepresentable + RawValue == String）
    @AppStorage(MenuBarDisplayMode.storageKey) private var mode: MenuBarDisplayMode = .icon

    var body: some View {
        switch mode {
        case .icon:
            iconView
        case .percent:
            Text(percentText).monospacedDigit()
        case .percentWithTrend:
            HStack(spacing: 4) {
                Text(percentText).monospacedDigit()
                if let t = trend {
                    Text(trendText(t))
                        .monospacedDigit()
                        .foregroundStyle(t.direction == .up ? .red : .green)
                }
            }
        }
    }

    @ViewBuilder
    private var iconView: some View {
        Image(nsImage: runtime.isConfigured
            ? renderIcon(pct5h: primaryFraction, pct7d: secondaryFraction)
            : renderUnauthenticatedIcon())
    }

    /// 主 / 次窗口已用比例（0...1）—— `renderIcon` 接受的是 0...1。
    private var primaryFraction: Double { (runtime.snapshot?.primaryWindow?.utilizationPct ?? 0) / 100.0 }
    private var secondaryFraction: Double { (runtime.snapshot?.secondaryWindow?.utilizationPct ?? 0) / 100.0 }

    private var percentText: String {
        guard runtime.isConfigured else {
            return formatMenuBarPercent(utilization: nil, prefix: "5h")
        }
        return formatMenuBarPercent(utilization: runtime.snapshot?.primaryWindow?.utilizationPct, prefix: "5h")
    }

    private var trend: TrendIndicator? {
        guard runtime.isConfigured, showTrend else { return nil }
        return computeTrend(
            currentPct: runtime.snapshot?.primaryWindow?.utilizationPct,
            points: historyService.history.dataPoints,
            metric: \.pct5h
        )
    }

    private func trendText(_ t: TrendIndicator) -> String {
        let arrow = t.direction == .up ? "▲" : "▼"
        return "\(arrow)\(t.deltaPct)"
    }
}
