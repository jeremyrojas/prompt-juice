import Foundation

struct ProviderSnapshot: Identifiable, Equatable {
    let identity: ProviderIdentity
    let rateWindow: RateWindow
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let statusDetail: String?

    init(
        identity: ProviderIdentity,
        rateWindow: RateWindow,
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        updatedAt: Date = Date(),
        statusDetail: String? = nil
    ) {
        self.identity = identity
        self.rateWindow = rateWindow
        self.source = source
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.statusDetail = statusDetail
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

    var resetAt: Date {
        rateWindow.resetAt ?? updatedAt
    }

    var windowDurationMinutes: Int {
        rateWindow.durationMinutes ?? 0
    }

    var isAvailable: Bool {
        rateWindow.isAvailable && confidence != .unavailable
    }

    var clampedUsedPercent: Double {
        rateWindow.clampedUsedPercent ?? 0
    }

    var remainingPercent: Double {
        rateWindow.remainingPercent ?? 0
    }

    var resetWindowID: String {
        guard let resetAt = rateWindow.resetAt else {
            return "\(provider.rawValue):unavailable"
        }

        let resetMinute = Int(resetAt.timeIntervalSince1970 / 60)
        return "\(provider.rawValue):\(resetMinute)"
    }
}
