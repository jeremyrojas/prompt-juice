import Foundation
import XCTest
@testable import PromptJuice

final class ResetFormatterTests: XCTestCase {
    func testResetCountdownAddsFlooredSecondUnitBelowThreeHoursOrDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(seconds: TimeInterval, expected: String)] = [
            (-60, "resets in 0m"),
            (0, "resets in 0m"),
            (59, "resets in 0m"),
            (33 * 60, "resets in 33m"),
            (60 * 60 - 1, "resets in 59m"),
            (60 * 60, "resets in 1h"),
            (60 * 60 + 32 * 60 + 59, "resets in 1h 32m"),
            (2 * 60 * 60, "resets in 2h"),
            (2 * 60 * 60 + 59, "resets in 2h"),
            (3 * 60 * 60 - 1, "resets in 2h 59m"),
            (3 * 60 * 60, "resets in 3h"),
            (5 * 60 * 60 + 10 * 60, "resets in 5h"),
            (23 * 60 * 60 + 40 * 60, "resets in 23h"),
            (24 * 60 * 60, "resets in 1d"),
            (25 * 60 * 60, "resets in 1d 1h"),
            (36 * 60 * 60 + 59 * 60, "resets in 1d 12h"),
            (48 * 60 * 60, "resets in 2d"),
            (48 * 60 * 60 + 59 * 60, "resets in 2d"),
            (72 * 60 * 60 - 1, "resets in 2d 23h"),
            (72 * 60 * 60, "resets in 3d"),
            (6 * 24 * 60 * 60 + 2 * 60 * 60, "resets in 6d"),
            (146 * 60 * 60 + 4 * 60, "resets in 6d")
        ]

        for testCase in cases {
            let resetAt = now.addingTimeInterval(testCase.seconds)
            XCTAssertEqual(
                ResetFormatter.text(until: resetAt, now: now),
                testCase.expected,
                "reset after \(testCase.seconds) seconds"
            )
        }
    }
}
