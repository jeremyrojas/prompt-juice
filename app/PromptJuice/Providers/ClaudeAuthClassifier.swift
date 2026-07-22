import Foundation

enum ClaudeExternalProvider: String, Codable, Sendable, Equatable, Hashable {
    case bedrock
    case vertex
    case foundry
    case gateway
}

enum ClaudeSignInReason: String, Codable, Sendable, Equatable {
    case initial
    case reauthenticationRequired
}

enum ClaudeAuthentication: Sendable, Equatable {
    case subscription(plan: String?)
    case apiBilling
    case externalProvider(ClaudeExternalProvider)
    case signedOut(reason: ClaudeSignInReason)
    case unsupported
    case checkFailed

    var permitsUsageProbe: Bool {
        if case .subscription = self {
            return true
        }
        return false
    }
}

struct ClaudeBillingEvidence: Sendable, Equatable {
    fileprivate var routes: Set<Route> = []
    fileprivate var hasSubscriptionToken = false
    fileprivate var isAmbiguous = false

    fileprivate enum Route: Sendable, Hashable {
        case apiBilling
        case external(ClaudeExternalProvider)
        case unsupported
    }

    static let none = ClaudeBillingEvidence()
}

struct ClaudeBillingEvidenceScanner {
    private static let maximumSettingsBytes = 1 * 1_024 * 1_024

    static func scan(
        environment: [String: String],
        settingsDocuments: [Data] = [],
        settingsReadFailed: Bool = false
    ) -> ClaudeBillingEvidence {
        var evidence = ClaudeBillingEvidence()
        inspect(environment: environment, evidence: &evidence)

        for document in settingsDocuments {
            inspect(settingsData: document, evidence: &evidence)
        }

        if settingsReadFailed {
            evidence.isAmbiguous = true
        }
        return evidence
    }

    private static func inspect(
        environment: [String: String],
        evidence: inout ClaudeBillingEvidence
    ) {
        if hasValue(environment["ANTHROPIC_API_KEY"]) {
            evidence.routes.insert(.apiBilling)
        }

        if hasValue(environment["CLAUDE_CODE_OAUTH_TOKEN"])
            || hasValue(environment["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"]) {
            evidence.hasSubscriptionToken = true
        }

        let hasGatewayBaseURL = hasNonFirstPartyBaseURL(environment["ANTHROPIC_BASE_URL"])
        if hasGatewayBaseURL {
            evidence.routes.insert(.external(.gateway))
        }

        if hasValue(environment["ANTHROPIC_AUTH_TOKEN"]) {
            evidence.routes.insert(hasGatewayBaseURL ? .external(.gateway) : .apiBilling)
        }

        inspectFlag(
            environment["CLAUDE_CODE_USE_BEDROCK"],
            route: .external(.bedrock),
            evidence: &evidence
        )
        inspectFlag(
            environment["CLAUDE_CODE_USE_MANTLE"],
            route: .external(.bedrock),
            evidence: &evidence
        )
        inspectFlag(
            environment["CLAUDE_CODE_USE_VERTEX"],
            route: .external(.vertex),
            evidence: &evidence
        )
        inspectFlag(
            environment["CLAUDE_CODE_USE_FOUNDRY"],
            route: .external(.foundry),
            evidence: &evidence
        )
        inspectFlag(
            environment["CLAUDE_CODE_USE_ANTHROPIC_AWS"],
            route: .unsupported,
            evidence: &evidence
        )
        if ["ANTHROPIC_AWS_BASE_URL", "ANTHROPIC_AWS_WORKSPACE_ID"].contains(where: {
            hasValue(environment[$0])
        }) {
            evidence.routes.insert(.unsupported)
        }

        let providerKeys: [(ClaudeExternalProvider, [String])] = [
            (.bedrock, [
                "ANTHROPIC_BEDROCK_BASE_URL",
                "ANTHROPIC_BEDROCK_MANTLE_BASE_URL"
            ]),
            (.vertex, [
                "ANTHROPIC_VERTEX_BASE_URL",
                "ANTHROPIC_VERTEX_PROJECT_ID"
            ]),
            (.foundry, [
                "ANTHROPIC_FOUNDRY_API_KEY",
                "ANTHROPIC_FOUNDRY_BASE_URL",
                "ANTHROPIC_FOUNDRY_RESOURCE"
            ])
        ]
        for (provider, keys) in providerKeys where keys.contains(where: { hasValue(environment[$0]) }) {
            evidence.routes.insert(.external(provider))
        }

        if hasValue(environment["ANTHROPIC_CUSTOM_HEADERS"]), evidence.routes.isEmpty {
            evidence.routes.insert(hasGatewayBaseURL ? .external(.gateway) : .unsupported)
        }

        if [
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
            "http_proxy", "https_proxy", "all_proxy",
        ].contains(where: {
            hasValue(environment[$0])
        }) {
            evidence.isAmbiguous = true
        }
    }

    private static func inspect(settingsData: Data, evidence: inout ClaudeBillingEvidence) {
        guard settingsData.count <= maximumSettingsBytes,
              let object = try? JSONSerialization.jsonObject(with: settingsData),
              let dictionary = object as? [String: Any] else {
            evidence.isAmbiguous = true
            return
        }
        inspect(settings: dictionary, evidence: &evidence)
    }

    private static func inspect(
        settings: [String: Any],
        evidence: inout ClaudeBillingEvidence
    ) {
        if let helper = settings["apiKeyHelper"] {
            if let helper = helper as? String, hasValue(helper) {
                evidence.routes.insert(.apiBilling)
            } else if !(helper is NSNull) {
                evidence.isAmbiguous = true
            }
        }

        if settings["policyHelper"] != nil {
            evidence.routes.insert(.unsupported)
        }

        if let environment = settings["env"] {
            guard let dictionary = environment as? [String: Any] else {
                evidence.isAmbiguous = true
                return
            }

            var stringEnvironment: [String: String] = [:]
            for (key, value) in dictionary {
                guard let string = value as? String else {
                    evidence.isAmbiguous = true
                    continue
                }
                stringEnvironment[key] = string
            }
            inspect(environment: stringEnvironment, evidence: &evidence)
        }

        if settings["awsAuthRefresh"] != nil {
            evidence.routes.insert(.external(.bedrock))
        }
        if settings["gcpAuthRefresh"] != nil {
            evidence.routes.insert(.external(.vertex))
        }

        if let managedSettings = settings["managedSettings"] {
            guard let dictionary = managedSettings as? [String: Any] else {
                evidence.isAmbiguous = true
                return
            }
            inspect(settings: dictionary, evidence: &evidence)
        }
    }

    private static func inspectFlag(
        _ value: String?,
        route: ClaudeBillingEvidence.Route,
        evidence: inout ClaudeBillingEvidence
    ) {
        guard let value, hasValue(value) else {
            return
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            evidence.routes.insert(route)
        case "0", "false", "no", "off":
            break
        default:
            evidence.isAmbiguous = true
        }
    }

    private static func hasNonFirstPartyBaseURL(_ value: String?) -> Bool {
        guard let value, hasValue(value),
              let host = URL(string: value)?.host?.lowercased() else {
            return value.map(hasValue) ?? false
        }

        return !["api.anthropic.com", "claude.ai", "platform.claude.com"].contains(host)
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ClaudeAuthClassifier {
    private static let knownSubscriptionTypes: Set<String> = [
        "pro", "max", "team", "enterprise"
    ]
    private static let reauthenticationErrors: Set<String> = [
        "oauth_expired", "oauth_revoked", "missing_scope", "missing_scopes",
        "token_expired", "token_revoked"
    ]

    static func classify(
        authStatusData: Data,
        evidence: ClaudeBillingEvidence = .none
    ) -> ClaudeAuthentication {
        guard authStatusData.count <= 64 * 1_024 else {
            return .checkFailed
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: authStatusData)
        } catch {
            return .checkFailed
        }

        guard let status = object as? [String: Any],
              let loggedIn = status["loggedIn"] as? Bool,
              let authMethod = status["authMethod"] as? String,
              let apiProvider = status["apiProvider"] as? String,
              status.keys.contains("subscriptionType") else {
            return .unsupported
        }

        let subscriptionType: String?
        if status["subscriptionType"] is NSNull {
            subscriptionType = nil
        } else if let value = status["subscriptionType"] as? String {
            subscriptionType = value.lowercased()
        } else {
            return .unsupported
        }

        let normalizedMethod = authMethod.lowercased()
        let normalizedProvider = apiProvider.lowercased()
        let normalizedError = (status["error"] as? String)?.lowercased()

        guard knownAuthMethod(normalizedMethod),
              knownAPIProvider(normalizedProvider),
              subscriptionType.map(knownSubscriptionTypes.contains) ?? true else {
            return .unsupported
        }

        if !loggedIn {
            return classifySignedOut(
                authMethod: normalizedMethod,
                apiProvider: normalizedProvider,
                subscriptionType: subscriptionType,
                error: normalizedError,
                evidence: evidence
            )
        }

        let statusClassification: ClaudeAuthentication
        switch (normalizedMethod, normalizedProvider, subscriptionType) {
        case ("claude.ai", "firstparty", .some(let plan)):
            statusClassification = .subscription(plan: plan)
        case ("apikey", "firstparty", nil):
            statusClassification = .apiBilling
        case ("external", let provider, nil):
            guard let externalProvider = ClaudeExternalProvider(rawValue: provider) else {
                return .unsupported
            }
            statusClassification = .externalProvider(externalProvider)
        default:
            return .unsupported
        }

        return apply(evidence: evidence, to: statusClassification)
    }

    private static func classifySignedOut(
        authMethod: String,
        apiProvider: String,
        subscriptionType: String?,
        error: String?,
        evidence: ClaudeBillingEvidence
    ) -> ClaudeAuthentication {
        if evidence.isAmbiguous || evidence.routes.count > 1 {
            return .unsupported
        }

        if let route = evidence.routes.first {
            switch route {
            case .apiBilling, .external, .unsupported:
                return .unsupported
            }
        }

        if authMethod == "none", apiProvider == "none", subscriptionType == nil {
            return evidence.hasSubscriptionToken
                ? .signedOut(reason: .reauthenticationRequired)
                : .signedOut(reason: .initial)
        }

        if authMethod == "claude.ai", apiProvider == "firstparty",
           subscriptionType != nil || error.map(reauthenticationErrors.contains) == true {
            return .signedOut(reason: .reauthenticationRequired)
        }

        return .unsupported
    }

    private static func apply(
        evidence: ClaudeBillingEvidence,
        to statusClassification: ClaudeAuthentication
    ) -> ClaudeAuthentication {
        guard !evidence.isAmbiguous,
              !evidence.routes.contains(.unsupported),
              evidence.routes.count <= 1 else {
            return .unsupported
        }

        guard let route = evidence.routes.first else {
            return statusClassification
        }

        switch route {
        case .apiBilling:
            if case .externalProvider = statusClassification {
                return .unsupported
            }
            return .apiBilling
        case .external(let provider):
            if case .apiBilling = statusClassification {
                return .unsupported
            }
            return .externalProvider(provider)
        case .unsupported:
            return .unsupported
        }
    }

    private static func knownAuthMethod(_ value: String) -> Bool {
        ["claude.ai", "apikey", "external", "none"].contains(value)
    }

    private static func knownAPIProvider(_ value: String) -> Bool {
        ["firstparty", "bedrock", "vertex", "foundry", "gateway", "none"].contains(value)
    }
}
