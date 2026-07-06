import Foundation

protocol ClaudeStatuslineSnapshotReading: Sendable {
    func snapshot(now: Date) throws -> ProviderSnapshot
}

protocol ClaudeLocalUsageReading: Sendable {
    func snapshot(now: Date) throws -> ProviderSnapshot
}

enum ClaudeLocalEstimatePolicy: Sendable, Equatable {
    case disabled
    case enabled
    case invalidStatuslineOnly
}

struct ClaudeProviderClient: UsageProviderClient {
    let source: SnapshotSource = .claudeStatusline

    private let statuslineReader: any ClaudeStatuslineSnapshotReading
    private let localUsageReader: any ClaudeLocalUsageReading
    private let cache: ClaudeSnapshotCache?
    private let localEstimatePolicy: ClaudeLocalEstimatePolicy

    init(
        statuslineReader: any ClaudeStatuslineSnapshotReading = ClaudeStatuslineSnapshotReader(),
        localUsageReader: any ClaudeLocalUsageReading = ClaudeLocalLogUsageReader(),
        cache: ClaudeSnapshotCache? = .shared,
        localEstimatePolicy: ClaudeLocalEstimatePolicy = .disabled
    ) {
        self.statuslineReader = statuslineReader
        self.localUsageReader = localUsageReader
        self.cache = cache
        self.localEstimatePolicy = localEstimatePolicy
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [snapshot(now: now)]
    }

    private func snapshot(now: Date) -> ProviderSnapshot {
        PromptJuiceLog.usage.debug("Claude provider read started")

        do {
            let snapshot = try statuslineReader.snapshot(now: now)
            cache?.save(snapshot)
            PromptJuiceLog.usage.debug("Claude provider read finished with exact statusline")
            return snapshot
        } catch {
            let statuslineDetail = error.localizedDescription

            if error as? ClaudeUsageError == .statuslineCacheStale {
                return localEstimateOrUnavailable(
                    now: now,
                    error: error,
                    fallbackDetail: statuslineDetail,
                    logMessage: "Claude statusline cache stale"
                )
            }

            if let cachedSnapshot = cache?.snapshot(now: now, failureDetail: statuslineDetail) {
                PromptJuiceLog.usage.debug("Claude provider read finished with cached statusline")
                return cachedSnapshot
            }

            return localEstimateOrUnavailable(
                now: now,
                error: error,
                fallbackDetail: statuslineDetail,
                logMessage: "Claude statusline cache unavailable"
            )
        }
    }

    private func localEstimateOrUnavailable(
        now: Date,
        error: Error,
        fallbackDetail: String,
        logMessage: String
    ) -> ProviderSnapshot {
        guard shouldUseLocalEstimate(for: error) else {
            PromptJuiceLog.usage.notice(
                "\(logMessage, privacy: .public); local estimate skipped: \(fallbackDetail, privacy: .public)"
            )
            return unavailableSnapshot(now: now, detail: fallbackDetail)
        }

        do {
            PromptJuiceLog.usage.debug("\(logMessage, privacy: .public); local estimate started")
            let snapshot = try localUsageReader.snapshot(now: now)
            PromptJuiceLog.usage.debug("Claude provider read finished with local estimate")
            return snapshot
        } catch {
            PromptJuiceLog.usage.notice(
                "Claude local estimate failed: \(error.localizedDescription, privacy: .public); statusline: \(fallbackDetail, privacy: .public)"
            )
            return unavailableSnapshot(
                now: now,
                detail: "Claude statusline and local usage unavailable"
            )
        }
    }

    private func shouldUseLocalEstimate(for error: Error) -> Bool {
        switch localEstimatePolicy {
        case .disabled:
            return false
        case .enabled:
            return true
        case .invalidStatuslineOnly:
            return isFreshUnusableStatuslineError(error)
        }
    }

    private func isFreshUnusableStatuslineError(_ error: Error) -> Bool {
        guard let usageError = error as? ClaudeUsageError else {
            return false
        }

        switch usageError {
        case .missingFiveHourRateLimit, .invalidFiveHourRateLimit:
            return true
        case .statuslineCacheUnavailable, .statuslineCacheStale, .localLogActiveBlockUnavailable:
            return false
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

    private let claudeProviderClient: ClaudeProviderClient
    private let codexProviderClient: CodexProviderClient

    init(
        claudeProviderClient: ClaudeProviderClient = ClaudeProviderClient(localEstimatePolicy: .invalidStatuslineOnly),
        codexProviderClient: CodexProviderClient = CodexProviderClient()
    ) {
        self.claudeProviderClient = claudeProviderClient
        self.codexProviderClient = codexProviderClient
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        let claudeSnapshot = claudeProviderClient.snapshots(now: now).first
        let codexSnapshot = codexProviderClient.snapshots(now: now).first

        return [
            claudeSnapshot ?? unavailableSnapshot(identity: .claude, source: .claudeStatusline, now: now),
            codexSnapshot ?? unavailableSnapshot(identity: .codex, source: .codexAppServer, now: now)
        ]
    }

    private func unavailableSnapshot(
        identity: ProviderIdentity,
        source: SnapshotSource,
        now: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: identity,
            rateWindow: .unavailable,
            source: source,
            confidence: .unavailable,
            updatedAt: now
        )
    }
}

struct ClaudeStatuslineSnapshotReader: ClaudeStatuslineSnapshotReading {
    private static let fiveHourWindowMinutes = 5 * 60
    private static let sevenDayWindowMinutes = 7 * 24 * 60
    private static let sameWindowResetTolerance: TimeInterval = 90
    static let maximumCacheAge: TimeInterval = 2 * 60
    static let maximumCacheBytes = 64 * 1024

    let cacheURL: URL

    init(cacheURL: URL = Self.defaultCacheURL()) {
        self.cacheURL = cacheURL
    }

    func snapshot(now: Date = Date()) throws -> ProviderSnapshot {
        do {
            let sessionFiles = Self.sessionCacheFiles(
                in: cacheURL.deletingLastPathComponent()
            )

            if !sessionFiles.isEmpty {
                return try Self.snapshot(fromSessionFiles: sessionFiles, now: now)
            }

            try Self.validateCacheFile(at: cacheURL)
            let updatedAt = try Self.cacheModificationDate(at: cacheURL, now: now)
            let data = try Data(contentsOf: cacheURL)
            return try Self.legacySnapshot(from: data, now: now, updatedAt: updatedAt)
        } catch {
            if let usageError = error as? ClaudeUsageError {
                throw usageError
            }

            throw ClaudeUsageError.statuslineCacheUnavailable
        }
    }

    static func validateCacheFile(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ])

        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= maximumCacheBytes else {
            throw ClaudeUsageError.statuslineCacheUnavailable
        }
    }

    static func snapshot(from data: Data, now: Date) throws -> ProviderSnapshot {
        try legacySnapshot(from: data, now: now, updatedAt: now)
    }

    private static func legacySnapshot(
        from data: Data,
        now: Date,
        updatedAt: Date
    ) throws -> ProviderSnapshot {
        let payload = try JSONDecoder().decode(ClaudeStatuslinePayload.self, from: data)

        guard let fiveHour = payload.rateLimits?.fiveHour else {
            throw ClaudeUsageError.missingFiveHourRateLimit
        }

        guard let sessionCandidate = windowCandidate(
            from: fiveHour,
            kind: .fiveHour,
            updatedAt: updatedAt
        ),
              let resetAt = sessionCandidate.window.resetAt,
              resetAt > now else {
            throw ClaudeUsageError.invalidFiveHourRateLimit
        }

        let weeklyCandidate = windowCandidate(
            from: payload.rateLimits?.sevenDay,
            kind: .sevenDay,
            updatedAt: updatedAt
        )
        let weeklyWindow = weeklyCandidate.flatMap { candidate -> RateWindow? in
            guard let resetAt = candidate.window.resetAt,
                  resetAt > now else {
                return nil
            }
            return candidate.window
        }

        return ProviderSnapshot(
            identity: .claude,
            rateWindow: sessionCandidate.window,
            weeklyWindow: weeklyWindow,
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: updatedAt,
            weeklyUpdatedAt: weeklyWindow == nil ? nil : updatedAt
        )
    }

    private static func snapshot(
        fromSessionFiles files: [StatuslineCacheFile],
        now: Date
    ) throws -> ProviderSnapshot {
        var sessionCandidates: [WindowCandidate] = []
        var weeklyCandidates: [WindowCandidate] = []

        for file in files {
            guard let data = try? Data(contentsOf: file.url),
                  let payload = try? JSONDecoder().decode(ClaudeStatuslinePayload.self, from: data),
                  let rateLimits = payload.rateLimits else {
                continue
            }

            if let candidate = windowCandidate(
                from: rateLimits.fiveHour,
                kind: .fiveHour,
                updatedAt: file.modificationDate
            ) {
                sessionCandidates.append(candidate)
            }

            if let candidate = windowCandidate(
                from: rateLimits.sevenDay,
                kind: .sevenDay,
                updatedAt: file.modificationDate
            ) {
                weeklyCandidates.append(candidate)
            }
        }

        let mergedSession = mergedWindow(from: sessionCandidates, now: now)
        let mergedWeekly = mergedWindow(from: weeklyCandidates, now: now)
        let sawRateLimitData = !sessionCandidates.isEmpty || !weeklyCandidates.isEmpty

        guard let mergedSession else {
            guard sawRateLimitData else {
                throw ClaudeUsageError.missingFiveHourRateLimit
            }

            let newestUpdate = (sessionCandidates + weeklyCandidates)
                .map(\.updatedAt)
                .max() ?? now

            return ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                weeklyWindow: mergedWeekly?.window,
                source: .claudeStatusline,
                confidence: freshnessConfidence(updatedAt: newestUpdate, now: now),
                updatedAt: newestUpdate,
                weeklyUpdatedAt: mergedWeekly?.updatedAt ?? weeklyCandidates.map(\.updatedAt).max(),
                statusDetail: "Fresh window",
                isFreshSessionWindow: true,
                isFreshWeeklyWindow: mergedWeekly == nil && !weeklyCandidates.isEmpty
            )
        }

        return ProviderSnapshot(
            identity: .claude,
            rateWindow: mergedSession.window,
            weeklyWindow: mergedWeekly?.window,
            source: .claudeStatusline,
            confidence: mergedSession.confidence,
            updatedAt: mergedSession.updatedAt,
            weeklyUpdatedAt: mergedWeekly?.updatedAt ?? weeklyCandidates.map(\.updatedAt).max(),
            isFreshWeeklyWindow: mergedWeekly == nil && !weeklyCandidates.isEmpty
        )
    }

    private static func windowCandidate(
        from window: ClaudeStatuslineRateLimitWindow?,
        kind: ClaudeStatuslineWindowKind,
        updatedAt: Date
    ) -> WindowCandidate? {
        guard let window,
              let usedPercent = window.usedPercentage,
              usedPercent.isFinite,
              let resetsAtText = window.resetsAt,
              let resetAt = parseResetDate(resetsAtText) else {
            return nil
        }

        return WindowCandidate(
            window: .available(
                usedPercent: usedPercent,
                resetAt: resetAt,
                durationMinutes: window.durationMinutes ?? window.windowMinutes ?? kind.defaultDurationMinutes
            ),
            updatedAt: updatedAt
        )
    }

    private static func mergedWindow(
        from candidates: [WindowCandidate],
        now: Date
    ) -> MergedWindow? {
        let survivors = candidates.filter { candidate in
            guard let resetAt = candidate.window.resetAt else {
                return false
            }

            return resetAt > now
        }

        guard let maxResetAt = survivors.compactMap(\.window.resetAt).max() else {
            return nil
        }

        let sameWindow = survivors.filter { candidate in
            guard let resetAt = candidate.window.resetAt else {
                return false
            }

            return abs(resetAt.timeIntervalSince(maxResetAt)) <= sameWindowResetTolerance
        }

        guard let chosen = sameWindow.max(by: { first, second in
            let firstUsed = first.window.usedPercent ?? 0
            let secondUsed = second.window.usedPercent ?? 0
            if firstUsed != secondUsed {
                return firstUsed < secondUsed
            }

            return first.updatedAt < second.updatedAt
        }) else {
            return nil
        }

        return MergedWindow(
            window: chosen.window,
            updatedAt: chosen.updatedAt,
            confidence: freshnessConfidence(updatedAt: chosen.updatedAt, now: now)
        )
    }

    private static func freshnessConfidence(updatedAt: Date, now: Date) -> SnapshotConfidence {
        now.timeIntervalSince(updatedAt) <= maximumCacheAge ? .exact : .stale
    }

    private static func sessionCacheFiles(in directory: URL) -> [StatuslineCacheFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { url in
                url.lastPathComponent.hasPrefix("session-")
                    && url.lastPathComponent.hasSuffix(".json")
            }
            .compactMap { url -> StatuslineCacheFile? in
                guard (try? validateCacheFile(at: url)) != nil,
                      let modificationDate = try? rawCacheModificationDate(at: url) else {
                    return nil
                }

                return StatuslineCacheFile(url: url, modificationDate: modificationDate)
            }
            .sorted { first, second in
                if first.modificationDate != second.modificationDate {
                    return first.modificationDate > second.modificationDate
                }

                return first.url.path < second.url.path
            }
            .prefix(64)
            .map { $0 }
    }

    private static func cacheModificationDate(at url: URL, now: Date) throws -> Date {
        let modificationDate = try rawCacheModificationDate(at: url)

        guard now.timeIntervalSince(modificationDate) <= maximumCacheAge else {
            throw ClaudeUsageError.statuslineCacheStale
        }

        return modificationDate
    }

    private static func rawCacheModificationDate(at url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modificationDate = values.contentModificationDate else {
            throw ClaudeUsageError.statuslineCacheUnavailable
        }

        return modificationDate
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

    private let storage: ProviderWindowSnapshotCache

    init(defaults: UserDefaults = .standard) {
        storage = ProviderWindowSnapshotCache(
            defaults: defaults,
            key: Key.lastGoodClaudeSnapshot,
            identity: .claude,
            cacheSource: .claudeCache
        )
    }

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == .claude,
              snapshot.source == .claudeStatusline,
              snapshot.confidence != .unavailable else {
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
    let sevenDay: ClaudeStatuslineRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private enum ClaudeStatuslineWindowKind {
    case fiveHour
    case sevenDay

    var defaultDurationMinutes: Int {
        switch self {
        case .fiveHour:
            5 * 60
        case .sevenDay:
            7 * 24 * 60
        }
    }
}

private struct StatuslineCacheFile {
    let url: URL
    let modificationDate: Date
}

private struct WindowCandidate {
    let window: RateWindow
    let updatedAt: Date
}

private struct MergedWindow {
    let window: RateWindow
    let updatedAt: Date
    let confidence: SnapshotConfidence
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = Self.decodeDouble(from: container, forKey: .usedPercentage)
        resetsAt = Self.decodeResetText(from: container, forKey: .resetsAt)
        durationMinutes = Self.decodeInt(from: container, forKey: .durationMinutes)
        windowMinutes = Self.decodeInt(from: container, forKey: .windowMinutes)
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }

        if let text = try? container.decode(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private static func decodeInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return positiveWholeMinutes(value)
        }

        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return positiveWholeMinutes(doubleValue)
        }

        if let text = try? container.decode(String.self, forKey: key) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                return positiveWholeMinutes(value)
            }
            if let doubleValue = Double(trimmed) {
                return positiveWholeMinutes(doubleValue)
            }
        }

        return nil
    }

    private static func positiveWholeMinutes(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    private static func positiveWholeMinutes(_ value: Double) -> Int? {
        guard value.isFinite,
              value > 0,
              value.rounded(.towardZero) == value,
              value <= Double(Int.max) else {
            return nil
        }

        return Int(value)
    }

    private static func decodeResetText(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let text = try? container.decode(String.self, forKey: key) {
            return text
        }

        if let intValue = try? container.decode(Int64.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            if doubleValue.rounded(.towardZero) == doubleValue {
                return String(Int64(doubleValue))
            }

            return String(doubleValue)
        }

        return nil
    }
}

enum ClaudeUsageError: Error, LocalizedError, Equatable {
    case statuslineCacheUnavailable
    case statuslineCacheStale
    case missingFiveHourRateLimit
    case invalidFiveHourRateLimit
    case localLogActiveBlockUnavailable

    var errorDescription: String? {
        switch self {
        case .statuslineCacheUnavailable:
            return "Claude statusline cache unavailable"
        case .statuslineCacheStale:
            return "Claude statusline cache stale"
        case .missingFiveHourRateLimit:
            return "Claude five-hour rate limit unavailable"
        case .invalidFiveHourRateLimit:
            return "Claude five-hour rate limit unreadable"
        case .localLogActiveBlockUnavailable:
            return "Claude local usage active block unavailable"
        }
    }
}
