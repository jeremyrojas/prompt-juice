import Foundation

enum DemoUsageProvider {
    static func snapshots(for scenario: DemoScenario, now: Date = Date()) -> [UsageSnapshot] {
        switch scenario {
        case .underusedCodex:
            return [
                UsageSnapshot(
                    provider: .claude,
                    usedPercent: 57,
                    resetAt: now.addingTimeInterval(42 * 60),
                    windowDurationMinutes: 300
                ),
                UsageSnapshot(
                    provider: .codex,
                    usedPercent: 31,
                    resetAt: now.addingTimeInterval(52 * 60),
                    windowDurationMinutes: 300
                )
            ]
        case .underusedClaude:
            return [
                UsageSnapshot(
                    provider: .claude,
                    usedPercent: 36,
                    resetAt: now.addingTimeInterval(47 * 60),
                    windowDurationMinutes: 300
                ),
                UsageSnapshot(
                    provider: .codex,
                    usedPercent: 72,
                    resetAt: now.addingTimeInterval(86 * 60),
                    windowDurationMinutes: 300
                )
            ]
        case .healthy:
            return [
                UsageSnapshot(
                    provider: .claude,
                    usedPercent: 68,
                    resetAt: now.addingTimeInterval(128 * 60),
                    windowDurationMinutes: 300
                ),
                UsageSnapshot(
                    provider: .codex,
                    usedPercent: 61,
                    resetAt: now.addingTimeInterval(116 * 60),
                    windowDurationMinutes: 300
                )
            ]
        case .quiet:
            return [
                UsageSnapshot(
                    provider: .claude,
                    usedPercent: 18,
                    resetAt: now.addingTimeInterval(211 * 60),
                    windowDurationMinutes: 300
                ),
                UsageSnapshot(
                    provider: .codex,
                    usedPercent: 24,
                    resetAt: now.addingTimeInterval(196 * 60),
                    windowDurationMinutes: 300
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

