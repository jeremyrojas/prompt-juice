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

    func testPreferredSnapshotFallbackUsesSnapshotsWithResetWindows() {
        let freshClaude = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60),
            statusDetail: "Fresh window",
            isFreshSessionWindow: true
        )
        let codex = makeSnapshot(
            identity: .codex,
            usedPercent: 20,
            resetMinutesFromNow: 180,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.preferredSnapshot(
                in: [freshClaude, codex],
                thresholds: thresholds,
                now: now
            ),
            codex
        )
        XCTAssertNil(
            engine.preferredSnapshot(
                in: [freshClaude],
                thresholds: thresholds,
                now: now
            )
        )
    }

    func testSeverityHealthyWhenPlentyAndFarFromReset() {
        let snapshot = makeSnapshot(
            usedPercent: 20,
            resetMinutesFromNow: 240,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .healthy
        )
    }

    func testSeverityUseSoonWhenPlentyButResetIsNear() {
        let snapshot = makeSnapshot(
            usedPercent: 31,
            resetMinutesFromNow: 52,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .useSoon
        )
    }

    func testFreshSessionNeverTriggersUseSoon() {
        let snapshot = ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .exact,
            updatedAt: now,
            statusDetail: "Fresh window",
            isFreshSessionWindow: true
        )
        let advancedNow = now.addingTimeInterval(4.5 * 60 * 60)

        XCTAssertFalse(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: advancedNow
            )
        )
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: advancedNow),
            .healthy
        )
    }

    func testSeverityLowTakesPriorityOverUseSoon() {
        let snapshot = makeSnapshot(
            usedPercent: 90,
            resetMinutesFromNow: 20,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .low
        )
    }

    func testSeverityEmptyWhenNoneLeft() {
        let snapshot = makeSnapshot(
            usedPercent: 100,
            resetMinutesFromNow: 30,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .empty
        )
    }

    func testWeeklyLowUsesEffectiveRemainingForSeverity() {
        let snapshot = makeSnapshot(
            identity: .codex,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 95,
            weeklyResetMinutesFromNow: 4 * 24 * 60,
            confidence: .exact
        )

        XCTAssertEqual(snapshot.sessionRemainingPercent, 80)
        XCTAssertEqual(snapshot.remainingPercent, 5)
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .low
        )
        XCTAssertEqual(
            engine.statusText(for: snapshot, thresholds: thresholds, now: now),
            "Low"
        )
    }

    func testWeeklyEmptyUsesEffectiveRemainingForSeverity() {
        let snapshot = makeSnapshot(
            identity: .claude,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 100,
            weeklyResetMinutesFromNow: 4 * 24 * 60,
            confidence: .exact
        )

        XCTAssertEqual(snapshot.sessionRemainingPercent, 80)
        XCTAssertEqual(snapshot.remainingPercent, 0)
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .empty
        )
    }

    func testWeeklyResetTimingDoesNotTriggerUseSoon() {
        let snapshot = makeSnapshot(
            identity: .codex,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 20,
            weeklyResetMinutesFromNow: 20,
            confidence: .exact
        )

        XCTAssertFalse(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: now
            )
        )
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .healthy
        )
    }

    func testSeverityUnavailableSnapshot() {
        let snapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexStub,
            confidence: .unavailable,
            updatedAt: now
        )

        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .unavailable
        )
    }

    func testAggregateSeverityWorstAlertingWins() {
        let healthy = makeSnapshot(
            identity: .claude,
            usedPercent: 8,
            resetMinutesFromNow: 240,
            confidence: .exact
        )
        let useSoon = makeSnapshot(
            identity: .codex,
            usedPercent: 31,
            resetMinutesFromNow: 52,
            confidence: .exact
        )

        XCTAssertEqual(
            engine.aggregateSeverity(
                in: [healthy, useSoon],
                thresholds: thresholds,
                now: now
            ),
            .useSoon
        )
    }

    func testAggregateSeverityIgnoresUnavailableUnlessAll() {
        let healthy = makeSnapshot(
            identity: .claude,
            usedPercent: 8,
            resetMinutesFromNow: 240,
            confidence: .exact
        )
        let unavailable = ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexStub,
            confidence: .unavailable,
            updatedAt: now
        )

        XCTAssertEqual(
            engine.aggregateSeverity(
                in: [healthy, unavailable],
                thresholds: thresholds,
                now: now
            ),
            .healthy
        )

        XCTAssertEqual(
            engine.aggregateSeverity(
                in: [unavailable],
                thresholds: thresholds,
                now: now
            ),
            .unavailable
        )
    }

    func testSeverityPresentationContract() {
        let cases: [(UsageSeverity, String?, Bool, Bool, Int)] = [
            (.healthy, nil, false, false, 0),
            (.unavailable, nil, false, false, 1),
            (.low, nil, false, false, 2),
            (.empty, nil, false, false, 3),
            (.useSoon, "Use soon", true, true, 4)
        ]

        for (severity, chipText, isAlerting, hasMenuBarTint, rank) in cases {
            XCTAssertEqual(severity.chipText, chipText, "\(severity)")
            XCTAssertEqual(severity.isAlerting, isAlerting, "\(severity)")
            XCTAssertEqual(severity.menuBarTint != nil, hasMenuBarTint, "\(severity)")
            XCTAssertEqual(severity.rank, rank, "\(severity)")
        }
    }

    private func makeSnapshot(
        identity: ProviderIdentity = .codex,
        usedPercent: Double,
        resetMinutesFromNow: Int,
        weeklyUsedPercent: Double? = nil,
        weeklyResetMinutesFromNow: Int? = nil,
        confidence: SnapshotConfidence
    ) -> ProviderSnapshot {
        let weeklyWindow: RateWindow? = if let weeklyUsedPercent,
                                           let weeklyResetMinutesFromNow {
            .available(
                usedPercent: weeklyUsedPercent,
                resetAt: now.addingTimeInterval(TimeInterval(weeklyResetMinutesFromNow * 60)),
                durationMinutes: 10_080
            )
        } else {
            nil
        }

        return ProviderSnapshot(
            identity: identity,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: now.addingTimeInterval(TimeInterval(resetMinutesFromNow * 60)),
                durationMinutes: 300
            ),
            weeklyWindow: weeklyWindow,
            source: .fixture,
            confidence: confidence,
            updatedAt: now,
            weeklyUpdatedAt: weeklyWindow == nil ? nil : now
        )
    }
}
