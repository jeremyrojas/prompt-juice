import AppKit
import XCTest
@testable import PromptJuice

final class PanelClickRouterTests: XCTestCase {
    func testRoutesTwoProviderRowsInVisualOrder() {
        let providers: [UsageProvider] = [.claude, .codex]
        let bounds = panelBounds(providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertLessThan(rows[0].rect.minY, rows[1].rect.minY)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, providers: providers), .provider(.claude))
        XCTAssertEqual(target(at: rows[1].rect.center, in: bounds, providers: providers), .provider(.codex))
        XCTAssertNotEqual(
            target(at: rows[0].rect.center, in: bounds, providers: providers),
            target(at: rows[1].rect.center, in: bounds, providers: providers)
        )

        assertRowEdges(rows[0].rect, routeTo: .claude, in: bounds, providers: providers)
        assertRowEdges(rows[1].rect, routeTo: .codex, in: bounds, providers: providers)
        XCTAssertEqual(target(at: closeCenter(in: bounds), in: bounds, providers: providers), .close)
        XCTAssertEqual(target(at: PanelClickRouter.settingsRect(in: bounds).center, in: bounds, providers: providers), .settings)
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: 28), in: bounds, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: (rows[0].rect.maxY + rows[1].rect.minY) / 2), in: bounds, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: 6, y: rows[0].rect.midY), in: bounds, providers: providers))
    }

    func testRoutesSingleProviderRows() {
        assertSingleProvider(.claude)
        assertSingleProvider(.codex)
    }

    func testKeepsRowsFixedHeight() {
        let providers: [UsageProvider] = [.claude, .codex]
        let bounds = panelBounds(providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(
            in: bounds,
            providers: providers
        )

        XCTAssertEqual(rows[0].rect.height, PromptJuicePanelMetrics.plainRowHeight)
        XCTAssertEqual(rows[1].rect.height, PromptJuicePanelMetrics.plainRowHeight)
        XCTAssertEqual(
            bounds.height,
            63
                + PromptJuicePanelMetrics.plainRowHeight * 2
                + PromptJuicePanelMetrics.rowSpacing
                + PromptJuicePanelMetrics.settingsHeightIncrement
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[0].rect.center,
                in: bounds,
                providers: providers
            ),
            .provider(.claude)
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rows[1].rect.center,
                in: bounds,
                providers: providers
            ),
            .provider(.codex)
        )
    }

    private func assertSingleProvider(_ provider: UsageProvider) {
        let providers = [provider]
        let bounds = panelBounds(providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, providers: providers), .provider(provider))
        assertRowEdges(rows[0].rect, routeTo: provider, in: bounds, providers: providers)
        XCTAssertEqual(target(at: PanelClickRouter.settingsRect(in: bounds).center, in: bounds, providers: providers), .settings)
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: 28), in: bounds, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: bounds.midX, y: rows[0].rect.minY - 4), in: bounds, providers: providers))
        XCTAssertNil(target(at: NSPoint(x: 6, y: rows[0].rect.midY), in: bounds, providers: providers))
    }

    private func assertRowEdges(
        _ rect: NSRect,
        routeTo provider: UsageProvider,
        in bounds: NSRect,
        providers: [UsageProvider]
    ) {
        XCTAssertEqual(target(at: NSPoint(x: rect.midX, y: rect.minY), in: bounds, providers: providers), .provider(provider))
        XCTAssertEqual(target(at: NSPoint(x: rect.midX, y: rect.maxY), in: bounds, providers: providers), .provider(provider))
    }

    private func target(
        at point: NSPoint,
        in bounds: NSRect,
        providers: [UsageProvider]
    ) -> PanelClickTarget? {
        PanelClickRouter.target(at: point, in: bounds, providers: providers)
    }

    private func panelBounds(providerCount: Int) -> NSRect {
        NSRect(
            x: 0,
            y: 0,
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(
                rowCount: providerCount
            )
        )
    }

    private func closeCenter(in bounds: NSRect) -> NSPoint {
        NSPoint(x: bounds.width - 32, y: 32)
    }

}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
