import AppKit
import XCTest
@testable import PromptJuice

@MainActor
final class PanelToolTipViewTests: XCTestCase {
    func testDrawsWordsAfterReadFromPrefix() throws {
        let text = "Read from Claude Code"
        let view = PanelToolTipView(text: text)
        view.appearance = NSAppearance(named: .darkAqua)

        let image = try render(view)
        let prefixWidth = ("Read from " as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 12)]
        ).width
        let startX = Int(ceil(8 + prefixWidth))
        let endX = min(image.pixelsWide, Int(floor(view.bounds.width - 8)))
        var brightPixels = 0

        for y in 0..<image.pixelsHigh {
            for x in startX..<endX {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if color.alphaComponent > 0.2, brightness > 0.5 {
                    brightPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(brightPixels, 20)
    }

    func testWrapsLongTooltipWithinPanelWidth() {
        let text = "Estimated from local Claude Code activity · send a message in Claude Code to see exact usage"
        let view = PanelToolTipView(text: text)

        XCTAssertLessThanOrEqual(view.fittingSize.width, 296)
        XCTAssertGreaterThan(view.fittingSize.height, 26)
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        let bounds = view.bounds
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
        view.cacheDisplay(in: bounds, to: image)
        return image
    }
}
