import Foundation

/// 多数据源抽象骨架。当前仅 ClaudeCLICredentialsStrategy 一个实现；
/// v0.1.2 LocalCostScanStrategy / v0.1.3 MultiAccountStrategy /
/// v0.2.3 CookieFallbackStrategy / v0.2.4 CLIPTYStrategy 将依次加入。
protocol ClaudeUsageStrategy {
    /// 从该 strategy 提供凭证。
    /// - 返回 nil：该 strategy 无凭证可提供（静默降级，调用方走原路径）
    /// - 抛出 error：明确异常需上层 log（**SC7 安全约束**：error 不得带 raw credential 值）
    func loadCredentials() async throws -> StoredCredentials?
}
