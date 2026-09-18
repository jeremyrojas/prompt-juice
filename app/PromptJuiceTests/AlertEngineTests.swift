import XCTest
@testable import PromptJuice

final class AlertEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let thresholds = AlertThresholds.default
    private let engine = AlertEngine()

    func testUntouchedWindowNeverAlerts() {
        let snapshot = makeSnapshot(
            usedPercent: 0,
            resetMinutesFromNow: 20,
            confidence: .exact
        )
        XCTAssertFalse(engine.shouldUseSoon(for: snapshot, thresholds: thresholds, now: now))
    }

    func testFivePercentUsedIsEligibleForUseSoon() {
        let snapshot = makeSnapshot(
            usedPercent: 5,
            resetMinutesFromNow: 60,
            confidence: .exact
        )
        XCTAssertTrue(engine.shouldUseSoon(for: snapshot, thresholds: thresholds, now: now))
    }

    func testUnexpectedDurationUsesItsCadenceThreshold() {
        let short = LimitWindow(
            kind: .other(180),
            rateWindow: .available(
                usedPercent: 20,
                resetAt: now.addingTimeInterval(61 * 60),
                durationMinutes: 180
            ),
            updatedAt: now
        )
        let long = LimitWindow(
            kind: .other(1_440),
            rateWindow: .available(
                usedPercent: 20,
                resetAt: now.addingTimeInterval(23 * 60 * 60),
                durationMinutes: 1_440
            ),
            updatedAt: now
        )
        let snapshot = ProviderSnapshot(
            identity: .codex,
            windows: [short, long],
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        XCTAssertFalse(engine.shouldUseSoon(
            for: short, in: snapshot, thresholds: .default, now: now
        ))
        XCTAssertTrue(engine.shouldUseSoon(
            for: long, in: snapshot, thresholds: .weeklyDefault, now: now
        ))
        XCTAssertEqual(engine.severity(for: snapshot, thresholds: .default, now: now), .useSoon)
    }

    func testFableEmptyDoesNotMakeClaudeEmpty() {
        let snapshot = ProviderSnapshot(
            identity: .claude,
            windows: [
                LimitWindow(
                    kind: .fiveHour,
                    rateWindow: .available(
                        usedPercent: 17,
                        resetAt: now.addingTimeInterval(180 * 60),
                        durationMinutes: 300
                    ),
                    updatedAt: now
                ),
                LimitWindow(
                    kind: .weeklyModel("Fable"),
                    rateWindow: .available(
                        usedPercent: 100,
                        resetAt: now.addingTimeInterval(23 * 60 * 60),
                        durationMinutes: 10_080
                    ),
                    updatedAt: now
                )
            ],
            source: .fixture,
            confidence: .exact,
            updatedAt: now
        )
        XCTAssertEqual(engine.severity(for: snapshot, thresholds: .default, now: now), .healthy)
    }

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

    func testCodexFreshSessionNeverTriggersUseSoon() {
        let snapshot = ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexAppServer,
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

    func testWeeklyMinimumIsDormantForSeverity() {
        let snapshot = makeSnapshot(
            identity: .codex,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 95,
            weeklyResetMinutesFromNow: 4 * 24 * 60,
            confidence: .exact
        )

        XCTAssertEqual(snapshot.sessionRemainingPercent, 80)
        XCTAssertEqual(snapshot.remainingPercent, 80)
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .healthy
        )
        XCTAssertEqual(
            engine.statusText(for: snapshot, thresholds: thresholds, now: now),
            "Some left"
        )
    }

    func testAllModelsWeeklyEmptyLocksProvider() {
        let snapshot = makeSnapshot(
            identity: .claude,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 100,
            weeklyResetMinutesFromNow: 4 * 24 * 60,
            confidence: .exact
        )

        XCTAssertEqual(snapshot.sessionRemainingPercent, 80)
        XCTAssertEqual(snapshot.remainingPercent, 80)
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .empty
        )
    }

    func testWeeklyResetTimingTriggersUseSoon() {
        let snapshot = makeSnapshot(
            identity: .codex,
            usedPercent: 20,
            resetMinutesFromNow: 240,
            weeklyUsedPercent: 20,
            weeklyResetMinutesFromNow: 20,
            confidence: .exact
        )

        XCTAssertTrue(
            engine.shouldUseSoon(
                for: snapshot,
                thresholds: thresholds,
                now: now
            )
        )
        XCTAssertEqual(
            engine.severity(for: snapshot, thresholds: thresholds, now: now),
            .useSoon
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
