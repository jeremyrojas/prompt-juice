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
        snapshots = self.providerClient.snapshots(now: now())
    }

    var primarySnapshot: UsageSnapshot? {
        snapshots
            .filter(\.isAvailable)
            .min { first, second in
                first.resetAt < second.resetAt
            }
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
            return "Prompt juice check"
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
            return sourceMode == .liveCodex
                ? "Live Claude and Codex usage."
                : "Claude and Codex usage at a glance."
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
        refreshSnapshots()
        mode = .manual
        actionMessage = nil
        selectedProvider = nil
        clearSnoozeForCurrentWindow()
    }

    @discardableResult
    func checkUsageAlert(force: Bool = false) -> Bool {
        actionMessage = nil
        selectedProvider = nil
        refreshSnapshots()

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
        refreshSnapshots()
        actionMessage = "\(sourceMode.title) refreshed."

        if mode == .alert && !hasPendingAlert {
            mode = .manual
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
        refreshSnapshots()

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

    private func refreshSnapshots() {
        snapshots = providerClient.snapshots(now: now())
    }

    private static func makeProviderClient(sourceMode: UsageSourceMode) -> any UsageProviderClient {
        switch sourceMode {
        case .fixture:
            return FixtureUsageProviderClient(scenario: .underusedCodex)
        case .liveCodex:
            return ClaudeLiveUsageProviderClient()
        }
    }
}
