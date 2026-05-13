import SwiftUI

struct AccountSwitcherView: View {
    @ObservedObject var service: UsageService

    var body: some View {
        // accounts.count <= 1 时整张隐藏（不打扰单账号用户 SC9）
        if service.accounts.count > 1,
           let active = service.accounts.first(where: { $0.id == service.activeAccountId }) {
            Menu {
                ForEach(service.accounts) { account in
                    Button {
                        service.switchAccount(to: account.id)
                    } label: {
                        HStack {
                            if account.id == service.activeAccountId {
                                Image(systemName: "checkmark")
                            }
                            Text(account.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle")
                    Text(active.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Switch account")
        }
    }
}
