import Foundation

/// A single judgment per provider snapshot, shared by the panel chip, the
/// row/bar color, the header droplet tint, and the menu-bar glyph tint so all
/// surfaces agree.
///
/// Two display modes stay calm while the session-reset nudge draws attention:
/// - `useSoon` (orange): plenty left, but the window resets soon — use it or
///   lose it.
/// - `low` / `empty` (muted): nearly out; the short fill communicates level.
///
/// `healthy` is deliberately quiet (no chip) so the alerting states read loud.
enum UsageSeverity: Equatable {
    case unavailable
    case empty
    case low
    case useSoon
    case healthy

    /// Remaining-percent floor below which a provider counts as nearly out.
    /// Matches the existing "Low" boundary used by `statusText`.
    static let lowRemainingFloor = 15

    /// Short chip label. `nil` means no chip is shown — the healthy state stays
    /// silent so the alerting states stand out.
    /// One-alert model: only `useSoon` (the orange "use it before it resets" nudge)
    /// gets a chip. Low/empty are calm — the short bar already tells the story.
    var chipText: String? {
        switch self {
        case .useSoon:
            return "Use soon"
        case .healthy, .unavailable, .low, .empty:
            return nil
        }
    }

    /// True when the severity should pull attention (orange chip + tint). Only the
    /// use-soon nudge does; "running low" stays calm (no action to take).
    var isAlerting: Bool {
        switch self {
        case .useSoon:
            return true
        case .healthy, .unavailable, .low, .empty:
            return false
        }
    }

    /// Worst-wins ordering for aggregating across providers (higher = louder). The
    /// orange `useSoon` nudge outranks everything so it always surfaces in the
    /// header/glyph, even when the other provider is low.
    var rank: Int {
        switch self {
        case .healthy:
            return 0
        case .unavailable:
            return 1
        case .low:
            return 2
        case .empty:
            return 3
        case .useSoon:
            return 4
        }
    }
}
