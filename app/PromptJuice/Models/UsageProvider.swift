enum UsageProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case codex = "Codex"

    var id: String {
        rawValue
    }
}

