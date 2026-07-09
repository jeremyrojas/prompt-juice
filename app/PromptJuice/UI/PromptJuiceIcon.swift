import AppKit

enum PromptJuiceIcon {
    /// Live menu-bar glyph: a droplet whose juice level encodes the remaining
    /// capacity, like the battery icon but juice. Healthy renders as a system
    /// template (tinted white/black by the bar); the use-soon nudge renders in
    /// amber, matching the panel.
    static func statusBarImage(
        remaining: Double = 1,
        severity: UsageSeverity = .healthy
    ) -> NSImage? {
        let level = quantizedRemaining(remaining)
        let tint = severity.menuBarTint
        let size = NSSize(width: 18, height: 18)

        let image = NSImage(size: size, flipped: true) { rect in
            drawGlyph(in: rect, remaining: level, color: tint ?? .black)
            return true
        }

        // Healthy → template so the system tints it for light/dark/active bars.
        // Alert states carry their own color and opt out of templating.
        image.isTemplate = (tint == nil)
        image.accessibilityDescription = "PromptJuice"
        return image
    }

    /// Quantize to 10 steps so the level reads as deliberate jumps, not
    /// sub-pixel jitter — and so the narrow tip near 100% still reads.
    private static func quantizedRemaining(_ remaining: Double) -> Double {
        let clamped = min(1, max(0, remaining))
        return (clamped * 10).rounded() / 10
    }

    private static func drawGlyph(in rect: NSRect, remaining: Double, color: NSColor) {
        let body = NSRect(
            x: rect.width * 0.18,
            y: rect.height * 0.05,
            width: rect.width * 0.64,
            height: rect.height * 0.90
        )
        let outline = dropletPath(in: body)

        if remaining >= DropletGeometry.solidFillThreshold {
            color.setFill()
            outline.fill()
        } else if remaining > 0 {
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            color.setFill()
            wavePath(in: body, remaining: remaining).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        color.setStroke()
        outline.lineWidth = max(1, body.width * 0.11)
        outline.lineJoinStyle = .round
        outline.stroke()
    }

    /// Droplet outline from the shared `DropletGeometry`, drawn in a flipped
    /// (y-down) context so the same fractions as the SwiftUI gauge apply.
    private static func dropletPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: DropletGeometry.point(DropletGeometry.tip, in: rect))

        for segment in DropletGeometry.segments {
            path.curve(
                to: DropletGeometry.point(segment.2, in: rect),
                controlPoint1: DropletGeometry.point(segment.0, in: rect),
                controlPoint2: DropletGeometry.point(segment.1, in: rect)
            )
        }

        path.close()
        return path
    }

    private static func wavePath(in rect: NSRect, remaining: Double) -> NSBezierPath {
        let y = rect.minY + DropletGeometry.waterline(forRemaining: remaining) * rect.height
        let amplitude = rect.height * 0.02

        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.curve(
            to: NSPoint(x: rect.maxX, y: y),
            controlPoint1: NSPoint(x: rect.minX + rect.width * 0.33, y: y - amplitude),
            controlPoint2: NSPoint(x: rect.minX + rect.width * 0.66, y: y + amplitude)
        )
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    static func appIconImage(size: CGFloat = 128) -> NSImage? {
        guard
            let mascotURL = Bundle.main.url(
                forResource: "PromptJuiceMascot",
                withExtension: "png"
            ),
            let mascot = NSImage(contentsOf: mascotURL)
        else {
            return nil
        }

        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            mascot.draw(
                in: rect,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            return true
        }
    }
}
