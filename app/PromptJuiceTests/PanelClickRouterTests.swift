import AppKit
import XCTest
@testable import PromptJuice

final class PanelClickRouterTests: XCTestCase {
    func testManualModeRoutesTwoProviderRowsInVisualOrder() {
        let providers: [UsageProvider] = [.claude, .codex]
        let bounds = panelBounds(mode: .manual, providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, mode: .manual, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertLessThan(rows[0].rect.minY, rows[1].rect.minY)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, mode: .manual, providers: providers), .provider(.claude))
        XCTAssertEqual(target(at: rows[1].rect.center, in: bounds, mode: .manual, providers: providers), .provider(.codex))
        XCTAssertNotEqual(
            target(at: rows[0].rect.center, in: bounds, mode: .manual, providers: providers),
            target(at: rows[1].rect.center, in: bounds, mode: .manual, providers: providers)
        )

        assertRowEdges(rows[0].rect, routeTo: .claude, in: bounds, mode: .manual, providers: providers)
        assertRowEdges(rows[1].rect, routeTo: .codex, in: bounds, mode: .manual, providers: providers)
        XCTAssertEqual(target(at: closeCenter(in: bounds), in: bounds, mode: .manual, providers: providers), .close)
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: 28), in: bounds, mode: .manual, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: (rows[0].rect.maxY + rows[1].rect.minY) / 2), in: bounds, mode: .manual, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: 6, y: rows[0].rect.midY), in: bounds, mode: .manual, providers: providers))
    }

    func testAlertModeRoutesRowsAndSnooze() {
        let providers: [UsageProvider] = [.claude, .codex]
        let bounds = panelBounds(mode: .alert, providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, mode: .alert, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, mode: .alert, providers: providers), .provider(.claude))
        XCTAssertEqual(target(at: rows[1].rect.center, in: bounds, mode: .alert, providers: providers), .provider(.codex))
        XCTAssertNotEqual(
            target(at: rows[0].rect.center, in: bounds, mode: .alert, providers: providers),
            target(at: rows[1].rect.center, in: bounds, mode: .alert, providers: providers)
        )

        assertRowEdges(rows[0].rect, routeTo: .claude, in: bounds, mode: .alert, providers: providers)
        assertRowEdges(rows[1].rect, routeTo: .codex, in: bounds, mode: .alert, providers: providers)
        XCTAssertEqual(target(at: closeCenter(in: bounds), in: bounds, mode: .alert, providers: providers), .close)
        XCTAssertEqual(target(at: snoozeCenter(in: bounds), in: bounds, mode: .alert, providers: providers), .snooze)
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: 28), in: bounds, mode: .alert, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: (rows[0].rect.maxY + rows[1].rect.minY) / 2), in: bounds, mode: .alert, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: 6, y: rows[0].rect.midY), in: bounds, mode: .alert, providers: providers))
    }

    func testManualModeRoutesSingleProviderRows() {
        assertSingleProvider(.claude)
        assertSingleProvider(.codex)
    }

    private func assertSingleProvider(_ provider: UsageProvider) {
        let providers = [provider]
        let bounds = panelBounds(mode: .manual, providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, mode: .manual, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, mode: .manual, providers: providers), .provider(provider))
        assertRowEdges(rows[0].rect, routeTo: provider, in: bounds, mode: .manual, providers: providers)
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: 28), in: bounds, mode: .manual, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: rows[0].rect.minY - 4), in: bounds, mode: .manual, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: 6, y: rows[0].rect.midY), in: bounds, mode: .manual, providers: providers))
    }

    private func assertRowEdges(
        _ rect: NSRect,
        routeTo provider: UsageProvider,
        in bounds: NSRect,
        mode: PanelMode,
        providers: [UsageProvider]
    ) {
        XCTAssertEqual(target(at: NSPoint(x: rect.midX, y: rect.minY), in: bounds, mode: mode, providers: providers), .provider(provider))
        XCTAssertEqual(target(at: NSPoint(x: rect.midX, y: rect.maxY), in: bounds, mode: mode, providers: providers), .provider(provider))
    }

    private func target(
        at point: NSPoint,
        in bounds: NSRect,
        mode: PanelMode,
        providers: [UsageProvider]
    ) -> PanelClickTarget? {
        PanelClickRouter.target(at: point, in: bounds, mode: mode, providers: providers)
    }

    private func panelBounds(mode: PanelMode, providerCount: Int) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(mode: mode, rowCount: providerCount)
        )
    }

    private func closeCenter(in bounds: NSRect) -> NSPoint {
        NSPoint(x: bounds.width - 32, y: 32)
    }

    private func snoozeCenter(in bounds: NSRect) -> NSPoint {
        NSPoint(x: bounds.midX, y: bounds.height - 27)
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
