import XCTest
@testable import PromptJuice

@MainActor
final class PromptJuiceViewModelTests: XCTestCase {
    func testFixtureAlertIsPending() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkUsageAlert())
        XCTAssertEqual(viewModel.mode, .alert)
    }

    func testSnoozeSuppressesCurrentFixtureWindow() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkUsageAlert(force: true))
        viewModel.snooze()

        XCTAssertFalse(viewModel.checkUsageAlert())
        XCTAssertEqual(viewModel.mode, .manual)
    }

    func testDismissDoesNotSuppressCurrentFixtureWindow() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkUsageAlert(force: true))
        viewModel.dismissCurrentWindow()

        XCTAssertTrue(viewModel.checkUsageAlert())
        XCTAssertEqual(viewModel.mode, .alert)
    }

    func testManualCheckClearsCurrentFixtureSnooze() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkUsageAlert(force: true))
        viewModel.snooze()
        viewModel.showManualCheck()

        XCTAssertTrue(viewModel.checkUsageAlert())
        XCTAssertEqual(viewModel.mode, .alert)
    }

    func testThresholdsAffectFixtureAlert() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        viewModel.setRemainingMinutesThreshold(30)
        viewModel.setRemainingPercentThreshold(80)

        XCTAssertFalse(viewModel.checkUsageAlert())
        XCTAssertEqual(viewModel.mode, .manual)
    }

    func testAlertCopyUsesRemainingJuice() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        viewModel.setRemainingPercentThreshold(50)
        XCTAssertTrue(viewModel.checkUsageAlert(force: true))

        XCTAssertEqual(viewModel.headline, "Codex: 69% to use")
        XCTAssertEqual(viewModel.detail, "resets in 52m")
        XCTAssertFalse(viewModel.detail.contains("demo"))
        XCTAssertFalse(viewModel.detail.contains("exact"))
        XCTAssertFalse(viewModel.detail.contains("server"))
        XCTAssertFalse(viewModel.detail.contains("logs"))

        let codex = viewModel.snapshots.first { $0.provider == .codex }!
        XCTAssertEqual(viewModel.percentText(for: codex), "69% left")
    }

    func testManualVerdictAndSubtitleReflectAggregate() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.headline, "Use prompt juice soon")
        XCTAssertTrue(viewModel.detail.contains("Claude 43%"))
        XCTAssertTrue(viewModel.detail.contains("Codex 69%"))
        XCTAssertTrue(viewModel.detail.contains("resets in"))
    }

    func testManualVerdictIsCalmWhenHealthy() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .quiet),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.aggregateSeverity, .healthy)
    }

    func testManualSubtitleNamesUnavailableClaudeAsNotSetUp() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertTrue(viewModel.detail.contains("Claude not set up"))
        XCTAssertFalse(viewModel.detail.contains("Claude n/a"))
    }

    func testEnabledProvidersDefaultToAllWhenKeyIsAbsent() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        XCTAssertTrue(fixture.store.isFirstRun)
        XCTAssertEqual(fixture.store.enabledProviders, Set(UsageProvider.allCases))
    }

    func testEnabledProvidersEmptyWriteKeepsPreviousSelection() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.store.enabledProviders = [.claude]
        fixture.store.enabledProviders = []

        XCTAssertFalse(fixture.store.isFirstRun)
        XCTAssertEqual(fixture.store.enabledProviders, [.claude])
    }

    func testHiddenClaudeIsIgnoredByAggregateAndPanelInputs() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.codex]
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUseSoonCodexHealthySnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertEqual(viewModel.enabledProviders, [.codex])
        XCTAssertEqual(viewModel.visibleSnapshots.map(\.provider), [.codex])
        XCTAssertEqual(viewModel.aggregateSeverity, .healthy)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Codex 65% · resets in 3h 0m")
        XCTAssertEqual(viewModel.menuBarRemainingPercent, 65)
    }

    func testSetProviderEnabledKeepsOneProviderEnabled() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.codex]
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.setProviderEnabled(.codex, false)

        XCTAssertEqual(viewModel.enabledProviders, [.codex])
        XCTAssertEqual(fixture.store.enabledProviders, [.codex])
    }

    func testCompleteFirstRunPersistsEnabledProviders() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.isFirstRun)

        viewModel.completeFirstRun(enabledProviders: [.claude])

        XCTAssertFalse(fixture.store.isFirstRun)
        XCTAssertEqual(viewModel.enabledProviders, [.claude])
        XCTAssertEqual(fixture.store.enabledProviders, [.claude])
    }

    func testSettingsStatusShowsCheckingForInFlightUnavailableSnapshot() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.refreshingUnavailableSnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertEqual(viewModel.settingsStatusText(for: .claude), "Checking…")
        XCTAssertEqual(viewModel.settingsStatusText(for: .codex), "Checking…")
    }

    func testSavedFixtureSourceFallsBackToLiveUsage() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.store.usageSourceMode = .fixture

        XCTAssertEqual(fixture.store.usageSourceMode, .liveCodex)
    }

    func testManualCheckReturnsBeforeBackgroundRefreshCompletes() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.healthySnapshots,
            refreshedSnapshots: Self.alertSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        let start = DispatchTime.now().uptimeNanoseconds
        viewModel.showManualCheck()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        XCTAssertLessThan(elapsed, 100)
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)

        provider.releaseRefresh()
        XCTAssertEqual(provider.callCount, 2)
    }

    func testQuietRefreshRunsBackgroundFetchWithoutModeOrMessageSideEffects() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.healthySnapshots,
            refreshedSnapshots: Self.alertSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkUsageAlert(force: true))
        viewModel.refreshUsageQuietly()

        XCTAssertEqual(viewModel.mode, .alert)
        XCTAssertNil(viewModel.actionMessage)
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)

        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(viewModel.mode, .alert)
        XCTAssertNil(viewModel.actionMessage)
    }

    func testSettingsWindowShowStartsExactlyOneQuietRefresh() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.healthySnapshots,
            refreshedSnapshots: Self.alertSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = SettingsWindowController(viewModel: viewModel)

        controller.show()
        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)
        controller.close()

        XCTAssertEqual(provider.callCount, 2)
    }

    func testFirstRunWindowShowStartsExactlyOneQuietRefresh() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.healthySnapshots,
            refreshedSnapshots: Self.alertSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = SettingsWindowController(viewModel: viewModel)

        controller.showFirstRun()
        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)
        controller.close()

        XCTAssertEqual(provider.callCount, 2)
    }

    func testLaunchAlertDecisionUsesBackgroundRefreshResult() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.healthySnapshots,
            refreshedSnapshots: Self.alertSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let expectation = expectation(description: "refresh alert decision")
        var shouldShow = false

        viewModel.refreshUsageAlertInBackground { result in
            shouldShow = result
            expectation.fulfill()
        }

        provider.releaseRefresh()
        await fulfillment(of: [expectation], timeout: 1)

        XCTAssertTrue(shouldShow)
        XCTAssertEqual(viewModel.mode, .alert)
        XCTAssertEqual(viewModel.snapshots, Self.alertSnapshots)
    }

    private func makeFixture() -> (
        suiteName: String,
        defaults: UserDefaults,
        store: PromptJuiceSettingsStore
    ) {
        let suiteName = "PromptJuiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = PromptJuiceSettingsStore(defaults: defaults)
        return (suiteName, defaults, store)
    }

    private func waitForSnapshots(
        _ expected: [ProviderSnapshot],
        in viewModel: PromptJuiceViewModel,
        timeout: TimeInterval = 1
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while viewModel.snapshots != expected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(viewModel.snapshots, expected)
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static let healthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 10,
                resetAt: fixedNow.addingTimeInterval(240 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 12,
                resetAt: fixedNow.addingTimeInterval(250 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        )
    ]

    private static let alertSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: fixedNow.addingTimeInterval(10 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 22,
                resetAt: fixedNow.addingTimeInterval(12 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        )
    ]

    private static let claudeUseSoonCodexHealthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: fixedNow.addingTimeInterval(20 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 35,
                resetAt: fixedNow.addingTimeInterval(180 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        )
    ]

    private static let refreshingUnavailableSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Refreshing usage"
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexAppServer,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Refreshing usage"
        )
    ]

    private static let claudeUnavailableCodexHealthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Claude statusline and local usage unavailable"
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: fixedNow.addingTimeInterval(180 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        )
    ]

    private struct StaticUsageProviderClient: UsageProviderClient {
        let source: SnapshotSource = .fixture
        let storedSnapshots: [ProviderSnapshot]

        init(snapshots: [ProviderSnapshot]) {
            self.storedSnapshots = snapshots
        }

        func snapshots(now _: Date) -> [ProviderSnapshot] {
            storedSnapshots
        }
    }

    private final class BlockingUsageProviderClient: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .fixture

        private let initialSnapshots: [ProviderSnapshot]
        private let refreshedSnapshots: [ProviderSnapshot]
        private let refreshStarted = DispatchSemaphore(value: 0)
        private let refreshCanFinish = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        init(
            initialSnapshots: [ProviderSnapshot],
            refreshedSnapshots: [ProviderSnapshot]
        ) {
            self.initialSnapshots = initialSnapshots
            self.refreshedSnapshots = refreshedSnapshots
        }

        var callCount: Int {
            lock.withLock {
                calls
            }
        }

        func snapshots(now _: Date) -> [ProviderSnapshot] {
            let currentCall = lock.withLock {
                calls += 1
                return calls
            }

            guard currentCall > 1 else {
                return initialSnapshots
            }

            refreshStarted.signal()
            _ = refreshCanFinish.wait(timeout: .now() + 1)
            return refreshedSnapshots
        }

        func releaseRefresh() {
            _ = refreshStarted.wait(timeout: .now() + 1)
            refreshCanFinish.signal()
        }
    }
}
