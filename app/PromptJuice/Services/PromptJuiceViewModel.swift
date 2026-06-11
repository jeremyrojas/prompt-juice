import Foundation
import SwiftUI

@MainActor
final class PromptJuiceViewModel: ObservableObject {
    @Published private(set) var snapshots: [UsageSnapshot]
    @Published private(set) var mode: PanelMode = .manual
    @Published private(set) var actionMessage: String?
    @Published private(set) var selectedProvider: UsageProvider?
    @Published private(set) var thresholds: AlertThresholds
    @Published private(set) var sourceMode: UsageSourceMode

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

        self.settingsStore = settingsStore
        self.injectedProviderClient = providerClient
        self.sourceMode = initialSourceMode
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

    var primarySnapshot: UsageSnapshot? {
        snapshots
            .filter(\.isAvailable)
            .min { first, second in
                first.resetAt < second.resetAt
            }
    }

    // MARK: - Severity

    /// Per-provider judgment for the row chip, bar color, and header tint.
    func severity(for snapshot: UsageSnapshot) -> UsageSeverity {
        alertEngine.severity(for: snapshot, thresholds: thresholds, now: now())
    }

    /// Worst-wins judgment across all providers.
    var aggregateSeverity: UsageSeverity {
        alertEngine.aggregateSeverity(in: snapshots, thresholds: thresholds, now: now())
    }

    /// Header droplet follows selection: the selected provider when one is
    /// chosen, otherwise the aggregate.
    var headerSeverity: UsageSeverity {
        if let selectedSnapshot {
            return severity(for: selectedSnapshot)
        }

        return aggregateSeverity
    }

    /// Fill level for the header droplet (0...100), matching `headerSeverity`.
    var headerRemainingPercent: Double {
        if let selectedSnapshot {
            return selectedSnapshot.isAvailable ? selectedSnapshot.remainingPercent : 0
        }

        return menuBarRemainingPercent
    }

    /// Tint for the menu-bar glyph — the worst judgment across providers.
    var menuBarSeverity: UsageSeverity {
        aggregateSeverity
    }

    /// Fill for the menu-bar glyph — the binding constraint (lowest remaining
    /// among available providers). 100 when nothing is available yet.
    var menuBarRemainingPercent: Double {
        let available = snapshots.filter(\.isAvailable)

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
            return "Use it before reset"
        case .low:
            return "Running low on juice"
        case .empty:
            return "Out of prompt juice"
        case .unavailable:
            return "Usage unavailable"
        }
    }

    /// Manual-mode subtitle — the live aggregate the static label used to hide.
    private var manualSubtitle: String {
        guard snapshots.contains(where: \.isAvailable) else {
            return "Usage unavailable"
        }

        var parts = snapshots.map { snapshot -> String in
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
        if let selectedSnapshot {
            if shouldUseSoon(for: selectedSnapshot) {
                return "\(selectedSnapshot.displayName): \(remainingPercentValueText(for: selectedSnapshot)) to use"
            }

            return "\(selectedSnapshot.displayName) has \(remainingPercentText(for: selectedSnapshot))"
        }

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
        if let selectedSnapshot {
            let sourceText = sourceText(for: selectedSnapshot)

            if !selectedSnapshot.isAvailable {
                return [sourceText, selectedSnapshot.statusDetail]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            }

            if shouldUseSoon(for: selectedSnapshot) {
                return "\(fullResetText(for: selectedSnapshot)) · \(sourceText)"
            }

            return "\(remainingPercentText(for: selectedSnapshot)) · \(fullResetText(for: selectedSnapshot))"
        }

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

    private var selectedSnapshot: UsageSnapshot? {
        guard let selectedProvider else {
            return nil
        }

        return snapshots.first { $0.provider == selectedProvider }
    }

    private var alertSnapshot: UsageSnapshot? {
        alertEngine.preferredSnapshot(
            in: snapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    private var alertingSnapshots: [UsageSnapshot] {
        alertEngine.alertingSnapshots(
            in: snapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    func showManualCheck() {
        mode = .manual
        actionMessage = nil
        selectedProvider = nil
        clearSnoozeForCurrentWindow()
        refreshSnapshotsInBackground()
    }

    @discardableResult
    func checkUsageAlert(force: Bool = false) -> Bool {
        actionMessage = nil
        selectedProvider = nil

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
        selectedProvider = nil
    }

    func dismissCurrentWindow() {
        if mode == .alert {
            settingsStore.snoozedUsageWindowID = currentWindowID
        }

        actionMessage = nil
        selectedProvider = nil
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

    func selectProvider(_ provider: UsageProvider) {
        selectedProvider = provider
        actionMessage = nil
    }

    func clearSelection() {
        selectedProvider = nil
        actionMessage = nil
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

    func sourceText(for snapshot: UsageSnapshot) -> String {
        let source = switch snapshot.source {
        case .fixture:
            "fixture"
        case .codexStub:
            "Codex stub"
        case .codexAppServer:
            "Codex app-server"
        case .codexCache:
            "Codex cache"
        case .claudeStatusline:
            "Claude statusline"
        case .claudeLocalLogs:
            "Claude local logs"
        case .claudeCache:
            "Claude cache"
        }

        return "\(source) · \(snapshot.confidence.rawValue)"
    }

    private var hasPendingAlert: Bool {
        !alertingSnapshots.isEmpty
    }

    private var isCurrentWindowSnoozed: Bool {
        settingsStore.snoozedUsageWindowID == currentWindowID
    }

    private var currentWindowID: String {
        let windowParts = snapshots
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
        actionMessage = "Alerts: \(thresholds.remainingMinutes)m / \(thresholds.remainingPercent)%"

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
