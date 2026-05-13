import Foundation

/// Claude 模型的展示名 + 模型名规范化。
///
/// 价格数据统一走 `ModelPricingCatalog`（打包的 LiteLLM 快照 + 逐级回退候选链）——本类型只剩
/// `normalize`（折叠同一模型的不同写法成统计 bucket key）和 `displayName`（给 UI 用的简短别名）。
/// 费用是 list-price 估算，不是真实账单（Claude 套餐按包额度计费）。
enum ClaudePricing {
    /// 去尾部 8 位日期后缀（`-YYYYMMDD`）+ 小写。
    static func normalize(_ model: String) -> String {
        let lower = model.lowercased()
        if let range = lower.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return String(lower[..<range.lowerBound])
        }
        return lower
    }

    /// `claude-opus-4-7` → `Opus 4.7`、`claude-3-5-sonnet` → `Sonnet 3.5`、`claude-3-opus` → `Opus 3`。
    /// 识别不出 family（如 `<synthetic>`）→ 原样返回。
    static func displayName(_ model: String) -> String {
        let m = model.lowercased()
        let family: String?
        if m.contains("opus") { family = "Opus" }
        else if m.contains("sonnet") { family = "Sonnet" }
        else if m.contains("haiku") { family = "Haiku" }
        else { family = nil }
        guard let fam = family else { return model }
        let nums = m.split(separator: "-").compactMap { Int($0) }.filter { $0 < 1000 }
        switch nums.count {
        case 0:  return fam
        case 1:  return "\(fam) \(nums[0])"
        default: return "\(fam) \(nums[0]).\(nums[1])"
        }
    }
}

/// `ModelPriceTable` 适配器 —— `normalize`/`displayName` 走 `ClaudePricing`，价格查表走 `ModelPricingCatalog`。
struct ClaudeModelPriceTable: ModelPriceTable {
    static let shared = ClaudeModelPriceTable()
    func normalize(_ model: String) -> String { ClaudePricing.normalize(model) }
    func displayName(_ model: String) -> String { ClaudePricing.displayName(model) }
    func lookup(_ model: String) -> ModelUnitPricing? { ModelPricingCatalog.shared.unitPricing(rawModel: model) }
}
