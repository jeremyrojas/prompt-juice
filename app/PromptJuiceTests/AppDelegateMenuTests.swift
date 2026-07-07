import AppKit
import XCTest
@testable import PromptJuice

@MainActor
final class AppDelegateMenuTests: XCTestCase {
    func testContextMenuOmitsManualRefreshItem() {
        let menu = AppDelegate.makeContextMenu(target: NSObject())
        let nonSeparatorItems = menu.items.filter { !$0.isSeparatorItem }

        XCTAssertEqual(nonSeparatorItems.map(\.title), [
            "Show Usage",
            "Settings…",
            "Quit PromptJuice"
        ])
        XCTAssertFalse(menu.items.contains { $0.title == "Refresh Usage" })
        XCTAssertFalse(menu.items.contains { $0.keyEquivalent == "r" })
    }
}
