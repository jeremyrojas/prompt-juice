import Foundation
import SwiftUI

enum ClaudeLiveUpgrade: Equatable {
    case live
    case setupAvailable
    case awaitingSession
}

struct UseSoonNotice: Equatable {
    let provider: UsageProvider
    let providerDisplayName: String
    let remainingPercent: Int
    let resetText: String
    let windowID: String

    var title: String {
        "Use \(providerDisplayName) before it resets"
    }

    var body: String {
        "You have \(remainingPercent)% left with \(resetText) until reset"
    }

    var notificationIdentifier: String {
        Self.notificationIdentifier(provider: provider, windowID: windowID)
    }

    static func notificationIdentifier(provider: UsageProvider, windowID: String) -> String {
        "promptjuice.use-soon.\(provider.rawValue).\(windowID)"
    }
}

struct UseSoonNotificationWithdrawal: Equatable {
    let provider: UsageProvider
    let windowID: String

    var notificationIdentifier: String {
        UseSoonNotice.notificationIdentifier(provider: provider, windowID: windowID)
    }
}

/// The single macOS notification actually delivered. When more than one provider
/// is orange at once their per-provider `UseSoonNotice`s are merged into this so
/// the user gets one banner listing every provider, not one banner each.
struct MergedUseSoonNotification: Equatable {
    let title: String
    let body: String
    let identifier: String

    /// Builds the delivered banner from the qualifying per-provider notices,
    /// already sorted by provider order. Returns `nil` when there's nothing to
    /// send. One provider reuses its own copy; two or more are combined, and the
    /// reset clause collapses when the windows share a time (matching the panel).
    init?(notices: [UseSoonNotice]) {
        guard let first = notices.first else {
            return nil
        }

        if notices.count == 1 {
            title = first.title
            body = first.body
            identifier = first.notificationIdentifier
            return
        }

        let names = notices.map(\.providerDisplayName)
        title = "Use \(names.joined(separator: " and ")) before they reset"

        let sharesResetTime = Set(notices.map(\.resetText)).count == 1
        if sharesResetTime {
            let leadIn = notices
                .map { "\($0.providerDisplayName) \($0.remainingPercent)%" }
                .joined(separator: " · ")
            body = "\(leadIn) left, resetting in \(first.resetText)"
        } else {
            body = notices
                .map { "\($0.providerDisplayName) \($0.remainingPercent)% left in \($0.resetText)" }
                .joined(separator: " · ")
        }

        identifier = "promptjuice.use-soon.merged." + notices
            .map { "\($0.provider.rawValue).\($0.windowID)" }
            .joined(separator: "_")
    }
}

private typealias RefreshCompletion = @MainActor @Sendable () -> Void

private enum LiveProviderRefreshResult: Sendable {
    case claudeSnapshot(ProviderSnapshot?)
    case claudeCoordinator(ClaudeUsageCoordinatorState)
    case codexSnapshot(ProviderSnapshot?)
}

@MainActor
final class PromptJuiceViewModel: ObservableObject {
    @Published private(set) var snapshots: [UsageSnapshot]
    /// Dormant row selection state retained for future scoped provider UI.
    /// Provider row clicks currently leave this unchanged.
    @Published private(set) var selectedProvider: UsageProvider?
    @Published private(set) var hoveredPanelTarget: PanelClickTarget?
    @Published private(set) var actionMessage: String?
    @Published private(set) var thresholds: AlertThresholds
    @Published private(set) var sourceMode: UsageSourceMode
    @Published private(set) var enabledProviders: Set<UsageProvider>
    @Published private(set) var useSoonNotificationsEnabled: Bool
    @Published private(set) var claudeAccessState: ClaudeAccessState
    @Published private(set) var claudeRefreshState: ClaudeRefreshState
    @Published private(set) var legacyBridgeStatus: LegacyBridgeStatus
    @Published private(set) var notificationAuthorization: PromptJuiceNotificationAuthorization = .unknown
    /// Mirrors `settingsStore.didOfferUseSoonNotification` so SwiftUI re-renders
    /// the panel when the just-in-time prime is answered.
    @Published private(set) var didOfferUseSoonNotification: Bool

    private let settingsStore: PromptJuiceSettingsStore
    private let alertEngine: AlertEngine
    private let now: () -> Date
    private let isClaudeBridgeCurrent: () -> Bool
    private let injectedProviderClient: (any UsageProviderClient)?
    private let claudeStatusCacheProviderClient: any UsageProviderClient
    private let liveClaudeProviderClient: any UsageProviderClient
    private let liveCodexProviderClient: any UsageProviderClient
    private let claudeUsageCoordinator: (any ClaudeUsageSnapshotProviding)?
    private let claudeUsageDogfoodEnabled: Bool
    private var providerClient: any UsageProviderClient
    private var refreshTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var hasPendingRefresh = false
    private var pendingRefreshCompletionMessage: String?
    private var pendingRefreshCompletions: [RefreshCompletion] = []
    private var pendingClaudeRefreshReason: ClaudeRefreshReason?
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
        claudeUsageCoordinator: (any ClaudeUsageSnapshotProviding)? = nil,
        claudeUsageDogfoodEnabled: Bool? = nil,
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
        let dogfoodEnabled = claudeUsageDogfoodEnabled
            ?? (claudeUsageCoordinator != nil || ClaudeUsageDogfoodSwitch.isEnabled())

        self.settingsStore = settingsStore
        self.injectedProviderClient = providerClient
        self.liveClaudeProviderClient = liveClaudeClient
        self.liveCodexProviderClient = liveCodexClient
        self.claudeUsageDogfoodEnabled = dogfoodEnabled
        self.claudeUsageCoordinator = if let claudeUsageCoordinator {
            claudeUsageCoordinator
        } else if dogfoodEnabled {
            ClaudeUsageCoordinator(featureEnabled: true)
        } else {
            nil
        }
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
        self.useSoonNotificationsEnabled = settingsStore.useSoonNotificationsEnabled
        self.didOfferUseSoonNotification = settingsStore.didOfferUseSoonNotification
        claudeAccessState = .checking
        claudeRefreshState = .idle
        legacyBridgeStatus = isClaudeBridgeCurrentState ? .removable : .none
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

    private var quotaBearingVisibleSnapshots: [UsageSnapshot] {
        guard claudeUsageDogfoodEnabled else {
            return visibleSnapshots
        }
        return ClaudeAggregatePolicy.quotaBearingSnapshots(
            visibleSnapshots,
            claudeAccess: claudeAccessState
        )
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
            in: quotaBearingVisibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    /// Header droplet tint follows the aggregate across visible providers.
    var headerSeverity: UsageSeverity {
        return aggregateSeverity
    }

    /// Fill level for the header droplet (0...100), matching the visible rows.
    var headerRemainingPercent: Double {
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
        // provider's session remaining so the orange droplet matches its headline.
        if aggregateSeverity == .useSoon, let alertSnapshot {
            return alertSnapshot.remainingPercent
        }

        let available = quotaBearingVisibleSnapshots.filter(\.isAvailable)

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
        quotaBearingVisibleSnapshots.filter { $0.isAvailable && severity(for: $0) == .low }
    }

    private var emptySnapshots: [UsageSnapshot] {
        quotaBearingVisibleSnapshots.filter { severity(for: $0) == .empty }
    }

    /// Manual-mode subtitle — the next visible reset, with provider context.
    private var manualSubtitle: String {
        if isCheckingUsage {
            return "Just a moment…"
        }

        guard quotaBearingVisibleSnapshots.contains(where: \.isAvailable) else {
            return "Usage unavailable"
        }

        let refreshDate = now()
        let resetSnapshots = quotaBearingVisibleSnapshots
            .filter { $0.isAvailable && $0.hasActiveResetWindow(at: refreshDate) }
            .sorted { first, second in
                first.provider.sortIndex < second.provider.sortIndex
            }

        guard !resetSnapshots.isEmpty else {
            return "Fresh window"
        }

        let contextualResetSnapshots = resetSnapshotsForHeaderDetail(
            from: resetSnapshots,
            at: refreshDate
        )
        let resetTexts = contextualResetSnapshots.map { resetText(for: $0) }
        if let sharedText = resetTexts.first,
           resetTexts.allSatisfy({ $0 == sharedText }) {
            let verb = contextualResetSnapshots.count == 1 ? "resets" : "reset"
            return "\(providerNameList(contextualResetSnapshots)) \(verb) in \(sharedText)"
        }

        if let soonest = contextualResetSnapshots.min(by: { first, second in
            (first.rateWindow.resetAt ?? .distantFuture) < (second.rateWindow.resetAt ?? .distantFuture)
        }) {
            return "\(soonest.displayName) resets in \(resetText(for: soonest))"
        }

        return "Fresh window"
    }

    private func resetSnapshotsForHeaderDetail(
        from resetSnapshots: [UsageSnapshot],
        at refreshDate: Date
    ) -> [UsageSnapshot] {
        guard aggregateSeverity == .useSoon else {
            return resetSnapshots
        }

        let alerting = alertingSnapshots.filter {
            $0.hasActiveResetWindow(at: refreshDate)
        }
        return alerting.isEmpty ? resetSnapshots : alerting
    }

    private func providerNameList(_ snapshots: [UsageSnapshot]) -> String {
        let names = snapshots
            .sorted { first, second in
                first.provider.sortIndex < second.provider.sortIndex
            }
            .map(\.displayName)

        if names.count == 2 {
            return "\(names[0]) and \(names[1])"
        }

        return names.joined(separator: ", ")
    }

    var headline: String {
        manualVerdict
    }

    var detail: String {
        manualSubtitle
    }

    // MARK: - Selection

    /// True only when the Claude row is showing its "Set up" cue.
    var claudeRowOffersSetup: Bool {
        isUnavailable(.claude)
            && !isRefreshing(.claude)
            && claudeLiveUpgrade == .setupAvailable
    }

    /// Toggle dormant scoped-provider state. The panel does not currently call this.
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

    func setHoveredPanelTarget(_ target: PanelClickTarget?) {
        guard hoveredPanelTarget != target else {
            return
        }

        hoveredPanelTarget = target
    }

    private var alertSnapshot: UsageSnapshot? {
        alertEngine.preferredSnapshot(
            in: quotaBearingVisibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    private var alertingSnapshots: [UsageSnapshot] {
        alertEngine.alertingSnapshots(
            in: quotaBearingVisibleSnapshots,
            thresholds: thresholds,
            now: now()
        )
    }

    func showManualCheck() {
        actionMessage = nil
        refreshSnapshotsInBackground(claudeReason: .manual)
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

    func setUseSoonNotificationsEnabled(_ enabled: Bool) {
        guard enabled != useSoonNotificationsEnabled else {
            return
        }

        settingsStore.useSoonNotificationsEnabled = enabled
        useSoonNotificationsEnabled = enabled
    }

    func setNotificationAuthorization(_ authorization: PromptJuiceNotificationAuthorization) {
        guard authorization != notificationAuthorization else {
            return
        }

        notificationAuthorization = authorization
    }

    var showsNotificationAuthorizationHint: Bool {
        useSoonNotificationsEnabled && notificationAuthorization == .denied
    }

    /// Just-in-time notification prime: show the one-time in-panel ask only when
    /// there's a live orange nudge, notifications aren't on, macOS hasn't been
    /// asked yet, and we haven't already offered it. Any other auth state
    /// (`.denied`, `.authorized`, `.unknown`) suppresses it — a denied user can't
    /// be re-prompted from here, an authorized one needs nothing.
    var shouldOfferUseSoonNotificationPrime: Bool {
        !didOfferUseSoonNotification
            && !useSoonNotificationsEnabled
            && notificationAuthorization == .notDetermined
            && aggregateSeverity == .useSoon
    }

    /// Accept the prime: enable notifications (which requests macOS authorization
    /// upstream) and latch the ask closed.
    func enableUseSoonNotificationsFromPrime() {
        markUseSoonNotificationPrimeOffered()
        setUseSoonNotificationsEnabled(true)
    }

    /// Decline the prime: latch it closed without enabling. Settings stays the
    /// always-on path.
    func dismissUseSoonNotificationPrime() {
        markUseSoonNotificationPrimeOffered()
    }

    private func markUseSoonNotificationPrimeOffered() {
        guard !didOfferUseSoonNotification else {
            return
        }

        settingsStore.didOfferUseSoonNotification = true
        didOfferUseSoonNotification = true
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
            refreshSnapshotsInBackground(claudeReason: .foreground)
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
            claudeReason: .manual,
            completionMessage: "\(sourceMode.title) refreshed."
        )
    }

    func refreshUsageQuietly(reason: ClaudeRefreshReason = .timer) {
        refreshClaudeBridgeState()
        refreshSnapshotsInBackground(claudeReason: reason)
    }

    func refreshClaudeAfterStatusCacheChange(reason: String = "cache change") {
        guard !claudeUsageDogfoodEnabled,
              sourceMode == .liveCodex,
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

    func setUsageSourceMode(_ mode: UsageSourceMode) {
        setUsageSourceMode(mode, persist: true, announce: true)
    }

    func pendingUseSoonNotifications(now noticeDate: Date) -> [UseSoonNotice] {
        guard useSoonNotificationsEnabled else {
            return []
        }

        let notifiedWindowIDs = settingsStore.notifiedUseSoonWindowIDs

        return quotaBearingVisibleSnapshots
            .filter { snapshot in
                snapshot.isAvailable
                    && snapshot.hasActiveResetWindow(at: noticeDate)
                    && alertEngine.severity(for: snapshot, thresholds: thresholds, now: noticeDate) == .useSoon
                    && notifiedWindowIDs[snapshot.provider.rawValue] != snapshot.resetWindowID
            }
            .sorted { first, second in
                first.provider.sortIndex < second.provider.sortIndex
            }
            .map { snapshot in
                UseSoonNotice(
                    provider: snapshot.provider,
                    providerDisplayName: snapshot.displayName,
                    remainingPercent: Int(snapshot.sessionRemainingPercent.rounded()),
                    resetText: resetText(for: snapshot),
                    windowID: snapshot.resetWindowID
                )
            }
    }

    /// The single banner to deliver for the current pending notices — the merge
    /// of every orange provider into one notification.
    func mergedUseSoonNotification(now noticeDate: Date) -> MergedUseSoonNotification? {
        MergedUseSoonNotification(notices: pendingUseSoonNotifications(now: noticeDate))
    }

    func markUseSoonNoticeDispatched(_ notice: UseSoonNotice) {
        settingsStore.markUseSoonWindowNotified(
            provider: notice.provider,
            windowID: notice.windowID
        )
    }

    /// Remembers the id of the merged banner just delivered so it can be removed
    /// when its windows go stale.
    func rememberDispatchedUseSoonNotification(_ merged: MergedUseSoonNotification) {
        settingsStore.lastUseSoonNotificationIdentifier = merged.identifier
    }

    var lastDispatchedUseSoonNotificationIdentifier: String? {
        settingsStore.lastUseSoonNotificationIdentifier
    }

    /// Drops the remembered banner id once no windows remain latched, so a future
    /// orange moment starts clean.
    func forgetDispatchedUseSoonNotificationIfCleared() {
        if settingsStore.notifiedUseSoonWindowIDs.isEmpty {
            settingsStore.lastUseSoonNotificationIdentifier = nil
        }
    }

    func staleUseSoonNotificationWithdrawals(now withdrawalDate: Date) -> [UseSoonNotificationWithdrawal] {
        let snapshotsByProvider = Dictionary(
            uniqueKeysWithValues: quotaBearingVisibleSnapshots.map { ($0.provider, $0) }
        )

        return settingsStore.notifiedUseSoonWindowIDs.compactMap { providerRawValue, windowID in
            guard let provider = UsageProvider(rawValue: providerRawValue) else {
                return nil
            }

            guard let storedResetAt = resetDate(fromWindowID: windowID) else {
                return UseSoonNotificationWithdrawal(provider: provider, windowID: windowID)
            }

            if storedResetAt <= withdrawalDate {
                return UseSoonNotificationWithdrawal(provider: provider, windowID: windowID)
            }

            guard let snapshot = snapshotsByProvider[provider],
                  snapshot.hasActiveResetWindow(at: withdrawalDate),
                  snapshot.resetWindowID != windowID,
                  let currentResetAt = snapshot.rateWindow.resetAt,
                  currentResetAt > storedResetAt else {
                return nil
            }

            return UseSoonNotificationWithdrawal(provider: provider, windowID: windowID)
        }
    }

    private func resetDate(fromWindowID windowID: String) -> Date? {
        guard let resetMinuteText = windowID.split(separator: ":").last,
              let resetMinute = TimeInterval(resetMinuteText) else {
            return nil
        }

        return Date(timeIntervalSince1970: resetMinute * 60)
    }

    func clearUseSoonNotificationLatch(for withdrawal: UseSoonNotificationWithdrawal) {
        settingsStore.clearUseSoonWindowNotification(provider: withdrawal.provider)
    }

    func tick() {
        refreshExpiredSnapshotsIfNeeded()
        ageExactClaudeSnapshotsIfNeeded()
        objectWillChange.send()
    }

    func refreshClaudeBridgeState() {
        isClaudeBridgeCurrentState = isClaudeBridgeCurrent()
        legacyBridgeStatus = isClaudeBridgeCurrentState ? .removable : .none
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

        refreshUsageQuietly(reason: .resetBoundary)
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
        remainingPercentText(for: snapshot, basis: .display, unavailableText: "Unavailable")
    }

    func remainingPercentText(for snapshot: UsageSnapshot) -> String {
        remainingPercentText(for: snapshot, basis: .display, unavailableText: "unavailable")
    }

    func remainingPercentValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentValueText(for: snapshot, basis: .display)
    }

    func remainingPercentDisplayValueText(for snapshot: UsageSnapshot) -> String {
        remainingPercentDisplayValueText(for: snapshot, basis: .display)
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
        case display
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
        case .display:
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

    // retained for future weekly UI; not currently displayed
    func weeklyText(for snapshot: UsageSnapshot) -> String? {
        if snapshot.isFreshWeeklyWindow {
            return "Week: 100% left · fresh week"
        }

        guard let weeklyWindow = snapshot.weeklyWindow,
              let remaining = snapshot.weeklyRemainingPercent else {
            return nil
        }

        var text = "Week: \(Int(remaining.rounded()))% left · resets in \(weeklyResetText(for: weeklyWindow))"

        if let weeklyUpdatedAt = snapshot.weeklyUpdatedAt,
           now().timeIntervalSince(weeklyUpdatedAt) > 30 * 60 {
            text += " · as of \(clockTime(weeklyUpdatedAt))"
        }

        return text
    }

    // retained for future weekly UI; not currently displayed
    private func weeklyResetText(for window: RateWindow) -> String {
        guard let minutes = window.minutesUntilReset(now: now()) else {
            return "n/a"
        }

        let hours = max(1, minutes / 60)
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

            if snapshot.isAvailable && snapshot.remainingPercent <= 0 {
                return "Claude is out until reset · read from Claude Code as of \(clockTime(snapshot.updatedAt))"
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
                return "Read from Claude Code as of \(clockTime(snapshot.updatedAt)) · send any message in Claude Code to refresh"
            case .unavailable:
                if claudeLiveUpgrade == .awaitingSession {
                    return "You're set up · waiting for Claude Code usage"
                }

                return "Not measured yet"
            }
        }

        let label: String
        switch snapshot.source {
        case .claudeStatusline, .claudeUsageCLI, .claudeCache:
            label = "Claude Code"
        case .claudeLocalLogs:
            label = "local Claude Code activity"
        case .codexAppServer, .codexCache:
            label = "Codex app-server"
        case .codexStub, .fixture:
            label = "a fixture"
        }

        if snapshot.isAvailable && snapshot.remainingPercent <= 0 {
            return "\(snapshot.displayName) is out until reset · read from \(label) as of \(clockTime(snapshot.updatedAt))"
        }

        switch snapshot.confidence {
        case .exact:
            return "Read from \(label)"
        case .estimated:
            return "Estimated from \(label)"
        case .stale:
            return "Read from \(label) as of \(clockTime(snapshot.updatedAt))"
        case .unavailable:
            return "Not measured yet"
        }
    }

    func showsStaleReadingIndicator(for snapshot: UsageSnapshot) -> Bool {
        snapshot.provider == .claude
            && snapshot.isAvailable
            && snapshot.confidence == .stale
            && !snapshot.isFreshSessionWindow
            && now().timeIntervalSince(snapshot.updatedAt) > 10 * 60
    }

    func staleReadingIndicatorAccessibilityLabel(for snapshot: UsageSnapshot) -> String? {
        guard showsStaleReadingIndicator(for: snapshot) else {
            return nil
        }

        return "Reading from \(clockTime(snapshot.updatedAt))"
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

    private func refreshModeForThresholds() {
        actionMessage = nil
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
        refreshSnapshotsInBackground(claudeReason: .manual)

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
        let existing = snapshots
            .first { $0.provider == refreshedSnapshot.provider }
            .map { currentSnapshotForComparison($0, refreshDate: refreshDate) }

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
        claudeReason: ClaudeRefreshReason = .timer,
        completionMessage: String? = nil,
        completion: RefreshCompletion? = nil
    ) {
        guard let refreshRequest = beginRefresh(
            claudeReason: claudeReason,
            completionMessage: completionMessage,
            completion: completion
        ) else {
            return
        }

        if shouldRefreshLiveProvidersIndependently {
            startLiveProviderRefresh(
                refreshID: refreshRequest.id,
                refreshDate: refreshRequest.date,
                claudeReason: claudeReason,
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
        claudeReason: ClaudeRefreshReason,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) -> (id: UUID, date: Date)? {
        if activeRefreshID != nil {
            hasPendingRefresh = true
            pendingClaudeRefreshReason = Self.preferredRefreshReason(
                pendingClaudeRefreshReason,
                claudeReason
            )
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
        claudeReason: ClaudeRefreshReason,
        completionMessage: String?,
        completion: RefreshCompletion?
    ) {
        let claudeProviderClient = liveClaudeProviderClient
        let codexProviderClient = liveCodexProviderClient
        let claudeUsageCoordinator = claudeUsageCoordinator
        let claudeProviderEnabled = enabledProviders.contains(.claude)

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            await withTaskGroup(of: LiveProviderRefreshResult.self) { group in
                if let claudeUsageCoordinator {
                    group.addTask {
                        PromptJuiceLog.usage.debug("Claude usage coordinator refresh started")
                        let state = await claudeUsageCoordinator.snapshot(
                            now: refreshDate,
                            reason: claudeReason,
                            force: false,
                            providerEnabled: claudeProviderEnabled,
                            isAwake: true,
                            isOnline: true
                        )
                        return .claudeCoordinator(state)
                    }
                } else {
                    group.addTask {
                        PromptJuiceLog.usage.debug("Live Claude refresh task started")
                        return .claudeSnapshot(
                            claudeProviderClient.snapshots(now: refreshDate)
                                .first { $0.provider == .claude }
                        )
                    }
                }
                group.addTask {
                    PromptJuiceLog.usage.debug("Live Codex refresh task started")
                    return .codexSnapshot(
                        codexProviderClient.snapshots(now: refreshDate)
                            .first { $0.provider == .codex }
                    )
                }

                for await result in group {
                    await MainActor.run { [weak self] in
                        switch result {
                        case .claudeCoordinator(let state):
                            self?.mergeClaudeCoordinatorState(state, refreshID: refreshID)
                        case .claudeSnapshot(let snapshot), .codexSnapshot(let snapshot):
                            if let snapshot {
                                self?.mergeLiveRefreshSnapshot(snapshot, refreshID: refreshID)
                            }
                        }
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

    private func mergeClaudeCoordinatorState(
        _ coordinatorState: ClaudeUsageCoordinatorState,
        refreshID: UUID
    ) {
        guard activeRefreshID == refreshID else {
            return
        }

        claudeAccessState = coordinatorState.access
        claudeRefreshState = coordinatorState.refresh
        legacyBridgeStatus = coordinatorState.legacyBridge
        if let snapshot = coordinatorState.snapshot {
            mergeLiveRefreshSnapshot(snapshot, refreshID: refreshID)
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
        let claudeReason = pendingClaudeRefreshReason ?? .timer
        hasPendingRefresh = false
        pendingRefreshCompletionMessage = nil
        pendingRefreshCompletions = []
        pendingClaudeRefreshReason = nil

        refreshSnapshotsInBackground(
            claudeReason: claudeReason,
            completionMessage: completionMessage
        ) {
            for completion in completions {
                completion()
            }
        }
    }

    private static func preferredRefreshReason(
        _ current: ClaudeRefreshReason?,
        _ candidate: ClaudeRefreshReason
    ) -> ClaudeRefreshReason {
        guard let current else {
            return candidate
        }

        func priority(_ reason: ClaudeRefreshReason) -> Int {
            switch reason {
            case .manual:
                3
            case .resetBoundary:
                2
            case .panelOpen, .wake, .foreground, .launch:
                1
            case .timer:
                0
            }
        }
        return priority(candidate) > priority(current) ? candidate : current
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

                if let existing = snapshots
                    .first(where: { $0.provider == currentSnapshot.provider })
                    .map({ currentSnapshotForComparison($0, refreshDate: refreshDate) }),
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

    private func currentSnapshotForComparison(
        _ snapshot: ProviderSnapshot,
        refreshDate: Date
    ) -> ProviderSnapshot {
        let current = Self.currentOrUnavailableSnapshot(snapshot, now: refreshDate)
        guard current.identity == .claude,
              current.source == .claudeStatusline,
              current.confidence == .exact,
              !current.isFreshSessionWindow,
              refreshDate.timeIntervalSince(current.updatedAt) > ClaudeStatuslineSnapshotReader.maximumCacheAge else {
            return current
        }

        return ProviderSnapshot(
            identity: current.identity,
            rateWindow: current.rateWindow,
            weeklyWindow: current.weeklyWindow,
            source: current.source,
            confidence: .stale,
            updatedAt: current.updatedAt,
            weeklyUpdatedAt: current.weeklyUpdatedAt,
            statusDetail: current.statusDetail,
            isFreshSessionWindow: current.isFreshSessionWindow,
            isFreshWeeklyWindow: current.isFreshWeeklyWindow
        )
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
