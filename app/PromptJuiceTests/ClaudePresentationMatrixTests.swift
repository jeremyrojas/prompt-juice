import XCTest
@testable import PromptJuice

@MainActor
final class ClaudePresentationMatrixTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let staleUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000 - 10 * 60)

    func testClaudePresentationMatrix() {
        let staleTime = clockTime(staleUpdatedAt)
        let cases: [Case] = [
            Case(
                name: "exact statusline",
                claudeSnapshot: claudeSnapshot(
                    source: .claudeStatusline,
                    confidence: .exact
                ),
                bridgeCurrent: false,
                liveUpgrade: .live,
                settingsStatus: "Live",
                setupButtonTitle: nil,
                tooltip: "Read from Claude Code",
                popover: "Right now it's exact, current as of your last terminal session.",
                displayPercent: "42%",
                headerDetailIncludes: ["Claude 42%", "Codex 80%", "resets in 2h 30m"],
                headerDetailExcludes: ["Claude ~42%"],
                claudeSeverity: .healthy,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 42,
                setupWouldOpen: false
            ),
            Case(
                name: "estimate with bridge missing",
                claudeSnapshot: claudeSnapshot(
                    source: .claudeLocalLogs,
                    confidence: .estimated
                ),
                bridgeCurrent: false,
                liveUpgrade: .setupAvailable,
                settingsStatus: "Estimate",
                setupButtonTitle: "Set up live readings",
                tooltip: "Estimated from local Claude Code activity · open Settings to set up live",
                popover: "Right now it's estimating. Set up live readings, then use Claude Code in the terminal for exact numbers.",
                displayPercent: "~42%",
                headerDetailIncludes: ["Claude ~42%", "Codex 80%", "resets in 2h 30m"],
                headerDetailExcludes: ["Claude 42%"],
                claudeSeverity: .healthy,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 42,
                setupWouldOpen: true
            ),
            Case(
                name: "estimate with bridge current",
                claudeSnapshot: claudeSnapshot(
                    source: .claudeLocalLogs,
                    confidence: .estimated
                ),
                bridgeCurrent: true,
                liveUpgrade: .awaitingSession,
                settingsStatus: "Estimate",
                setupButtonTitle: nil,
                tooltip: "Estimated from local Claude Code activity",
                popover: "Showing a local Claude Code estimate. Exact usage replaces it when Claude Code sends a current rate-limit window.",
                displayPercent: "~42%",
                headerDetailIncludes: ["Claude ~42%", "Codex 80%", "resets in 2h 30m"],
                headerDetailExcludes: ["Claude 42%"],
                claudeSeverity: .healthy,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 42,
                setupWouldOpen: false
            ),
            Case(
                name: "stale last exact reading",
                claudeSnapshot: claudeSnapshot(
                    source: .claudeCache,
                    confidence: .stale,
                    updatedAt: staleUpdatedAt
                ),
                bridgeCurrent: false,
                liveUpgrade: .setupAvailable,
                settingsStatus: "Read earlier · \(staleTime)",
                setupButtonTitle: "Set up live readings",
                tooltip: "Read from Claude Code · \(staleTime)",
                popover: "Right now it's showing your last exact reading from \(staleTime). Claude Code will replace it when the statusline sends a current window.",
                displayPercent: "42%",
                headerDetailIncludes: ["Claude 42%", "Codex 80%", "resets in 2h 30m"],
                headerDetailExcludes: ["Claude ~42%"],
                claudeSeverity: .healthy,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 42,
                setupWouldOpen: true
            ),
            Case(
                name: "unavailable with bridge missing",
                claudeSnapshot: unavailableClaudeSnapshot(),
                bridgeCurrent: false,
                liveUpgrade: .setupAvailable,
                settingsStatus: "Not set up yet",
                setupButtonTitle: "Set Up…",
                tooltip: "Claude statusline and local usage unavailable",
                popover: "It's not set up yet. Set it up, then use Claude Code in the terminal for exact numbers.",
                displayPercent: "n/a",
                headerDetailIncludes: ["Claude not set up", "Codex 80%", "resets in 3h 0m"],
                headerDetailExcludes: ["Claude ~", "Claude 0%"],
                claudeSeverity: .unavailable,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 80,
                setupWouldOpen: true
            ),
            Case(
                name: "unavailable with bridge current",
                claudeSnapshot: unavailableClaudeSnapshot(),
                bridgeCurrent: true,
                liveUpgrade: .awaitingSession,
                settingsStatus: "Waiting for Claude statusline",
                setupButtonTitle: nil,
                tooltip: "You're set up · waiting for Claude Code usage",
                popover: "You're set up. PromptJuice is waiting for Claude Code's next statusline window.",
                displayPercent: "n/a",
                headerDetailIncludes: ["Claude waiting for terminal", "Codex 80%", "resets in 3h 0m"],
                headerDetailExcludes: ["Claude not set up", "Claude ~", "Claude 0%"],
                claudeSeverity: .unavailable,
                aggregateSeverity: .healthy,
                headerRemainingPercent: 80,
                setupWouldOpen: false
            )
        ]

        for testCase in cases {
            let viewModel = makeViewModel(
                claudeSnapshot: testCase.claudeSnapshot,
                bridgeCurrent: testCase.bridgeCurrent
            )
            viewModel.showManualCheck()
            let claude = viewModel.snapshots.first { $0.provider == .claude }!

            XCTAssertEqual(viewModel.claudeLiveUpgrade, testCase.liveUpgrade, testCase.name)
            XCTAssertEqual(viewModel.settingsStatusText(for: .claude), testCase.settingsStatus, testCase.name)
            XCTAssertEqual(viewModel.claudeSetupButtonTitle, testCase.setupButtonTitle, testCase.name)
            XCTAssertEqual(viewModel.sourceTooltip(for: claude), testCase.tooltip, testCase.name)
            XCTAssertEqual(viewModel.claudeMeasurementPopoverDetail, testCase.popover, testCase.name)
            XCTAssertEqual(viewModel.remainingPercentDisplayValueText(for: claude), testCase.displayPercent, testCase.name)
            XCTAssertEqual(viewModel.severity(for: claude), testCase.claudeSeverity, testCase.name)
            XCTAssertEqual(viewModel.aggregateSeverity, testCase.aggregateSeverity, testCase.name)
            XCTAssertEqual(viewModel.headerSeverity, testCase.aggregateSeverity, testCase.name)
            XCTAssertEqual(viewModel.menuBarSeverity, testCase.aggregateSeverity, testCase.name)
            XCTAssertEqual(viewModel.headerRemainingPercent, testCase.headerRemainingPercent, accuracy: 0.001, testCase.name)
            XCTAssertEqual(viewModel.menuBarRemainingPercent, testCase.headerRemainingPercent, accuracy: 0.001, testCase.name)
            XCTAssertEqual(viewModel.claudeLiveUpgrade == .setupAvailable, testCase.setupWouldOpen, testCase.name)

            for expected in testCase.headerDetailIncludes {
                XCTAssertTrue(
                    viewModel.detail.contains(expected),
                    "\(testCase.name) should include \(expected) in \(viewModel.detail)"
                )
            }

            for unexpected in testCase.headerDetailExcludes {
                XCTAssertFalse(
                    viewModel.detail.contains(unexpected),
                    "\(testCase.name) should exclude \(unexpected) from \(viewModel.detail)"
                )
            }
        }
    }

    func testUseSoonSeverityDrivesHeaderColorAndFill() {
        let viewModel = makeViewModel(
            claudeSnapshot: claudeSnapshot(
                source: .claudeStatusline,
                confidence: .exact,
                usedPercent: 57,
                resetMinutes: 42
            ),
            codexSnapshot: codexSnapshot(usedPercent: 31, resetMinutes: 52),
            bridgeCurrent: false
        )

        viewModel.showManualCheck()

        XCTAssertEqual(viewModel.aggregateSeverity, .useSoon)
        XCTAssertEqual(viewModel.headerSeverity, .useSoon)
        XCTAssertEqual(viewModel.menuBarSeverity, .useSoon)
        XCTAssertEqual(viewModel.headerRemainingPercent, 69, accuracy: 0.001)
        XCTAssertEqual(viewModel.menuBarRemainingPercent, 69, accuracy: 0.001)
        XCTAssertEqual(viewModel.headline, "Use prompt juice soon")
        XCTAssertTrue(viewModel.detail.contains("Claude 43%"))
        XCTAssertTrue(viewModel.detail.contains("Codex 69%"))
    }

    func testFreshSessionWithWeeklyCarryForwardPresentation() {
        let weeklyUpdatedAt = fixedNow.addingTimeInterval(-9 * 60 * 60)
        let weeklyResetAt = fixedNow.addingTimeInterval(4 * 24 * 60 * 60)
        let viewModel = makeViewModel(
            claudeSnapshot: ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                weeklyWindow: .available(
                    usedPercent: 30,
                    resetAt: weeklyResetAt,
                    durationMinutes: 10_080
                ),
                source: .claudeStatusline,
                confidence: .stale,
                updatedAt: weeklyUpdatedAt,
                weeklyUpdatedAt: weeklyUpdatedAt,
                statusDetail: "Fresh window",
                isFreshSessionWindow: true
            ),
            bridgeCurrent: true
        )

        viewModel.showManualCheck()
        let claude = viewModel.snapshots.first { $0.provider == .claude }!

        XCTAssertEqual(viewModel.claudeLiveUpgrade, .live)
        XCTAssertEqual(viewModel.settingsStatusText(for: .claude), "Fresh window")
        XCTAssertEqual(viewModel.sourceTooltip(for: claude), "Fresh window · starts with your next Claude Code message")
        XCTAssertEqual(viewModel.claudeMeasurementPopoverDetail, "Fresh window. Usage starts with your next Claude Code message.")
        XCTAssertEqual(viewModel.remainingPercentDisplayValueText(for: claude), "70%")
        XCTAssertEqual(viewModel.severity(for: claude), .healthy)
        XCTAssertEqual(viewModel.menuBarRemainingPercent, 70, accuracy: 0.001)
        XCTAssertEqual(
            viewModel.weeklyText(for: claude),
            "Week: 70% left · resets 4d · as of \(clockTime(weeklyUpdatedAt))"
        )
        XCTAssertTrue(viewModel.detail.contains("Claude Fresh window"))
    }

    func testFreshWeeklyPresentation() {
        let viewModel = makeViewModel(
            claudeSnapshot: ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 5,
                    resetAt: fixedNow.addingTimeInterval(2 * 60 * 60),
                    durationMinutes: 300
                ),
                weeklyWindow: nil,
                source: .claudeStatusline,
                confidence: .exact,
                updatedAt: fixedNow,
                weeklyUpdatedAt: staleUpdatedAt,
                isFreshWeeklyWindow: true
            ),
            bridgeCurrent: true
        )

        let claude = viewModel.snapshots.first { $0.provider == .claude }!

        XCTAssertEqual(viewModel.weeklyText(for: claude), "Week: 100% left · fresh week")
        XCTAssertEqual(viewModel.remainingPercentDisplayValueText(for: claude), "95%")
    }

    private func makeViewModel(
        claudeSnapshot: ProviderSnapshot,
        codexSnapshot: ProviderSnapshot? = nil,
        bridgeCurrent: Bool
    ) -> PromptJuiceViewModel {
        let suiteName = "ClaudePresentationMatrixTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = PromptJuiceSettingsStore(defaults: defaults)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return PromptJuiceViewModel(
            settingsStore: store,
            providerClient: StaticUsageProviderClient(
                storedSnapshots: [claudeSnapshot, codexSnapshot ?? self.codexSnapshot()]
            ),
            now: { self.fixedNow },
            isClaudeBridgeCurrent: { bridgeCurrent }
        )
    }

    private func claudeSnapshot(
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        usedPercent: Double = 58,
        resetMinutes: Int = 150,
        updatedAt: Date? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: fixedNow.addingTimeInterval(TimeInterval(resetMinutes * 60)),
                durationMinutes: 300
            ),
            source: source,
            confidence: confidence,
            updatedAt: updatedAt ?? fixedNow
        )
    }

    private func unavailableClaudeSnapshot() -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeStatusline,
            confidence: .unavailable,
            updatedAt: fixedNow,
            statusDetail: "Claude statusline and local usage unavailable"
        )
    }

    private func codexSnapshot(
        usedPercent: Double = 20,
        resetMinutes: Int = 180
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: fixedNow.addingTimeInterval(TimeInterval(resetMinutes * 60)),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: fixedNow
        )
    }

    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private struct Case {
        let name: String
        let claudeSnapshot: ProviderSnapshot
        let bridgeCurrent: Bool
        let liveUpgrade: ClaudeLiveUpgrade
        let settingsStatus: String
        let setupButtonTitle: String?
        let tooltip: String
        let popover: String
        let displayPercent: String
        let headerDetailIncludes: [String]
        let headerDetailExcludes: [String]
        let claudeSeverity: UsageSeverity
        let aggregateSeverity: UsageSeverity
        let headerRemainingPercent: Double
        let setupWouldOpen: Bool
    }

    private struct StaticUsageProviderClient: UsageProviderClient {
        let source: SnapshotSource = .fixture
        let storedSnapshots: [ProviderSnapshot]

        func snapshots(now _: Date) -> [ProviderSnapshot] {
            storedSnapshots
        }
    }
}
