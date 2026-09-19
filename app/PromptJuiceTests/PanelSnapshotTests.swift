import SwiftUI
import XCTest
@testable import PromptJuice

/// Offscreen render of the real `PromptJuicePanelView` across the three
/// severity states. Skipped by default; run with PROMPTJUICE_SNAPSHOT=1 to
/// write PNGs to /tmp for visual review.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRenderPanelSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render panel snapshots."
        )

        try render("healthy", FixtureUsageProviderClient(scenario: .quiet))
        try render("usesoon", FixtureUsageProviderClient(scenario: .underusedCodex))
        try render("low", LowFixtureClient())
        try render("estimate", EstimateFixtureClient())
        try render("checking", CheckingFixtureClient())
        try render("notmeasured", NotMeasuredFixtureClient())
        try render("clash", ClashFixtureClient())
        try render("stale-claude", StaleClaudeFixtureClient())
        try render("codexonly", CodexOnlyFixtureClient(), enabledProviders: [.codex])
        try render(
            "claude-three-windows",
            MultiWindowFixtureClient(codexHasFiveHour: false),
            expandedProviders: [.claude]
        )
        try render("collapsed", MultiWindowFixtureClient(codexHasFiveHour: false))
        try render(
            "claude-expanded",
            MultiWindowFixtureClient(codexHasFiveHour: false),
            expandedProviders: [.claude]
        )
        try render("fable-amber-collapsed", MultiWindowFixtureClient(
            codexHasFiveHour: false,
            fableRemaining: 62,
            fableResetMinutes: 23 * 60
        ))
        try render("fable-low-collapsed", MultiWindowFixtureClient(
            codexHasFiveHour: false,
            fableRemaining: 9,
            fableResetMinutes: 23 * 60
        ))
        for scenario in MultiAmberFixtureClient.Scenario.allCases {
            try render("multi-amber-\(scenario.rawValue)", MultiAmberFixtureClient(scenario: scenario))
        }
        try render("codex-weekly-only", MultiWindowFixtureClient(codexHasFiveHour: false), enabledProviders: [.codex])
        try render(
            "codex-five-hour-weekly",
            MultiWindowFixtureClient(codexHasFiveHour: true),
            enabledProviders: [.codex],
            expandedProviders: [.codex]
        )
        try render(
            "claudeonly-notmeasured",
            ClaudeOnlyNotMeasuredFixtureClient(),
            enabledProviders: [.claude]
        )
    }

    func testRenderNotificationPrimeSnapshot() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render the notification prime snapshot."
        )

        let suiteName = "PanelSnapshotTests.prime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptJuiceSettingsStore(defaults: defaults)
        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { self.now }
        )
        viewModel.showManualCheck()
        viewModel.setNotificationAuthorization(.notDetermined)

        XCTAssertTrue(viewModel.shouldOfferUseSoonNotificationPrime)

        let panelHeight = PromptJuicePanelMetrics.height(
            windowCounts: viewModel.visibleWindowCounts,
            showsNotificationPrime: viewModel.shouldOfferUseSoonNotificationPrime
        )

        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            PromptJuicePanelView(viewModel: viewModel, onClose: {})
                .padding(40)
        }
        .frame(width: 464, height: panelHeight + 80)

        try renderView("panel-notification-prime", content: content)
    }

    func testRenderClaudeGuidanceFooterSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render guidance snapshots."
        )

        try renderView(
            "guidance-install-normal",
            content: ClaudeGuidancePreviewShell(
                viewModel: guidanceViewModel(access: .cliMissing, executable: nil),
                journey: .install
            )
            .environment(\.dynamicTypeSize, .large)
        )
        try renderView(
            "guidance-update-unknown-enlarged",
            content: ClaudeGuidancePreviewShell(
                viewModel: guidanceViewModel(
                    access: .updateRequired(
                        installed: ClaudeCodeVersion(major: 2, minor: 0, patch: 14),
                        minimum: .minimumUsageVersion
                    ),
                    executable: ClaudeExecutableLocation(
                        invokedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
                        resolvedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
                        provenance: .unknown
                    )
                ),
                journey: .update
            )
            .environment(\.dynamicTypeSize, .xxxLarge)
        )
    }

        private func render(
        _ name: String,
        _ client: any UsageProviderClient,
        enabledProviders: Set<UsageProvider>? = nil,
        expandedProviders: Set<UsageProvider> = []
    ) throws {
        let suiteName = "PanelSnapshotTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptJuiceSettingsStore(defaults: defaults)
        store.expandedProviders = expandedProviders
        if let enabledProviders {
            store.enabledProviders = enabledProviders
        }

        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: client,
            now: { self.now }
        )
        viewModel.showManualCheck()
        let panelHeight = PromptJuicePanelMetrics.height(
            windowCounts: viewModel.visibleWindowCounts
        )

        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            PromptJuicePanelView(viewModel: viewModel, onClose: {})
                .padding(40)
        }
        .frame(width: 464, height: panelHeight + 80)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw XCTSkip("ImageRenderer produced no image on this platform.")
        }

        let url = URL(fileURLWithPath: "/tmp/promptjuice-panel-\(name).png")
        try png.write(to: url)
        print("wrote \(url.path)")
    }

    private func renderView<Content: View>(
        _ name: String,
        content: Content
    ) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw XCTSkip("ImageRenderer produced no image on this platform.")
        }

        let url = URL(fileURLWithPath: "/tmp/promptjuice-\(name).png")
        try png.write(to: url)
        print("wrote \(url.path)")
    }

        private func guidanceViewModel(
        access: ClaudeAccessState,
        executable: ClaudeExecutableLocation?
    ) -> PromptJuiceViewModel {
        let suiteName = "PanelSnapshotTests.guidance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(UsageProvider.allCases.map(\.rawValue), forKey: "enabledProviders")
        let store = PromptJuiceSettingsStore(defaults: defaults)
        let claude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: now
        )
        return PromptJuiceViewModel(
            settingsStore: store,
            providerClient: NotMeasuredFixtureClient(),
            claudeExecutableLocator: { executable },
            initialSnapshots: [claude, codexExact(now)],
            initialClaudeAccessState: access,
            initialClaudeRefreshState: .idle,
            now: { self.now }
        )
    }
}


private func codexExact(_ now: Date, usedPercent: Double = 1) -> ProviderSnapshot {
    ProviderSnapshot(
        identity: .codex,
        rateWindow: .available(
            usedPercent: usedPercent,
            resetAt: now.addingTimeInterval(180 * 60),
            durationMinutes: 300
        ),
        source: .codexAppServer,
        confidence: .exact,
        updatedAt: now
    )
}

private struct MultiWindowFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture
    let codexHasFiveHour: Bool
    var fableRemaining: Double = 93
    var fableResetMinutes: Int = 5 * 24 * 60

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        let claude = ProviderSnapshot(
            identity: .claude,
            windows: [
                window(.fiveHour, remaining: 83, resetMinutes: 176, now: now),
                window(.weekly, remaining: 95, resetMinutes: 5 * 24 * 60, now: now),
                window(.weeklyModel("Fable"), remaining: fableRemaining, resetMinutes: fableResetMinutes, now: now)
            ],
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        var codexWindows: [LimitWindow] = []
        if codexHasFiveHour {
            codexWindows.append(window(.fiveHour, remaining: 92, resetMinutes: 176, now: now))
        }
        codexWindows.append(window(.weekly, remaining: 56, resetMinutes: 5 * 24 * 60, now: now))
        let codex = ProviderSnapshot(
            identity: .codex,
            windows: codexWindows,
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        return [claude, codex]
    }

    private func window(
        _ kind: LimitWindow.Kind,
        remaining: Double,
        resetMinutes: Int,
        now: Date
    ) -> LimitWindow {
        LimitWindow(
            kind: kind,
            rateWindow: .available(
                usedPercent: 100 - remaining,
                resetAt: now.addingTimeInterval(TimeInterval(resetMinutes * 60)),
                durationMinutes: kind.durationMinutes
            ),
            updatedAt: now
        )
    }
}

private struct MultiAmberFixtureClient: UsageProviderClient {
    enum Scenario: String, CaseIterable {
        case claudeTwo = "claude-two"
        case claudeThree = "claude-three"
        case codexTwo = "codex-two"
        case acrossProviders = "across-providers"
        case allFive = "all-five"
    }

    let source: SnapshotSource = .fixture
    let scenario: Scenario

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        let claudeFiveAmber = scenario == .claudeThree
            || scenario == .acrossProviders || scenario == .allFive
        let claudeWeeklyAmber = scenario == .claudeTwo
            || scenario == .claudeThree || scenario == .allFive
        let codexFivePresent = scenario == .codexTwo || scenario == .allFive
        let codexWeeklyAmber = scenario == .codexTwo
            || scenario == .acrossProviders || scenario == .allFive

        let claude = ProviderSnapshot(
            identity: .claude,
            windows: [
                make(.fiveHour, remaining: 83, minutes: claudeFiveAmber ? 33 : 176, now: now),
                make(.weekly, remaining: claudeWeeklyAmber ? 55 : 95,
                     minutes: claudeWeeklyAmber ? 1_380 : 7_200, now: now),
                make(.weeklyModel("Fable"), remaining: claudeWeeklyAmber ? 62 : 93,
                     minutes: claudeWeeklyAmber ? 1_380 : 7_200, now: now)
            ],
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        var codexWindows: [LimitWindow] = []
        if codexFivePresent {
            codexWindows.append(make(.fiveHour, remaining: 78, minutes: 52, now: now))
        }
        codexWindows.append(make(.weekly, remaining: 69,
                                 minutes: codexWeeklyAmber ? 1_380 : 7_200, now: now))
        let codex = ProviderSnapshot(
            identity: .codex,
            windows: codexWindows,
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        return [claude, codex]
    }

    private func make(
        _ kind: LimitWindow.Kind,
        remaining: Double,
        minutes: Int,
        now: Date
    ) -> LimitWindow {
        LimitWindow(
            kind: kind,
            rateWindow: .available(
                usedPercent: 100 - remaining,
                resetAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
                durationMinutes: kind.durationMinutes
            ),
            updatedAt: now
        )
    }
}

private struct LowFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 94,
                    resetAt: now.addingTimeInterval(12 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 42,
                    resetAt: now.addingTimeInterval(180 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}

private struct EstimateFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeLocalLogs

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 65,
                    resetAt: now.addingTimeInterval(100 * 60),
                    durationMinutes: 300
                ),
                source: .claudeLocalLogs,
                confidence: .estimated,
                updatedAt: now
            ),
            codexExact(now)
        ]
    }
}

private struct StaleClaudeFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeCache

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 32,
                    resetAt: now.addingTimeInterval(78 * 60),
                    durationMinutes: 300
                ),
                source: .claudeCache,
                confidence: .stale,
                updatedAt: now.addingTimeInterval(-11 * 60)
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 11,
                    resetAt: now.addingTimeInterval(81 * 60),
                    durationMinutes: 300
                ),
                source: .codexAppServer,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}

private struct NotMeasuredFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeUsageCLI

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeUsageCLI,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Claude usage unavailable"
            ),
            codexExact(now)
        ]
    }
}

private struct CheckingFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeUsageCLI,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Refreshing usage"
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .unavailable,
                source: .codexAppServer,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Refreshing usage"
            )
        ]
    }
}

private struct ClashFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 22,
                    resetAt: now.addingTimeInterval(20 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 92,
                    resetAt: now.addingTimeInterval(180 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}

private struct CodexOnlyFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 12,
                    resetAt: now.addingTimeInterval(180 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 30,
                    resetAt: now.addingTimeInterval(20 * 60),
                    durationMinutes: 300
                ),
                source: .codexAppServer,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}

private struct ClaudeOnlyNotMeasuredFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeUsageCLI

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeUsageCLI,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Claude usage unavailable"
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 28,
                    resetAt: now.addingTimeInterval(22 * 60),
                    durationMinutes: 300
                ),
                source: .codexAppServer,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}
