import SwiftUI

/// 菜单栏 label —— 将所有已启用且已注册的 provider 并排展示（按 orderedProviderIDs 顺序）。
/// 各 provider 的显示由各自的 `MenuBarLabel` 负责；启用/禁用变化实时反映。
struct MultiMenuBarLabel: View {
    @ObservedObject var coordinator: ProviderCoordinator

    var body: some View {
        HStack(spacing: 6) {
            ForEach(coordinator.availableIDs, id: \.self) { id in
                if let runtime = coordinator.runtime(for: id) {
                    MenuBarLabel(runtime: runtime, providerID: id)
                }
            }
        }
    }
}
