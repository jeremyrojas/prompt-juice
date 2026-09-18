import XCTest
@testable import PromptJuice

@MainActor
final class PromptJuiceSettingsStoreTests: XCTestCase {
    func testLegacyThresholdsMigrateIntoFiveHourDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(45, forKey: "remainingMinutesThreshold")
        defaults.set(50, forKey: "remainingPercentThreshold")

        let store = PromptJuiceSettingsStore(defaults: defaults)
        XCTAssertEqual(store.sharedThresholds(for: .fiveHour),
                       AlertThresholds(remainingMinutes: 45, remainingPercent: 50))
        XCTAssertEqual(store.sharedThresholds(for: .weekly), .weeklyDefault)
        XCTAssertNil(defaults.object(forKey: "remainingMinutesThreshold"))
        XCTAssertNil(defaults.object(forKey: "remainingPercentThreshold"))

        let reopened = PromptJuiceSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.sharedThresholds(for: .fiveHour),
                       AlertThresholds(remainingMinutes: 45, remainingPercent: 50))
    }

    func testPerProviderCadenceOverrideFallsBackToSharedDefaults() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PromptJuiceSettingsStore(defaults: defaults)
        store.saveThresholds(
            AlertThresholds(remainingMinutes: 2_880, remainingPercent: 50),
            for: .weekly,
            provider: .codex
        )

        XCTAssertEqual(store.thresholds(for: .codex, cadence: .weekly),
                       AlertThresholds(remainingMinutes: 2_880, remainingPercent: 50))
        XCTAssertEqual(store.thresholds(for: .claude, cadence: .weekly), .weeklyDefault)
        XCTAssertEqual(store.thresholds(for: .codex, cadence: .fiveHour), .default)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "PromptJuiceSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
