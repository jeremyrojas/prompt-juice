import XCTest
@testable import PromptJuice

@MainActor
final class PromptJuiceViewModelTests: XCTestCase {
    func testDefaultDemoAlertIsPending() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkDemoAlert())
        XCTAssertEqual(viewModel.mode, .alert)
    }

    func testSnoozeSuppressesCurrentDemoWindow() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkDemoAlert(force: true))
        viewModel.snooze()

        XCTAssertFalse(viewModel.checkDemoAlert())
        XCTAssertEqual(viewModel.mode, .manual)
    }

    func testManualCheckClearsCurrentDemoSnooze() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            now: { Self.fixedNow }
        )

        XCTAssertTrue(viewModel.checkDemoAlert(force: true))
        viewModel.snooze()
        viewModel.showManualCheck()

        XCTAssertTrue(viewModel.checkDemoAlert())
        XCTAssertEqual(viewModel.mode, .alert)
    }

    func testThresholdsAffectDemoAlert() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            now: { Self.fixedNow }
        )

        viewModel.setRemainingMinutesThreshold(30)
        viewModel.setRemainingPercentThreshold(80)

        XCTAssertFalse(viewModel.checkDemoAlert())
        XCTAssertEqual(viewModel.mode, .manual)
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
        store.usageSourceMode = .demo
        return (suiteName, defaults, store)
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
}
