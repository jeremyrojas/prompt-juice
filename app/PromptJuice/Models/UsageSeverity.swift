import Foundation

/// A single judgment per provider snapshot, shared by the panel chip, the
/// row/bar color, the header droplet tint, and the menu-bar glyph tint so all
/// surfaces agree.
///
/// Two failure modes get two different colors:
/// - `useSoon` (amber): plenty left, but the window resets soon — use it or
///   lose it.
/// - `low` / `empty` (red): nearly out, about to be blocked.
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
    var chipText: String? {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .empty:
            return "Empty"
        case .low:
            return "Low"
        case .useSoon:
            return "Use soon"
        case .healthy:
            return nil
        }
    }

    /// True when the severity should pull attention (colored chip + bar).
    var isAlerting: Bool {
        switch self {
        case .useSoon, .low, .empty:
            return true
        case .healthy, .unavailable:
            return false
        }
    }

    /// Worst-wins ordering for aggregating across providers (higher = louder).
    var rank: Int {
        switch self {
        case .healthy:
            return 0
        case .unavailable:
            return 1
        case .useSoon:
            return 2
        case .low:
            return 3
        case .empty:
            return 4
        }
    }
}
