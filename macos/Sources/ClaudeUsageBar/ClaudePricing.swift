import Foundation

struct ClaudeModelPricing: Equatable {
    let inputUSDPerMTok: Double
    let outputUSDPerMTok: Double
    let cacheReadUSDPerMTok: Double
    let cacheWriteUSDPerMTok: Double
}

// LiteLLM-compatible 离线快照。来源参考：
// https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json
// claude-opus-4 family $15/$75 per MTok 与 Anthropic 官方定价对齐；
// claude-opus-4-6/4-7 子版本沿用 family 价（待 Anthropic 公布差异化定价时升级 spec）。
enum ClaudePricing {
    static let snapshotDate = "2026-05-11"

    private static let table: [String: ClaudeModelPricing] = [
        "claude-opus-4-7":     .init(inputUSDPerMTok: 15.0, outputUSDPerMTok: 75.0, cacheReadUSDPerMTok: 1.50, cacheWriteUSDPerMTok: 18.75),
        "claude-opus-4-6":     .init(inputUSDPerMTok: 15.0, outputUSDPerMTok: 75.0, cacheReadUSDPerMTok: 1.50, cacheWriteUSDPerMTok: 18.75),
        "claude-opus-4":       .init(inputUSDPerMTok: 15.0, outputUSDPerMTok: 75.0, cacheReadUSDPerMTok: 1.50, cacheWriteUSDPerMTok: 18.75),
        "claude-sonnet-4-6":   .init(inputUSDPerMTok: 3.0,  outputUSDPerMTok: 15.0, cacheReadUSDPerMTok: 0.30, cacheWriteUSDPerMTok: 3.75),
        "claude-sonnet-4-5":   .init(inputUSDPerMTok: 3.0,  outputUSDPerMTok: 15.0, cacheReadUSDPerMTok: 0.30, cacheWriteUSDPerMTok: 3.75),
        "claude-sonnet-4":     .init(inputUSDPerMTok: 3.0,  outputUSDPerMTok: 15.0, cacheReadUSDPerMTok: 0.30, cacheWriteUSDPerMTok: 3.75),
        "claude-haiku-4-5":    .init(inputUSDPerMTok: 1.0,  outputUSDPerMTok: 5.0,  cacheReadUSDPerMTok: 0.10, cacheWriteUSDPerMTok: 1.25),
        "claude-haiku-4":      .init(inputUSDPerMTok: 1.0,  outputUSDPerMTok: 5.0,  cacheReadUSDPerMTok: 0.10, cacheWriteUSDPerMTok: 1.25),
        "claude-3-5-sonnet":   .init(inputUSDPerMTok: 3.0,  outputUSDPerMTok: 15.0, cacheReadUSDPerMTok: 0.30, cacheWriteUSDPerMTok: 3.75),
        "claude-3-5-haiku":    .init(inputUSDPerMTok: 0.80, outputUSDPerMTok: 4.0,  cacheReadUSDPerMTok: 0.08, cacheWriteUSDPerMTok: 1.0),
        "claude-3-opus":       .init(inputUSDPerMTok: 15.0, outputUSDPerMTok: 75.0, cacheReadUSDPerMTok: 1.50, cacheWriteUSDPerMTok: 18.75)
    ]

    static func normalize(_ model: String) -> String {
        let lower = model.lowercased()
        if let range = lower.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(lower[..<range.lowerBound])
        }
        return lower
    }

    static func lookup(model: String) -> ClaudeModelPricing? {
        return table[normalize(model)]
    }

    static func cost(for pricing: ClaudeModelPricing?, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        guard let p = pricing else { return 0 }
        return (Double(input) * p.inputUSDPerMTok
              + Double(output) * p.outputUSDPerMTok
              + Double(cacheRead) * p.cacheReadUSDPerMTok
              + Double(cacheWrite) * p.cacheWriteUSDPerMTok) / 1_000_000.0
    }
}
