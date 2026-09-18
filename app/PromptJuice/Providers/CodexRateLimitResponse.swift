import Foundation

struct CodexRateLimitReadResult: Decodable, Equatable {
    let rateLimits: CodexRateLimitBucket?
    let rateLimitsByLimitId: [String: CodexRateLimitBucket]?

    var preferredCodexBucket: CodexRateLimitBucket? {
        rateLimitsByLimitId?["codex"] ?? rateLimits
    }

    func providerSnapshot(now: Date) throws -> ProviderSnapshot {
        guard let bucket = preferredCodexBucket else {
            throw CodexRateLimitMappingError.missingCodexBucket
        }

        let windows = [bucket.primary, bucket.secondary].compactMap { slot -> LimitWindow? in
            guard let slot,
                  let rateWindow = slot.rateWindowIfUnexpired(now: now) else {
                return nil
            }

            let kind = LimitWindow.Kind.codexKind(durationMinutes: slot.windowDurationMins)
            if case .other(let durationMinutes) = kind {
                CodexUnexpectedDurationLog.shared.logOnce(durationMinutes)
            }
            return LimitWindow(kind: kind, rateWindow: rateWindow, updatedAt: now)
        }

        guard !windows.isEmpty else {
            throw CodexRateLimitMappingError.noUsableWindows
        }

        return ProviderSnapshot(
            identity: .codex,
            windows: windows,
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now,
            statusDetail: bucket.rateLimitReachedType
        )
    }
}

struct CodexRateLimitBucket: Decodable, Equatable {
    let limitId: String
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
    let rateLimitReachedType: String?
}

struct CodexRateLimitWindow: Decodable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: TimeInterval

    func rateWindow() -> RateWindow? {
        guard usedPercent.isFinite,
              windowDurationMins > 0,
              resetsAt > 0 else {
            return nil
        }

        return .available(
            usedPercent: usedPercent,
            resetAt: Date(timeIntervalSince1970: resetsAt),
            durationMinutes: windowDurationMins
        )
    }

    func rateWindowIfUnexpired(now: Date) -> RateWindow? {
        guard let window = rateWindow(),
              let resetAt = window.resetAt,
              resetAt > now else {
            return nil
        }

        return window
    }
}

enum CodexRateLimitMappingError: Error, LocalizedError, Equatable {
    case missingCodexBucket
    case noUsableWindows

    var errorDescription: String? {
        switch self {
        case .missingCodexBucket:
            return "Codex rate-limit bucket unavailable"
        case .noUsableWindows:
            return "Codex rate-limit windows unavailable"
        }
    }
}

private final class CodexUnexpectedDurationLog: @unchecked Sendable {
    static let shared = CodexUnexpectedDurationLog()

    private let lock = NSLock()
    private var loggedDurations: Set<Int> = []

    func logOnce(_ durationMinutes: Int) {
        lock.lock()
        let shouldLog = loggedDurations.insert(durationMinutes).inserted
        lock.unlock()

        if shouldLog {
            PromptJuiceLog.usage.notice("Codex reported a \(durationMinutes)-minute rate window")
        }
    }
}
