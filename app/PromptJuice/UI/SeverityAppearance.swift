import AppKit
import SwiftUI

/// Brand colors for capacity, shared across the panel and the menu-bar glyph so
/// every surface tells the same story. Orange is the session-reset nudge; calm
/// low/empty states use muted color.
enum JuicePalette {
    static let green = Color(red: 0.373, green: 0.820, blue: 0.122)
    static let orange = Color(red: 0.941, green: 0.639, blue: 0.165)
    static let muted = Color(red: 0.59, green: 0.61, blue: 0.65)

    static let nsGreen = NSColor(calibratedRed: 0.373, green: 0.820, blue: 0.122, alpha: 1)
    static let nsOrange = NSColor(calibratedRed: 0.941, green: 0.639, blue: 0.165, alpha: 1)
}

extension UsageSeverity {
    /// SwiftUI tint for the panel (chip, bar, header droplet).
    var tint: Color {
        switch self {
        case .healthy:
            return JuicePalette.green
        case .useSoon:
            return JuicePalette.orange
        case .low, .empty, .unavailable:
            return JuicePalette.muted
        }
    }

    /// AppKit tint for the menu-bar glyph low states. `nil` means draw as a
    /// plain system-tinted template (the healthy default).
    var menuBarTint: NSColor? {
        switch self {
        case .useSoon:
            return JuicePalette.nsOrange
        case .healthy, .unavailable, .low, .empty:
            return nil
        }
    }
}
