import Foundation

struct LimitWindow: Equatable, Sendable, Identifiable {
    enum Kind: Codable, Equatable, Hashable, Sendable {
        case fiveHour
        case weekly
        case weeklyModel(String)
        case other(Int)

        static func codexKind(durationMinutes: Int) -> Kind {
            switch durationMinutes {
            case 300: .fiveHour
            case 10_080: .weekly
            default: .other(durationMinutes)
            }
        }

        var label: String {
            switch self {
            case .fiveHour:
                return "5-hour limit"
            case .weekly:
                return "Weekly"
            case .weeklyModel(let name):
                return name
            case .other(let durationMinutes):
                let minutes = max(0, durationMinutes)
                if minutes < 60 {
                    return "\(minutes)-minute limit"
                }
                if minutes <= 24 * 60 {
                    return "\(minutes / 60)-hour limit"
                }
                return "\(minutes / (24 * 60))-day limit"
            }
        }

        var durationMinutes: Int {
            switch self {
            case .fiveHour: 300
            case .weekly, .weeklyModel: 10_080
            case .other(let durationMinutes): durationMinutes
            }
        }

        var cadenceIsWeekly: Bool {
            durationMinutes >= 24 * 60
        }

        var identifier: String {
            switch self {
            case .fiveHour: "five-hour"
            case .weekly: "weekly"
            case .weeklyModel(let name): "weekly-model:\(name)"
            case .other(let durationMinutes): "other:\(durationMinutes)"
            }
        }

        fileprivate var sortPriority: Int {
            switch self {
            case .fiveHour: 0
            case .weekly: 1
            case .weeklyModel: 2
            case .other: 3
            }
        }
    }

    let kind: Kind
    let rateWindow: RateWindow
    let updatedAt: Date

    var id: String { kind.identifier }

    func resetWindowID(provider: UsageProvider) -> String {
        guard let resetAt = rateWindow.resetAt else {
            return "\(provider.rawValue):\(id):fresh"
        }
        let resetMinute = Int(resetAt.timeIntervalSince1970 / 60)
        return "\(provider.rawValue):\(id):\(resetMinute)"
    }
}

struct ProviderSnapshot: Identifiable, Equatable, Sendable {
    let identity: ProviderIdentity
    let windows: [LimitWindow]
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let statusDetail: String?
    let isFreshSessionWindow: Bool
    let isFreshWeeklyWindow: Bool

    init(
        identity: ProviderIdentity,
        windows: [LimitWindow],
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        updatedAt: Date = Date(),
        statusDetail: String? = nil,
        isFreshSessionWindow: Bool = false,
        isFreshWeeklyWindow: Bool = false
    ) {
        self.identity = identity
        self.windows = windows.sorted { first, second in
            let firstDuration = first.rateWindow.durationMinutes ?? first.kind.durationMinutes
            let secondDuration = second.rateWindow.durationMinutes ?? second.kind.durationMinutes
            if firstDuration != secondDuration {
                return firstDuration < secondDuration
            }
            return first.kind.sortPriority < second.kind.sortPriority
        }
        self.source = source
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.statusDetail = statusDetail
        self.isFreshSessionWindow = identity.provider == .codex && isFreshSessionWindow
        self.isFreshWeeklyWindow = isFreshWeeklyWindow
    }

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
        var windows: [LimitWindow] = []
        if rateWindow.isAvailable || isFreshSessionWindow {
            let kind = rateWindow.durationMinutes.map(LimitWindow.Kind.codexKind) ?? .fiveHour
            windows.append(LimitWindow(kind: kind, rateWindow: rateWindow, updatedAt: updatedAt))
        }
        if let weeklyWindow {
            windows.append(LimitWindow(
                kind: .weekly,
                rateWindow: weeklyWindow,
                updatedAt: weeklyUpdatedAt ?? updatedAt
            ))
        }
        self.init(
            identity: identity,
            windows: windows,
            source: source,
            confidence: confidence,
            updatedAt: updatedAt,
            statusDetail: statusDetail,
            isFreshSessionWindow: isFreshSessionWindow,
            isFreshWeeklyWindow: isFreshWeeklyWindow
        )
    }

    var id: UsageProvider { identity.id }
    var provider: UsageProvider { identity.provider }
    var displayName: String { identity.displayName }
    var mainWindow: LimitWindow? { windows.first }

    var rateWindow: RateWindow {
        if provider == .claude {
            return windows.first(where: { $0.kind == .fiveHour })?.rateWindow ?? .unavailable
        }
        return mainWindow?.rateWindow ?? .unavailable
    }

    var weeklyWindow: RateWindow? {
        windows.first(where: { $0.kind == .weekly })?.rateWindow
    }

    var weeklyUpdatedAt: Date? {
        windows.first(where: { $0.kind == .weekly })?.updatedAt
    }

    var usedPercent: Double { rateWindow.usedPercent ?? 0 }
    var windowDurationMinutes: Int { rateWindow.durationMinutes ?? 0 }

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
        isAvailable && rateWindow.resetAt != nil && !isExpired(at: now)
    }

    var clampedUsedPercent: Double { rateWindow.clampedUsedPercent ?? 0 }

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

    var remainingPercent: Double { sessionRemainingPercent }

    var effectiveRemainingPercent: Double {
        min(sessionRemainingPercent, weeklyRemainingPercent ?? 100)
    }

    var resetWindowID: String {
        mainWindow?.resetWindowID(provider: provider) ?? "\(provider.rawValue):unavailable"
    }
}
