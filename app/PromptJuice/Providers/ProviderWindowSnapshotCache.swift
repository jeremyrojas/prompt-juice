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

struct CachedLimitWindow: Codable, Equatable {
    let kind: LimitWindow.Kind
    let window: CachedProviderWindow

    init?(limitWindow: LimitWindow) {
        guard let window = CachedProviderWindow(
            window: limitWindow.rateWindow,
            updatedAt: limitWindow.updatedAt
        ) else {
            return nil
        }
        self.kind = limitWindow.kind
        self.window = window
    }

    init(kind: LimitWindow.Kind, window: CachedProviderWindow) {
        self.kind = kind
        self.window = window
    }

    func limitWindowIfUnexpired(now: Date) -> LimitWindow? {
        guard let rateWindow = window.rateWindowIfUnexpired(now: now) else {
            return nil
        }
        return LimitWindow(kind: kind, rateWindow: rateWindow, updatedAt: window.updatedAt)
    }
}

struct CachedProviderSnapshot: Codable, Equatable {
    let windows: [CachedLimitWindow]

    init(windows: [CachedLimitWindow]) {
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case windows
        case session
        case weekly
        case usedPercent
        case resetAt
        case durationMinutes
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.windows) {
            windows = try container.decode([CachedLimitWindow].self, forKey: .windows)
            return
        }

        if container.contains(.session) || container.contains(.weekly) {
            var restored: [CachedLimitWindow] = []
            if let session = try container.decodeIfPresent(CachedProviderWindow.self, forKey: .session) {
                restored.append(CachedLimitWindow(
                    kind: .codexKind(durationMinutes: session.durationMinutes),
                    window: session
                ))
            }
            if let weekly = try container.decodeIfPresent(CachedProviderWindow.self, forKey: .weekly) {
                restored.append(CachedLimitWindow(kind: .weekly, window: weekly))
            }
            windows = restored
            return
        }

        if container.contains(.usedPercent)
            || container.contains(.resetAt)
            || container.contains(.durationMinutes)
            || container.contains(.updatedAt) {
            let legacy = try LegacyCachedProviderSnapshot(from: decoder)
            let window = CachedProviderWindow(
                usedPercent: legacy.usedPercent,
                resetAt: legacy.resetAt,
                durationMinutes: legacy.durationMinutes,
                updatedAt: legacy.updatedAt
            )
            windows = [CachedLimitWindow(
                kind: .codexKind(durationMinutes: legacy.durationMinutes),
                window: window
            )]
            return
        }

        windows = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windows, forKey: .windows)
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
    let allowsFreshWindowEvidence: Bool

    init(
        defaults: UserDefaults,
        key: String,
        identity: ProviderIdentity,
        cacheSource: SnapshotSource,
        allowsFreshWindowEvidence: Bool = true
    ) {
        self.defaults = defaults
        self.key = key
        self.identity = identity
        self.cacheSource = cacheSource
        self.allowsFreshWindowEvidence = allowsFreshWindowEvidence
    }

    func save(_ snapshot: ProviderSnapshot, replacingWindows: Bool = false) {
        guard snapshot.identity == identity else {
            return
        }

        var byKind: [LimitWindow.Kind: CachedLimitWindow] = [:]
        if !replacingWindows {
            for cached in cachedSnapshot()?.windows ?? [] {
                byKind[cached.kind] = cached
            }
        }
        for limitWindow in snapshot.windows {
            if let cached = CachedLimitWindow(limitWindow: limitWindow) {
                byKind[limitWindow.kind] = cached
            }
        }

        guard !byKind.isEmpty else {
            return
        }

        let windows = byKind.values.sorted { first, second in
            first.kind.identifier < second.kind.identifier
        }
        if let data = try? JSONEncoder().encode(CachedProviderSnapshot(windows: windows)) {
            defaults.set(data, forKey: key)
        }
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        guard let cached = cachedSnapshot(), !cached.windows.isEmpty else {
            return nil
        }

        var validWindows = cached.windows.compactMap { $0.limitWindowIfUnexpired(now: now) }
        guard !validWindows.isEmpty else {
            return nil
        }

        let hadFiveHour = cached.windows.contains { $0.kind == .fiveHour }
        let hasValidFiveHour = validWindows.contains { $0.kind == .fiveHour }
        let freshSession = allowsFreshWindowEvidence
            && identity.provider == .codex
            && hadFiveHour
            && !hasValidFiveHour
        if freshSession, let previous = cached.windows.first(where: { $0.kind == .fiveHour }) {
            validWindows.append(LimitWindow(
                kind: .fiveHour,
                rateWindow: .unavailable,
                updatedAt: previous.window.updatedAt
            ))
        }

        let hadWeekly = cached.windows.contains { $0.kind == .weekly }
        let hasValidWeekly = validWindows.contains { $0.kind == .weekly }
        let newestUpdatedAt = cached.windows.map(\.window.updatedAt).max() ?? now
        let sessionUpdatedAt = cached.windows.first(where: { $0.kind == .fiveHour })?.window.updatedAt

        return ProviderSnapshot(
            identity: identity,
            windows: validWindows,
            source: cacheSource,
            confidence: .stale,
            updatedAt: sessionUpdatedAt ?? newestUpdatedAt,
            statusDetail: failureDetail,
            isFreshSessionWindow: freshSession,
            isFreshWeeklyWindow: allowsFreshWindowEvidence && hadWeekly && !hasValidWeekly
        )
    }

    private func cachedSnapshot() -> CachedProviderSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedProviderSnapshot.self, from: data)
    }
}
