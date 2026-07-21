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
            rowCount: viewModel.visibleSnapshots.count,
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

    func testRenderClaudeAwaitingSessionUXSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render awaiting-session snapshots."
        )

        let viewModel = awaitingSessionViewModel()
        let unavailableViewModel = awaitingSessionUnavailableViewModel()

        try renderView(
            "settings-awaiting",
            content: SettingsProviderRowPreviewShell(viewModel: viewModel)
                .environment(\.colorScheme, .dark)
        )
        try renderView(
            "popover-awaiting",
            content: ClaudeMeasurementPopoverPreviewShell(viewModel: viewModel)
                .environment(\.colorScheme, .dark)
        )
        try renderView(
            "popover-awaiting-unavailable",
            content: ClaudeMeasurementPopoverPreviewShell(viewModel: unavailableViewModel)
                .environment(\.colorScheme, .dark)
        )
        try renderView(
            "tooltip-awaiting",
            content: AwaitingTooltipPreview(
                text: tooltipText(from: viewModel)
            )
            .environment(\.colorScheme, .dark)
        )
        try renderView(
            "tooltip-awaiting-unavailable",
            content: AwaitingTooltipPreview(
                text: tooltipText(from: unavailableViewModel)
            )
            .environment(\.colorScheme, .dark)
        )
        try renderAwaitingSessionPanel(viewModel: viewModel)

        try renderView(
            "settings-claude-disabled",
            content: SettingsProviderRowPreviewShell(
                viewModel: setupAvailableViewModel(),
                isEnabled: false
            )
                .environment(\.colorScheme, .dark)
        )
    }

    func testRenderStaleClaudeIndicatorSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render stale Claude snapshots."
        )

        let viewModel = staleClaudeViewModel()
        let panelHeight = PromptJuicePanelMetrics.height(
            rowCount: viewModel.visibleSnapshots.count
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

        try renderView("panel-stale-claude", content: content)
        try renderView(
            "tooltip-stale-claude",
            content: AwaitingTooltipPreview(text: tooltipText(from: viewModel))
                .environment(\.colorScheme, .dark)
        )
    }

    private func render(
        _ name: String,
        _ client: any UsageProviderClient,
        enabledProviders: Set<UsageProvider>? = nil
    ) throws {
        let suiteName = "PanelSnapshotTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PromptJuiceSettingsStore(defaults: defaults)
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
            rowCount: viewModel.visibleSnapshots.count
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

    private func renderAwaitingSessionPanel(viewModel: PromptJuiceViewModel) throws {
        let panelHeight = PromptJuicePanelMetrics.height(
            rowCount: viewModel.visibleSnapshots.count
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

        try renderView("panel-awaiting", content: content)
    }

    private func awaitingSessionViewModel() -> PromptJuiceViewModel {
        let suiteName = "PanelSnapshotTests.awaiting-session.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PromptJuiceSettingsStore(defaults: defaults)
        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: EstimateFixtureClient(),
            now: { self.now },
            isClaudeBridgeCurrent: { true }
        )
        viewModel.showManualCheck()
        return viewModel
    }

    private func awaitingSessionUnavailableViewModel() -> PromptJuiceViewModel {
        let suiteName = "PanelSnapshotTests.awaiting-session-unavailable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PromptJuiceSettingsStore(defaults: defaults)
        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: NotMeasuredFixtureClient(),
            now: { self.now },
            isClaudeBridgeCurrent: { true }
        )
        viewModel.showManualCheck()
        return viewModel
    }

    private func tooltipText(from viewModel: PromptJuiceViewModel) -> String {
        let claude = viewModel.snapshots.first { $0.provider == .claude }!
        return viewModel.sourceTooltip(for: claude)
    }

    private func setupAvailableViewModel() -> PromptJuiceViewModel {
        let suiteName = "PanelSnapshotTests.setup-available.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PromptJuiceSettingsStore(defaults: defaults)
        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: NotMeasuredFixtureClient(),
            now: { self.now },
            isClaudeBridgeCurrent: { false }
        )
        viewModel.showManualCheck()
        return viewModel
    }

    private func staleClaudeViewModel() -> PromptJuiceViewModel {
        let suiteName = "PanelSnapshotTests.stale-claude.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = PromptJuiceSettingsStore(defaults: defaults)
        let viewModel = PromptJuiceViewModel(
            settingsStore: store,
            providerClient: StaleClaudeFixtureClient(),
            now: { self.now },
            isClaudeBridgeCurrent: { true }
        )
        viewModel.showManualCheck()
        return viewModel
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
            claudeUsageDogfoodEnabled: true,
            claudeExecutableLocator: { executable },
            initialSnapshots: [claude, codexExact(now)],
            initialClaudeAccessState: access,
            initialClaudeRefreshState: .idle,
            now: { self.now },
            isClaudeBridgeCurrent: { false }
        )
    }
}

private struct AwaitingTooltipPreview: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 330, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .padding(18)
            .background(Color(NSColor.windowBackgroundColor))
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
    let source: SnapshotSource = .claudeStatusline

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeStatusline,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Claude statusline and local usage unavailable"
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
                source: .claudeStatusline,
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
    let source: SnapshotSource = .claudeStatusline

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeStatusline,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Claude statusline and local usage unavailable"
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
