import AppKit
import SwiftUI

/// Brand colors for capacity, shared across the panel and the menu-bar glyph so
/// every surface tells the same story. Two failure modes, two colors:
/// amber = use-it-or-lose-it, red = nearly out.
enum JuicePalette {
    static let green = Color(red: 0.373, green: 0.820, blue: 0.122)
    static let amber = Color(red: 0.941, green: 0.639, blue: 0.165)
    static let red = Color(red: 0.941, green: 0.271, blue: 0.224)
    static let muted = Color(red: 0.59, green: 0.61, blue: 0.65)

    static let nsGreen = NSColor(calibratedRed: 0.373, green: 0.820, blue: 0.122, alpha: 1)
    static let nsAmber = NSColor(calibratedRed: 0.941, green: 0.639, blue: 0.165, alpha: 1)
    static let nsRed = NSColor(calibratedRed: 0.941, green: 0.271, blue: 0.224, alpha: 1)
}

extension UsageSeverity {
    /// SwiftUI tint for the panel (chip, bar, header droplet).
    var tint: Color {
        switch self {
        case .healthy:
            return JuicePalette.green
        case .useSoon:
            return JuicePalette.amber
        case .low, .empty, .unavailable:
            return JuicePalette.muted
        }
    }

    /// AppKit tint for the menu-bar glyph low states. `nil` means draw as a
    /// plain system-tinted template (the healthy default).
    var menuBarTint: NSColor? {
        switch self {
        case .useSoon:
            return JuicePalette.nsAmber
        case .healthy, .unavailable, .low, .empty:
            return nil
        }
    }
}
