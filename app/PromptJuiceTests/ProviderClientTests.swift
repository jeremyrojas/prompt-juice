import XCTest
@testable import PromptJuice

final class ProviderClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFixtureProviderReturnsNormalizedSnapshots() {
        let snapshots = FixtureUsageProviderClient(scenario: .underusedCodex)
            .snapshots(now: now)

        XCTAssertEqual(snapshots.map(\.identity), [.claude, .codex])
        XCTAssertEqual(snapshots.map(\.source), [.fixture, .fixture])
        XCTAssertEqual(snapshots.map(\.confidence), [.exact, .exact])
        XCTAssertEqual(snapshots[1].remainingPercent, 69)
        XCTAssertEqual(snapshots[1].rateWindow.minutesUntilReset(now: now), 52)
    }

    func testCodexStubProviderReturnsUnavailableSnapshot() {
        let snapshots = CodexStubProviderClient().snapshots(now: now)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].identity, .codex)
        XCTAssertEqual(snapshots[0].source, .codexStub)
        XCTAssertEqual(snapshots[0].confidence, .unavailable)
        XCTAssertEqual(snapshots[0].rateWindow, .unavailable)
        XCTAssertEqual(snapshots[0].updatedAt, now)
    }

    func testCodexProviderReturnsExactSnapshotFromRateLimits() throws {
        let readResult = try decodeRateLimits(multiBucketFixture)
        let provider = CodexProviderClient(
            rateLimitReader: StubRateLimitReader(result: .success(readResult)),
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.identity, .codex)
        XCTAssertEqual(snapshot.source, .codexAppServer)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 6)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
        XCTAssertEqual(snapshot.rateWindow.resetAt, Date(timeIntervalSince1970: 1_800_005_173))
    }

    func testCodexProviderReturnsUnavailableWhenAppServerFails() {
        let provider = CodexProviderClient(
            rateLimitReader: StubRateLimitReader(result: .failure(CodexAppServerClientError.executableUnavailable)),
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.identity, .codex)
        XCTAssertEqual(snapshot.source, .codexAppServer)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.rateWindow, .unavailable)
        XCTAssertEqual(snapshot.statusDetail, "Codex executable unavailable")
    }

    func testCodexProviderUsesStaleCacheAfterLiveFailure() throws {
        let suiteName = "PromptJuiceCodexCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = CodexSnapshotCache(defaults: defaults)
        let exactSnapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 6,
                resetAt: now.addingTimeInterval(300),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now
        )
        cache.save(exactSnapshot)

        let provider = CodexProviderClient(
            rateLimitReader: StubRateLimitReader(result: .failure(CodexAppServerClientError.timeout(""))),
            cache: cache
        )

        let snapshot = provider.snapshots(now: now.addingTimeInterval(60))[0]

        XCTAssertEqual(snapshot.source, .codexCache)
        XCTAssertEqual(snapshot.confidence, .stale)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 6)
        XCTAssertEqual(snapshot.statusDetail, "Codex app-server timed out")
    }

    func testClaudeStatuslineReaderReturnsExactSnapshot() throws {
        let snapshot = try ClaudeStatuslineSnapshotReader.snapshot(
            from: Data(claudeStatuslineFixture.utf8),
            now: now
        )

        XCTAssertEqual(snapshot.identity, .claude)
        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 24.5)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
        XCTAssertEqual(snapshot.rateWindow.resetAt, Date(timeIntervalSince1970: 1_800_001_800))
        XCTAssertEqual(snapshot.remainingPercent, 75.5)
    }

    func testClaudeStatuslineFileReaderUsesCacheModificationDate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let cacheUpdatedAt = now.addingTimeInterval(-30)

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try claudeStatuslineFixture.write(to: cacheURL, atomically: true, encoding: .utf8)
        try setModificationDate(cacheUpdatedAt, for: cacheURL)

        let snapshot = try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)

        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.updatedAt, cacheUpdatedAt)
    }

    func testClaudeStatuslineFileReaderRejectsStaleCache() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try claudeStatuslineFixture.write(to: cacheURL, atomically: true, encoding: .utf8)
        try setModificationDate(
            now.addingTimeInterval(-ClaudeStatuslineSnapshotReader.maximumCacheAge - 1),
            for: cacheURL
        )

        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .statuslineCacheStale)
        }
    }

    func testClaudeStatuslineFileReaderRejectsFreshCacheWithExpiredReset() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let expiredFixture = """
        {
          "rate_limits": {
            "five_hour": {
              "used_percentage": 0,
              "resets_at": "\(Int(now.addingTimeInterval(-60).timeIntervalSince1970))",
              "duration_minutes": 300
            }
          }
        }
        """

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try expiredFixture.write(to: cacheURL, atomically: true, encoding: .utf8)
        try setModificationDate(now, for: cacheURL)

        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .invalidFiveHourRateLimit)
        }
    }

    func testClaudeStatuslineReaderAcceptsNumericResetTimestamp() throws {
        let fixture = """
        {
          "rate_limits": {
            "five_hour": {
              "used_percentage": "24.5",
              "resets_at": 1800001800,
              "duration_minutes": "300"
            }
          }
        }
        """

        let snapshot = try ClaudeStatuslineSnapshotReader.snapshot(
            from: Data(fixture.utf8),
            now: now
        )

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 24.5)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
        XCTAssertEqual(snapshot.rateWindow.resetAt, Date(timeIntervalSince1970: 1_800_001_800))
    }

    func testClaudeStatuslineReaderFallsBackForInvalidDurationValues() throws {
        let fixture = """
        {
          "rate_limits": {
            "five_hour": {
              "used_percentage": "24.5",
              "resets_at": 1800001800,
              "duration_minutes": 0.5,
              "window_minutes": "240"
            }
          }
        }
        """

        let snapshot = try ClaudeStatuslineSnapshotReader.snapshot(
            from: Data(fixture.utf8),
            now: now
        )

        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 240)
    }

    func testClaudeStatuslineReaderDefaultsWhenAllDurationValuesAreInvalid() throws {
        let fixture = """
        {
          "rate_limits": {
            "five_hour": {
              "used_percentage": "24.5",
              "resets_at": 1800001800,
              "duration_minutes": -1,
              "window_minutes": "0.5"
            }
          }
        }
        """

        let snapshot = try ClaudeStatuslineSnapshotReader.snapshot(
            from: Data(fixture.utf8),
            now: now
        )

        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
    }

    func testClaudeStatuslineReaderRejectsMissingFiveHourWindow() {
        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader.snapshot(
                from: Data(#"{"rate_limits":{"seven_day":{"used_percentage":10}}}"#.utf8),
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .missingFiveHourRateLimit)
        }
    }

    func testClaudeStatuslineReaderRejectsOversizedCacheFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0, count: ClaudeStatuslineSnapshotReader.maximumCacheBytes + 1)
            .write(to: cacheURL)

        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .statuslineCacheUnavailable)
        }
    }

    func testClaudeStatuslineReaderRejectsSymlinkCacheFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let targetURL = root.appendingPathComponent("target.json")

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try claudeStatuslineFixture.write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: cacheURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        ) { error in
            XCTAssertEqual(error as? ClaudeUsageError, .statuslineCacheUnavailable)
        }
    }

    func testClaudeProviderUsesStatuslineBeforeOtherSources() {
        let exact = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 11,
                resetAt: now.addingTimeInterval(600),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 60,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .success(exact)),
            localUsageReader: localUsageReader,
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 11)
        XCTAssertEqual(localUsageReader.callCount, 0)
    }

    func testClaudeProviderUsesCachedExactSnapshotBeforeLocalEstimate() {
        let suiteName = "PromptJuiceClaudeCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = ClaudeSnapshotCache(defaults: defaults)
        cache.save(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 22,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now
        ))

        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 60,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheUnavailable)),
            localUsageReader: StubClaudeLocalUsageReader(result: .success(estimate)),
            cache: cache
        )

        let snapshot = provider.snapshots(now: now.addingTimeInterval(60))[0]

        XCTAssertEqual(snapshot.source, .claudeCache)
        XCTAssertEqual(snapshot.confidence, .stale)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 22)
        XCTAssertEqual(snapshot.statusDetail, "Claude statusline cache unavailable")
    }

    func testClaudeProviderSkipsLocalEstimateWhenStatuslineCacheIsUnavailableByDefault() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 60,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheUnavailable)),
            localUsageReader: localUsageReader,
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.statusDetail, "Claude statusline cache unavailable")
        XCTAssertEqual(localUsageReader.callCount, 0)
    }

    func testClaudeProviderUsesLocalEstimateWhenExplicitlyEnabled() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 60,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheUnavailable)),
            localUsageReader: localUsageReader,
            cache: nil,
            localEstimatePolicy: .enabled
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(localUsageReader.callCount, 1)
    }

    func testClaudeProviderUsesLocalEstimateWhenStatuslineResetIsInvalidAndPolicyIsEnabled() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 3,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.invalidFiveHourRateLimit)),
            localUsageReader: localUsageReader,
            cache: nil,
            localEstimatePolicy: .enabled
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 3)
        XCTAssertEqual(localUsageReader.callCount, 1)
    }

    func testClaudeProviderUsesLocalEstimateWhenStatuslineResetIsInvalidAndInvalidOnlyPolicyIsEnabled() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 3,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.invalidFiveHourRateLimit)),
            localUsageReader: localUsageReader,
            cache: nil,
            localEstimatePolicy: .invalidStatuslineOnly
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 3)
        XCTAssertEqual(localUsageReader.callCount, 1)
    }

    func testClaudeProviderSkipsLocalEstimateForMissingCacheWhenInvalidOnlyPolicyIsEnabled() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 3,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheUnavailable)),
            localUsageReader: localUsageReader,
            cache: nil,
            localEstimatePolicy: .invalidStatuslineOnly
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.statusDetail, "Claude statusline cache unavailable")
        XCTAssertEqual(localUsageReader.callCount, 0)
    }

    func testClaudeProviderUsesLocalEstimateForFreshCacheWithExpiredResetWhenInvalidOnlyPolicyIsEnabled() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let project = root.appendingPathComponent("projects/demo", isDirectory: true)
        let log = project.appendingPathComponent("session.jsonl")
        let expiredFixture = """
        {
          "rate_limits": {
            "five_hour": {
              "used_percentage": 0,
              "resets_at": "\(Int(now.addingTimeInterval(-60).timeIntervalSince1970))",
              "duration_minutes": 300
            }
          }
        }
        """

        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try expiredFixture.write(to: cacheURL, atomically: true, encoding: .utf8)
        try localClaudeLogFixture.write(to: log, atomically: true, encoding: .utf8)
        try setModificationDate(now, for: cacheURL)
        try setModificationDate(now, for: log)

        let provider = ClaudeProviderClient(
            statuslineReader: ClaudeStatuslineSnapshotReader(cacheURL: cacheURL),
            localUsageReader: ClaudeLocalLogUsageReader(
                projectRoots: [root.appendingPathComponent("projects", isDirectory: true)],
                limits: .unboundedForTests
            ),
            cache: nil,
            localEstimatePolicy: .invalidStatuslineOnly
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.rateWindow.resetAt, expectedActiveClaudeBlockReset)
    }

    func testClaudeProviderSkipsLocalEstimateWhenStatuslineCacheIsStaleByDefault() {
        let estimate = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 60,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )
        let localUsageReader = CountingClaudeLocalUsageReader(result: .success(estimate))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheStale)),
            localUsageReader: localUsageReader,
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.statusDetail, "Claude statusline cache stale")
        XCTAssertEqual(localUsageReader.callCount, 0)
    }

    func testClaudeProviderSkipsCachedExactWhenStatuslineCacheIsStale() {
        let suiteName = "PromptJuiceClaudeStaleCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = ClaudeSnapshotCache(defaults: defaults)
        cache.save(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 22,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now
        ))
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheStale)),
            localUsageReader: StubClaudeLocalUsageReader(result: .failure(ClaudeUsageError.localLogActiveBlockUnavailable)),
            cache: cache
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.statusDetail, "Claude statusline cache stale")
    }

    func testClaudeProviderReturnsUnavailableWhenAllSourcesFail() {
        let provider = ClaudeProviderClient(
            statuslineReader: StubClaudeStatuslineReader(result: .failure(ClaudeUsageError.statuslineCacheUnavailable)),
            localUsageReader: StubClaudeLocalUsageReader(result: .failure(ClaudeUsageError.localLogActiveBlockUnavailable)),
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.identity, .claude)
        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .unavailable)
        XCTAssertEqual(snapshot.rateWindow, .unavailable)
    }

    func testClaudeLocalLogReaderParsesDedupesAndEstimatesActiveBlock() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("projects/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let log = project.appendingPathComponent("session.jsonl")
        try localClaudeLogFixture.write(to: log, atomically: true, encoding: .utf8)

        let reader = ClaudeLocalLogUsageReader(projectRoots: [
            root.appendingPathComponent("projects", isDirectory: true)
        ], limits: .unboundedForTests)

        let entries = reader.loadEntries()
        let snapshot = try reader.snapshot(now: now)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.totalTokens).sorted(), [400, 500, 1_000])
        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 90)
        XCTAssertEqual(snapshot.rateWindow.resetAt, expectedActiveClaudeBlockReset)
        XCTAssertEqual(snapshot.statusDetail, "Estimated from local Claude logs")
    }

    func testClaudeLocalLogReaderBoundsRecentFileScanAndReadsTails() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("projects/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let limits = ClaudeLocalLogUsageReader.Limits(
            maximumFiles: 2,
            maximumTotalBytes: 2 * 1024,
            maximumBytesPerFile: 768,
            recentFileAge: 60 * 60
        )
        let reader = ClaudeLocalLogUsageReader(
            projectRoots: [root.appendingPathComponent("projects", isDirectory: true)],
            limits: limits
        )

        for index in 0..<4 {
            let file = project.appendingPathComponent("recent-\(index).jsonl")
            try (String(repeating: "x", count: 2_000) + "\n" + localClaudeLogLine(
                timestamp: now.addingTimeInterval(-Double(index + 1) * 60),
                inputTokens: 100 + index,
                requestID: "recent-\(index)"
            )).write(to: file, atomically: true, encoding: .utf8)
            try setModificationDate(now.addingTimeInterval(-Double(index) * 60), for: file)
        }

        let oldFile = project.appendingPathComponent("old.jsonl")
        try localClaudeLogLine(
            timestamp: now.addingTimeInterval(-30 * 60),
            inputTokens: 999,
            requestID: "old"
        ).write(to: oldFile, atomically: true, encoding: .utf8)
        try setModificationDate(now.addingTimeInterval(-2 * 60 * 60), for: oldFile)

        let urls = reader.usageFileURLs(now: now)
        let entries = reader.loadEntries(now: now)

        XCTAssertEqual(urls.map(\.lastPathComponent), ["recent-0.jsonl", "recent-1.jsonl"])
        XCTAssertEqual(entries.compactMap(\.requestID).sorted(), ["recent-0", "recent-1"])
        XCTAssertFalse(entries.contains { $0.requestID == "old" })
    }

    func testClaudeLocalLogReaderReturnsNoEntriesWhenTaskIsCancelled() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appendingPathComponent("projects/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        for index in 0..<10 {
            let file = project.appendingPathComponent("session-\(index).jsonl")
            try localClaudeLogFixture.write(to: file, atomically: true, encoding: .utf8)
            try setModificationDate(now, for: file)
        }

        let reader = ClaudeLocalLogUsageReader(projectRoots: [
            root.appendingPathComponent("projects", isDirectory: true)
        ], limits: .unboundedForTests)
        let fixedNow = now
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            return reader.loadEntries(now: fixedNow)
        }

        try? await Task.sleep(nanoseconds: 5_000_000)
        task.cancel()
        let entries = await task.value

        XCTAssertEqual(entries, [])
    }

    func testClaudeLocalLogReaderUsesClaudeConfigDirRoots() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let first = home.appendingPathComponent("one")
        let secondProjects = home.appendingPathComponent("two/projects")
        let reader = ClaudeLocalLogUsageReader(
            environment: ["CLAUDE_CONFIG_DIR": "\(first.path),\(secondProjects.path)"],
            homeDirectory: home
        )

        XCTAssertEqual(reader.projectRootURLs(), [
            first.appendingPathComponent("projects", isDirectory: true),
            secondProjects
        ])
    }

    func testClaudeStatuslineBridgeDefaultsToPlutilAndWritesSanitizedCache() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateInputURL = root.appendingPathComponent("delegate-input.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: delegateInputURL,
            output: "custom statusline"
        )
        let input = """
        {
          "workspace": { "current_dir": "/secret/project" },
          "model": { "display_name": "Claude" },
          "context_window": { "used_percentage": 42 },
          "rate_limits": {
            "five_hour": {
              "used_percentage": "12.5",
              "resets_at": 1800001800,
              "duration_minutes": "300"
            }
          }
        }
        """

        let result = try runClaudeStatuslineBridge(
            input: input,
            cacheURL: cacheURL,
            delegateURL: delegateURL
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "custom statusline")
        XCTAssertEqual(try String(contentsOf: delegateInputURL, encoding: .utf8), input)

        let fiveHour = try bridgeCacheFiveHour(cacheURL)
        XCTAssertEqual(fiveHour["used_percentage"] as? Double, 12.5)
        XCTAssertEqual(fiveHour["resets_at"] as? String, "1800001800")
        XCTAssertEqual(fiveHour["duration_minutes"] as? Int, 300)

        let cacheText = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertFalse(cacheText.contains("workspace"))
        XCTAssertFalse(cacheText.contains("current_dir"))
        XCTAssertFalse(cacheText.contains("model"))

        let debugURL = cacheURL.deletingLastPathComponent().appendingPathComponent("debug-latest.json")
        let debugText = try String(contentsOf: debugURL, encoding: .utf8)
        XCTAssertFalse(debugText.contains("workspace"))
        XCTAssertFalse(debugText.contains("current_dir"))
        XCTAssertFalse(debugText.contains("model"))

        let debugRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(debugText.utf8)) as? [String: Any])
        let debugFiveHour = try XCTUnwrap(debugRoot["five_hour"] as? [String: Any])
        XCTAssertEqual(debugFiveHour["used_percentage"] as? String, "12.5")
        XCTAssertEqual(debugFiveHour["resets_at"] as? String, "1800001800")
        XCTAssertEqual(debugFiveHour["duration_minutes"] as? String, "300")

        let snapshot = try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 12.5)
        XCTAssertEqual(snapshot.rateWindow.resetAt, Date(timeIntervalSince1970: 1_800_001_800))
    }

    func testClaudeStatuslineBridgeAutoParserWritesCache() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: root.appendingPathComponent("delegate-input.json"),
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: #"{"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":"2030-01-01T00:00:00Z","window_minutes":"240"}}}"#,
            cacheURL: cacheURL,
            delegateURL: delegateURL,
            parser: "auto"
        )

        XCTAssertEqual(result.status, 0)
        let fiveHour = try bridgeCacheFiveHour(cacheURL)
        XCTAssertEqual(fiveHour["used_percentage"] as? Double, 12.5)
        XCTAssertEqual(fiveHour["resets_at"] as? String, "2030-01-01T00:00:00Z")
        XCTAssertEqual(fiveHour["duration_minutes"] as? Int, 240)
    }

    func testClaudeStatuslineBridgeCanDisableDebugOutput() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: root.appendingPathComponent("delegate-input.json"),
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: claudeStatuslineFixture,
            cacheURL: cacheURL,
            delegateURL: delegateURL,
            extraEnvironment: ["PROMPTJUICE_CLAUDE_STATUS_DEBUG": "0"]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: cacheURL.deletingLastPathComponent()
                    .appendingPathComponent("debug-latest.json")
                    .path
            )
        )
    }

    func testClaudeStatuslineBridgeWritesCustomDebugPathWithNullMissingFields() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let debugURL = root.appendingPathComponent("Debug/custom-debug.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: root.appendingPathComponent("delegate-input.json"),
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: #"{"context_window":{"used_percentage":42}}"#,
            cacheURL: cacheURL,
            delegateURL: delegateURL,
            extraEnvironment: ["PROMPTJUICE_CLAUDE_STATUS_DEBUG_PATH": debugURL.path]
        )

        XCTAssertEqual(result.status, 0)

        let debugRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: debugURL)) as? [String: Any])
        let debugFiveHour = try XCTUnwrap(debugRoot["five_hour"] as? [String: Any])
        XCTAssert(debugFiveHour["used_percentage"] is NSNull)
        XCTAssert(debugFiveHour["resets_at"] is NSNull)
        XCTAssert(debugFiveHour["duration_minutes"] is NSNull)
    }

    func testClaudeStatuslineBridgeDefaultsInvalidOptionalDurationToFiveHours() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: root.appendingPathComponent("delegate-input.json"),
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: #"{"rate_limits":{"five_hour":{"used_percentage":"8","resets_at":"1800001800","duration_minutes":"0.5","window_minutes":"also later"}}}"#,
            cacheURL: cacheURL,
            delegateURL: delegateURL
        )

        XCTAssertEqual(result.status, 0)
        let fiveHour = try bridgeCacheFiveHour(cacheURL)
        XCTAssertEqual(fiveHour["used_percentage"] as? Double, 8)
        XCTAssertEqual(fiveHour["duration_minutes"] as? Int, 300)
    }

    func testClaudeStatuslineBridgeJQParserRollbackWritesCache() throws {
        try requireJQ()

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: root.appendingPathComponent("delegate-input.json"),
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: #"{"rate_limits":{"five_hour":{"used_percentage":"12.5","resets_at":1800001800}}}"#,
            cacheURL: cacheURL,
            delegateURL: delegateURL,
            parser: "jq"
        )

        XCTAssertEqual(result.status, 0)
        let fiveHour = try bridgeCacheFiveHour(cacheURL)
        XCTAssertEqual(fiveHour["used_percentage"] as? Double, 12.5)
        XCTAssertEqual(fiveHour["resets_at"] as? String, "1800001800")
        XCTAssertEqual(fiveHour["duration_minutes"] as? Int, 300)
    }

    func testClaudeStatuslineBridgeWritesUnavailableMarkerForInvalidRequiredFields() throws {
        let cases: [(name: String, input: String)] = [
            ("missing rate limits", #"{"context_window":{"used_percentage":42}}"#),
            ("missing used percentage", #"{"rate_limits":{"five_hour":{"resets_at":1800001800}}}"#),
            ("negative used percentage", #"{"rate_limits":{"five_hour":{"used_percentage":-1,"resets_at":1800001800}}}"#),
            ("non-numeric used percentage", #"{"rate_limits":{"five_hour":{"used_percentage":"soon","resets_at":1800001800}}}"#),
            ("overflow used percentage", #"{"rate_limits":{"five_hour":{"used_percentage":"1e999","resets_at":1800001800}}}"#),
            ("array used percentage", #"{"rate_limits":{"five_hour":{"used_percentage":[12],"resets_at":1800001800}}}"#),
            ("missing reset", #"{"rate_limits":{"five_hour":{"used_percentage":12.5}}}"#),
            ("object reset", #"{"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":{"bad":1}}}}"#),
            ("malformed json", #"{"rate_limits":{"five_hour":"#)
        ]

        for testCase in cases {
            let root = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
            let delegateInputURL = root.appendingPathComponent("delegate-input.json")
            let delegateURL = try makeDelegateScript(
                in: root,
                delegateInputURL: delegateInputURL,
                output: "custom statusline"
            )

            let result = try runClaudeStatuslineBridge(
                input: testCase.input,
                cacheURL: cacheURL,
                delegateURL: delegateURL
            )

            XCTAssertEqual(result.status, 0, testCase.name)
            XCTAssertEqual(result.output, "custom statusline", testCase.name)
            XCTAssertEqual(try String(contentsOf: delegateInputURL, encoding: .utf8), testCase.input, testCase.name)
            let marker = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
            XCTAssertNotNil(marker?["rate_limits"], testCase.name)
            XCTAssertThrowsError(
                try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now),
                testCase.name
            )
        }
    }

    func testClaudeStatuslineBridgeWritesUnavailableMarkerWhenRateLimitsAreMissing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheURL = root.appendingPathComponent("ClaudeStatus/latest.json")
        let delegateInputURL = root.appendingPathComponent("delegate-input.json")
        let delegateURL = try makeDelegateScript(
            in: root,
            delegateInputURL: delegateInputURL,
            output: "custom statusline"
        )

        let result = try runClaudeStatuslineBridge(
            input: #"{"context_window":{"used_percentage":42}}"#,
            cacheURL: cacheURL,
            delegateURL: delegateURL
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "custom statusline")
        let marker = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
        XCTAssertNotNil(marker?["rate_limits"])
        XCTAssertThrowsError(
            try ClaudeStatuslineSnapshotReader(cacheURL: cacheURL).snapshot(now: now)
        )
    }

    func testEstimatedClaudeSnapshotCanTriggerAlert() {
        let snapshot = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 30,
                resetAt: now.addingTimeInterval(20 * 60),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now
        )

        XCTAssertTrue(AlertEngine().shouldUseSoon(
            for: snapshot,
            thresholds: AlertThresholds(remainingMinutes: 30, remainingPercent: 50),
            now: now
        ))
    }

    func testRateLimitParserPrefersCodexBucket() throws {
        let snapshot = try decodeRateLimits(multiBucketFixture)
            .providerSnapshot(now: now)

        XCTAssertEqual(snapshot.rateWindow.usedPercent, 6)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
    }

    func testRateLimitParserSupportsSingleBucketResponse() throws {
        let snapshot = try decodeRateLimits(singleBucketFixture)
            .providerSnapshot(now: now)

        XCTAssertEqual(snapshot.rateWindow.usedPercent, 17)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
    }

    func testRateLimitParserRejectsExpiredCodexBucket() throws {
        let expiredFixture = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": {
              "usedPercent": 17,
              "windowDurationMins": 300,
              "resetsAt": \(Int(now.addingTimeInterval(-60).timeIntervalSince1970))
            },
            "secondary": null,
            "planType": "pro",
            "rateLimitReachedType": null
          }
        }
        """

        XCTAssertThrowsError(
            try decodeRateLimits(expiredFixture)
                .providerSnapshot(now: now)
        ) { error in
            XCTAssertEqual(error as? CodexRateLimitMappingError, .expiredPrimaryWindow)
        }
    }

    func testLiveCodexAppServerReadsCurrentRateLimitWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["PROMPTJUICE_LIVE_CODEX_TEST"] == "1" else {
            throw XCTSkip("Set PROMPTJUICE_LIVE_CODEX_TEST=1 to read live Codex app-server usage.")
        }

        let snapshot = CodexProviderClient(cache: nil)
            .snapshots(now: Date())[0]

        XCTAssertEqual(snapshot.identity, .codex)
        XCTAssertEqual(snapshot.source, .codexAppServer)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertTrue((0...100).contains(snapshot.clampedUsedPercent))
        XCTAssertNotNil(snapshot.rateWindow.resetAt)
        XCTAssertNotNil(snapshot.rateWindow.durationMinutes)
    }

    private func decodeRateLimits(_ json: String) throws -> CodexRateLimitReadResult {
        try JSONDecoder().decode(
            CodexRateLimitReadResult.self,
            from: Data(json.utf8)
        )
    }

    private struct StubRateLimitReader: CodexRateLimitReading {
        let result: Result<CodexRateLimitReadResult, Error>

        func readRateLimits() throws -> CodexRateLimitReadResult {
            try result.get()
        }
    }

    private struct StubClaudeStatuslineReader: ClaudeStatuslineSnapshotReading {
        let result: Result<ProviderSnapshot, Error>

        func snapshot(now _: Date) throws -> ProviderSnapshot {
            try result.get()
        }
    }

    private struct StubClaudeLocalUsageReader: ClaudeLocalUsageReading {
        let result: Result<ProviderSnapshot, Error>

        func snapshot(now _: Date) throws -> ProviderSnapshot {
            try result.get()
        }
    }

    private final class CountingClaudeLocalUsageReader: ClaudeLocalUsageReading, @unchecked Sendable {
        private let result: Result<ProviderSnapshot, Error>
        private let lock = NSLock()
        private var calls = 0

        init(result: Result<ProviderSnapshot, Error>) {
            self.result = result
        }

        var callCount: Int {
            lock.withLock {
                calls
            }
        }

        func snapshot(now _: Date) throws -> ProviderSnapshot {
            lock.withLock {
                calls += 1
            }

            return try result.get()
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private func requireJQ() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["bash", "-lc", "command -v jq >/dev/null 2>&1"]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XCTSkip("jq is required for the explicit Claude statusline bridge rollback test.")
        }
    }

    private func bridgeCacheFiveHour(_ cacheURL: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: cacheURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rateLimits = try XCTUnwrap(root["rate_limits"] as? [String: Any])
        return try XCTUnwrap(rateLimits["five_hour"] as? [String: Any])
    }

    private func makeDelegateScript(
        in directory: URL,
        delegateInputURL: URL,
        output: String
    ) throws -> URL {
        let scriptURL = directory.appendingPathComponent("delegate.sh")
        let script = """
        #!/usr/bin/env bash
        cat > '\(shellSingleQuotedContent(delegateInputURL.path))'
        printf '%s' '\(shellSingleQuotedContent(output))'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
        return scriptURL
    }

    private func runClaudeStatuslineBridge(
        input: String,
        cacheURL: URL,
        delegateURL: URL,
        parser: String? = nil,
        extraEnvironment: [String: String?] = [:]
    ) throws -> (status: Int32, output: String, error: String) {
        let bridgeURL = repositoryRoot
            .appendingPathComponent("scripts/claude-statusline-bridge.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bridgeURL.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [bridgeURL.path]

        var environment = ProcessInfo.processInfo.environment
        environment["PROMPTJUICE_CLAUDE_STATUS_CACHE"] = cacheURL.path
        environment["PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND"] = "bash \(shellSingleQuoted(delegateURL.path))"
        if let parser {
            environment["PROMPTJUICE_CLAUDE_STATUSLINE_PARSER"] = parser
        } else {
            environment.removeValue(forKey: "PROMPTJUICE_CLAUDE_STATUSLINE_PARSER")
        }
        for (key, value) in extraEnvironment {
            if let value {
                environment[key] = value
            } else {
                environment.removeValue(forKey: key)
            }
        }
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(input.utf8))
        try inputPipe.fileHandleForWriting.close()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try setModificationDate(now, for: cacheURL)
        }

        return (
            process.terminationStatus,
            String(data: output, encoding: .utf8) ?? "",
            String(data: error, encoding: .utf8) ?? ""
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(shellSingleQuotedContent(value))'"
    }

    private func shellSingleQuotedContent(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private let multiBucketFixture = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": {
          "usedPercent": 6,
          "windowDurationMins": 300,
          "resetsAt": 1800005173
        },
        "secondary": null,
        "planType": "pro",
        "rateLimitReachedType": null
      },
      "rateLimitsByLimitId": {
        "codex": {
          "limitId": "codex",
          "limitName": null,
          "primary": {
            "usedPercent": 6,
            "windowDurationMins": 300,
            "resetsAt": 1800005173
          },
          "secondary": null,
          "planType": "pro",
          "rateLimitReachedType": null
        },
        "codex_bengalfox": {
          "limitId": "codex_bengalfox",
          "limitName": "GPT-5.3-Codex-Spark",
          "primary": {
            "usedPercent": 0,
            "windowDurationMins": 300,
            "resetsAt": 1800008210
          },
          "secondary": null,
          "planType": "pro",
          "rateLimitReachedType": null
        }
      }
    }
    """

    private let singleBucketFixture = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": {
          "usedPercent": 17,
          "windowDurationMins": 300,
          "resetsAt": 1800005173
        },
        "secondary": null,
        "planType": "pro",
        "rateLimitReachedType": null
      }
    }
    """

    private let claudeStatuslineFixture = """
    {
      "rate_limits": {
        "five_hour": {
          "used_percentage": 24.5,
          "resets_at": "1800001800",
          "duration_minutes": 300
        }
      }
    }
    """

    private var expectedActiveClaudeBlockReset: Date {
        let activeTimestamp = now.addingTimeInterval(-30 * 60)
        let blockStart = floor(activeTimestamp.timeIntervalSince1970 / 3600) * 3600
        return Date(timeIntervalSince1970: blockStart + 5 * 60 * 60)
    }

    private func localClaudeLogLine(
        timestamp: Date,
        inputTokens: Int,
        requestID: String
    ) -> String {
        let timestamp = Int(timestamp.timeIntervalSince1970)
        return """
        {"type":"assistant","timestamp":"\(timestamp)","message":{"id":"msg_\(requestID)","usage":{"input_tokens":\(inputTokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"\(requestID)"}
        """
    }

    private var localClaudeLogFixture: String {
        let previousTimestamp = Int(now.addingTimeInterval(-7 * 60 * 60).timeIntervalSince1970)
        let activeTimestamp = Int(now.addingTimeInterval(-30 * 60).timeIntervalSince1970)
        return """
        {"type":"assistant","timestamp":"\(previousTimestamp)","message":{"id":"msg_previous","usage":{"input_tokens":1000,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_previous"}
        {"type":"assistant","timestamp":"\(activeTimestamp)","message":{"id":"msg_active","usage":{"input_tokens":400,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_active"}
        {"type":"assistant","timestamp":"\(activeTimestamp)","message":{"id":"msg_active","usage":{"input_tokens":200,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_active"}
        {"type":"assistant","timestamp":"\(activeTimestamp)","message":{"id":"msg_active_two","usage":{"input_tokens":500,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"requestId":"req_active_two"}
        {"type":"user","timestamp":"\(activeTimestamp)","message":{"usage":{"input_tokens":9999}}}
        """
    }
}
