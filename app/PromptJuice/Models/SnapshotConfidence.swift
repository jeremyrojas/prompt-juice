enum SnapshotConfidence: String, Equatable, Sendable {
    case exact
    case estimated
    case stale
    case unavailable

    var canTriggerAlert: Bool {
        self == .exact || self == .estimated
    }
}
