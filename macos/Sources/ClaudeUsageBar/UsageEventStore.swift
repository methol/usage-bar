import Foundation

actor UsageEventStore {
    private let dataDir: URL
    private let provider: UsageProvider
    private let fm = FileManager.default

    init(dataDirOverride: URL? = nil, provider: UsageProvider = .claude) {
        if let o = dataDirOverride {
            self.dataDir = o
        } else if let cfg = UsageEventStore.defaultConfigDir() {
            self.dataDir = cfg.appendingPathComponent("data", isDirectory: true)
        } else {
            self.dataDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("claude-usage-bar/data", isDirectory: true)
        }
        self.provider = provider
    }

    /// ~/.config/claude-usage-bar/
    static func defaultConfigDir() -> URL? {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-usage-bar", isDirectory: true)
    }

    private var providerDir: URL { dataDir.appendingPathComponent(provider.rawValue, isDirectory: true) }
    private func monthFileURL(_ key: String) -> URL { providerDir.appendingPathComponent("\(key).json") }

    // MARK: month key (UTC)
    private static let utcMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"; return f
    }()
    static func utcMonthKey(_ d: Date) -> String { utcMonthFormatter.string(from: d) }

    // MARK: codec
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func ensureDir(_ url: URL) {
        try? fm.createDirectory(at: url, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
    }
    private func writeAtomic0600(_ data: Data, to url: URL) {
        ensureDir(url.deletingLastPathComponent())
        do {
            try data.write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("[claude-usage-bar] store write: \(type(of: error))")
        }
    }

    private func loadMonth(_ key: String) -> MonthDetailFile? {
        guard let data = try? Data(contentsOf: monthFileURL(key)) else { return nil }
        do { return try Self.decoder.decode(MonthDetailFile.self, from: data) }
        catch { NSLog("[claude-usage-bar] store decode month: \(type(of: error))"); return nil }
    }
    private func saveMonth(_ file: MonthDetailFile, key: String) {
        guard let data = try? Self.encoder.encode(file) else { return }
        writeAtomic0600(data, to: monthFileURL(key))
    }

    // MARK: public — merge
    /// 返回 dirtyMonths（decode 失败被当空覆盖的月 key），collector 据此清相关游标。
    /// 注意：本任务实现先返回 []；Task 2 收尾时会改为返回真实 dirtyMonths（Task 2 已含 rebuild）。
    @discardableResult
    func mergeEvents(_ events: [StoredUsageEvent]) -> Set<String> {
        guard !events.isEmpty else { return [] }
        let grouped = Dictionary(grouping: events) { Self.utcMonthKey($0.ts) }
        for (monthKey, newEvents) in grouped {
            var existing = loadMonth(monthKey)?.events ?? []
            var seen = Set(existing.map { "\($0.msgId)|\($0.reqId)" })
            for e in newEvents {
                let k = "\(e.msgId)|\(e.reqId)"
                if seen.contains(k) { continue }
                seen.insert(k); existing.append(e)
            }
            existing.sort { $0.ts < $1.ts }
            saveMonth(MonthDetailFile(provider: provider.rawValue, month: monthKey,
                                      lastUpdated: Date(), events: existing), key: monthKey)
        }
        return []
    }

    // MARK: public — query
    func queryEvents(from: Date, to: Date) -> [StoredUsageEvent] {
        guard fm.fileExists(atPath: providerDir.path) else { return [] }
        let fromKey = Self.utcMonthKey(from), toKey = Self.utcMonthKey(to)
        guard let files = try? fm.contentsOfDirectory(at: providerDir, includingPropertiesForKeys: nil) else { return [] }
        var result: [StoredUsageEvent] = []
        for f in files where f.pathExtension == "json" {
            let name = f.deletingPathExtension().lastPathComponent  // "YYYY-MM" or "agg-day" ...
            // 用 !hasPrefix("agg") 明确排除 agg-* 文件（"agg-day" 也是 7 字符，光靠 count 不够稳）
            guard !name.hasPrefix("agg"), name.count == 7, name <= toKey, name >= fromKey else { continue }
            if let mf = loadMonth(name) {
                result.append(contentsOf: mf.events.filter { $0.ts >= from && $0.ts < to })
            }
        }
        return result.sorted { $0.ts < $1.ts }
    }

    // MARK: 给 Task 2 用的内部访问器（先建好）
    func allMonthKeys() -> [String] {
        guard let files = try? fm.contentsOfDirectory(at: providerDir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.count == 7 && $0.contains("-") && !$0.hasPrefix("agg") }
            .sorted()
    }
    func eventsForMonth(_ key: String) -> [StoredUsageEvent] { loadMonth(key)?.events ?? [] }
}
