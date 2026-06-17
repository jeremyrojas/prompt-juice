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
        try render("codexonly", CodexOnlyFixtureClient(), enabledProviders: [.codex])
        try render(
            "claudeonly-notmeasured",
            ClaudeOnlyNotMeasuredFixtureClient(),
            enabledProviders: [.claude]
        )
    }

    func testRenderClaudeSetupSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render setup snapshots."
        )

        let outputDirectory = URL(fileURLWithPath: "/tmp/promptjuice-verification", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        try renderClaudeSetup(
            "preview-nostatusline",
            plan: claudeSetupPlan(isWrappingExisting: false, jqInstalled: true),
            showsCommand: true,
            outputDirectory: outputDirectory
        )
        try renderClaudeSetup(
            "preview-jqmissing",
            plan: claudeSetupPlan(isWrappingExisting: true, jqInstalled: false),
            showsCommand: false,
            outputDirectory: outputDirectory
        )
    }

    func testRenderClaudeAwaitingSessionUXSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render awaiting-session snapshots."
        )

        let viewModel = awaitingSessionViewModel()

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
            "sheet-success",
            content: ClaudeSetupSuccessPreviewShell()
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
            mode: viewModel.mode,
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

            PromptJuicePanelView(viewModel: viewModel, onClose: {}, onSnooze: {})
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

    private func renderClaudeSetup(
        _ name: String,
        plan: ClaudeBridgeInstaller.Plan,
        showsCommand: Bool,
        outputDirectory: URL
    ) throws {
        let content = ClaudeSetupPlanPreviewShell(
            plan: plan,
            showsCommand: showsCommand
        )
        .environment(\.colorScheme, .dark)

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

        let url = outputDirectory.appendingPathComponent("\(name).png")
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
            mode: viewModel.mode,
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

            PromptJuicePanelView(viewModel: viewModel, onClose: {}, onSnooze: {})
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

    private func claudeSetupPlan(
        isWrappingExisting: Bool,
        jqInstalled: Bool
    ) -> ClaudeBridgeInstaller.Plan {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsPath = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
        let installedScriptPath = home
            .appendingPathComponent("Library/Application Support/PromptJuice", isDirectory: true)
            .appendingPathComponent("claude-statusline-bridge.sh")
        let previousCommand = isWrappingExisting ? "bash ~/.claude/statusline-command.sh" : nil
        let newCommand: String
        if let previousCommand {
            newCommand = "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='\(previousCommand)' bash '\(installedScriptPath.path)'"
        } else {
            newCommand = "bash '\(installedScriptPath.path)'"
        }

        return ClaudeBridgeInstaller.Plan(
            settingsPath: settingsPath,
            installedScriptPath: installedScriptPath,
            isWrappingExisting: isWrappingExisting,
            previousCommand: previousCommand,
            newCommand: newCommand,
            newSettingsData: Data(),
            jqInstalled: jqInstalled
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
