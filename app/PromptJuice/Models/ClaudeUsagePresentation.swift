import Foundation

enum ClaudeGuidanceJourney: String, Sendable, Equatable, Identifiable {
    case install
    case signIn
    case update
    case trustWorkspace

    var id: String { rawValue }

    var capsuleTitle: String {
        switch self {
        case .install: "Install"
        case .signIn: "Sign in"
        case .update: "Update"
        case .trustWorkspace: "Trust"
        }
    }

    var settingsButtonTitle: String {
        switch self {
        case .install: "Install…"
        case .signIn: "Sign In…"
        case .update: "Update…"
        case .trustWorkspace: "Trust…"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .install: "Install Claude Code"
        case .signIn: "Sign in to Claude Code"
        case .update: "Update Claude Code"
        case .trustWorkspace: "Trust PromptJuice Claude workspace"
        }
    }
}

enum ClaudeSettingsAction: Sendable, Equatable {
    case journey(ClaudeGuidanceJourney)
    case retry

    var title: String {
        switch self {
        case .journey(let journey): journey.settingsButtonTitle
        case .retry: "Retry"
        }
    }
}

enum ClaudePresentationState: Sendable, Equatable {
    case checking
    case current
    case saved
    case outOfQuota
    case backingOff
    case cliMissing
    case signedOut(ClaudeSignInReason)
    case updateRequired
    case workspaceTrustRequired
    case apiBilling
    case externalProvider(ClaudeExternalProvider)
    case unsupportedAuth
    case failure
    case off
}

struct ClaudeFreshnessFormatter {
    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func title(for date: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(date))
        if age < 60 {
            return "Updated just now"
        }
        if age < 60 * 60 {
            return "Updated \(max(1, Int(age / 60))) min ago"
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return "Updated at \(clockTime(date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Updated yesterday at \(clockTime(date))"
        }
        return "Updated \(monthDay(date)) at \(clockTime(date))"
    }

    func clause(for date: Date, now: Date) -> String {
        let title = title(for: date, now: now)
        return title.prefix(1).lowercased() + title.dropFirst()
    }

    func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

struct ClaudeUsagePresentation: Sendable, Equatable {
    let state: ClaudePresentationState
    let showsReading: Bool
    let showsClock: Bool
    let rowStatus: String?
    let tooltip: String?
    let settingsSubtitle: String
    let settingsAction: ClaudeSettingsAction?
    let estimateFootnote: String?
    let popoverStatus: String?
    let popoverAction: ClaudeSettingsAction?
    let isNeutral: Bool

    var guidanceJourney: ClaudeGuidanceJourney? {
        guard case .journey(let journey) = settingsAction else {
            return nil
        }
        return journey
    }

    static func resolve(
        access: ClaudeAccessState,
        refresh: ClaudeRefreshState,
        snapshot: ProviderSnapshot?,
        isEnabled: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> ClaudeUsagePresentation {
        let freshness = ClaudeFreshnessFormatter(calendar: calendar)
        let hasReading = snapshot?.isAvailable == true
        let isEstimate = snapshot?.confidence == .estimated
        let updatedAt = snapshot?.updatedAt ?? now
        let updatedTitle = freshness.title(for: updatedAt, now: now)
        let updatedClause = freshness.clause(for: updatedAt, now: now)

        guard isEnabled else {
            return ClaudeUsagePresentation(
                state: .off,
                showsReading: false,
                showsClock: false,
                rowStatus: nil,
                tooltip: nil,
                settingsSubtitle: "Off",
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: nil,
                popoverAction: nil,
                isNeutral: false
            )
        }

        if refresh == .refreshing || access == .checking {
            return ClaudeUsagePresentation(
                state: .checking,
                showsReading: hasReading,
                showsClock: false,
                rowStatus: hasReading ? nil : "Checking…",
                tooltip: "Checking usage with Claude Code",
                settingsSubtitle: "Checking…",
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Checking usage with Claude Code now.",
                popoverAction: nil,
                isNeutral: false
            )
        }

        switch access {
        case .cliMissing:
            return journeyPresentation(
                state: .cliMissing,
                journey: .install,
                noReadingStatus: "Claude Code needed",
                noReadingTooltip: "Install Claude Code to read your plan usage",
                settingsWithoutReading: "Claude Code not installed",
                settingsWithEstimate: "Claude Code not installed · showing local estimate",
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. Install Claude Code and sign in, and PromptJuice switches to direct readings automatically.",
                popoverStatus: "Claude Code isn't installed yet. Install it and sign in once. Claude Desktop, Claude.ai, and Claude Code share the same plan usage.",
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .signedOut(let reason):
            let settingsWithoutReading = reason == .initial
                ? "Signed out of Claude Code"
                : "Signed out of Claude Code · sign in again"
            let settingsWithEstimate = reason == .initial
                ? "Estimate · signed out of Claude Code"
                : "Signed out of Claude Code · sign in again · showing local estimate"
            let footnote = reason == .initial
                ? "This is an estimate from Claude Code's activity logs on this Mac. Sign in to Claude Code and PromptJuice switches to direct readings automatically."
                : "This is an estimate from Claude Code's activity logs on this Mac. Sign in to Claude Code again and PromptJuice switches back to direct readings automatically."
            let popover = reason == .initial
                ? "Claude Code is signed out. Sign in once and PromptJuice takes it from there."
                : "Claude Code's sign-in has expired. Sign in again and PromptJuice takes it from there."
            return journeyPresentation(
                state: .signedOut(reason),
                journey: .signIn,
                noReadingStatus: "Sign in needed",
                noReadingTooltip: "Sign in to Claude Code to read your plan usage",
                settingsWithoutReading: settingsWithoutReading,
                settingsWithEstimate: settingsWithEstimate,
                footnote: footnote,
                popoverStatus: popover,
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .workspaceTrustRequired:
            return journeyPresentation(
                state: .workspaceTrustRequired,
                journey: .trustWorkspace,
                noReadingStatus: "Workspace trust needed",
                noReadingTooltip: "Trust PromptJuice's Claude workspace to read plan usage",
                settingsWithoutReading: "Claude workspace trust needed",
                settingsWithEstimate: "Claude workspace trust needed · showing local estimate",
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. Trust PromptJuice's dedicated Claude workspace and PromptJuice switches to direct readings automatically.",
                popoverStatus: "Claude Code needs you to trust PromptJuice's dedicated empty workspace once before PromptJuice can read plan usage.",
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .updateRequired(_, let minimum):
            return journeyPresentation(
                state: .updateRequired,
                journey: .update,
                noReadingStatus: "Update needed",
                noReadingTooltip: "Update Claude Code to read your plan usage",
                settingsWithoutReading: "Update Claude Code to track plan usage",
                settingsWithEstimate: "Update Claude Code to track plan usage · showing local estimate",
                footnote: "This is an estimate from Claude Code's activity logs on this Mac. Update Claude Code and PromptJuice switches to direct readings automatically.",
                popoverStatus: "PromptJuice needs Claude Code \(minimum) or newer to read plan usage.",
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .apiBilling:
            return ClaudeUsagePresentation(
                state: .apiBilling,
                showsReading: false,
                showsClock: false,
                rowStatus: "API billing",
                tooltip: "Claude Code is using API billing · plan quota unavailable",
                settingsSubtitle: "API billing · Claude Console tracks spend",
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Claude Code is using first-party API billing, which Claude Console tracks as spend. Plan quota doesn't apply, so there's no juice bar to fill.",
                popoverAction: .journey(.signIn),
                isNeutral: true
            )
        case .externalProvider(let provider):
            let providerName = provider.displayName
            return ClaudeUsagePresentation(
                state: .externalProvider(provider),
                showsReading: false,
                showsClock: false,
                rowStatus: "External provider",
                tooltip: "Claude Code uses \(providerName) · plan quota unavailable",
                settingsSubtitle: "\(providerName) · plan quota unavailable",
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Claude Code is set up to use \(providerName), which bills through your cloud account. Plan quota doesn't apply, so there's no juice bar to fill.",
                popoverAction: nil,
                isNeutral: true
            )
        case .unsupportedAuth:
            return ClaudeUsagePresentation(
                state: .unsupportedAuth,
                showsReading: false,
                showsClock: false,
                rowStatus: "Usage unavailable",
                tooltip: "This Claude Code setup isn't supported yet",
                settingsSubtitle: "Account type not recognized · usage not tracked",
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Claude Code is signed in with an account type PromptJuice doesn't recognize yet, so usage tracking is off for it. A future update may add support.",
                popoverAction: nil,
                isNeutral: true
            )
        case .authCheckFailed:
            return failurePresentation(
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .checking, .subscription:
            break
        }

        switch refresh {
        case .backingOff(let nextAttemptAt):
            let nextTime = freshness.clockTime(nextAttemptAt)
            let tooltip: String
            let settingsSubtitle: String
            if hasReading {
                let source = isEstimate
                    ? "Estimated from Claude Code's activity logs on this Mac"
                    : "From Claude Code · \(updatedClause)"
                tooltip = "\(source) · next check at \(nextTime)"
                settingsSubtitle = isEstimate
                    ? "Estimate · next check at \(nextTime)"
                    : "\(updatedTitle) · next check at \(nextTime)"
            } else {
                tooltip = "Usage check paused · next check at \(nextTime)"
                settingsSubtitle = "Next check at \(nextTime)"
            }
            let readingSuffix = hasReading
                ? " Showing your \(freshness.clockTime(updatedAt)) reading in the meantime."
                : ""
            return ClaudeUsagePresentation(
                state: .backingOff,
                showsReading: hasReading,
                showsClock: hasReading && !isEstimate,
                rowStatus: hasReading ? nil : "Next check \(nextTime)",
                tooltip: tooltip,
                settingsSubtitle: settingsSubtitle,
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "The last usage check was rate limited. PromptJuice tries again at \(nextTime).\(readingSuffix)",
                popoverAction: nil,
                isNeutral: false
            )
        case .failed:
            return failurePresentation(
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        case .idle, .refreshing:
            break
        }

        guard let snapshot, snapshot.isAvailable else {
            return failurePresentation(
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        }

        if snapshot.confidence == .estimated {
            return failurePresentation(
                snapshot: snapshot,
                now: now,
                freshness: freshness
            )
        }

        if snapshot.remainingPercent <= 0 {
            return ClaudeUsagePresentation(
                state: .outOfQuota,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "Claude is out until reset · \(updatedClause)",
                settingsSubtitle: updatedTitle,
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Showing your last reading from \(freshness.clockTime(updatedAt)). PromptJuice refreshes it automatically.",
                popoverAction: nil,
                isNeutral: false
            )
        }

        if snapshot.confidence == .stale || snapshot.source == .claudeCache {
            return ClaudeUsagePresentation(
                state: .saved,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "From Claude Code · \(updatedClause)",
                settingsSubtitle: updatedTitle,
                settingsAction: nil,
                estimateFootnote: nil,
                popoverStatus: "Showing your last reading from \(freshness.clockTime(updatedAt)). PromptJuice refreshes it automatically.",
                popoverAction: nil,
                isNeutral: false
            )
        }

        return ClaudeUsagePresentation(
            state: .current,
            showsReading: true,
            showsClock: false,
            rowStatus: nil,
            tooltip: "From Claude Code · \(updatedClause)",
            settingsSubtitle: updatedTitle,
            settingsAction: nil,
            estimateFootnote: nil,
            popoverStatus: "Right now it's current, read a moment ago.",
            popoverAction: nil,
            isNeutral: false
        )
    }

    private static func journeyPresentation(
        state: ClaudePresentationState,
        journey: ClaudeGuidanceJourney,
        noReadingStatus: String,
        noReadingTooltip: String,
        settingsWithoutReading: String,
        settingsWithEstimate: String,
        footnote: String,
        popoverStatus: String,
        snapshot: ProviderSnapshot?,
        now: Date,
        freshness: ClaudeFreshnessFormatter
    ) -> ClaudeUsagePresentation {
        let hasReading = snapshot?.isAvailable == true
        let isEstimate = snapshot?.confidence == .estimated
        let showsReading = hasReading
        let tooltip: String
        if isEstimate {
            tooltip = "Estimated from Claude Code's activity logs on this Mac"
        } else if hasReading, let snapshot {
            tooltip = "From Claude Code · \(freshness.clause(for: snapshot.updatedAt, now: now))"
        } else {
            tooltip = noReadingTooltip
        }

        return ClaudeUsagePresentation(
            state: state,
            showsReading: showsReading,
            showsClock: hasReading && !isEstimate,
            rowStatus: showsReading ? nil : noReadingStatus,
            tooltip: tooltip,
            settingsSubtitle: isEstimate ? settingsWithEstimate : settingsWithoutReading,
            settingsAction: .journey(journey),
            estimateFootnote: isEstimate ? footnote : nil,
            popoverStatus: popoverStatus,
            popoverAction: nil,
            isNeutral: false
        )
    }

    private static func failurePresentation(
        snapshot: ProviderSnapshot?,
        now: Date,
        freshness: ClaudeFreshnessFormatter
    ) -> ClaudeUsagePresentation {
        let hasReading = snapshot?.isAvailable == true
        let isEstimate = snapshot?.confidence == .estimated
        let updatedAt = snapshot?.updatedAt ?? now
        let clockTime = freshness.clockTime(updatedAt)

        if isEstimate {
            return ClaudeUsagePresentation(
                state: .failure,
                showsReading: true,
                showsClock: false,
                rowStatus: nil,
                tooltip: "Couldn't check usage with Claude Code · trying again automatically",
                settingsSubtitle: "Estimate · having trouble reading Claude Code",
                settingsAction: .retry,
                estimateFootnote: "This is an estimate from Claude Code's activity logs on this Mac. PromptJuice checks about every 15 minutes and switches back automatically.",
                popoverStatus: "PromptJuice couldn't get a new reading from Claude Code. It's showing a local estimate and will keep trying automatically.",
                popoverAction: nil,
                isNeutral: false
            )
        }

        if hasReading {
            return ClaudeUsagePresentation(
                state: .failure,
                showsReading: true,
                showsClock: true,
                rowStatus: nil,
                tooltip: "From Claude Code · \(freshness.clause(for: updatedAt, now: now)) · having trouble updating",
                settingsSubtitle: "Having trouble updating · showing \(clockTime) reading",
                settingsAction: .retry,
                estimateFootnote: nil,
                popoverStatus: "PromptJuice couldn't get a new reading from Claude Code. It's showing your \(clockTime) reading and will keep trying.",
                popoverAction: nil,
                isNeutral: false
            )
        }

        return ClaudeUsagePresentation(
            state: .failure,
            showsReading: false,
            showsClock: false,
            rowStatus: "Having trouble checking",
            tooltip: "Couldn't check usage with Claude Code · trying again automatically",
            settingsSubtitle: "Having trouble checking usage",
            settingsAction: .retry,
            estimateFootnote: nil,
            popoverStatus: "PromptJuice couldn't check usage with Claude Code. It will keep trying automatically.",
            popoverAction: nil,
            isNeutral: false
        )
    }
}

extension ClaudeExternalProvider {
    var displayName: String {
        switch self {
        case .bedrock: "Amazon Bedrock"
        case .vertex: "Google Vertex AI"
        case .foundry: "Microsoft Foundry"
        case .gateway: "External gateway"
        }
    }
}
