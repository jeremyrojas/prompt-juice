import Foundation

struct ProviderSnapshot: Identifiable, Equatable {
    let identity: ProviderIdentity
    let rateWindow: RateWindow
    let weeklyWindow: RateWindow?
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let weeklyUpdatedAt: Date?
    let statusDetail: String?
    let isFreshSessionWindow: Bool
    let isFreshWeeklyWindow: Bool

    init(
        identity: ProviderIdentity,
        rateWindow: RateWindow,
        weeklyWindow: RateWindow? = nil,
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        updatedAt: Date = Date(),
        weeklyUpdatedAt: Date? = nil,
        statusDetail: String? = nil,
        isFreshSessionWindow: Bool = false,
        isFreshWeeklyWindow: Bool = false
    ) {
        self.identity = identity
        self.rateWindow = rateWindow
        self.weeklyWindow = weeklyWindow
        self.source = source
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.weeklyUpdatedAt = weeklyUpdatedAt
        self.statusDetail = statusDetail
        self.isFreshSessionWindow = isFreshSessionWindow
        self.isFreshWeeklyWindow = isFreshWeeklyWindow
    }

    var id: UsageProvider {
        identity.id
    }

    var provider: UsageProvider {
        identity.provider
    }

    var displayName: String {
        identity.displayName
    }

    var usedPercent: Double {
        rateWindow.usedPercent ?? 0
    }

    var windowDurationMinutes: Int {
        rateWindow.durationMinutes ?? 0
    }

    var isAvailable: Bool {
        (rateWindow.isAvailable || isFreshSessionWindow) && confidence != .unavailable
    }

    func isExpired(at now: Date) -> Bool {
        if isFreshSessionWindow {
            return false
        }

        guard isAvailable, let resetAt = rateWindow.resetAt else {
            return false
        }

        return resetAt <= now
    }

    func hasActiveResetWindow(at now: Date) -> Bool {
        isAvailable
            && rateWindow.resetAt != nil
            && !isExpired(at: now)
    }

    var clampedUsedPercent: Double {
        rateWindow.clampedUsedPercent ?? 0
    }

    var sessionRemainingPercent: Double {
        if isFreshSessionWindow {
            return 100
        }

        return rateWindow.remainingPercent ?? 0
    }

    var weeklyRemainingPercent: Double? {
        if isFreshWeeklyWindow {
            return 100
        }

        return weeklyWindow?.remainingPercent
    }

    var remainingPercent: Double {
        guard identity == .claude else {
            return sessionRemainingPercent
        }

        return min(sessionRemainingPercent, weeklyRemainingPercent ?? 100)
    }

    var resetWindowID: String {
        if isFreshSessionWindow {
            return "\(provider.rawValue):fresh"
        }

        guard let resetAt = rateWindow.resetAt else {
            return "\(provider.rawValue):unavailable"
        }

        let resetMinute = Int(resetAt.timeIntervalSince1970 / 60)
        return "\(provider.rawValue):\(resetMinute)"
    }
}
