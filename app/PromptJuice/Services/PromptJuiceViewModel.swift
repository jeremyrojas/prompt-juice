import Foundation
import SwiftUI

enum ResetFormatter {
    static func duration(until resetAt: Date, now: Date) -> String {
        let seconds = max(0, resetAt.timeIntervalSince(now))

        if seconds < 60 * 60 {
            return "\(Int(seconds / 60))m"
        }
        if seconds < 24 * 60 * 60 {
            return "\(Int(seconds / (60 * 60)))h"
        }
        return "\(Int(seconds / (24 * 60 * 60)))d"
    }

    static func text(until resetAt: Date, now: Date) -> String {
        "resets in \(duration(until: resetAt, now: now))"
    }
}

struct UseSoonNotice: Equatable {
    let provider: UsageProvider
    let providerDisplayName: String
    let remainingPercent: Int
    let resetText: String
    let resetAt: Date
    let windowID: String
    var kind: LimitWindow.Kind = .fiveHour
    var rowOrder: Int = 0

    var latchKey: String { "\(provider.rawValue):\(kind.identifier)" }

    var alertingLimit: AlertingLimit {
        AlertingLimit(
            provider: provider,
            kind: kind,
            remainingPercent: remainingPercent,
            resetAt: resetAt,
            rowOrder: rowOrder
        )
    }

    var title: String {
        UseSoonHeader.make(alerts: [alertingLimit], now: resetAt)?.title ?? "Use your juice"
    }

    var body: String {
        let prefix: String = switch kind {
        case .weeklyModel:
            ""
        default:
            "\(alertingLimit.shortLabel) · "
        }
        return prefix + "\(remainingPercent)% left · resets in \(resetText)"
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
    var latchKey: String = ""

    var notificationIdentifier: String {
        UseSoonNotice.notificationIdentifier(provider: provider, windowID: windowID)
    }
}

/// The single macOS notification delivered for all newly orange windows.
struct MergedUseSoonNotification: Equatable {
    let title: String
    let body: String
    let identifier: String

    /// Builds the delivered banner from the qualifying per-provider notices,
    /// already sorted by provider order. Returns `nil` when there's nothing to
    /// send. One provider reuses its own copy; two or more are combined, and the
    /// reset clause collapses when the windows share a time (matching the panel).
    init?(notices: [UseSoonNotice], now: Date = Date()) {
        guard let first = notices.first else {
            return nil
        }

        if notices.count == 1 {
            title = first.title
            body = first.body
            identifier = first.notificationIdentifier
            return
        }

        guard let header = UseSoonHeader.make(
            alerts: notices.map(\.alertingLimit),
            now: now
        ) else { return nil }
        title = header.title
        body = notices.count == 1 ? first.body : header.subtitle

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
    @Published private(set) var fiveHourThresholds: AlertThresholds
    @Published private(set) var weeklyThresholds: AlertThresholds
    @Published private(set) var sourceMode: UsageSourceMode
    @Published private(set) var enabledProviders: Set<UsageProvider>
    @Published private(set) var expandedProviders: Set<UsageProvider>
    @Published private(set) var useSoonNotificationsEnabled: Bool
    @Published private(set) var claudeAccessState: ClaudeAccessState
    @Published private(set) var claudeRefreshState: ClaudeRefreshState
    @Published private(set) var notificationAuthorization: PromptJuiceNotificationAuthorization = .unknown
    /// Mirrors `settingsStore.didOfferUseSoonNotification` so SwiftUI re-renders
    /// the panel when the just-in-time prime is answered.
    @Published private(set) var didOfferUseSoonNotification: Bool

    private let settingsStore: PromptJuiceSettingsStore
    private let alertEngine: AlertEngine
    private let now: () -> Date
    private let injectedProviderClient: (any UsageProviderClient)?
    private let liveClaudeProviderClient: (any UsageProviderClient)?
    private let liveCodexProviderClient: any UsageProviderClient
    private let claudeUsageCoordinator: (any ClaudeUsageSnapshotProviding)?
    private let claudeGuidanceChecker: any ClaudeGuidanceChecking
    private let claudeExecutableLocator: @Sendable () -> ClaudeExecutableLocation?
    private let claudeTimerCheckInterval: TimeInterval
    private let actionMessageDuration: Duration
    private var providerClient: any UsageProviderClient
    private var refreshTask: Task<Void, Never>?
    private var claudeTimerRefreshTask: Task<Void, Never>?
    private var actionMessageClearTask: Task<Void, Never>?
    private var activeRefreshID: UUID?
    private var hasPendingRefresh = false
    private var pendingRefreshCompletionMessage: String?
    private var pendingRefreshCompletions: [RefreshCompletion] = []
    private var pendingClaudeRefreshReason: ClaudeRefreshReason?
    private var expiredWindowRefreshKeys = Set<String>()
    private var lastClaudeTimerCheckAt: Date?
    private var isNetworkOnline = true

    init(
        settingsStore: PromptJuiceSettingsStore = .shared,
        providerClient: (any UsageProviderClient)? = nil,
        liveClaudeProviderClient: (any UsageProviderClient)? = nil,
        liveCodexProviderClient: (any UsageProviderClient)? = nil,
        claudeUsageCoordinator: (any ClaudeUsageSnapshotProviding)? = nil,
        claudeGuidanceChecker: any ClaudeGuidanceChecking = SystemClaudeGuidanceChecker(),
        claudeExecutableLocator: @escaping @Sendable () -> ClaudeExecutableLocation? = {
            ClaudeExecutableLocator.locate()
        },
        initialSnapshots: [UsageSnapshot]? = nil,
        initialClaudeAccessState: ClaudeAccessState? = nil,
        initialClaudeRefreshState: ClaudeRefreshState? = nil,
        alertEngine: AlertEngine = AlertEngine(),
        claudeTimerCheckInterval: TimeInterval = 60,
        actionMessageDuration: Duration = .seconds(3),
        now: @escaping () -> Date = Date.init
    ) {
        let initialSourceMode = settingsStore.usageSourceMode
        let initialEnabledProviders = settingsStore.enabledProviders
        let liveCodexClient = liveCodexProviderClient ?? CodexProviderClient()

        self.settingsStore = settingsStore
        self.injectedProviderClient = providerClient
        self.liveClaudeProviderClient = liveClaudeProviderClient
        self.liveCodexProviderClient = liveCodexClient
        self.claudeGuidanceChecker = claudeGuidanceChecker
        self.claudeExecutableLocator = claudeExecutableLocator
        self.claudeTimerCheckInterval = claudeTimerCheckInterval
        self.actionMessageDuration = actionMessageDuration
        self.claudeUsageCoordinator = if let claudeUsageCoordinator {
            claudeUsageCoordinator
        } else if liveClaudeProviderClient != nil {
            nil
        } else {
            ClaudeUsageCoordinator()
        }
        self.sourceMode = initialSourceMode
        self.enabledProviders = initialEnabledProviders
        self.expandedProviders = settingsStore.expandedProviders
        self.providerClient = providerClient ?? Self.makeProviderClient(
            sourceMode: initialSourceMode
        )
        self.alertEngine = alertEngine
        self.now = now
        self.useSoonNotificationsEnabled = settingsStore.useSoonNotificationsEnabled
        self.didOfferUseSoonNotification = settingsStore.didOfferUseSoonNotification
        claudeAccessState = initialClaudeAccessState ?? .checking
        claudeRefreshState = initialClaudeRefreshState ?? .idle
        fiveHourThresholds = settingsStore.sharedThresholds(for: .fiveHour)
        weeklyThresholds = settingsStore.sharedThresholds(for: .weekly)
        snapshots = if let initialSnapshots {
            initialSnapshots
        } else if let providerClient {
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

    func measuredWindows(for snapshot: UsageSnapshot) -> [LimitWindow] {
        guard snapshot.confidence != .unavailable,
              snapshot.provider != .claude || claudePresentation.showsReading,
              !snapshot.isFreshSessionWindow else {
            return []
        }
        return snapshot.windows.filter { $0.rateWindow.isAvailable }
    }

    func visibleWindows(for snapshot: UsageSnapshot) -> [LimitWindow] {
        let measured = measuredWindows(for: snapshot)
        guard let main = measured.first else { return [] }
        guard !expandedProviders.contains(snapshot.provider) else { return measured }
        return [main] + measured.dropFirst().filter { window in
            isWindowUseSoon(window, in: snapshot)
        }
    }

    func isWindowUseSoon(_ window: LimitWindow, in snapshot: UsageSnapshot) -> Bool {
        alertEngine.shouldUseSoon(
            for: window,
            in: snapshot,
            thresholds: thresholds(for: window, provider: snapshot.provider),
            now: now()
        )
    }

    private func thresholds(for window: LimitWindow, provider: UsageProvider) -> AlertThresholds {
        settingsStore.thresholds(for: provider, cadence: LimitCadence(kind: window.kind))
    }

    func windowSeverity(_ window: LimitWindow, in snapshot: UsageSnapshot) -> UsageSeverity {
        let refreshDate = now()
        if alertEngine.isLockedOut(snapshot, now: refreshDate) { return .empty }
        guard let remaining = window.rateWindow.remainingPercent,
              let resetAt = window.rateWindow.resetAt,
              resetAt > refreshDate else { return .unavailable }
        if remaining <= 0 { return .empty }
        if isWindowUseSoon(window, in: snapshot) { return .useSoon }
        if remaining < Double(UsageSeverity.lowRemainingFloor) { return .low }
        return .healthy
    }

    func toggleExpanded(_ provider: UsageProvider) {
        if expandedProviders.contains(provider) {
            expandedProviders.remove(provider)
        } else {
            expandedProviders.insert(provider)
        }
        settingsStore.expandedProviders = expandedProviders
    }

    var visibleWindowCounts: [Int] {
        visibleSnapshots.map { visibleWindows(for: $0).count }
    }

    var disclosureProviders: Set<UsageProvider> {
        Set(visibleSnapshots.compactMap { snapshot in
            let windowCount = measuredWindows(for: snapshot).count
            guard windowCount > 0 else { return nil }
            return (snapshot.provider == .claude || windowCount > 1)
                ? snapshot.provider
                : nil
        })
    }

    var currentDate: Date { now() }

    var claudePresentation: ClaudeUsagePresentation {
        ClaudeUsagePresentation.resolve(
            access: claudeAccessState,
            refresh: claudeRefreshState,
            snapshot: snapshots.first { $0.provider == .claude },
            isEnabled: enabledProviders.contains(.claude),
            now: now()
        )
    }

    func claudeGuidanceContent(for journey: ClaudeGuidanceJourney) -> ClaudeGuidanceContent {
        ClaudeGuidanceContent.make(
            journey: journey,
            access: claudeAccessState,
            location: claudeExecutableLocator()
        )
    }

    func claudeFreshnessAccessibilityLabel(for snapshot: UsageSnapshot) -> String? {
        guard snapshot.provider == .claude,
              claudePresentation.showsClock else {
            return nil
        }
        return ClaudeFreshnessFormatter().title(for: snapshot.updatedAt, now: now())
    }

    func recheckClaudeGuidance(_ journey: ClaudeGuidanceJourney) async -> ClaudeGuidanceCheckResult {
        claudeRefreshState = .refreshing
        let checker = claudeGuidanceChecker
        let result = await Task.detached(priority: .userInitiated) {
            checker.check(journey: journey)
        }.value
        claudeAccessState = result.access
        claudeRefreshState = .idle
        return result
    }

    private var quotaBearingVisibleSnapshots: [UsageSnapshot] {
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
        alertEngine.severity(
            for: snapshot,
            thresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .fiveHour),
            weeklyThresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .weekly),
            now: now()
        )
    }

    /// Worst-wins judgment across all providers.
    var aggregateSeverity: UsageSeverity {
        alertEngine.aggregateSeverity(
            in: quotaBearingVisibleSnapshots,
            thresholdsFor: { provider, cadence in
                settingsStore.thresholds(for: provider, cadence: cadence)
            },
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
        if aggregateSeverity == .useSoon,
           let first = alertingLimits(at: now()).first,
           let snapshot = quotaBearingVisibleSnapshots.first(where: { $0.provider == first.provider }) {
            return snapshot.remainingPercent
        }

        if aggregateSeverity == .empty,
           quotaBearingVisibleSnapshots.contains(where: { alertEngine.isLockedOut($0, now: now()) }) {
            return 0
        }

        let available = quotaBearingVisibleSnapshots.filter(\.isAvailable)

        guard !available.isEmpty else {
            return 100
        }

        return available.map(\.remainingPercent).min() ?? 100
    }

    var menuBarShowsPercentage: Bool {
        quotaBearingVisibleSnapshots.contains(where: \.isAvailable)
    }

    var menuBarAccessibilityLabel: String {
        guard menuBarShowsPercentage else {
            return "PromptJuice: plan usage unavailable"
        }
        return "PromptJuice: \(Int(menuBarRemainingPercent.rounded()))% left"
    }

    /// Manual-mode verdict headline — the answer, not the mechanism.
    private var manualVerdict: String {
        if isCheckingUsage {
            return "Checking usage…"
        }

        if let neutralClaudeHeader {
            return neutralClaudeHeader.headline
        }

        switch aggregateSeverity {
        case .healthy:
            return "Plenty of prompt juice left"
        case .useSoon:
            return useSoonHeader?.title ?? "Use your juice"
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

    private var lockoutSubtitle: String? {
        let refreshDate = now()
        let lockouts = quotaBearingVisibleSnapshots.compactMap { snapshot -> (ProviderSnapshot, Date)? in
            guard alertEngine.isLockedOut(snapshot, now: refreshDate),
                  let resetAt = snapshot.windows
                    .first(where: { $0.kind == .weekly })?
                    .rateWindow.resetAt else {
                return nil
            }
            return (snapshot, resetAt)
        }.sorted { $0.1 < $1.1 }

        guard let (snapshot, resetAt) = lockouts.first else {
            return nil
        }

        let label = lockouts.count == 1 ? "Weekly" : "\(snapshot.displayName) Weekly"
        return "\(label) resets in \(ResetFormatter.duration(until: resetAt, now: refreshDate))"
    }

    /// Manual-mode subtitle — the next visible reset, with provider context.
    private var manualSubtitle: String {
        if isCheckingUsage {
            return "Just a moment…"
        }

        if let neutralClaudeHeader {
            return neutralClaudeHeader.detail
        }

        if let lockoutSubtitle {
            return lockoutSubtitle
        }

        if let useSoonHeader {
            return useSoonHeader.subtitle
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

        let contextualResetSnapshots = resetSnapshots
        let resetDates = contextualResetSnapshots.compactMap(\.rateWindow.resetAt)
        if let sharedResetAt = resetDates.first,
           resetDates.count == contextualResetSnapshots.count,
           resetDates.allSatisfy({ $0 == sharedResetAt }) {
            let names = providerNameList(contextualResetSnapshots)
            let prefix = contextualResetSnapshots.count == 1 ? "\(names) · resets" : "\(names) reset"
            return "\(prefix) in \(ResetFormatter.duration(until: sharedResetAt, now: refreshDate))"
        }

        if let soonest = contextualResetSnapshots.min(by: { first, second in
            (first.rateWindow.resetAt ?? .distantFuture) < (second.rateWindow.resetAt ?? .distantFuture)
        }) {
            return "\(soonest.displayName) · resets in \(resetText(for: soonest))"
        }

        return "Fresh window"
    }

    private var neutralClaudeHeader: (headline: String, detail: String)? {
        guard quotaBearingVisibleSnapshots.isEmpty,
              enabledProviders.contains(.claude),
              claudeAccessState.isNeutralAuthenticationCategory else {
            return nil
        }

        let detail: String = switch claudeAccessState {
        case .apiBilling:
            "Claude Code is using API billing"
        case .externalProvider:
            "Claude Code uses an external provider"
        case .unsupportedAuth:
            "Account type not recognized"
        default:
            "Usage unavailable"
        }
        return ("Claude plan usage unavailable", detail)
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

    var headerDetail: String {
        aggregateSeverity == .useSoon ? detail : actionMessage ?? detail
    }

    // MARK: - Selection

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

    private var useSoonHeader: UseSoonHeader? {
        UseSoonHeader.make(alerts: alertingLimits(at: now()), now: now())
    }

    private func alertingLimits(at date: Date) -> [AlertingLimit] {
        quotaBearingVisibleSnapshots.flatMap { snapshot in
            snapshot.windows.enumerated().compactMap { index, window in
                let pair = thresholds(for: window, provider: snapshot.provider)
                guard alertEngine.shouldUseSoon(
                    for: window,
                    in: snapshot,
                    thresholds: pair,
                    now: date
                ), let resetAt = window.rateWindow.resetAt,
                   let remaining = window.rateWindow.remainingPercent else {
                    return nil
                }
                return AlertingLimit(
                    provider: snapshot.provider,
                    kind: window.kind,
                    remainingPercent: Int(remaining.rounded()),
                    resetAt: resetAt,
                    rowOrder: index
                )
            }
        }.sorted { first, second in
            if first.resetAt != second.resetAt { return first.resetAt < second.resetAt }
            if first.remainingPercent != second.remainingPercent {
                return first.remainingPercent > second.remainingPercent
            }
            if first.provider.sortIndex != second.provider.sortIndex {
                return first.provider.sortIndex < second.provider.sortIndex
            }
            return first.rowOrder < second.rowOrder
        }
    }

    func showManualCheck() {
        setActionMessage(nil)
        refreshSnapshotsInBackground(claudeReason: .manual)
    }

    func dismissCurrentWindow() {
        setActionMessage(nil)
        selectedProvider = nil
    }

    func setRemainingMinutesThreshold(_ value: Int, cadence: LimitCadence) {
        var pair = settingsStore.sharedThresholds(for: cadence)
        pair.remainingMinutes = value
        settingsStore.saveThresholds(pair, for: cadence)
        if cadence == .fiveHour { fiveHourThresholds = pair }
        else { weeklyThresholds = pair }
        refreshModeForThresholds()
    }

    func setRemainingPercentThreshold(_ value: Int, cadence: LimitCadence) {
        var pair = settingsStore.sharedThresholds(for: cadence)
        pair.remainingPercent = value
        settingsStore.saveThresholds(pair, for: cadence)
        if cadence == .fiveHour { fiveHourThresholds = pair }
        else { weeklyThresholds = pair }
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
        setActionMessage("Refreshing usage.", autoClears: false)
        refreshSnapshotsInBackground(
            claudeReason: .manual,
            completionMessage: "Usage refreshed."
        )
    }

    func refreshUsageQuietly(reason: ClaudeRefreshReason = .timer) {
        refreshSnapshotsInBackground(claudeReason: reason)
    }

    func setNetworkOnline(_ isOnline: Bool) {
        let wasOnline = isNetworkOnline
        isNetworkOnline = isOnline
        if isOnline, !wasOnline {
            refreshUsageQuietly(reason: .foreground)
        }
    }

    func setUsageSourceMode(_ mode: UsageSourceMode) {
        setUsageSourceMode(mode, persist: true, announce: true)
    }

    func pendingUseSoonNotifications(now noticeDate: Date) -> [UseSoonNotice] {
        guard useSoonNotificationsEnabled else {
            return []
        }

        let notifiedWindowIDs = settingsStore.notifiedUseSoonWindowIDs

        return quotaBearingVisibleSnapshots.flatMap { snapshot in
            snapshot.windows.enumerated().compactMap { index, window -> UseSoonNotice? in
                let pair = thresholds(for: window, provider: snapshot.provider)
                let latchKey = "\(snapshot.provider.rawValue):\(window.kind.identifier)"
                let windowID = window.resetWindowID(provider: snapshot.provider)
                guard alertEngine.shouldUseSoon(
                    for: window,
                    in: snapshot,
                    thresholds: pair,
                    now: noticeDate
                ), notifiedWindowIDs[latchKey] != windowID,
                   let resetAt = window.rateWindow.resetAt,
                   let remaining = window.rateWindow.remainingPercent else {
                    return nil
                }
                return UseSoonNotice(
                    provider: snapshot.provider,
                    providerDisplayName: snapshot.displayName,
                    remainingPercent: Int(remaining.rounded()),
                    resetText: ResetFormatter.duration(until: resetAt, now: noticeDate),
                    resetAt: resetAt,
                    windowID: windowID,
                    kind: window.kind,
                    rowOrder: index
                )
            }
        }.sorted { first, second in
            if first.resetAt != second.resetAt { return first.resetAt < second.resetAt }
            if first.remainingPercent != second.remainingPercent {
                return first.remainingPercent > second.remainingPercent
            }
            if first.provider.sortIndex != second.provider.sortIndex {
                return first.provider.sortIndex < second.provider.sortIndex
            }
            return first.rowOrder < second.rowOrder
        }
    }

    /// The single banner to deliver for the current pending notices — the merge
    /// of every orange provider into one notification.
    func mergedUseSoonNotification(now noticeDate: Date) -> MergedUseSoonNotification? {
        MergedUseSoonNotification(notices: pendingUseSoonNotifications(now: noticeDate), now: noticeDate)
    }

    func markUseSoonNoticeDispatched(_ notice: UseSoonNotice) {
        settingsStore.markUseSoonWindowNotified(
            latchKey: notice.latchKey,
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

        return settingsStore.notifiedUseSoonWindowIDs.compactMap { latchKey, windowID in
            guard let providerRawValue = windowID.split(separator: ":").first,
                  let provider = UsageProvider(rawValue: String(providerRawValue)) else {
                return nil
            }

            guard let storedResetAt = resetDate(fromWindowID: windowID) else {
                return UseSoonNotificationWithdrawal(
                    provider: provider, windowID: windowID, latchKey: latchKey
                )
            }

            if storedResetAt <= withdrawalDate {
                return UseSoonNotificationWithdrawal(
                    provider: provider, windowID: windowID, latchKey: latchKey
                )
            }

            guard let snapshot = snapshotsByProvider[provider],
                  let current = snapshot.windows.first(where: {
                      "\(provider.rawValue):\($0.kind.identifier)" == latchKey
                  }),
                  let currentResetAt = current.rateWindow.resetAt,
                  current.resetWindowID(provider: provider) != windowID,
                  currentResetAt > storedResetAt else {
                return nil
            }

            return UseSoonNotificationWithdrawal(
                provider: provider, windowID: windowID, latchKey: latchKey
            )
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
        settingsStore.clearUseSoonWindowNotification(latchKey: withdrawal.latchKey)
    }

    func tick() {
        refreshExpiredSnapshotsIfNeeded()
        refreshClaudeOnTimerIfNeeded()
        objectWillChange.send()
    }

    private func refreshClaudeOnTimerIfNeeded() {
        let checkDate = now()
        guard activeRefreshID == nil,
              claudeTimerRefreshTask == nil,
              shouldRefreshLiveProvidersIndependently,
              let claudeUsageCoordinator,
              enabledProviders.contains(.claude),
              isNetworkOnline,
              lastClaudeTimerCheckAt.map({
                  checkDate.timeIntervalSince($0) >= claudeTimerCheckInterval
              }) ?? true else {
            return
        }

        lastClaudeTimerCheckAt = checkDate
        claudeTimerRefreshTask = Task { [weak self] in
            let state = await claudeUsageCoordinator.snapshot(
                now: checkDate,
                reason: .timer,
                force: false,
                providerEnabled: true,
                isOnline: true
            )
            guard !Task.isCancelled else {
                return
            }
            self?.applyClaudeCoordinatorState(state)
            self?.claudeTimerRefreshTask = nil
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

        guard let resetAt = snapshot.rateWindow.resetAt else {
            return "n/a"
        }

        return ResetFormatter.duration(until: resetAt, now: now())
    }

    func fullResetText(for snapshot: UsageSnapshot) -> String {
        if snapshot.isFreshSessionWindow {
            return "Fresh window"
        }

        guard let resetAt = snapshot.rateWindow.resetAt else {
            return "resets in n/a"
        }

        return ResetFormatter.text(until: resetAt, now: now())
    }

    func shouldUseSoon(for snapshot: UsageSnapshot) -> Bool {
        alertEngine.shouldUseSoon(
            for: snapshot,
            thresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .fiveHour),
            weeklyThresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .weekly),
            now: now()
        )
    }

    func statusText(for snapshot: UsageSnapshot) -> String {
        if snapshot.isFreshSessionWindow {
            return "Fresh window"
        }

        return alertEngine.statusText(
            for: snapshot,
            thresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .fiveHour),
            weeklyThresholds: settingsStore.thresholds(for: snapshot.provider, cadence: .weekly),
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

        let resetText = weeklyWindow.resetAt.map {
            ResetFormatter.text(until: $0, now: now())
        } ?? "resets in n/a"
        var text = "Week: \(Int(remaining.rounded()))% left · \(resetText)"

        if let weeklyUpdatedAt = snapshot.weeklyUpdatedAt,
           now().timeIntervalSince(weeklyUpdatedAt) > 30 * 60 {
            text += " · as of \(clockTime(weeklyUpdatedAt))"
        }

        return text
    }

    /// Friendly hover text for a row — where the reading came from, stated as a
    /// fact (never a promise). Lives in a tooltip, never inline.
    func sourceTooltip(for snapshot: UsageSnapshot) -> String {
        if snapshot.provider == .claude {
            return claudePresentation.tooltip ?? "Usage unavailable"
        }

        let label: String
        switch snapshot.source {
        case .claudeUsageCLI, .claudeCache:
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

        return "Updated at \(clockTime(snapshot.updatedAt))"
    }

    var shouldShowClaudeMeasurementInfo: Bool {
        true
    }

    var claudeSetupButtonTitle: String? {
        claudePresentation.settingsAction?.title
    }

    var claudeMeasurementPopoverDetail: String {
        claudePresentation.popoverStatus ?? "Usage unavailable."
    }

    func settingsStatusText(for provider: UsageProvider) -> String {
        if provider == .claude {
            return claudePresentation.settingsSubtitle
        }

        guard let snapshot = snapshots.first(where: { $0.provider == provider }) else {
            return provider == .claude ? "Not set up yet" : "Not detected"
        }

        guard snapshot.isAvailable else {
            if snapshot.statusDetail == "Refreshing usage" {
                return "Checking…"
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
        setActionMessage(nil)
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
        refreshSnapshotsInBackground(claudeReason: .manual)

        if announce {
            setActionMessage("\(mode.title) selected.")
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
        if shouldRefreshLiveProvidersIndependently,
           claudeUsageCoordinator != nil,
           enabledProviders.contains(.claude) {
            claudeRefreshState = .refreshing
        }
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
        let networkOnline = isNetworkOnline

        refreshTask = Task.detached(priority: .userInitiated) { [weak self] in
            var claudeScheduleDecision: ClaudeUsageScheduleDecision?
            await withTaskGroup(of: LiveProviderRefreshResult.self) { group in
                if let claudeUsageCoordinator {
                    group.addTask {
                        PromptJuiceLog.usage.debug("Claude usage coordinator refresh started")
                        let state = await claudeUsageCoordinator.snapshot(
                            now: refreshDate,
                            reason: claudeReason,
                            force: false,
                            providerEnabled: claudeProviderEnabled,
                            isOnline: networkOnline
                        )
                        return .claudeCoordinator(state)
                    }
                } else if let claudeProviderClient {
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
                    if case .claudeCoordinator(let state) = result {
                        claudeScheduleDecision = state.scheduleDecision
                    }
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
                let resolvedCompletionMessage = claudeReason == .manual
                    && claudeScheduleDecision == .skipDebounce
                    ? "Just checked · up to date"
                    : completionMessage
                self?.finishLiveProviderRefresh(
                    refreshID: refreshID,
                    completionMessage: resolvedCompletionMessage,
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

        applyClaudeCoordinatorState(coordinatorState, refreshID: refreshID)
    }

    private func applyClaudeCoordinatorState(
        _ coordinatorState: ClaudeUsageCoordinatorState,
        refreshID: UUID? = nil
    ) {
        claudeAccessState = coordinatorState.access
        claudeRefreshState = coordinatorState.refresh
        guard let snapshot = coordinatorState.snapshot else {
            return
        }

        if let refreshID {
            mergeLiveRefreshSnapshot(snapshot, refreshID: refreshID)
        } else {
            _ = mergeSnapshotIfNewer(snapshot)
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
            setActionMessage(completionMessage)
        }

        completion?()
        runPendingRefreshIfNeeded()
    }

    private func setActionMessage(_ message: String?, autoClears: Bool = true) {
        actionMessageClearTask?.cancel()
        actionMessageClearTask = nil
        actionMessage = message

        guard let message, autoClears else {
            return
        }

        let duration = actionMessageDuration
        actionMessageClearTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.actionMessage == message else {
                return
            }
            self?.actionMessage = nil
            self?.actionMessageClearTask = nil
        }
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
        Self.currentOrUnavailableSnapshot(snapshot, now: refreshDate)
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
            windows: existing.windows,
            source: existing.source,
            confidence: existing.confidence,
            updatedAt: existing.updatedAt,
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

                let current = Self.currentOrUnavailableSnapshot(snapshot, now: refreshDate)
                if !current.windows.isEmpty {
                    return current
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
        PromptJuiceLog.usage.notice(
            "Snapshot state updated (\(reason, privacy: .public)): \(states, privacy: .public)"
        )
    }

    private static func makeProviderClient(sourceMode: UsageSourceMode) -> any UsageProviderClient {
        switch sourceMode {
        case .fixture:
            return FixtureUsageProviderClient(scenario: .underusedCodex)
        case .liveCodex:
            return CodexProviderClient()
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
                    source: .claudeUsageCLI,
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

        let activeWindows = snapshot.windows.filter {
            guard let resetAt = $0.rateWindow.resetAt else {
                return false
            }
            return resetAt > now
        }
        if !activeWindows.isEmpty {
            return ProviderSnapshot(
                identity: snapshot.identity,
                windows: activeWindows,
                source: snapshot.source,
                confidence: snapshot.confidence,
                updatedAt: snapshot.updatedAt,
                statusDetail: snapshot.statusDetail,
                isFreshWeeklyWindow: snapshot.isFreshWeeklyWindow
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
