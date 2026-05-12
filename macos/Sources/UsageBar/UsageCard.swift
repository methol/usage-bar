import SwiftUI

/// popover 内容区块的统一圆角卡片容器（圆角 14 + 提亮材质 + 细描边 + 浅阴影）。
struct UsageCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview("UsageCard") {
    VStack(spacing: 10) {
        UsageCard {
            Text("卡片 A").font(.headline)
            Text("正文").foregroundStyle(.secondary)
        }
        UsageCard { Text("卡片 B") }
    }
    .padding()
    .frame(width: 360)
    .background(
        LinearGradient(colors: [Color.accentColor.opacity(0.06), .clear],
                       startPoint: .top, endPoint: .bottom)
    )
}
