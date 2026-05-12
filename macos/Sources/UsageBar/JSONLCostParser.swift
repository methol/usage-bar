import Foundation

struct JSONLUsageEvent: Equatable {
    let messageId: String
    let requestId: String
    let model: String
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int
    let cacheReadInputTokens: Int
}

enum JSONLCostParser {
    private struct Envelope: Decodable {
        let type: String?
        let requestId: String?
        let timestamp: String?
        let message: Message?
        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
            struct Usage: Decodable {
                let inputTokens: Int?
                let outputTokens: Int?
                let cacheCreationInputTokens: Int?
                let cacheReadInputTokens: Int?
                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                }
            }
        }
    }

    enum ParseError: Error, CustomStringConvertible {
        case invalidJSON
        case missingRequiredField

        var description: String {
            switch self {
            case .invalidJSON: return "invalidJSON"
            case .missingRequiredField: return "missingRequiredField"
            }
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseLine(_ line: String) throws -> JSONLUsageEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { throw ParseError.invalidJSON }
        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ParseError.invalidJSON
        }
        guard env.type == "assistant" else { return nil }
        guard let msg = env.message,
              let msgId = msg.id,
              let model = msg.model,
              let timestampStr = env.timestamp,
              let usage = msg.usage else {
            throw ParseError.missingRequiredField
        }
        // requestId 可能缺失（早期 CLI 版本）；此时回退用 msgId 单独作为去重 key
        let requestId = env.requestId ?? msgId
        let timestamp = isoFormatter.date(from: timestampStr)
            ?? isoFormatterNoFractional.date(from: timestampStr)
        guard let ts = timestamp else { throw ParseError.missingRequiredField }
        return JSONLUsageEvent(
            messageId: msgId,
            requestId: requestId,
            model: model,
            timestamp: ts,
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheCreationInputTokens: usage.cacheCreationInputTokens ?? 0,
            cacheReadInputTokens: usage.cacheReadInputTokens ?? 0
        )
    }
}
