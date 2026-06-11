import Foundation

struct CodexProviderClient: UsageProviderClient {
    let source: SnapshotSource = .codexStub

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [
            ProviderSnapshot(
                identity: .codex,
                rateWindow: .unavailable,
                source: source,
                confidence: .unavailable,
                updatedAt: now
            )
        ]
    }
}
