import Foundation

final class CodexSnapshotCache: @unchecked Sendable {
    static let shared = CodexSnapshotCache()

    private enum Key {
        static let lastGoodCodexSnapshot = "lastGoodCodexSnapshot"
    }

    private let storage: ProviderWindowSnapshotCache

    init(defaults: UserDefaults = .standard) {
        storage = ProviderWindowSnapshotCache(
            defaults: defaults,
            key: Key.lastGoodCodexSnapshot,
            identity: .codex,
            cacheSource: .codexCache
        )
    }

    func save(_ snapshot: ProviderSnapshot) {
        guard snapshot.identity == .codex,
              snapshot.source == .codexAppServer,
              snapshot.confidence == .exact else {
            return
        }

        storage.save(snapshot)
    }

    func snapshot(now: Date, failureDetail: String?) -> ProviderSnapshot? {
        storage.snapshot(now: now, failureDetail: failureDetail)
    }
}
