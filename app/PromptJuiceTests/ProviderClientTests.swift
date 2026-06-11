import XCTest
@testable import PromptJuice

final class ProviderClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDemoProviderReturnsNormalizedSnapshots() {
        let snapshots = DemoProviderClient(scenario: .underusedCodex)
            .snapshots(now: now)

        XCTAssertEqual(snapshots.map(\.identity), [.claude, .codex])
        XCTAssertEqual(snapshots.map(\.source), [.demo, .demo])
        XCTAssertEqual(snapshots.map(\.confidence), [.exact, .exact])
        XCTAssertEqual(snapshots[1].remainingPercent, 69)
        XCTAssertEqual(snapshots[1].rateWindow.minutesUntilReset(now: now), 52)
    }

    func testCodexProviderShellReturnsUnavailableSnapshot() {
        let snapshots = CodexProviderClient().snapshots(now: now)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].identity, .codex)
        XCTAssertEqual(snapshots[0].source, .codexStub)
        XCTAssertEqual(snapshots[0].confidence, .unavailable)
        XCTAssertEqual(snapshots[0].rateWindow, .unavailable)
        XCTAssertEqual(snapshots[0].updatedAt, now)
    }
}
