import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageBucket?
    let sevenDay: UsageBucket?
    let sevenDayOpus: UsageBucket?
    let sevenDaySonnet: UsageBucket?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }

    func reconciled(with previous: UsageResponse?, now: Date = Date()) -> UsageResponse {
        UsageResponse(
            fiveHour: fiveHour?.reconciled(
                with: previous?.fiveHour,
                resetInterval: 5 * 60 * 60,
                now: now
            ),
            sevenDay: sevenDay?.reconciled(
                with: previous?.sevenDay,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            sevenDayOpus: sevenDayOpus?.reconciled(
                with: previous?.sevenDayOpus,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            sevenDaySonnet: sevenDaySonnet?.reconciled(
                with: previous?.sevenDaySonnet,
                resetInterval: 7 * 24 * 60 * 60,
                now: now
            ),
            extraUsage: extraUsage
        )
    }
}

struct UsageBucket: Codable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetsAtDate: Date? {
        Self.parseResetDate(from: resetsAt)
    }

    func reconciled(with previous: UsageBucket?, resetInterval: TimeInterval, now: Date) -> UsageBucket {
        guard resetsAtDate == nil else { return self }
        guard let previousDate = previous?.resetsAtDate else { return self }

        let resolvedDate = Self.nextResetDate(
            from: previousDate,
            resetInterval: resetInterval,
            now: now
        )

        return UsageBucket(
            utilization: utilization,
            resetsAt: Self.resetString(from: resolvedDate)
        )
    }

    private static func parseResetDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let isoFormatters: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]

        for options in isoFormatters {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }

        let fallbackPatterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for pattern in fallbackPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func nextResetDate(from previous: Date, resetInterval: TimeInterval, now: Date) -> Date {
        guard resetInterval > 0 else { return previous }
        guard previous <= now else { return previous }

        let elapsed = now.timeIntervalSince(previous)
        let stepCount = floor(elapsed / resetInterval) + 1
        return previous.addingTimeInterval(stepCount * resetInterval)
    }

    private static func resetString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let utilization: Double?
    let usedCredits: Double?
    let monthlyLimit: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case utilization
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
    }

    /// API returns credits in minor units (cents); convert to dollars.
    var usedCreditsAmount: Double? {
        usedCredits.map { $0 / 100.0 }
    }

    var monthlyLimitAmount: Double? {
        monthlyLimit.map { $0 / 100.0 }
    }

    static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = true
        return f
    }()

    static func formatUSD(_ amount: Double) -> String {
        let formatted = currencyFormatter.string(from: NSNumber(value: amount))
            ?? String(format: "%.2f", amount)
        return "$\(formatted)"
    }

    /// Compact dollar format: $14.69, $13.12K, $1.05M, $1.23B, $1.23T
    static func formatUSDCompact(_ amount: Double) -> String {
        if amount == 0 { return "$0.00" }
        let abs = Swift.abs(amount)
        let sign = amount < 0 ? "-" : ""
        switch abs {
        case 1e12...:
            return "\(sign)$\(String(format: "%.2f", abs / 1e12))T"
        case 1e9...:
            return "\(sign)$\(String(format: "%.2f", abs / 1e9))B"
        case 1e6...:
            return "\(sign)$\(String(format: "%.2f", abs / 1e6))M"
        case 1e3...:
            return "\(sign)$\(String(format: "%.2f", abs / 1e3))K"
        default:
            return "\(sign)$\(String(format: "%.2f", abs))"
        }
    }

    /// Compact token count: 847, 33.00K, 7.12M, 1.23B, 1.23T
    static func formatTokens(_ count: Int) -> String {
        let abs = count < 0 ? -count : count
        let sign = count < 0 ? "-" : ""
        let d = Double(abs)
        switch d {
        case 1e12...:
            return "\(sign)\(String(format: "%.2f", d / 1e12))T"
        case 1e9...:
            return "\(sign)\(String(format: "%.2f", d / 1e9))B"
        case 1e6...:
            return "\(sign)\(String(format: "%.2f", d / 1e6))M"
        case 1e3...:
            return "\(sign)\(String(format: "%.2f", d / 1e3))K"
        default:
            return "\(sign)\(abs)"
        }
    }
}
