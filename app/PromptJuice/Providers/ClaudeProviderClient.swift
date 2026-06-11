import Foundation

protocol ClaudeStatuslineSnapshotReading {
    func snapshot(now: Date) throws -> ProviderSnapshot
}

protocol ClaudeLocalUsageReading {
    func snapshot(now: Date) throws -> ProviderSnapshot
}

struct ClaudeProviderClient: UsageProviderClient {
    let source: SnapshotSource = .claudeStatusline

    private let statuslineReader: any ClaudeStatuslineSnapshotReading
    private let localUsageReader: any ClaudeLocalUsageReading
    private let cache: ClaudeSnapshotCache?

    init(
        statuslineReader: any ClaudeStatuslineSnapshotReading = ClaudeStatuslineSnapshotReader(),
        localUsageReader: any ClaudeLocalUsageReading = ClaudeLocalLogUsageReader(),
        cache: ClaudeSnapshotCache? = .shared
    ) {
        self.statuslineReader = statuslineReader
        self.localUsageReader = localUsageReader
        self.cache = cache
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [snapshot(now: now)]
    }

    private func snapshot(now: Date) -> ProviderSnapshot {
        do {
            let snapshot = try statuslineReader.snapshot(now: now)
            cache?.save(snapshot)
            return snapshot
        } catch {
            let statuslineDetail = error.localizedDescription

            if let cachedSnapshot = cache?.snapshot(now: now, failureDetail: statuslineDetail) {
                return cachedSnapshot
            }

            do {
                return try localUsageReader.snapshot(now: now)
            } catch {
                return unavailableSnapshot(
                    now: now,
                    detail: "Claude statusline and local usage unavailable"
                )
            }
        }
    }

    private func unavailableSnapshot(now: Date, detail: String) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: source,
            confidence: .unavailable,
            updatedAt: now,
            statusDetail: detail
        )
    }
}

struct ClaudeLiveUsageProviderClient: UsageProviderClient {
    let source: SnapshotSource = .claudeStatusline

    private let scenario: DemoScenario
    private let claudeProviderClient: ClaudeProviderClient
    private let codexProviderClient: CodexProviderClient

    init(
        scenario: DemoScenario,
        claudeProviderClient: ClaudeProviderClient = ClaudeProviderClient(),
        codexProviderClient: CodexProviderClient = CodexProviderClient()
    ) {
        self.scenario = scenario
        self.claudeProviderClient = claudeProviderClient
        self.codexProviderClient = codexProviderClient
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        let claudeSnapshot = claudeProviderClient.snapshots(now: now).first
        let codexSnapshot = codexProviderClient.snapshots(now: now).first

        return DemoProviderClient(scenario: scenario)
            .snapshots(now: now)
            .map { snapshot in
                if snapshot.identity == .claude {
                    return claudeSnapshot ?? snapshot
                }

                if snapshot.identity == .codex {
                    return codexSnapshot ?? snapshot
                }

                return snapshot
            }
    }
}

struct ClaudeStatuslineSnapshotReader: ClaudeStatuslineSnapshotReading {
    private static let fiveHourWindowMinutes = 5 * 60

    let cacheURL: URL

    init(cacheURL: URL = Self.defaultCacheURL()) {
        self.cacheURL = cacheURL
    }

    func snapshot(now: Date = Date()) throws -> ProviderSnapshot {
        let data: Data

        do {
            data = try Data(contentsOf: cacheURL)
        } catch {
            throw ClaudeUsageError.statuslineCacheUnavailable
        }

        return try Self.snapshot(from: data, now: now)
    }

    static func snapshot(from data: Data, now: Date) throws -> ProviderSnapshot {
        let payload = try JSONDecoder().decode(ClaudeStatuslinePayload.self, from: data)

        guard let fiveHour = payload.rateLimits?.fiveHour else {
            throw ClaudeUsageError.missingFiveHourRateLimit
        }

        guard let usedPercent = fiveHour.usedPercentage,
              usedPercent.isFinite,
              let resetsAtText = fiveHour.resetsAt,
              let resetAt = Self.parseResetDate(resetsAtText),
              resetAt > now else {
            throw ClaudeUsageError.invalidFiveHourRateLimit
        }

        return ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: resetAt,
                durationMinutes: fiveHour.durationMinutes ?? fiveHour.windowMinutes ?? Self.fiveHourWindowMinutes
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now
        )
    }

    static func defaultCacheURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/PromptJuice/ClaudeStatus", isDirectory: true)
            .appendingPathComponent("latest.json")
    }

    static func parseResetDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }

        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        if let date = plainFormatter.date(from: trimmed) {
            return date
        }

        if let seconds = TimeInterval(trimmed), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }

        return nil
    }
}

final class ClaudeSnapshotCache: @unchecked Sendable {
    static let shared = ClaudeSnapshotCache()

    private enum Key {
        static let lastGoodClaudeSnapshot = "lastGoodClaudeStatuslineSnapshot"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == .claude,
              snapshot.source == .claudeStatusline,
              snapshot.confidence == .exact,
              let usedPercent = snapshot.rateWindow.usedPercent,
              let resetAt = snapshot.rateWindow.resetAt,
              let durationMinutes = snapshot.rateWindow.durationMinutes else {
            return
        }

        let cached = CachedClaudeSnapshot(
            usedPercent: usedPercent,
            resetAt: resetAt,
            durationMinutes: durationMinutes,
            updatedAt: snapshot.updatedAt
        )

        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: Key.lastGoodClaudeSnapshot)
        }
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        guard let data = defaults.data(forKey: Key.lastGoodClaudeSnapshot),
              let cached = try? JSONDecoder().decode(CachedClaudeSnapshot.self, from: data),
              cached.resetAt > now else {
            return nil
        }

        return ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: cached.usedPercent,
                resetAt: cached.resetAt,
                durationMinutes: cached.durationMinutes
            ),
            source: .claudeCache,
            confidence: .stale,
            updatedAt: cached.updatedAt,
            statusDetail: failureDetail
        )
    }
}

struct ClaudeLocalLogUsageReader: ClaudeLocalUsageReading {
    static let sessionDuration: TimeInterval = 5 * 60 * 60
    private static let sessionDurationMinutes = 5 * 60

    let projectRoots: [URL]?
    let environment: [String: String]
    let homeDirectory: URL
    let fileManager: FileManager

    init(
        projectRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.projectRoots = projectRoots
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func snapshot(now: Date = Date()) throws -> ProviderSnapshot {
        let entries = loadEntries()
        let blocks = Self.sessionBlocks(from: entries)

        guard let activeBlock = blocks.last(where: { $0.isActive(at: now) }) else {
            throw ClaudeUsageError.localLogActiveBlockUnavailable
        }

        let estimatedLimit = max(blocks.map(\.totalTokens).max() ?? 0, 1)
        let usedPercent = min(100, max(0, (Double(activeBlock.totalTokens) / Double(estimatedLimit)) * 100))

        return ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: activeBlock.resetAt,
                durationMinutes: Self.sessionDurationMinutes
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now,
            statusDetail: "Estimated from local Claude logs"
        )
    }

    func loadEntries() -> [ClaudeUsageLogEntry] {
        var keyedEntries: [String: ClaudeUsageLogEntry] = [:]
        var unkeyedEntries: [ClaudeUsageLogEntry] = []

        for fileURL in usageFileURLs() {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for line in content.split(whereSeparator: \.isNewline) {
                guard let entry = Self.parseLine(String(line)) else {
                    continue
                }

                if let key = entry.dedupeKey {
                    let current = keyedEntries[key]
                    if current == nil || entry.totalTokens >= current!.totalTokens {
                        keyedEntries[key] = entry
                    }
                } else {
                    unkeyedEntries.append(entry)
                }
            }
        }

        return keyedEntries.values.sorted(by: { $0.timestamp < $1.timestamp })
            + unkeyedEntries.sorted(by: { $0.timestamp < $1.timestamp })
    }

    func projectRootURLs() -> [URL] {
        if let projectRoots {
            return projectRoots
        }

        if let envValue = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envValue.isEmpty {
            return envValue
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { rawPath in
                    let expanded = Self.expandHome(in: rawPath, homeDirectory: homeDirectory)
                    return expanded.lastPathComponent == "projects"
                        ? expanded
                        : expanded.appendingPathComponent("projects", isDirectory: true)
                }
        }

        return [
            homeDirectory.appendingPathComponent(".config/claude/projects", isDirectory: true),
            homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        ]
    }

    func usageFileURLs() -> [URL] {
        projectRootURLs()
            .flatMap { root -> [URL] in
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    return []
                }

                return enumerator.compactMap { item in
                    guard let url = item as? URL,
                          url.pathExtension.lowercased() == "jsonl",
                          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                        return nil
                    }

                    return url
                }
            }
            .sorted { $0.path < $1.path }
    }

    static func parseLine(_ line: String) -> ClaudeUsageLogEntry? {
        guard line.contains(#""usage""#),
              line.contains(#""assistant""#),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "assistant",
              let timestampText = object["timestamp"] as? String,
              let timestamp = ClaudeStatuslineSnapshotReader.parseResetDate(timestampText),
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }

        let tokens = ClaudeTokenUsage(
            input: Self.intValue(usage["input_tokens"]),
            cacheCreation: Self.intValue(usage["cache_creation_input_tokens"]),
            cacheRead: Self.intValue(usage["cache_read_input_tokens"]),
            output: Self.intValue(usage["output_tokens"])
        )

        guard tokens.total > 0 else {
            return nil
        }

        return ClaudeUsageLogEntry(
            timestamp: timestamp,
            messageID: message["id"] as? String,
            requestID: object["requestId"] as? String,
            tokens: tokens,
            isSidechain: (object["isSidechain"] as? Bool) == true
        )
    }

    static func sessionBlocks(from entries: [ClaudeUsageLogEntry]) -> [ClaudeUsageBlock] {
        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
        var blocks: [ClaudeUsageBlock] = []
        var currentEntries: [ClaudeUsageLogEntry] = []
        var currentStart: Date?

        for entry in sortedEntries {
            if let start = currentStart,
               let last = currentEntries.last?.timestamp,
               entry.timestamp.timeIntervalSince(start) > Self.sessionDuration
                || entry.timestamp.timeIntervalSince(last) > Self.sessionDuration {
                blocks.append(ClaudeUsageBlock(start: start, entries: currentEntries))
                currentStart = Self.floorToHour(entry.timestamp)
                currentEntries = []
            }

            if currentStart == nil {
                currentStart = Self.floorToHour(entry.timestamp)
            }

            currentEntries.append(entry)
        }

        if let currentStart, !currentEntries.isEmpty {
            blocks.append(ClaudeUsageBlock(start: currentStart, entries: currentEntries))
        }

        return blocks
    }

    private static func floorToHour(_ date: Date) -> Date {
        let seconds = floor(date.timeIntervalSince1970 / 3600) * 3600
        return Date(timeIntervalSince1970: seconds)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            return max(0, number.intValue)
        }

        return 0
    }

    private static func expandHome(in path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }

        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }

        return URL(fileURLWithPath: path)
    }
}

struct ClaudeUsageLogEntry: Equatable {
    let timestamp: Date
    let messageID: String?
    let requestID: String?
    let tokens: ClaudeTokenUsage
    let isSidechain: Bool

    var totalTokens: Int {
        tokens.total
    }

    var dedupeKey: String? {
        guard let messageID,
              let requestID else {
            return nil
        }

        return "\(messageID):\(requestID)"
    }
}

struct ClaudeTokenUsage: Equatable {
    let input: Int
    let cacheCreation: Int
    let cacheRead: Int
    let output: Int

    var total: Int {
        input + cacheCreation + cacheRead + output
    }
}

struct ClaudeUsageBlock: Equatable {
    let start: Date
    let entries: [ClaudeUsageLogEntry]

    var resetAt: Date {
        start.addingTimeInterval(ClaudeLocalLogUsageReader.sessionDuration)
    }

    var totalTokens: Int {
        entries.reduce(0) { $0 + $1.totalTokens }
    }

    func isActive(at now: Date) -> Bool {
        guard let lastActivity = entries.last?.timestamp else {
            return false
        }

        return now < resetAt
            && now.timeIntervalSince(lastActivity) < ClaudeLocalLogUsageReader.sessionDuration
    }
}

private struct ClaudeStatuslinePayload: Decodable {
    let rateLimits: ClaudeStatuslineRateLimits?

    private enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct ClaudeStatuslineRateLimits: Decodable {
    let fiveHour: ClaudeStatuslineRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
    }
}

private struct ClaudeStatuslineRateLimitWindow: Decodable {
    let usedPercentage: Double?
    let resetsAt: String?
    let durationMinutes: Int?
    let windowMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
        case durationMinutes = "duration_minutes"
        case windowMinutes = "window_minutes"
    }
}

private struct CachedClaudeSnapshot: Codable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date
}

enum ClaudeUsageError: Error, LocalizedError, Equatable {
    case statuslineCacheUnavailable
    case missingFiveHourRateLimit
    case invalidFiveHourRateLimit
    case localLogActiveBlockUnavailable

    var errorDescription: String? {
        switch self {
        case .statuslineCacheUnavailable:
            return "Claude statusline cache unavailable"
        case .missingFiveHourRateLimit:
            return "Claude five-hour rate limit unavailable"
        case .invalidFiveHourRateLimit:
            return "Claude five-hour rate limit unreadable"
        case .localLogActiveBlockUnavailable:
            return "Claude local usage active block unavailable"
        }
    }
}
