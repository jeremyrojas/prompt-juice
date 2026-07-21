import Darwin
import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeUsageCoordinatorTests: XCTestCase {
    func testScheduleCoversTriggersCooldownFreshnessDebounceAndBudgets() {
        let now = date(2026, 7, 21, 14, 0)
        let schedule = ClaudeUsageSchedule()

        for reason in [
            ClaudeRefreshReason.launch,
            .wake,
            .foreground,
            .panelOpen,
            .manual,
            .timer,
            .resetBoundary,
        ] {
            XCTAssertEqual(
                schedule.decision(for: context(now: now, reason: reason)),
                .probe,
                "Expected \(reason) to probe when due"
            )
        }

        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .timer,
                    nextAttemptAt: now.addingTimeInterval(300)
                )
            ),
            .skipCooldown(nextAttemptAt: now.addingTimeInterval(300))
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .timer,
                    lastSuccessAt: now.addingTimeInterval(-60)
                )
            ),
            .skipFresh
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .resetBoundary,
                    lastSuccessAt: now.addingTimeInterval(-60)
                )
            ),
            .probe
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .manual,
                    lastAttemptAt: now.addingTimeInterval(-30)
                )
            ),
            .skipDebounce
        )

        let fourAutomatic = (0..<4).map {
            ClaudeUsageAttempt(
                date: now.addingTimeInterval(TimeInterval(-$0 * 60)),
                reason: .timer
            )
        }
        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .foreground,
                    recentAttempts: fourAutomatic
                )
            ),
            .skipBudget
        )
        let sixCombined = fourAutomatic + [
            ClaudeUsageAttempt(date: now.addingTimeInterval(-300), reason: .manual),
            ClaudeUsageAttempt(date: now.addingTimeInterval(-360), reason: .manual),
        ]
        XCTAssertEqual(
            schedule.decision(
                for: context(
                    now: now,
                    reason: .manual,
                    force: true,
                    recentAttempts: sixCombined
                )
            ),
            .skipBudget
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(now: now, reason: .timer, providerEnabled: false)
            ),
            .skipDisabled
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(now: now, reason: .timer, isAwake: false)
            ),
            .skipSleeping
        )
        XCTAssertEqual(
            schedule.decision(
                for: context(now: now, reason: .timer, isOnline: false)
            ),
            .skipOffline
        )
    }

    func testPersistenceUsesFiveFifteenThirtySixtyAndRepairsCorruptFixture() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let persistence = ClaudeUsagePersistence(defaults: defaults, key: "state")
        var now = date(2026, 7, 21, 14, 0)

        for minutes in [5, 15, 30, 60, 60] {
            let next = persistence.advanceBackoff(from: now)
            XCTAssertEqual(next, now.addingTimeInterval(TimeInterval(minutes * 60)))
            now = next.addingTimeInterval(1)
            XCTAssertNil(persistence.metadata(now: now).nextAttemptAt)
        }

        persistence.recordSuccess(at: now)
        XCTAssertEqual(
            persistence.advanceBackoff(from: now),
            now.addingTimeInterval(5 * 60)
        )

        XCTAssertFalse(persistence.updateAuthenticationFingerprint("subscription:max"))
        XCTAssertEqual(
            persistence.metadata(now: now).authenticationFingerprint,
            "subscription:max"
        )
        XCTAssertTrue(persistence.updateAuthenticationFingerprint("signedOut:initial"))
        XCTAssertNil(persistence.metadata(now: now).nextAttemptAt)
        XCTAssertEqual(
            persistence.advanceBackoff(from: now),
            now.addingTimeInterval(5 * 60)
        )

        let corrupt = try fixtureData("State/corrupt-next-at.json")
        defaults.set(corrupt, forKey: "corrupt")
        let repaired = ClaudeUsagePersistence(defaults: defaults, key: "corrupt")
            .metadata(now: now)
        XCTAssertTrue(repaired.wasRepaired)
        XCTAssertNil(repaired.nextAttemptAt)
        XCTAssertNil(defaults.data(forKey: "corrupt"))
    }

    func testCLIExactCacheRoundTripsAndClaudeNeverFabricatesFreshWindow() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let cache = ClaudeSnapshotCache(defaults: defaults)
        let now = date(2026, 7, 21, 14, 0)
        let exact = snapshot(
            source: .claudeUsageCLI,
            confidence: .exact,
            usedPercent: 42,
            resetAt: now.addingTimeInterval(3_600),
            updatedAt: now.addingTimeInterval(-120)
        )

        cache.save(exact)
        let restored = try XCTUnwrap(cache.snapshot(now: now, failureDetail: nil))
        XCTAssertEqual(restored.source, .claudeCache)
        XCTAssertEqual(restored.confidence, .stale)
        XCTAssertEqual(restored.usedPercent, 42)
        XCTAssertEqual(restored.updatedAt, exact.updatedAt)
        XCTAssertFalse(restored.isFreshSessionWindow)

        let expiredSession = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 70,
                resetAt: now.addingTimeInterval(-1),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 30,
                resetAt: now.addingTimeInterval(86_400),
                durationMinutes: 10_080
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: now
        )
        cache.save(expiredSession)
        let weeklyOnly = try XCTUnwrap(cache.snapshot(now: now, failureDetail: nil))
        XCTAssertFalse(weeklyOnly.isFreshSessionWindow)
        XCTAssertFalse(weeklyOnly.isAvailable)
        XCTAssertNotNil(weeklyOnly.weeklyWindow)
    }

    func testSourceLadderPrefersCLIThenCacheThenEstimate() {
        let now = date(2026, 7, 21, 14, 0)
        let cli = snapshot(source: .claudeUsageCLI, confidence: .exact, updatedAt: now)
        let cached = snapshot(source: .claudeCache, confidence: .stale, usedPercent: 45, updatedAt: now)
        let estimate = snapshot(source: .claudeLocalLogs, confidence: .estimated, usedPercent: 55, updatedAt: now)
        let cache = MemoryClaudeUsageCache(snapshot: cached)

        XCTAssertEqual(
            ClaudeExactSourceLadder.resolve(
                primary: cli,
                cache: cache,
                estimateReader: FixedClaudeReader(.snapshot(estimate)),
                now: now
            )?.source,
            .claudeUsageCLI
        )
        XCTAssertEqual(
            ClaudeExactSourceLadder.resolve(
                primary: nil,
                cache: cache,
                estimateReader: FixedClaudeReader(.snapshot(estimate)),
                now: now
            )?.source,
            .claudeCache
        )
        cache.storedSnapshot = nil
        XCTAssertEqual(
            ClaudeExactSourceLadder.resolve(
                primary: nil,
                cache: cache,
                estimateReader: FixedClaudeReader(.snapshot(estimate)),
                now: now
            )?.source,
            .claudeLocalLogs
        )
    }

    func testCachedBarsAndBackoffTransitionsT_RL1ThroughT_RL4() async throws {
        let fixture = try makeCoordinatorFixture()
        defer { fixture.remove() }
        let now = date(2026, 7, 21, 14, 0)
        let measuredAt = now.addingTimeInterval(-20 * 60)
        let savedReading = reading(
            usedPercent: 42,
            resetAt: now.addingTimeInterval(2 * 60 * 60),
            measuredAt: measuredAt,
            isSaved: true
        )
        let recoveredReading = reading(
            usedPercent: 50,
            resetAt: now.addingTimeInterval(3 * 60 * 60),
            measuredAt: now.addingTimeInterval(53 * 60),
            isSaved: false
        )
        let probe = ScriptedClaudeUsageProbe([
            .parsed(ClaudeUsageParseResult(
                reading: savedReading,
                rateLimitObserved: true,
                failure: nil
            )),
            .parsed(ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: true,
                failure: nil
            )),
            .parsed(ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: true,
                failure: .malformedMeasurementTimestamp
            )),
            .parsed(ClaudeUsageParseResult(
                reading: recoveredReading,
                rateLimitObserved: false,
                failure: nil
            )),
            .parsed(ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: true,
                failure: nil
            )),
        ])
        let cache = MemoryClaudeUsageCache()
        let coordinator = makeCoordinator(
            fixture: fixture,
            access: .subscription(plan: "max"),
            probe: probe,
            cache: cache
        )

        let first = await coordinator.snapshot(now: now, reason: .manual, force: true)
        XCTAssertEqual(first.snapshot?.source, .claudeUsageCLI)
        XCTAssertEqual(first.snapshot?.updatedAt, measuredAt)
        XCTAssertEqual(first.snapshot?.confidence, .stale)
        XCTAssertEqual(
            first.refresh,
            .backingOff(nextAttemptAt: now.addingTimeInterval(5 * 60))
        )

        let secondNow = now.addingTimeInterval(6 * 60)
        let second = await coordinator.snapshot(now: secondNow, reason: .manual, force: true)
        XCTAssertEqual(second.snapshot?.source, .claudeCache)
        XCTAssertEqual(second.snapshot?.updatedAt, measuredAt)
        XCTAssertEqual(
            second.refresh,
            .backingOff(nextAttemptAt: secondNow.addingTimeInterval(15 * 60))
        )

        let thirdNow = secondNow.addingTimeInterval(16 * 60)
        let third = await coordinator.snapshot(now: thirdNow, reason: .manual, force: true)
        XCTAssertEqual(third.snapshot?.updatedAt, measuredAt)
        XCTAssertEqual(
            third.refresh,
            .backingOff(nextAttemptAt: thirdNow.addingTimeInterval(30 * 60))
        )

        let recoveryNow = thirdNow.addingTimeInterval(31 * 60)
        let recovery = await coordinator.snapshot(
            now: recoveryNow,
            reason: .manual,
            force: true
        )
        XCTAssertEqual(recovery.refresh, .idle)
        XCTAssertEqual(recovery.snapshot?.usedPercent, 50)
        XCTAssertEqual(recovery.snapshot?.confidence, .exact)

        let nextRateLimitNow = recoveryNow.addingTimeInterval(60)
        let resetBackoff = await coordinator.snapshot(
            now: nextRateLimitNow,
            reason: .manual,
            force: true
        )
        XCTAssertEqual(
            resetBackoff.refresh,
            .backingOff(nextAttemptAt: nextRateLimitNow.addingTimeInterval(5 * 60))
        )
        XCTAssertEqual(probe.callCount, 5)
    }

    func testCooldownSkipsProbeAndAlwaysCarriesRetryDate() async throws {
        let fixture = try makeCoordinatorFixture()
        defer { fixture.remove() }
        let now = date(2026, 7, 21, 14, 0)
        let probe = ScriptedClaudeUsageProbe([
            .parsed(ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: true,
                failure: nil
            )),
        ])
        let coordinator = makeCoordinator(
            fixture: fixture,
            access: .subscription(plan: nil),
            probe: probe
        )

        _ = await coordinator.snapshot(now: now, reason: .manual, force: true)
        let duringCooldown = await coordinator.snapshot(
            now: now.addingTimeInterval(30),
            reason: .manual,
            force: true
        )

        XCTAssertEqual(
            duringCooldown.refresh,
            .backingOff(nextAttemptAt: now.addingTimeInterval(5 * 60))
        )
        XCTAssertEqual(probe.callCount, 1)

        let relaunched = makeCoordinator(
            fixture: fixture,
            access: .subscription(plan: nil),
            probe: probe
        )
        let relaunchedDuringCooldown = await relaunched.snapshot(
            now: now.addingTimeInterval(60),
            reason: .launch
        )
        XCTAssertEqual(relaunchedDuringCooldown.access, .subscription(plan: nil))
        XCTAssertEqual(
            relaunchedDuringCooldown.refresh,
            .backingOff(nextAttemptAt: now.addingTimeInterval(5 * 60))
        )
        XCTAssertEqual(probe.callCount, 1)
    }

    func testAllFourSignedOutSnapshotCombinationsRemainIndependent() async throws {
        for reason in [ClaudeSignInReason.initial, .reauthenticationRequired] {
            for hasEstimate in [true, false] {
                let fixture = try makeCoordinatorFixture()
                defer { fixture.remove() }
                let estimate = hasEstimate
                    ? FixedClaudeReader(.snapshot(snapshot(
                        source: .claudeLocalLogs,
                        confidence: .estimated,
                        updatedAt: date(2026, 7, 21, 14, 0)
                    )))
                    : FixedClaudeReader(.failure)
                let probe = ScriptedClaudeUsageProbe([])
                let coordinator = makeCoordinator(
                    fixture: fixture,
                    access: .signedOut(reason: reason),
                    probe: probe,
                    estimateReader: estimate
                )

                let state = await coordinator.snapshot(
                    now: date(2026, 7, 21, 14, 0),
                    reason: .manual,
                    force: true
                )
                XCTAssertEqual(state.access, .signedOut(reason: reason))
                XCTAssertEqual(state.snapshot != nil, hasEstimate)
                XCTAssertEqual(state.snapshot?.confidence, hasEstimate ? .estimated : nil)
                XCTAssertEqual(probe.callCount, 0)
            }
        }
    }

    func testNeutralClaudeAuthenticationIsExcludedFromAggregates() {
        let now = date(2026, 7, 21, 14, 0)
        let claude = snapshot(
            source: .claudeLocalLogs,
            confidence: .estimated,
            usedPercent: 99,
            updatedAt: now
        )
        let codex = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: now.addingTimeInterval(3_600),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now
        )

        for access in [
            ClaudeAccessState.apiBilling,
            .externalProvider(.bedrock),
            .unsupportedAuth,
        ] {
            XCTAssertEqual(
                ClaudeAggregatePolicy.quotaBearingSnapshots(
                    [claude, codex],
                    claudeAccess: access
                ).map(\.provider),
                [.codex]
            )
            XCTAssertTrue(
                ClaudeAggregatePolicy.quotaBearingSnapshots(
                    [claude],
                    claudeAccess: access
                ).isEmpty
            )
        }

        XCTAssertEqual(
            ClaudeAggregatePolicy.quotaBearingSnapshots(
                [claude, codex],
                claudeAccess: .signedOut(reason: .initial)
            ).map(\.provider),
            [.claude, .codex]
        )
    }

    func testConcurrentRefreshesCoalesceIntoOneProbe() async throws {
        let fixture = try makeCoordinatorFixture()
        defer { fixture.remove() }
        let now = date(2026, 7, 21, 14, 0)
        let probe = ScriptedClaudeUsageProbe(
            [.parsed(ClaudeUsageParseResult(
                reading: reading(
                    usedPercent: 42,
                    resetAt: now.addingTimeInterval(3_600),
                    measuredAt: now,
                    isSaved: false
                ),
                rateLimitObserved: false,
                failure: nil
            ))],
            delay: 0.1
        )
        let coordinator = makeCoordinator(
            fixture: fixture,
            access: .subscription(plan: nil),
            probe: probe
        )

        async let first = coordinator.snapshot(now: now, reason: .launch, force: true)
        try await Task.sleep(for: .milliseconds(10))
        async let second = coordinator.snapshot(now: now, reason: .foreground, force: true)
        let states = await [first, second]

        XCTAssertEqual(probe.callCount, 1)
        XCTAssertTrue(states.allSatisfy { $0.snapshot?.usedPercent == 42 })
    }

    private func makeCoordinator(
        fixture: CoordinatorFixture,
        access: ClaudeAccessState,
        probe: ScriptedClaudeUsageProbe,
        cache: MemoryClaudeUsageCache = MemoryClaudeUsageCache(),
        estimateReader: FixedClaudeReader = FixedClaudeReader(.failure)
    ) -> ClaudeUsageCoordinator {
        let authentication: ClaudeAuthentication = switch access {
        case .subscription(let plan):
            .subscription(plan: plan)
        case .signedOut(let reason):
            .signedOut(reason: reason)
        case .apiBilling:
            .apiBilling
        case .externalProvider(let provider):
            .externalProvider(provider)
        case .unsupportedAuth:
            .unsupported
        case .authCheckFailed:
            .checkFailed
        case .checking, .cliMissing, .updateRequired, .workspaceTrustRequired:
            .unsupported
        }
        let check = ClaudePrerequisiteCheck(
            access: access,
            location: ClaudeExecutableLocation(
                invokedURL: URL(fileURLWithPath: "/fake/claude"),
                resolvedURL: URL(fileURLWithPath: "/fake/claude"),
                provenance: .unknown
            ),
            version: .supported(.minimumUsageVersion),
            authentication: authentication
        )

        return ClaudeUsageCoordinator(
            prerequisiteChecker: FixedPrerequisiteChecker(check),
            usageProbe: probe,
            workspace: fixture.workspace,
            cache: cache,
            estimateReader: estimateReader,
            persistence: ClaudeUsagePersistence(
                defaults: fixture.defaults,
                key: "coordinator"
            ),
            environment: [:],
            featureEnabled: true
        )
    }

    private func context(
        now: Date,
        reason: ClaudeRefreshReason,
        force: Bool = false,
        providerEnabled: Bool = true,
        isAwake: Bool = true,
        isOnline: Bool = true,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        recentAttempts: [ClaudeUsageAttempt] = []
    ) -> ClaudeUsageScheduleContext {
        ClaudeUsageScheduleContext(
            now: now,
            reason: reason,
            force: force,
            providerEnabled: providerEnabled,
            isAwake: isAwake,
            isOnline: isOnline,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            nextAttemptAt: nextAttemptAt,
            recentAttempts: recentAttempts
        )
    }

    private func reading(
        usedPercent: Double,
        resetAt: Date,
        measuredAt: Date,
        isSaved: Bool
    ) -> ClaudeUsageReading {
        ClaudeUsageReading(
            session: ClaudeUsageQuotaWindow(
                kind: .session,
                usedPercent: usedPercent,
                resetAt: resetAt
            ),
            weekly: nil,
            modelSpecificWeekly: [],
            plan: "Max",
            measuredAt: measuredAt,
            isSavedReading: isSaved
        )
    }

    private func snapshot(
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        usedPercent: Double = 25,
        resetAt: Date? = nil,
        updatedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: resetAt ?? updatedAt.addingTimeInterval(3_600),
                durationMinutes: 300
            ),
            source: source,
            confidence: confidence,
            updatedAt: updatedAt
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func fixtureData(_ path: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.resourceURL)
            .appendingPathComponent("Fixtures/Claude/\(path)")
        return try Data(contentsOf: url)
    }

    private func makeCoordinatorFixture() throws -> CoordinatorFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptJuice-Coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        XCTAssertEqual(chmod(root.path, 0o700), 0)
        let defaults = makeDefaults()
        return CoordinatorFixture(
            root: root,
            workspace: ClaudeProbeWorkspace(
                url: root.appendingPathComponent("ClaudeProbe/Workspace", isDirectory: true)
            ),
            defaults: defaults
        )
    }

    private func makeDefaults() -> UserDefaults {
        let name = "PromptJuice-ClaudeCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func clear(_ defaults: UserDefaults) {
        if let name = defaults.volatileDomainNames.first(where: {
            $0.hasPrefix("PromptJuice-ClaudeCoordinatorTests-")
        }) {
            defaults.removePersistentDomain(forName: name)
        }
    }
}

private struct CoordinatorFixture {
    let root: URL
    let workspace: ClaudeProbeWorkspace
    let defaults: UserDefaults

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct FixedPrerequisiteChecker: ClaudePrerequisiteChecking {
    let result: ClaudePrerequisiteCheck

    init(_ result: ClaudePrerequisiteCheck) {
        self.result = result
    }

    func check(environment _: [String: String]) -> ClaudePrerequisiteCheck {
        result
    }
}

private enum FixedClaudeRead: Sendable {
    case snapshot(ProviderSnapshot)
    case failure
}

private struct FixedClaudeReader: ClaudeLocalUsageReading {
    let result: FixedClaudeRead

    init(_ result: FixedClaudeRead) {
        self.result = result
    }

    func snapshot(now _: Date) throws -> ProviderSnapshot {
        switch result {
        case .snapshot(let snapshot):
            snapshot
        case .failure:
            throw ClaudeUsageError.localLogActiveBlockUnavailable
        }
    }
}

private final class MemoryClaudeUsageCache: ClaudeExactUsageCaching, @unchecked Sendable {
    private let lock = NSLock()
    var storedSnapshot: ProviderSnapshot?

    init(snapshot: ProviderSnapshot? = nil) {
        storedSnapshot = snapshot
    }

    func save(_ snapshot: ProviderSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        storedSnapshot = snapshot
    }

    func snapshot(now: Date, failureDetail _: String?) -> ProviderSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let storedSnapshot,
              storedSnapshot.isAvailable,
              !storedSnapshot.isExpired(at: now) else {
            return nil
        }
        return ProviderSnapshot(
            identity: storedSnapshot.identity,
            rateWindow: storedSnapshot.rateWindow,
            weeklyWindow: storedSnapshot.weeklyWindow,
            source: .claudeCache,
            confidence: .stale,
            updatedAt: storedSnapshot.updatedAt,
            weeklyUpdatedAt: storedSnapshot.weeklyUpdatedAt,
            isFreshSessionWindow: false,
            isFreshWeeklyWindow: false
        )
    }
}

private final class ScriptedClaudeUsageProbe: ClaudeUsageProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ClaudeUsageProbeOutcome]
    private let delay: TimeInterval
    private var count = 0

    init(_ outcomes: [ClaudeUsageProbeOutcome], delay: TimeInterval = 0) {
        self.outcomes = outcomes
        self.delay = delay
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func probe(
        executableURL _: URL,
        version _: ClaudeVersionGateResult,
        authentication _: ClaudeAuthentication,
        workspaceURL _: URL,
        environment _: [String: String],
        now _: Date,
        calendar _: Calendar,
        isCancelled _: @escaping @Sendable () -> Bool
    ) -> ClaudeUsageProbeOutcome {
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return outcomes.removeFirst()
    }
}
