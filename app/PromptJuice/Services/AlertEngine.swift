import Foundation

struct AlertEngine {
    func shouldUseSoon(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> Bool {
        guard snapshot.confidence.canTriggerAlert,
              let minutesUntilReset = snapshot.rateWindow.minutesUntilReset(now: now),
              let remainingPercent = snapshot.rateWindow.remainingPercent else {
            return false
        }

        return minutesUntilReset <= thresholds.remainingMinutes
            && remainingPercent >= Double(thresholds.remainingPercent)
    }

    func alertingSnapshots(
        in snapshots: [ProviderSnapshot],
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> [ProviderSnapshot] {
        snapshots.filter {
            shouldUseSoon(for: $0, thresholds: thresholds, now: now)
        }
    }

    func preferredSnapshot(
        in snapshots: [ProviderSnapshot],
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> ProviderSnapshot? {
        if let highestRemainingAlert = alertingSnapshots(
            in: snapshots,
            thresholds: thresholds,
            now: now
        ).max(by: { $0.remainingPercent < $1.remainingPercent }) {
            return highestRemainingAlert
        }

        return snapshots
            .filter(\.isAvailable)
            .max { $0.remainingPercent < $1.remainingPercent }
    }

    /// The single judgment for one provider, used by the chip, row/bar color,
    /// header droplet, and menu-bar glyph. "Nearly out" (red) takes priority
    /// over "use it before reset" (amber).
    func severity(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> UsageSeverity {
        guard snapshot.isAvailable else {
            return .unavailable
        }

        let remaining = snapshot.remainingPercent

        if remaining <= 0 {
            return .empty
        }

        if remaining < Double(UsageSeverity.lowRemainingFloor) {
            return .low
        }

        if shouldUseSoon(for: snapshot, thresholds: thresholds, now: now) {
            return .useSoon
        }

        return .healthy
    }

    /// Worst-wins judgment across providers, ignoring unavailable ones unless
    /// every provider is unavailable. Drives the panel verdict headline and the
    /// menu-bar glyph tint.
    func aggregateSeverity(
        in snapshots: [ProviderSnapshot],
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> UsageSeverity {
        let available = snapshots
            .map { severity(for: $0, thresholds: thresholds, now: now) }
            .filter { $0 != .unavailable }

        return available.max { $0.rank < $1.rank } ?? .unavailable
    }

    func statusText(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> String {
        if shouldUseSoon(for: snapshot, thresholds: thresholds, now: now) {
            return "Use soon"
        }

        guard snapshot.isAvailable else {
            return "Unavailable"
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
}
