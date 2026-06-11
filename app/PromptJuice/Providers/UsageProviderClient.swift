import Foundation

protocol UsageProviderClient: Sendable {
    var source: SnapshotSource { get }

    func snapshots(now: Date) -> [ProviderSnapshot]
}

extension UsageProviderClient {
    func snapshots() -> [ProviderSnapshot] {
        snapshots(now: Date())
    }
}
