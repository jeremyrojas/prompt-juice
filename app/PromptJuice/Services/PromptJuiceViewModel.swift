import Foundation
import SwiftUI

@MainActor
final class PromptJuiceViewModel: ObservableObject {
    @Published private(set) var snapshots: [UsageSnapshot]
    @Published private(set) var mode: PanelMode = .manual
    @Published private(set) var actionMessage: String?
    @Published private(set) var thresholds: AlertThresholds
    @Published private(set) var sourceMode: UsageSourceMode
    @Published private(set) var enabledProviders: Set<UsageProvider>

    private let settingsStore: PromptJuiceSettingsStore
    private let alertEngine: AlertEngine
    private let now: () -> Date
    private let injectedProviderClient: (any UsageProviderClient)?
    private var providerClient: any UsageProviderClient
    private var refreshTask: Task<Void, Never>?

    init(
        settingsStore: PromptJuiceSettingsStore = .shared,
        providerClient: (any UsageProviderClient)? = nil,
        alertEngine: AlertEngine = AlertEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        let initialSourceMode = settingsStore.usageSourceMode
        let initialEnabledProviders = settingsStore.enabledProviders

        self.settingsStore = settingsStore
        self.injectedProviderClient = providerClient
        self.sourceMode = initialSourceMode
        self.enabledProviders = initialEnabledProviders
        self.providerClient = providerClient ?? Self.makeProviderClient(
            sourceMode: initialSourceMode
        )
        self.alertEngine = alertEngine
        self.now = now
        thresholds = settingsStore.thresholds
        snapshots = if let providerClient {
            providerClient.snapshots(now: now())
        } else {
            Self.cachedOrUnavailableSnapshots(
                sourceMode: initialSourceMode,
                now: now()
            )
        }
    }

    var visibleSnapshots: [UsageSnapshot] {
        snapshots.filter { enabledProviders.contains($0.provider) }
    }

    var primarySnapshot: UsageSnapshot? {
        visibleSnapshots
            .filter(\.isAvailable)
            .min { first, second in
                first.resetAt < second.resetAt
            }
    }

    /// True when a provider has no usable reading (the "Not measured yet" state).
    func isUnavailable(_ provider: UsageProvider) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.provider == provider }) else {
            return true
        }
        return !snapshot.isAvailable
    }

    // MARK: - Severity

    /// Per-provider judgment for the row chip, bar color, and header tint.
    func severity(for snapshot: UsageSnapshot) -> UsageSeverity {
        alertEngine.severity(for: snapshot, thresholds: thresholds, now: now())
    }

    /// Worst-wins judgment across all providers.
    var aggregateSeverity: UsageSeverity {
        alertEngine.aggregateSeverity(
            in: visibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    /// Header droplet tint — the aggregate judgment across providers.
    var headerSeverity: UsageSeverity {
        aggregateSeverity
    }

    /// Fill level for the header droplet (0...100), matching `headerSeverity`.
    var headerRemainingPercent: Double {
        menuBarRemainingPercent
    }

    /// Tint for the menu-bar glyph — the worst judgment across providers.
    var menuBarSeverity: UsageSeverity {
        aggregateSeverity
    }

    /// Fill for the menu-bar glyph — the binding constraint (lowest remaining
    /// among available providers). 100 when nothing is available yet.
    var menuBarRemainingPercent: Double {
        // Clash rule: when a use-soon nudge is active, the fill follows the nudged
        // provider (the actionable one), not the lowest — so an amber droplet
        // matches its "use it" headline instead of showing the other provider's low %.
        if aggregateSeverity == .useSoon, let alertSnapshot {
            return alertSnapshot.remainingPercent
        }

        let available = visibleSnapshots.filter(\.isAvailable)

        guard !available.isEmpty else {
            return 100
        }

        return available.map(\.remainingPercent).min() ?? 100
    }

    /// Manual-mode verdict headline — the answer, not the mechanism.
    private var manualVerdict: String {
        switch aggregateSeverity {
        case .healthy:
            return "Plenty of prompt juice left"
        case .useSoon:
            let soon = alertingSnapshots
            if soon.count > 1 {
                return "Use prompt juice soon"
            }
            if let one = soon.first {
                return "Use \(one.displayName) before it resets"
            }
            return "Use prompt juice soon"
        case .low:
            let lows = lowSnapshots
            if lows.count > 1 {
                return "Running low on both"
            }
            if let one = lows.first {
                return "\(one.displayName) is running low"
            }
            return "Running low on juice"
        case .empty:
            let outs = emptySnapshots
            if outs.count == 1, let one = outs.first {
                return "\(one.displayName) is out"
            }
            return "Out of prompt juice"
        case .unavailable:
            return "Not measured yet"
        }
    }

    private var lowSnapshots: [UsageSnapshot] {
        visibleSnapshots.filter { $0.isAvailable && severity(for: $0) == .low }
    }

    private var emptySnapshots: [UsageSnapshot] {
        visibleSnapshots.filter { severity(for: $0) == .empty }
    }

    /// Manual-mode subtitle — the live aggregate the static label used to hide.
    private var manualSubtitle: String {
        guard visibleSnapshots.contains(where: \.isAvailable) else {
            return "Usage unavailable"
        }

        var parts = visibleSnapshots.map { snapshot -> String in
            snapshot.isAvailable
                ? "\(snapshot.displayName) \(remainingPercentValueText(for: snapshot))"
                : "\(snapshot.displayName) n/a"
        }

        if let soonest = primarySnapshot {
            parts.append(fullResetText(for: soonest))
        }

        return parts.joined(separator: " · ")
    }

    var headline: String {
        switch mode {
        case .manual:
            return manualVerdict
        case .alert:
            guard let alertSnapshot else {
                return "Plenty of prompt juice left"
            }

            let alertingSnapshots = self.alertingSnapshots

            if alertingSnapshots.count > 1 {
                return "Use prompt juice soon"
            }

            if shouldUseSoon(for: alertSnapshot) {
                return "\(alertSnapshot.displayName): \(remainingPercentValueText(for: alertSnapshot)) to use"
            }

            return "\(alertSnapshot.displayName) has \(remainingPercentText(for: alertSnapshot))"
        case .snoozed:
            return "Snoozed for this window"
        }
    }

    var detail: String {
        switch mode {
        case .manual:
            return manualSubtitle
        case .alert:
            let alertingSnapshots = self.alertingSnapshots

            if alertingSnapshots.count > 1 {
                return alertingSnapshots
                    .map { "\($0.displayName) \(remainingPercentText(for: $0)), \(resetText(for: $0))" }
                    .joined(separator: " · ")
            }

            if let alertSnapshot {
                if shouldUseSoon(for: alertSnapshot) {
                    return fullResetText(for: alertSnapshot)
                }

                return "\(remainingPercentText(for: alertSnapshot)) · \(fullResetText(for: alertSnapshot))"
            }

            return "Good time to launch agents."
        case .snoozed:
            return "PromptJuice will stay quiet."
        }
    }

    private var alertSnapshot: UsageSnapshot? {
        alertEngine.preferredSnapshot(
            in: visibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    private var alertingSnapshots: [UsageSnapshot] {
        alertEngine.alertingSnapshots(
            in: visibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    func showManualCheck() {
        mode = .manual
        actionMessage = nil
        clearSnoozeForCurrentWindow()
        refreshSnapshotsInBackground()
    }

    @discardableResult
    func checkUsageAlert(force: Bool = false) -> Bool {
        actionMessage = nil

        if force {
            clearSnoozeForCurrentWindow()
            mode = .alert
            return true
        }

        guard hasPendingAlert, !isCurrentWindowSnoozed else {
            mode = .manual
            return false
        }

        mode = .alert
        return true
    }

    func snooze() {
        if mode == .alert {
            settingsStore.snoozedUsageWindowID = currentWindowID
        }

        mode = .snoozed
        actionMessage = nil
    }

    func dismissCurrentWindow() {
        actionMessage = nil
    }

    func setRemainingMinutesThreshold(_ value: Int) {
        thresholds.remainingMinutes = value
        settingsStore.saveThresholds(thresholds)
        refreshModeForThresholds()
    }

    func setRemainingPercentThreshold(_ value: Int) {
        thresholds.remainingPercent = value
        settingsStore.saveThresholds(thresholds)
        refreshModeForThresholds()
    }

    func setProviderEnabled(_ provider: UsageProvider, _ enabled: Bool) {
        var next = enabledProviders

        if enabled {
            next.insert(provider)
        } else {
            next.remove(provider)
        }

        guard !next.isEmpty, next != enabledProviders else {
            return
        }

        settingsStore.enabledProviders = next
        enabledProviders = settingsStore.enabledProviders
        refreshModeForThresholds()
    }

    func refreshUsage() {
        actionMessage = "Refreshing \(sourceMode.title.lowercased())."
        refreshSnapshotsInBackground(
            completionMessage: "\(sourceMode.title) refreshed."
        ) { [weak self] in
            guard let self else {
                return
            }

            if self.mode == .alert && !self.hasPendingAlert {
                self.mode = .manual
            }
        }
    }

    func refreshUsageAlertInBackground(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        refreshSnapshotsInBackground { [weak self] in
            guard let self else {
                completion(false)
                return
            }

            completion(self.checkUsageAlert())
        }
    }

    func setUsageSourceMode(_ mode: UsageSourceMode) {
        setUsageSourceMode(mode, persist: true, announce: true)
    }

    func tick() {
        objectWillChange.send()
    }

    func percentText(for snapshot: UsageSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Unavailable"
        }

        return remainingPercentText(for: snapshot)
    }

    func remainingPercentText(for snapshot: UsageSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "unavailable"
        }

        return "\(Int(snapshot.remainingPercent.rounded()))% left"
    }

    func remainingPercentValueText(for snapshot: UsageSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "n/a"
        }

        return "\(Int(snapshot.remainingPercent.rounded()))%"
    }

    func remainingText(for snapshot: UsageSnapshot) -> String {
        guard let minutes = snapshot.rateWindow.minutesUntilReset(now: now()) else {
            return "Unavailable"
        }

        if minutes < 60 {
            return "\(minutes)m left"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m left"
    }

    func resetText(for snapshot: UsageSnapshot) -> String {
        guard let minutes = snapshot.rateWindow.minutesUntilReset(now: now()) else {
            return "n/a"
        }

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m"
    }

    func fullResetText(for snapshot: UsageSnapshot) -> String {
        "resets in \(resetText(for: snapshot))"
    }

    func shouldUseSoon(for snapshot: UsageSnapshot) -> Bool {
        alertEngine.shouldUseSoon(
            for: snapshot,
            thresholds: thresholds,
            now: now()
        )
    }

    func statusText(for snapshot: UsageSnapshot) -> String {
        alertEngine.statusText(
            for: snapshot,
            thresholds: thresholds,
            now: now()
        )
    }

    /// Friendly hover text for a row — where the reading came from, stated as a
    /// fact (never a promise). Lives in a tooltip, never inline.
    func sourceTooltip(for snapshot: UsageSnapshot) -> String {
        let label: String
        switch snapshot.source {
        case .claudeStatusline, .claudeCache:
            label = "Claude Code"
        case .claudeLocalLogs:
            label = "local Claude Code activity"
        case .codexAppServer, .codexCache:
            label = "Codex app-server"
        case .codexStub, .fixture:
            label = "a fixture"
        }

        switch snapshot.confidence {
        case .exact:
            return "Read from \(label)"
        case .estimated:
            return "Estimated from \(label)"
        case .stale:
            return "Read from \(label) · \(clockTime(snapshot.updatedAt))"
        case .unavailable:
            return snapshot.statusDetail ?? "Not measured yet"
        }
    }

    func settingsStatusText(for provider: UsageProvider) -> String {
        guard let snapshot = snapshots.first(where: { $0.provider == provider }),
              snapshot.isAvailable else {
            return provider == .claude ? "Not set up yet" : "Not detected"
        }

        switch snapshot.confidence {
        case .exact:
            if provider == .codex {
                return "Live · \(fullResetText(for: snapshot))"
            }
            return "Live"
        case .estimated:
            return "Estimate"
        case .stale:
            return "Read earlier · \(clockTime(snapshot.updatedAt))"
        case .unavailable:
            return provider == .claude ? "Not set up yet" : "Not detected"
        }
    }

    private func clockTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private var hasPendingAlert: Bool {
        !alertingSnapshots.isEmpty
    }

    private var isCurrentWindowSnoozed: Bool {
        settingsStore.snoozedUsageWindowID == currentWindowID
    }

    private var currentWindowID: String {
        let windowParts = visibleSnapshots
            .map(\.resetWindowID)
            .joined(separator: "|")

        return "\(sourceMode.rawValue)-\(windowParts)"
    }

    private func clearSnoozeForCurrentWindow() {
        if isCurrentWindowSnoozed {
            settingsStore.snoozedUsageWindowID = nil
        }
    }

    private func refreshModeForThresholds() {
        actionMessage = nil

        if mode == .alert && !hasPendingAlert {
            mode = .manual
        }

        objectWillChange.send()
    }

    private func setUsageSourceMode(
        _ mode: UsageSourceMode,
        persist: Bool,
        announce: Bool
    ) {
        sourceMode = mode

        if persist {
            settingsStore.usageSourceMode = mode
        }

        configureProviderClient()
        snapshots = Self.cachedOrUnavailableSnapshots(
            sourceMode: mode,
            now: now()
        )
        refreshSnapshotsInBackground()

        if announce {
            actionMessage = "\(mode.title) selected."
        }
    }

    private func configureProviderClient() {
        if let injectedProviderClient {
            providerClient = injectedProviderClient
            return
        }

        providerClient = Self.makeProviderClient(
            sourceMode: sourceMode
        )
    }

    private func refreshSnapshotsInBackground(
        completionMessage: String? = nil,
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        refreshTask?.cancel()

        let providerClient = providerClient
        let refreshDate = now()

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            let refreshedSnapshots = providerClient.snapshots(now: refreshDate)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else {
                    return
                }

                self.snapshots = refreshedSnapshots

                if let completionMessage {
                    self.actionMessage = completionMessage
                }

                completion?()
            }
        }
    }

    private static func makeProviderClient(sourceMode: UsageSourceMode) -> any UsageProviderClient {
        switch sourceMode {
        case .fixture:
            return FixtureUsageProviderClient(scenario: .underusedCodex)
        case .liveCodex:
            return ClaudeLiveUsageProviderClient()
        }
    }

    private static func cachedOrUnavailableSnapshots(
        sourceMode: UsageSourceMode,
        now: Date
    ) -> [ProviderSnapshot] {
        switch sourceMode {
        case .fixture:
            return FixtureUsageProviderClient(scenario: .underusedCodex)
                .snapshots(now: now)
        case .liveCodex:
            return [
                ClaudeSnapshotCache.shared.snapshot(
                    now: now,
                    failureDetail: "Refreshing usage"
                ) ?? unavailableSnapshot(
                    identity: .claude,
                    source: .claudeStatusline,
                    now: now
                ),
                CodexSnapshotCache.shared.snapshot(
                    now: now,
                    failureDetail: "Refreshing usage"
                ) ?? unavailableSnapshot(
                    identity: .codex,
                    source: .codexAppServer,
                    now: now
                )
            ]
        }
    }

    private static func unavailableSnapshot(
        identity: ProviderIdentity,
        source: SnapshotSource,
        now: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: identity,
            rateWindow: .unavailable,
            source: source,
            confidence: .unavailable,
            updatedAt: now,
            statusDetail: "Refreshing usage"
        )
    }
}
