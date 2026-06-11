import XCTest
@testable import PromptJuice

final class ProviderClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDemoProviderReturnsNormalizedSnapshots() {
        let snapshots = DemoProviderClient(scenario: .underusedCodex)
            .snapshots(now: now)

        XCTAssertEqual(snapshots.map(\.identity), [.claude, .codex])
        XCTAssertEqual(snapshots.map(\.source), [.demo, .demo])
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
        XCTAssertEqual(snapshot.rateWindow.resetAt, Date(timeIntervalSince1970: 1_781_195_173))
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
            statuslineReader: StubClaudeStatuslineReader(result: .success(exact)),
            localUsageReader: StubClaudeLocalUsageReader(result: .success(estimate)),
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeStatusline)
        XCTAssertEqual(snapshot.confidence, .exact)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 11)
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

    func testClaudeProviderUsesLocalEstimateWhenExactSourcesAreUnavailable() {
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
            cache: nil
        )

        let snapshot = provider.snapshots(now: now)[0]

        XCTAssertEqual(snapshot.source, .claudeLocalLogs)
        XCTAssertEqual(snapshot.confidence, .estimated)
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
        ])

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

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private let multiBucketFixture = """
    {
      "rateLimits": {
        "limitId": "codex",
        "limitName": null,
        "primary": {
          "usedPercent": 6,
          "windowDurationMins": 300,
          "resetsAt": 1781195173
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
            "resetsAt": 1781195173
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
            "resetsAt": 1781208210
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
          "resetsAt": 1781195173
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
