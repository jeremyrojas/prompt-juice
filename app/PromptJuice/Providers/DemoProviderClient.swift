import Foundation

struct DemoProviderClient: UsageProviderClient {
    let scenario: DemoScenario
    let source: SnapshotSource = .demo

    func snapshots(now: Date = Date()) -> [ProviderSnapshot] {
        switch scenario {
        case .underusedCodex:
            return [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 57,
                        resetAt: now.addingTimeInterval(42 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 31,
                        resetAt: now.addingTimeInterval(52 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                )
            ]
        case .underusedClaude:
            return [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 36,
                        resetAt: now.addingTimeInterval(47 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 72,
                        resetAt: now.addingTimeInterval(86 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                )
            ]
        case .healthy:
            return [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 68,
                        resetAt: now.addingTimeInterval(128 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 61,
                        resetAt: now.addingTimeInterval(116 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                )
            ]
        case .quiet:
            return [
                ProviderSnapshot(
                    identity: .claude,
                    rateWindow: .available(
                        usedPercent: 18,
                        resetAt: now.addingTimeInterval(211 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                ),
                ProviderSnapshot(
                    identity: .codex,
                    rateWindow: .available(
                        usedPercent: 24,
                        resetAt: now.addingTimeInterval(196 * 60),
                        durationMinutes: 300
                    ),
                    source: source,
                    confidence: .exact,
                    updatedAt: now
                )
            ]
        }
    }
}

enum DemoScenario: Int, CaseIterable {
    case underusedCodex
    case underusedClaude
    case healthy
    case quiet

    var next: DemoScenario {
        let allCases = Self.allCases
        let nextIndex = (rawValue + 1) % allCases.count
        return allCases[nextIndex]
    }
}
