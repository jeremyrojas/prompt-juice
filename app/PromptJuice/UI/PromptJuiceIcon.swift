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

    static func appIconImage(size: CGFloat = 128) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            drawAppIcon(in: rect, detail: size >= 64)
            return true
        }
    }

    /// The vertical "gauge droplet" hero — lime-to-green juice in a glass
    /// droplet with a prompt cursor. Drawn in a flipped (y-down) context so the
    /// shared `DropletGeometry` matches the menu-bar glyph. `detail` carries the
    /// cursor and highlight, dropped below ~64 px so small icns sizes stay clean.
    static func drawAppIcon(in rect: NSRect, detail: Bool) {
        let size = rect.width
        let background = NSBezierPath(
            roundedRect: rect,
            xRadius: size * 0.22,
            yRadius: size * 0.22
        )
        NSGradient(colors: [
            NSColor(calibratedRed: 0.086, green: 0.188, blue: 0.122, alpha: 1),
            NSColor(calibratedRed: 0.043, green: 0.102, blue: 0.071, alpha: 1),
            NSColor(calibratedRed: 0.020, green: 0.043, blue: 0.027, alpha: 1)
        ])?.draw(in: background, angle: -90)

        NSGraphicsContext.saveGraphicsState()
        background.addClip()
        let glowCenter = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.60)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.78, green: 1, blue: 0.24, alpha: 0.22),
            NSColor(calibratedRed: 0.78, green: 1, blue: 0.24, alpha: 0)
        ])?.draw(
            fromCenter: glowCenter,
            radius: 0,
            toCenter: glowCenter,
            radius: size * 0.44,
            options: []
        )
        NSGraphicsContext.restoreGraphicsState()

        let dropRect = NSRect(
            x: size * 0.22,
            y: size * 0.10,
            width: size * 0.56,
            height: size * 0.80
        )
        let drop = dropletPath(in: dropRect)

        NSColor.white.withAlphaComponent(0.10).setFill()
        drop.fill()

        NSGraphicsContext.saveGraphicsState()
        drop.addClip()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.92, green: 1.00, blue: 0.27, alpha: 1),
            NSColor(calibratedRed: 0.44, green: 0.886, blue: 0.10, alpha: 1),
            NSColor(calibratedRed: 0.04, green: 0.60, blue: 0.35, alpha: 1)
        ])?.draw(in: wavePath(in: dropRect, remaining: 0.74), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if detail {
            let cursor = NSBezierPath()
            cursor.move(to: dropPoint(0.34, 0.58, in: dropRect))
            cursor.line(to: dropPoint(0.50, 0.71, in: dropRect))
            cursor.line(to: dropPoint(0.34, 0.84, in: dropRect))
            cursor.lineWidth = size * 0.034
            cursor.lineCapStyle = .round
            cursor.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(0.95).setStroke()
            cursor.stroke()

            let underscore = NSBezierPath()
            underscore.move(to: dropPoint(0.56, 0.84, in: dropRect))
            underscore.line(to: dropPoint(0.74, 0.84, in: dropRect))
            underscore.lineWidth = size * 0.034
            underscore.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.95).setStroke()
            underscore.stroke()

            let highlight = NSBezierPath(ovalIn: NSRect(
                x: dropRect.minX + dropRect.width * 0.18,
                y: dropRect.minY + dropRect.height * 0.16,
                width: dropRect.width * 0.32,
                height: dropRect.height * 0.24
            ))
            NSColor.white.withAlphaComponent(0.16).setFill()
            highlight.fill()
        }

        NSColor.white.withAlphaComponent(0.30).setStroke()
        drop.lineWidth = max(1, size * 0.012)
        drop.lineJoinStyle = .round
        drop.stroke()
    }

    private static func dropPoint(_ fx: CGFloat, _ fy: CGFloat, in rect: NSRect) -> NSPoint {
        DropletGeometry.point(CGPoint(x: fx, y: fy), in: rect)
    }
}
