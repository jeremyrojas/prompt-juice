import Foundation
import SwiftUI

@MainActor
final class PromptJuiceViewModel: ObservableObject {
    @Published private(set) var snapshots: [UsageSnapshot]
    @Published private(set) var mode: PanelMode = .manual
    @Published private(set) var actionMessage: String?
    @Published private(set) var selectedProvider: UsageProvider?
    @Published private(set) var thresholds: AlertThresholds

    private let settingsStore: PromptJuiceSettingsStore
    private let alertEngine: AlertEngine
    private let now: () -> Date
    private var providerClient: any UsageProviderClient
    private var scenario: DemoScenario = .underusedCodex

    init(
        settingsStore: PromptJuiceSettingsStore = .shared,
        providerClient: (any UsageProviderClient)? = nil,
        alertEngine: AlertEngine = AlertEngine(),
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.providerClient = providerClient ?? DemoProviderClient(scenario: scenario)
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
            if shouldUseSoon(for: selectedSnapshot) {
                return "\(resetText(for: selectedSnapshot)) before reset."
            }

            return "\(percentText(for: selectedSnapshot)) · \(fullResetText(for: selectedSnapshot))"
        }

        switch mode {
        case .manual:
            return "Claude and Codex usage at a glance."
        case .alert:
            let alertingSnapshots = self.alertingSnapshots

            if alertingSnapshots.count > 1 {
                return alertingSnapshots
                    .map { "\($0.displayName) \(remainingPercentValueText(for: $0)) in \(resetText(for: $0))" }
                    .joined(separator: " · ")
            }

            if let alertSnapshot {
                if shouldUseSoon(for: alertSnapshot) {
                    return "\(resetText(for: alertSnapshot)) before reset."
                }

                return "\(percentText(for: alertSnapshot)) · \(fullResetText(for: alertSnapshot))"
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
    }

    @discardableResult
    func checkDemoAlert(force: Bool = false) -> Bool {
        actionMessage = nil
        selectedProvider = nil
        setDemoScenario(.underusedCodex)

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

    func cycleDemoState() {
        setDemoScenario(scenario.next)
        mode = scenario == .quiet ? .manual : .alert
        actionMessage = nil
        selectedProvider = nil
        clearSnoozeForCurrentWindow()
    }

    func snooze() {
        if mode == .alert {
            settingsStore.snoozedDemoWindowID = currentWindowID
        }

        mode = .snoozed
        actionMessage = nil
        selectedProvider = nil
    }

    func dismissCurrentWindow() {
        if mode == .alert {
            settingsStore.snoozedDemoWindowID = currentWindowID
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

    func selectProvider(_ provider: UsageProvider) {
        selectedProvider = selectedProvider == provider ? nil : provider
        actionMessage = nil
    }

    func clearSelection() {
        selectedProvider = nil
        actionMessage = nil
    }

    func recordDemoAction(_ title: String) {
        actionMessage = "\(title) queued for later."
    }

    func tick() {
        objectWillChange.send()
    }

    func percentText(for snapshot: UsageSnapshot) -> String {
        guard snapshot.isAvailable else {
            return "Unavailable"
        }

        return "\(Int(snapshot.clampedUsedPercent.rounded()))% used"
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

    private var hasPendingAlert: Bool {
        !alertingSnapshots.isEmpty
    }

    private var isCurrentWindowSnoozed: Bool {
        settingsStore.snoozedDemoWindowID == currentWindowID
    }

    private var currentWindowID: String {
        let windowParts = snapshots
            .map(\.resetWindowID)
            .joined(separator: "|")

        return "\(scenario.rawValue)-\(windowParts)"
    }

    private func clearSnoozeForCurrentWindow() {
        if isCurrentWindowSnoozed {
            settingsStore.snoozedDemoWindowID = nil
        }
    }

    private func refreshModeForThresholds() {
        actionMessage = "Alerts: \(thresholds.remainingMinutes)m / \(thresholds.remainingPercent)%"

        if mode == .alert && !hasPendingAlert {
            mode = .manual
        }

        objectWillChange.send()
    }

    private func setDemoScenario(_ nextScenario: DemoScenario) {
        scenario = nextScenario
        providerClient = DemoProviderClient(scenario: nextScenario)
        snapshots = providerClient.snapshots(now: now())
    }
}
