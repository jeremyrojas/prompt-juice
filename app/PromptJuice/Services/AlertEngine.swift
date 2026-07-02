import Foundation

struct AlertEngine {
    func shouldUseSoon(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> Bool {
        guard snapshot.confidence.canTriggerAlert,
              !snapshot.isFreshSessionWindow,
              !snapshot.isExpired(at: now),
              let minutesUntilReset = snapshot.rateWindow.minutesUntilReset(now: now),
              snapshot.rateWindow.remainingPercent != nil else {
            return false
        }

        return minutesUntilReset <= thresholds.remainingMinutes
            && snapshot.sessionRemainingPercent >= Double(thresholds.remainingPercent)
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
        ).max(by: { $0.sessionRemainingPercent < $1.sessionRemainingPercent }) {
            return highestRemainingAlert
        }

        return snapshots
            .filter { $0.isAvailable && !$0.isExpired(at: now) }
            .max { $0.sessionRemainingPercent < $1.sessionRemainingPercent }
    }

    /// The single judgment for one provider, used by the chip, row/bar color,
    /// header droplet, and menu-bar glyph. "Nearly out" (red) takes priority
    /// over "use it before reset" (amber).
    func severity(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> UsageSeverity {
        guard snapshot.isAvailable,
              !snapshot.isExpired(at: now) else {
            return .unavailable
        }

        let remaining = snapshot.sessionRemainingPercent

        if snapshot.isFreshSessionWindow {
            return .healthy
        }

        if remaining <= 0 {
            return .empty
        }

        // The amber nudge takes priority; below it, "running low" is a calm state.
        if shouldUseSoon(for: snapshot, thresholds: thresholds, now: now) {
            return .useSoon
        }

        if remaining < Double(UsageSeverity.lowRemainingFloor) {
            return .low
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

        guard snapshot.isAvailable,
              !snapshot.isExpired(at: now) else {
            return "Unavailable"
        }

        if snapshot.sessionRemainingPercent <= 0 {
            return "Empty"
        }

        if snapshot.sessionRemainingPercent >= Double(UsageSeverity.lowRemainingFloor) {
            return "Some left"
        }

        return "Low"
    }
}
