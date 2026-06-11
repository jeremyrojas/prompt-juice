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
    private var scenario: DemoScenario = .underusedCodex

    init(settingsStore: PromptJuiceSettingsStore = .shared) {
        self.settingsStore = settingsStore
        thresholds = settingsStore.thresholds
        snapshots = DemoUsageProvider.snapshots(for: scenario)
    }

    var primarySnapshot: UsageSnapshot? {
        snapshots.min { first, second in
            first.resetAt < second.resetAt
        }
    }

    var headline: String {
        if let selectedSnapshot {
            if shouldUseSoon(for: selectedSnapshot) {
                return "\(selectedSnapshot.provider.rawValue): \(remainingPercentValueText(for: selectedSnapshot)) to use"
            }

            return "\(selectedSnapshot.provider.rawValue) has \(remainingPercentText(for: selectedSnapshot))"
        }

        switch mode {
        case .manual:
            return "Prompt juice check"
        case .alert:
            guard let alertSnapshot else {
                return "Plenty of prompt juice left"
            }

            let alertingSnapshots = snapshots.filter { shouldAlert(for: $0) }

            if alertingSnapshots.count > 1 {
                return "Use prompt juice soon"
            }

            if shouldUseSoon(for: alertSnapshot) {
                return "\(alertSnapshot.provider.rawValue): \(remainingPercentValueText(for: alertSnapshot)) to use"
            }

            return "\(alertSnapshot.provider.rawValue) has \(remainingPercentText(for: alertSnapshot))"
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
            let alertingSnapshots = snapshots.filter { shouldAlert(for: $0) }

            if alertingSnapshots.count > 1 {
                return alertingSnapshots
                    .map { "\($0.provider.rawValue) \(remainingPercentValueText(for: $0)) in \(resetText(for: $0))" }
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
        let alertingSnapshots = snapshots.filter { shouldAlert(for: $0) }

        if let highestRemaining = alertingSnapshots.max(by: { $0.remainingPercent < $1.remainingPercent }) {
            return highestRemaining
        }

        return snapshots.max { $0.remainingPercent < $1.remainingPercent }
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
        scenario = .underusedCodex
        snapshots = DemoUsageProvider.snapshots(for: scenario)

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
        scenario = scenario.next
        snapshots = DemoUsageProvider.snapshots(for: scenario)
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
        "\(Int(snapshot.clampedUsedPercent.rounded()))% used"
    }

    func remainingPercentText(for snapshot: UsageSnapshot) -> String {
        "\(Int(snapshot.remainingPercent.rounded()))% left"
    }

    func remainingPercentValueText(for snapshot: UsageSnapshot) -> String {
        "\(Int(snapshot.remainingPercent.rounded()))%"
    }

    func remainingText(for snapshot: UsageSnapshot) -> String {
        let seconds = max(0, snapshot.resetAt.timeIntervalSinceNow)
        let minutes = max(0, Int(ceil(seconds / 60)))

        if minutes < 60 {
            return "\(minutes)m left"
        }

        let hours = minutes / 60
        let remainder = minutes % 60
        return "\(hours)h \(remainder)m left"
    }

    func resetText(for snapshot: UsageSnapshot) -> String {
        let seconds = max(0, snapshot.resetAt.timeIntervalSinceNow)
        let minutes = max(0, Int(ceil(seconds / 60)))

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
        minutesUntilReset(for: snapshot) <= thresholds.remainingMinutes
            && snapshot.remainingPercent >= Double(thresholds.remainingPercent)
    }

    func statusText(for snapshot: UsageSnapshot) -> String {
        if shouldUseSoon(for: snapshot) {
            return "Use soon"
        }

        if snapshot.remainingPercent <= 0 {
            return "Empty"
        }

        if snapshot.remainingPercent >= 40 {
            return "Lots left"
        }

        if snapshot.remainingPercent >= 15 {
            return "Some left"
        }

        return "Low"
    }

    private func minutesUntilReset(for snapshot: UsageSnapshot) -> Int {
        let seconds = max(0, snapshot.resetAt.timeIntervalSinceNow)
        return Int(ceil(seconds / 60))
    }

    private var hasPendingAlert: Bool {
        snapshots.contains { shouldAlert(for: $0) }
    }

    private var isCurrentWindowSnoozed: Bool {
        settingsStore.snoozedDemoWindowID == currentWindowID
    }

    private var currentWindowID: String {
        let windowParts = snapshots
            .map { snapshot in
                let resetMinute = Int(snapshot.resetAt.timeIntervalSince1970 / 60)
                return "\(snapshot.provider.rawValue):\(resetMinute)"
            }
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

    private func shouldAlert(for snapshot: UsageSnapshot) -> Bool {
        shouldUseSoon(for: snapshot)
    }
}
