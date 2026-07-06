import Foundation

struct CachedProviderWindow: Codable, Equatable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date

    init?(
        window: RateWindow,
        updatedAt: Date
    ) {
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

struct CachedProviderSnapshot: Codable, Equatable {
    let session: CachedProviderWindow?
    let weekly: CachedProviderWindow?

    init(session: CachedProviderWindow?, weekly: CachedProviderWindow?) {
        self.session = session
        self.weekly = weekly
    }

    private enum CodingKeys: String, CodingKey {
        case session
        case weekly
        case usedPercent
        case resetAt
        case durationMinutes
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.session) || container.contains(.weekly) {
            session = try container.decodeIfPresent(CachedProviderWindow.self, forKey: .session)
            weekly = try container.decodeIfPresent(CachedProviderWindow.self, forKey: .weekly)
            return
        }

        if container.contains(.usedPercent)
            || container.contains(.resetAt)
            || container.contains(.durationMinutes)
            || container.contains(.updatedAt) {
            let legacy = try LegacyCachedProviderSnapshot(from: decoder)
            session = CachedProviderWindow(
                usedPercent: legacy.usedPercent,
                resetAt: legacy.resetAt,
                durationMinutes: legacy.durationMinutes,
                updatedAt: legacy.updatedAt
            )
            weekly = nil
            return
        }

        session = nil
        weekly = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(weekly, forKey: .weekly)
    }
}

private struct LegacyCachedProviderSnapshot: Codable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date
}

struct ProviderWindowSnapshotCache {
    let defaults: UserDefaults
    let key: String
    let identity: ProviderIdentity
    let cacheSource: SnapshotSource

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == identity else {
            return
        }

        let existing = cachedSnapshot()

        var sessionWindow = existing?.session
        if !snapshot.isFreshSessionWindow, snapshot.rateWindow.isAvailable {
            sessionWindow = CachedProviderWindow(
                window: snapshot.rateWindow,
                updatedAt: snapshot.updatedAt
            )
        }

        var weeklyWindow = existing?.weekly
        if !snapshot.isFreshWeeklyWindow,
           let weekly = snapshot.weeklyWindow,
           weekly.isAvailable {
            weeklyWindow = CachedProviderWindow(
                window: weekly,
                updatedAt: snapshot.weeklyUpdatedAt ?? snapshot.updatedAt
            )
        }

        guard sessionWindow != nil || weeklyWindow != nil else {
            return
        }

        let cached = CachedProviderSnapshot(
            session: sessionWindow,
            weekly: weeklyWindow
        )

        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: key)
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
            identity: identity,
            rateWindow: validSession ?? .unavailable,
            weeklyWindow: validWeekly,
            source: cacheSource,
            confidence: .stale,
            updatedAt: cached.session?.updatedAt ?? newestUpdatedAt,
            weeklyUpdatedAt: cached.weekly?.updatedAt,
            statusDetail: failureDetail,
            isFreshSessionWindow: validSession == nil,
            isFreshWeeklyWindow: validWeekly == nil && cached.weekly != nil
        )
    }

    private func cachedSnapshot() -> CachedProviderSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(CachedProviderSnapshot.self, from: data)
    }
}
