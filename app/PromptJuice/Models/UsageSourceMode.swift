enum UsageSourceMode: String, CaseIterable, Equatable {
    case fixture
    case liveCodex

    static let defaultMode: UsageSourceMode = .liveCodex
    static let userFacingModes: [UsageSourceMode] = [.liveCodex]

    var title: String {
        switch self {
        case .fixture:
            return "Fixture Usage"
        case .liveCodex:
            return "Live Usage"
        }
    }

    var isUserFacing: Bool {
        Self.userFacingModes.contains(self)
    }
}
