#if DEBUG
import Foundation

enum ClaudeUIPreviewScenario: String, CaseIterable {
    case checkingNone = "checking-none"
    case checkingCached = "checking-cached"
    case current
    case saved
    case outOfQuota = "out-of-quota"
    case backingOffCached = "backing-off-cached"
    case backingOffNone = "backing-off-none"
    case cliMissingEstimate = "cli-missing-estimate"
    case cliMissingNone = "cli-missing-none"
    case signedOutInitialEstimate = "signed-out-initial-estimate"
    case signedOutInitialNone = "signed-out-initial-none"
    case signedOutReauthEstimate = "signed-out-reauth-estimate"
    case signedOutReauthNone = "signed-out-reauth-none"
    case updateEstimate = "update-estimate"
    case updateNone = "update-none"
    case apiBilling = "api-billing"
    case externalProvider = "external-provider"
    case unsupportedAuth = "unsupported-auth"
    case failureCached = "failure-cached"
    case failureEstimate = "failure-estimate"
    case failureNone = "failure-none"
    case providerOff = "provider-off"
    case workspaceTrust = "workspace-trust"

    var fixture: ClaudeUIPreviewFixture {
        let now = Date()
        let unavailable = Self.unavailable(at: now)
        let current = Self.reading(updatedAt: now)
        let saved = Self.reading(
            source: .claudeCache,
            confidence: .stale,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60)
        )
        let estimate = Self.reading(
            source: .claudeLocalLogs,
            confidence: .estimated,
            updatedAt: now.addingTimeInterval(-12 * 60)
        )
        let nextAttempt = now.addingTimeInterval(45 * 60)
        let update = ClaudeAccessState.updateRequired(
            installed: ClaudeCodeVersion(major: 2, minor: 0, patch: 14),
            minimum: .minimumUsageVersion
        )

        switch self {
        case .checkingNone:
            return fixture(.subscription(plan: "Max"), .refreshing, unavailable)
        case .checkingCached:
            return fixture(.subscription(plan: "Max"), .refreshing, saved)
        case .current:
            return fixture(.subscription(plan: "Max"), .idle, current)
        case .saved:
            return fixture(.subscription(plan: "Max"), .idle, saved)
        case .outOfQuota:
            return fixture(
                .subscription(plan: "Max"),
                .idle,
                Self.reading(usedPercent: 100, updatedAt: now.addingTimeInterval(-2 * 60 * 60))
            )
        case .backingOffCached:
            return fixture(.subscription(plan: "Max"), .backingOff(nextAttemptAt: nextAttempt), saved)
        case .backingOffNone:
            return fixture(.subscription(plan: "Max"), .backingOff(nextAttemptAt: nextAttempt), unavailable)
        case .cliMissingEstimate:
            return fixture(.cliMissing, .idle, estimate, executable: nil)
        case .cliMissingNone:
            return fixture(.cliMissing, .idle, unavailable, executable: nil)
        case .signedOutInitialEstimate:
            return fixture(.signedOut(reason: .initial), .idle, estimate)
        case .signedOutInitialNone:
            return fixture(.signedOut(reason: .initial), .idle, unavailable)
        case .signedOutReauthEstimate:
            return fixture(.signedOut(reason: .reauthenticationRequired), .idle, estimate)
        case .signedOutReauthNone:
            return fixture(.signedOut(reason: .reauthenticationRequired), .idle, unavailable)
        case .updateEstimate:
            return fixture(update, .idle, estimate)
        case .updateNone:
            return fixture(update, .idle, unavailable, executable: Self.unknownExecutable)
        case .apiBilling:
            return fixture(.apiBilling, .idle, unavailable, enabledProviders: [.claude])
        case .externalProvider:
            return fixture(.externalProvider(.bedrock), .idle, unavailable, enabledProviders: [.claude])
        case .unsupportedAuth:
            return fixture(.unsupportedAuth, .idle, unavailable, enabledProviders: [.claude])
        case .failureCached:
            return fixture(.subscription(plan: "Max"), .failed(.timeout), saved)
        case .failureEstimate:
            return fixture(.subscription(plan: "Max"), .failed(.parse), estimate)
        case .failureNone:
            return fixture(.authCheckFailed, .failed(.process), unavailable)
        case .providerOff:
            return fixture(.subscription(plan: "Max"), .idle, current, enabledProviders: [.codex])
        case .workspaceTrust:
            return fixture(.workspaceTrustRequired, .idle, unavailable)
        }
    }

    private func fixture(
        _ access: ClaudeAccessState,
        _ refresh: ClaudeRefreshState,
        _ claude: ProviderSnapshot,
        executable: ClaudeExecutableLocation? = nativeExecutable,
        enabledProviders: Set<UsageProvider> = Set(UsageProvider.allCases)
    ) -> ClaudeUIPreviewFixture {
        ClaudeUIPreviewFixture(
            access: access,
            refresh: refresh,
            claudeSnapshot: claude,
            executable: executable,
            enabledProviders: enabledProviders
        )
    }

    private static var nativeExecutable: ClaudeExecutableLocation {
        ClaudeExecutableLocation(
            invokedURL: URL(fileURLWithPath: "/Users/preview/.local/bin/claude"),
            resolvedURL: URL(fileURLWithPath: "/Users/preview/.local/share/claude/versions/2.0.14/claude"),
            provenance: .native
        )
    }

    private static var unknownExecutable: ClaudeExecutableLocation {
        ClaudeExecutableLocation(
            invokedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
            resolvedURL: URL(fileURLWithPath: "/opt/tools/bin/claude"),
            provenance: .unknown
        )
    }

    private static func reading(
        usedPercent: Double = 58,
        source: SnapshotSource = .claudeUsageCLI,
        confidence: SnapshotConfidence = .exact,
        updatedAt: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .available(
                usedPercent: usedPercent,
                resetAt: updatedAt.addingTimeInterval(4.5 * 60 * 60),
                durationMinutes: 300
            ),
            source: source,
            confidence: confidence,
            updatedAt: updatedAt
        )
    }

    private static func unavailable(at date: Date) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .claude,
            rateWindow: .unavailable,
            source: .claudeUsageCLI,
            confidence: .unavailable,
            updatedAt: date
        )
    }
}

struct ClaudeUIPreviewFixture {
    let access: ClaudeAccessState
    let refresh: ClaudeRefreshState
    let claudeSnapshot: ProviderSnapshot
    let executable: ClaudeExecutableLocation?
    let enabledProviders: Set<UsageProvider>

    @MainActor
    func makeViewModel() -> PromptJuiceViewModel {
        let defaults = UserDefaults(suiteName: "PromptJuice.ClaudeUIPreview")!
        defaults.set(enabledProviders.map(\.rawValue), forKey: "enabledProviders")
        let store = PromptJuiceSettingsStore(defaults: defaults)
        let codex = ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: 25,
                resetAt: Date().addingTimeInterval(3 * 60 * 60),
                durationMinutes: 300
            ),
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: Date()
        )
        let state = ClaudeUsageCoordinatorState(
            access: access,
            refresh: refresh,
            snapshot: claudeSnapshot
        )
        let recheckAccess: ClaudeAccessState = switch access {
        case .cliMissing:
            .signedOut(reason: .initial)
        case .signedOut, .updateRequired, .workspaceTrustRequired:
            .subscription(plan: "Max")
        default:
            access
        }
        return PromptJuiceViewModel(
            settingsStore: store,
            liveClaudeProviderClient: ClaudeUIPreviewProviderClient(snapshot: claudeSnapshot),
            liveCodexProviderClient: ClaudeUIPreviewProviderClient(snapshot: codex),
            claudeUsageCoordinator: ClaudeUIPreviewCoordinator(state: state),
            claudeGuidanceChecker: ClaudeUIPreviewGuidanceChecker(result: ClaudeGuidanceCheckResult(
                access: recheckAccess,
                location: executable
            )),
            claudeExecutableLocator: { executable },
            initialSnapshots: [claudeSnapshot, codex],
            initialClaudeAccessState: access,
            initialClaudeRefreshState: refresh
        )
    }
}

private struct ClaudeUIPreviewProviderClient: UsageProviderClient {
    let snapshot: ProviderSnapshot
    var source: SnapshotSource { snapshot.source }

    func snapshots(now _: Date) -> [ProviderSnapshot] {
        [snapshot]
    }
}

private actor ClaudeUIPreviewCoordinator: ClaudeUsageSnapshotProviding {
    let state: ClaudeUsageCoordinatorState

    init(state: ClaudeUsageCoordinatorState) {
        self.state = state
    }

    func snapshot(
        now _: Date,
        reason _: ClaudeRefreshReason,
        force _: Bool,
        providerEnabled _: Bool,
        isAwake _: Bool,
        isOnline _: Bool
    ) async -> ClaudeUsageCoordinatorState {
        state
    }
}

private struct ClaudeUIPreviewGuidanceChecker: ClaudeGuidanceChecking {
    let result: ClaudeGuidanceCheckResult

    func check(journey _: ClaudeGuidanceJourney) -> ClaudeGuidanceCheckResult {
        result
    }
}

extension PromptJuiceViewModel {
    static func makeAppViewModel(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PromptJuiceViewModel {
        guard let rawScenario = environment["PROMPTJUICE_CLAUDE_UI_SCENARIO"],
              let scenario = ClaudeUIPreviewScenario(rawValue: rawScenario) else {
            return PromptJuiceViewModel()
        }
        return scenario.fixture.makeViewModel()
    }
}
#else
extension PromptJuiceViewModel {
    static func makeAppViewModel() -> PromptJuiceViewModel {
        PromptJuiceViewModel()
    }
}
#endif
