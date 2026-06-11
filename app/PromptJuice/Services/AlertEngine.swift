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
