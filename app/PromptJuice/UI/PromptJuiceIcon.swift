import AppKit

enum PromptJuiceIcon {
    static func statusBarImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "drop.fill",
            accessibilityDescription: "PromptJuice"
        )
        image?.isTemplate = true
        return image
    }

    static func appIconImage(size: CGFloat = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer {
            image.unlockFocus()
        }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.22
        let background = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.08, alpha: 1),
                NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.14, alpha: 1),
                NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)
            ]
        )?.draw(in: background, angle: -45)

        let glow = NSBezierPath(ovalIn: NSRect(
            x: size * 0.16,
            y: size * 0.56,
            width: size * 0.52,
            height: size * 0.32
        ))
        NSColor(calibratedRed: 0.22, green: 0.82, blue: 1, alpha: 0.18).setFill()
        glow.fill()

        let drop = NSBezierPath()
        drop.move(to: NSPoint(x: size * 0.50, y: size * 0.80))
        drop.curve(
            to: NSPoint(x: size * 0.24, y: size * 0.42),
            controlPoint1: NSPoint(x: size * 0.38, y: size * 0.66),
            controlPoint2: NSPoint(x: size * 0.24, y: size * 0.55)
        )
        drop.curve(
            to: NSPoint(x: size * 0.50, y: size * 0.18),
            controlPoint1: NSPoint(x: size * 0.24, y: size * 0.27),
            controlPoint2: NSPoint(x: size * 0.36, y: size * 0.18)
        )
        drop.curve(
            to: NSPoint(x: size * 0.76, y: size * 0.42),
            controlPoint1: NSPoint(x: size * 0.64, y: size * 0.18),
            controlPoint2: NSPoint(x: size * 0.76, y: size * 0.27)
        )
        drop.curve(
            to: NSPoint(x: size * 0.50, y: size * 0.80),
            controlPoint1: NSPoint(x: size * 0.76, y: size * 0.55),
            controlPoint2: NSPoint(x: size * 0.62, y: size * 0.66)
        )
        drop.close()

        NSGradient(
            colors: [
                NSColor(calibratedRed: 0.24, green: 0.88, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.09, green: 0.52, blue: 1, alpha: 1)
            ]
        )?.draw(in: drop, angle: 90)

        let shine = NSBezierPath(ovalIn: NSRect(
            x: size * 0.39,
            y: size * 0.56,
            width: size * 0.16,
            height: size * 0.16
        ))
        NSColor.white.withAlphaComponent(0.34).setFill()
        shine.fill()

        return image
    }
}
