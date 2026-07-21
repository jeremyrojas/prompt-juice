import Foundation
import XCTest
@testable import PromptJuice

final class ClaudeUsageParserTests: XCTestCase {
    private var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func testSessionWeeklyAndModelSpecificFixtures() throws {
        let now = easternDate(2026, 11, 3, 12, 0)

        let sessionOnly = parse("Usage/session-only.txt", now: now)
        XCTAssertEqual(sessionOnly.reading?.session.usedPercent, 38)
        XCTAssertEqual(sessionOnly.reading?.session.resetAt, easternDate(2026, 11, 3, 15, 14))
        XCTAssertEqual(sessionOnly.reading?.plan, "Max")
        XCTAssertNil(sessionOnly.reading?.weekly)
        XCTAssertEqual(sessionOnly.reading?.modelSpecificWeekly, [])

        let weekly = parse("Usage/session-weekly.txt", now: now)
        XCTAssertEqual(weekly.reading?.session.usedPercent, 42)
        XCTAssertEqual(weekly.reading?.weekly?.usedPercent, 61)
        XCTAssertEqual(weekly.reading?.weekly?.resetAt, easternDate(2026, 11, 7, 0, 0))

        let modelSpecific = parse("Usage/session-weekly-model-specific.txt", now: now)
        XCTAssertEqual(modelSpecific.reading?.session.usedPercent, 22)
        XCTAssertEqual(modelSpecific.reading?.weekly?.usedPercent, 47)
        XCTAssertEqual(modelSpecific.reading?.modelSpecificWeekly.count, 1)
        XCTAssertEqual(modelSpecific.reading?.modelSpecificWeekly.first?.usedPercent, 73)
        XCTAssertEqual(
            modelSpecific.reading?.modelSpecificWeekly.first?.kind,
            .weeklyModel("Sonnet")
        )
    }

    func testZeroPercentRemainsAnOrdinaryExactWindow() throws {
        let now = easternDate(2026, 11, 3, 12, 0)
        let result = parse("Usage/zero-percent-used.txt", now: now)

        XCTAssertEqual(result.reading?.session.usedPercent, 0)
        XCTAssertEqual(result.reading?.plan, "Pro")
        XCTAssertFalse(result.reading?.isSavedReading ?? true)
        XCTAssertFalse(result.rateLimitObserved)
        XCTAssertNil(result.failure)
    }

    func testANSIResidueIsRemovedWithoutDamagingQuotaText() throws {
        let data = try fixtureData("Usage/ansi-residue.ans")
        let visible = ClaudeUsageParser.visibleTerminalText(from: data)
        XCTAssertFalse(visible.contains("\u{001B}"))
        XCTAssertTrue(visible.contains("Current session"))

        let result = ClaudeUsageParser().parse(
            data,
            now: easternDate(2026, 11, 3, 12, 0),
            calendar: easternCalendar
        )
        XCTAssertEqual(result.reading?.session.usedPercent, 50)
        XCTAssertEqual(result.reading?.session.resetAt, easternDate(2026, 11, 3, 16, 5))
    }

    func testMalformedAndPartialScreensFailSafely() throws {
        let now = easternDate(2026, 11, 3, 12, 0)
        XCTAssertEqual(parse("Usage/truncated.txt", now: now).failure, .incompleteWindow)
        XCTAssertEqual(parse("Usage/malformed.txt", now: now).failure, .incompleteWindow)

        let invalid = Data(
            "Usage\nCurrent session\n117% used\nResets at 4:00 PM\n".utf8
        )
        XCTAssertEqual(
            ClaudeUsageParser().parse(
                invalid,
                now: now,
                calendar: easternCalendar
            ).failure,
            .invalidPercentage
        )

        XCTAssertEqual(
            ClaudeUsageParser().parse(
                Data("Claude Code ready\n$".utf8),
                now: now,
                calendar: easternCalendar
            ).failure,
            .usagePanelUnavailable
        )
        XCTAssertEqual(
            ClaudeUsageParser().parse(
                Data(repeating: 0x41, count: ClaudeUsageParser.maximumOutputBytes + 1),
                now: now,
                calendar: easternCalendar
            ).failure,
            .outputTooLarge
        )
    }

    func testCachedBarFixturesKeepReadingAndRateLimitAsIndependentOutcomes() throws {
        let now = easternDate(2026, 7, 21, 10, 0)
        let expectedMeasurement = easternDate(2026, 7, 21, 9, 15)

        let session = parse("Usage/F-RL1-session-cached.txt", now: now)
        XCTAssertEqual(session.reading?.session.usedPercent, 42)
        XCTAssertEqual(session.reading?.measuredAt, expectedMeasurement)
        XCTAssertTrue(session.reading?.isSavedReading ?? false)
        XCTAssertTrue(session.rateLimitObserved)
        XCTAssertNil(session.failure)

        let weekly = parse("Usage/F-RL2-weekly-cached.txt", now: now)
        XCTAssertEqual(weekly.reading?.session.usedPercent, 42)
        XCTAssertEqual(weekly.reading?.weekly?.usedPercent, 61)
        XCTAssertEqual(weekly.reading?.measuredAt, expectedMeasurement)
        XCTAssertTrue(weekly.rateLimitObserved)
        XCTAssertNil(weekly.failure)

        let noBars = parse("Usage/F-RL3-rate-limit-no-bars.txt", now: now)
        XCTAssertNil(noBars.reading)
        XCTAssertTrue(noBars.rateLimitObserved)
        XCTAssertNil(noBars.failure)

        let malformedTimestamp = parse("Usage/F-RL4-bars-malformed-as-of.txt", now: now)
        XCTAssertNil(malformedTimestamp.reading)
        XCTAssertTrue(malformedTimestamp.rateLimitObserved)
        XCTAssertEqual(malformedTimestamp.failure, .malformedMeasurementTimestamp)
    }

    func testMeasurementTimestampFormatsAndDSTOffsets() throws {
        let now = easternDate(2026, 11, 3, 12, 0)
        let twelveHour = parse("Usage/as-of-12-hour.txt", now: now)
        XCTAssertEqual(twelveHour.reading?.measuredAt, easternDate(2026, 11, 3, 1, 30))

        let twentyFourHour = parse("Usage/as-of-24-hour.txt", now: now)
        XCTAssertEqual(
            twentyFourHour.reading?.measuredAt,
            date(timeZone: TimeZone(secondsFromGMT: -5 * 3_600)!, 2026, 11, 3, 1, 30)
        )

        let ansi = parse("Usage/as-of-ansi-residue.ans", now: now)
        XCTAssertEqual(
            ansi.reading?.measuredAt,
            date(timeZone: TimeZone(secondsFromGMT: -5 * 3_600)!, 2026, 11, 1, 1, 30)
        )

        let first = try XCTUnwrap(
            parse("Usage/as-of-timezone-dst-fall-first.txt", now: now).reading?.measuredAt
        )
        let second = try XCTUnwrap(
            parse("Usage/as-of-timezone-dst-fall-second.txt", now: now).reading?.measuredAt
        )
        XCTAssertEqual(second.timeIntervalSince(first), 3_600)

        let spring = parse("Usage/as-of-timezone-dst-spring.txt", now: now)
        XCTAssertEqual(
            spring.reading?.measuredAt,
            date(timeZone: TimeZone(secondsFromGMT: -4 * 3_600)!, 2026, 3, 8, 3, 0, 1)
        )
    }

    func testSanitizedLiveCaptureSelectsLatestCompleteRedraw() throws {
        let now = easternDate(2026, 7, 21, 10, 0)
        let result = parse("Live/usage-flat-subscription.ans", now: now)

        XCTAssertEqual(result.reading?.session.usedPercent, 100)
        XCTAssertEqual(result.reading?.session.resetAt, easternDate(2026, 7, 21, 11, 0))
        XCTAssertEqual(result.reading?.weekly?.usedPercent, 39)
        XCTAssertEqual(result.reading?.weekly?.resetAt, easternDate(2026, 7, 21, 19, 0))
        XCTAssertEqual(result.reading?.modelSpecificWeekly.count, 1)
        XCTAssertEqual(result.reading?.modelSpecificWeekly.first?.usedPercent, 59)
        XCTAssertEqual(result.reading?.modelSpecificWeekly.first?.kind, .weeklyModel("Fable"))
        XCTAssertEqual(result.reading?.plan, "Max")
        XCTAssertFalse(result.rateLimitObserved)
        XCTAssertNil(result.failure)
    }

    private func parse(_ path: String, now: Date) -> ClaudeUsageParseResult {
        do {
            return ClaudeUsageParser().parse(
                try fixtureData(path),
                now: now,
                calendar: easternCalendar
            )
        } catch {
            XCTFail("Unable to load fixture \(path): \(error)")
            return ClaudeUsageParseResult(
                reading: nil,
                rateLimitObserved: false,
                failure: .usagePanelUnavailable
            )
        }
    }

    private func fixtureData(_ path: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.resourceURL)
            .appendingPathComponent("Fixtures/Claude/\(path)")
        return try Data(contentsOf: url)
    }

    private func easternDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int = 0
    ) -> Date {
        date(
            timeZone: TimeZone(identifier: "America/New_York")!,
            year,
            month,
            day,
            hour,
            minute,
            second
        )
    }

    private func date(
        timeZone: TimeZone,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            )
        )!
    }
}
