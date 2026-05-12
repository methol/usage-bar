import Foundation
import Combine

/// Codex provider —— 复用本机 `codex` CLI 已登录的 ChatGPT 凭证（`~/.codex/auth.json`，**只读**）
/// 拉 `chatgpt.com/backend-api/wham/usage`。无通知 / 多账号（范围收敛，见 spec）。
/// 不主动刷新 / 不写回 auth.json：401/403 → 提示用户跑 `codex`。
/// v0.2.8：自持一个 `UsageHistoryService`（`history-codex.json`）+ 一个 5 分钟轻量 refresh timer
/// （`startPolling()`），每次成功拉取记一个 `(session%, weekly%)` 历史点 —— 给 popover 的趋势箭头/折线图供数。
@MainActor
final class CodexProvider: UsageProvider {
    let id: ProviderID = .codex
    let runtime = ProviderRuntime()
    /// 仍 `false` —— 见 spec §2 / SC3：该 flag = 「菜单栏 primary 候选资格」（需稳定后台数据源 **且** provider-aware
    /// 的菜单栏渲染）；本版本菜单栏渲染尚未 provider-aware，Codex 暂不进 Settings primary 下拉。
    /// Codex 自己**有** refresh timer（`startPolling()`，下方），只是不靠它上菜单栏。
    let supportsBackgroundPolling = false

    /// 本 provider 的历史样本（与 Claude 的 `history.json` 同结构，不同文件 `history-codex.json`）。
    let history: UsageHistoryService

    var isConfigured: Bool { runtime.isConfigured }

    private let environment: [String: String]
    private let session: URLSession

    /// 后台采样 timer（仿 `UsageHistoryService` 的 `Timer.publish().autoconnect().sink`）。
    /// `CodexProvider` 生命周期 = app 生命周期，与 `UsageHistoryService` 一样不在 deinit 显式 cancel。
    private var pollCancellable: AnyCancellable?
    static let pollIntervalSeconds: TimeInterval = 300
    /// 单测可见：`startPolling()` 是否已起 timer。
    var isPolling: Bool { pollCancellable != nil }

    /// 重入闸门：`refreshNow()` 同一时刻只跑一份（timer / Refresh 按钮 / 切 tab 可能撞上）。
    /// `@MainActor` 序列化读写 —— 第二个调用在第一个的网络 `await` 期间进来会命中此 guard 直接 return。
    private var isRefreshing = false

    /// 后台采样 tick 时额外回调（装配处用它驱动 `codexStats.refresh()` —— 即 Codex 本机 session 扫描走同一节奏）。
    var onPollTick: (@MainActor () -> Void)? = nil

    init(environment: [String: String] = ProcessInfo.processInfo.environment,
         session: URLSession = .shared,
         history: UsageHistoryService? = nil) {
        self.environment = environment
        self.session = session
        // 默认值不能写在参数上（`UsageHistoryService` 是 @MainActor，默认参数会在 nonisolated 上下文求值）——
        // 在 @MainActor 的 init 里现造。
        let history = history ?? UsageHistoryService(filename: "history-codex.json")
        self.history = history
        // 轻量同步探测：auth.json 在不在 —— 让 tab 一打开就显示对的「未配置 / 待拉取」态（不发网络）。
        // `load` 返回 CodexCredentials?，`try?` 再包一层 → CodexCredentials??；`?? nil` 拍平后判 != nil。
        let present = ((try? CodexCredentialStore.load(environment: environment)) ?? nil) != nil
        runtime.setConfigured(present)
        history.loadHistory()
    }

    /// 起 5 分钟的轻量后台采样（幂等）；调用即先拉一次。装配处（`ClaudeUsageBarApp`）显式调用。
    func startPolling() {
        guard pollCancellable == nil else { return }
        Task { [weak self] in await self?.refreshNow() }
        onPollTick?()
        pollCancellable = Timer.publish(every: Self.pollIntervalSeconds, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refreshNow() }
                self?.onPollTick?()
            }
    }

    func refreshNow() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let creds: CodexCredentials?
        do {
            creds = try CodexCredentialStore.load(environment: environment)
        } catch {
            runtime.setConfigured(false)
            runtime.setError("未检测到有效的 Codex 凭证，请在终端运行 `codex` 登录", clearSnapshot: true)
            return
        }
        guard let creds else {
            runtime.setConfigured(false)
            runtime.clear()
            return
        }
        runtime.setConfigured(true)
        do {
            let response = try await CodexUsageClient.fetchUsage(credentials: creds, session: session)
            let snapshot = response.asProviderSnapshot()
            runtime.setSuccess(snapshot: snapshot)
            recordHistorySample(from: snapshot)
        } catch CodexUsageError.unauthorized {
            runtime.setError("Codex 凭证已过期，请在终端运行 `codex` 重新登录", clearSnapshot: true)
        } catch {
            runtime.setError("无法获取 Codex 用量（稍后重试）", clearSnapshot: false)
        }
    }

    /// 把一次成功拉取的 (session%, weekly%) 落进历史：`pct5h↔session`、`pct7d↔weekly`
    /// （沿用 `UsageDataPoint` 既有字段名 —— 它的 pct5h/pct7d 本质就是「主/次窗口已用比例」）。
    /// 缺失的窗口按 0 记（如 Free 计划只有 weekly）；两个都缺则不记。百分比 0...100 → 0...1。
    private func recordHistorySample(from snap: ProviderUsageSnapshot) {
        let p = snap.primaryWindow?.utilizationPct
        let s = snap.secondaryWindow?.utilizationPct
        guard p != nil || s != nil else { return }
        func unit(_ pct: Double?) -> Double { min(max((pct ?? 0) / 100.0, 0), 1) }   // 防服务端给出范围外值污染折线
        history.recordDataPoint(pct5h: unit(p), pct7d: unit(s))
    }
}
