import Foundation

enum ClaudeRefreshReason: String, Codable, Sendable, Equatable {
    case launch
    case wake
    case foreground
    case panelOpen
    case manual
    case timer
    case resetBoundary

    var isAutomatic: Bool {
        self != .manual
    }
}

struct ClaudeUsageAttempt: Codable, Sendable, Equatable {
    let date: Date
    let reason: ClaudeRefreshReason
}

struct ClaudeUsageScheduleContext: Sendable, Equatable {
    let now: Date
    let reason: ClaudeRefreshReason
    let force: Bool
    let providerEnabled: Bool
    let isAwake: Bool
    let isOnline: Bool
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let nextAttemptAt: Date?
    let recentAttempts: [ClaudeUsageAttempt]
}

enum ClaudeUsageScheduleDecision: Sendable, Equatable {
    case probe
    case skipDisabled
    case skipSleeping
    case skipOffline
    case skipCooldown(nextAttemptAt: Date)
    case skipDebounce
    case skipFresh
    case skipBudget
}

struct ClaudeUsageSchedule: Sendable {
    static let successTTL: TimeInterval = 15 * 60
    static let manualDebounce: TimeInterval = 60
    static let automaticHourlyBudget = 4
    static let combinedHourlyBudget = 6

    func decision(for context: ClaudeUsageScheduleContext) -> ClaudeUsageScheduleDecision {
        guard context.providerEnabled else {
            return .skipDisabled
        }
        guard context.isAwake else {
            return .skipSleeping
        }
        guard context.isOnline else {
            return .skipOffline
        }
        if let nextAttemptAt = context.nextAttemptAt,
           nextAttemptAt > context.now {
            return .skipCooldown(nextAttemptAt: nextAttemptAt)
        }

        let recent = context.recentAttempts.filter {
            context.now.timeIntervalSince($0.date) >= 0
                && context.now.timeIntervalSince($0.date) < 60 * 60
        }
        if recent.count >= Self.combinedHourlyBudget {
            return .skipBudget
        }
        if context.reason.isAutomatic,
           recent.filter({ $0.reason.isAutomatic }).count >= Self.automaticHourlyBudget {
            return .skipBudget
        }

        if context.reason == .manual,
           !context.force,
           let lastAttemptAt = context.lastAttemptAt,
           context.now.timeIntervalSince(lastAttemptAt) < Self.manualDebounce {
            return .skipDebounce
        }

        if context.reason.isAutomatic,
           context.reason != .resetBoundary,
           !context.force,
           let lastSuccessAt = context.lastSuccessAt,
           context.now.timeIntervalSince(lastSuccessAt) < Self.successTTL {
            return .skipFresh
        }

        return .probe
    }
}
