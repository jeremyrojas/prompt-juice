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
              let primaryWindow = primary.rateWindow() else {
            throw CodexRateLimitMappingError.missingPrimaryWindow
        }

        guard let resetAt = primaryWindow.resetAt,
              resetAt > now else {
            throw CodexRateLimitMappingError.expiredPrimaryWindow
        }

        let weeklyWindow = bucket.secondary?.rateWindowIfUnexpired(now: now)

        return ProviderSnapshot(
            identity: .codex,
            rateWindow: primaryWindow,
            weeklyWindow: weeklyWindow,
            source: .codexAppServer,
            confidence: .exact,
            updatedAt: now,
            weeklyUpdatedAt: weeklyWindow == nil ? nil : now,
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
    case missingPrimaryWindow
    case expiredPrimaryWindow

    var errorDescription: String? {
        switch self {
        case .missingCodexBucket:
            return "Codex rate-limit bucket unavailable"
        case .missingPrimaryWindow:
            return "Codex primary rate-limit window unavailable"
        case .expiredPrimaryWindow:
            return "Codex primary rate-limit window expired"
        }
    }
}
