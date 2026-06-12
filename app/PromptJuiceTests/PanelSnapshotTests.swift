import SwiftUI
import XCTest
@testable import PromptJuice

/// Offscreen render of the real `PromptJuicePanelView` across the three
/// severity states. Skipped by default; run with PROMPTJUICE_SNAPSHOT=1 to
/// write PNGs to /tmp for visual review.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRenderPanelSnapshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTJUICE_SNAPSHOT"] == "1",
            "Set PROMPTJUICE_SNAPSHOT=1 to render panel snapshots."
        )

        try render("healthy", FixtureUsageProviderClient(scenario: .quiet))
        try render("usesoon", FixtureUsageProviderClient(scenario: .underusedCodex))
        try render("low", LowFixtureClient())
        try render("estimate", EstimateFixtureClient())
        try render("notmeasured", NotMeasuredFixtureClient())
        try render("clash", ClashFixtureClient())
    }

    private func render(_ name: String, _ client: any UsageProviderClient) throws {
        let viewModel = PromptJuiceViewModel(providerClient: client, now: { self.now })
        viewModel.showManualCheck()

        let content = ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            PromptJuicePanelView(viewModel: viewModel, onClose: {}, onSnooze: {})
                .padding(40)
        }
        .frame(width: 464, height: 246)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        guard
            let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw XCTSkip("ImageRenderer produced no image on this platform.")
        }

        let url = URL(fileURLWithPath: "/tmp/promptjuice-panel-\(name).png")
        try png.write(to: url)
        print("wrote \(url.path)")
    }
}

private func codexExact(_ now: Date, usedPercent: Double = 1) -> ProviderSnapshot {
    ProviderSnapshot(
        identity: .codex,
        rateWindow: .available(
            usedPercent: usedPercent,
            resetAt: now.addingTimeInterval(180 * 60),
            durationMinutes: 300
        ),
        source: .codexAppServer,
        confidence: .exact,
        updatedAt: now
    )
}

private struct LowFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 94,
                    resetAt: now.addingTimeInterval(12 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 42,
                    resetAt: now.addingTimeInterval(180 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}

private struct EstimateFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeLocalLogs

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 65,
                    resetAt: now.addingTimeInterval(100 * 60),
                    durationMinutes: 300
                ),
                source: .claudeLocalLogs,
                confidence: .estimated,
                updatedAt: now
            ),
            codexExact(now)
        ]
    }
}

private struct NotMeasuredFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .claudeStatusline

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .unavailable,
                source: .claudeStatusline,
                confidence: .unavailable,
                updatedAt: now,
                statusDetail: "Claude statusline and local usage unavailable"
            ),
            codexExact(now)
        ]
    }
}

private struct ClashFixtureClient: UsageProviderClient {
    let source: SnapshotSource = .fixture

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .claude,
                rateWindow: .available(
                    usedPercent: 22,
                    resetAt: now.addingTimeInterval(20 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            ),
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .available(
                    usedPercent: 92,
                    resetAt: now.addingTimeInterval(180 * 60),
                    durationMinutes: 300
                ),
                source: .fixture,
                confidence: .exact,
                updatedAt: now
            )
        ]
    }
}
