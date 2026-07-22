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

    func testEffectiveRemainingPercentUsesWeeklyMinimumForBothProviders() {
        let snapshots = [ProviderIdentity.claude, .codex].map { identity in
            ProviderSnapshot(
                identity: identity,
                rateWindow: .available(
                    usedPercent: 20,
                    resetAt: now.addingTimeInterval(3 * 60 * 60),
                    durationMinutes: 300
                ),
                weeklyWindow: .available(
                    usedPercent: 88,
                    resetAt: now.addingTimeInterval(3 * 24 * 60 * 60),
                    durationMinutes: 10_080
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now,
                weeklyUpdatedAt: now
            )
        }

        XCTAssertEqual(snapshots.map(\.sessionRemainingPercent), [80, 80])
        XCTAssertEqual(snapshots.map(\.weeklyRemainingPercent), [12, 12])
        XCTAssertEqual(snapshots.map(\.remainingPercent), [80, 80])
        XCTAssertEqual(snapshots.map(\.effectiveRemainingPercent), [12, 12])
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
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 12)
        XCTAssertEqual(snapshot.weeklyWindow?.durationMinutes, 10_080)
        XCTAssertEqual(snapshot.weeklyWindow?.resetAt, Date(timeIntervalSince1970: 1_800_345_600))
        XCTAssertEqual(snapshot.weeklyUpdatedAt, now)
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

    func testCodexSnapshotCacheDecodesLegacySessionBlob() throws {
        let suiteName = "PromptJuiceCodexLegacyCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let resetAt = now.addingTimeInterval(3 * 60 * 60)
        let updatedAt = now.addingTimeInterval(-10 * 60)
        let legacy = LegacyProviderCacheBlob(
            usedPercent: 41,
            resetAt: resetAt,
            durationMinutes: 300,
            updatedAt: updatedAt
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: "lastGoodCodexSnapshot"
        )

        let snapshot = try XCTUnwrap(
            CodexSnapshotCache(defaults: defaults).snapshot(
                now: now.addingTimeInterval(60),
                failureDetail: "Codex app-server timed out"
            )
        )

        XCTAssertEqual(snapshot.source, .codexCache)
        XCTAssertEqual(snapshot.confidence, .stale)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 41)
        XCTAssertEqual(snapshot.rateWindow.resetAt, resetAt)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
        XCTAssertEqual(snapshot.updatedAt, updatedAt)
        XCTAssertFalse(snapshot.isFreshSessionWindow)
        XCTAssertNil(snapshot.weeklyWindow)
        XCTAssertEqual(snapshot.statusDetail, "Codex app-server timed out")
    }

    func testCodexSnapshotCacheOnlySavesExactAppServerSnapshots() {
        let suiteName = "PromptJuiceCodexSaveEligibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = CodexSnapshotCache(defaults: defaults)
        cache.save(ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 50,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .stale,
            updatedAt: now
        ))
        cache.save(ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 51,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        ))

        XCTAssertNil(
            cache.snapshot(
                now: now.addingTimeInterval(60),
                failureDetail: "Codex app-server timed out"
            )
        )
    }

    func testCodexSnapshotCachePreservesWeeklyAcrossSessionOnlySave() throws {
        let suiteName = "PromptJuiceCodexWeeklyCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = CodexSnapshotCache(defaults: defaults)
        let firstSnapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: now.addingTimeInterval(3 * 60 * 60),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 44,
                resetAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now,
            weeklyUpdatedAt: now
        )
        let sessionOnlySnapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 30,
                resetAt: now.addingTimeInterval(4 * 60 * 60),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now.addingTimeInterval(60)
        )

        cache.save(firstSnapshot)
        cache.save(sessionOnlySnapshot)

        let snapshot = try XCTUnwrap(
            cache.snapshot(
                now: now.addingTimeInterval(120),
                failureDetail: "Codex app-server timed out"
            )
        )

        XCTAssertEqual(snapshot.source, .codexCache)
        XCTAssertEqual(snapshot.confidence, .stale)
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 30)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 44)
        XCTAssertEqual(snapshot.remainingPercent, 70)
        XCTAssertEqual(snapshot.effectiveRemainingPercent, 56)
        XCTAssertEqual(snapshot.statusDetail, "Codex app-server timed out")
    }

    func testCodexSnapshotCacheCarriesValidWeeklyAsFreshSession() throws {
        let suiteName = "PromptJuiceCodexFreshCacheTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = CodexSnapshotCache(defaults: defaults)
        cache.save(
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 20,
                    resetAt: now.addingTimeInterval(30 * 60),
                    durationMinutes: 300
                ),
                weeklyWindow: .available(
                    usedPercent: 35,
                    resetAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                    durationMinutes: 10_080
                ),
                source: .codexAppServer,
                confidence: .exact,
                updatedAt: now,
                weeklyUpdatedAt: now
            )
        )

        let snapshot = try XCTUnwrap(
            cache.snapshot(
                now: now.addingTimeInterval(60 * 60),
                failureDetail: "Codex app-server timed out"
            )
        )

        XCTAssertTrue(snapshot.isFreshSessionWindow)
        XCTAssertEqual(snapshot.rateWindow, .unavailable)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 35)
        XCTAssertEqual(snapshot.remainingPercent, 100)
        XCTAssertEqual(snapshot.effectiveRemainingPercent, 65)
        XCTAssertEqual(snapshot.weeklyUpdatedAt, now)
    }

    func testClaudeSnapshotCacheSavesUsageSnapshotsUnlessUnavailable() throws {
        let suiteName = "PromptJuiceClaudeSaveEligibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cache = ClaudeSnapshotCache(defaults: defaults)
        cache.save(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 52,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: now
        ))

        XCTAssertNil(
            cache.snapshot(
                now: now.addingTimeInterval(60),
                failureDetail: "Claude usage unavailable"
            )
        )

        cache.save(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 22,
                resetAt: now.addingTimeInterval(900),
                durationMinutes: 300
            ),
            source: .claudeUsageCLI,
            confidence: .stale,
            updatedAt: now
        ))

        let snapshot = try XCTUnwrap(
            cache.snapshot(
                now: now.addingTimeInterval(60),
                failureDetail: "Claude usage unavailable"
            )
        )
        XCTAssertEqual(snapshot.rateWindow.usedPercent, 22)
        XCTAssertEqual(snapshot.source, .claudeCache)
    }

    func testClaudeSnapshotCacheReturnsNilWhenAllWindowsExpired() {
        let suiteName = "PromptJuiceClaudeExpiredCacheTests.\(UUID().uuidString)"
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
            weeklyWindow: .available(
                usedPercent: 33,
                resetAt: now.addingTimeInterval(1_800),
                durationMinutes: 10_080
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: now,
            weeklyUpdatedAt: now
        ))

        XCTAssertNil(
            cache.snapshot(
                now: now.addingTimeInterval(3_600),
                failureDetail: "Claude usage unavailable"
            )
        )
    }

    func testClaudeSnapshotCachePreservesWeeklyAcrossSessionOnlySave() throws {
        let suiteName = "PromptJuiceClaudeWeeklyMergeCacheTests.\(UUID().uuidString)"
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
            weeklyWindow: .available(
                usedPercent: 44,
                resetAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: now,
            weeklyUpdatedAt: now
        ))
        cache.save(ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 11,
                resetAt: now.addingTimeInterval(1_200),
                durationMinutes: 300
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: now.addingTimeInterval(60)
        ))

        let snapshot = try XCTUnwrap(
            cache.snapshot(
                now: now.addingTimeInterval(90),
                failureDetail: "Claude usage unavailable"
            )
        )

        XCTAssertEqual(snapshot.rateWindow.usedPercent, 11)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 44)
        XCTAssertEqual(snapshot.remainingPercent, 89)
        XCTAssertEqual(snapshot.effectiveRemainingPercent, 56)
    }

    func testClaudeSnapshotCacheCarriesWeeklyWithoutFabricatingFreshSession() throws {
        let suiteName = "PromptJuiceClaudeWeeklyOnlyCacheTests.\(UUID().uuidString)"
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
            weeklyWindow: .available(
                usedPercent: 35,
                resetAt: now.addingTimeInterval(4 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: now,
            weeklyUpdatedAt: now
        ))

        let snapshot = try XCTUnwrap(
            cache.snapshot(
                now: now.addingTimeInterval(1_800),
                failureDetail: "Claude usage unavailable"
            )
        )

        XCTAssertFalse(snapshot.isFreshSessionWindow)
        XCTAssertEqual(snapshot.rateWindow, .unavailable)
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 35)
        XCTAssertEqual(snapshot.remainingPercent, 0)
        XCTAssertEqual(snapshot.weeklyRemainingPercent, 65)
        XCTAssertEqual(snapshot.effectiveRemainingPercent, 0)
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
        XCTAssertEqual(snapshot.weeklyWindow?.usedPercent, 12)
        XCTAssertEqual(snapshot.weeklyWindow?.durationMinutes, 10_080)
    }

    func testRateLimitParserSupportsSingleBucketResponse() throws {
        let snapshot = try decodeRateLimits(singleBucketFixture)
            .providerSnapshot(now: now)

        XCTAssertEqual(snapshot.rateWindow.usedPercent, 17)
        XCTAssertEqual(snapshot.rateWindow.durationMinutes, 300)
        XCTAssertNil(snapshot.weeklyWindow)
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

        private struct LegacyProviderCacheBlob: Encodable {
        let usedPercent: Double
        let resetAt: Date
        let durationMinutes: Int
        let updatedAt: Date
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
        "secondary": {
          "usedPercent": 12,
          "windowDurationMins": 10080,
          "resetsAt": 1800345600
        },
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
          "secondary": {
            "usedPercent": 12,
            "windowDurationMins": 10080,
            "resetsAt": 1800345600
          },
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
