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

        guard let primary = bucket.primary,
              primary.usedPercent.isFinite,
              primary.windowDurationMins > 0,
              primary.resetsAt > 0 else {
            throw CodexRateLimitMappingError.missingPrimaryWindow
        }

        return ProviderSnapshot(
            identity: .codex,
            rateWindow: .available(
                usedPercent: primary.usedPercent,
                resetAt: Date(timeIntervalSince1970: primary.resetsAt),
                durationMinutes: primary.windowDurationMins
            ),
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
}

enum CodexRateLimitMappingError: Error, LocalizedError, Equatable {
    case missingCodexBucket
    case missingPrimaryWindow

    var errorDescription: String? {
        switch self {
        case .missingCodexBucket:
            return "Codex rate-limit bucket unavailable"
        case .missingPrimaryWindow:
            return "Codex primary rate-limit window unavailable"
        }
    }
}
