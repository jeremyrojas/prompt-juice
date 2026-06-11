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

    func testProviderSelectionStaysSticky() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let viewModel = PromptJuiceViewModel(
            settingsStore: fixture.store,
            providerClient: FixtureUsageProviderClient(scenario: .underusedCodex),
            now: { Self.fixedNow }
        )

        viewModel.selectProvider(.codex)
        XCTAssertEqual(viewModel.headline, "Codex: 69% to use")

        viewModel.selectProvider(.claude)
        XCTAssertEqual(viewModel.headline, "Claude: 43% to use")

        viewModel.selectProvider(.claude)
        XCTAssertEqual(viewModel.headline, "Claude: 43% to use")
    }

    func testSavedFixtureSourceFallsBackToLiveUsage() {
        let fixture = makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.store.usageSourceMode = .fixture

        XCTAssertEqual(fixture.store.usageSourceMode, .liveCodex)
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

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
}
