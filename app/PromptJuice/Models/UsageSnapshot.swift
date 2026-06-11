import Foundation

struct UsageSnapshot: Identifiable, Equatable {
    let provider: UsageProvider
    let usedPercent: Double
    let resetAt: Date
    let windowDurationMinutes: Int

    var id: UsageProvider {
        provider
    }

    var clampedUsedPercent: Double {
        min(100, max(0, usedPercent))
    }

    var remainingPercent: Double {
        100 - clampedUsedPercent
    }
}
