import Foundation

final class CodexSnapshotCache: @unchecked Sendable {
    static let shared = CodexSnapshotCache()

    private enum Key {
        static let lastGoodCodexSnapshot = "lastGoodCodexSnapshot"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == .codex,
              snapshot.source == .codexAppServer,
              snapshot.confidence == .exact else {
            return
        }

        let existing = cachedSnapshot()

        var sessionWindow = existing?.session
        if !snapshot.isFreshSessionWindow, snapshot.rateWindow.isAvailable {
            sessionWindow = CachedCodexWindow(
                window: snapshot.rateWindow,
                updatedAt: snapshot.updatedAt
            )
        }

        var weeklyWindow = existing?.weekly
        if !snapshot.isFreshWeeklyWindow,
           let weekly = snapshot.weeklyWindow,
           weekly.isAvailable {
            weeklyWindow = CachedCodexWindow(
                window: weekly,
                updatedAt: snapshot.weeklyUpdatedAt ?? snapshot.updatedAt
            )
        }

        guard sessionWindow != nil || weeklyWindow != nil else {
            return
        }

        let cached = CachedCodexSnapshot(
            session: sessionWindow,
            weekly: weeklyWindow
        )

        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: Key.lastGoodCodexSnapshot)
        }
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        guard let cached = cachedSnapshot(),
              cached.session != nil || cached.weekly != nil else {
            return nil
        }

        let validSession = cached.session?.rateWindowIfUnexpired(now: now)
        let validWeekly = cached.weekly?.rateWindowIfUnexpired(now: now)
        let newestUpdatedAt = [
            cached.session?.updatedAt,
            cached.weekly?.updatedAt
        ].compactMap { $0 }.max() ?? now

        guard validSession != nil || validWeekly != nil else {
            return nil
        }

        return ProviderSnapshot(
            identity: .codex,
            rateWindow: validSession ?? .unavailable,
            weeklyWindow: validWeekly,
            source: .codexCache,
            confidence: .stale,
            updatedAt: cached.session?.updatedAt ?? newestUpdatedAt,
            weeklyUpdatedAt: cached.weekly?.updatedAt,
            statusDetail: failureDetail,
            isFreshSessionWindow: validSession == nil,
            isFreshWeeklyWindow: validWeekly == nil && cached.weekly != nil
        )
    }

    private func cachedSnapshot() -> CachedCodexSnapshot? {
        guard let data = defaults.data(forKey: Key.lastGoodCodexSnapshot) else {
            return nil
        }

        if let cached = try? JSONDecoder().decode(CachedCodexSnapshot.self, from: data) {
            return cached
        }

        guard let legacy = try? JSONDecoder().decode(LegacyCachedCodexSnapshot.self, from: data) else {
            return nil
        }

        return CachedCodexSnapshot(
            session: CachedCodexWindow(
                usedPercent: legacy.usedPercent,
                resetAt: legacy.resetAt,
                durationMinutes: legacy.durationMinutes,
                updatedAt: legacy.updatedAt
            ),
            weekly: nil
        )
    }
}

private struct CachedCodexWindow: Codable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date

    init?(window: RateWindow, updatedAt: Date) {
        guard let usedPercent = window.usedPercent,
              let resetAt = window.resetAt,
              let durationMinutes = window.durationMinutes else {
            return nil
        }

        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.durationMinutes = durationMinutes
        self.updatedAt = updatedAt
    }

    init(
        usedPercent: Double,
        resetAt: Date,
        durationMinutes: Int,
        updatedAt: Date
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.durationMinutes = durationMinutes
        self.updatedAt = updatedAt
    }

    func rateWindowIfUnexpired(now: Date) -> RateWindow? {
        guard resetAt > now else {
            return nil
        }

        return .available(
            usedPercent: usedPercent,
            resetAt: resetAt,
            durationMinutes: durationMinutes
        )
    }
}

private struct CachedCodexSnapshot: Codable {
    let session: CachedCodexWindow?
    let weekly: CachedCodexWindow?
}

private struct LegacyCachedCodexSnapshot: Codable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date
}
