import AppKit
import XCTest
@testable import PromptJuice

@MainActor
final class JuicebarPanelControllerTests: XCTestCase {
    func testOpenPanelResizesWhenSelectedWeeklyRowExpands() async throws {
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
            mode: .manual,
            rowCount: 2,
            weeklyRowCount: 0
        )
        let weeklyHeight = PromptJuicePanelMetrics.height(
            mode: .manual,
            rowCount: 2,
            weeklyRowCount: 1
        )

        controller.show()
        defer { controller.hide() }

        await waitUntil {
            controller.panelFrameForTesting?.height == initialHeight
        }

        let initialFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(initialFrame.height, initialHeight)
        XCTAssertEqual(viewModel.visibleWeeklyRowCount, 0)

        viewModel.toggleSelection(.claude)

        await waitUntil {
            viewModel.visibleWeeklyRowCount == 1
                && controller.panelFrameForTesting?.height == weeklyHeight
        }

        let resizedFrame = try XCTUnwrap(controller.panelFrameForTesting)
        XCTAssertEqual(resizedFrame.height, weeklyHeight)
        XCTAssertGreaterThan(resizedFrame.height, initialFrame.height)

        let providers = viewModel.visibleSnapshots.map(\.provider)
        let weeklyProviders = Set(
            viewModel.visibleSnapshots
                .filter { viewModel.showsWeeklyLine(for: $0) }
                .map(\.provider)
        )
        let bounds = NSRect(origin: .zero, size: resizedFrame.size)
        let rows = PanelClickRouter.rowRects(
            in: bounds,
            mode: viewModel.mode,
            providers: providers,
            weeklyProviders: weeklyProviders
        )

        XCTAssertEqual(rows.map(\.provider), [.claude, .codex])
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[0].rect.center,
                in: bounds,
                mode: viewModel.mode,
                providers: providers,
                weeklyProviders: weeklyProviders
            ),
            .provider(.claude)
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[1].rect.center,
                in: bounds,
                mode: viewModel.mode,
                providers: providers,
                weeklyProviders: weeklyProviders
            ),
            .provider(.codex)
        )

        viewModel.toggleSelection(.claude)

        await waitUntil {
            viewModel.visibleWeeklyRowCount == 0
                && controller.panelFrameForTesting?.height == initialHeight
        }

        XCTAssertEqual(controller.panelFrameForTesting?.height, initialHeight)
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
