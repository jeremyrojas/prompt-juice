import Foundation
import SwiftUI

enum ClaudeLiveUpgrade: Equatable {
    case live
    case setupAvailable
    case awaitingSession
}

private typealias RefreshCompletion = @MainActor @Sendable () -> Void

@MainActor
final class PromptJuiceViewModel: ObservableObject {
    @Published private(set) var snapshots: [UsageSnapshot]
    @Published private(set) var mode: PanelMode = .manual
    /// Row the user tapped to scope the header summary to a single provider.
    /// `nil` shows the combined overview. Cleared when the panel is dismissed.
    @Published private(set) var selectedProvider: UsageProvider?
    @Published private(set) var actionMessage: String?
    @Published private(set) var thresholds: AlertThresholds
    @Published private(set) var sourceMode: UsageSourceMode
    @Published private(set) var enabledProviders: Set<UsageProvider>

    private let settingsStore: PromptJuiceSettingsStore
    private let alertEngine: AlertEngine
    private let now: () -> Date
    private let isClaudeBridgeCurrent: () -> Bool
    private let injectedProviderClient: (any UsageProviderClient)?
    private let claudeStatusCacheProviderClient: any UsageProviderClient
    private let liveClaudeProviderClient: any UsageProviderClient
    private let liveCodexProviderClient: any UsageProviderClient
    private var providerClient: any UsageProviderClient
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var hasPendingRefresh = false
    private var pendingRefreshCompletionMessage: String?
    private var pendingRefreshCompletions: [RefreshCompletion] = []
    private var expiredWindowRefreshKeys = Set<String>()
    private var claudeStatusCacheRefreshTask: Task<Void, Never>?
    private var claudeStatusCacheRefreshTimeoutTask: Task<Void, Never>?
    private var activeClaudeStatusCacheRefreshID: UUID?
    private var claudeStatusCacheRefreshStartedAt: Date?
    private var isClaudeStatusCacheRefreshInFlight = false
    private var hasPendingClaudeStatusCacheRefresh = false
    private var isClaudeBridgeCurrentState: Bool
    private let claudeStatusCacheRefreshTimeoutNanoseconds: UInt64

    init(
        settingsStore: PromptJuiceSettingsStore = .shared,
        providerClient: (any UsageProviderClient)? = nil,
        claudeStatusCacheProviderClient: (any UsageProviderClient)? = nil,
        liveClaudeProviderClient: (any UsageProviderClient)? = nil,
        liveCodexProviderClient: (any UsageProviderClient)? = nil,
        alertEngine: AlertEngine = AlertEngine(),
        now: @escaping () -> Date = Date.init,
        claudeStatusCacheRefreshTimeoutNanoseconds: UInt64 = 5_000_000_000,
        isClaudeBridgeCurrent: @escaping () -> Bool = {
            ClaudeBridgeInstaller().isBridgeCurrent()
        }
    ) {
        let initialSourceMode = settingsStore.usageSourceMode
        let initialEnabledProviders = settingsStore.enabledProviders
        let liveClaudeClient = liveClaudeProviderClient ?? ClaudeProviderClient(localEstimatePolicy: .invalidStatuslineOnly)
        let liveCodexClient = liveCodexProviderClient ?? CodexProviderClient()

        self.settingsStore = settingsStore
        self.injectedProviderClient = providerClient
        self.liveClaudeProviderClient = liveClaudeClient
        self.liveCodexProviderClient = liveCodexClient
        self.claudeStatusCacheProviderClient = claudeStatusCacheProviderClient ?? liveClaudeClient
        self.sourceMode = initialSourceMode
        self.enabledProviders = initialEnabledProviders
        self.providerClient = providerClient ?? Self.makeProviderClient(
            sourceMode: initialSourceMode
        )
        self.alertEngine = alertEngine
        self.now = now
        self.claudeStatusCacheRefreshTimeoutNanoseconds = claudeStatusCacheRefreshTimeoutNanoseconds
        self.isClaudeBridgeCurrent = isClaudeBridgeCurrent
        self.isClaudeBridgeCurrentState = isClaudeBridgeCurrent()
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

    var isCheckingUsage: Bool {
        let visible = visibleSnapshots
        guard !visible.isEmpty else {
            return false
        }

        return !visible.contains(where: \.isAvailable)
            && visible.contains { isRefreshing($0.provider) }
    }

    var isFirstRun: Bool {
        settingsStore.isFirstRun
    }

    var primarySnapshot: UsageSnapshot? {
        let refreshDate = now()
        return visibleSnapshots
            .filter { $0.hasActiveResetWindow(at: refreshDate) }
            .min { first, second in
                (first.rateWindow.resetAt ?? .distantFuture) < (second.rateWindow.resetAt ?? .distantFuture)
            }
    }

    var claudeLiveUpgrade: ClaudeLiveUpgrade {
        if let claude = snapshots.first(where: { $0.provider == .claude }),
           claude.confidence == .exact || claude.isFreshSessionWindow {
            return .live
        }

        return isClaudeBridgeCurrentState ? .awaitingSession : .setupAvailable
    }

    /// True when a provider has no usable reading (the "Not measured yet" state).
    func isUnavailable(_ provider: UsageProvider) -> Bool {
        guard let snapshot = snapshots.first(where: { $0.provider == provider }) else {
            return true
        }
        return !snapshot.isAvailable
    }

    func isRefreshing(_ provider: UsageProvider) -> Bool {
        snapshots.first(where: { $0.provider == provider })?.statusDetail == "Refreshing usage"
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

    /// Header droplet tint — the selected provider's judgment when a row is
    /// picked, otherwise the aggregate across providers.
    var headerSeverity: UsageSeverity {
        if let snapshot = selectedSnapshot {
            return severity(for: snapshot)
        }

        return aggregateSeverity
    }

    /// Fill level for the header droplet (0...100), matching `headerSeverity`.
    var headerRemainingPercent: Double {
        if let snapshot = selectedSnapshot {
            return snapshot.remainingPercent
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
        // Clash rule: when a use-soon nudge is active, the fill follows the nudged
        // provider's effective remaining so the amber droplet matches its headline.
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
        if isCheckingUsage {
            return "Checking usage…"
        }

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
        if isCheckingUsage {
            return "Just a moment…"
        }

        guard visibleSnapshots.contains(where: \.isAvailable) else {
            return "Usage unavailable"
        }

        var parts = visibleSnapshots.map { snapshot -> String in
            if snapshot.isFreshSessionWindow {
                return "\(snapshot.displayName) Fresh window"
            }

            return snapshot.isAvailable
                ? "\(snapshot.displayName) \(remainingPercentDisplayValueText(for: snapshot))"
                : unavailableHeaderSubtitle(for: snapshot)
        }

        if let soonest = primarySnapshot {
            parts.append(fullResetText(for: soonest))
        }

        return parts.joined(separator: " · ")
    }

    private func unavailableHeaderSubtitle(for snapshot: UsageSnapshot) -> String {
        guard snapshot.provider == .claude else {
            return "\(snapshot.displayName) not detected"
        }

        return switch claudeLiveUpgrade {
        case .awaitingSession:
            "\(snapshot.displayName) waiting for terminal"
        case .live, .setupAvailable:
            "\(snapshot.displayName) not set up"
        }
    }

    var headline: String {
        if mode != .snoozed, let snapshot = selectedSnapshot {
            return scopedHeadline(for: snapshot)
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
                return "\(alertSnapshot.displayName): \(remainingPercentDisplayValueText(for: alertSnapshot)) to use"
            }

            return "\(alertSnapshot.displayName) has \(remainingPercentText(for: alertSnapshot))"
        case .snoozed:
            return "Snoozed for this window"
        }
    }

    var detail: String {
        if mode != .snoozed, let snapshot = selectedSnapshot {
            return scopedDetail(for: snapshot)
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

    // MARK: - Selection

    /// The tapped provider's snapshot, but only while it has a usable reading.
    /// Scoping the header to a "not measured yet" provider says nothing, so it
    /// falls back to the overview.
    private var selectedSnapshot: UsageSnapshot? {
        guard let selectedProvider,
              let snapshot = visibleSnapshots.first(where: { $0.provider == selectedProvider }),
              snapshot.isAvailable else {
            return nil
        }

        return snapshot
    }

    /// True only when the Claude row is showing its "Set up" cue — the one state
    /// where tapping the row opens Settings instead of selecting it. Keeps the
    /// visible button and the click behavior in lockstep.
    var claudeRowOffersSetup: Bool {
        isUnavailable(.claude)
            && !isRefreshing(.claude)
            && claudeLiveUpgrade == .setupAvailable
    }

    /// Toggle the scoped summary for a provider. Only providers with a reading can
    /// be selected; tapping the selected one again returns to the overview.
    func toggleSelection(_ provider: UsageProvider) {
        guard let snapshot = visibleSnapshots.first(where: { $0.provider == provider }),
              snapshot.isAvailable else {
            return
        }

        selectedProvider = (selectedProvider == provider) ? nil : provider
    }

    func clearSelection() {
        selectedProvider = nil
    }

    private func scopedHeadline(for snapshot: UsageSnapshot) -> String {
        switch severity(for: snapshot) {
        case .healthy:
            return "\(snapshot.displayName) has plenty of juice"
        case .useSoon:
            return "Use \(snapshot.displayName) before it resets"
        case .low:
            return "\(snapshot.displayName) is running low"
        case .empty:
            return "\(snapshot.displayName) is out"
        case .unavailable:
            return unavailableHeaderSubtitle(for: snapshot)
        }
    }

    private func scopedDetail(for snapshot: UsageSnapshot) -> String {
        var parts: [String]

        if snapshot.isFreshSessionWindow {
            parts = ["Fresh window", "starts with your next Claude Code message"]
        } else {
            parts = [
                sessionRemainingPercentDisplayValueText(for: snapshot),
                fullResetText(for: snapshot)
            ]
        }

        if let weeklyText = weeklyText(for: snapshot) {
            parts.append(weeklyText)
        }

        return parts.joined(separator: " · ")
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

        if enabled {
            refreshSnapshotsInBackground()
        }
    }

    func completeFirstRun(enabledProviders: Set<UsageProvider>) {
        guard !enabledProviders.isEmpty else {
            return
        }

        settingsStore.enabledProviders = enabledProviders
        self.enabledProviders = settingsStore.enabledProviders
        refreshModeForThresholds()
    }

    func refreshUsage() {
        refreshClaudeBridgeState()
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

    func refreshUsageQuietly() {
        refreshClaudeBridgeState()
        refreshSnapshotsInBackground()
    }

    func refreshClaudeAfterStatusCacheChange(reason: String = "cache change") {
        guard sourceMode == .liveCodex,
              enabledProviders.contains(.claude) else {
            PromptJuiceLog.usage.notice("Claude status cache refresh skipped: \(reason, privacy: .public)")
            return
        }

        recoverStaleClaudeStatusCacheRefreshIfNeeded(reason: reason)

        if isClaudeStatusCacheRefreshInFlight {
            hasPendingClaudeStatusCacheRefresh = true
            PromptJuiceLog.usage.notice("Claude status cache refresh coalesced: \(reason, privacy: .public)")
            return
        }

        startClaudeStatusCacheRefresh(reason: reason)
    }

    func refreshClaudeStatusCacheNow(reason: String) {
        refreshClaudeBridgeState()
        PromptJuiceLog.usage.notice("Claude status cache catch-up requested: \(reason, privacy: .public)")
        refreshClaudeAfterStatusCacheChange(reason: reason)
    }

    func refreshUsageAlertInBackground(
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        refreshClaudeBridgeState()
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
        refreshExpiredSnapshotsIfNeeded()
        ageExactClaudeSnapshotsIfNeeded()
        objectWillChange.send()
    }

    func refreshClaudeBridgeState() {
        isClaudeBridgeCurrentState = isClaudeBridgeCurrent()
        if isClaudeBridgeCurrentState {
            PromptJuiceLog.usage.debug("Claude bridge check passed")
        } else {
            PromptJuiceLog.usage.debug("Claude bridge check missing")
        }
    }

    private func refreshExpiredSnapshotsIfNeeded() {
        let refreshDate = now()
        let expiredSnapshots = visibleSnapshots.filter { $0.isExpired(at: refreshDate) }

        guard !expiredSnapshots.isEmpty else {
            return
        }

        let refreshKey = expiredSnapshots
            .map(\.resetWindowID)
            .sorted()
            .joined(separator: "|")

        replaceExpiredSnapshots(expiredSnapshots, at: refreshDate)

        guard expiredWindowRefreshKeys.insert(refreshKey).inserted else {
            return
        }

        refreshUsageQuietly()
    }

    private func ageExactClaudeSnapshotsIfNeeded() {
        let refreshDate = now()
        var didAgeSnapshot = false

        let agedSnapshots = snapshots.map { snapshot in
            guard snapshot.identity == .claude,
                  snapshot.source == .claudeStatusline,
                  snapshot.confidence == .exact,
                  !snapshot.isFreshSessionWindow,
                  refreshDate.timeIntervalSince(snapshot.updatedAt) > ClaudeStatuslineSnapshotReader.maximumCacheAge else {
                return snapshot
            }

            didAgeSnapshot = true
            return ProviderSnapshot(
                identity: snapshot.identity,
                rateWindow: snapshot.rateWindow,
                weeklyWindow: snapshot.weeklyWindow,
                source: snapshot.source,
                confidence: .stale,
                updatedAt: snapshot.updatedAt,
                weeklyUpdatedAt: snapshot.weeklyUpdatedAt,
                statusDetail: snapshot.statusDetail,
                isFreshSessionWindow: snapshot.isFreshSessionWindow,
                isFreshWeeklyWindow: snapshot.isFreshWeeklyWindow
            )
        }

        if didAgeSnapshot {
            snapshots = agedSnapshots
            logSnapshotState(reason: "exact snapshot aged")
        }
    }

    func percentText(for snapshot: UsageSnapshot) -> String {
        remainingPercentText(for: snapshot, basis: .effective, unavailableText: "Unavailable")
    }

    func remainingPercentText(for snapshot: UsageSnapshot) -> String {
        remainingPercentText(for: snapshot, basis: .effective, unavailableText: "unavailable")
    }

    func remainingPercentValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentValueText(for: snapshot, basis: .effective)
    }

    func remainingPercentDisplayValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentDisplayValueText(for: snapshot, basis: .effective)
    }

    func sessionRemainingPercentText(for snapshot: UsageSnapshot) -> String {
        remainingPercentText(for: snapshot, basis: .session, unavailableText: "unavailable")
    }

    func sessionRemainingPercentValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentValueText(for: snapshot, basis: .session)
    }

    func sessionRemainingPercentDisplayValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentDisplayValueText(for: snapshot, basis: .session)
    }

    private enum RemainingPercentBasis {
        case effective
        case session
    }

    private func remainingPercentText(
        for snapshot: UsageSnapshot,
        basis: RemainingPercentBasis,
        unavailableText: String
    ) -> String {
        guard snapshot.isAvailable else {
            return unavailableText
        }

        return "\(roundedRemainingPercent(for: snapshot, basis: basis))% left"
    }

    private func remainingPercentValueText(
        for snapshot: UsageSnapshot,
        basis: RemainingPercentBasis
    ) -> String {
        guard snapshot.isAvailable else {
            return "n/a"
        }

        return "\(roundedRemainingPercent(for: snapshot, basis: basis))%"
    }

    private func remainingPercentDisplayValueText(
        for snapshot: UsageSnapshot,
        basis: RemainingPercentBasis
    ) -> String {
        let value = remainingPercentValueText(for: snapshot, basis: basis)
        return snapshot.confidence == .estimated ? "~\(value)" : value
    }

    private func roundedRemainingPercent(
        for snapshot: UsageSnapshot,
        basis: RemainingPercentBasis
    ) -> Int {
        let percent = switch basis {
        case .effective:
            snapshot.remainingPercent
        case .session:
            snapshot.sessionRemainingPercent
        }

        return Int(percent.rounded())
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
        if snapshot.isFreshSessionWindow {
            return "fresh"
        }

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
        if snapshot.isFreshSessionWindow {
            return "Fresh window"
        }

        return "resets in \(resetText(for: snapshot))"
    }

    func shouldUseSoon(for snapshot: UsageSnapshot) -> Bool {
        alertEngine.shouldUseSoon(
            for: snapshot,
            thresholds: thresholds,
            now: now()
        )
    }

    func statusText(for snapshot: UsageSnapshot) -> String {
        if snapshot.isFreshSessionWindow {
            return "Fresh window"
        }

        return alertEngine.statusText(
            for: snapshot,
            thresholds: thresholds,
            now: now()
        )
    }

    func weeklyText(for snapshot: UsageSnapshot) -> String? {
        if snapshot.isFreshWeeklyWindow {
            return "Week: 100% left · fresh week"
        }

        guard let weeklyWindow = snapshot.weeklyWindow,
              let remaining = snapshot.weeklyRemainingPercent else {
            return nil
        }

        var text = "Week: \(Int(remaining.rounded()))% left · resets \(weeklyResetText(for: weeklyWindow))"

        if let weeklyUpdatedAt = snapshot.weeklyUpdatedAt,
           now().timeIntervalSince(weeklyUpdatedAt) > 30 * 60 {
            text += " · as of \(clockTime(weeklyUpdatedAt))"
        }

        return text
    }

    private func weeklyResetText(for window: RateWindow) -> String {
        guard let minutes = window.minutesUntilReset(now: now()) else {
            return "n/a"
        }

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }

        let days = hours / 24
        let remainderHours = hours % 24
        if remainderHours == 0 {
            return "\(days)d"
        }

        return "\(days)d \(remainderHours)h"
    }

    /// Friendly hover text for a row — where the reading came from, stated as a
    /// fact (never a promise). Lives in a tooltip, never inline.
    func sourceTooltip(for snapshot: UsageSnapshot) -> String {
        if snapshot.provider == .claude {
            if snapshot.isFreshSessionWindow {
                return "Fresh window · starts with your next Claude Code message"
            }

            switch snapshot.confidence {
            case .exact:
                return "Read from Claude Code"
            case .estimated:
                switch claudeLiveUpgrade {
                case .live:
                    return "Read from Claude Code"
                case .setupAvailable:
                    return "Estimated from local Claude Code activity · open Settings to set up live"
                case .awaitingSession:
                    return "Estimated from local Claude Code activity"
                }
            case .stale:
                return "Read from Claude Code · \(clockTime(snapshot.updatedAt))"
            case .unavailable:
                if claudeLiveUpgrade == .awaitingSession {
                    return "You're set up · waiting for Claude Code usage"
                }

                return snapshot.statusDetail ?? "Not measured yet"
            }
        }

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

    var shouldShowClaudeMeasurementInfo: Bool {
        true
    }

    var claudeSetupButtonTitle: String? {
        guard claudeLiveUpgrade == .setupAvailable, !isRefreshing(.claude) else {
            return nil
        }

        return isUnavailable(.claude) ? "Set Up…" : "Set up live readings"
    }

    var claudeMeasurementPopoverDetail: String {
        if let snapshot = snapshots.first(where: { $0.provider == .claude }),
           snapshot.isFreshSessionWindow {
            return "Fresh window. Usage starts with your next Claude Code message."
        }

        if let snapshot = snapshots.first(where: { $0.provider == .claude }),
           snapshot.confidence == .stale {
            return "Right now it's showing your last exact reading from \(clockTime(snapshot.updatedAt)). Claude Code will replace it when the statusline sends a current window."
        }

        switch claudeLiveUpgrade {
        case .live:
            return "Right now it's exact, current as of your last terminal session."
        case .setupAvailable:
            if isUnavailable(.claude) {
                return "It's not set up yet. Set it up, then use Claude Code in the terminal for exact numbers."
            }

            return "Right now it's estimating. Set up live readings, then use Claude Code in the terminal for exact numbers."
        case .awaitingSession:
            if isUnavailable(.claude) {
                return "You're set up. PromptJuice is waiting for Claude Code's next statusline window."
            }

            return "Showing a local Claude Code estimate. Exact usage replaces it when Claude Code sends a current rate-limit window."
        }
    }

    func settingsStatusText(for provider: UsageProvider) -> String {
        guard let snapshot = snapshots.first(where: { $0.provider == provider }) else {
            return provider == .claude ? "Not set up yet" : "Not detected"
        }

        guard snapshot.isAvailable else {
            if snapshot.statusDetail == "Refreshing usage" {
                return "Checking…"
            }

            if provider == .claude, claudeLiveUpgrade == .awaitingSession {
                return "Waiting for Claude statusline"
            }

            return provider == .claude ? "Not set up yet" : "Not detected"
        }

        switch snapshot.confidence {
        case .exact:
            if snapshot.isFreshSessionWindow {
                return "Fresh window"
            }

            if provider == .codex {
                return "Live · \(fullResetText(for: snapshot))"
            }
            return "Live"
        case .estimated:
            return "Estimate"
        case .stale:
            if snapshot.isFreshSessionWindow {
                return "Fresh window"
            }

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

        refreshClaudeBridgeState()
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

    private func startClaudeStatusCacheRefresh(reason: String) {
        let refreshID = UUID()
        isClaudeStatusCacheRefreshInFlight = true
        hasPendingClaudeStatusCacheRefresh = false
        activeClaudeStatusCacheRefreshID = refreshID
        claudeStatusCacheRefreshStartedAt = now()

        let providerClient = claudeStatusCacheProviderClient
        let refreshDate = now()

        PromptJuiceLog.usage.notice("Claude status cache refresh started: \(reason, privacy: .public)")

        claudeStatusCacheRefreshTask?.cancel()
        claudeStatusCacheRefreshTask = Task.detached(priority: .utility) { [weak self] in
            let claudeSnapshot = providerClient.snapshots(now: refreshDate)
                .first { $0.provider == .claude }

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }

                self.completeClaudeStatusCacheRefresh(
                    refreshID: refreshID,
                    claudeSnapshot: Task.isCancelled ? nil : claudeSnapshot,
                    outcome: Task.isCancelled ? "cancelled" : "finished"
                )
            }
        }

        scheduleClaudeStatusCacheRefreshTimeout(refreshID: refreshID)
    }

    private func scheduleClaudeStatusCacheRefreshTimeout(refreshID: UUID) {
        claudeStatusCacheRefreshTimeoutTask?.cancel()
        claudeStatusCacheRefreshTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.claudeStatusCacheRefreshTimeoutNanoseconds ?? 0)
            guard let self, !Task.isCancelled else {
                return
            }

            self.timeoutClaudeStatusCacheRefresh(refreshID: refreshID)
        }
    }

    private func completeClaudeStatusCacheRefresh(
        refreshID: UUID,
        claudeSnapshot: ProviderSnapshot?,
        outcome: String
    ) {
        guard activeClaudeStatusCacheRefreshID == refreshID else {
            PromptJuiceLog.usage.notice("Claude status cache refresh result ignored: \(outcome, privacy: .public)")
            return
        }

        if sourceMode == .liveCodex,
           enabledProviders.contains(.claude),
           let claudeSnapshot {
            if mergeSnapshotIfNewer(claudeSnapshot) {
                PromptJuiceLog.usage.notice(
                    "Claude status cache refresh merged snapshot: \(claudeSnapshot.source.rawValue, privacy: .public)/\(claudeSnapshot.confidence.rawValue, privacy: .public)"
                )
            } else {
                PromptJuiceLog.usage.notice(
                    "Claude status cache refresh kept existing snapshot over: \(claudeSnapshot.source.rawValue, privacy: .public)/\(claudeSnapshot.confidence.rawValue, privacy: .public)"
                )
            }
        } else {
            PromptJuiceLog.usage.notice("Claude status cache refresh completed without merge: \(outcome, privacy: .public)")
        }

        finishClaudeStatusCacheRefresh(refreshID: refreshID, outcome: outcome)
    }

    private func timeoutClaudeStatusCacheRefresh(refreshID: UUID) {
        guard activeClaudeStatusCacheRefreshID == refreshID else {
            return
        }

        PromptJuiceLog.usage.notice("Claude status cache refresh timeout recovered")
        claudeStatusCacheRefreshTask?.cancel()
        finishClaudeStatusCacheRefresh(refreshID: refreshID, outcome: "timeout")
    }

    private func recoverStaleClaudeStatusCacheRefreshIfNeeded(reason: String) {
        guard isClaudeStatusCacheRefreshInFlight,
              let activeClaudeStatusCacheRefreshID,
              let claudeStatusCacheRefreshStartedAt,
              now().timeIntervalSince(claudeStatusCacheRefreshStartedAt) > claudeStatusCacheRefreshTimeoutInterval else {
            return
        }

        PromptJuiceLog.usage.notice("Claude status cache stale in-flight recovered: \(reason, privacy: .public)")
        claudeStatusCacheRefreshTask?.cancel()
        finishClaudeStatusCacheRefresh(
            refreshID: activeClaudeStatusCacheRefreshID,
            outcome: "stale in-flight"
        )
    }

    private var claudeStatusCacheRefreshTimeoutInterval: TimeInterval {
        Double(claudeStatusCacheRefreshTimeoutNanoseconds) / 1_000_000_000
    }

    private func finishClaudeStatusCacheRefresh(refreshID: UUID, outcome: String) {
        guard activeClaudeStatusCacheRefreshID == refreshID else {
            return
        }

        isClaudeStatusCacheRefreshInFlight = false
        activeClaudeStatusCacheRefreshID = nil
        claudeStatusCacheRefreshStartedAt = nil
        claudeStatusCacheRefreshTask = nil
        claudeStatusCacheRefreshTimeoutTask?.cancel()
        claudeStatusCacheRefreshTimeoutTask = nil

        PromptJuiceLog.usage.notice("Claude status cache refresh \(outcome, privacy: .public)")

        if hasPendingClaudeStatusCacheRefresh {
            hasPendingClaudeStatusCacheRefresh = false
            refreshClaudeAfterStatusCacheChange(reason: "pending cache change")
        }
    }

    private func mergeSnapshotIfNewer(_ snapshot: ProviderSnapshot) -> Bool {
        let refreshDate = now()
        let refreshedSnapshot = Self.currentOrUnavailableSnapshot(snapshot, now: refreshDate)
        let existing = snapshots.first { $0.provider == refreshedSnapshot.provider }

        if let existing,
           shouldKeepExistingSnapshot(
            existing,
            over: refreshedSnapshot,
            refreshDate: refreshDate
           ) {
            let settledExisting = settledExistingSnapshot(existing, over: refreshedSnapshot)
            if settledExisting != existing {
                var mergedSnapshots = snapshots.filter { $0.provider != settledExisting.provider }
                mergedSnapshots.append(settledExisting)
                snapshots = Self.sortedSnapshots(mergedSnapshots)
                logSnapshotState(reason: "settled kept snapshot")
                return true
            }

            return false
        }

        var mergedSnapshots = snapshots.filter { $0.provider != refreshedSnapshot.provider }
        mergedSnapshots.append(refreshedSnapshot)
        snapshots = Self.sortedSnapshots(mergedSnapshots)
        logSnapshotState(reason: "single snapshot merge")
        return true
    }

    private static func sortedSnapshots(_ snapshots: [ProviderSnapshot]) -> [ProviderSnapshot] {
        snapshots.sorted { first, second in
            first.provider.sortIndex < second.provider.sortIndex
        }
    }

    private func refreshSnapshotsInBackground(
        completionMessage: String? = nil,
        completion: RefreshCompletion? = nil
    ) {
        guard let refreshRequest = beginRefresh(
            completionMessage: completionMessage,
            completion: completion
        ) else {
            return
        }

        if shouldRefreshLiveProvidersIndependently {
            startLiveProviderRefresh(
                refreshID: refreshRequest.id,
                refreshDate: refreshRequest.date,
                completionMessage: completionMessage,
                completion: completion
            )
            return
        }

        startAggregateRefresh(
            refreshID: refreshRequest.id,
            refreshDate: refreshRequest.date,
            completionMessage: completionMessage,
            completion: completion
        )
    }

    private var shouldRefreshLiveProvidersIndependently: Bool {
        sourceMode == .liveCodex && injectedProviderClient == nil
    }

    private func beginRefresh(
        completionMessage: String?,
        completion: RefreshCompletion?
    ) -> (id: UUID, date: Date)? {
        if activeRefreshID != nil {
            hasPendingRefresh = true
            if let completionMessage {
                pendingRefreshCompletionMessage = completionMessage
            }
            if let completion {
                pendingRefreshCompletions.append(completion)
            }
            PromptJuiceLog.usage.debug("Usage refresh coalesced while provider read is active")
            return nil
        }

        let refreshID = UUID()
        activeRefreshID = refreshID
        PromptJuiceLog.usage.debug("Usage refresh started")
        return (refreshID, now())
    }

    private func startAggregateRefresh(
        refreshID: UUID,
        refreshDate: Date,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        let providerClient = providerClient

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            let refreshedSnapshots = providerClient.snapshots(now: refreshDate)

            await MainActor.run { [weak self] in
                self?.finishAggregateRefresh(
                    refreshID: refreshID,
                    refreshedSnapshots: refreshedSnapshots,
                    refreshDate: refreshDate,
                    completionMessage: completionMessage,
                    completion: completion
                )
            }
        }
    }

    private func startLiveProviderRefresh(
        refreshID: UUID,
        refreshDate: Date,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        let claudeProviderClient = liveClaudeProviderClient
        let codexProviderClient = liveCodexProviderClient

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            await withTaskGroup(of: ProviderSnapshot?.self) { group in
                group.addTask {
                    PromptJuiceLog.usage.debug("Live Claude refresh task started")
                    return claudeProviderClient.snapshots(now: refreshDate)
                        .first { $0.provider == .claude }
                }
                group.addTask {
                    PromptJuiceLog.usage.debug("Live Codex refresh task started")
                    return codexProviderClient.snapshots(now: refreshDate)
                        .first { $0.provider == .codex }
                }

                for await snapshot in group {
                    guard let snapshot else {
                        continue
                    }

                    await MainActor.run { [weak self] in
                        self?.mergeLiveRefreshSnapshot(snapshot, refreshID: refreshID)
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.finishLiveProviderRefresh(
                    refreshID: refreshID,
                    completionMessage: completionMessage,
                    completion: completion
                )
            }
        }
    }

    private func finishAggregateRefresh(
        refreshID: UUID,
        refreshedSnapshots: [ProviderSnapshot],
        refreshDate: Date,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        guard activeRefreshID == refreshID else {
            return
        }

        snapshots = mergedSnapshots(
            with: refreshedSnapshots,
            refreshDate: refreshDate
        )
        logSnapshotState(reason: "aggregate refresh")
        finishRefresh(
            refreshID: refreshID,
            completionMessage: completionMessage,
            completion: completion
        )
    }

    private func mergeLiveRefreshSnapshot(
        _ snapshot: ProviderSnapshot,
        refreshID: UUID
    ) {
        guard activeRefreshID == refreshID else {
            return
        }

        if mergeSnapshotIfNewer(snapshot) {
            PromptJuiceLog.usage.debug("Live provider snapshot merged: \(snapshot.provider.rawValue, privacy: .public)")
        } else {
            PromptJuiceLog.usage.debug("Live provider snapshot kept existing: \(snapshot.provider.rawValue, privacy: .public)")
        }
    }

    private func finishLiveProviderRefresh(
        refreshID: UUID,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        guard activeRefreshID == refreshID else {
            return
        }

        finishRefresh(
            refreshID: refreshID,
            completionMessage: completionMessage,
            completion: completion
        )
    }

    private func finishRefresh(
        refreshID: UUID,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        guard activeRefreshID == refreshID else {
            return
        }

        activeRefreshID = nil
        PromptJuiceLog.usage.debug("Usage refresh finished")

        if let completionMessage {
            actionMessage = completionMessage
        }

        completion?()
        runPendingRefreshIfNeeded()
    }

    private func runPendingRefreshIfNeeded() {
        guard hasPendingRefresh else {
            return
        }

        let completionMessage = pendingRefreshCompletionMessage
        let completions = pendingRefreshCompletions
        hasPendingRefresh = false
        pendingRefreshCompletionMessage = nil
        pendingRefreshCompletions = []

        refreshSnapshotsInBackground(completionMessage: completionMessage) {
            for completion in completions {
                completion()
            }
        }
    }

    private func mergedSnapshots(
        with refreshedSnapshots: [ProviderSnapshot],
        refreshDate: Date
    ) -> [ProviderSnapshot] {
        Self.sortedSnapshots(
            refreshedSnapshots.map { refreshed in
                let currentSnapshot = Self.currentOrUnavailableSnapshot(
                    refreshed,
                    now: refreshDate
                )

                if let existing = snapshots.first(where: { $0.provider == currentSnapshot.provider }),
                   shouldKeepExistingSnapshot(
                    existing,
                    over: currentSnapshot,
                    refreshDate: refreshDate
                   ) {
                    return settledExistingSnapshot(existing, over: currentSnapshot)
                }

                return currentSnapshot
            }
        )
    }

    private func shouldKeepExistingSnapshot(
        _ existing: ProviderSnapshot,
        over refreshed: ProviderSnapshot,
        refreshDate: Date
    ) -> Bool {
        if existing.isExpired(at: refreshDate) || !existing.isAvailable {
            return false
        }

        let existingPriority = snapshotPriority(existing)
        let refreshedPriority = snapshotPriority(refreshed)
        if existingPriority != refreshedPriority {
            return existingPriority > refreshedPriority
        }

        if let existingResetAt = existing.rateWindow.resetAt,
           let refreshedResetAt = refreshed.rateWindow.resetAt,
           refreshedResetAt > existingResetAt {
            return false
        }

        return existing.updatedAt > refreshed.updatedAt
    }

    private func settledExistingSnapshot(
        _ existing: ProviderSnapshot,
        over refreshed: ProviderSnapshot
    ) -> ProviderSnapshot {
        guard existing.statusDetail == "Refreshing usage" else {
            return existing
        }

        return ProviderSnapshot(
            identity: existing.identity,
            rateWindow: existing.rateWindow,
            weeklyWindow: existing.weeklyWindow,
            source: existing.source,
            confidence: existing.confidence,
            updatedAt: existing.updatedAt,
            weeklyUpdatedAt: existing.weeklyUpdatedAt,
            statusDetail: refreshed.statusDetail,
            isFreshSessionWindow: existing.isFreshSessionWindow,
            isFreshWeeklyWindow: existing.isFreshWeeklyWindow
        )
    }

    private func snapshotPriority(_ snapshot: ProviderSnapshot) -> Int {
        if snapshot.isFreshSessionWindow {
            return 0
        }

        guard snapshot.isAvailable else {
            return -1
        }

        switch snapshot.confidence {
        case .exact:
            return 3
        case .estimated:
            return 2
        case .stale:
            return 1
        case .unavailable:
            return 0
        }
    }

    private func replaceExpiredSnapshots(
        _ expiredSnapshots: [ProviderSnapshot],
        at refreshDate: Date
    ) {
        let expiredProviders = Set(expiredSnapshots.map(\.provider))

        snapshots = Self.sortedSnapshots(
            snapshots.map { snapshot in
                guard expiredProviders.contains(snapshot.provider),
                      snapshot.isExpired(at: refreshDate) else {
                    return snapshot
                }

                return Self.unavailableSnapshot(
                    identity: snapshot.identity,
                    source: snapshot.source,
                    now: refreshDate
                )
            }
        )
        logSnapshotState(reason: "expired snapshot replacement")

        if let selectedProvider,
           expiredProviders.contains(selectedProvider) {
            clearSelection()
        }
    }

    private func logSnapshotState(reason: String) {
        let states = snapshots
            .map { snapshot in
                let availability = snapshot.isAvailable ? "available" : "unavailable"
                return "\(snapshot.provider.rawValue):\(snapshot.source.rawValue):\(snapshot.confidence.rawValue):\(availability)"
            }
            .joined(separator: ",")
        let claudeState = claudeLiveUpgrade

        PromptJuiceLog.usage.notice(
            "Snapshot state updated (\(reason, privacy: .public)): \(states, privacy: .public); claudeLiveUpgrade=\(String(describing: claudeState), privacy: .public)"
        )
    }

    private static func makeProviderClient(sourceMode: UsageSourceMode) -> any UsageProviderClient {
        switch sourceMode {
        case .fixture:
            return FixtureUsageProviderClient(scenario: .underusedCodex)
        case .liveCodex:
            return ClaudeLiveUsageProviderClient(
                claudeProviderClient: ClaudeProviderClient(localEstimatePolicy: .invalidStatuslineOnly)
            )
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

    private static func currentOrUnavailableSnapshot(
        _ snapshot: ProviderSnapshot,
        now: Date
    ) -> ProviderSnapshot {
        guard snapshot.isExpired(at: now) else {
            return snapshot
        }

        if snapshot.identity == .claude,
           snapshot.source == .claudeStatusline || snapshot.source == .claudeCache {
            let weeklyWindow: RateWindow?
            let isFreshWeeklyWindow: Bool
            if let weekly = snapshot.weeklyWindow,
               let resetAt = weekly.resetAt,
               resetAt > now {
                weeklyWindow = weekly
                isFreshWeeklyWindow = false
            } else if snapshot.weeklyWindow != nil {
                weeklyWindow = nil
                isFreshWeeklyWindow = true
            } else {
                weeklyWindow = nil
                isFreshWeeklyWindow = false
            }

            return ProviderSnapshot(
                identity: snapshot.identity,
                rateWindow: .unavailable,
                weeklyWindow: weeklyWindow,
                source: snapshot.source,
                confidence: snapshot.confidence == .unavailable ? .stale : snapshot.confidence,
                updatedAt: snapshot.updatedAt,
                weeklyUpdatedAt: snapshot.weeklyUpdatedAt,
                statusDetail: "Fresh window",
                isFreshSessionWindow: true,
                isFreshWeeklyWindow: isFreshWeeklyWindow
            )
        }

        return ProviderSnapshot(
            identity: snapshot.identity,
            rateWindow: .unavailable,
            source: snapshot.source,
            confidence: .unavailable,
            updatedAt: now,
            statusDetail: "Usage window expired"
        )
    }
}
