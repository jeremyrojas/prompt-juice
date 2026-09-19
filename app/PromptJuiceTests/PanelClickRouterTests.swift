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
        XCTAssertLessThan(rows[1].rect.maxY, bounds.height)
        XCTAssertEqual(
            bounds.height,
            PromptJuicePanelMetrics.height(windowCounts: [0, 0])
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

    func testRoutesNotificationPrimeButtonsOnlyWhenShown() {
        let providers: [UsageProvider] = [.claude, .codex]
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(
                windowCounts: [0, 0],
                showsNotificationPrime: true
            )
        )
        let rects = PanelClickRouter.notificationPrimeButtonRects(
            in: bounds,
            windowCounts: [0, 0]
        )

        XCTAssertEqual(
            PanelClickRouter.target(
                at: rects.enable.center,
                in: bounds,
                providers: providers,
                showsNotificationPrime: true
            ),
            .enableNotifications
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: rects.dismiss.center,
                in: bounds,
                providers: providers,
                showsNotificationPrime: true
            ),
            .dismissNotificationPrime
        )

        // With the prime hidden, those same points must not route to it.
        XCTAssertNotEqual(
            PanelClickRouter.target(
                at: rects.enable.center,
                in: bounds,
                providers: providers,
                showsNotificationPrime: false
            ),
            .enableNotifications
        )

        // The banner buttons sit clear of the rows above and panel bottom.
        let rows = PanelClickRouter.rowRects(in: bounds, providers: providers)
        XCTAssertGreaterThan(rects.enable.minY, rows[1].rect.maxY)
        XCTAssertLessThan(rects.enable.maxY, bounds.height - PromptJuicePanelMetrics.contentPadding)
        XCTAssertGreaterThan(rects.dismiss.minX, 0)
        XCTAssertLessThan(rects.enable.maxX, bounds.width)
    }

    func testExpandableProviderHeaderRoutesToDisclosureAcrossItsFullWidth() {
        let providers: [UsageProvider] = [.claude, .codex]
        let counts = [3, 1]
        let expandableProviders: Set<UsageProvider> = [.claude]
        let bounds = NSRect(
            x: 0,
            y: 0,
            width: PromptJuicePanelMetrics.width,
            height: PromptJuicePanelMetrics.height(windowCounts: counts)
        )
        let rows = PanelClickRouter.rowRects(
            in: bounds,
            providers: providers,
            windowCounts: counts
        )
        XCTAssertEqual(rows.map(\.rect.height), [
            PromptJuicePanelMetrics.cardHeight(windowCount: 3),
            PromptJuicePanelMetrics.cardHeight(windowCount: 1)
        ])
        XCTAssertGreaterThan(rows[1].rect.minY, rows[0].rect.maxY)

        for x in [rows[0].rect.minX + 8, rows[0].rect.midX, rows[0].rect.maxX - 8] {
            XCTAssertEqual(
                PanelClickRouter.target(
                    at: NSPoint(x: x, y: rows[0].rect.minY + 20),
                    in: bounds,
                    providers: providers,
                    windowCounts: counts,
                    expandableProviders: expandableProviders
                ),
                .disclosure(.claude)
            )
        }

        XCTAssertEqual(
            PanelClickRouter.target(
                at: NSPoint(x: rows[0].rect.midX, y: rows[0].rect.maxY - 12),
                in: bounds,
                providers: providers,
                windowCounts: counts,
                expandableProviders: expandableProviders
            ),
            .provider(.claude)
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: NSPoint(x: rows[1].rect.maxX - 20, y: rows[1].rect.minY + 20),
                in: bounds,
                providers: providers,
                windowCounts: counts,
                expandableProviders: expandableProviders
            ),
            .provider(.codex)
        )
        XCTAssertEqual(
            PanelClickRouter.target(
                at: NSPoint(x: rows[1].rect.minX + 8, y: rows[1].rect.minY + 20),
                in: bounds,
                providers: providers,
                windowCounts: counts,
                expandableProviders: [.claude, .codex]
            ),
            .disclosure(.codex)
        )
    }

    private func assertSingleProvider(_ provider: UsageProvider) {
        let providers = [provider]
        let bounds = panelBounds(providerCount: providers.count)
        let rows = PanelClickRouter.rowRects(in: bounds, providers: providers)

        XCTAssertEqual(rows.map(\.provider), providers)
        XCTAssertEqual(target(at: rows[0].rect.center, in: bounds, providers: providers), .provider(provider))
        assertRowEdges(rows[0].rect, routeTo: provider, in: bounds, providers: providers)
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
                windowCounts: Array(repeating: 0, count: providerCount)
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
