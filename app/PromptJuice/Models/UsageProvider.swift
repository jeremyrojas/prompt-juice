enum UsageProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"

    var id: String {
        rawValue
    }

    var sortIndex: Int {
        switch self {
        case .claude:
            0
        case .codex:
            1
        }
    }
}
