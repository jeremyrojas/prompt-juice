import XCTest
@testable import PromptJuice

final class AlertEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let thresholds = AlertThresholds.default
    private let engine = AlertEngine()

    func testUseSoonWhenWindowIsNearResetWithEnoughRemaining() {
        let snapshot = makeSnapshot(
            usedPercent: 31,
            resetMinutesFromNow: 52,
            confidence: .exact
        )

        XCTAssertTrue(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: now
            )
        )
    }

    func testUseSoonIgnoresLowRemainingCapacity() {
        let snapshot = makeSnapshot(
            usedPercent: 80,
            resetMinutesFromNow: 30,
            confidence: .exact
        )

        XCTAssertFalse(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: now
            )
        )
    }

    func testStaleSnapshotCannotTriggerAlert() {
        let snapshot = makeSnapshot(
            usedPercent: 20,
            resetMinutesFromNow: 30,
            confidence: .stale
        )

        XCTAssertFalse(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: now
            )
        )
    }

    func testUnavailableSnapshotStatusIsExplicit() {
        let snapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexStub,
            confidence: .unavailable,
            updatedAt: now
        )

        XCTAssertEqual(
            engine.statusText(
                for: snapshot,
                thresholds: thresholds,
                now: now
            ),
            "Unavailable"
        )
    }

    func testPreferredSnapshotUsesHighestRemainingAlert() {
        let claude = makeSnapshot(
            identity: .claude,
            usedPercent: 36,
            resetMinutesFromNow: 47,
            confidence: .exact
        )
        let codex = makeSnapshot(
            identity: .codex,
            usedPercent: 31,
            resetMinutesFromNow: 52,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.preferredSnapshot(
                in: [claude, codex],
                thresholds: thresholds,
                now: now
            ),
            codex
        )
    }

    private func makeSnapshot(
        identity: ProviderIdentity = .codex,
        usedPercent: Double,
        resetMinutesFromNow: Int,
        confidence: SnapshotConfidence
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: identity,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: now.addingTimeInterval(TimeInterval(resetMinutesFromNow * 60)),
                durationMinutes: 300
            ),
            source: .fixture,
            confidence: confidence,
            updatedAt: now
        )
    }
}
