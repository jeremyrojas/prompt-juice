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

    func testNotificationPrimeOffersOnlyDuringAmberWhenAuthUndetermined() {
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

    func testNotificationPrimeHiddenWhenNotAmber() {
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

        // Latch survives relaunch even while still amber + undetermined.
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
                    source: .claudeStatusline,
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
                now: { Self.fixedNow },
                isClaudeBridgeCurrent: { false }
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
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
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
                    source: .claudeStatusline,
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
                    source: .claudeStatusline,
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
                    source: .claudeStatusline,
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
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Codex resets in 3h 0m")
    }

    func testManualSubtitleUsesAvailableResetWhenClaudeAwaitsTerminal() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
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

    func testClaudeLiveUpgradeIsLiveForExactSnapshot() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .live)
        XCTAssertNil(viewModel.claudeSetupButtonTitle)
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "Right now it's exact, current as of your last terminal session."
        )
    }

    func testClaudeLiveUpgradeOffersSetupWhenBridgeIsMissing() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeEstimatedCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )

        let claude = viewModel.snapshots.first { $0.provider == .claude }!

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .setupAvailable)
        XCTAssertEqual(viewModel.settingsStatusText(for: .claude), "Estimate")
        XCTAssertEqual(viewModel.claudeSetupButtonTitle, "Set up live readings")
        XCTAssertEqual(
            viewModel.sourceTooltip(for: claude),
            "Estimated from local Claude Code activity · open Settings to set up live"
        )
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "Right now it's estimating. Set up live readings, then use Claude Code in the terminal for exact numbers."
        )
    }

    func testClaudeLiveUpgradeAwaitsTerminalSessionWhenBridgeIsCurrent() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeEstimatedCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )

        let claude = viewModel.snapshots.first { $0.provider == .claude }!

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .awaitingSession)
        XCTAssertEqual(viewModel.settingsStatusText(for: .claude), "Estimate")
        XCTAssertNil(viewModel.claudeSetupButtonTitle)
        XCTAssertEqual(
            viewModel.sourceTooltip(for: claude),
            "Estimated from local Claude Code activity"
        )
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "Showing a local Claude Code estimate. Exact usage replaces it when Claude Code sends a current rate-limit window."
        )
    }

    func testClaudeAwaitingSessionWithNoUsageShowsTerminalGuidance() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )

        let claude = viewModel.snapshots.first { $0.provider == .claude }!

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .awaitingSession)
        XCTAssertEqual(viewModel.settingsStatusText(for: .claude), "Waiting for Claude statusline")
        XCTAssertNil(viewModel.claudeSetupButtonTitle)
        XCTAssertEqual(
            viewModel.sourceTooltip(for: claude),
            "You're set up · waiting for Claude Code usage"
        )
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "You're set up. PromptJuice is waiting for Claude Code's next statusline window."
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.detail, "Codex resets in 3h 0m")
    }

    func testClaudeStalePopoverNamesLastExactReading() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeStaleCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )

        let claude = viewModel.snapshots.first { $0.provider == .claude }!
        let time = clockTime(Self.staleClaudeUpdatedAt)

        XCTAssertEqual(
            viewModel.sourceTooltip(for: claude),
            "Read from Claude Code as of \(time) · send any message in Claude Code to refresh"
        )
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "Right now it's showing your last exact reading from \(time). Claude Code will replace it when the statusline sends a current window."
        )
    }

    func testSourceTooltipCallsOutEmptyProviderWithReadingTime() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow }
        )
        let updatedAt = Self.fixedNow.addingTimeInterval(-75)
        let emptyClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 100,
                resetAt: Self.fixedNow.addingTimeInterval(31 * 60),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: updatedAt
        )
        let emptyCodex = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 100,
                resetAt: Self.fixedNow.addingTimeInterval(38 * 60),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: updatedAt
        )
        let time = clockTime(updatedAt)

        XCTAssertEqual(
            viewModel.sourceTooltip(for: emptyClaude),
            "Claude is out until reset · read from Claude Code as of \(time)"
        )
        XCTAssertEqual(
            viewModel.sourceTooltip(for: emptyCodex),
            "Codex is out until reset · read from Codex app-server as of \(time)"
        )
    }

    func testStaleClaudeIndicatorAppearsOnlyAfterTenMinutes() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )
        let staleUpdatedAt = Self.fixedNow.addingTimeInterval(-11 * 60)
        let staleClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 32,
                resetAt: Self.fixedNow.addingTimeInterval(78 * 60),
                durationMinutes: 300
            ),
            source: .claudeCache,
            confidence: .stale,
            updatedAt: staleUpdatedAt
        )
        let time = clockTime(staleUpdatedAt)

        XCTAssertTrue(viewModel.showsStaleReadingIndicator(for: staleClaude))
        XCTAssertEqual(
            viewModel.staleReadingIndicatorAccessibilityLabel(for: staleClaude),
            "Reading from \(time)"
        )
        XCTAssertEqual(
            viewModel.sourceTooltip(for: staleClaude),
            "Read from Claude Code as of \(time) · send any message in Claude Code to refresh"
        )
        XCTAssertEqual(viewModel.sessionRemainingPercentDisplayValueText(for: staleClaude), "68%")
        XCTAssertEqual(viewModel.fullResetText(for: staleClaude), "resets in 1h 18m")
    }

    func testStaleClaudeIndicatorStaysHiddenForNonqualifyingRows() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )
        let oldUpdate = Self.fixedNow.addingTimeInterval(-11 * 60)
        let exactlyTenMinutesOld = Self.fixedNow.addingTimeInterval(-10 * 60)
        let baseRateWindow = RateWindow.available(
            usedPercent: 32,
            resetAt: Self.fixedNow.addingTimeInterval(78 * 60),
            durationMinutes: 300
        )
        let cases = [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: baseRateWindow,
                source: .claudeStatusline,
                confidence: .exact,
                updatedAt: oldUpdate
            ),
            ProviderSnapshot(
                identity: .claude,
                rateWindow: baseRateWindow,
                source: .claudeLocalLogs,
                confidence: .estimated,
                updatedAt: oldUpdate
            ),
            ProviderSnapshot(
                identity: .claude,
                rateWindow: baseRateWindow,
                source: .claudeCache,
                confidence: .stale,
                updatedAt: exactlyTenMinutesOld
            ),
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeStatusline,
                confidence: .stale,
                updatedAt: oldUpdate,
                statusDetail: "Fresh window",
                isFreshSessionWindow: true
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: baseRateWindow,
                source: .codexCache,
                confidence: .stale,
                updatedAt: oldUpdate
            )
        ]

        for snapshot in cases {
            XCTAssertFalse(viewModel.showsStaleReadingIndicator(for: snapshot), snapshot.displayName)
            XCTAssertNil(viewModel.staleReadingIndicatorAccessibilityLabel(for: snapshot), snapshot.displayName)
        }
    }

    func testClaudeUnavailableSetupUsesShortButtonLabel() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .setupAvailable)
        XCTAssertEqual(viewModel.claudeSetupButtonTitle, "Set Up…")
        XCTAssertEqual(
            viewModel.claudeMeasurementPopoverDetail,
            "It's not set up yet. Set it up, then use Claude Code in the terminal for exact numbers."
        )
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

        XCTAssertEqual(viewModel.actionMessage, "Refreshing live usage.")
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)

        provider.releaseRefresh()
        await waitForSnapshots(Self.alertSnapshots, in: viewModel)

        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(viewModel.actionMessage, "Live Usage refreshed.")
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
            source: .claudeStatusline,
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

    func testTickAgesExactClaudeStatuslineSnapshotToEarlier() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let oldClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 29,
                resetAt: Self.fixedNow.addingTimeInterval(3 * 60 * 60),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 3,
                resetAt: Self.fixedNow.addingTimeInterval(5 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: Self.fixedNow.addingTimeInterval(-ClaudeStatuslineSnapshotReader.maximumCacheAge - 1),
            weeklyUpdatedAt: Self.fixedNow.addingTimeInterval(-ClaudeStatuslineSnapshotReader.maximumCacheAge - 1)
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [oldClaude, Self.healthySnapshots[1]]),
            now: { Self.fixedNow }
        )

        viewModel.tick()

        let claude = viewModel.snapshots.first { $0.provider == .claude }
        XCTAssertEqual(claude?.confidence, .stale)
        XCTAssertEqual(claude?.weeklyWindow?.usedPercent, 3)
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

    func testFreshClaudeRefreshDoesNotReplaceValidExistingSnapshot() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let validClaude = Self.claudeSnapshot(
            usedPercent: 55,
            resetMinutes: 180,
            updatedAt: Self.fixedNow
        )
        let freshClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeCache,
            confidence: .stale,
            updatedAt: Self.fixedNow.addingTimeInterval(60),
            statusDetail: "Fresh window",
            isFreshSessionWindow: true
        )
        let claudeProvider = CountingUsageProviderClient(snapshots: [freshClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: [validClaude, Self.healthySnapshots[1]]),
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        await waitUntil { claudeProvider.callCount == 1 }
        let claude = viewModel.snapshots.first { $0.provider == .claude }
        XCTAssertEqual(claude, validClaude)
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
            source: .claudeStatusline,
            confidence: .unavailable,
            updatedAt: Self.fixedNow,
            statusDetail: "Claude statusline cache unavailable"
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

    func testClaudeStatusCacheRefreshMergesOnlyClaudeSnapshot() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let aggregateProvider = CountingUsageProviderClient(snapshots: Self.healthySnapshots)
        let refreshedClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 28,
                resetAt: Self.fixedNow.addingTimeInterval(210 * 60),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: Self.fixedNow.addingTimeInterval(1)
        )
        let claudeProvider = CountingUsageProviderClient(snapshots: [refreshedClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: aggregateProvider,
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        await waitForSnapshots([refreshedClaude, Self.healthySnapshots[1]], in: viewModel)

        XCTAssertEqual(aggregateProvider.callCount, 1)
        XCTAssertEqual(claudeProvider.callCount, 1)
    }

    func testClaudeStatusCacheRefreshLetsExactSnapshotReplaceNewerEstimate() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let estimatedClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 58,
                resetAt: Self.fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: Self.fixedNow.addingTimeInterval(60)
        )
        let exactClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 12,
                resetAt: Self.fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: Self.fixedNow
        )
        let aggregateProvider = CountingUsageProviderClient(snapshots: [
            estimatedClaude,
            Self.healthySnapshots[1]
        ])
        let claudeProvider = CountingUsageProviderClient(snapshots: [exactClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: aggregateProvider,
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        await waitForSnapshots([exactClaude, Self.healthySnapshots[1]], in: viewModel)
        XCTAssertEqual(claudeProvider.callCount, 1)
    }

    func testClaudeStatusCacheRefreshReplacesAgedExactSnapshotWithNewerStaleReading() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let oldExactClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 51,
                resetAt: Self.fixedNow.addingTimeInterval(31 * 60),
                durationMinutes: 300
            ),
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: Self.fixedNow.addingTimeInterval(-ClaudeStatuslineSnapshotReader.maximumCacheAge - 30)
        )
        let newerStaleClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 103,
                resetAt: Self.fixedNow.addingTimeInterval(31 * 60),
                durationMinutes: 300
            ),
            source: .claudeCache,
            confidence: .stale,
            updatedAt: Self.fixedNow.addingTimeInterval(-ClaudeStatuslineSnapshotReader.maximumCacheAge - 1)
        )
        let aggregateProvider = CountingUsageProviderClient(snapshots: [
            oldExactClaude,
            Self.healthySnapshots[1]
        ])
        let claudeProvider = CountingUsageProviderClient(snapshots: [newerStaleClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: aggregateProvider,
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        await waitForSnapshots([newerStaleClaude, Self.healthySnapshots[1]], in: viewModel)
        XCTAssertEqual(viewModel.sessionRemainingPercentDisplayValueText(for: newerStaleClaude), "0%")
        XCTAssertEqual(claudeProvider.callCount, 1)
    }

    func testClaudeStatusCacheRefreshKeepsEstimateOverUnavailableStatusline() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let estimatedClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: 58,
                resetAt: Self.fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: Self.fixedNow
        )
        let unavailableClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .unavailable,
            updatedAt: Self.fixedNow.addingTimeInterval(60),
            statusDetail: "Claude five-hour rate limit unreadable"
        )
        let aggregateProvider = CountingUsageProviderClient(snapshots: [
            estimatedClaude,
            Self.healthySnapshots[1]
        ])
        let claudeProvider = CountingUsageProviderClient(snapshots: [unavailableClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: aggregateProvider,
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(viewModel.snapshots, [estimatedClaude, Self.healthySnapshots[1]])
        XCTAssertEqual(claudeProvider.callCount, 1)
    }

    func testClaudeStatusCacheRefreshSkipsWhenClaudeIsDisabled() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.store.enabledProviders = [.codex]
        let claudeProvider = CountingUsageProviderClient(snapshots: [Self.healthySnapshots[0]])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()

        XCTAssertEqual(claudeProvider.callCount, 0)
        XCTAssertEqual(viewModel.snapshots, Self.healthySnapshots)
    }

    func testClaudeStatusCacheRefreshTimeoutAllowsLaterRefresh() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let refreshedClaude = Self.claudeSnapshot(
            usedPercent: 24,
            resetMinutes: 220,
            updatedAt: Self.fixedNow.addingTimeInterval(5)
        )
        let claudeProvider = TimeoutThenFreshClaudeProvider(freshSnapshot: refreshedClaude)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow },
            claudeStatusCacheRefreshTimeoutNanoseconds: 30_000_000
        )

        viewModel.refreshClaudeAfterStatusCacheChange()
        await waitUntil { claudeProvider.callCount == 1 }
        try? await Task.sleep(nanoseconds: 80_000_000)

        viewModel.refreshClaudeAfterStatusCacheChange()

        await waitForSnapshots([refreshedClaude, Self.healthySnapshots[1]], in: viewModel)
        XCTAssertGreaterThanOrEqual(claudeProvider.callCount, 2)
        claudeProvider.releaseFirstRefresh()
    }

    func testPendingClaudeStatusCacheRefreshRunsAfterSlowRefreshFinishes() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let firstClaude = Self.claudeSnapshot(
            usedPercent: 18,
            resetMinutes: 210,
            updatedAt: Self.fixedNow.addingTimeInterval(1)
        )
        let secondClaude = Self.claudeSnapshot(
            usedPercent: 12,
            resetMinutes: 230,
            updatedAt: Self.fixedNow.addingTimeInterval(2)
        )
        let claudeProvider = SlowFirstThenFreshClaudeProvider(
            firstSnapshot: firstClaude,
            freshSnapshot: secondClaude
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.healthySnapshots),
            claudeStatusCacheProviderClient: claudeProvider,
            now: { Self.fixedNow }
        )

        viewModel.refreshClaudeAfterStatusCacheChange()
        await waitUntil { claudeProvider.callCount == 1 }

        viewModel.refreshClaudeAfterStatusCacheChange()
        XCTAssertEqual(claudeProvider.callCount, 1)

        claudeProvider.releaseFirstRefresh()

        await waitUntil { claudeProvider.callCount == 2 }
        await waitForSnapshots([secondClaude, Self.healthySnapshots[1]], in: viewModel)
    }

    func testClaudeStatusCacheCatchUpMergesWhileLiveRefreshIsBlocked() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let liveClaude = CountingUsageProviderClient(snapshots: [Self.claudeUnavailableCodexHealthySnapshots[0]])
        let slowCodex = BlockingSingleProviderClient(snapshots: [Self.healthySnapshots[1]])
        let refreshedClaude = Self.claudeSnapshot(
            usedPercent: 8,
            resetMinutes: 245,
            updatedAt: Self.fixedNow.addingTimeInterval(5)
        )
        let cacheProvider = CountingUsageProviderClient(snapshots: [refreshedClaude])
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            claudeStatusCacheProviderClient: cacheProvider,
            liveClaudeProviderClient: liveClaude,
            liveCodexProviderClient: slowCodex,
            now: { Self.fixedNow }
        )

        viewModel.refreshUsageQuietly()
        await waitUntil { slowCodex.callCount == 1 }

        viewModel.refreshClaudeStatusCacheNow(reason: "test catch-up")

        await waitUntil { viewModel.snapshots.contains(refreshedClaude) }
        XCTAssertEqual(cacheProvider.callCount, 1)
        slowCodex.releaseRefresh()
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
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
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

    func testClaudeRowOffersSetupOnlyWhenSetupCueShows() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let setupState = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )
        XCTAssertTrue(setupState.claudeRowOffersSetup)

        let awaitingState = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeUnavailableCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )
        XCTAssertFalse(awaitingState.claudeRowOffersSetup)

        let estimatedState = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeEstimatedCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )
        XCTAssertEqual(estimatedState.claudeLiveUpgrade, .setupAvailable)
        XCTAssertFalse(estimatedState.claudeRowOffersSetup)
    }

    func testEstimatedClaudeRowSelectsInsteadOfOpeningSetup() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: StaticUsageProviderClient(snapshots: Self.claudeEstimatedCodexHealthySnapshots),
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )

        XCTAssertFalse(viewModel.claudeRowOffersSetup)

        viewModel.toggleSelection(.claude)

        XCTAssertEqual(viewModel.selectedProvider, .claude)
        XCTAssertEqual(viewModel.detail, "Claude resets in 2h 30m")
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
            source: .claudeStatusline,
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

    private static let genuineUnavailableSnapshots = [
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

    private final class SlowFirstThenFreshClaudeProvider: UsageProviderClient, @unchecked Sendable {
        let source: SnapshotSource = .claudeStatusline

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
        let source: SnapshotSource = .claudeStatusline

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
