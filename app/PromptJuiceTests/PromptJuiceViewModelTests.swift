import AppKit
import Combine
import XCTest
@testable import PromptJuice

@MainActor
final class PromptJuiceViewModelTests: XCTestCase {
    func testUseSoonNotificationsArePendingForEachQualifyingProvider() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        let notices = viewModel.pendingUseSoonNotifications(now: Self.fixedNow)

        XCTAssertEqual(notices.map(\.provider), [.claude, .codex])
        XCTAssertEqual(
            notices.map(\.body),
            [
                "You have 80% left with 10m until reset",
                "You have 78% left with 12m until reset"
            ]
        )
        XCTAssertEqual(
            notices.map(\.notificationIdentifier),
            [
                "promptjuice.use-soon.\(UsageProvider.claude.rawValue).\(notices[0].windowID)",
                "promptjuice.use-soon.\(UsageProvider.codex.rawValue).\(notices[1].windowID)"
            ]
        )
    }

    func testDispatchedUseSoonNotificationLatchesCurrentWindow() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        let notices = viewModel.pendingUseSoonNotifications(now: Self.fixedNow)
        notices.forEach(viewModel.markUseSoonNoticeDispatched)

        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)

        let relaunchedViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        XCTAssertTrue(relaunchedViewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
    }

    func testUseSoonNotificationReappearsForNewWindow() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.claude]
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.alertSnapshots[0]]),
            now: { Self.fixedNow }
        )

        let oldNotice = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!
        viewModel.markUseSoonNoticeDispatched(oldNotice)

        let rotatedClaude = Self.claudeSnapshot(
            usedPercent: 20,
            resetMinutes: 45,
            updatedAt: Self.fixedNow
        )
        let rotatedViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [rotatedClaude]),
            now: { Self.fixedNow }
        )

        let newNotices = rotatedViewModel.pendingUseSoonNotifications(now: Self.fixedNow)
        XCTAssertEqual(newNotices.map(\.provider), [.claude])
        XCTAssertNotEqual(newNotices.first?.windowID, oldNotice.windowID)
    }

    func testUseSoonNotificationToggleSuppressesBannersOnly() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        viewModel.setUseSoonNotificationsEnabled(false)

        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        XCTAssertEqual(viewModel.aggregateSeverity, .useSoon)

        let relaunchedViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        XCTAssertFalse(relaunchedViewModel.useSoonNotificationsEnabled)
    }

    func testUseSoonNotificationsDefaultOffUntilEnabled() {
        let fixture = makeFixture(notificationsEnabled: nil)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertFalse(viewModel.useSoonNotificationsEnabled)
        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        XCTAssertEqual(viewModel.aggregateSeverity, .useSoon)

        viewModel.setUseSoonNotificationsEnabled(true)

        XCTAssertTrue(viewModel.useSoonNotificationsEnabled)
        XCTAssertEqual(
            viewModel.pendingUseSoonNotifications(now: Self.fixedNow).map(\.provider),
            [.claude, .codex]
        )
    }

    func testDeniedNotificationAuthorizationShowsHintOnlyWhenEnabled() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertFalse(viewModel.showsNotificationAuthorizationHint)

        viewModel.setNotificationAuthorization(.denied)

        XCTAssertTrue(viewModel.showsNotificationAuthorizationHint)

        viewModel.setUseSoonNotificationsEnabled(false)

        XCTAssertFalse(viewModel.showsNotificationAuthorizationHint)
    }

    func testNotificationPrimeOffersOnlyDuringOrangeWhenAuthUndetermined() {
        let fixture = makeFixture(notificationsEnabled: nil)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertEqual(viewModel.aggregateSeverity, .useSoon)
        // Auth starts .unknown until the async status refresh lands — suppressed.
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)

        viewModel.setNotificationAuthorization(.notDetermined)
        XCTAssertTrue(viewModel.shouldOfferUseSoonNotificationPrime)

        viewModel.setNotificationAuthorization(.denied)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)

        viewModel.setNotificationAuthorization(.authorized)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)
    }

    func testNotificationPrimeHiddenWhenNotOrange() {
        let fixture = makeFixture(notificationsEnabled: nil)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )
        viewModel.setNotificationAuthorization(.notDetermined)

        XCTAssertNotEqual(viewModel.aggregateSeverity, .useSoon)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)
    }

    func testNotificationPrimeHiddenWhenNotificationsAlreadyEnabled() {
        let fixture = makeFixture(notificationsEnabled: true)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        viewModel.setNotificationAuthorization(.notDetermined)

        XCTAssertTrue(viewModel.useSoonNotificationsEnabled)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)
    }

    func testEnablingNotificationPrimeEnablesAndLatchesForever() {
        let fixture = makeFixture(notificationsEnabled: nil)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        viewModel.setNotificationAuthorization(.notDetermined)
        XCTAssertTrue(viewModel.shouldOfferUseSoonNotificationPrime)

        viewModel.enableUseSoonNotificationsFromPrime()

        XCTAssertTrue(viewModel.useSoonNotificationsEnabled)
        XCTAssertTrue(viewModel.didOfferUseSoonNotification)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)
        XCTAssertTrue(fixture.store.didOfferUseSoonNotification)

        // Latch survives relaunch even while still orange + undetermined.
        let relaunched = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        relaunched.setNotificationAuthorization(.notDetermined)
        XCTAssertFalse(relaunched.shouldOfferUseSoonNotificationPrime)
    }

    func testDismissingNotificationPrimeLatchesWithoutEnabling() {
        let fixture = makeFixture(notificationsEnabled: nil)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        viewModel.setNotificationAuthorization(.notDetermined)
        XCTAssertTrue(viewModel.shouldOfferUseSoonNotificationPrime)

        viewModel.dismissUseSoonNotificationPrime()

        XCTAssertFalse(viewModel.useSoonNotificationsEnabled)
        XCTAssertTrue(viewModel.didOfferUseSoonNotification)
        XCTAssertFalse(viewModel.shouldOfferUseSoonNotificationPrime)

        let relaunched = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )
        relaunched.setNotificationAuthorization(.notDetermined)
        XCTAssertFalse(relaunched.shouldOfferUseSoonNotificationPrime)
    }

    func testMergedNotificationCombinesBothProvidersWithDistinctResetTimes() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        let merged = viewModel.mergedUseSoonNotification(now: Self.fixedNow)

        XCTAssertEqual(merged?.title, "Use Claude and Codex before they reset")
        XCTAssertEqual(merged?.body, "Claude 80% left in 10m · Codex 78% left in 12m")
        XCTAssertEqual(merged?.identifier.hasPrefix("promptjuice.use-soon.merged."), true)
    }

    func testMergedNotificationCollapsesSharedResetTime() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let sameTime = [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 20,
                    resetAt: Self.fixedNow.addingTimeInterval(10 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: Self.fixedNow
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 22,
                    resetAt: Self.fixedNow.addingTimeInterval(10 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: Self.fixedNow
            )
        ]
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: sameTime),
            now: { Self.fixedNow }
        )

        let merged = viewModel.mergedUseSoonNotification(now: Self.fixedNow)

        XCTAssertEqual(merged?.title, "Use Claude and Codex before they reset")
        XCTAssertEqual(merged?.body, "Claude 80% · Codex 78% left, resetting in 10m")
    }

    func testMergedNotificationForSingleProviderReusesSingleProviderCopy() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUseSoonCodexHealthySnapshots),
            now: { Self.fixedNow }
        )

        let single = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!
        let merged = viewModel.mergedUseSoonNotification(now: Self.fixedNow)

        XCTAssertEqual(merged?.title, single.title)
        XCTAssertEqual(merged?.body, single.body)
        XCTAssertEqual(merged?.identifier, single.notificationIdentifier)
        XCTAssertEqual(merged?.identifier.contains("merged"), false)
    }

    func testDispatchedMergedIdentifierIsRememberedThenForgotten() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.alertSnapshots),
            now: { Self.fixedNow }
        )

        let notices = viewModel.pendingUseSoonNotifications(now: Self.fixedNow)
        let merged = MergedUseSoonNotification(notices: notices)!
        notices.forEach(viewModel.markUseSoonNoticeDispatched)
        viewModel.rememberDispatchedUseSoonNotification(merged)

        XCTAssertEqual(viewModel.lastDispatchedUseSoonNotificationIdentifier, merged.identifier)
        // Dedup still holds: both windows latched, nothing re-pends.
        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)

        notices.forEach {
            viewModel.clearUseSoonNotificationLatch(
                for: UseSoonNotificationWithdrawal(provider: $0.provider, windowID: $0.windowID)
            )
        }
        viewModel.forgetDispatchedUseSoonNotificationIfCleared()

        XCTAssertNil(viewModel.lastDispatchedUseSoonNotificationIdentifier)
    }

    func testUnavailableFreshLowEmptyAndHealthySnapshotsDoNotCreateUseSoonNotices() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.claude]

        let cases: [[ProviderSnapshot]] = [
            [Self.claudeUnavailableCodexHealthySnapshots[0]],
            [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .unavailable,
                    source: .claudeUsageCLI,
                    confidence: .exact,
                    updatedAt: Self.fixedNow,
                    statusDetail: "Fresh window",
                    isFreshSessionWindow: true
                )
            ],
            [
                Self.claudeSnapshot(
                    usedPercent: 95,
                    resetMinutes: 240,
                    updatedAt: Self.fixedNow
                )
            ],
            [
                Self.claudeSnapshot(
                    usedPercent: 100,
                    resetMinutes: 10,
                    updatedAt: Self.fixedNow
                )
            ],
            [Self.healthySnapshots[0]]
        ]

        for snapshots in cases {
            let viewModel = PromptJuiceViewModel(
                settingsStore: fixture.store,
                providerClient: StaticUsageProviderClient(snapshots: snapshots),
                now: { Self.fixedNow }
            )
            XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        }
    }

    func testTransientUnavailableSnapshotPreservesUseSoonLatch() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.claude]

        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.alertSnapshots[0]]),
            now: { Self.fixedNow }
        )
        let notice = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!
        viewModel.markUseSoonNoticeDispatched(notice)

        let unavailableViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.genuineUnavailableSnapshots[0]]),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(unavailableViewModel.staleUseSoonNotificationWithdrawals(now: Self.fixedNow).isEmpty)
        XCTAssertEqual(fixture.store.notifiedUseSoonWindowIDs[UsageProvider.claude.rawValue], notice.windowID)

        let returnedViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.alertSnapshots[0]]),
            now: { Self.fixedNow }
        )

        XCTAssertTrue(returnedViewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
    }

    func testDisableThenReenableProviderPreservesUseSoonLatch() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUseSoonCodexHealthySnapshots),
            now: { Self.fixedNow }
        )
        let notice = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!

        viewModel.markUseSoonNoticeDispatched(notice)
        viewModel.setProviderEnabled(.claude, false)

        XCTAssertTrue(viewModel.staleUseSoonNotificationWithdrawals(now: Self.fixedNow).isEmpty)

        viewModel.setProviderEnabled(.claude, true)

        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        XCTAssertEqual(fixture.store.notifiedUseSoonWindowIDs[UsageProvider.claude.rawValue], notice.windowID)
    }

    func testStaleUseSoonNotificationWithdrawsOnlyAfterWindowEnd() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.claude]

        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.alertSnapshots[0]]),
            now: { Self.fixedNow }
        )
        let notice = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!
        viewModel.markUseSoonNoticeDispatched(notice)

        XCTAssertTrue(viewModel.staleUseSoonNotificationWithdrawals(now: Self.fixedNow).isEmpty)

        let afterOldReset = Self.fixedNow.addingTimeInterval(11 * 60)
        let rotatedClaude = Self.claudeSnapshot(
            usedPercent: 20,
            resetMinutes: 45,
            updatedAt: Self.fixedNow
        )
        let rotatedViewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [rotatedClaude]),
            now: { afterOldReset }
        )
        XCTAssertEqual(
            rotatedViewModel.staleUseSoonNotificationWithdrawals(now: afterOldReset),
            [UseSoonNotificationWithdrawal(provider: .claude, windowID: notice.windowID)]
        )

        rotatedViewModel.clearUseSoonNotificationLatch(
            for: UseSoonNotificationWithdrawal(provider: .claude, windowID: notice.windowID)
        )

        XCTAssertTrue(fixture.store.notifiedUseSoonWindowIDs.isEmpty)
        XCTAssertEqual(
            rotatedViewModel.pendingUseSoonNotifications(now: afterOldReset).map(\.provider),
            [.claude]
        )
    }

    func testFailedPermissionCannotReemitDispatchedUseSoonNotice() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.claude]

        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [Self.alertSnapshots[0]]),
            now: { Self.fixedNow }
        )
        let notice = viewModel.pendingUseSoonNotifications(now: Self.fixedNow).first!

        viewModel.markUseSoonNoticeDispatched(notice)

        XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)

        for _ in 0..<3 {
            viewModel.tick()
            XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        }
    }

    func testManualVerdictAndSubtitleUsesSoonestReset() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.headline, "Use prompt juice soon")
        XCTAssertEqual(viewModel.detail, "Claude resets in 42m")
    }

    func testManualSubtitleNamesProvidersWhenResetTextMatches() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 25,
                        resetAt: Self.fixedNow.addingTimeInterval(85 * 60),
                        durationMinutes: 300
                    ),
                    source: .fixture,
                    confidence: .exact,
                    updatedAt: Self.fixedNow
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 18,
                        resetAt: Self.fixedNow.addingTimeInterval(84 * 60 + 10),
                        durationMinutes: 300
                    ),
                    source: .fixture,
                    confidence: .exact,
                    updatedAt: Self.fixedNow
                )
            ]),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Claude and Codex reset in 1h 25m")
    }

    func testManualSubtitleUsesCodexResetWhenClaudeIsFresh() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .unavailable,
                    source: .claudeUsageCLI,
                    confidence: .exact,
                    updatedAt: Self.fixedNow.addingTimeInterval(-2 * 60 * 60),
                    statusDetail: "Fresh window",
                    isFreshSessionWindow: true
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 20,
                        resetAt: Self.fixedNow.addingTimeInterval(3 * 60 * 60),
                        durationMinutes: 300
                    ),
                    source: .fixture,
                    confidence: .exact,
                    updatedAt: Self.fixedNow
                )
            ]),
            now: { Self.fixedNow }
        )

        XCTAssertEqual(
            viewModel.detail,
            "Codex resets in 3h 0m"
        )
    }

    func testManualSubtitleUsesFreshWindowWhenAllVisibleSnapshotsAreFresh() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .unavailable,
                    source: .claudeUsageCLI,
                    confidence: .exact,
                    updatedAt: Self.fixedNow,
                    statusDetail: "Fresh window",
                    isFreshSessionWindow: true
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .unavailable,
                    source: .codexAppServer,
                    confidence: .exact,
                    updatedAt: Self.fixedNow,
                    statusDetail: "Fresh window",
                    isFreshSessionWindow: true
                )
            ]),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Fresh window")
    }

    func testManualSubtitleFollowsUseSoonProviderWhenAnotherProviderIsEmpty() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 100,
                        resetAt: Self.fixedNow.addingTimeInterval(31 * 60),
                        durationMinutes: 300
                    ),
                    source: .claudeUsageCLI,
                    confidence: .exact,
                    updatedAt: Self.fixedNow
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 42,
                        resetAt: Self.fixedNow.addingTimeInterval(38 * 60),
                        durationMinutes: 300
                    ),
                    source: .codexAppServer,
                    confidence: .exact,
                    updatedAt: Self.fixedNow
                )
            ]),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.headline, "Use Codex before it resets")
        XCTAssertEqual(viewModel.detail, "Codex resets in 38m")
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

    func testManualVerdictShowsCheckingWhileVisibleProvidersRefresh() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.refreshingUnavailableSnapshots,
            refreshedSnapshots: Self.genuineUnavailableSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.isCheckingUsage)
        XCTAssertEqual(viewModel.headline, "Checking usage…")
        XCTAssertEqual(viewModel.detail, "Just a moment…")

        viewModel.showManualCheck()
        provider.releaseRefresh()
        await waitForSnapshots(Self.genuineUnavailableSnapshots, in: viewModel)

        XCTAssertFalse(viewModel.isCheckingUsage)
        XCTAssertEqual(viewModel.headline, "Not measured yet")
        XCTAssertEqual(viewModel.detail, "Usage unavailable")
    }

    func testManualSubtitleUsesAvailableResetWhenClaudeIsUnavailable() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Codex resets in 3h 0m")
    }

    func testManualSubtitleUsesAvailableResetWhenCodexIsUnavailable() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeHealthyCodexUnavailableSnapshots),
            now: { Self.fixedNow }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Claude resets in 3h 0m")
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
        XCTAssertEqual(viewModel.detail, "Codex resets in 3h 0m")
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

    func testRefreshUsageRunsBackgroundFetchAndShowsMessages() async {
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

        viewModel.refreshUsage()

        XCTAssertEqual(viewModel.actionMessage, "Refreshing usage.")
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)

        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(viewModel.actionMessage, "Usage refreshed.")
    }

    func testDebouncedClaudeRefreshShowsUpToDateMessage() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let coordinator = StaticClaudeUsageCoordinator(
            state: ClaudeUsageCoordinatorState(
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: Self.healthySnapshots[0],
                scheduleDecision: .skipDebounce
            )
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveCodexProviderClient: StaticUsageProviderClient(
                snapshots: [Self.healthySnapshots[1]]
            ),
            claudeUsageCoordinator: coordinator,
            initialSnapshots: Self.healthySnapshots,
            initialClaudeAccessState: .subscription(plan: "Max"),
            now: { Self.fixedNow }
        )

        viewModel.refreshUsage()

        XCTAssertEqual(viewModel.actionMessage, "Refreshing usage.")
        await waitUntil { viewModel.actionMessage == "Just checked · up to date" }
    }

    func testQuietRefreshRunsBackgroundFetchWithoutMessageSideEffects() async {
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

        viewModel.refreshUsageQuietly()

        XCTAssertNil(viewModel.actionMessage)
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)

        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertNil(viewModel.actionMessage)
    }

    func testTickExpiresVisibleWindowsAndRefreshesUsage() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.expiredSnapshots,
            refreshedSnapshots: Self.healthySnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        viewModel.tick()

        XCTAssertTrue(viewModel.isCheckingUsage)
        XCTAssertTrue(viewModel.snapshots.allSatisfy { !$0.isAvailable })
        XCTAssertTrue(viewModel.snapshots.allSatisfy { $0.statusDetail == "Refreshing usage" })

        provider.releaseRefresh()
        await waitForSnapshots(Self.healthySnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 2)
    }

    func testTickChecksClaudeCoordinatorEveryMinuteAndRespectsOfflineState() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let clock = MutableTestClock(Self.fixedNow)
        let coordinator = RecordingClaudeUsageCoordinator(
            state: ClaudeUsageCoordinatorState(
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: Self.healthySnapshots[0],
                scheduleDecision: .skipFresh
            )
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveCodexProviderClient: StaticUsageProviderClient(
                snapshots: [Self.healthySnapshots[1]]
            ),
            claudeUsageCoordinator: coordinator,
            initialSnapshots: Self.healthySnapshots,
            initialClaudeAccessState: .subscription(plan: "Max"),
            claudeTimerCheckInterval: 60,
            now: clock.now
        )

        viewModel.tick()
        await waitUntil { coordinator.callCount == 1 }
        XCTAssertEqual(coordinator.lastReason, .timer)
        XCTAssertEqual(coordinator.lastIsOnline, true)

        viewModel.tick()
        clock.advance(by: 59)
        viewModel.tick()
        XCTAssertEqual(coordinator.callCount, 1)

        clock.advance(by: 1)
        viewModel.tick()
        await waitUntil { coordinator.callCount == 2 }

        viewModel.setNetworkOnline(false)
        clock.advance(by: 60)
        viewModel.tick()
        XCTAssertEqual(coordinator.callCount, 2)
    }

    func testTickReplacesExpiredClaudeWindowWithLocalEstimate() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let expiredClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 0,
                resetAt: Self.fixedNow.addingTimeInterval(-60),
                durationMinutes: 300
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: Self.fixedNow.addingTimeInterval(-3600)
        )
        let provider = BlockingUsageProviderClient(
            initialSnapshots: [
                expiredClaude,
                Self.healthySnapshots[1]
            ],
            refreshedSnapshots: Self.claudeEstimatedCodexHealthySnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        viewModel.tick()

        let claudeWhileRefreshing = viewModel.snapshots.first { $0.provider == .claude }
        XCTAssertEqual(claudeWhileRefreshing?.confidence, .unavailable)
        XCTAssertEqual(claudeWhileRefreshing?.statusDetail, "Refreshing usage")

        provider.releaseRefresh()
        await waitForSnapshots(Self.claudeEstimatedCodexHealthySnapshots, in: viewModel)

        let refreshedClaude = viewModel.snapshots.first { $0.provider == .claude }
        XCTAssertEqual(refreshedClaude?.source, .claudeLocalLogs)
        XCTAssertEqual(refreshedClaude?.confidence, .estimated)
        XCTAssertEqual(provider.callCount, 2)
    }

    func testTickDoesNotPublishSnapshotsWhenNothingAges() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )
        var publishCount = 0
        let cancellable = viewModel.$snapshots
            .dropFirst()
            .sink { _ in
                publishCount += 1
            }

        viewModel.tick()

        XCTAssertEqual(publishCount, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testRefreshStormCoalescesIntoOneActiveAndOnePendingFetch() async {
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

        for _ in 0..<20 {
            viewModel.refreshUsageQuietly()
        }

        await waitUntil { provider.callCount == 2 }
        provider.releaseRefresh()
        await waitUntil { provider.callCount == 3 }
        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 3)
    }

    func testLiveCodexRefreshMergesWhileClaudeIsStillReading() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claudeUnavailable = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: Self.fixedNow,
            statusDetail: "Claude usage unavailable"
        )
        let slowClaudeProvider = BlockingSingleProviderClient(snapshots: [claudeUnavailable])
        let codexSnapshot = Self.healthySnapshots[1]
        let codexProvider = CountingUsageProviderClient(snapshots: [codexSnapshot])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveClaudeProviderClient: slowClaudeProvider,
            liveCodexProviderClient: codexProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshUsageQuietly()

        await waitUntil { viewModel.snapshots.contains(codexSnapshot) }
        XCTAssertEqual(codexProvider.callCount, 1)
        XCTAssertEqual(slowClaudeProvider.callCount, 1)

        slowClaudeProvider.releaseRefresh()
        await waitUntil {
            viewModel.snapshots.contains { snapshot in
                snapshot.provider == .claude
                    && snapshot.statusDetail != "Refreshing usage"
            }
        }
    }

    func testLiveCodexRefreshMergesBeforeClaudeCoordinatorAndPublishesCoordinatorState() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let claudeSnapshot = Self.alertSnapshots[0]
        let nextAttemptAt = Self.fixedNow.addingTimeInterval(30)
        let coordinator = BlockingClaudeUsageCoordinator(
            state: ClaudeUsageCoordinatorState(
                access: .subscription(plan: "Max"),
                refresh: .backingOff(nextAttemptAt: nextAttemptAt),
                snapshot: claudeSnapshot
            )
        )
        let codexSnapshot = Self.healthySnapshots[1]
        let codexProvider = CountingUsageProviderClient(snapshots: [codexSnapshot])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveCodexProviderClient: codexProvider,
            claudeUsageCoordinator: coordinator,
            now: { Self.fixedNow }
        )

        viewModel.refreshUsageQuietly(reason: .manual)

        await waitUntil { viewModel.snapshots.contains(codexSnapshot) }
        XCTAssertEqual(coordinator.callCount, 1)
        XCTAssertEqual(coordinator.lastForce, false)
        XCTAssertEqual(viewModel.claudeAccessState, .checking)

        coordinator.releaseRefresh()
        await waitUntil { viewModel.claudeAccessState == .subscription(plan: "Max") }

        XCTAssertTrue(viewModel.snapshots.contains(claudeSnapshot))
        XCTAssertEqual(viewModel.claudeRefreshState, .backingOff(nextAttemptAt: nextAttemptAt))
    }

    func testNeutralClaudeAuthenticationCategoriesStayOutsideAggregateAndNotifications() async {
        let neutralStates: [ClaudeAccessState] = [
            .apiBilling,
            .externalProvider(.bedrock),
            .unsupportedAuth,
        ]

        for neutralState in neutralStates {
            let fixture = makeFixture()
            defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
            let coordinator = StaticClaudeUsageCoordinator(
                state: ClaudeUsageCoordinatorState(
                    access: neutralState,
                    refresh: .idle,
                    snapshot: Self.alertSnapshots[0]
                )
            )
            let codexSnapshot = Self.healthySnapshots[1]
            let viewModel = PromptJuiceViewModel(
                settingsStore: fixture.store,
                liveCodexProviderClient: StaticUsageProviderClient(snapshots: [codexSnapshot]),
                claudeUsageCoordinator: coordinator,
                now: { Self.fixedNow }
            )

            viewModel.refreshUsageQuietly(reason: .manual)
            await waitUntil { viewModel.claudeAccessState == neutralState }

            XCTAssertTrue(viewModel.visibleSnapshots.contains { $0.provider == .claude })
            XCTAssertEqual(viewModel.aggregateSeverity, .healthy)
            XCTAssertEqual(viewModel.menuBarSeverity, .healthy)
            XCTAssertEqual(viewModel.menuBarRemainingPercent, codexSnapshot.remainingPercent)
            XCTAssertTrue(viewModel.pendingUseSoonNotifications(now: Self.fixedNow).isEmpty)
        }
    }

    func testRefreshReplacesExpiredSnapshotWithOlderSourceTimestamp() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let refreshedSnapshots = Self.healthySnapshots.map { snapshot in
            ProviderSnapshot(
                identity: snapshot.identity,
                rateWindow: snapshot.rateWindow,
                source: snapshot.source,
                confidence: snapshot.confidence,
                updatedAt: Self.fixedNow.addingTimeInterval(-60),
                statusDetail: snapshot.statusDetail
            )
        }
        let provider = BlockingUsageProviderClient(
            initialSnapshots: Self.expiredSnapshots,
            refreshedSnapshots: refreshedSnapshots
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )

        viewModel.refreshUsageQuietly()
        provider.releaseRefresh()

        await waitForSnapshots(refreshedSnapshots, in: viewModel)
        XCTAssertEqual(provider.callCount, 2)
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
        XCTAssertGreaterThan(
            controller.window?.level.rawValue ?? 0,
            NSWindow.Level.floating.rawValue
        )
        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)
        controller.close()

        XCTAssertEqual(provider.callCount, 2)
    }

    func testSettingsWindowPreservesRequestedClaudeJourneyWhileRefreshRuns() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let coordinator = BlockingClaudeUsageCoordinator(
            state: ClaudeUsageCoordinatorState(
                access: .cliMissing,
                refresh: .idle,
                snapshot: Self.healthySnapshots[0]
            )
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveCodexProviderClient: StaticUsageProviderClient(
                snapshots: [Self.healthySnapshots[1]]
            ),
            claudeUsageCoordinator: coordinator,
            initialSnapshots: Self.healthySnapshots,
            initialClaudeAccessState: .cliMissing,
            now: { Self.fixedNow }
        )
        let controller = SettingsWindowController(viewModel: viewModel)

        controller.show(claudeJourney: .install)

        XCTAssertEqual(controller.claudeGuidanceJourneyForTesting, .install)
        XCTAssertEqual(viewModel.claudeRefreshState, .refreshing)

        coordinator.releaseRefresh()
        await waitUntil { viewModel.claudeRefreshState == .idle }
        XCTAssertEqual(controller.claudeGuidanceJourneyForTesting, .install)
        controller.close()
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

    func testFirstRunFinishPersistsClosesAndInvokesCompletion() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .quiet),
            now: { Self.fixedNow }
        )
        let completion = expectation(description: "first run completion")
        let controller = SettingsWindowController(viewModel: viewModel) {
            completion.fulfill()
        }

        controller.showFirstRun()
        XCTAssertTrue(controller.window?.isVisible == true)

        controller.finishFirstRun()
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertFalse(fixture.store.isFirstRun)
        XCTAssertFalse(controller.window?.isVisible == true)
        controller.close()
    }

    func testUseSoonNoticeDecisionUsesBackgroundRefreshResult() async {
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

        viewModel.refreshUsageQuietly()

        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(
            viewModel.pendingUseSoonNotifications(now: Self.fixedNow).map(\.provider),
            [.claude, .codex]
        )
    }

    // MARK: - Dormant row selection

    func testDormantSelectionDoesNotChangeVisibleHeader() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")

        viewModel.toggleSelection(.claude)

        XCTAssertEqual(viewModel.selectedProvider, .claude)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
        XCTAssertEqual(viewModel.headerRemainingPercent, 88)
        XCTAssertEqual(viewModel.headerSeverity, .healthy)
    }

    func testWeeklyWindowsStayDormantInVisibleHeader() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.weeklySnapshots),
            now: { Self.fixedNow }
        )
        let claude = viewModel.visibleSnapshots.first { $0.provider == .claude }!

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
        XCTAssertEqual(viewModel.sessionRemainingPercentDisplayValueText(for: claude), "80%")
        XCTAssertEqual(viewModel.remainingPercentDisplayValueText(for: claude), "80%")
        XCTAssertEqual(claude.effectiveRemainingPercent, 65)

        viewModel.toggleSelection(.claude)

        XCTAssertEqual(viewModel.selectedProvider, .claude)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
        XCTAssertEqual(viewModel.headerRemainingPercent, 80)
        XCTAssertEqual(
            viewModel.weeklyText(for: claude),
            "Week: 65% left · resets in 3d 4h"
        )

        viewModel.toggleSelection(.codex)

        XCTAssertEqual(viewModel.selectedProvider, .codex)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
        XCTAssertEqual(viewModel.headerRemainingPercent, 80)
        XCTAssertEqual(
            viewModel.weeklyText(for: viewModel.visibleSnapshots.first { $0.provider == .codex }!),
            "Week: 70% left · resets in 4d"
        )

        viewModel.toggleSelection(.codex)

        XCTAssertNil(viewModel.selectedProvider)
    }

    func testSelectedProviderWithoutWeeklyKeepsVisibleOverview() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.toggleSelection(.claude)

        XCTAssertEqual(viewModel.selectedProvider, .claude)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
    }

    func testSelectingCodexKeepsVisibleOverview() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.toggleSelection(.codex)

        XCTAssertEqual(viewModel.selectedProvider, .codex)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
        XCTAssertEqual(viewModel.headerRemainingPercent, 88)
    }

    func testTogglingSelectedProviderReturnsToOverview() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.toggleSelection(.claude)
        viewModel.toggleSelection(.claude)

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
    }

    func testUnavailableProviderCannotBeSelected() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow }
        )

        let headlineBefore = viewModel.headline
        viewModel.toggleSelection(.claude)

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.headline, headlineBefore)
    }

    func testDismissClearsSelection() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.weeklySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.toggleSelection(.codex)
        XCTAssertEqual(viewModel.selectedProvider, .codex)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")

        viewModel.dismissCurrentWindow()

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
    }

    func testClearSelectionReturnsToOverview() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )

        viewModel.toggleSelection(.claude)
        XCTAssertEqual(viewModel.selectedProvider, .claude)

        viewModel.clearSelection()

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertEqual(viewModel.headline, "Plenty of prompt juice left")
        XCTAssertEqual(viewModel.detail, "Claude resets in 4h 0m")
    }

        private func makeFixture(notificationsEnabled: Bool? = true) -> (
        suiteName: String,
        defaults: UserDefaults,
        store: PromptJuiceSettingsStore
    ) {
        let suiteName = "PromptJuiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = PromptJuiceSettingsStore(defaults: defaults)

        if let notificationsEnabled {
            store.useSoonNotificationsEnabled = notificationsEnabled
        }

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

    private func waitUntil(
        _ condition: @MainActor @escaping () -> Bool,
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private static let staleClaudeUpdatedAt = fixedNow.addingTimeInterval(-10 * 60)

    private static func claudeSnapshot(
        usedPercent: Double,
        resetMinutes: Int,
        updatedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: fixedNow.addingTimeInterval(TimeInterval(resetMinutes * 60)),
                durationMinutes: 300
            ),
            source: .claudeUsageCLI,
            confidence: .exact,
            updatedAt: updatedAt
        )
    }

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

    private static let weeklySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: fixedNow.addingTimeInterval(240 * 60),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 35,
                resetAt: fixedNow.addingTimeInterval((3 * 24 + 4) * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow,
            weeklyUpdatedAt: fixedNow
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 12,
                resetAt: fixedNow.addingTimeInterval(250 * 60),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 30,
                resetAt: fixedNow.addingTimeInterval(4 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow,
            weeklyUpdatedAt: fixedNow
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

    private static let expiredSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 0,
                resetAt: fixedNow.addingTimeInterval(-60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow.addingTimeInterval(-3600)
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 9,
                resetAt: fixedNow.addingTimeInterval(-30),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow.addingTimeInterval(-3600)
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

    private static let claudeEstimatedCodexHealthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 58,
                resetAt: fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: fixedNow
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

    private static let claudeStaleCodexHealthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 58,
                resetAt: fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: .claudeCache,
            confidence: .stale,
            updatedAt: staleClaudeUpdatedAt
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

    private static let refreshingUnavailableSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
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

    private static let genuineUnavailableSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Claude usage unavailable"
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexAppServer,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Codex app-server unavailable"
        )
    ]

    private static let claudeUnavailableCodexHealthySnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Claude usage unavailable"
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

    private static let claudeHealthyCodexUnavailableSnapshots = [
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 20,
                resetAt: fixedNow.addingTimeInterval(180 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexAppServer,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Codex app-server unavailable"
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

    private final class CountingUsageProviderClient: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .fixture

        private let storedSnapshots: [ProviderSnapshot]
        private let lock = NSLock()
        private var calls = 0

        init(snapshots: [ProviderSnapshot]) {
            self.storedSnapshots = snapshots
        }

        var callCount: Int {
            lock.withLock {
                calls
            }
        }

        func snapshots(now _: Date) -> [ProviderSnapshot] {
            lock.withLock {
                calls += 1
            }

            return storedSnapshots
        }
    }

    private final class BlockingSingleProviderClient: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .fixture

        private let storedSnapshots: [ProviderSnapshot]
        private let refreshStarted = DispatchSemaphore(value: 0)
        private let refreshCanFinish = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        init(snapshots: [ProviderSnapshot]) {
            self.storedSnapshots = snapshots
        }

        var callCount: Int {
            lock.withLock {
                calls
            }
        }

        func snapshots(now _: Date) -> [ProviderSnapshot] {
            lock.withLock {
                calls += 1
            }

            refreshStarted.signal()
            _ = refreshCanFinish.wait(timeout: .now() + 1)
            return storedSnapshots
        }

        func releaseRefresh() {
            _ = refreshStarted.wait(timeout: .now() + 1)
            refreshCanFinish.signal()
        }
    }

    private final class MutableTestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date

        init(_ date: Date) {
            self.date = date
        }

        func now() -> Date {
            lock.withLock { date }
        }

        func advance(by interval: TimeInterval) {
            lock.withLock {
                date = date.addingTimeInterval(interval)
            }
        }
    }

    private final class RecordingClaudeUsageCoordinator: ClaudeUsageSnapshotProviding, @unchecked Sendable {
        private let state: ClaudeUsageCoordinatorState
        private let lock = NSLock()
        private var calls = 0
        private var recordedReason: ClaudeRefreshReason?
        private var recordedIsOnline: Bool?

        init(state: ClaudeUsageCoordinatorState) {
            self.state = state
        }

        var callCount: Int {
            lock.withLock { calls }
        }

        var lastReason: ClaudeRefreshReason? {
            lock.withLock { recordedReason }
        }

        var lastIsOnline: Bool? {
            lock.withLock { recordedIsOnline }
        }

        func snapshot(
            now _: Date,
            reason: ClaudeRefreshReason,
            force _: Bool,
            providerEnabled _: Bool,
            isOnline: Bool
        ) async -> ClaudeUsageCoordinatorState {
            lock.withLock {
                calls += 1
                recordedReason = reason
                recordedIsOnline = isOnline
            }
            return state
        }
    }

    private struct StaticClaudeUsageCoordinator: ClaudeUsageSnapshotProviding {
        let state: ClaudeUsageCoordinatorState

        func snapshot(
            now _: Date,
            reason _: ClaudeRefreshReason,
            force _: Bool,
            providerEnabled _: Bool,
            isOnline _: Bool
        ) async -> ClaudeUsageCoordinatorState {
            state
        }
    }

    private final class BlockingClaudeUsageCoordinator: ClaudeUsageSnapshotProviding, @unchecked Sendable {
        private let state: ClaudeUsageCoordinatorState
        private let lock = NSLock()
        private var calls = 0
        private var recordedForce: Bool?
        private var refreshContinuation: CheckedContinuation<Void, Never>?
        private var refreshReleased = false

        init(state: ClaudeUsageCoordinatorState) {
            self.state = state
        }

        var callCount: Int {
            lock.withLock {
                calls
            }
        }

        var lastForce: Bool? {
            lock.withLock {
                recordedForce
            }
        }

        func snapshot(
            now _: Date,
            reason _: ClaudeRefreshReason,
            force: Bool,
            providerEnabled _: Bool,
            isOnline _: Bool
        ) async -> ClaudeUsageCoordinatorState {
            lock.withLock {
                calls += 1
                recordedForce = force
            }
            await withCheckedContinuation { continuation in
                let shouldResume = lock.withLock {
                    if refreshReleased {
                        return true
                    }
                    refreshContinuation = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
            return state
        }

        func releaseRefresh() {
            let continuation = lock.withLock {
                refreshReleased = true
                let continuation = refreshContinuation
                refreshContinuation = nil
                return continuation
            }
            continuation?.resume()
        }
    }

    private final class SlowFirstThenFreshClaudeProvider: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .claudeUsageCLI

        private let firstSnapshot: ProviderSnapshot
        private let freshSnapshot: ProviderSnapshot
        private let firstRefreshStarted = DispatchSemaphore(value: 0)
        private let firstRefreshCanFinish = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        init(firstSnapshot: ProviderSnapshot, freshSnapshot: ProviderSnapshot) {
            self.firstSnapshot = firstSnapshot
            self.freshSnapshot = freshSnapshot
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

            if currentCall == 1 {
                firstRefreshStarted.signal()
                _ = firstRefreshCanFinish.wait(timeout: .now() + 1)
                return [firstSnapshot]
            }

            return [freshSnapshot]
        }

        func releaseFirstRefresh() {
            _ = firstRefreshStarted.wait(timeout: .now() + 1)
            firstRefreshCanFinish.signal()
        }
    }

    private final class TimeoutThenFreshClaudeProvider: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .claudeUsageCLI

        private let freshSnapshot: ProviderSnapshot
        private let firstRefreshStarted = DispatchSemaphore(value: 0)
        private let firstRefreshCanFinish = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0

        init(freshSnapshot: ProviderSnapshot) {
            self.freshSnapshot = freshSnapshot
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

            if currentCall == 1 {
                firstRefreshStarted.signal()
                _ = firstRefreshCanFinish.wait(timeout: .now() + 1)
                return []
            }

            return [freshSnapshot]
        }

        func releaseFirstRefresh() {
            _ = firstRefreshStarted.wait(timeout: .now() + 1)
            firstRefreshCanFinish.signal()
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
