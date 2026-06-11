enum UsageSourceMode: String, CaseIterable, Equatable {
    case demo
    case liveCodex

    static let defaultMode: UsageSourceMode = .liveCodex

    var title: String {
        switch self {
        case .demo:
            return "Demo Usage"
        case .liveCodex:
            return "Live Codex"
        }
    }
}
