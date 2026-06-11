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
              snapshot.confidence == .exact,
              let usedPercent = snapshot.rateWindow.usedPercent,
              let resetAt = snapshot.rateWindow.resetAt,
              let durationMinutes = snapshot.rateWindow.durationMinutes else {
            return
        }

        let cached = CachedCodexSnapshot(
            usedPercent: usedPercent,
            resetAt: resetAt,
            durationMinutes: durationMinutes,
            updatedAt: snapshot.updatedAt
        )

        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: Key.lastGoodCodexSnapshot)
        }
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        guard let data = defaults.data(forKey: Key.lastGoodCodexSnapshot),
              let cached = try? JSONDecoder().decode(CachedCodexSnapshot.self, from: data),
              cached.resetAt > now else {
            return nil
        }

        return ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: cached.usedPercent,
                resetAt: cached.resetAt,
                durationMinutes: cached.durationMinutes
            ),
            source: .codexCache,
            confidence: .stale,
            updatedAt: cached.updatedAt,
            statusDetail: failureDetail
        )
    }
}

private struct CachedCodexSnapshot: Codable {
    let usedPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let updatedAt: Date
}
