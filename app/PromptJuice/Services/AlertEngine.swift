import Foundation

struct AlertEngine {
    func isLockedOut(_ snapshot: ProviderSnapshot, now: Date = Date()) -> Bool {
        snapshot.windows.contains { window in
            window.kind == .weekly
                && window.rateWindow.resetAt.map { $0 > now } == true
                && window.rateWindow.remainingPercent.map { $0 <= 0 } == true
        }
    }

    func shouldUseSoon(
        for window: LimitWindow,
        in snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        now: Date = Date()
    ) -> Bool {
        guard !isLockedOut(snapshot, now: now),
              snapshot.confidence.canTriggerAlert,
              window.rateWindow.isAvailable,
              let resetAt = window.rateWindow.resetAt,
              resetAt > now,
              let minutes = window.rateWindow.minutesUntilReset(now: now),
              let used = window.rateWindow.clampedUsedPercent,
              let remaining = window.rateWindow.remainingPercent else {
            return false
        }
        return used >= 5
            && minutes <= thresholds.remainingMinutes
            && remaining >= Double(thresholds.remainingPercent)
    }
    func shouldUseSoon(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        weeklyThresholds: AlertThresholds = .weeklyDefault,
        now: Date = Date()
    ) -> Bool {
        snapshot.windows.contains { window in
            shouldUseSoon(
                for: window,
                in: snapshot,
                thresholds: window.kind.cadenceIsWeekly ? weeklyThresholds : thresholds,
                now: now
            )
        }
    }

    /// The single judgment for one provider, used by the chip, row/bar color,
    /// header droplet, and menu-bar glyph. Low and empty are calm display states;
    /// use-soon is the one alerting state.
    func severity(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        weeklyThresholds: AlertThresholds = .weeklyDefault,
        now: Date = Date()
    ) -> UsageSeverity {
        guard snapshot.isAvailable,
              !snapshot.isExpired(at: now) else {
            return .unavailable
        }

        if isLockedOut(snapshot, now: now) { return .empty }

        let remaining = snapshot.remainingPercent

        if remaining <= 0 {
            return .empty
        }

        // The orange nudge takes priority; below it, "running low" is a calm state.
        if shouldUseSoon(
            for: snapshot,
            thresholds: thresholds,
            weeklyThresholds: weeklyThresholds,
            now: now
        ) {
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
        thresholdsFor: (UsageProvider, LimitCadence) -> AlertThresholds,
        now: Date = Date()
    ) -> UsageSeverity {
        let available = snapshots
            .map { snapshot in
                severity(
                    for: snapshot,
                    thresholds: thresholdsFor(snapshot.provider, .fiveHour),
                    weeklyThresholds: thresholdsFor(snapshot.provider, .weekly),
                    now: now
                )
            }
            .filter { $0 != .unavailable }

        return available.max { $0.rank < $1.rank } ?? .unavailable
    }

    func statusText(
        for snapshot: ProviderSnapshot,
        thresholds: AlertThresholds,
        weeklyThresholds: AlertThresholds = .weeklyDefault,
        now: Date = Date()
    ) -> String {
        if shouldUseSoon(for: snapshot, thresholds: thresholds, weeklyThresholds: weeklyThresholds, now: now) {
            return "Use soon"
        }

        guard snapshot.isAvailable,
              !snapshot.isExpired(at: now) else {
            return "Unavailable"
        }

        let remaining = snapshot.remainingPercent

        if remaining <= 0 {
            return "Empty"
        }

        if remaining >= Double(UsageSeverity.lowRemainingFloor) {
            return "Some left"
        }

        return "Low"
    }
}
