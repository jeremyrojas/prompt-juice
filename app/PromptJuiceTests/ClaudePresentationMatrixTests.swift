import XCTest
@testable import PromptJuice

@MainActor
final class ClaudePresentationMatrixTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    func testTwentyTwoScenarioPresentationCatalog() {
        let formatter = ClaudeFreshnessFormatter()
        let savedAt = fixedNow.addingTimeInterval(-2 * 60 * 60)
        let savedTime = formatter.clockTime(savedAt)
        let nextAttemptAt = fixedNow.addingTimeInterval(45 * 60)
        let nextTime = formatter.clockTime(nextAttemptAt)
        let estimate = snapshot(confidence: .estimated)
        let cached = snapshot(source: .claudeCache, confidence: .stale, updatedAt: savedAt)
        let unavailable = unavailableSnapshot()
        let cases: [Case] = [
            Case(
                name: "checking without reading",
                access: .subscription(plan: "Max"),
                refresh: .refreshing,
                snapshot: unavailable,
                expectedState: .checking,
                showsReading: false,
                showsClock: false,
                rowStatus: "Checking…",
                tooltip: "Checking usage with Claude Code",
                settingsSubtitle: "Checking…",
                settingsAction: nil,
                footnote: nil,
                popover: "Checking usage with Claude Code now.",
                neutral: false
            ),
            Case(
                name: "checking with cached reading",
                access: .subscription(plan: "Max"),
                refresh: .refreshing,
                snapshot: cached,
                expectedState: .checking,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "Checking usage with Claude Code",
                settingsSubtitle: "Checking…",
                settingsAction: nil,
                footnote: nil,
                popover: "Checking usage with Claude Code now.",
                neutral: false
            ),
            Case(
                name: "connected current",
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: snapshot(),
                expectedState: .current,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "From Claude Code · updated just now",
                settingsSubtitle: "Updated just now",
                settingsAction: nil,
                footnote: nil,
                popover: "Right now it's current, read a moment ago.",
                neutral: false
            ),
            Case(
                name: "connected saved",
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: cached,
                expectedState: .saved,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "From Claude Code · updated at \(savedTime)",
                settingsSubtitle: "Updated at \(savedTime)",
                settingsAction: nil,
                footnote: nil,
                popover: "Showing your last reading from \(savedTime). PromptJuice refreshes it automatically.",
                neutral: false
            ),
            Case(
                name: "out of quota",
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: snapshot(usedPercent: 100, updatedAt: savedAt),
                expectedState: .outOfQuota,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "Claude is out until reset · updated at \(savedTime)",
                settingsSubtitle: "Updated at \(savedTime)",
                settingsAction: nil,
                footnote: nil,
                popover: "Showing your last reading from \(savedTime). PromptJuice refreshes it automatically.",
                neutral: false
            ),
            Case(
                name: "backing off with cached reading",
                access: .subscription(plan: "Max"),
                refresh: .backingOff(nextAttemptAt: nextAttemptAt),
                snapshot: cached,
                expectedState: .backingOff,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "From Claude Code · updated at \(savedTime) · next check at \(nextTime)",
                settingsSubtitle: "Updated at \(savedTime) · next check at \(nextTime)",
                settingsAction: nil,
                footnote: nil,
                popover: "The last usage check was rate limited. PromptJuice tries again at \(nextTime). Showing your \(savedTime) reading in the meantime.",
                neutral: false
            ),
            Case(
                name: "backing off without reading",
                access: .subscription(plan: "Max"),
                refresh: .backingOff(nextAttemptAt: nextAttemptAt),
                snapshot: unavailable,
                expectedState: .backingOff,
                showsReading: false,
                showsClock: false,
                rowStatus: "Next check \(nextTime)",
                tooltip: "Usage check paused · next check at \(nextTime)",
                settingsSubtitle: "Next check at \(nextTime)",
                settingsAction: nil,
                footnote: nil,
                popover: "The last usage check was rate limited. PromptJuice tries again at \(nextTime).",
                neutral: false
            ),
            Case(
                name: "CLI missing with estimate",
                access: .cliMissing,
                refresh: .idle,
                snapshot: estimate,
                expectedState: .cliMissing,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "Estimated from Claude Code's activity logs on this Mac",
                settingsSubtitle: "Claude Code not installed · showing local estimate",
                settingsAction: .journey(.install),
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. Install Claude Code and sign in, and PromptJuice switches to direct readings automatically.",
                popover: "Claude Code isn't installed yet. Install it and sign in once. Claude Desktop, Claude.ai, and Claude Code share the same plan usage.",
                neutral: false
            ),
            Case(
                name: "CLI missing without reading",
                access: .cliMissing,
                refresh: .idle,
                snapshot: unavailable,
                expectedState: .cliMissing,
                showsReading: false,
                showsClock: false,
                rowStatus: "Claude Code needed",
                tooltip: "Install Claude Code to read your plan usage",
                settingsSubtitle: "Claude Code not installed",
                settingsAction: .journey(.install),
                footnote: nil,
                popover: "Claude Code isn't installed yet. Install it and sign in once. Claude Desktop, Claude.ai, and Claude Code share the same plan usage.",
                neutral: false
            ),
            signedOutCase(reason: .initial, estimate: true),
            signedOutCase(reason: .initial, estimate: false),
            signedOutCase(reason: .reauthenticationRequired, estimate: true),
            signedOutCase(reason: .reauthenticationRequired, estimate: false),
            Case(
                name: "update required with reading",
                access: updateRequiredAccess,
                refresh: .idle,
                snapshot: estimate,
                expectedState: .updateRequired,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "Estimated from Claude Code's activity logs on this Mac",
                settingsSubtitle: "Update Claude Code to track plan usage · showing local estimate",
                settingsAction: .journey(.update),
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. Update Claude Code and PromptJuice switches to direct readings automatically.",
                popover: "PromptJuice needs Claude Code 2.1.208 or newer to read plan usage.",
                neutral: false
            ),
            Case(
                name: "update required without reading",
                access: updateRequiredAccess,
                refresh: .idle,
                snapshot: unavailable,
                expectedState: .updateRequired,
                showsReading: false,
                showsClock: false,
                rowStatus: "Update needed",
                tooltip: "Update Claude Code to read your plan usage",
                settingsSubtitle: "Update Claude Code to track plan usage",
                settingsAction: .journey(.update),
                footnote: nil,
                popover: "PromptJuice needs Claude Code 2.1.208 or newer to read plan usage.",
                neutral: false
            ),
            Case(
                name: "API billing",
                access: .apiBilling,
                refresh: .idle,
                snapshot: unavailable,
                expectedState: .apiBilling,
                showsReading: false,
                showsClock: false,
                rowStatus: "API billing",
                tooltip: "Claude Code is using API billing · plan quota unavailable",
                settingsSubtitle: "API billing · Claude Console tracks spend",
                settingsAction: nil,
                footnote: nil,
                popover: "Claude Code is using first-party API billing, which Claude Console tracks as spend. Plan quota doesn't apply, so there's no juice bar to fill.",
                neutral: true,
                popoverAction: .journey(.signIn)
            ),
            Case(
                name: "external provider",
                access: .externalProvider(.bedrock),
                refresh: .idle,
                snapshot: unavailable,
                expectedState: .externalProvider(.bedrock),
                showsReading: false,
                showsClock: false,
                rowStatus: "External provider",
                tooltip: "Claude Code uses Amazon Bedrock · plan quota unavailable",
                settingsSubtitle: "Amazon Bedrock · plan quota unavailable",
                settingsAction: nil,
                footnote: nil,
                popover: "Claude Code is set up to use Amazon Bedrock, which bills through your cloud account. Plan quota doesn't apply, so there's no juice bar to fill.",
                neutral: true
            ),
            Case(
                name: "unknown authentication",
                access: .unsupportedAuth,
                refresh: .idle,
                snapshot: unavailable,
                expectedState: .unsupportedAuth,
                showsReading: false,
                showsClock: false,
                rowStatus: "Usage unavailable",
                tooltip: "This Claude Code setup isn't supported yet",
                settingsSubtitle: "Account type not recognized · usage not tracked",
                settingsAction: nil,
                footnote: nil,
                popover: "Claude Code is signed in with an account type PromptJuice doesn't recognize yet, so usage tracking is off for it. A future update may add support.",
                neutral: true
            ),
            Case(
                name: "failure with cached reading",
                access: .subscription(plan: "Max"),
                refresh: .failed(.timeout),
                snapshot: cached,
                expectedState: .failure,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "From Claude Code · updated at \(savedTime) · having trouble updating",
                settingsSubtitle: "Having trouble updating · showing \(savedTime) reading",
                settingsAction: .retry,
                footnote: nil,
                popover: "PromptJuice couldn't get a new reading from Claude Code. It's showing your \(savedTime) reading and will keep trying.",
                neutral: false
            ),
            Case(
                name: "failure with estimate",
                access: .subscription(plan: "Max"),
                refresh: .failed(.parse),
                snapshot: estimate,
                expectedState: .failure,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "Couldn't check usage with Claude Code · trying again automatically",
                settingsSubtitle: "Estimate · having trouble reading Claude Code",
                settingsAction: .retry,
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. PromptJuice checks about every 15 minutes and switches back automatically.",
                popover: "PromptJuice couldn't get a new reading from Claude Code. It's showing a local estimate and will keep trying automatically.",
                neutral: false
            ),
            Case(
                name: "failure without reading",
                access: .authCheckFailed,
                refresh: .failed(.process),
                snapshot: unavailable,
                expectedState: .failure,
                showsReading: false,
                showsClock: false,
                rowStatus: "Having trouble checking",
                tooltip: "Couldn't check usage with Claude Code · trying again automatically",
                settingsSubtitle: "Having trouble checking usage",
                settingsAction: .retry,
                footnote: nil,
                popover: "PromptJuice couldn't check usage with Claude Code. It will keep trying automatically.",
                neutral: false
            ),
            Case(
                name: "provider off",
                access: .subscription(plan: "Max"),
                refresh: .idle,
                snapshot: snapshot(),
                isEnabled: false,
                expectedState: .off,
                showsReading: false,
                showsClock: false,
                rowStatus: nil,
                tooltip: nil,
                settingsSubtitle: "Off",
                settingsAction: nil,
                footnote: nil,
                popover: nil,
                neutral: false
            ),
        ]

        XCTAssertEqual(cases.count, 22)
        for testCase in cases {
            let presentation = ClaudeUsagePresentation.resolve(
                access: testCase.access,
                refresh: testCase.refresh,
                snapshot: testCase.snapshot,
                isEnabled: testCase.isEnabled,
                now: fixedNow
            )

            XCTAssertEqual(presentation.state, testCase.expectedState, testCase.name)
            XCTAssertEqual(presentation.showsReading, testCase.showsReading, testCase.name)
            XCTAssertEqual(presentation.showsClock, testCase.showsClock, testCase.name)
            XCTAssertEqual(presentation.rowStatus, testCase.rowStatus, testCase.name)
            XCTAssertEqual(presentation.tooltip, testCase.tooltip, testCase.name)
            XCTAssertEqual(presentation.settingsSubtitle, testCase.settingsSubtitle, testCase.name)
            XCTAssertEqual(presentation.settingsAction, testCase.settingsAction, testCase.name)
            XCTAssertEqual(presentation.estimateFootnote, testCase.footnote, testCase.name)
            XCTAssertEqual(presentation.popoverStatus, testCase.popover, testCase.name)
            XCTAssertEqual(presentation.popoverAction, testCase.popoverAction, testCase.name)
            XCTAssertEqual(presentation.isNeutral, testCase.neutral, testCase.name)
        }
    }

    func testFreshnessFormatterUsesFiveRequiredTiers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -4 * 60 * 60)!
        calendar.locale = Locale(identifier: "en_US")
        let formatter = ClaudeFreshnessFormatter(calendar: calendar)
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 21,
            hour: 16
        ))!

        XCTAssertEqual(formatter.title(for: now.addingTimeInterval(-20), now: now), "Updated just now")
        XCTAssertEqual(formatter.title(for: now.addingTimeInterval(-12 * 60), now: now), "Updated 12 min ago")
        XCTAssertEqual(formatter.title(for: now.addingTimeInterval(-2 * 60 * 60), now: now), "Updated at 2:00 PM")
        XCTAssertEqual(formatter.title(for: now.addingTimeInterval(-24 * 60 * 60), now: now), "Updated yesterday at 4:00 PM")
        XCTAssertEqual(formatter.title(for: now.addingTimeInterval(-3 * 24 * 60 * 60), now: now), "Updated Jul 18 at 4:00 PM")
        XCTAssertEqual(formatter.clause(for: now.addingTimeInterval(-12 * 60), now: now), "updated 12 min ago")
    }

    func testClaudeZeroUsageUsesStandardReadingAndCodexKeepsFreshEvidence() {
        let claude = snapshot(usedPercent: 0)
        let claudePresentation = ClaudeUsagePresentation.resolve(
            access: .subscription(plan: "Max"),
            refresh: .idle,
            snapshot: claude,
            isEnabled: true,
            now: fixedNow
        )
        let codex = ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: fixedNow,
            isFreshSessionWindow: true
        )

        XCTAssertEqual(claudePresentation.state, .current)
        XCTAssertEqual(claude.remainingPercent, 100)
        XCTAssertFalse(claude.isFreshSessionWindow)
        XCTAssertTrue(codex.isFreshSessionWindow)
    }

    private func signedOutCase(reason: ClaudeSignInReason, estimate: Bool) -> Case {
        let isInitial = reason == .initial
        let settingsSubtitle: String
        if isInitial {
            settingsSubtitle = estimate
                ? "Estimate · signed out of Claude Code"
                : "Signed out of Claude Code"
        } else {
            settingsSubtitle = estimate
                ? "Signed out of Claude Code · sign in again · showing local estimate"
                : "Signed out of Claude Code · sign in again"
        }
        return Case(
            name: "signed out \(reason.rawValue) \(estimate ? "with estimate" : "without reading")",
            access: .signedOut(reason: reason),
            refresh: .idle,
            snapshot: estimate ? snapshot(confidence: .estimated) : unavailableSnapshot(),
            expectedState: .signedOut(reason),
            showsReading: estimate,
            showsClock: false,
            rowStatus: estimate ? nil : "Sign in needed",
            tooltip: estimate
                ? "Estimated from Claude Code's activity logs on this Mac"
                : "Sign in to Claude Code to read your plan usage",
            settingsSubtitle: settingsSubtitle,
            settingsAction: .journey(.signIn),
            footnote: estimate
                ? (isInitial
                    ? "This is an estimate from Claude Code's activity logs on this Mac. Sign in to Claude Code and PromptJuice switches to direct readings automatically."
                    : "This is an estimate from Claude Code's activity logs on this Mac. Sign in to Claude Code again and PromptJuice switches back to direct readings automatically.")
                : nil,
            popover: isInitial
                ? "Claude Code is signed out. Sign in once and PromptJuice takes it from there."
                : "Claude Code's sign-in has expired. Sign in again and PromptJuice takes it from there.",
            neutral: false
        )
    }

    private var updateRequiredAccess: ClaudeAccessState {
        .updateRequired(
            installed: ClaudeCodeVersion(major: 2, minor: 0, patch: 14),
            minimum: .minimumUsageVersion
        )
    }

    private func snapshot(
        source: SnapshotSource = .claudeUsageCLI,
        confidence: SnapshotConfidence = .exact,
        usedPercent: Double = 58,
        updatedAt: Date? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: fixedNow.addingTimeInterval(150 * 60),
                durationMinutes: 300
            ),
            source: source,
            confidence: confidence,
            updatedAt: updatedAt ?? fixedNow
        )
    }

    private func unavailableSnapshot() -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: fixedNow
        )
    }

    private struct Case {
        let name: String
        let access: ClaudeAccessState
        let refresh: ClaudeRefreshState
        let snapshot: ProviderSnapshot?
        var isEnabled = true
        let expectedState: ClaudePresentationState
        let showsReading: Bool
        let showsClock: Bool
        let rowStatus: String?
        let tooltip: String?
        let settingsSubtitle: String
        let settingsAction: ClaudeSettingsAction?
        let footnote: String?
        let popover: String?
        let neutral: Bool
        var popoverAction: ClaudeSettingsAction? = nil
    }
}
