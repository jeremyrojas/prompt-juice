import AppKit
import XCTest
@testable import PromptJuice

@MainActor
final class JuicebarPanelControllerTests: XCTestCase {
    func testOpenPanelKeepsFrameStableWhenSnapshotHasWeekly() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.weeklySnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(viewModel: viewModel)
        let initialHeight = PromptJuicePanelMetrics.height(
            rowCount: 2
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting?.height == initialHeight
        }

        let initialFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(initialFrame.height, initialHeight)

        let selectedFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(selectedFrame.height, initialFrame.height)
        XCTAssertEqual(
            viewModel.detail,
            "Claude resets in 3h 0m"
        )
        XCTAssertEqual(viewModel.headerRemainingPercent, 80)

        let providers = viewModel.visibleSnapshots.map(\.provider)
        let bounds = NSRect(origin: .zero, size: selectedFrame.size)
        let rows = PanelClickRouter.rowRects(
            in: bounds,
            providers: providers
        )

        XCTAssertEqual(rows.map(\.provider), [.claude, .codex])
        XCTAssertEqual(rows.map(\.rect.height), [
            PromptJuicePanelMetrics.plainRowHeight,
            PromptJuicePanelMetrics.plainRowHeight
        ])
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[0].rect.center,
                in: bounds,
                providers: providers
            ),
            .provider(.claude)
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[1].rect.center,
                in: bounds,
                providers: providers
            ),
            .provider(.codex)
        )
        XCTAssertEqual(controller.panelFrameForTesting?.height, initialHeight)
    }

    func testClaudeSetupRowClickOpensClaudeSettings() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.claudeSetupSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            initialClaudeAccessState: .cliMissing,
            initialClaudeRefreshState: .idle,
            now: { Self.fixedNow }
        )
        var guidanceRequests: [ClaudeGuidanceJourney] = []
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            onClaudeGuidanceRequested: { guidanceRequests.append($0) }
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting != nil
        }

        XCTAssertEqual(viewModel.claudePresentation.guidanceJourney, .install)

        let target = try providerTarget(row: 0, controller: controller, viewModel: viewModel)
        XCTAssertEqual(target, .provider(.claude))

        controller.clickTargetForTesting(target)

        XCTAssertEqual(guidanceRequests, [.install])
        XCTAssertNil(viewModel.selectedProvider)
    }

    func testClaudeSetupRowClickPreservesJourneyWhileSettingsRefreshRuns() async {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let coordinator = PanelStaticClaudeUsageCoordinator(
            state: ClaudeUsageCoordinatorState(
                access: .cliMissing,
                refresh: .idle,
                snapshot: Self.claudeSetupSnapshots[0]
            )
        )
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            liveCodexProviderClient: MutableUsageProviderClient(
                snapshots: [Self.claudeSetupSnapshots[1]]
            ),
            claudeUsageCoordinator: coordinator,
            initialSnapshots: Self.claudeSetupSnapshots,
            initialClaudeAccessState: .cliMissing,
            initialClaudeRefreshState: .idle,
            now: { Self.fixedNow }
        )
        let settingsController = SettingsWindowController(viewModel: viewModel)
        let panelController = JuicebarPanelController(
            viewModel: viewModel,
            onClaudeGuidanceRequested: { journey in
                settingsController.show(claudeJourney: journey)
            }
        )

        panelController.clickTargetForTesting(.provider(.claude))

        XCTAssertEqual(settingsController.claudeGuidanceJourneyForTesting, .install)
        await waitUntil { viewModel.claudeRefreshState == .idle }
        XCTAssertEqual(settingsController.claudeGuidanceJourneyForTesting, .install)
        settingsController.close()
    }

    func testAvailableProviderRowClickIsDisplayOnly() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        var guidanceRequests: [ClaudeGuidanceJourney] = []
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            onClaudeGuidanceRequested: { guidanceRequests.append($0) }
        )
        let expectedHeight = PromptJuicePanelMetrics.height(
            rowCount: 2
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting?.height == expectedHeight
        }

        let target = try providerTarget(row: 1, controller: controller, viewModel: viewModel)
        XCTAssertEqual(target, .provider(.codex))

        controller.clickTargetForTesting(target)

        XCTAssertNil(viewModel.selectedProvider)
        XCTAssertTrue(guidanceRequests.isEmpty)
        XCTAssertEqual(viewModel.detail, "Claude resets in 3h 0m")
        XCTAssertEqual(controller.panelFrameForTesting?.height, expectedHeight)
    }

    func testPinnedCloseReturnsToAnchoredMode() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            settingsStore: fixture.store
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting != nil
        }

        let anchoredFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(controller.panelModeForTesting, .anchored)
        XCTAssertFalse(controller.panelIsMovableForTesting)
        XCTAssertTrue(controller.panelAllowsBackgroundDraggingForTesting)

        controller.pin()

        XCTAssertEqual(controller.panelModeForTesting, .pinned)
        XCTAssertTrue(controller.panelIsMovableForTesting)
        let pinnedOrigin = try XCTUnwrap(fixture.store.pinnedJuicebarOrigin)
        XCTAssertEqual(pinnedOrigin.x, anchoredFrame.origin.x)
        XCTAssertEqual(pinnedOrigin.y, anchoredFrame.origin.y)

        controller.clickTargetForTesting(.close)

        await waitUntil {
            controller.panelIsVisibleForTesting == false
        }

        XCTAssertEqual(controller.panelModeForTesting, .anchored)
        XCTAssertNil(viewModel.selectedProvider)

        controller.show()

        await waitUntil {
            controller.panelIsVisibleForTesting
        }

        let reopenedFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(reopenedFrame.origin.x, anchoredFrame.origin.x, accuracy: 0.5)
        XCTAssertEqual(reopenedFrame.origin.y, anchoredFrame.origin.y, accuracy: 0.5)
        XCTAssertEqual(controller.panelModeForTesting, .anchored)
    }

    func testPinnedOriginPersistsAndRestoresFromClosed() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            settingsStore: fixture.store
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting != nil
        }

        controller.pin()

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let savedOrigin = NSPoint(x: visibleFrame.minX + 24, y: visibleFrame.minY + 24)
        controller.movePanelOriginForTesting(to: savedOrigin)

        let pinnedOrigin = try XCTUnwrap(fixture.store.pinnedJuicebarOrigin)
        XCTAssertEqual(pinnedOrigin.x, savedOrigin.x, accuracy: 0.5)
        XCTAssertEqual(pinnedOrigin.y, savedOrigin.y, accuracy: 0.5)

        controller.hide()
        controller.pin()

        await waitUntil {
            controller.panelIsVisibleForTesting
        }

        let restoredFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(controller.panelModeForTesting, .pinned)
        XCTAssertEqual(restoredFrame.origin.x, savedOrigin.x, accuracy: 0.5)
        XCTAssertEqual(restoredFrame.origin.y, savedOrigin.y, accuracy: 0.5)
    }

    func testPinnedOriginRestoresOnScreen() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        fixture.store.pinnedJuicebarOrigin = CGPoint(x: 100_000, y: 100_000)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            settingsStore: fixture.store
        )

        controller.pin()
        defer { controller.hide() }

        await waitUntil {
            controller.panelIsVisibleForTesting
        }

        let frame = try XCTUnwrap(controller.panelFrameForTesting)
        let isInsideVisibleFrame = NSScreen.screens.contains { screen in
            frame.minX >= screen.visibleFrame.minX
                && frame.maxX <= screen.visibleFrame.maxX + 0.5
                && frame.minY >= screen.visibleFrame.minY
                && frame.maxY <= screen.visibleFrame.maxY + 0.5
        }
        XCTAssertTrue(isInsideVisibleFrame)
    }

    func testPanelContextMenuReflectsPinState() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            settingsStore: fixture.store
        )

        controller.prepare()

        XCTAssertEqual(controller.panelContextMenuTitlesForTesting, [
            "Settings…",
            "Pin Juicebar",
            "Quit PromptJuice"
        ])

        controller.pin()
        defer { controller.hide() }

        XCTAssertEqual(controller.panelContextMenuTitlesForTesting, [
            "Settings…",
            "Unpin Juicebar",
            "Quit PromptJuice"
        ])
    }

    func testMaterialRootPreservesPanelInteractionContracts() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow }
        )
        let controller = JuicebarPanelController(viewModel: viewModel)

        controller.prepare()

        XCTAssertTrue(controller.panelContentForwardsToolTipsForTesting)
        XCTAssertTrue(controller.panelHasShadowForTesting)
        XCTAssertEqual(controller.panelAnimationBehaviorForTesting, NSWindow.AnimationBehavior.none)

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelIsVisibleForTesting
        }

        XCTAssertTrue(controller.panelFirstResponderIsInteractiveContentForTesting)
        XCTAssertTrue(controller.panelContentForwardsToolTipsForTesting)
        XCTAssertTrue(controller.panelHasShadowForTesting)
        XCTAssertEqual(controller.panelAnimationBehaviorForTesting, NSWindow.AnimationBehavior.none)
    }

    private func makeFixture() -> (
        suiteName: String,
        defaults: UserDefaults,
        store: PromptJuiceSettingsStore
    ) {
        let suiteName = "PromptJuicePanelControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = PromptJuiceSettingsStore(defaults: defaults)
        return (suiteName, defaults, store)
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

    private func providerTarget(
        row: Int,
        controller: JuicebarPanelController,
        viewModel: PromptJuiceViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PanelClickTarget {
        let frame = try XCTUnwrap(controller.panelFrameForTesting, file: file, line: line)
        let providers = viewModel.visibleSnapshots.map(\.provider)
        let bounds = NSRect(origin: .zero, size: frame.size)
        let rows = PanelClickRouter.rowRects(
            in: bounds,
            providers: providers
        )
        let row = try XCTUnwrap(rows[safe: row], file: file, line: line)
        return try XCTUnwrap(
            PanelClickRouter.target(
                at: row.rect.center,
                in: bounds,
                providers: providers
            ),
            file: file,
            line: line
        )
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static let plainSnapshots = [
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
            rateWindow: .available(
                usedPercent: 12,
                resetAt: fixedNow.addingTimeInterval(240 * 60),
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
                resetAt: fixedNow.addingTimeInterval(180 * 60),
                durationMinutes: 300
            ),
            weeklyWindow: .available(
                usedPercent: 5,
                resetAt: fixedNow.addingTimeInterval(5 * 24 * 60 * 60),
                durationMinutes: 10_080
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow.addingTimeInterval(60),
            weeklyUpdatedAt: fixedNow.addingTimeInterval(60)
        ),
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 12,
                resetAt: fixedNow.addingTimeInterval(240 * 60),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: .exact,
            updatedAt: fixedNow.addingTimeInterval(60)
        )
    ]

    private static let claudeSetupSnapshots = [
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
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private final class MutableUsageProviderClient: UsageProviderClient, @unchecked Sendable {
    let source: SnapshotSource = .fixture

    private let lock = NSLock()
    private var storedSnapshots: [ProviderSnapshot]

    init(snapshots: [ProviderSnapshot]) {
        self.storedSnapshots = snapshots
    }

    func setSnapshots(_ snapshots: [ProviderSnapshot]) {
        lock.withLock {
            storedSnapshots = snapshots
        }
    }

    func snapshots(now _: Date) -> [ProviderSnapshot] {
        lock.withLock {
            storedSnapshots
        }
    }
}

private struct PanelStaticClaudeUsageCoordinator: ClaudeUsageSnapshotProviding {
    let state: ClaudeUsageCoordinatorState

    init(state: ClaudeUsageCoordinatorState) {
        self.state = state
    }

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

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
