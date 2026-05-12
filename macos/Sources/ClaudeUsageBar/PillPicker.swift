import SwiftUI

/// 通用药丸式分段选择器，配色随 popover 卡片审美（不用系统 `.segmented`，避免那一行"出戏"）。
struct PillPicker<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Button { selection = item } label: {
                    Text(label(item))
                        .font(.caption.weight(item == selection ? .semibold : .regular))
                        .foregroundStyle(item == selection ? .primary : .secondary)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(item == selection ? Color(nsColor: .controlBackgroundColor) : .clear)
                                .shadow(color: item == selection ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.secondary.opacity(0.12)))
    }
}

#Preview("PillPicker") {
    struct Wrap: View {
        @State var sel = "1d"
        var body: some View {
            PillPicker(items: ["1h", "6h", "1d", "7d", "30d"], selection: $sel) { $0 }
                .padding()
                .frame(width: 340)
        }
    }
    return Wrap()
}
