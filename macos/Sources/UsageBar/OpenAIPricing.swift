import Foundation

/// OpenAI 模型的展示名 + 模型名规范化（给 Codex tab 用）。
///
/// ⚠️ **费用是 best-effort 估算**——价格数据来自打包的 LiteLLM 快照（`ModelPricingCatalog`），按各模型 list price
/// 推算的 per-Mtok 价，**不是真实账单**。ChatGPT / Codex 套餐（Free / Plus / Pro）是「套餐包额度」计费，没有按
/// token 收费的口径；Codex tab 的 USD 跟 Claude tab 一样是合成估算。
///
/// 本类型只剩 `normalize`（折叠同一模型的不同写法成统计 bucket key）和 `displayName`（UI 短名）——
/// 价格查表统一走 `ModelPricingCatalog`（含逐级回退候选链）。
enum OpenAIPricing {
    /// 去尾部日期后缀（`-YYYY-MM-DD` 带短横线形式 —— OpenAI API 模型串常用；也兼容 `-YYYYMMDD`）+ 小写。
    static func normalize(_ model: String) -> String {
        let lower = model.lowercased()
        if let r = lower.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            return String(lower[..<r.lowerBound])
        }
        if let r = lower.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(lower[..<r.lowerBound])
        }
        return lower
    }

    static func displayName(_ model: String) -> String {
        switch normalize(model) {
        case "gpt-5.5": return "GPT-5.5"
        case "gpt-5.1": return "GPT-5.1"
        case "gpt-5": return "GPT-5"
        case "gpt-5-codex": return "GPT-5 Codex"
        case "gpt-5-mini": return "GPT-5 mini"
        case "gpt-5-nano": return "GPT-5 nano"
        case "o3": return "o3"
        case "o4-mini": return "o4-mini"
        default: return model   // 未知 → 原样
        }
    }
}

struct OpenAIModelPriceTable: ModelPriceTable {
    static let shared = OpenAIModelPriceTable()
    func normalize(_ model: String) -> String { OpenAIPricing.normalize(model) }
    func lookup(_ model: String) -> ModelUnitPricing? { ModelPricingCatalog.shared.unitPricing(rawModel: model) }
    func displayName(_ model: String) -> String { OpenAIPricing.displayName(model) }
}
