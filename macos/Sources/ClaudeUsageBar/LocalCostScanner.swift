import Foundation

actor LocalCostScanner {
    static let shared = LocalCostScanner()

    private let fileManager = FileManager.default
    private let cacheDir: URL
    private let cacheFile: URL
    private let cacheTTL: TimeInterval = 60
    private let windowDays: Int = 30
    private let scanRootsOverride: [URL]?

    init(cacheDirOverride: URL? = nil, scanRootsOverride: [URL]? = nil) {
        let base: URL
        if let override = cacheDirOverride {
            base = override
        } else if let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            base = cachesURL.appendingPathComponent("claude-usage-bar/cost-usage", isDirectory: true)
        } else {
            // 沙盒/异常环境兜底
            base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("claude-usage-bar/cost-usage", isDirectory: true)
        }
        self.cacheDir = base
        self.cacheFile = base.appendingPathComponent("claude-v1.json")
        self.scanRootsOverride = scanRootsOverride
    }

    func scan(now: Date = Date()) async -> CostSummary {
        if let cached = loadCache(), now.timeIntervalSince(cached.generatedAt) < cacheTTL {
            return cached
        }
        let summary = performScan(now: now)
        saveCache(summary)
        return summary
    }

    func scanForceRefresh(now: Date = Date()) async -> CostSummary {
        let summary = performScan(now: now)
        saveCache(summary)
        return summary
    }

    private func performScan(now: Date) -> CostSummary {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86400)
        let roots = scanRootsOverride ?? Self.scanRoots()
        var seen: Set<String> = []
        var perModelAgg: [String: ModelAgg] = [:]
        var parseErrors = 0
        var fileCount = 0

        for root in roots {
            guard let projectDirs = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for projectDir in projectDirs {
                let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let candidates: [URL]
                if isDir {
                    candidates = (try? fileManager.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil)) ?? []
                } else {
                    candidates = [projectDir]
                }
                for file in candidates where file.pathExtension == "jsonl" {
                    fileCount += 1
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
                    for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
                        do {
                            guard let event = try JSONLCostParser.parseLine(String(line)) else { continue }
                            guard event.timestamp >= cutoff else { continue }
                            // G5 R2: msgId 是 Anthropic 生成的全局唯一 UUID（msg_01...），
                            // 跨 session 不碰撞；requestId 进一步区分同一 msg 的 retry。
                            let key = "\(event.messageId)|\(event.requestId)"
                            if seen.contains(key) { continue }
                            seen.insert(key)
                            let normalized = ClaudePricing.normalize(event.model)
                            if perModelAgg[normalized] == nil {
                                perModelAgg[normalized] = ModelAgg(model: event.model, normalized: normalized)
                            }
                            perModelAgg[normalized]?.add(event)
                        } catch {
                            parseErrors += 1
                            // SC7 (G2 #1): 不 log 文件名（含 session UUID）；只 log error type
                            NSLog("[claude-usage-bar] cost scan parse: \(type(of: error))")
                        }
                    }
                }
            }
        }

        var unknownCount = 0
        var total = 0.0
        var perModel: [ModelCost] = []
        for (_, agg) in perModelAgg {
            let pricing = ClaudePricing.lookup(model: agg.normalized)
            if pricing == nil { unknownCount += agg.calls }
            let usd = ClaudePricing.cost(
                for: pricing,
                input: agg.inputTokens,
                output: agg.outputTokens,
                cacheRead: agg.cacheReadTokens,
                cacheWrite: agg.cacheCreationTokens
            )
            total += usd
            perModel.append(ModelCost(
                model: agg.firstSeenModel,
                normalizedModel: agg.normalized,
                calls: agg.calls,
                inputTokens: agg.inputTokens,
                outputTokens: agg.outputTokens,
                cacheReadTokens: agg.cacheReadTokens,
                cacheCreationTokens: agg.cacheCreationTokens,
                usd: usd,
                isUnknownPricing: pricing == nil
            ))
        }
        perModel.sort { $0.usd > $1.usd }

        return CostSummary(
            generatedAt: now,
            windowDays: windowDays,
            totalUSD: total,
            perModel: perModel,
            unknownModelCount: unknownCount,
            parseErrorCount: parseErrors,
            scannedFileCount: fileCount
        )
    }

    private struct ModelAgg {
        let firstSeenModel: String
        let normalized: String
        var calls: Int = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheCreationTokens: Int = 0
        init(model: String, normalized: String) {
            self.firstSeenModel = model
            self.normalized = normalized
        }
        mutating func add(_ e: JSONLUsageEvent) {
            calls += 1
            inputTokens += e.inputTokens
            outputTokens += e.outputTokens
            cacheReadTokens += e.cacheReadInputTokens
            cacheCreationTokens += e.cacheCreationInputTokens
        }
    }

    private func loadCache() -> CostSummary? {
        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return try? Self.decoder.decode(CostSummary.self, from: data)
    }

    private func saveCache(_ summary: CostSummary) {
        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(summary)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            NSLog("[claude-usage-bar] cost cache write: \(type(of: error))")
        }
    }

    // G2 D: 用类型内部 static 而非全局 extension 避免命名污染
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 测试入口：固定 env override（避免依赖进程 env）
    static func scanRoots(env: [String: String], home: URL, fileExists: (String) -> Bool) -> [URL] {
        var roots: [URL] = []
        let envValue = env["CLAUDE_CONFIG_DIR"] ?? ""
        if !envValue.isEmpty {
            for path in envValue.split(separator: ":") {
                let url = URL(fileURLWithPath: String(path)).appendingPathComponent("projects", isDirectory: true)
                if fileExists(url.path) { roots.append(url) }
            }
        }
        let xdg = home.appendingPathComponent(".config/claude/projects", isDirectory: true)
        if fileExists(xdg.path) { roots.append(xdg) }
        let legacy = home.appendingPathComponent(".claude/projects", isDirectory: true)
        if fileExists(legacy.path) { roots.append(legacy) }
        return roots
    }

    static func scanRoots() -> [URL] {
        var roots: [URL] = []
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? ""
        if !env.isEmpty {
            for path in env.split(separator: ":") {
                let url = URL(fileURLWithPath: String(path)).appendingPathComponent("projects", isDirectory: true)
                if fm.fileExists(atPath: url.path) { roots.append(url) }
            }
        }
        let home = fm.homeDirectoryForCurrentUser
        let xdg = home.appendingPathComponent(".config/claude/projects", isDirectory: true)
        if fm.fileExists(atPath: xdg.path) { roots.append(xdg) }
        let legacy = home.appendingPathComponent(".claude/projects", isDirectory: true)
        if fm.fileExists(atPath: legacy.path) { roots.append(legacy) }
        return roots
    }
}

