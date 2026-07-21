import Foundation

enum ClaudeAccessState: Sendable, Equatable {
    case checking
    case cliMissing
    case updateRequired(installed: ClaudeCodeVersion, minimum: ClaudeCodeVersion)
    case workspaceTrustRequired
    case signedOut(reason: ClaudeSignInReason)
    case subscription(plan: String?)
    case apiBilling
    case externalProvider(ClaudeExternalProvider)
    case unsupportedAuth
    case authCheckFailed

    var isNeutralAuthenticationCategory: Bool {
        switch self {
        case .apiBilling, .externalProvider, .unsupportedAuth:
            true
        case .checking, .cliMissing, .updateRequired, .workspaceTrustRequired, .signedOut,
             .subscription, .authCheckFailed:
            false
        }
    }

    var persistenceFingerprint: String {
        switch self {
        case .checking:
            "checking"
        case .cliMissing:
            "cliMissing"
        case .updateRequired(let installed, let minimum):
            "updateRequired:\(installed):\(minimum)"
        case .workspaceTrustRequired:
            "workspaceTrustRequired"
        case .signedOut(let reason):
            "signedOut:\(reason.rawValue)"
        case .subscription(let plan):
            "subscription:\(plan ?? "unknown")"
        case .apiBilling:
            "apiBilling"
        case .externalProvider(let provider):
            "external:\(provider.rawValue)"
        case .unsupportedAuth:
            "unsupportedAuth"
        case .authCheckFailed:
            "authCheckFailed"
        }
    }

    init?(persistenceFingerprint: String) {
        switch persistenceFingerprint {
        case "checking":
            self = .checking
        case "cliMissing":
            self = .cliMissing
        case "workspaceTrustRequired":
            self = .workspaceTrustRequired
        case "apiBilling":
            self = .apiBilling
        case "unsupportedAuth":
            self = .unsupportedAuth
        case "authCheckFailed":
            self = .authCheckFailed
        default:
            if persistenceFingerprint.hasPrefix("subscription:") {
                let plan = String(persistenceFingerprint.dropFirst("subscription:".count))
                self = .subscription(plan: plan == "unknown" ? nil : plan)
                return
            }
            if persistenceFingerprint.hasPrefix("signedOut:"),
               let reason = ClaudeSignInReason(
                   rawValue: String(persistenceFingerprint.dropFirst("signedOut:".count))
               ) {
                self = .signedOut(reason: reason)
                return
            }
            if persistenceFingerprint.hasPrefix("external:"),
               let provider = ClaudeExternalProvider(
                   rawValue: String(persistenceFingerprint.dropFirst("external:".count))
               ) {
                self = .externalProvider(provider)
                return
            }
            if persistenceFingerprint.hasPrefix("updateRequired:") {
                let versions = persistenceFingerprint
                    .dropFirst("updateRequired:".count)
                    .split(separator: ":", omittingEmptySubsequences: false)
                if versions.count == 2,
                   let installed = ClaudeCodeVersion.parse(String(versions[0])),
                   let minimum = ClaudeCodeVersion.parse(String(versions[1])) {
                    self = .updateRequired(installed: installed, minimum: minimum)
                    return
                }
            }
            return nil
        }
    }
}

enum ClaudeProbeFailure: String, Codable, Sendable, Equatable {
    case timeout
    case offline
    case parse
    case process
    case outputTooLarge
    case cancelled
    case workspace
}

enum ClaudeRefreshState: Sendable, Equatable {
    case idle
    case refreshing
    case backingOff(nextAttemptAt: Date)
    case failed(ClaudeProbeFailure)
}

enum LegacyBridgeStatus: Sendable, Equatable {
    case none
    case removable
}

struct ClaudeUsageCoordinatorState: Sendable, Equatable {
    let access: ClaudeAccessState
    let refresh: ClaudeRefreshState
    let snapshot: ProviderSnapshot?
    let legacyBridge: LegacyBridgeStatus
}

struct ClaudeAggregatePolicy {
    static func quotaBearingSnapshots(
        _ snapshots: [ProviderSnapshot],
        claudeAccess: ClaudeAccessState
    ) -> [ProviderSnapshot] {
        snapshots.filter { snapshot in
            snapshot.provider == .codex || !claudeAccess.isNeutralAuthenticationCategory
        }
    }
}
