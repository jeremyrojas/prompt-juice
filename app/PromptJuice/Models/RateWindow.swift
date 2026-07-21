import Foundation

struct RateWindow: Equatable, Sendable {
    let usedPercent: Double?
    let resetAt: Date?
    let durationMinutes: Int?

    static let unavailable = RateWindow(
        usedPercent: nil,
        resetAt: nil,
        durationMinutes: nil
    )

    static func available(
        usedPercent: Double,
        resetAt: Date,
        durationMinutes: Int
    ) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            resetAt: resetAt,
            durationMinutes: durationMinutes
        )
    }

    var isAvailable: Bool {
        usedPercent != nil && resetAt != nil && durationMinutes != nil
    }

    var clampedUsedPercent: Double? {
        usedPercent.map { min(100, max(0, $0)) }
    }

    var remainingPercent: Double? {
        clampedUsedPercent.map { 100 - $0 }
    }

    func minutesUntilReset(now: Date = Date()) -> Int? {
        guard let resetAt else {
            return nil
        }

        let seconds = max(0, resetAt.timeIntervalSince(now))
        return Int(ceil(seconds / 60))
    }
}
