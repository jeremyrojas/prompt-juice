import CoreGraphics

/// One source of truth for the gauge-droplet silhouette and its juice line,
/// shared by the SwiftUI header (`DropletGauge`) and the AppKit menu-bar glyph
/// (`PromptJuiceIcon`) so the two renderings can't drift.
///
/// Coordinates are normalized to a unit square in **y-down** space (SwiftUI
/// convention). The AppKit glyph draws into a flipped image context so the same
/// fractions apply there too.
enum DropletGeometry {
    /// Tip of the teardrop (top-center).
    static let tip = CGPoint(x: 0.5, y: 0.1208)

    /// Cubic segments tracing the outline clockwise from the tip:
    /// (control1, control2, endPoint).
    static let segments: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 0.5000, y: 0.1208), CGPoint(x: 0.2083, y: 0.4708), CGPoint(x: 0.2083, y: 0.6667)),
        (CGPoint(x: 0.2083, y: 0.8292), CGPoint(x: 0.3375, y: 0.9333), CGPoint(x: 0.5000, y: 0.9333)),
        (CGPoint(x: 0.6625, y: 0.9333), CGPoint(x: 0.7917, y: 0.8292), CGPoint(x: 0.7917, y: 0.6667)),
        (CGPoint(x: 0.7917, y: 0.4708), CGPoint(x: 0.5000, y: 0.1208), CGPoint(x: 0.5000, y: 0.1208))
    ]

    /// The juice surface never climbs into the narrow tip and never quite
    /// drains past the bulb floor, so "full" and "empty" both read cleanly.
    static let fillTop: CGFloat = 0.17
    static let fillBottom: CGFloat = 0.92

    /// Above this remaining fraction the droplet renders as a solid fill (the
    /// classic `drop.fill` look) — that IS the 100% state.
    static let solidFillThreshold: Double = 0.97

    /// Below this remaining fraction a single "last drop" bead is shown.
    static let lastDropThreshold: Double = 0.10

    /// Maps a normalized fraction point into an actual rect.
    static func point(_ fraction: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + fraction.x * rect.width,
            y: rect.minY + fraction.y * rect.height
        )
    }

    /// y-fraction of the juice surface for a remaining level in 0...1.
    static func waterline(forRemaining remaining: Double) -> CGFloat {
        let clamped = CGFloat(min(1, max(0, remaining)))
        return fillTop + (1 - clamped) * (fillBottom - fillTop)
    }
}
