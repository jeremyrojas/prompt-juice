import Foundation

struct CodexProviderClient: UsageProviderClient {
    let source: SnapshotSource = .codexAppServer

    private let rateLimitReader: any CodexRateLimitReading
    private let cache: CodexSnapshotCache?

    init(
        rateLimitReader: any CodexRateLimitReading = CodexAppServerClient(),
        cache: CodexSnapshotCache? = .shared
    ) {
        self.rateLimitReader = rateLimitReader
        self.cache = cache
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        [snapshot(now: now)]
    }

    private func snapshot(now: Date) -> ProviderSnapshot {
        do {
            let snapshot = try rateLimitReader
                .readRateLimits()
                .providerSnapshot(now: now)
            cache?.save(snapshot)
            return snapshot
        } catch {
            let detail = error.localizedDescription

            if let cachedSnapshot = cache?.snapshot(now: now, failureDetail: detail) {
                return cachedSnapshot
            }

            return unavailableSnapshot(now: now, detail: detail)
        }
    }

    private func unavailableSnapshot(now: Date, detail: String) -> ProviderSnapshot {
        ProviderSnapshot(
            identity: .codex,
            rateWindow: .unavailable,
            source: source,
            confidence: .unavailable,
            updatedAt: now,
            statusDetail: detail
        )
    }
}

struct CodexLiveUsageProviderClient: UsageProviderClient {
    let source: SnapshotSource = .codexAppServer

    private let scenario: DemoScenario
    private let codexProviderClient: CodexProviderClient

    init(
        scenario: DemoScenario,
        codexProviderClient: CodexProviderClient = CodexProviderClient()
    ) {
        self.scenario = scenario
        self.codexProviderClient = codexProviderClient
    }

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        let codexSnapshot = codexProviderClient.snapshots(now: now).first

        return DemoProviderClient(scenario: scenario)
            .snapshots(now: now)
            .map { snapshot in
                guard snapshot.identity == .codex,
                      let codexSnapshot else {
                    return snapshot
                }

                return codexSnapshot
            }
    }
}

struct CodexStubProviderClient: UsageProviderClient {
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
