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
}
