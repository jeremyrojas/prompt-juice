import Foundation

protocol ClaudeLocalUsageReading: Sendable {
    func snapshot(now: Date) throws -> ProviderSnapshot
}

enum ClaudeUsagePrivacyBoundary {
    static func safeDescription(for error: Error, fallback: String) -> String {
        guard let usageError = error as? ClaudeUsageError else {
            return fallback
        }
        return usageError.localizedDescription
    }
}

final class ClaudeSnapshotCache: @unchecked Sendable {
    static let shared = ClaudeSnapshotCache()

    private enum Key {
        static let lastGoodClaudeSnapshot = "lastGoodClaudeUsageSnapshot"
    }

    private let storage: ProviderWindowSnapshotCache

    init(defaults: UserDefaults = .standard) {
        storage = ProviderWindowSnapshotCache(
            defaults: defaults,
            key: Key.lastGoodClaudeSnapshot,
            identity: .claude,
            cacheSource: .claudeCache,
            allowsFreshWindowEvidence: false
        )
    }

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == .claude,
              snapshot.source == .claudeUsageCLI,
              snapshot.confidence != .unavailable,
              snapshot.rateWindow.isAvailable else {
            return
        }

        storage.save(snapshot)
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        storage.snapshot(now: now, failureDetail: failureDetail)
    }
}

struct ClaudeLocalLogUsageReader: ClaudeLocalUsageReading, @unchecked Sendable {
    static let sessionDuration: TimeInterval = 5 * 60 * 60
    private static let sessionDurationMinutes = 5 * 60

    struct Limits: Sendable, Equatable {
        var maximumFiles: Int
        var maximumTotalBytes: Int
        var maximumBytesPerFile: Int
        var recentFileAge: TimeInterval

        static let production = Limits(
            maximumFiles: 64,
            maximumTotalBytes: 8 * 1024 * 1024,
            maximumBytesPerFile: 512 * 1024,
            recentFileAge: 7 * 24 * 60 * 60
        )

        static let unboundedForTests = Limits(
            maximumFiles: .max,
            maximumTotalBytes: .max,
            maximumBytesPerFile: .max,
            recentFileAge: .infinity
        )
    }

    let projectRoots: [URL]?
    let environment: [String: String]
    let homeDirectory: URL
    let fileManager: FileManager
    let limits: Limits

    init(
        projectRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        limits: Limits = .production
    ) {
        self.projectRoots = projectRoots
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.limits = limits
    }

    func snapshot(now: Date = Date()) throws -> ProviderSnapshot {
        let entries = loadEntries(now: now)
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

    func loadEntries(now: Date = Date()) -> [ClaudeUsageLogEntry] {
        var keyedEntries: [String: ClaudeUsageLogEntry] = [:]
        var unkeyedEntries: [ClaudeUsageLogEntry] = []
        var scannedBytes = 0

        for fileURL in usageFileURLs(now: now) {
            guard !Task.isCancelled else {
                return []
            }

            guard scannedBytes < limits.maximumTotalBytes,
                  let content = readBoundedLogContent(from: fileURL) else {
                continue
            }
            scannedBytes += min(content.utf8.count, limits.maximumBytesPerFile)

            for line in content.split(whereSeparator: \.isNewline) {
                guard !Task.isCancelled else {
                    return []
                }

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

    func usageFileURLs(now: Date = Date()) -> [URL] {
        let files: [ClaudeUsageLogFile] = projectRootURLs()
            .flatMap { root -> [ClaudeUsageLogFile] in
                guard let enumerator = fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    return []
                }

                return enumerator.compactMap { item in
                    guard !Task.isCancelled else {
                        return nil
                    }

                    guard let url = item as? URL,
                          url.pathExtension.lowercased() == "jsonl",
                          let values = try? url.resourceValues(forKeys: [
                            .isRegularFileKey,
                            .fileSizeKey,
                            .contentModificationDateKey
                          ]),
                          values.isRegularFile == true,
                          Self.isRecentEnough(values.contentModificationDate, now: now, limits: limits) else {
                        return nil
                    }

                    return ClaudeUsageLogFile(
                        url: url,
                        modificationDate: values.contentModificationDate ?? .distantPast
                    )
                }
            }

        return files
            .sorted(by: Self.sortLogFiles)
            .prefix(limits.maximumFiles)
            .map { $0.url }
    }

    private static func sortLogFiles(_ first: ClaudeUsageLogFile, _ second: ClaudeUsageLogFile) -> Bool {
        if first.modificationDate != second.modificationDate {
            return first.modificationDate > second.modificationDate
        }

        return first.url.path < second.url.path
    }

    private func readBoundedLogContent(from fileURL: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }

        defer {
            try? fileHandle.close()
        }

        let fileSize = (try? fileHandle.seekToEnd()) ?? 0
        let maxBytes = UInt64(max(0, limits.maximumBytesPerFile))
        let startOffset = fileSize > maxBytes ? fileSize - maxBytes : 0

        do {
            try fileHandle.seek(toOffset: startOffset)
            let data = try fileHandle.readToEnd() ?? Data()
            guard var text = String(data: data, encoding: .utf8) else {
                return nil
            }

            if startOffset > 0, let firstNewline = text.firstIndex(where: \.isNewline) {
                text.removeSubrange(...firstNewline)
            }

            return text
        } catch {
            return nil
        }
    }

    private static func isRecentEnough(
        _ modificationDate: Date?,
        now: Date,
        limits: Limits
    ) -> Bool {
        guard limits.recentFileAge.isFinite else {
            return true
        }

        guard let modificationDate else {
            return false
        }

        return now.timeIntervalSince(modificationDate) <= limits.recentFileAge
    }

    static func parseLine(_ line: String) -> ClaudeUsageLogEntry? {
        guard line.contains(#""usage""#),
              line.contains(#""assistant""#),
              let record = try? JSONDecoder().decode(
                ClaudeUsageJSONLRecord.self,
                from: Data(line.utf8)
              ),
              record.type == "assistant",
              let timestampText = record.timestamp,
              let timestamp = Self.parseTimestamp(timestampText),
              let message = record.message,
              let usage = message.usage else {
            return nil
        }

        let tokens = ClaudeTokenUsage(
            input: max(0, usage.inputTokens ?? 0),
            cacheCreation: max(0, usage.cacheCreationInputTokens ?? 0),
            cacheRead: max(0, usage.cacheReadInputTokens ?? 0),
            output: max(0, usage.outputTokens ?? 0)
        )

        guard tokens.total > 0 else {
            return nil
        }

        return ClaudeUsageLogEntry(
            timestamp: timestamp,
            messageID: message.id,
            requestID: record.requestID,
            tokens: tokens,
            isSidechain: record.isSidechain == true
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

    private static func parseTimestamp(_ text: String) -> Date? {
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

private struct ClaudeUsageJSONLRecord: Decodable {
    let type: String?
    let timestamp: String?
    let message: Message?
    let requestID: String?
    let isSidechain: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case message
        case requestID = "requestId"
        case isSidechain
    }

    struct Message: Decodable {
        let id: String?
        let usage: TokenUsage?
    }

    struct TokenUsage: Decodable {
        let inputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?
        let outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
        }
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

private struct ClaudeUsageLogFile {
    let url: URL
    let modificationDate: Date
}

struct ClaudeTokenUsage: Equatable {
    let input: Int
    let cacheCreation: Int
    let cacheRead: Int
    let output: Int

    var total: Int {
        [input, cacheCreation, cacheRead, output].reduce(0, Self.saturatingAdd)
    }

    private static func saturatingAdd(_ partial: Int, _ value: Int) -> Int {
        if value > Int.max - partial {
            return Int.max
        }
        return partial + value
    }
}

struct ClaudeUsageBlock: Equatable {
    let start: Date
    let entries: [ClaudeUsageLogEntry]

    var resetAt: Date {
        start.addingTimeInterval(ClaudeLocalLogUsageReader.sessionDuration)
    }

    var totalTokens: Int {
        entries.reduce(0) { partial, entry in
            if entry.totalTokens > Int.max - partial {
                return Int.max
            }
            return partial + entry.totalTokens
        }
    }

    func isActive(at now: Date) -> Bool {
        guard let lastActivity = entries.last?.timestamp else {
            return false
        }

        return now < resetAt
            && now.timeIntervalSince(lastActivity) < ClaudeLocalLogUsageReader.sessionDuration
    }
}

enum ClaudeUsageError: Error, LocalizedError, Equatable, Sendable {
    case localLogActiveBlockUnavailable

    var errorDescription: String? {
        switch self {
        case .localLogActiveBlockUnavailable:
            return "Claude local usage active block unavailable"
        }
    }
}
