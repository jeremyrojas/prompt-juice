import Foundation

enum ProviderSetupState: String, Equatable {
    case exact = "Exact"
    case estimated = "Estimated"
    case stale = "Stale"
    case unavailable = "Unavailable"

    init(confidence: SnapshotConfidence) {
        switch confidence {
        case .exact:
            self = .exact
        case .estimated:
            self = .estimated
        case .stale:
            self = .stale
        case .unavailable:
            self = .unavailable
        }
    }
}

struct ProviderSetupSummary: Identifiable, Equatable {
    let identity: ProviderIdentity
    let state: ProviderSetupState
    let sourceTitle: String
    let headline: String
    let detail: String
    let helper: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let updatedAt: Date?

    var id: UsageProvider {
        identity.provider
    }

    var provider: UsageProvider {
        identity.provider
    }

    var isUsable: Bool {
        state == .exact || state == .estimated || state == .stale
    }

    static func from(snapshot: ProviderSnapshot?) -> ProviderSetupSummary {
        guard let snapshot else {
            return unavailable(for: .codex, detail: "Refresh to check local provider data.")
        }

        switch snapshot.provider {
        case .codex:
            return codex(from: snapshot)
        case .claude:
            return claude(from: snapshot)
        }
    }

    static func unavailable(
        for provider: UsageProvider,
        detail: String
    ) -> ProviderSetupSummary {
        switch provider {
        case .codex:
            return ProviderSetupSummary(
                identity: .codex,
                state: .unavailable,
                sourceTitle: "Codex app-server",
                headline: "Codex usage is unavailable.",
                detail: detail,
                helper: "Open Codex once, then refresh.",
                primaryActionTitle: "Refresh",
                secondaryActionTitle: "Details",
                updatedAt: nil
            )
        case .claude:
            return ProviderSetupSummary(
                identity: .claude,
                state: .unavailable,
                sourceTitle: "Claude statusline",
                headline: "Claude usage is unavailable.",
                detail: detail,
                helper: "Use Claude Code once, then refresh.",
                primaryActionTitle: "Refresh",
                secondaryActionTitle: "Learn More",
                updatedAt: nil
            )
        }
    }

    private static func codex(from snapshot: ProviderSnapshot) -> ProviderSetupSummary {
        let state = ProviderSetupState(confidence: snapshot.confidence)

        switch state {
        case .exact:
            return ProviderSetupSummary(
                identity: .codex,
                state: state,
                sourceTitle: "Codex app-server",
                headline: "Codex is available.",
                detail: "Reads reset and usage from the local app-server.",
                helper: "Read-only usage and reset data.",
                primaryActionTitle: "Use Codex",
                secondaryActionTitle: "Details",
                updatedAt: snapshot.updatedAt
            )
        case .stale:
            return ProviderSetupSummary(
                identity: .codex,
                state: state,
                sourceTitle: "Codex cache",
                headline: "Showing last Codex reading.",
                detail: "Alerts pause until fresh data returns.",
                helper: snapshot.statusDetail ?? "Last exact reading is still inside the current reset window.",
                primaryActionTitle: "Refresh",
                secondaryActionTitle: "Details",
                updatedAt: snapshot.updatedAt
            )
        case .estimated:
            return ProviderSetupSummary(
                identity: .codex,
                state: state,
                sourceTitle: "Codex local data",
                headline: "Codex estimate is available.",
                detail: "Good for timing alerts.",
                helper: "Source confidence appears beside the provider.",
                primaryActionTitle: "Use Estimate",
                secondaryActionTitle: "Details",
                updatedAt: snapshot.updatedAt
            )
        case .unavailable:
            let detail = snapshot.statusDetail ?? "Codex usage data is unavailable right now."
            return unavailable(for: .codex, detail: detail)
        }
    }

    private static func claude(from snapshot: ProviderSnapshot) -> ProviderSetupSummary {
        let state = ProviderSetupState(confidence: snapshot.confidence)

        switch state {
        case .exact:
            return ProviderSetupSummary(
                identity: .claude,
                state: state,
                sourceTitle: "Claude statusline",
                headline: "Claude exact readings are available.",
                detail: "Reads a sanitized statusline cache.",
                helper: "Stores usage percent and reset time.",
                primaryActionTitle: "Use Claude",
                secondaryActionTitle: "Details",
                updatedAt: snapshot.updatedAt
            )
        case .estimated:
            return ProviderSetupSummary(
                identity: .claude,
                state: state,
                sourceTitle: "Claude local logs",
                headline: "Claude estimates are available.",
                detail: "Estimated from local Claude Code logs. Good for timing alerts.",
                helper: "Set up statusline for exact readings.",
                primaryActionTitle: "Use Estimate",
                secondaryActionTitle: "Set Up Exact",
                updatedAt: snapshot.updatedAt
            )
        case .stale:
            return ProviderSetupSummary(
                identity: .claude,
                state: state,
                sourceTitle: "Claude cache",
                headline: "Showing last Claude reading.",
                detail: "Alerts pause until fresh data returns.",
                helper: snapshot.statusDetail ?? "Last exact reading is still inside the current reset window.",
                primaryActionTitle: "Refresh",
                secondaryActionTitle: "Set Up Exact",
                updatedAt: snapshot.updatedAt
            )
        case .unavailable:
            let detail = snapshot.statusDetail ?? "Claude usage data is unavailable right now."
            return unavailable(for: .claude, detail: detail)
        }
    }
}
