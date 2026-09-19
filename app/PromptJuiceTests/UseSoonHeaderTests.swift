import XCTest
@testable import PromptJuice

final class UseSoonHeaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testScopeAndGroupingMatrix() {
        let c5 = alert(.claude, .fiveHour, 83, 33, order: 0)
        let cw = alert(.claude, .weekly, 55, 1_380, order: 1)
        let fable = alert(.claude, .weeklyModel("Fable"), 62, 1_380, order: 2)
        let x5 = alert(.codex, .fiveHour, 78, 52, order: 0)
        let xw = alert(.codex, .weekly, 69, 1_380, order: 1)

        let cases: [(String, [AlertingLimit], String, String)] = [
            ("single 5-hour", [c5], "Use your Claude 5-hour juice", "83% left · resets in 33m"),
            ("single weekly", [xw], "Use your Codex Weekly juice", "69% left · resets in 23h"),
            ("single Fable", [fable], "Use your Fable juice", "62% left · resets in 23h"),
            ("Claude pair", [fable, cw], "Use your Claude juice", "Weekly & Fable reset in 23h"),
            ("Claude three", [fable, cw, c5], "Use your Claude juice",
             "5-hour resets in 33m · Weekly & Fable reset in 23h"),
            ("Codex pair", [xw, x5], "Use your Codex juice",
             "5-hour resets in 52m · Weekly resets in 23h"),
            ("across providers", [xw, c5], "Use your juice",
             "Claude 5-hour resets in 33m · Codex Weekly resets in 23h"),
            ("all five", [xw, fable, c5, x5, cw], "Use your juice",
             "5 limits reset soon · Claude 5-hour resets in 33m")
        ]

        for (name, alerts, title, subtitle) in cases {
            let result = UseSoonHeader.make(alerts: alerts, now: now, maxSubtitleWidth: 1_000)
            XCTAssertEqual(result?.title, title, name)
            XCTAssertEqual(result?.subtitle, subtitle, name)
        }
    }

    func testThreeResetGroupsUseCountForm() {
        let alerts = [
            alert(.claude, .fiveHour, 83, 33, order: 0),
            alert(.codex, .fiveHour, 78, 52, order: 0),
            alert(.codex, .weekly, 69, 1_380, order: 1)
        ]
        XCTAssertEqual(
            UseSoonHeader.make(alerts: alerts, now: now, maxSubtitleWidth: 1_000)?.subtitle,
            "3 limits reset soon · Claude 5-hour resets in 33m"
        )
    }

    func testLongEnumerationUsesCountFormBeforeItCanEllipsize() {
        let alerts = [
            alert(.claude, .fiveHour, 83, 33, order: 0),
            alert(.codex, .weekly, 69, 1_380, order: 0)
        ]
        XCTAssertEqual(
            UseSoonHeader.make(alerts: alerts, now: now)?.subtitle,
            "2 limits reset soon · Claude 5-hour resets in 33m"
        )
    }

    func testNoAmberHasNoHeader() {
        XCTAssertNil(UseSoonHeader.make(alerts: [], now: now))
    }

    func testSameBoundaryUsesRowOrderEvenWhenRankingBreaksTieByRemaining() {
        let alerts = [
            alert(.claude, .weeklyModel("Fable"), 62, 1_380, order: 2),
            alert(.claude, .weekly, 55, 1_380, order: 1)
        ]
        XCTAssertEqual(
            UseSoonHeader.make(alerts: alerts, now: now)?.subtitle,
            "Weekly & Fable reset in 23h"
        )
    }

    private func alert(
        _ provider: UsageProvider,
        _ kind: LimitWindow.Kind,
        _ remaining: Int,
        _ resetMinutes: Int,
        order: Int
    ) -> AlertingLimit {
        AlertingLimit(
            provider: provider,
            kind: kind,
            remainingPercent: remaining,
            resetAt: now.addingTimeInterval(TimeInterval(resetMinutes * 60)),
            rowOrder: order
        )
    }
}
