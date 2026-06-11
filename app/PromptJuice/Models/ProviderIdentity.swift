struct ProviderIdentity: Identifiable, Equatable, Hashable {
    let provider: UsageProvider
    let displayName: String

    var id: UsageProvider {
        provider
    }

    static let claude = ProviderIdentity(
        provider: .claude,
        displayName: UsageProvider.claude.rawValue
    )

    static let codex = ProviderIdentity(
        provider: .codex,
        displayName: UsageProvider.codex.rawValue
    )
}
