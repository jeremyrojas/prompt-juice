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
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
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
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { false }
        )
        var settingsRequests: [Bool] = []
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            onClaudeSettingsRequested: { settingsRequests.append($0) }
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting != nil
        }

        XCTAssertTrue(viewModel.claudeRowOffersSetup)

        let target = try providerTarget(row: 0, controller: controller, viewModel: viewModel)
        XCTAssertEqual(target, .provider(.claude))

        controller.clickTargetForTesting(target)

        XCTAssertEqual(settingsRequests, [true])
        XCTAssertNil(viewModel.selectedProvider)
    }

    func testAvailableProviderRowClickIsDisplayOnly() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )
        var settingsRequests: [Bool] = []
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            onClaudeSettingsRequested: { settingsRequests.append($0) }
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
        XCTAssertTrue(settingsRequests.isEmpty)
        XCTAssertEqual(viewModel.detail, "Claude resets in 3h 0m")
        XCTAssertEqual(controller.panelFrameForTesting?.height, expectedHeight)
    }

    func testSettingsGearClickOpensSettings() async throws {
        let fixture = makeFixture()
        fixture.store.usageSourceMode = .fixture
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let provider = MutableUsageProviderClient(snapshots: Self.plainSnapshots)
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: provider,
            now: { Self.fixedNow },
            isClaudeBridgeCurrent: { true }
        )
        var settingsOpenCount = 0
        let controller = JuicebarPanelController(
            viewModel: viewModel,
            onSettingsRequested: { settingsOpenCount += 1 }
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting != nil
        }

        let frame = try XCTUnwrap(controller.panelFrameForTesting)
        let bounds = NSRect(origin: .zero, size: frame.size)
        let providers = viewModel.visibleSnapshots.map(\.provider)
        let target = try XCTUnwrap(
            PanelClickRouter.target(
                at: PanelClickRouter.settingsRect(in: bounds).center,
                in: bounds,
                providers: providers
            )
        )

        XCTAssertEqual(target, .settings)

        controller.clickTargetForTesting(target)

        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertTrue(controller.panelIsVisibleForTesting)
        XCTAssertNil(viewModel.selectedProvider)
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

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
