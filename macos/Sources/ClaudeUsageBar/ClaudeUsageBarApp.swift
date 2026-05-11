import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var service = UsageService()
    @StateObject private var historyService = UsageHistoryService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appUpdater = AppUpdater()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                service: service,
                historyService: historyService,
                notificationService: notificationService,
                appUpdater: appUpdater
            )
        } label: {
            MenuBarLabel(service: service, historyService: historyService)
                .task {
                    historyService.loadHistory()
                    service.historyService = historyService
                    service.notificationService = notificationService
                    // v0.1.1: 启动期尝试复用 Claude CLI 凭证（Keychain 'Claude Code-credentials'）
                    // 内部已用 Task.detached 避免主线程阻塞
                    await service.bootstrapFromCLIIfNeeded()
                    // bootstrap 成功或本来已 sign in 的用户：标记 setup 完成不显示 SetupView
                    if service.isAuthenticated && !UserDefaults.standard.bool(forKey: "setupComplete") {
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                    }
                    service.startPolling()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowContent(
                service: service,
                notificationService: notificationService
            )
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }
}
