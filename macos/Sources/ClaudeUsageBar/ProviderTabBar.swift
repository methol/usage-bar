import SwiftUI

/// popover 顶部多 provider 切换 tab 的 UI 维度。
/// 注意：与存储层的 `UsageProvider`（`UsageStoreTypes.swift`，Codable、用作 data/<provider>/ 目录名）
/// 是两个东西 —— 本枚举纯 UI，只有 Claude 拉通了数据层（见 ADR 0005，其余 provider 是占位）。
enum ProviderTab: String, CaseIterable, Identifiable {
    case claude, codex, cursor, copilot, gemini

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }   // "claude" → "Claude"
    var isAvailable: Bool { self == .claude }
}

/// popover 顶部的多 provider 药丸 tab。不可用的 provider 仍可点选，
/// 由调用方在 selection 非 Claude 时展示 `ProviderComingSoonView`。
struct ProviderTabBar: View {
    @Binding var selection: ProviderTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProviderTab.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    Text(provider.displayName)
                        .font(.caption.weight(provider == selection ? .semibold : .regular))
                        .foregroundStyle(pillForeground(for: provider))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(provider == selection ? Color(nsColor: .controlBackgroundColor) : .clear)
                                .shadow(color: provider == selection ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                        )
                        .contentShape(Rectangle())   // 整个药丸（含两侧空白）都可点
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private func pillForeground(for provider: ProviderTab) -> Color {
        if provider == selection { return .primary }
        return provider.isAvailable ? .secondary : .secondary.opacity(0.5)
    }
}

/// 选中一个尚未拉通数据层的 provider 时显示。
struct ProviderComingSoonView: View {
    let provider: ProviderTab
    var onBackToClaude: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("\(provider.displayName) 支持开发中，敬请期待")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("← 回到 Claude", action: onBackToClaude)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview("ProviderTabBar") {
    struct Wrap: View {
        @State var sel: ProviderTab = .claude
        var body: some View {
            VStack(spacing: 12) {
                ProviderTabBar(selection: $sel)
                if sel != .claude {
                    ProviderComingSoonView(provider: sel, onBackToClaude: { sel = .claude })
                }
            }
            .padding()
            .frame(width: 360)
        }
    }
    return Wrap()
}
